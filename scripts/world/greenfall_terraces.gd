class_name GreenfallTerraces
extends ArenaMap

const TURN_X := 124.0
const SWEEP := 68.0


func _init() -> void:
	super("Greenfall Terraces", 335.0, 27.0, 88.0, 162, _colours(), Vector2(430, 215),
		["north bank", "switchbacks", "south bank"])


static func _colours() -> Palette:
	var made := Palette.meadow()
	made.title = "Greenfall Terraces"
	made.zenith = Color("55767c")
	made.horizon = Color("d6e3d3")
	made.sky_middle = Color("9bb6ad")
	made.cloud_amount = 0.73
	made.cloud_colour = Color("e3e7de")
	made.cloud_shade = Color("9caeab")
	made.far_range = Color("8fa7a5")
	made.near_range = Color("6b8981")
	made.fog_colour = Color("b8cdc7")
	made.fog_density = 0.0022
	made.sun_colour = Color("f4f4d8")
	made.ambient = Color("a2b9b5")
	made.ambient_energy = 0.54
	made.grass = Color("75944d")
	made.grass_dark = Color("42684c")
	made.dirt = Color("647354")
	made.low = Color("a3a992")
	made.low_height = 9.0
	made.high = Color("8ea15c")
	made.high_height = 23.0
	made.rock = Color("4b5b52")
	made.rock_alt = Color("65776b")
	made.strata = 2.8
	made.patch_colour = Color("9da978")
	made.patch_amount = 0.095
	made.patch_alt_amount = 0.0
	made.variation = 0.21
	made.variation_size = 23.0
	made.structure = Color("c4cdc0")
	return made


func _lane_offsets() -> Vector3:
	return Vector3(-74, 0, 74)


static func _spillway_z(x: float) -> float:
	return SWEEP * cos(PI * x / TURN_X) * (1.0 - smoothstep(176.0, 266.0, absf(x)))


func _land(x: float, z: float) -> float:
	var across := absf(z)
	var from_channel := absf(z - _spillway_z(x))
	var terrace := 23.0 * smoothstep(24.0, 64.0, from_channel)
	var back_slope := 11.0 * smoothstep(76.0, 135.0, from_channel)
	var crest := 19.0 * smoothstep(171.0, 217.0, across) * (1.0 + 0.21 * cos(x * 0.026))
	var join := smoothstep(182.0, 276.0, x)
	var floor := 6.0 + 21.0 * join + 3.2 * cos(x * PI / TURN_X) * (1.0 - join)
	# The low route switches banks twice. The high ground stays open at the edges.
	var banks := (terrace + back_slope) * (1.0 - join)
	var roll := 2.8 * sin(z * 0.051 + x * 0.018) * smoothstep(28.0, 62.0, from_channel)
	return floor + banks + crest + roll


func _dress(parent: Node3D) -> void:
	var concrete := Color("9eaba1")
	var steel := Color("566b61")
	var cap := Color("c1c6ab")
	var channel := _spillway_z(TURN_X)
	for side: float in [-1.0, 1.0]:
		var x := side * TURN_X
		var bed := ground_height(x, channel)
		for bank: float in [-1.0, 1.0]:
			prop(parent, Vector2(x, channel + bank * 18.0), Vector3(5.0, 10.0, 3.4), concrete)
			prop(parent, Vector2(x + side * 6.2, channel + bank * 21.5), Vector3(8.4, 2.8, 3.7), steel, bank * side * 0.34)
			prop(parent, Vector2(side * 186.0, bank * 99.0), Vector3(10.0, 6.2, 6.0), concrete, bank * side * 0.28)
		# The sluice beam leaves the spillway bed clear below it.
		_box(parent, Vector3(5.4, 2.4, 38.0), Transform3D(Basis.IDENTITY, Vector3(x, bed + 10.15, channel)), Cel.material(concrete))
		_box(parent, Vector3(3.8, 0.6, 40.0), Transform3D(Basis.IDENTITY, Vector3(x, bed + 11.58, channel)), Cel.material(cap))
		var warning := MeshInstance3D.new()
		warning.mesh = Cel.box(Vector3(0.18, 0.30, 8.0))
		warning.material_override = Cel.glow(Color("e5b673"))
		warning.position = Vector3(x + side * 2.77, bed + 10.15, channel)
		parent.add_child(warning)


func control_sites() -> Array[Vector2]:
	return [Vector2(0, -97), Vector2(0, -22), Vector2(0, _spillway_z(0))]
