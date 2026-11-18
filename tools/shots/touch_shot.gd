extends Node

## Takes a picture of the touch controls over the main scene and quits. It
## needs a screen:
##   DISPLAY=:0 ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/touch_shot.tscn
## touch.png is in /srv/downloads/temp/debug/vectorfall.

const FOLDER := "/srv/downloads/temp/debug/vectorfall"


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	# These pictures are of the test map.
	GameMap.chosen = "test"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.input.set_device(LocalInput.Device.TOUCH)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(FOLDER)
	get_viewport().get_texture().get_image().save_png(FOLDER + "/touch.png")
	get_tree().quit()
