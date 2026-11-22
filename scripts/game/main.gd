extends Node

## A match from MatchSetup.current: the map (or another with --map NAME
## after -- on the command line, or GameMap.chosen), you on your team beside
## your base, a flag on each base, and bots on both teams playing capture the
## flag with you, as offence, defence or midfield. F3 shows what the bots are
## doing, and V, the D-pad up or ORDERS opens the order menu. Esc, Start or
## the touch pause button opens the pause menu, which pauses the whole tree.
## You start in your last saved loadout. The loadout screen opens when you
## step onto one of your team's inventory stations, and with I, B, the
## gamepad's Back or the LOADOUT button while you're on one or dead.

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
var loadout_screen: LoadoutScreen
var replica: MatchReplica
var team_map: TeamMap
var results_board: ResultsBoard
var ladder_round: int = BotLadder.Round.NONE
var duo_panel: DuoPanel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().paused = false
	Settings.load_file()
	setup = MatchSetup.current
	var connection := OnlineClient.active
	var selected := GameMap.chosen_name(setup.map) if connection == null else connection.map_name
	if connection == null and BotLadder.active in [BotLadder.Round.FLAG, BotLadder.Round.HOLD]:
		ladder_round = BotLadder.active
		setup = BotLadder.match_setup(ladder_round)
		selected = setup.map
	map = GameMap.make(selected)
	add_child(map)
	map.set_view_distance(Settings.view_distance)
	print("Map %s built in %.2f s, its route graph in %.2f s" % [map.title, map.build_seconds, map.graph_seconds])
	var minutes := setup.time_limit / 60.0 if connection == null else float(connection.minutes)
	var captures := setup.capture_limit if connection == null else connection.captures
	var hold: bool = setup.hold if connection == null else not connection.initial.get("hold_points", []).is_empty()
	var resupply := setup.resupply if connection == null else false
	game = ArenaMatch.make(self, map, minutes, captures, 1, 8, hold, resupply)
	game.match_over.connect(_on_match_over)
	input = LocalInput.new()
	add_child(input)
	if connection == null:
		_spawn_offline()
	else:
		replica = MatchReplica.new()
		replica.start(connection, game)
		player = replica.player
	player.display_name = "You"
	player.set_first_person(true)
	input.soldier = player
	input.source.yaw = player.yaw
	input.source.pitch = player.pitch

	var view := ProjectileView.new()
	view.game = game
	if replica != null:
		view.online_pose = replica.projectile_position
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
	audio.watch(game, player, map)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new(ladder_round != BotLadder.Round.NONE)
	hud.soldier = player
	hud.watch(game)
	hud.restart_requested.connect(restart)
	hud.menu_requested.connect(quit_to_menu)
	layer.add_child(hud)
	menu = OrderMenu.new()
	menu.director = bots
	menu.soldier = player
	menu.commander_mode = replica == null and Settings.commander_mode
	layer.add_child(menu)
	menu.chosen.connect(input.queue_order)
	touch = TouchControls.new()
	touch.scale_factor = Settings.touch_size
	layer.add_child(touch)
	touch.menu = menu
	menu.touch = touch
	touch.pause_pressed.connect(pause)
	touch.soldier = player
	input.touch = touch
	hud.touch = touch
	input.menu = menu
	input.pause_requested.connect(pause)
	if bots != null:
		for team: int in bots.commanders:
			bots.commanders[team].said.connect(_on_said)
	input.device_changed.connect(_on_device_changed)
	_on_device_changed(input.device)
	loadout_screen = LoadoutScreen.new()
	layer.add_child(loadout_screen)
	loadout_screen.chosen.connect(input.want_loadout)
	loadout_screen.closed.connect(_on_loadout_closed)
	hud.loadout_requested.connect(open_loadout)
	input.loadout_requested.connect(open_loadout)
	game.station_entered.connect(_on_station_entered)

	team_map = TeamMap.new()
	team_map.game = game
	team_map.viewer = player
	team_map.closed.connect(_close_team_map)
	team_map.waypoint_requested.connect(_send_waypoint)
	layer.add_child(team_map)
	hud.tactical_requested.connect(_open_team_map)
	results_board = ResultsBoard.new()
	results_board.game = game
	results_board.viewer = player
	results_board.closed.connect(_close_results)
	layer.add_child(results_board)
	hud.results_requested.connect(results_board.open)
	if Engine.has_singleton(DuoPanel.PLUGIN):
		duo_panel = DuoPanel.new(game, player)

	var top := CanvasLayer.new()
	top.layer = 2
	add_child(top)
	var quit_title := "Quit to ladder" if ladder_round != BotLadder.Round.NONE else "Quit to menu"
	pause_menu = PauseMenu.new("Restart" if replica == null else "", quit_title)
	top.add_child(pause_menu)
	pause_menu.resumed.connect(_on_resumed)
	pause_menu.restart_pressed.connect(restart)
	pause_menu.quit_pressed.connect(quit_to_menu)
	pause_menu.settings.changed.connect(apply_settings)
	if replica != null:
		replica.client.arena_ready()
		hud.online_round()
		if game.over:
			game.match_over.emit(game.winner)


func _spawn_offline() -> void:
	var own := setup.team
	var other := 1 - own
	player = game.add_soldier(own, map.spawn_point(own, 3), input.source, Settings.current_loadout())
	bots = BotDirector.new(game, map.route_graph)
	bots.skill_levels.assign(setup.skill_levels())
	for k in setup.own_bots:
		bots.add_bot(own, map.spawn_point(own, k if k < 3 else k + 1))
	for k in setup.enemy_bots:
		var brain := bots.add_bot(other, map.spawn_point(other, k))
		if enemy == null:
			enemy = brain.soldier
	game.prepare_terrain()
	overlay = BotOverlay.new(bots)
	add_child(overlay)


