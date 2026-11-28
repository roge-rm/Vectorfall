class_name TrainingDrill
extends Node

enum Kind { AIR, FLAG, REPAIR, LANDING }

const MENU_SCENE := "res://scenes/menu.tscn"
const FLAG_SPEED := 18.0
const ESCAPE_SECONDS := 4.0
const AIR_SECONDS := 30.0
const REPAIR_SECONDS := 32.0
const MOTION := PlayerCommand.JUMP | PlayerCommand.SKI | PlayerCommand.JET

static var selected := Kind.AIR
static var returning := false

var kind: Kind
var map: DrillMap
var game: Match
var player: Soldier
var target: Soldier
var generator: BaseAsset
var turret: BaseAsset
var input: DrillInput
var touch: DrillTouch
var camera: FirstPersonCamera
var pause_menu: PauseMenu
var finished := false
var passed := false
var grab_speed := 0.0
var _started := 0
var _grabbed := -1
var _flight: AirTarget
var _hint: Label
var _readout: Label
var _crosshair: Label
var _result: Control
var _result_band: MenuKit.Band
var _result_words: Label
var _repair_link: MeshInstance3D


class DrillInput:
	extends LocalInput
	var allowed := MOTION

	func make_command(delta: float) -> PlayerCommand:
		var command := super(delta)
		command.buttons &= allowed
		return command


class DrillTouch:
	extends TouchControls
	var allowed := MOTION

	func button_shown(index: int) -> bool:
		return BUTTONS[index][1] & allowed != 0 and super(index)


class AirTarget:
	extends CommandSource
	var soldier: Soldier
	var started := 0

	static func course(seconds: float) -> Vector3:
		var phase := seconds * 0.86
		return Vector3(19.0 * sin(phase), 11.5 + 2.5 * cos(phase), DrillMap.TARGET_Z)

	func make_command(delta: float) -> PlayerCommand:
		# Steer a real collision body around a repeatable airborne course.
		var seconds: float = (soldier.game.tick - started) * delta
		var next := course(seconds)
		soldier.velocity = (next - soldier.global_position) / delta
		soldier.velocity.y += soldier.tuning.gravity * delta
		var ahead := course(seconds + delta) - next
		var command := PlayerCommand.new()
		command.yaw = atan2(-ahead.x, -ahead.z)
		return command


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().paused = false
	Settings.load_file()
	kind = selected
	var args := OS.get_cmdline_user_args()
	var choice := args.find("--drill")
	if choice >= 0 and choice + 1 < args.size():
		var value := ["air", "flag", "repair", "landing"].find(args[choice + 1])
		if value >= 0:
			kind = value as Kind

	map = DrillMap.new(kind == Kind.FLAG, kind == Kind.REPAIR, kind == Kind.LANDING)
	add_child(map)
	game = Match.new()
	game.terrain = map.terrain
	game.spawns[0] = [map.start]
	add_child(game)

	var allowed := MOTION
	var armed := kind in [Kind.AIR, Kind.REPAIR]
	if armed:
		allowed |= PlayerCommand.FIRE
	if kind == Kind.REPAIR:
		allowed |= PlayerCommand.USE
	input = DrillInput.new()
	input.allowed = allowed
	add_child(input)
	var armour := Loadout.Armour.MEDIUM
	var pack := Loadout.NO_PACK
	if kind == Kind.FLAG:
		armour = Loadout.Armour.LIGHT
		pack = Pack.ENERGY
	elif kind == Kind.REPAIR:
		armour = Loadout.Armour.HEAVY
		pack = Pack.REPAIR
	player = game.add_soldier(0, map.start, input.source, Loadout.make(armour, [Weapon.DISC], pack))
	player.set_first_person(true)
	input.soldier = player
	_add_objective()
	game.prepare_terrain()

	camera = FirstPersonCamera.new()
	camera.soldier = player
	camera.view_model.set_team_colour(Palette.team(0))
	if not armed:
		camera.view_model.process_mode = Node.PROCESS_MODE_DISABLED
		camera.view_model.hide()
	add_child(camera)
	camera.make_current()
	if kind == Kind.REPAIR:
		_repair_link = MeshInstance3D.new()
		_repair_link.mesh = Cel.box(Vector3.ONE)
		_repair_link.material_override = Cel.glow(Palette.team(0))
		_repair_link.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_repair_link.hide()
		add_child(_repair_link)
	var shots := ProjectileView.new()
	shots.game = game
	add_child(shots)
	var effects := Effects.new()
	add_child(effects)
	effects.watch(game)
	var audio := GameAudio.new()
	add_child(audio)
	audio.watch(game, player, map)

	var layer := CanvasLayer.new()
	add_child(layer)
	_build_hud(layer)
	touch = DrillTouch.new()
	touch.allowed = allowed
	touch.soldier = player
	layer.add_child(touch)
	input.touch = touch
	touch.pause_pressed.connect(_pause)
	input.pause_requested.connect(_pause)
	input.device_changed.connect(_device_changed)

	var top := CanvasLayer.new()
	top.layer = 2
	add_child(top)
	pause_menu = PauseMenu.new("Restart drill", "Back to drills")
	top.add_child(pause_menu)
	pause_menu.resumed.connect(_resume)
	pause_menu.restart_pressed.connect(reset_run)
	pause_menu.quit_pressed.connect(_quit)
	pause_menu.settings.changed.connect(_apply_settings)
	_apply_settings()
	reset_run()


