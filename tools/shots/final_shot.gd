extends "res://tools/shots/direction_shot.gd"

## Pictures of the game's look in the paperback palette for sign-off, then
## quits. It needs a screen:
##   DISPLAY=:0 ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/final_shot.tscn
## Saves in /srv/downloads/temp/debug/skifrei: final-ingame.png (the
## style scene from the dir-2 camera), final-soldiers.png (light, medium and
## heavy of both teams, close, from the front and from behind), final-weapons.png (both guns in your hands
## for both teams) and final-far.png (the six soldiers at 50 m on sand, in
## front of turquoise rock, from their shaded side and against the sky,
## each a 4x crop, top to bottom).


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_noise.seed = 3
	_noise.frequency = 0.05
	_camera = Camera3D.new()
	_camera.fov = 62.0
	_camera.far = 600.0
	add_child(_camera)
	_camera.make_current()
	var palette := Palette.paperback()
	palette.low_height = 0.3
	palette.high_height = 9.0
	await _build(palette)
	_rocks(palette)
	_camera.look_at_from_position(Vector3(0.0, 3.2, 9.0), Vector3(1.0, 2.6, -12.0))
	await _save("final-ingame.png")
	# Each team's three from closer, side by side, from the front and from
	# behind.
	var close := Image.create(1280, 1240, false, Image.FORMAT_RGBA8)
	for team in 2:
		var x := -2.45 if team == 0 else 2.55
		for back in 2:
			var eye := Vector3(x, 1.15, 2.5) if back == 0 else Vector3(x - 1.0, 1.4, -5.0)
			_camera.look_at_from_position(eye, Vector3(x, 0.95, -1.2))
			var frame := await _grab()
			frame.convert(Image.FORMAT_RGBA8)
			close.blit_rect(frame, Rect2i(320, 50, 640, 620), Vector2i(team * 640, back * 620))
	_write(close, "final-soldiers.png")
	await _weapons("final-weapons.png")
	# Only the ground and sky behind them.
	for child in _root.get_children():
		if child is Node3D and not child is StaticBody3D and not child is Atmosphere:
			child.visible = false
	var sheet := Image.create(640, 800, false, Image.FORMAT_RGBA8)
	# On sand, in front of turquoise rock, from the shaded side, and in the
	# air against the sky.
	sheet.blit_rect(await _far(Vector3(-0.25, 0.0, -36.0), Vector3.RIGHT, Vector3(0.0, 0.0, 14.0)), Rect2i(0, 0, 640, 200), Vector2i(0, 0))
	var wall := MeshInstance3D.new()
	wall.mesh = Cel.box(Vector3(30.0, 12.0, 2.0))
	wall.material_override = Cel.material(palette.rock)
	wall.position = Vector3(0.0, _height(0.0, -39.0) + 4.0, -39.0)
	_root.add_child(wall)
	sheet.blit_rect(await _far(Vector3(-0.25, 0.0, -36.0), Vector3.RIGHT, Vector3(0.0, 0.0, 14.0)), Rect2i(0, 0, 640, 200), Vector2i(0, 200))
	wall.queue_free()
	sheet.blit_rect(await _far(Vector3(-55.0, 0.0, -5.0), Vector3.BACK, Vector3(-5.0, 0.0, -5.0)), Rect2i(0, 0, 640, 200), Vector2i(0, 400))
	sheet.blit_rect(await _far(Vector3(-0.25, 22.0, -30.0), Vector3.RIGHT, Vector3(0.0, 0.0, 16.0)), Rect2i(0, 0, 640, 200), Vector2i(0, 600))
	_write(sheet, "final-far.png")
	get_tree().quit()


## The six soldiers in a line through centre along a direction, facing a
## camera at camera_at (on the ground there), seen at the game's field of
## view, cropped and shown at 4x. A centre above the ground puts them in
## the air.
func _far(centre: Vector3, along: Vector3, camera_at: Vector3) -> Image:
	var airborne := centre.y > 0.0
	var to_camera := (camera_at - centre).normalized()
	var facing := atan2(-to_camera.x, -to_camera.z)
	var armours := [SoldierBody.Armour.LIGHT, SoldierBody.Armour.MEDIUM, SoldierBody.Armour.HEAVY]
	var lineup: Array[Soldier] = []
	for team in 2:
		for k in 3:
			var at := centre + along * (-5.25 + team * 6.5 + k * 2.0)
			var soldier := _soldier(team, armours[k], at, facing + (0.5 if team == 0 else -0.5))
			soldier.grounded = not airborne
			lineup.append(soldier)
	for i in 20:
		await get_tree().physics_frame
	for soldier in lineup:
		soldier.blob.follow(soldier)
		soldier.blob.visible = not airborne
	var eye := Vector3(camera_at.x, _height(camera_at.x, camera_at.z) + 1.7, camera_at.z)
	var middle := centre + Vector3.UP * 1.0
	if not airborne:
		middle.y += _height(centre.x, centre.z)
	_camera.fov = 75.0
	_camera.look_at_from_position(eye, middle)
	var frame := await _grab()
	frame.convert(Image.FORMAT_RGBA8)
	var close := frame.get_region(Rect2i(560, 335, 160, 50))
	close.resize(640, 200, Image.INTERPOLATE_NEAREST)
	_camera.fov = 62.0
	for soldier in lineup:
		_soldiers.erase(soldier)
		soldier.queue_free()
	await get_tree().process_frame
	return close
