extends "res://tools/shots/style_shot.gd"

## The style test scene from one camera in five art directions, each with
## its own light, shade, ground, sky and lines, then quits. It needs a
## screen:
##   DISPLAY=:0 ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/direction_shot.tscn
## Saves dir-1.png to dir-5.png in /srv/downloads/temp/debug/vectorfall:
## 1 warm sun and cool shade, 2 retro sci-fi paperback, 3 lush painterly,
## 4 flat travel poster, 5 neon frontier at dusk. Add numbers after -- to
## take only those, like -- 2 5.


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
	var looks: Array[Palette] = [
		Palette.sun_and_shade(),
		Palette.paperback(),
		Palette.meadow(),
		Palette.travel_poster(),
		Palette.neon_frontier(),
	]
	var only := OS.get_cmdline_user_args()
	for k in looks.size():
		if not only.is_empty() and not only.has(str(k + 1)):
			continue
		var palette := looks[k]
		palette.low_height = 0.3
		palette.high_height = 9.0
		await _build(palette)
		_rocks(palette)
		if palette.tech_glow.a > 0.0:
			_tech_lights(palette)
		if k == 4:
			_neon_glows()
		_camera.look_at_from_position(Vector3(0.0, 3.2, 9.0), Vector3(1.0, 2.6, -12.0))
		await _save("dir-%d.png" % (k + 1))
		Cel.clear_glows()
		_root.queue_free()
		await get_tree().process_frame
	get_tree().quit()


## A few more rocks in the boulder colour and the second rock colour.
func _rocks(palette: Palette) -> void:
	var colours := [palette.boulder, palette.rock_alt]
	var spots: Array[Vector3] = [Vector3(-9.0, 0.0, -6.0), Vector3(11.0, 0.0, -3.0), Vector3(4.5, 0.0, -24.0), Vector3(-2.0, 0.0, -40.0), Vector3(30.0, 0.0, -48.0), Vector3(-12.0, 0.0, 2.0), Vector3(14.0, 0.0, -30.0)]
	for k in spots.size():
		var at := spots[k]
		var view := MeshInstance3D.new()
		var size := 0.8 + float(k % 3) * 0.7
		view.mesh = Cel.sphere(size, size * 1.3, 6) if k % 2 == 0 else Cel.box(Vector3(size * 1.6, size, size * 1.2))
		view.material_override = Cel.material(colours[k % 2])
		view.position = Vector3(at.x, _height(at.x, at.z) + size * 0.3, at.z)
		view.rotation = Vector3(0.2 * (k % 3), at.x, 0.15)
		_root.add_child(view)


## Light strips along the base's deck and tower.
func _tech_lights(palette: Palette) -> void:
	var light := Cel.glow(Color(palette.tech_glow, 1.0))
	_strip(Vector3(16.2, 0.18, 0.18), Vector3(-18.0, 1.6, -14.95), light)
	_strip(Vector3(0.18, 0.18, 14.2), Vector3(-9.95, 1.6, -22.0), light)
	_strip(Vector3(0.18, 9.0, 0.18), Vector3(-20.2, 8.0, -24.2), light)
	_strip(Vector3(8.2, 0.16, 0.16), Vector3(-22.0, 14.0, -21.95), light)


func _strip(size: Vector3, at: Vector3, material: Material) -> void:
	var view := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	view.mesh = mesh
	view.material_override = material
	view.position = at
	_root.add_child(view)


## Cyan from energy (disc, chaingun, base lights) and magenta from jets and
## the blast.
func _neon_glows() -> void:
	var at := Vector3(17.0, _height(17.0, -27.0) + 1.0, -27.0)
	Cel.set_glow(0, at, 16.0, Color(1.0, 0.3, 0.75, 1.0))
	for soldier in _soldiers:
		if soldier.jetting:
			Cel.set_glow(1, soldier.body.flame.global_position, 10.0, Color(1.0, 0.25, 0.8, 1.0))
	Cel.set_glow(2, Vector3(1.5, 1.7, -11.5), 9.0, Color(0.0, 0.9, 1.0, 1.0))
	Cel.set_glow(3, Vector3(-12.0, 2.0, -16.0), 12.0, Color(0.2, 0.95, 1.0, 0.9))
