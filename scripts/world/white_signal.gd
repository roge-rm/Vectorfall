class_name WhiteSignal
extends ArenaMap

const TUNNEL_HALF := 66.0
const TUNNEL_WALL := 16.0
const TUNNEL_FLOOR := 23.0
const FRAME := Color("364959")
const LINER := Color("657e8a")
const SNOW := Color("e2e9e9")
const MARK := Color("cf9458")


func _init() -> void:
	super("White Signal", 318.0, 56.0, 102.0, 726, _colours(), Vector2(418.0, 253.0),
		["north cornice", "signal tunnel", "south snowfield"])


static func _colours() -> Palette:
	var made := Palette.highland()
	made.title = "White Signal"
	made.zenith = Color("67829d")
	made.horizon = Color("e2e7ed")
	made.sky_middle = Color("aec6d5")
	made.sky_middle_height = 0.38
	made.sky_ground = Color("b4c0cf")
	made.far_range = Color("a4adc1")
	made.far_range_height = 0.24
	made.near_range = Color("788ba3")
	made.near_range_height = 0.16
	made.sun_direction = Vector3(-0.45, 0.73, 0.51)
	made.sun_colour = Color("fff3e8")
	made.fog_colour = Color("c7d4e1")
	made.fog_density = 0.0021
	made.shade_mid = 0.65
	made.shade_dark = 0.44
	made.shade_colour = Color(0.34, 0.48, 0.66, 0.42)
	made.hatching = false
	made.line_brush = 0.0
	made.grit = 0.012
	made.grass = SNOW
	made.grass_dark = Color("c9d9df")
	made.dirt = Color("a6b7c8")
	made.rock = Color("5e6e87")
	made.rock_alt = Color("76859a")
	made.strata = 4.8
	made.strata_fade_distance = 310.0
	made.high = Color("f2f3f0")
	made.high_height = 73.0
	made.patch_colour = Color("b7cbd7")
	made.patch_size = 12.0
	made.patch_amount = 0.13
	made.variation_colour = Color("bdcddd")
	made.variation = 0.23
	made.variation_size = 27.0
	made.structure = Color("aab9c4")
	made.boulder = Color("76849a")
	return made


func _lane_offsets() -> Vector3:
	return Vector3(-112.0, 0.0, 112.0)


func _land(x: float, z: float) -> float:
	var across := absf(z)
	var base_rise := 33.0 * smoothstep(96.0, 310.0, x)
	var shelter := 1.0 - smoothstep(54.0, 112.0, x)
	var ridge := smoothstep(16.0, 47.0, across) * (1.0 - smoothstep(53.0, 94.0, across))
	var roll := (4.0 + 3.5 * cos(x * 0.038 + z * 0.012)) * smoothstep(22.0, 85.0, across)
	var mountain_edge := 151.0 + 18.0 * cos(x * 0.020 + z * 0.017)
	var mountain := smoothstep(mountain_edge, mountain_edge + 101.0, across)
	var height := 88.0 + 27.0 * cos(x * 0.026 + z * 0.021) + 16.0 * sin(x * 0.047)
	# The north flank climbs a wind-scoured crest. The south stays open for skiing.
	var cornice := (1.0 - smoothstep(16.0, 56.0, absf(z + 118.0))) * (1.0 - smoothstep(35.0, 124.0, x))
	return TUNNEL_FLOOR + base_rise + shelter * ridge * 29.0 + roll + mountain * height + 32.0 * cornice


func blocked_at(x: float, z: float) -> bool:
	# The walls are thin and parallel to the tunnel lane.
	if absf(x) < TUNNEL_HALF + 3.0 and absf(absf(z) - TUNNEL_WALL) < 3.5:
		return true
	return super(x, z)