func _add_objective() -> void:
	match kind:
		Kind.AIR:
			var spawn := Transform3D(Basis.IDENTITY, AirTarget.course(0.0))
			_flight = AirTarget.new()
			game.spawns[1] = [spawn]
			target = game.add_soldier(1, spawn, _flight, Loadout.make(Loadout.Armour.HEAVY, [Weapon.DISC]))
			_flight.soldier = target
			game.air_hit.connect(_air_hit)
		Kind.FLAG:
			_add_flag(1, DrillMap.FLAG_X)
			_add_flag(0, DrillMap.EXIT_X)
			game.flag_taken.connect(_flag_taken)
			game.flag_captured.connect(_flag_captured)
		Kind.REPAIR:
			generator = game.add_asset(0, BaseAsset.Kind.GENERATOR, DrillMap.GENERATOR)
			turret = game.add_asset(1, BaseAsset.Kind.TURRET, DrillMap.ATTACKER, PI * 0.5)
			game.asset_repaired.connect(_asset_repaired)
		Kind.LANDING:
			game.landed.connect(_landed)


func _add_flag(team: int, x: float) -> void:
	var stand := Vector3(x, map.terrain.height_at(x, 0.0), 0.0)
	game.add_flag(team, stand, stand + Vector3.UP * (Flag.POLE * 0.5))


func _build_hud(layer: CanvasLayer) -> void:
	var hud := Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.theme = MenuKit.theme()
	layer.add_child(hud)

	var readout := VBoxContainer.new()
	readout.set_anchors_preset(Control.PRESET_CENTER_TOP)
	readout.grow_horizontal = Control.GROW_DIRECTION_BOTH
	readout.position.y = MenuKit.px(9.0)
	readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(readout)
	_hint = _hud_label("", 22)
	readout.add_child(_hint)
	_readout = _hud_label("", 15)
	readout.add_child(_readout)
	_crosshair = _hud_label("+", 16)
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH
	hud.add_child(_crosshair)

	_result = Control.new()
	_result.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_result)
	var card := MenuKit.card(_result, "Drill complete", 340.0)
	_result_band = card.get_parent().get_parent().get_child(0) as MenuKit.Band
	_result_words = MenuKit.ink_label("", 17)
	_result_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_result_words)
	card.add_child(MenuKit.button("Try again", reset_run, 22, false, true))
	card.add_child(MenuKit.button("Back to drills", _quit, 22, true))


