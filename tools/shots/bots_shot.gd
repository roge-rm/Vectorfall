extends Node

## Takes a picture of the bots on their routes with the F3 overlay on, from
## high above team 0's base looking along the map, and quits. It needs a
## screen:
##   DISPLAY=:0 ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/bots_shot.tscn
## Saved as /srv/downloads/temp/debug/skifrei/bots.png. A number after --
## is the seconds to let the bots run first (12).

const FOLDER := "/srv/downloads/temp/debug/skifrei"


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var args := OS.get_cmdline_user_args()
	var seconds := float(args[0]) if not args.is_empty() else 12.0
	# These pictures are of the test map.
	GameMap.chosen = "test"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.overlay.visible = true
	var camera := Camera3D.new()
	camera.far = 2000.0
	add_child(camera)
	camera.look_at_from_position(Vector3(-265.0, 95.0, 70.0), Vector3(-20.0, -25.0, 0.0))
	camera.make_current()
	while main.game.tick < int(seconds * 60.0):
		await get_tree().physics_frame
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var path := FOLDER + "/bots.png"
	get_viewport().get_texture().get_image().save_png(path)
	print("Saved ", path)
	get_tree().quit()
