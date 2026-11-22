extends "res://tools/shots/direction_shot.gd"

## Soldiers with each pack, shields and jammers on, hand grenades and mines,
## in the paperback palette, then quits. It needs a screen:
##   DISPLAY=:0 ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/packs_shot.tscn
## Saves in /srv/downloads/temp/debug/skifrei/m9: packs.png (top to
## bottom: lime mediums from behind with repair, shield, energy, ammo and
## jammer packs; blue light, medium, heavy, light and heavy with the same;
## shields and jammers on, both teams, from the front and behind) and
## mines.png (mines of both teams lit and dark with hand grenades in the air
## close up, then the same from 8 m).

const PACK_NAMES: Array[String] = ["repair", "shield", "energy", "ammo", "jammer"]

var _lineup: Array[Soldier] = []


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
	# Only the ground and sky.
	for child in _root.get_children():
		if child is Node3D and not child is StaticBody3D and not child is Atmosphere:
			child.visible = false
	DirAccess.make_dir_recursive_absolute(FOLDER + "/m9")
	var sheet := Image.create(1280, 2160, false, Image.FORMAT_RGBA8)
	var armours: Array[int] = [SoldierBody.Armour.MEDIUM, SoldierBody.Armour.MEDIUM, SoldierBody.Armour.MEDIUM, SoldierBody.Armour.MEDIUM, SoldierBody.Armour.MEDIUM]
	_line(0, armours, [0, 1, 2, 3, 4], [false, false, false, false, false])
	sheet.blit_rect(await _from_behind(), Rect2i(0, 0, 1280, 720), Vector2i(0, 0))
	armours = [SoldierBody.Armour.LIGHT, SoldierBody.Armour.MEDIUM, SoldierBody.Armour.HEAVY, SoldierBody.Armour.LIGHT, SoldierBody.Armour.HEAVY]
	_line(1, armours, [0, 1, 2, 3, 4], [false, false, false, false, false])
	sheet.blit_rect(await _from_behind(), Rect2i(0, 0, 1280, 720), Vector2i(0, 720))
	# Shields and jammers on: lime medium shield, lime light jammer, blue
	# heavy shield, blue medium jammer, half from the front.
	var on := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	armours = [SoldierBody.Armour.MEDIUM, SoldierBody.Armour.LIGHT, SoldierBody.Armour.HEAVY, SoldierBody.Armour.MEDIUM]
	_line(0, armours, [Pack.SHIELD, Pack.JAMMER, Pack.SHIELD, Pack.JAMMER], [true, true, true, true])
	_lineup[2].set_team(1)
	_lineup[3].set_team(1)
	for i in 6:
		await get_tree().process_frame
	_camera.look_at_from_position(Vector3(0.8, 1.4, -5.6), Vector3(0.0, 1.0, -1.5))
	var front := await _grab()
	front.convert(Image.FORMAT_RGBA8)
	on.blit_rect(front, Rect2i(320, 0, 640, 720), Vector2i(0, 0))
	var back := await _from_behind()
	on.blit_rect(back, Rect2i(320, 0, 640, 720), Vector2i(640, 0))
	sheet.blit_rect(on, Rect2i(0, 0, 1280, 720), Vector2i(0, 1440))
	_write(sheet, "m9/packs.png")
	_clear()
	await _mines()
	get_tree().quit()


## A row of soldiers facing -z, about 1.3 m apart round x = 0, z = -1.5.
func _line(team: int, armours: Array[int], packs: Array, switched_on: Array) -> void:
	_clear()
	var count := armours.size()
	for k in count:
		var x := (k - (count - 1) * 0.5) * 1.35
		var soldier := _soldier(team, armours[k] as SoldierBody.Armour, Vector3(x, 0.0, -1.5), 0.0)
		soldier.set_loadout(Loadout.make(armours[k], [Weapon.DISC, Weapon.CHAINGUN], packs[k]))
		soldier.pack_on = switched_on[k]
		soldier.blob.follow(soldier)
		_lineup.append(soldier)


func _clear() -> void:
	for soldier in _lineup:
		_soldiers.erase(soldier)
		soldier.queue_free()
	_lineup.clear()


## The row from behind and a little to the left and above.
func _from_behind() -> Image:
	for i in 6:
		await get_tree().process_frame
	_camera.look_at_from_position(Vector3(-1.0, 1.7, 2.1), Vector3(0.0, 1.0, -1.5))
	var frame := await _grab()
	frame.convert(Image.FORMAT_RGBA8)
	return frame


## Mines on the ground and hand grenades in the air, as ProjectileView draws
## them, close up and from 8 m.
func _mines() -> void:
	var holder := Node3D.new()
	_root.add_child(holder)
	var inked := Cel.material(Color.WHITE, 1.0, true, true, false, false, true)
	for team in 2:
		for lit in 2:
			var x := -1.2 + team * 1.6 + lit * 0.8
			var z := -1.0 - lit * 0.3
			var at := Vector3(x, _height(x, z) - 0.04, z)
			var mine := MeshInstance3D.new()
			mine.mesh = ProjectileView.mine_mesh()
			mine.material_override = inked
			mine.position = at
			mine.rotation.y = 0.4 * (team + lit)
			holder.add_child(mine)
			Cel.set_team(mine, Palette.team(team))
			if lit == 1:
				var light := MeshInstance3D.new()
				light.mesh = Cel.sphere(0.045, 0.06, 8)
				light.material_override = Cel.glow(Palette.team(team).lightened(0.3))
				light.position = at + Vector3(0.0, 0.12, 0.0)
				holder.add_child(light)
	for k in 2:
		var grenade := MeshInstance3D.new()
		grenade.mesh = ProjectileView.hand_grenade_mesh()
		grenade.material_override = inked
		grenade.position = Vector3(-0.5 + k * 1.2, _height(0.0, -1.0) + 0.6 + k * 0.2, -1.4)
		grenade.rotation = Vector3(0.6 * k, 0.8, 0.3)
		holder.add_child(grenade)
	var sheet := Image.create(1280, 1440, false, Image.FORMAT_RGBA8)
	var ground := _height(0.0, -1.0)
	_camera.look_at_from_position(Vector3(0.0, ground + 1.3, 1.2), Vector3(0.0, ground + 0.2, -1.2))
	var near := await _grab()
	near.convert(Image.FORMAT_RGBA8)
	sheet.blit_rect(near, Rect2i(0, 0, 1280, 720), Vector2i(0, 0))
	_camera.fov = 75.0
	_camera.look_at_from_position(Vector3(0.0, ground + 1.7, 7.0), Vector3(0.0, ground + 0.2, -1.2))
	var far := await _grab()
	far.convert(Image.FORMAT_RGBA8)
	sheet.blit_rect(far, Rect2i(0, 0, 1280, 720), Vector2i(0, 720))
	_write(sheet, "m9/mines.png")
