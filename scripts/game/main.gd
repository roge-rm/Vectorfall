extends Node

## Loads straight into the test map with you on team 0's base, and a second
## soldier standing on the other team so there's something to look at.

var map: TestMap
var game: Match
var input: LocalInput
var player: Soldier
var hud: Hud
var touch: TouchControls


func _ready() -> void:
	Settings.load_file()
	map = TestMap.new()
	add_child(map)
	game = Match.new(1)
	add_child(game)
	input = LocalInput.new()
	add_child(input)
	player = game.add_soldier(0, map.spawn_point(0, 3), input.source)
	player.set_first_person(true)
	var other := game.add_soldier(1, map.spawn_point(0, 6))
	other.global_position += Vector3(14.0, 0.0, 0.0)

	var camera := FirstPersonCamera.new()
	camera.soldier = player
	add_child(camera)
	camera.make_current()

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.soldier = player
	layer.add_child(hud)
	touch = TouchControls.new()
	layer.add_child(touch)
	input.touch = touch
	input.device_changed.connect(_on_device_changed)
	_on_device_changed(input.device)


func _on_device_changed(device: LocalInput.Device) -> void:
	touch.visible = device == LocalInput.Device.TOUCH
