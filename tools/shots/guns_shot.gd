extends "res://tools/shots/direction_shot.gd"

## Every gun in your hands for both teams in the paperback palette, and every
## gun from the side, then quits. It needs a screen:
##   DISPLAY=:0 ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/guns_shot.tscn
## Saves m9/guns.png (a row per gun in slot order, team 0 on the left, the
## lower right of the frame as in style-weapons.png) and m9/guns-side.png
## (each gun from its left side, team 0, at the near detail level) in
## /srv/downloads/temp/debug/vectorfall.


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
	DirAccess.make_dir_recursive_absolute(FOLDER + "/m9")
	await _hands()
	await _side()
	get_tree().quit()


## Each gun as ViewModel holds it, at the game's field of view.
func _hands() -> void:
	_camera.fov = 75.0
	_camera.near = 0.05
	_camera.look_at_from_position(Vector3(0.0, 1.7, 9.0), Vector3(2.0, 1.2, -12.0))
	var count := Weapon.GUNS
	var sheet := Image.create(1280, 360 * count, false, Image.FORMAT_RGBA8)
	for slot in count:
		for team in 2:
			var gun := WeaponModels.build(slot, true)
			gun.scale = Vector3.ONE * ViewModel.SCALE
			gun.position = ViewModel.REST
			gun.rotation = Vector3(ViewModel.TIP, ViewModel.TURN, 0.0)
			_camera.add_child(gun)
			for view in gun.find_children("*", "GeometryInstance3D", true, false):
				Cel.set_team(view as GeometryInstance3D, Palette.team(team))
			var frame := await _grab()
			frame.convert(Image.FORMAT_RGBA8)
			var crop := frame.get_region(Rect2i(480, 270, 800, 450))
			crop.resize(640, 360, Image.INTERPOLATE_BILINEAR)
			sheet.blit_rect(crop, Rect2i(0, 0, 640, 360), Vector2i(team * 640, slot * 360))
			gun.queue_free()
	_write(sheet, "m9/guns.png")
	_camera.fov = 62.0


## Every gun from its left side, the sunny one, in two columns against the
## sky: slots 0 to 3 on the left, the rest on the right.
func _side() -> void:
	var holder := Node3D.new()
	holder.position = Vector3(0.0, 30.0, 0.0)
	add_child(holder)
	for slot in Weapon.GUNS:
		var gun := WeaponModels.build(slot, true)
		gun.position = Vector3(0.0, (3 - slot % 4) * 0.4, -0.6 + (slot / 4) * 1.25)
		holder.add_child(gun)
		for view in gun.find_children("*", "GeometryInstance3D", true, false):
			Cel.set_team(view as GeometryInstance3D, Palette.team(0))
	_camera.fov = 40.0
	var middle := holder.position + Vector3(0.0, 0.6, 0.0)
	_camera.look_at_from_position(middle + Vector3(-2.9, 0.3, 0.0), middle)
	await _save("m9/guns-side.png")
	holder.queue_free()