func _physics_process(_delta: float) -> void:
	if replica != null and is_instance_valid(replica.client):
		replica.advance(input.make_command(OnlineClient.STEP))


func _open_team_map() -> void:
	if game.over or pause_menu.visible or loadout_screen.visible:
		return
	menu.close()
	touch.release_all()
	touch.blocked = true
	input.held_off = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	team_map.open()


func _close_team_map() -> void:
	team_map.hide()
	touch.release_all()
	_on_loadout_closed()


func _send_waypoint(recipient: int, point: Vector2) -> void:
	input.queue_order(Orders.Kind.WAYPOINT, recipient, point)
	_close_team_map()


func _close_results() -> void:
	results_board.hide()
	hud.focus_results()


func _input(event: InputEvent) -> void:
	if team_map == null:
		return
	var toggle := false
	if event is InputEventKey:
		toggle = event.pressed and not event.echo and event.physical_keycode == KEY_M
	elif event is InputEventJoypadButton:
		toggle = event.pressed and event.button_index == JOY_BUTTON_RIGHT_STICK
	if results_board.visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		_close_results()
	elif team_map.visible and (toggle or event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		_close_team_map()
	elif game.over and ladder_round != BotLadder.Round.NONE and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		quit_to_menu()
		return
	elif toggle:
		_open_team_map()
	else:
		return
	get_viewport().set_input_as_handled()


## Opens the loadout screen while you're dead or on one of your stations.
## Your soldier stands still while it's open.
func open_loadout() -> void:
	if loadout_screen.visible or game.over or pause_menu.visible or team_map.visible:
		return
	if not player.dead and game.station_under(player) == null:
		return
	if menu.visible:
		menu.close()
	input.held_off = true
	touch.blocked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	loadout_screen.open()


func _on_loadout_closed() -> void:
	var online_paused := replica != null and pause_menu.visible
	input.held_off = online_paused
	touch.blocked = online_paused
	if input.device == LocalInput.Device.KEYBOARD and not game.over and not pause_menu.visible and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_station_entered(_station_id: int, soldier_id: int) -> void:
	if soldier_id == player.entity_id:
		open_loadout()


func _process(delta: float) -> void:
	if replica != null and is_instance_valid(replica.client):
		replica.render(delta)
		replica.events(_on_said)
	if duo_panel != null:
		duo_panel.update(delta)
	# It closes once you're back to life off a station, or pushed off one.
	if loadout_screen != null and loadout_screen.visible and (game.over or (not player.dead and game.station_under(player) == null)):
		loadout_screen.close()


func _on_device_changed(device: LocalInput.Device) -> void:
	touch.visible = device == LocalInput.Device.TOUCH
	hud.device = device


## Picks up settings that belong to the match after they change.
func apply_settings() -> void:
	map.set_view_distance(Settings.view_distance)
	camera.far = Settings.view_distance
	menu.commander_mode = replica == null and Settings.commander_mode
	touch.scale_factor = Settings.touch_size
	touch.queue_redraw()


## Pauses the whole tree, sim included, and opens the pause menu.
func pause() -> void:
	if pause_menu.visible or game.over:
		return
	if team_map.visible:
		_close_team_map()
	if menu.visible:
		menu.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if replica == null:
		get_tree().paused = true
	else:
		input.held_off = true
		touch.blocked = true
	# Touches lifted while paused are never seen, so start clean both ways.
	touch.release_all()
	pause_menu.device = input.device
	pause_menu.open()


func _on_resumed() -> void:
	get_tree().paused = false
	if replica != null:
		input.held_off = loadout_screen.visible
		touch.blocked = loadout_screen.visible
	touch.release_all()
	if input.device == LocalInput.Device.KEYBOARD and not game.over and not loadout_screen.visible and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## A bot said something to its team: shown and spoken if it's yours.
func _on_said(team: int, speaker_id: int, line: int, text: String) -> void:
	if team != player.team:
		return
	hud.add_chat(game.soldier(speaker_id), text)
	BotVoice.play(line, speaker_id, team)


func _on_match_over(winner: int) -> void:
	if team_map != null and team_map.visible:
		_close_team_map()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if ladder_round != BotLadder.Round.NONE and winner == player.team and BotLadder.record_clear(ladder_round):
		hud.show_ladder_clear("Ladder complete" if ladder_round == BotLadder.Round.HOLD else "Capture and hold unlocked")


## Starts the match again from the beginning.
func restart() -> void:
	if replica != null:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	get_tree().reload_current_scene()


func quit_to_menu() -> void:
	if OnlineClient.active != null:
		OnlineClient.active.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func _notification(what: int) -> void:
	# Android's back button and leaving the app pause the match.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if what == NOTIFICATION_WM_GO_BACK_REQUEST and results_board != null and results_board.visible:
			_close_results()
		elif what == NOTIFICATION_WM_GO_BACK_REQUEST and team_map != null and team_map.visible:
			_close_team_map()
		elif what == NOTIFICATION_WM_GO_BACK_REQUEST and game != null and game.over and ladder_round != BotLadder.Round.NONE:
			quit_to_menu()
		elif pause_menu != null and not pause_menu.visible and not game.over:
			pause()
		elif what == NOTIFICATION_WM_GO_BACK_REQUEST and pause_menu != null and pause_menu.home.visible:
			pause_menu.resume()


func _exit_tree() -> void:
	if duo_panel != null:
		duo_panel.clear()


func _unhandled_key_input(event: InputEvent) -> void:
	if game.over and not results_board.visible and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		restart()
