extends "res://tools/shots/direction_shot.gd"

## The paperback direction (dir-2) with candidate team colour pairs, from
## the same camera, then quits. It needs a screen:
##   DISPLAY=:0 ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/team_shot.tscn
## Saves dir-2a.png, dir-2b.png and dir-2c.png in
## /srv/downloads/temp/debug/vectorfall, plus dir-2-far.png with each pair's
## six soldiers at 50 m, stacked a, b, c. Add letters after -- to take only
## those, or a letter with two colours to try a pair, like -- x=ffd020,2040e0.

## Lime and azure, chartreuse and lavender violet, white and scarlet. Each
## pair is about as far from the sand, turquoise and purple shade as the
## other, and apart in brightness for colour blind players.
const PAIRS := {
	"a": [Color("a0ff40"), Color("2f6bff")],
	"b": [Color("c0ff40"), Color("8066ff")],
	"c": [Color("ffffff"), Color("ff2a3a")],
}


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
	var pairs := {}
	for arg in OS.get_cmdline_user_args():
		if arg.contains("="):
			var parts := arg.split("=")
			var hexes := parts[1].split(",")
			pairs[parts[0]] = [Color(hexes[0]), Color(hexes[1])]
		elif PAIRS.has(arg):
			pairs[arg] = PAIRS[arg]
	if pairs.is_empty():
		pairs = PAIRS
	var far := Image.create(640, 200 * pairs.size(), false, Image.FORMAT_RGBA8)
	var row := 0
	for letter: String in pairs:
		var palette := Palette.paperback()
		palette.team_colours = [pairs[letter][0], pairs[letter][1]]
		palette.low_height = 0.3
		palette.high_height = 9.0
		await _build(palette)
		_rocks(palette)
		_camera.look_at_from_position(Vector3(0.0, 3.2, 9.0), Vector3(1.0, 2.6, -12.0))
		await _save("dir-2%s.png" % letter)
		far.blit_rect(await _far(), Rect2i(0, 0, 640, 200), Vector2i(0, row * 200))
		row += 1
		_root.queue_free()
		await get_tree().process_frame
	_write(far, "dir-2-far.png")
	get_tree().quit()


## The six soldiers 50 m away at the game's field of view, cropped and
## shown at 4x.
func _far() -> Image:
	for soldier in _soldiers:
		soldier.visible = false
	var armours := [SoldierBody.Armour.LIGHT, SoldierBody.Armour.MEDIUM, SoldierBody.Armour.HEAVY]
	var lineup: Array[Soldier] = []
	for team in 2:
		for k in 3:
			var x := -5.5 + team * 6.5 + k * 2.0
			lineup.append(_soldier(team, armours[k], Vector3(x, 0.0, -41.0), PI + (0.5 if team == 0 else -0.5)))
	for i in 20:
		await get_tree().physics_frame
	for soldier in lineup:
		soldier.blob.follow(soldier)
	_camera.fov = 75.0
	_camera.look_at_from_position(Vector3(0.0, _height(0.0, 9.0) + 1.7, 9.0), Vector3(0.0, _height(0.0, -41.0) + 1.0, -41.0))
	var frame := await _grab()
	frame.convert(Image.FORMAT_RGBA8)
	var close := frame.get_region(Rect2i(560, 320, 160, 50))
	close.resize(640, 200, Image.INTERPOLATE_NEAREST)
	_camera.fov = 62.0
	for soldier in lineup:
		soldier.queue_free()
	for soldier in _soldiers:
		soldier.visible = true
	return close
