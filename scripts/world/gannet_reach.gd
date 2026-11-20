class_name GannetReach
extends ArenaMap

const HEADLAND_HEIGHT := 39.0
const SEA_LEVEL := -4.0
const CONCRETE := Color("969995")
const STEEL := Color("526064")
const SEA := Color("47768b")


func _init() -> void:
	super("Gannet Reach", 382.0, HEADLAND_HEIGHT, 90.0, 295, _colours(), Vector2(485, 245),
		["cliff path", "causeway", "tidal flats"])


static func _colours() -> Palette:
	var made := Palette.paperback()
	made.title = "Gannet Reach"
	made.zenith = Color("50778c")
	made.sky_middle = Color("8daeb9")
	made.horizon = Color("e1d5bf")
	made.sky_ground = Color("a7b1af")
	made.fog_colour = Color("a3b6bc")
	made.fog_density = 0.0017
	made.far_range = Color("8c9da6")
	made.near_range = Color("6a7d85")
	made.near_range_height = 0.08
	made.cloud_amount = 0.38
	made.cloud_colour = Color("f3e6d6")
	made.cloud_shade = Color("a9b7c2")
	made.sun_colour = Color("fff0ce")
	made.ambient = Color("a0b9c6")
	made.shade_colour = Color(Color("63879a"), 0.55)
	made.grass = Color("879384")
	made.grass_dark = Color("757f77")
	made.dirt = Color("ae9d8a")
	made.rock = Color("626773")
	made.rock_alt = Color("80848b")
	made.strata = 3.4
	made.strata_fade_distance = 350.0
	made.low = Color("b7ad9d")
	made.low_height = 7.0
	made.high = Color("acaa95")
	made.high_height = HEADLAND_HEIGHT - 2.0
	made.patch_colour = Color("83918d")
	made.patch_size = 12.0
	made.patch_amount = 0.18
	made.variation_colour = Color("c4ccbf")
	made.variation = 0.28
	made.variation_size = 25.0
	made.structure = Color("c7c6b9")
	made.boulder = Color("727477")
	made.tech_glow = Color("fbe0a0")
	return made


func _lane_offsets() -> Vector3:
	return Vector3(-135.0, 0.0, 117.0)


func _land(x: float, z: float) -> float:
	var flats := 3.2 + 1.7 * cos(x * 0.047 + z * 0.032) * cos(z * 0.078)
	var headland := smoothstep(154.0, 376.0, x)
	var road_centre := 5.0 * (1.0 - cos(x * 0.024))
	var road := 1.0 - smoothstep(21.0, 49.0, absf(z - road_centre))
	var cliff_edge := -108.0 + 16.0 * cos(x * 0.019)
	var cliff := smoothstep(0.0, 58.0, cliff_edge - z)
	var level := flats + (1.0 - headland) * (13.6 * road + 25.0 * cliff)
	level = lerpf(level, HEADLAND_HEIGHT, headland)
	# A dry tidal creek cuts across the seaward flank and ends at the road.
	var creek := (1.0 - smoothstep(10.0, 34.0, x)) * smoothstep(44.0, 105.0, z)
	level -= 8.0 * creek
	# The cliffs curl around the tidal flats beyond the playable bank.
	var shore := 260.0 + 52.0 * smoothstep(117.0, 406.0, x)
	return lerpf(level, -62.0, smoothstep(shore, shore + 41.0, z))


func _dress(parent: Node3D) -> void:
	var road_marks := []
	for side: float in [-1.0, 1.0]:
		for offset: float in [46.0, 101.0, 156.0, 211.0]:
			var x := side * offset
			prop(parent, Vector2(x, -20.0), Vector3(11.2, 1.7, 2.4), CONCRETE, side * 0.05)
			prop(parent, Vector2(x, 23.0), Vector3(11.2, 1.7, 2.4), CONCRETE, side * -0.05)
			var rise := ground_height(x + 2.0, 2.0) - ground_height(x - 2.0, 2.0)
			var tilt := Basis(Vector3.BACK, atan2(rise, 4.0))
			var centre := Vector3(x, ground_height(x, 2.0) + 0.1, 2.0)
			road_marks.append([Cel.box(Vector3(4.0, 0.018, 0.24)),
				Transform3D(tilt, centre), Color(Color("ddd6b4"), 0.0)])
		for z: float in [-24.0, 29.0]:
			prop(parent, Vector2(side * 244.0, z), Vector3(3.5, 8.1, 3.8), STEEL)
			var top := Vector3(side * 244.0, ground_height(side * 244.0, z) + 7.95, z)
			_box(parent, Vector3(3.6, 0.45, 3.9), Transform3D(Basis.IDENTITY, top), Cel.glow(Color("f9dca4")))
		for offset: float in [72.0, 209.0, 287.0]:
			_reef_rock(parent, Vector2(side * offset, 158.0 + 14.0 * sin(offset * 0.031)), 6.0 + offset / 100.0)
			_reef_rock(parent, Vector2(side * offset, -189.0 + 9.0 * cos(offset * 0.042)), 6.0)
	var marks := MeshInstance3D.new()
	marks.mesh = Cel.merged(road_marks)
	marks.material_override = Cel.material(Color.WHITE, 0.0, false, true)
	parent.add_child(marks)
	_open_water(parent)


func _reef_rock(parent: Node3D, at: Vector2, size: float) -> void:
	var centre := Vector3(at.x, ground_height(at.x, at.y) + size * 0.27, at.y)
	_rock(parent, centre, size)
	obstacles.append(Vector3(at.x, at.y, size * 1.2))


func _open_water(parent: Node3D) -> void:
	# The sea starts at the southern boundary, off the playable ground.
	var plane := PlaneMesh.new()
	plane.size = Vector2(4400.0, 2200.0)
	var water := MeshInstance3D.new()
	water.mesh = plane
	water.position = Vector3(0.0, SEA_LEVEL, play_half.y + plane.size.y * 0.5)
	water.material_override = Cel.material(SEA, 0.0, false)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(water)
	var streaks := []
	for row in 9:
		for x in range(-5, 6):
			var along := x * 97.0 + 28.0 * sin(row * 1.6 + x)
			var across := 302.0 + row * 31.0 + 9.0 * cos(x * 1.3 + row)
			var at := Vector3(along, SEA_LEVEL + 0.05, across)
			var size := Vector3(27.0 + 12.0 * cos(x * 2.05 + row), 0.02, 0.44 + row * 0.07)
			var spume := SEA.lerp(Color("a5c1c4"), 0.22 if (x + row) % 3 == 0 else 0.1)
			streaks.append([Cel.box(size), Transform3D(Basis.IDENTITY, at), Color(spume, 0.0)])
	var foam := MeshInstance3D.new()
	foam.mesh = Cel.merged(streaks)
	foam.material_override = Cel.material(Color.WHITE, 0.0, false, true)
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(foam)
