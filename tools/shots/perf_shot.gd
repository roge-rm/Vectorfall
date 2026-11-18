extends Node

## Measures drawing cost in the main scene with 17 soldiers in view, and
## quits. It needs a screen:
##   DISPLAY=:0 ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/perf_shot.tscn
## On Ochre Fold, the default, you stand in front of team 0's base looking
## down the map with the others spread from 20 to 470 m ahead, and then from
## the spine looking across the middle. Add "test" after -- for the test map,
## with everyone in a fan 12 to 60 m out. The match is paused so every run
## draws the same frame. Prints draw calls, triangles, CPU and GPU frame
## time and terrain chunks drawn per level, with outlines on and off.


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var test := OS.get_cmdline_user_args().has("test")
	GameMap.chosen = "test" if test else "ochre_fold"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var game: Match = main.game
	var map: GameMap = main.map
	for k in 9:
		main.bots.add_bot(k % 2, map.spawn_point(k % 2, k % 8))
	await get_tree().physics_frame
	var player: Soldier = main.player
	var x: float = map.base_x(0) + (24.0 if test else 30.0)
	player.global_position = Vector3(x, map.height_at(x, 0.0) + 0.5, 0.0)
	var soldiers: Array[Soldier] = []
	for entity: Node in game.entities.values():
		if entity is Soldier:
			soldiers.append(entity)
	var k := 0
	for soldier in soldiers:
		if soldier == player:
			continue
		var ahead := 12.0 + k * 3.2
		var side := (k % 5 - 2) * 0.12 * ahead
		if not test:
			ahead = 20.0 + k * 30.0
			side = sin(k * 1.7) * 0.25 * ahead
		var at := Vector3(x + ahead, 0.0, side)
		at.y = map.height_at(at.x, at.z) + 0.5
		soldier.global_position = at
		k += 1
	main.input.source.yaw = -PI * 0.5
	main.input.source.pitch = -0.05
	for i in 20:
		await get_tree().physics_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	main.bots.process_mode = Node.PROCESS_MODE_DISABLED
	print("soldiers: ", soldiers.size(), ", view distance ", Settings.view_distance, " m")
	await _measure("down the map", main.camera, map)
	if not test:
		var camera := Camera3D.new()
		camera.fov = 75.0
		camera.far = Settings.view_distance
		add_child(camera)
		var from := Vector3(-420.0, 0.0, OchreFold.spine_z(-420.0))
		from.y = map.height_at(from.x, from.z) + 2.0
		camera.look_at_from_position(from, Vector3(300.0, 10.0, 200.0))
		camera.make_current()
		await _measure("from the spine", camera, map)
	get_tree().quit()


func _measure(label: String, camera: Camera3D, map: GameMap) -> void:
	var viewport := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	for outlines in [true, false]:
		Cel.set_outlines(outlines)
		for i in 30:
			await get_tree().process_frame
		var cpu := 0.0
		var gpu := 0.0
		var calls := 0
		var triangles := 0
		var frames := 200
		var started := Time.get_ticks_usec()
		for i in frames:
			await RenderingServer.frame_post_draw
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(viewport)
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
			calls = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			triangles = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		print("%s, outlines %s: %d draw calls, %d triangles, render cpu %.2f ms, gpu %.2f ms, frame %.2f ms" % [label, outlines, calls, triangles, cpu / frames, gpu / frames, (Time.get_ticks_usec() - started) / 1000.0 / frames])
	Cel.set_outlines(true)
	if map.terrain != null:
		print("  terrain chunks drawn by level (near to far): ", _chunks_drawn(camera, map.terrain), " of ", map.terrain.chunk_views.size(), ", collision chunks ", map.terrain.active_collision().size())


## How many chunks are drawn at each level: in range and in the view.
func _chunks_drawn(camera: Camera3D, terrain: Terrain) -> Array[int]:
	var counts: Array[int] = []
	counts.resize(Terrain.LOD_STEPS.size())
	var eye := camera.global_position
	var planes := camera.get_frustum()
	for views in terrain.chunk_views:
		for level in views.size():
			var view: MeshInstance3D = views[level]
			var box := view.global_transform * view.get_aabb()
			var d := eye.distance_to(box.get_center())
			if d < view.visibility_range_begin or d >= view.visibility_range_end:
				continue
			var inside := true
			for plane in planes:
				# Outside if every corner is in front of a plane.
				var out := true
				for c in 8:
					if not plane.is_point_over(box.get_endpoint(c)):
						out = false
						break
				if out:
					inside = false
					break
			if inside:
				counts[level] += 1
	return counts