func _dress(parent: Node3D) -> void:
	var ceiling := TUNNEL_FLOOR + 10.0
	var length := TUNNEL_HALF * 2.0
	_box(parent, Vector3(length, 1.7, 39.0),
		Transform3D(Basis.IDENTITY, Vector3(0, ceiling, 0)), Cel.material(FRAME))
	_box(parent, Vector3(length - 6.0, 1.8, 37.0),
		Transform3D(Basis.IDENTITY, Vector3(0, ceiling + 1.72, 0)), Cel.material(SNOW))
	var panels := []
	var lamps := []
	for side: float in [-1.0, 1.0]:
		_box(parent, Vector3(length, 12.0, 2.5),
			Transform3D(Basis.IDENTITY, Vector3(0, ceiling - 5.3, side * TUNNEL_WALL)), Cel.material(LINER))
		for z: float in [-1.0, 1.0]:
			var portal := Vector3(side * TUNNEL_HALF, ceiling - 5.4, z * TUNNEL_WALL)
			_box(parent, Vector3(3.4, 11.9, 4.5), Transform3D(Basis.IDENTITY, portal), Cel.material(FRAME))
			_detail(panels, Vector3(0.12, 5.8, 0.65), portal + Vector3(side * 1.76, 0.6, -z * 0.85), MARK)
			prop(parent, Vector2(side * 128.0, z * 61.0), Vector3(9.0, 4.2, 3.5), LINER, side * z * 0.24)
			prop(parent, Vector2(side * 209.0, z * 150.0), Vector3(4.2, 3.6, 7.0), FRAME, side * z * -0.33)
		var lintel := Vector3(side * TUNNEL_HALF, ceiling + 0.42, 0)
		_box(parent, Vector3(3.4, 2.65, 36.0), Transform3D(Basis.IDENTITY, lintel), Cel.material(FRAME))
		_detail(panels, Vector3(0.12, 0.48, 24.0), lintel + Vector3(side * 1.76, 0.39, 0), MARK)
		_detail(lamps, Vector3(0.28, 0.12, 22.0), lintel + Vector3(0, -1.38, 0), Color.WHITE)
		_signal(parent, side * 47.0, ceiling + 2.62, panels, lamps)
	for x: float in [-50.0, -25.0, 0.0, 25.0, 50.0]:
		_detail(panels, Vector3(0.8, 0.25, 30.0), Vector3(x, ceiling - 0.88, 0), LINER)
		_detail(lamps, Vector3(0.64, 0.1, 9.0), Vector3(x, ceiling - 1.05, 0), Color.WHITE)
	_details_view(parent, panels, Cel.material(Color.WHITE, 0.0, false, true))
	_details_view(parent, lamps, Cel.glow(Color("ffe4b3")))


func _signal(parent: Node3D, x: float, y: float, panels: Array, lamps: Array) -> void:
	var at := Vector3(x, y, 0)
	_box(parent, Vector3(5.0, 1.4, 5.0), Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.7), Cel.material(FRAME))
	_box(parent, Vector3(1.8, 14.0, 1.8), Transform3D(Basis.IDENTITY, at + Vector3.UP * 7.0), Cel.material(LINER))
	_box(parent, Vector3(6.8, 1.0, 1.8), Transform3D(Basis.IDENTITY, at + Vector3.UP * 10.5), Cel.material(FRAME))
	_detail(panels, Vector3(2.3, 0.75, 2.3), at + Vector3.UP * 13.9, MARK)
	_detail(lamps, Vector3(1.2, 1.3, 1.2), at + Vector3.UP * 14.9, Color.WHITE)


static func _detail(parts: Array, size: Vector3, at: Vector3, colour: Color) -> void:
	parts.append([Cel.box(size), Transform3D(Basis.IDENTITY, at), Color(colour, 0.0)])


static func _details_view(parent: Node3D, parts: Array, material: Material) -> void:
	var view := MeshInstance3D.new()
	view.mesh = Cel.merged(parts)
	view.material_override = material
	parent.add_child(view)


func control_sites() -> Array[Vector2]:
	return [Vector2(0, -112), Vector2.ZERO, Vector2(0, 112)]
