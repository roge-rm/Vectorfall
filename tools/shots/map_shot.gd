extends Node

## Takes a picture of the test map from just in front of the player's base,
## looking down the valley to the other base, and quits. It needs a screen:
##   DISPLAY=:0 ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/map_shot.tscn
## Saved as /srv/downloads/temp/debug/vectorfall/map.png. Add "no-outlines"
## after -- for a picture without outlines.

const FOLDER := "/srv/downloads/temp/debug/vectorfall"


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var outlines := not OS.get_cmdline_user_args().has("no-outlines")
	# These pictures are of the test map.
	GameMap.chosen = "test"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	Cel.set_outlines(outlines)
	# Stand at the foot of the base's ramp, let the soldiers land, then look a
	# little down across the map.
	var map: TestMap = main.map
	var x := map.base_x(0) + 24.0
	main.player.global_position = Vector3(x, map.height_at(x, 0.0) + 0.5, 0.0)
	for i in 90:
		await get_tree().physics_frame
	main.input.source.pitch = -0.1
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var path := FOLDER + ("/map.png" if outlines else "/map-no-outlines.png")
	get_viewport().get_texture().get_image().save_png(path)
	print("Saved ", path)
	get_tree().quit()