static func _hud_label(words: String, font_size: int) -> Label:
	var label := MenuKit.heading(words, font_size)
	label.add_theme_color_override("font_color", InkUi.CREAM)
	label.add_theme_color_override("font_outline_color", InkUi.INK)
	label.add_theme_constant_override("outline_size", MenuKit.pxi(4))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _physics_process(_delta: float) -> void:
	if finished:
		return
	if player.dead:
		_finish(false, "You were taken out.")
		return
	if absf(player.position.x) > 88.0 or absf(player.position.z) > 88.0 or player.position.y < -6.0:
		_finish(false, "Stay inside the training area.")
		return
	match kind:
		Kind.AIR:
			if _seconds(_started) >= AIR_SECONDS:
				_finish(false, "Aim ahead of the target as it crosses the range.")
		Kind.FLAG:
			if player.position.x > DrillMap.FLAG_X + 4.0 and _grabbed < 0:
				_finish(false, "Pass through the flag instead of going around it.")
			elif _grabbed >= 0 and _seconds(_grabbed) > ESCAPE_SECONDS:
				_finish(false, "Keep your speed through the exit gate.")
		Kind.REPAIR:
			if _seconds(_started) >= REPAIR_SECONDS:
				_finish(false, "Get behind the wall and finish the repair.")


func _process(_delta: float) -> void:
	if finished:
		return
	match kind:
		Kind.AIR:
			_readout.text = "%d s  ·  %d discs" % [_left(AIR_SECONDS, _started), player.ammo_for(0)]
		Kind.FLAG:
			var speed := "%d / %d m/s" % [roundi(player.horizontal_speed()), roundi(FLAG_SPEED)]
			if _grabbed >= 0:
				speed = "%d m/s  ·  %d s to exit" % [roundi(player.horizontal_speed()), _left(ESCAPE_SECONDS, _grabbed)]
			_readout.text = speed
		Kind.REPAIR:
			var power := floori(generator.health * 100.0 / generator.max_health())
			var health := ceili(player.health * 100.0 / player.tuning.health_max)
			_readout.text = "Generator %d%%  ·  Health %d%%  ·  %d s" % [power, health, _left(REPAIR_SECONDS, _started)]
			_show_repair_link()
		Kind.LANDING:
			var energy := ceili(player.energy * 100.0 / player.tuning.energy_max)
			var descent := maxf(-player.velocity.y, 0.0) if not player.grounded else 0.0
			_readout.text = "Jet %d%%  ·  Down %.0f m/s" % [energy, descent]
			_update_hint()


func _show_repair_link() -> void:
	_repair_link.visible = player.repair_target == generator.entity_id
	if not _repair_link.visible:
		return
	var aim := player.eye_transform()
	var start := aim * Soldier.MUZZLE
	var end := generator.centre()
	var ray := end - start
	var up := Vector3.FORWARD if absf(ray.normalized().y) > 0.99 else Vector3.UP
	if ray.length_squared() > 0.0001:
		_repair_link.look_at_from_position((start + end) * 0.5, end, up)
		_repair_link.scale = Vector3(0.06, 0.06, ray.length())


func _update_hint() -> void:
	match kind:
		Kind.AIR:
			_hint.text = "Aim ahead of the flying target"
		Kind.FLAG:
			_hint.text = "Ski downhill and grab the flag at speed" if _grabbed < 0 else "Carry the flag through your gate"
		Kind.REPAIR:
			var control := "E"
			match input.device:
				LocalInput.Device.TOUCH:
					control = "PACK"
				LocalInput.Device.GAMEPAD:
					control = "X"
			_hint.text = "Use cover, face the generator and hold %s" % control
		Kind.LANDING:
			if player.position.x < DrillMap.LANDING_LIP:
				_hint.text = "Ski off the ridge and save your jet energy"
			else:
				_hint.text = "Jet before touching down inside the lit lane"


func _air_hit(attacker: int, victim: int) -> void:
	if attacker == player.entity_id and victim == target.entity_id:
		_finish(true, "Direct hit in the air.")


func _flag_taken(team: int, by: int) -> void:
	if team != 1 or by != player.entity_id:
		return
	grab_speed = player.horizontal_speed()
	_grabbed = game.tick
	if grab_speed < FLAG_SPEED:
		_finish(false, "Flag grabbed at %d m/s. Aim for %d m/s." % [roundi(grab_speed), roundi(FLAG_SPEED)])
	else:
		_update_hint()


