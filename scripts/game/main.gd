extends Node

## Loads straight into a map (Ochre Fold, or another with --map NAME after --
## on the command line, or GameMap.chosen) with you beside team 0's base, a flag on each
## base, and bots on both teams playing capture the flag with you, as
## offence, defence or midfield. F3 shows what the bots are doing, and V,
## the D-pad up or ORDERS opens the order menu. Bot skill per team and
## commander mode come from Settings.

## Bots on your team, and on the other.
const OWN_BOTS := 3
const ENEMY_BOTS := 4

var map: GameMap
var game: Match
var input: LocalInput
var player: Soldier
## The first enemy bot's soldier.
var enemy: Soldier
var bots: BotDirector
var overlay: BotOverlay
var camera: FirstPersonCamera
var hud: Hud
var touch: TouchControls
var menu: OrderMenu
var effects: Effects


func _ready() -> void:
	Settings.load_file()
	map = GameMap.make(GameMap.chosen_name())
	add_child(map)
	map.set_view_distance(Settings.view_distance)
	print("Map %s built in %.2f s, its route graph in %.2f s" % [map.title, map.build_seconds, map.graph_seconds])
	game = Match.new(1)
	game.terrain = map.terrain
	for team in 2:
		game.spawns[team] = map.spawn_points(team)
	for team in 2:
		game.add_flag(team, map.stand_point(team), map.flag_rest(team))
	add_child(game)
	game.match_over.connect(_on_match_over)
	input = LocalInput.new()
	add_child(input)
	player = game.add_soldier(0, map.spawn_point(0, 3), input.source)
	player.display_name = "You"
	player.set_first_person(true)

	bots = BotDirector.new(game, map.route_graph)
	bots.skill_levels.assign(Settings.bot_skill)
	for k in OWN_BOTS:
		# Slot 3 is yours.
		bots.add_bot(0, map.spawn_point(0, k if k < 3 else k + 1))
	for k in ENEMY_BOTS:
		bots.add_bot(1, map.spawn_point(1, k))
	enemy = bots.brains[OWN_BOTS].soldier
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

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.soldier = player
	hud.watch(game)
	hud.restart_requested.connect(restart)
	layer.add_child(hud)
	menu = OrderMenu.new()
	menu.director = bots
	menu.soldier = player
	menu.commander_mode = Settings.commander_mode
	layer.add_child(menu)
	menu.chosen.connect(input.queue_order)
	touch = TouchControls.new()
	layer.add_child(touch)
	touch.menu = menu
	input.touch = touch
	input.menu = menu
	for team: int in bots.commanders:
		bots.commanders[team].said.connect(_on_said)
	input.device_changed.connect(_on_device_changed)
	_on_device_changed(input.device)


func _on_device_changed(device: LocalInput.Device) -> void:
	touch.visible = device == LocalInput.Device.TOUCH


## A bot said something to its team: shown and spoken if it's yours.
func _on_said(team: int, speaker_id: int, line: int, text: String) -> void:
	if team != player.team:
		return
	hud.add_chat(game.soldier(speaker_id), text)
	BotVoice.play(line, speaker_id)


func _on_match_over(_winner: int) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Starts the match again from the beginning.
func restart() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


func _unhandled_key_input(event: InputEvent) -> void:
	if game.over and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		restart()
