extends Node

## A match from MatchSetup.current: the map (or another with --map NAME
## after -- on the command line, or GameMap.chosen), you on your team beside
## your base, a flag on each base, and bots on both teams playing capture the
## flag with you, as offence, defence or midfield. F3 shows what the bots are
## doing, and V, the D-pad up or ORDERS opens the order menu. Esc, Start or
## the touch pause button opens the pause menu, which pauses the whole tree.

const MENU_SCENE := "res://scenes/menu.tscn"

var setup: MatchSetup
var map: GameMap
var game: Match
var input: LocalInput
var player: Soldier
## The first enemy bot's soldier, or null with no enemy bots.
var enemy: Soldier
var bots: BotDirector
var overlay: BotOverlay
var camera: FirstPersonCamera
var hud: Hud
var touch: TouchControls
var menu: OrderMenu
var effects: Effects
var audio: GameAudio
var pause_menu: PauseMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().paused = false
	Settings.load_file()
	setup = MatchSetup.current
	map = GameMap.make(GameMap.chosen_name(setup.map))
	add_child(map)
	map.set_view_distance(Settings.view_distance)
	print("Map %s built in %.2f s, its route graph in %.2f s" % [map.title, map.build_seconds, map.graph_seconds])
	game = Match.new(1)
	game.settings.time_limit = setup.time_limit
	game.settings.capture_limit = setup.capture_limit
	game.start_clock()
	game.terrain = map.terrain
	for team in 2:
		game.spawns[team] = map.spawn_points(team)
	for team in 2:
		game.add_flag(team, map.stand_point(team), map.flag_rest(team))
	add_child(game)
	game.match_over.connect(_on_match_over)
	input = LocalInput.new()
	add_child(input)
	var own := setup.team
	var other := 1 - own
	player = game.add_soldier(own, map.spawn_point(own, 3), input.source)
	player.display_name = "You"
	player.set_first_person(true)
	input.soldier = player

	bots = BotDirector.new(game, map.route_graph)
	bots.skill_levels.assign(setup.skill_levels())
	for k in setup.own_bots:
		# Slot 3 is yours.
		bots.add_bot(own, map.spawn_point(own, k if k < 3 else k + 1))
	for k in setup.enemy_bots:
		var brain := bots.add_bot(other, map.spawn_point(other, k))
		if enemy == null:
			enemy = brain.soldier
	game.prepare_terrain()
	overlay = BotOverlay.new(bots)
	add_child(overlay)

	var view := ProjectileView.new()
	view.game = game
	add_child(view)
	effects = Effects.new()
	add_child(effects)
	effects.watch(game)

	camera = FirstPersonCamera.new()
	camera.soldier = player
	camera.view_model.set_team_colour(Palette.team(player.team))
	add_child(camera)
	camera.far = Settings.view_distance
	camera.make_current()
	audio = GameAudio.new()
	add_child(audio)
	audio.watch(game, player)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.soldier = player
	hud.watch(game)
	hud.restart_requested.connect(restart)
	hud.menu_requested.connect(quit_to_menu)
	layer.add_child(hud)
	menu = OrderMenu.new()
	menu.director = bots
	menu.soldier = player
	menu.commander_mode = Settings.commander_mode
	layer.add_child(menu)
	menu.chosen.connect(input.queue_order)
	touch = TouchControls.new()
	touch.scale_factor = Settings.touch_size
	layer.add_child(touch)
	touch.menu = menu
	menu.touch = touch
	touch.pause_pressed.connect(pause)
	input.touch = touch
	hud.touch = touch
	input.menu = menu
	input.pause_requested.connect(pause)
	for team: int in bots.commanders:
		bots.commanders[team].said.connect(_on_said)
	input.device_changed.connect(_on_device_changed)
	_on_device_changed(input.device)

	var top := CanvasLayer.new()
	top.layer = 2
	add_child(top)
	pause_menu = PauseMenu.new()
	top.add_child(pause_menu)
	pause_menu.resumed.connect(_on_resumed)
	pause_menu.restart_pressed.connect(restart)
	pause_menu.quit_pressed.connect(quit_to_menu)
	pause_menu.settings.changed.connect(apply_settings)


func _on_device_changed(device: LocalInput.Device) -> void:
	touch.visible = device == LocalInput.Device.TOUCH


## Picks up settings that belong to the match after they change.
func apply_settings() -> void:
	map.set_view_distance(Settings.view_distance)
	camera.far = Settings.view_distance
	menu.commander_mode = Settings.commander_mode
	touch.scale_factor = Settings.touch_size
	touch.queue_redraw()


## Pauses the whole tree, sim included, and opens the pause menu.
func pause() -> void:
	if pause_menu.visible:
		return
	if menu.visible:
		menu.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	# Touches lifted while paused are never seen, so start clean both ways.
	touch.release_all()
	pause_menu.device = input.device
	pause_menu.open()


func _on_resumed() -> void:
	get_tree().paused = false
	touch.release_all()
	if input.device == LocalInput.Device.KEYBOARD and not game.over and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## A bot said something to its team: shown and spoken if it's yours.
func _on_said(team: int, speaker_id: int, line: int, text: String) -> void:
	if team != player.team:
		return
	hud.add_chat(game.soldier(speaker_id), text)
	BotVoice.play(line, speaker_id, team)


func _on_match_over(_winner: int) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Starts the match again from the beginning.
func restart() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	get_tree().reload_current_scene()


func quit_to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func _notification(what: int) -> void:
	# Android's back button and leaving the app pause the match.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if pause_menu != null and not pause_menu.visible and not game.over:
			pause()
		elif what == NOTIFICATION_WM_GO_BACK_REQUEST and pause_menu != null and pause_menu.home.visible:
			pause_menu.resume()


func _unhandled_key_input(event: InputEvent) -> void:
	if game.over and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		restart()
