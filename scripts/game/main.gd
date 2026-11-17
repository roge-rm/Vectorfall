extends Node

## Loads straight into the test map with you on team 0's base, a flag on each
## base, and a dummy enemy on team 1 posted down the slope in front of it, strafing and firing
## discs now and then so there's something to shoot.

var map: TestMap
var game: Match
var input: LocalInput
var player: Soldier
var enemy: Soldier
var dummy: DummySource
var camera: FirstPersonCamera
var hud: Hud
var touch: TouchControls
var effects: Effects


func _ready() -> void:
	Settings.load_file()
	map = TestMap.new()
	add_child(map)
	game = Match.new(1)
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

	dummy = DummySource.new()
	var post_x := map.base_x(0) + 45.0
	dummy.post = Vector3(post_x, map.height_at(post_x, 0.0), 0.0)
	var facing := Transform3D(Basis(Vector3.UP, PI * 0.5), dummy.post + Vector3.UP * 0.5)
	enemy = game.add_soldier(1, facing, dummy)
	dummy.game = game
	dummy.soldier = enemy
	dummy.target = player

	var view := ProjectileView.new()
	view.game = game
	add_child(view)
	effects = Effects.new()
	add_child(effects)
	effects.watch(game)

	camera = FirstPersonCamera.new()
	camera.soldier = player
	camera.view_model.set_team_colour(Soldier.TEAM_COLOURS[player.team])
	add_child(camera)
	camera.make_current()

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.soldier = player
	hud.watch(game)
	hud.restart_requested.connect(restart)
	layer.add_child(hud)
	touch = TouchControls.new()
	layer.add_child(touch)
	input.touch = touch
	input.device_changed.connect(_on_device_changed)
	_on_device_changed(input.device)


func _on_device_changed(device: LocalInput.Device) -> void:
	touch.visible = device == LocalInput.Device.TOUCH


func _on_match_over(_winner: int) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Starts the match again from the beginning.
func restart() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


func _unhandled_key_input(event: InputEvent) -> void:
	if game.over and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		restart()
