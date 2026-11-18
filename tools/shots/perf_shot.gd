extends Node

## Measures drawing cost in the main scene with 16 soldiers in view, and
## quits. It needs a screen:
##   DISPLAY=:0 ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/perf_shot.tscn
## The match is paused so every run draws the same frame. Prints draw calls
## and CPU and GPU frame time with outlines on and off, and with hatching on
## and off where the game has it.


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var game: Match = main.game
	for k in 9:
		main.bots.add_bot(k % 2, main.map.spawn_point(k % 2, k % 8))
	await get_tree().physics_frame
	# Stand everyone in a fan in front of the player, 12 to 60 m out.
	var player: Soldier = main.player
	var x: float = main.map.base_x(0) + 24.0
	player.global_position = Vector3(x, main.map.height_at(x, 0.0) + 0.5, 0.0)
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
		var at := Vector3(x + ahead, 0.0, side)
		at.y = main.map.height_at(at.x, at.z) + 0.5
		soldier.global_position = at
		k += 1
	main.input.source.yaw = -PI * 0.5
	main.input.source.pitch = -0.05
	for i in 20:
		await get_tree().physics_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	main.bots.process_mode = Node.PROCESS_MODE_DISABLED
	var viewport := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	print("soldiers: ", soldiers.size())
	var cel: GDScript = load("res://scripts/world/cel.gd")
	var has_hatching := cel.get_script_method_list().any(func(m: Dictionary) -> bool: return m.name == "set_hatching")
	for outlines in [true, false]:
		Cel.set_outlines(outlines)
		for hatching in ([true, false] if has_hatching else [true]):
			if has_hatching:
				cel.call("set_hatching", hatching)
			for i in 30:
				await get_tree().process_frame
			var cpu := 0.0
			var gpu := 0.0
			var calls := 0
			var frames := 200
			var started := Time.get_ticks_usec()
			for i in frames:
				await RenderingServer.frame_post_draw
				cpu += RenderingServer.viewport_get_measured_render_time_cpu(viewport)
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
				calls = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			print("outlines %s hatching %s: %d draw calls, render cpu %.2f ms, gpu %.2f ms, frame %.2f ms" % [outlines, hatching, calls, cpu / frames, gpu / frames, (Time.get_ticks_usec() - started) / 1000.0 / frames])
	get_tree().quit()
