class_name SkiPractice
extends Node

const MENU_SCENE := "res://scenes/menu.tscn"

enum Stage { SKI, CREST, FLAG, FINISHED }

var map: PracticeMap
var game: Match
var player: Soldier
var input: LocalInput
var touch: TouchControls
var camera: FirstPersonCamera
var pause_menu: PauseMenu
var stage := Stage.SKI
var best_ticks := 0
var elapsed_ticks := 0
var _start_tick := -1
var _climbed := false
var _hint: Label
var _clock: Label
var _energy: ProgressBar
var _result: Control
var _result_time: Label
var _ladder_run := false
var _ladder_status: Label
var _ladder_button: Button


class MovementInput:
	extends LocalInput

	func make_command(delta: float) -> PlayerCommand:
		var command := super(delta)
		command.buttons &= PlayerCommand.JUMP | PlayerCommand.SKI | PlayerCommand.JET
		return command


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().paused = false
	Settings.load_file()
	_ladder_run = BotLadder.active == BotLadder.Round.SKI
	var file := ConfigFile.new()
	if file.load(Settings.path) == OK:
		best_ticks = maxi(0, int(file.get_value("practice", "best_ticks", 0)))

	map = PracticeMap.new()
	add_child(map)
	game = Match.new()
	game.terrain = map.terrain
	game.spawns[0] = [map.spawn_transform()]
	add_child(game)

	input = MovementInput.new()
	add_child(input)
	player = game.add_soldier(0, map.spawn_transform(), input.source)
	player.set_first_person(true)
	input.soldier = player
	game.prepare_terrain()
	game.flag_taken.connect(_on_flag_taken)

	camera = FirstPersonCamera.new()
	camera.soldier = player
	camera.view_model.process_mode = Node.PROCESS_MODE_DISABLED
	camera.view_model.hide()
	add_child(camera)
	camera.make_current()
	var audio := GameAudio.new()
	add_child(audio)
	audio.watch(game, player, map)

	var layer := CanvasLayer.new()
	add_child(layer)
	_build_hud(layer)
	touch = TouchControls.new()
	touch.movement_only = true
	touch.soldier = player
	layer.add_child(touch)
	input.touch = touch
	touch.pause_pressed.connect(_pause)
	input.pause_requested.connect(_pause)
	input.device_changed.connect(_on_device_changed)
	_on_device_changed(input.device)

	var top := CanvasLayer.new()
	top.layer = 2
	add_child(top)
	pause_menu = PauseMenu.new("Reset run", "Quit to ladder" if _ladder_run else "Quit to menu")
	top.add_child(pause_menu)
	pause_menu.resumed.connect(_resume)
	pause_menu.restart_pressed.connect(reset_run)
	pause_menu.quit_pressed.connect(_quit)
	pause_menu.settings.changed.connect(_apply_settings)
	_apply_settings()
	_capture_mouse()


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
	_hint = MenuKit.heading("", 22)
	_hint.add_theme_color_override("font_color", InkUi.CREAM)
	_hint.add_theme_color_override("font_outline_color", InkUi.INK)
	_hint.add_theme_constant_override("outline_size", MenuKit.pxi(4))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	readout.add_child(_hint)

	_clock = MenuKit.ink_label("", 15, InkUi.Face.BOLD, InkUi.CREAM)
	_clock.add_theme_color_override("font_outline_color", InkUi.INK)
	_clock.add_theme_constant_override("outline_size", MenuKit.pxi(4))
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	readout.add_child(_clock)

	_energy = ProgressBar.new()
	_energy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_energy.show_percentage = false
	_energy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_energy.custom_minimum_size = Vector2(MenuKit.px(90.0), MenuKit.px(4.0))
	var fill := StyleBoxFlat.new()
	fill.bg_color = InkUi.ORANGE
	_energy.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = InkUi.INK
	_energy.add_theme_stylebox_override("background", back)
	readout.add_child(_energy)

	_result = Control.new()
	_result.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_result)
	var result := MenuKit.card(_result, "Flag grabbed")
	_result_time = MenuKit.heading("", 23)
	_result_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.add_child(_result_time)
	if _ladder_run:
		_ladder_status = MenuKit.ink_label("Capture the flag unlocked", 15)
		_ladder_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_ladder_status.hide()
		result.add_child(_ladder_status)
	result.add_child(MenuKit.button("Run again", reset_run, 22, false, true))
	_ladder_button = MenuKit.button("Bot ladder" if _ladder_run else "Main menu", _quit, 22, true)
	result.add_child(_ladder_button)
	_result.hide()