func _flag_captured(team: int, by: int) -> void:
	if team == 0 and by == player.entity_id and _grabbed >= 0:
		var seconds := _seconds(_grabbed)
		_finish(seconds <= ESCAPE_SECONDS, "Grab at %d m/s. Exit in %.1f s." % [roundi(grab_speed), seconds])


func _asset_repaired(id: int, by: int) -> void:
	if id == generator.entity_id and by == player.entity_id:
		_finish(true, "Generator online in %.1f s." % _seconds(_started))


func _landed(by: int, speed: float) -> void:
	if by != player.entity_id or player.position.x <= DrillMap.LANDING_LIP:
		return
	var words := "Landing speed %.1f m/s." % speed
	var x := player.position.x
	if x < DrillMap.LANDING_START or x > DrillMap.LANDING_END or absf(player.position.z) > DrillMap.LANE_HALF_WIDTH:
		_finish(false, words + " Land inside the lit lane.")
	elif speed > Soldier.FALL_SAFE_SPEED:
		_finish(false, words + " Aim for %.0f m/s or less." % Soldier.FALL_SAFE_SPEED)
	else:
		_finish(true, words)


func _seconds(since: int) -> float:
	return float(game.tick - since) / Engine.physics_ticks_per_second


func _left(limit: float, since: int) -> int:
	return maxi(0, ceili(limit - _seconds(since)))


func reset_run() -> void:
	_started = game.tick
	_grabbed = -1
	grab_speed = 0.0
	finished = false
	passed = false
	game.projectiles.clear()
	game.rng.seed = game.seed_value
	game.over = false
	game.scores.fill(0)
	game.start_clock()
	game.respawn(player)
	for flag: Flag in game.flags.values():
		flag.send_home()
	if target != null:
		game.respawn(target)
		_flight.started = game.tick
	if generator != null:
		generator.health = 0.0
		generator.destroyed = true
		# Start with a partial repair so one drill takes a few seconds under cover.
		game.repair_asset(generator, generator.max_health() * 0.6, 0)
		turret.health = turret.max_health()
		turret.destroyed = false
		turret.target_id = 0
		turret.cooldown = 0.0
		turret.turn_towards(turret.facing, 0.0, TAU)
	game.prepare_terrain()
	game.running = true
	_result.hide()
	_hint.show()
	_readout.show()
	_crosshair.visible = kind in [Kind.AIR, Kind.REPAIR]
	input.held_off = false
	touch.blocked = false
	touch.release_all()
	_device_changed(input.device)
	if pause_menu.visible:
		pause_menu.resume()
	_capture_mouse()


func _finish(success: bool, words: String) -> void:
	if finished:
		return
	finished = true
	passed = success
	game.running = false
	player.skiing = false
	player.jetting = false
	player.repair_target = 0
	if _repair_link != null:
		_repair_link.hide()
	input.held_off = true
	touch.blocked = true
	touch.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hint.hide()
	_readout.hide()
	_crosshair.hide()
	_result_band.title = "DRILL COMPLETE" if success else "TRY AGAIN"
	_result_band.queue_redraw()
	_result_words.text = words
	_result.show()
	MenuKit.focus_first(_result)


func _device_changed(device: LocalInput.Device) -> void:
	touch.visible = device == LocalInput.Device.TOUCH and not finished
	_update_hint()


func _apply_settings() -> void:
	map.set_view_distance(Settings.view_distance)
	camera.far = Settings.view_distance
	touch.scale_factor = Settings.touch_size
	touch.queue_redraw()


func _capture_mouse() -> void:
	if input.device == LocalInput.Device.KEYBOARD and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _pause() -> void:
	if finished or pause_menu.visible:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	touch.release_all()
	pause_menu.device = input.device
	pause_menu.open()


func _resume() -> void:
	get_tree().paused = false
	touch.release_all()
	_capture_mouse()


func _quit() -> void:
	returning = true
	selected = kind
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func _notification(what: int) -> void:
	if pause_menu == null:
		return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if finished:
			_quit()
		elif pause_menu.home.is_visible_in_tree():
			pause_menu.resume()
		elif not pause_menu.visible:
			_pause()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_pause()


func _input(event: InputEvent) -> void:
	if finished and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("practice_reset"):
		get_viewport().set_input_as_handled()
		reset_run()
