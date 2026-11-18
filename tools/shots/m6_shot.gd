extends Node

## Pictures of Ochre Fold, and quits. It needs a screen:
##   DISPLAY=:0 ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/m6_shot.tscn
## Saves in /srv/downloads/temp/debug/vectorfall: m6-overview.png (the whole
## map from high up), m6-base.png (team 0's base), m6-skiline.png (in game,
## down the ski line from team 0's base) and m6-far.png (a long view at the
## full view distance, with the fog). The match is paused for each.

const FOLDER := "/srv/downloads/temp/debug/vectorfall"


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	GameMap.chosen = "ochre_fold"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 60:
		await get_tree().physics_frame
	var map: GameMap = main.map
	var game: Match = main.game
	var camera := Camera3D.new()
	camera.fov = 75.0
	camera.far = 4000.0
	add_child(camera)
	camera.make_current()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	main.bots.process_mode = Node.PROCESS_MODE_DISABLED
	main.hud.visible = false
	DirAccess.make_dir_recursive_absolute(FOLDER)

	# The whole map from high over the south edge, without fog.
	map.set_view_distance(4000.0)
	map.atmosphere.environment.fog_density = 0.0002
	camera.fov = 60.0
	camera.look_at_from_position(Vector3(0.0, 1250.0, -1150.0), Vector3(0.0, 0.0, 60.0))
	await _save("m6-overview.png")

	# Team 0's base from the front and above.
	map.set_view_distance(Settings.view_distance)
	camera.fov = 75.0
	var base := Vector3(map.base_x(0), map.deck_height(), 0.0)
	camera.look_at_from_position(base + Vector3(70.0, 30.0, 45.0), base + Vector3(0.0, 4.0, 0.0))
	await _save("m6-base.png")

	# In game, at the top of the first drop, looking down the ski line over
	# the ridges to the far base.
	var player: Soldier = main.player
	var x := map.base_x(0) + 60.0
	player.global_position = Vector3(x, map.height_at(x, 4.0) + 0.1, 4.0)
	player.yaw = -PI * 0.5
	player.pitch = -0.12
	main.camera.make_current()
	main.hud.visible = true
	await _save("m6-skiline.png")

	# A long view from the spine over the middle at the set view distance.
	main.hud.visible = false
	camera.make_current()
	var from := Vector3(-420.0, 0.0, OchreFold.spine_z(-420.0))
	from.y = map.height_at(from.x, from.z) + 12.0
	camera.look_at_from_position(from, Vector3(300.0, 10.0, 200.0))
	await _save("m6-far.png")
	get_tree().quit()


func _save(file: String) -> void:
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := FOLDER + "/" + file
	get_viewport().get_texture().get_image().save_png(path)
	print("Saved ", path)
