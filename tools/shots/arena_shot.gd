extends Node

const FOLDER := "/srv/downloads/temp/debug/vectorfall/m13"
const MAPS: Array[String] = ["saltwake_flats", "nightline_foundry", "copper_steps"]


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var folder := OS.get_environment("VECTORFALL_SHOT_DIR")
	if folder.is_empty():
		folder = FOLDER
	DirAccess.make_dir_recursive_absolute(folder)
	Settings.path = "user://arena-shot.cfg"
	var requested := OS.get_cmdline_user_args()
	if requested.is_empty():
		requested = PackedStringArray(MAPS)
	for selected in requested:
		if not GameMap.NAMES.has(selected):
			push_error("No such map: " + selected)
			get_tree().quit(1)
			return
		MatchSetup.current = MatchSetup.new()
		MatchSetup.current.map = selected
		MatchSetup.current.own_bots = 0
		MatchSetup.current.enemy_bots = 0
		var main: Node = load("res://scenes/main.tscn").instantiate()
		add_child(main)
		main.hud.hide()
		main.player.hide()
		var map: GameMap = main.map
		var camera := Camera3D.new()
		camera.far = Settings.view_distance
		camera.fov = 64.0
		main.add_child(camera)
		var eye := Vector3(map.base_x(0) + 54.0, map.base_ground + 50.0, -map.spawn_side * 0.62)
		var target := Vector3(0.0, map.ground_height(0, 0) + 3.0, 0.0)
		match selected:
			"nightline_foundry":
				eye = Vector3(-118.0, 44.0, -105.0)
				target = Vector3(19.0, 14.0, 12.0)
			"copper_steps":
				eye = Vector3(-410, 148, 187)
				target = Vector3(-286, 69, 83)
			"caldera_relay":
				eye = Vector3(-266, 158, -152)
				target = Vector3(20, 6, 57)
			"gannet_reach":
				eye = Vector3(-245, 163, -132)
				target = Vector3(25, 12, 153)
			"white_signal":
				eye = Vector3(-161, 65, -60)
				target.y += 10.0
			"glass_ravine":
				eye = Vector3(-158, 95, -104)
				target.y += 18.0
			"greenfall_terraces":
				eye = Vector3(-159, 84, -80)
				target.y += 10.0
			"beacon_wreck":
				eye = Vector3(-168, 72, -91)
				target.y += 10.0
		camera.look_at_from_position(eye, target)
		camera.make_current()
		for i in 20:
			await RenderingServer.frame_post_draw
		var saved := get_viewport().get_texture().get_image().save_png(folder.path_join(selected + ".png"))
		if saved != OK:
			get_tree().quit(1)
			return
		main.queue_free()
		await get_tree().process_frame
	get_tree().quit()
