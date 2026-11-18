extends "res://tools/shots/style_shot.gd"

## The style test scene from one camera in today's look and five warmer
## ones, then quits. It needs a screen:
##   DISPLAY=:0 ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/warm_shot.tscn
## Saves warm-0.png (today) to warm-5.png in /srv/downloads/temp/debug/vectorfall:
## 1 golden hour, 2 sepia ink on cream paper, 3 warm shadows, 4 glow from
## fire and energy, 5 sepia with warm shadows.


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_noise.seed = 3
	_noise.frequency = 0.05
	_camera = Camera3D.new()
	_camera.fov = 62.0
	add_child(_camera)
	_camera.make_current()
	var looks: Array[Palette] = [
		Palette.desert(),
		Palette.desert_golden_hour(),
		Palette.desert().sepia(),
		Palette.desert().warm_shadows(),
		Palette.desert(),
		Palette.desert().sepia().warm_shadows(),
	]
	for k in looks.size():
		var palette := looks[k]
		palette.low_height = 0.3
		palette.high_height = 9.0
		await _build(palette)
		if k == 4:
			_glows()
		_camera.look_at_from_position(Vector3(0.0, 3.2, 9.0), Vector3(1.0, 2.6, -12.0))
		await _save("warm-%d.png" % k)
		Cel.clear_glows()
		_root.queue_free()
		await get_tree().process_frame
	get_tree().quit()


## Glow from the blast, the jet, the disc and the chaingun's muzzle.
func _glows() -> void:
	var at := Vector3(17.0, _height(17.0, -27.0) + 1.0, -27.0)
	Cel.set_glow(0, at, 14.0, Color(1.0, 0.5, 0.15, 1.0))
	for soldier in _soldiers:
		if soldier.jetting:
			Cel.set_glow(1, soldier.body.flame.global_position, 9.0, Color(1.0, 0.6, 0.2, 0.9))
		elif soldier.spin > 0.0:
			Cel.set_glow(2, soldier.position + Vector3(-0.9, 1.4, -0.1), 5.0, Color(1.0, 0.72, 0.3, 0.8))
	Cel.set_glow(3, Vector3(1.5, 1.7, -11.5), 6.0, Color(1.0, 0.68, 0.3, 0.7))
