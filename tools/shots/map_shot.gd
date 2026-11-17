extends Node

## Takes a picture of the test map from the player's spawn, looking across
## the map, and quits. It needs a screen:
##   DISPLAY=:0 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/map_shot.tscn
## Saved as /srv/downloads/temp/debug/Vectorfall/map.png. Add "no-outlines"
## after -- for a picture without outlines.

const FOLDER := "/srv/downloads/temp/debug/Vectorfall"


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var outlines := not OS.get_cmdline_user_args().has("no-outlines")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	Cel.set_outlines(outlines)
	# Let the soldiers land, then look a little down across the map.
	for i in 90:
		await get_tree().physics_frame
	main.input.source.pitch = -0.12
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var path := FOLDER + ("/map.png" if outlines else "/map-no-outlines.png")
	get_viewport().get_texture().get_image().save_png(path)
	print("Saved ", path)
	get_tree().quit()
