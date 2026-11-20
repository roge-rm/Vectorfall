extends Node

## Captures the airfield and vehicles in flight on Ochre Fold.
## Set VECTORFALL_SHOT_DIR to change the output folder.

const FOLDER := "/srv/downloads/temp/debug/vectorfall/m12"

class PilotScript:
	extends CommandSource
	var buttons := 0
	var throttle := 0.0

	func make_command(_delta: float) -> PlayerCommand:
		var command := PlayerCommand.new()
		command.yaw = yaw
		command.move.y = throttle
		command.buttons = buttons
		return command

var main: Node
var rig := Camera3D.new()


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	Settings.path = "user://vehicle-shot-settings.cfg"
	GameMap.chosen = "ochre_fold"
	MatchSetup.current.own_bots = 0
	MatchSetup.current.enemy_bots = 0
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	add_child(rig)
	rig.far = 1200
	await _ticks(12)
	if main.game.fleet.hulls.size() != 10:
		push_error("Expected five vehicles per team")
		get_tree().quit(1)
		return
	var needle := _hull(0, Vehicle.Kind.GUNSHIP)
	main.hud.hide()
	_frame(needle.position + Vector3(-36, 15, 0), needle.position + Vector3(7, 1, 0), 66.0)
	await _save("lime-airfield.png")
	var tank := _hull(0, Vehicle.Kind.TANK)
	var bike := _hull(0, Vehicle.Kind.BIKE)
	var ground := (tank.position + bike.position) * 0.5
	_frame(ground + Vector3(9, 4.5, -4), ground + Vector3(0, 0.25, 0), 61.0)
	await _save("sled-and-crawler.png")
	main.player.position = _step_to(needle)
	main.player.velocity = Vector3.ZERO
	main.input.source.yaw = needle.yaw
	main.input.source.pitch = -0.19
	main.camera.make_current()
	main.hud.show()
	await _ticks(12)
	Input.action_press("board")
	await _ticks(3)
	Input.action_release("board")
	if main.player.vehicle_id != needle.entity_id:
		push_error("Could not board the Needlewing")
		get_tree().quit(1)
		return
	Input.action_press("jet")
	await _ticks(100)
	Input.action_press("move_forward")
	await _ticks(105)
	Input.action_release("jet")
	Input.action_release("move_forward")
	main.input.set_device(LocalInput.Device.TOUCH)
	await _save("needlewing-pilot.png")
	main.input.set_device(LocalInput.Device.KEYBOARD)

	var kite := _hull(1, Vehicle.Kind.BOMBER)
	var ferry := _hull(1, Vehicle.Kind.TRANSPORT)
	var kite_pilot := _pilot(kite)
	var ferry_pilot := _pilot(ferry)
	await _ticks(3)
	kite_pilot.buttons = PlayerCommand.JET
	ferry_pilot.buttons = PlayerCommand.JET
	await _ticks(100)
	kite_pilot.throttle = 0.9
	ferry_pilot.throttle = 0.9
	await _ticks(104)
	kite_pilot.buttons = 0
	ferry_pilot.buttons = 0
	var air := (kite.position + ferry.position) * 0.5
	main.hud.hide()
	_frame(air + Vector3(-16, 5, -9), air + Vector3(-1, 0, 0), 57.0)
	await _save("kite-and-ferry.png")
	get_tree().quit()


func _hull(team: int, kind: int) -> Vehicle:
	for hull: Vehicle in main.game.fleet.hulls.values():
		if hull.team == team and hull.kind == kind:
			return hull
	return null


func _step_to(hull: Vehicle) -> Vector3:
	var at := hull.to_global(Vector3(Vehicle.SIZE[hull.kind].x * 0.5 + 1.3, 0, 0))
	at.y = main.game.fleet.ground_at(at) + 0.1
	return at


func _pilot(hull: Vehicle) -> PilotScript:
	var pilot := PilotScript.new()
	pilot.yaw = hull.yaw
	pilot.buttons = PlayerCommand.BOARD
	main.game.add_soldier(hull.team, Transform3D(Basis(Vector3.UP, hull.yaw), _step_to(hull)), pilot)
	return pilot


func _frame(at: Vector3, target: Vector3, lens: float) -> void:
	rig.fov = lens
	rig.look_at_from_position(at, target)
	rig.make_current()


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	var folder := OS.get_environment("VECTORFALL_SHOT_DIR")
	if folder.is_empty():
		folder = FOLDER
	DirAccess.make_dir_recursive_absolute(folder)
	var saved := get_viewport().get_texture().get_image().save_png(folder.path_join(file))
	assert(saved == OK)
	print("Saved ", file)
