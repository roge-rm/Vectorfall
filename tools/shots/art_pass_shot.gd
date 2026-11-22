extends Node

## Same camera positions and objects for comparing art and rendering cost.
## Pass a folder name after -- to keep each run's pictures. Add gallery
## after the name for the other armour, vehicles, weapons and base equipment.

const FOLDER := "/srv/downloads/temp/debug/skifrei/art-pass"

var main: Node
var camera := Camera3D.new()
var output := FOLDER


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = FOLDER.path_join(args[0])
	DirAccess.make_dir_recursive_absolute(output)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Settings.path = "user://art-pass-shot.cfg"
	GameMap.chosen = "ochre_fold"
	MatchSetup.current.own_bots = 0
	MatchSetup.current.enemy_bots = 0
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	add_child(camera)
	camera.far = Settings.view_distance
	camera.make_current()
	main.hud.hide()
	for i in 12:
		await get_tree().physics_frame
	var game: Match = main.game
	game.running = false
	main.player.hide()
	var at := _ground(Vector3(-501, 0, -16))
	var left := _soldier(0, at + Vector3(0, 0, -0.9), -PI * 0.5)
	var right := _soldier(1, at + Vector3(0, 0, 0.9), -PI * 0.5)
	await _capture("armour-front", at + Vector3(3.0, 1.35, -0.42), at + Vector3(0, 0.9, 0), 51)
	await _capture("armour-back", at + Vector3(-3.15, 1.42, 0.58), at + Vector3(0, 0.92, 0), 51)
	left.hide()
	right.hide()
	var wing: Vehicle
	for hull: Vehicle in game.fleet.hulls.values():
		if hull.team == 1 and hull.kind == Vehicle.Kind.GUNSHIP:
			wing = hull
			break
	if wing == null:
		push_error("The gunship did not spawn")
		get_tree().quit(1)
		return
	var parked := wing.position
	wing.position = Vector3(510, 90, 26)
	await _capture("needlewing", wing.position + Vector3(-7.8, 5.2, -7.4), wing.position + Vector3(0, 0.2, 0), 49)
	wing.position = parked
	await _capture("ochre-fold", Vector3(590, 110, -55), Vector3(315, 44, -80), 73)
	left.show()
	right.show()
	for i in 15:
		var across := float(i % 5 - 2) * 2.4
		var down := 8.0 + (i / 5) * 11.0
		var place := _ground(Vector3(-646 + down, 0, across))
		if i == 0:
			left.position = place
		elif i == 1:
			right.position = place
		else:
			_soldier(i % 2, place, -PI * 0.5)
	main.player.show()
	main.player.position = _ground(Vector3(-644, 0, 4))
	for hull: Vehicle in game.fleet.hulls.values():
		if hull.team == 1:
			hull.position = _ground(Vector3(-540 - hull.kind * 3, 0, (hull.kind - 2) * 8 - 12))
			hull.position.y += Vehicle.ride_height(hull.kind) + (4.0 if hull.flies() else 0.0)
	await _capture("busy-view", Vector3(-644, 50, 4), Vector3(-548, 47, 0), 75)
	var in_view := 0
	for hull: Vehicle in game.fleet.hulls.values():
		if camera.is_position_in_frustum(hull.global_position):
			in_view += 1
	print("Busy view: ", in_view, " hulls in the camera frustum, 16 soldiers staged")
	await _measure(true)
	await _measure(false)
	if args.has("gallery"):
		await _gallery(game)
	get_tree().quit()