func _physics_process(_delta: float) -> void:
	if stage == Stage.FINISHED:
		return
	var at := player.global_position
	if player.dead or absf(at.z) > 44.0 or at.x > PracticeMap.RUNOUT_X or at.x < -141.0 or at.y < -5.0:
		reset_run()
		return
	if _start_tick < 0 and at.x >= PracticeMap.START_X + 8.0:
		_start_tick = game.tick
	if _start_tick >= 0:
		elapsed_ticks = game.tick - _start_tick
	if absf(at.z) > PracticeMap.HALF_LANE:
		return
	match stage:
		Stage.SKI:
			if at.x >= PracticeMap.SKI_X and at.x < -42.0 and player.skiing and player.velocity.x >= 12.0:
				stage = Stage.CREST
				_update_hint()
		Stage.CREST:
			if at.x < -60.0:
				_climbed = false
			elif at.x < PracticeMap.CREST_X and player.jetting and player.velocity.y > 1.0:
				_climbed = true
			if at.x >= PracticeMap.CREST_X and _climbed:
				stage = Stage.FLAG
				_update_hint()
				var flag_at := map.flag_position()
				game.add_flag(1, flag_at, flag_at + Vector3.UP * (Flag.POLE * 0.5))


func _process(_delta: float) -> void:
	if stage != Stage.FINISHED:
		_clock.text = "%s · %d m/s" % [_time(elapsed_ticks), roundi(player.horizontal_speed())]
		_energy.value = player.energy / player.tuning.energy_max * 100.0


func _update_hint() -> void:
	match stage:
		Stage.SKI:
			var button := "Space"
			if input.device == LocalInput.Device.TOUCH:
				button = "JUMP"
			elif input.device == LocalInput.Device.GAMEPAD:
				button = "the left bumper"
			_hint.text = "Move forward and hold %s to ski" % button
		Stage.CREST:
			var button := "Shift"
			if input.device == LocalInput.Device.TOUCH:
				button = "JET"
			elif input.device == LocalInput.Device.GAMEPAD:
				button = "the left trigger"
			_hint.text = "Hold %s to jet over the crest" % button
		Stage.FLAG:
			_hint.text = "Release jet, land and touch the flag"
		Stage.FINISHED:
			_hint.text = ""


func _on_flag_taken(_team: int, soldier_id: int) -> void:
	if stage != Stage.FLAG or soldier_id != player.entity_id:
		return
	stage = Stage.FINISHED
	elapsed_ticks = game.tick - _start_tick
	if best_ticks == 0 or elapsed_ticks < best_ticks:
		best_ticks = elapsed_ticks
		var file := ConfigFile.new()
		var error := file.load(Settings.path)
		if error == OK or error == ERR_FILE_NOT_FOUND:
			file.set_value("practice", "best_ticks", best_ticks)
			if file.save(Settings.path) != OK:
				push_warning("Couldn't save the best practice time.")
	game.running = false
	player.skiing = false
	player.jetting = false
	player.velocity = Vector3.ZERO
	input.held_off = true
	touch.blocked = true
	touch.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_hint()
	_clock.text = ""
	_energy.hide()
	_result_time.text = "%s · Best %s" % [_time(elapsed_ticks), _time(best_ticks)]
	_result.show()
	if _ladder_run and BotLadder.record_clear(BotLadder.Round.SKI):
		_ladder_status.show()
		_ladder_button.grab_focus()
	else:
		MenuKit.focus_first(_result)


func reset_run() -> void:
	var flag: Flag = game.flags.get(1)
	if flag != null:
		flag.queue_free()
		game.flags.erase(1)
		game.stands.erase(1)
	game.respawn(player)
	game.prepare_terrain()
	stage = Stage.SKI
	_start_tick = -1
	elapsed_ticks = 0
	_climbed = false
	_result.hide()
	if _ladder_run:
		_ladder_status.hide()
	_energy.show()
	_clock.text = _time(0)
	input.held_off = false
	touch.blocked = false
	touch.release_all()
	touch.visible = input.device == LocalInput.Device.TOUCH
	if pause_menu.visible:
		pause_menu.resume()
	game.over = false
	game.start_clock()
	game.running = true
	_update_hint()
	_capture_mouse()


func _on_device_changed(device: LocalInput.Device) -> void:
	touch.visible = device == LocalInput.Device.TOUCH and stage != Stage.FINISHED
	_update_hint()


func _apply_settings() -> void:
	map.set_view_distance(Settings.view_distance)
	camera.far = Settings.view_distance
	touch.scale_factor = Settings.touch_size
	touch.queue_redraw()


static func _time(ticks: int) -> String:
	return "%.2f s" % (float(ticks) / Engine.physics_ticks_per_second)


func _capture_mouse() -> void:
	if input.device == LocalInput.Device.KEYBOARD and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _pause() -> void:
	if stage == Stage.FINISHED or pause_menu.visible:
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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func _notification(what: int) -> void:
	if pause_menu == null:
		return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if stage == Stage.FINISHED:
			_quit()
		elif pause_menu.home.is_visible_in_tree():
			pause_menu.resume()
		elif not pause_menu.visible:
			_pause()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_pause()


func _input(event: InputEvent) -> void:
	if _ladder_run and stage == Stage.FINISHED and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("practice_reset"):
		get_viewport().set_input_as_handled()
		reset_run()
