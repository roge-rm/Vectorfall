extends Node

## Captures field equipment on Ochre Fold with the normal match HUD.

const FOLDER := "/srv/downloads/temp/debug/skifrei/m11"

var main: Node


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	Settings.path = "user://deploy-shot-settings.cfg"
	GameMap.chosen = "ochre_fold"
	MatchSetup.current.own_bots = 0
	MatchSetup.current.enemy_bots = 0
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var map: OchreFold = main.map
	var front: Vector3 = map.deploy_spots[2] + Vector3.RIGHT * 18.0
	var station := await _place(Pack.STATION, front + Vector3(0, 0, 4), -PI * 0.5)
	if station == null:
		_failed("station")
		return
	await _hold(_surface(station.position + Vector3(-4.0, 0, -1.0)), -1.82, -0.28, 14)
	await _save("field-station.png")
	var turret := await _place(Pack.TURRET, front + Vector3(0, 0, -2), -PI * 0.5)
	if turret == null:
		_failed("turret")
		return
	var sensor := await _place(Pack.SENSOR, front + Vector3(3, 0, -7), -PI * 0.5)
	if sensor == null:
		_failed("sensor")
		return
	var from := _surface(front + Vector3(-5.5, 0, 0))
	await _hold(from, -1.48, -0.1, 15)
	await _save("field-kit.png")
	await _hold(_surface(turret.position + Vector3(-6, 0, -5.0)), -1.9, -0.12, 225)
	await _save("turret-and-sensor.png")
	get_tree().quit()


func _failed(gear: String) -> void:
	push_error("Could not place the " + gear)
	get_tree().quit(1)


func _surface(at: Vector3) -> Vector3:
	return Vector3(at.x, main.map.surface_at(at.x, at.z) + 0.05, at.z)


func _place(slot: int, target: Vector3, yaw: float) -> BaseAsset:
	var player: Soldier = main.player
	var game: Match = main.game
	var before := game.next_id
	var worn := player.loadout.duplicate()
	worn.pack = slot
	player.set_loadout(worn)
	var from := _surface(target - BaseAsset.direction(yaw, 0.0) * Match.DEPLOY_DISTANCE)
	await _hold(from, yaw, -0.2, 30)
	Input.action_press("use")
	for i in 3:
		await get_tree().physics_frame
	Input.action_release("use")
	await get_tree().physics_frame
	return game.asset(before)


func _hold(at: Vector3, yaw: float, pitch: float, ticks: int) -> void:
	main.input.source.yaw = yaw
	main.input.source.pitch = pitch
	main.player.global_position = at
	main.player.velocity = Vector3.ZERO
	for i in ticks:
		await get_tree().physics_frame
	await get_tree().process_frame


func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var saved := get_viewport().get_texture().get_image().save_png(FOLDER.path_join(file))
	assert(saved == OK)
	print("Saved ", file)