## Stages the models in the same light as the match.
func _gallery(game: Match) -> void:
	Cel.set_outlines(true)
	for who: Soldier in game.entities.values():
		who.hide()
	for craft: Vehicle in game.fleet.hulls.values():
		if craft.team == 0:
			craft.position = _ground(Vector3(-604, 0, (craft.kind - 2) * 7))
			craft.position.y += Vehicle.ride_height(craft.kind)
	await _capture("fleet", Vector3(-580, 53, -2), Vector3(-604, 48, 0), 46)
	var air := Vector3(508, 88, 29)
	for craft: Vehicle in game.fleet.hulls.values():
		if craft.team != 1:
			continue
		if craft.kind == Vehicle.Kind.BOMBER:
			craft.position = air + Vector3(-2.0, 0, -4.3)
		elif craft.kind == Vehicle.Kind.TRANSPORT:
			craft.position = air + Vector3(2.0, 0.5, 4.6)
	await _capture("airframes", air + Vector3(-15, 5.0, -8), air + Vector3(0.0, 0, 0.5), 47)
	for craft: Vehicle in game.fleet.hulls.values():
		craft.hide()

	var at := _ground(Vector3(-501, 0, -22))
	var line: Array[Soldier] = []
	for team in 2:
		for armour in 3:
			var who := _soldier(team, at + Vector3(0, 0, (team * 3 + armour - 2.5) * 0.95), -PI * 0.5)
			var loadout := who.loadout.duplicate()
			loadout.armour = armour
			who.set_loadout(loadout)
			line.append(who)
	await _capture("all-armour-front", at + Vector3(5.0, 1.75, 0.17), at + Vector3(0, 1, 0), 46)
	await _capture("all-armour-back", at + Vector3(-5.0, 1.75, 0.17), at + Vector3(0, 1, 0), 46)
	for metres: int in [10, 25, 50]:
		var target := at + Vector3.UP
		await _capture("armour-front-%dm" % metres, target + Vector3.RIGHT * metres, target, 52)
		await _capture("armour-back-%dm" % metres, target + Vector3.LEFT * metres, target, 52)
	for who in line:
		who.hide()

	var gun_rack := Node3D.new()
	add_child(gun_rack)
	gun_rack.position = Vector3(-501, 125, 0)
	for slot in Weapon.GUNS:
		var gun := WeaponModels.build(slot, true)
		gun_rack.add_child(gun)
		gun.position = Vector3(0, (3 - slot % 4) * 0.39, -0.65 + (slot / 4) * 1.38)
		gun.rotation.y = -0.16
		for mesh in gun.find_children("*", "GeometryInstance3D", true, false):
			Cel.set_team(mesh, Palette.team(0 if slot < 4 else 1))
	var centre := gun_rack.global_position + Vector3.UP * 0.59
	await _capture("armoury", centre + Vector3(-3.0, 0.22, -0.04), centre, 39)
	gun_rack.hide()

	var equipment := _ground(Vector3(-516, 0, 13))
	game.add_asset(0, BaseAsset.Kind.SENSOR, _ground(equipment + Vector3(0, 0, -1.7)), PI * 0.5)
	game.add_asset(0, BaseAsset.Kind.TURRET, _ground(equipment + Vector3(0, 0, 1.45)), PI * 0.5)
	game.add_station(0, _ground(equipment + Vector3(0, 0, 4.5)))
	await _capture("base-equipment", equipment + Vector3(-8.2, 3.15, 1.0), equipment + Vector3(0.0, 1.0, 1.0), 49)
	var map: GameMap = main.map
	var generator := map.generator_point(0)
	var room := map.base_place(0, 0, 3.5, map.room_floor() + 1.6)
	await _capture("generator-room", room, generator + Vector3.UP * 1.05, 73)


func _ground(at: Vector3) -> Vector3:
	return Vector3(at.x, main.map.surface_at(at.x, at.z) + 0.019, at.z)


func _soldier(team: int, at: Vector3, yaw: float) -> Soldier:
	var soldier: Soldier = main.game.add_soldier(team, Transform3D(Basis(Vector3.UP, yaw), _ground(at)), null, Loadout.standard())
	soldier.grounded = true
	return soldier


func _capture(label: String, eye: Vector3, target: Vector3, fov: float) -> void:
	camera.fov = fov
	camera.look_at_from_position(eye, target)
	for i in 12:
		await RenderingServer.frame_post_draw
	var saved := get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png"))
	assert(saved == OK)
	print("Saved ", label)


func _measure(outlines: bool) -> void:
	Cel.set_outlines(outlines)
	var viewport := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	for i in 40:
		await RenderingServer.frame_post_draw
	var cpu := 0.0
	var gpu := 0.0
	var wall := PackedFloat64Array()
	var last := Time.get_ticks_usec()
	for i in 180:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		wall.append((now - last) / 1000.0)
		last = now
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(viewport)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
	wall.sort()
	print("Outlines %s: %d draws, %d triangles, render CPU %.2f ms, GPU %.2f ms, frame median %.2f ms, p95 %.2f ms" % [
		outlines, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		cpu / wall.size(), gpu / wall.size(), wall[wall.size() / 2], wall[int(wall.size() * 0.95)],
	])
