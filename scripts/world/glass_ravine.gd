class_name GlassRavine
extends ArenaMap

const BRIDGE_X := 84.0
const BRIDGE_BANK := 96.0
const BRIDGE_TIP := 20.0
const SPAN_BANK := 84.0
const SPAN_DECK := 54.0
const BRIDGE_FRAME := Color("394758")
const BRIDGE_DECK := Color("8f929c")
const BRIDGE_MARK := Color("ecb98e")


func _init() -> void:
	super("Glass Ravine", 324.0, 39.0, 87.0, 138, _colours(), Vector2(424.0, 206.0),
		["north ledge", "ravine floor", "south ledge"])


static func _colours() -> Palette:
	var made := Palette.paperback()
	made.title = "Glass Ravine"
	made.zenith = Color("3e7487")
	made.horizon = Color("f3d6b7")
	made.sky_middle = Color("93bab6")
	made.sky_middle_height = 0.37
	made.sky_ground = Color("9eb6ad")
	made.far_range = Color("7a979d")
	made.near_range = Color("557d85")
	made.far_range_height = 0.22
	made.near_range_height = 0.12
	made.sun_direction = Vector3(-0.42, 0.78, 0.46)
	made.sun_colour = Color("fff0ce")
	made.ambient = Color("83babe")
	made.ambient_energy = 0.54
	made.shade_dark = 0.43
	made.shade_colour = Color(0.22, 0.39, 0.52, 0.42)
	made.fog_colour = Color("aac6bc")
	made.fog_density = 0.0019
	made.ink = Color("172832")
	made.line_width = 1.18
	made.grass = Color("80b5a3")
	made.grass_dark = Color("6a9e94")
	made.dirt = Color("719991")
	made.rock = Color("317b81")
	made.rock_alt = Color("569c97")
	made.strata = 6.0
	made.strata_fade_distance = 340.0
	made.low = Color("abccba")
	made.low_height = 14.0
	made.high = Color("8ab9a7")
	made.high_height = 44.0
	made.patch_colour = Color("96bab0")
	made.patch_size = 9.0
	made.patch_amount = 0.16
	made.variation_colour = Color("a5d2c0")
	made.variation_size = 29.0
	made.variation = 0.3
	made.structure = Color("b2b9bd")
	made.boulder = Color("4c8287")
	return made


func _lane_offsets() -> Vector3:
	return Vector3(-104.0, 0.0, 104.0)


func _land(x: float, z: float) -> float:
	var across := absf(z)
	var floor_y := 7.0 + 5.0 * smoothstep(19.0, 155.0, x) + 1.4 * cos(x * 0.029) * cos(z * 0.044)
	var climb := 1.0 - smoothstep(10.0, 46.0, absf(x - 154.0))
	var wall_edge := 35.0 + 7.0 * cos(x * 0.028 + z * 0.018) - climb * 15.0
	var wall_width := 37.0 + climb * 31.0
	var wall := smoothstep(wall_edge, wall_edge + wall_width, across)
	var shelf := 44.0 + 4.0 * sin(x * 0.024 + z * 0.009) - climb * 7.0
	var end_ramp := smoothstep(190.0, 292.0, x)
	var canyon := lerpf(floor_y + wall * shelf, 39.0 + wall * 4.0, end_ramp)
	var outer_edge := 133.0 + 13.0 * cos(x * 0.027 + z * 0.023)
	var outer_wall := smoothstep(outer_edge, outer_edge + 68.0, across)
	var ledge := canyon + outer_wall * (52.0 + 16.0 * cos(x * 0.029 - z * 0.024))
	var landing := (1.0 - smoothstep(6.0, 34.0, x)) * (1.0 - smoothstep(8.0, 25.0, absf(across - SPAN_BANK)))
	return lerpf(ledge, SPAN_DECK, landing)


func blocked_at(x: float, z: float) -> bool:
	# Ground routes go round the deck, rails and braces on each bank.
	var across := absf(z)
	if absf(absf(x) - BRIDGE_X) < 7.0 and across > BRIDGE_TIP - 7.0 and across < BRIDGE_BANK + 1.0:
		return true
	if absf(x) < 8.0 and across > 42.0 and across < SPAN_BANK - 8.0:
		return true
	return super(x, z)


func _routes() -> RouteGraph:
	var graph := super()
	for direction: float in [-1.0, 1.0]:
		for side: float in [-1.0, 1.0]:
			var x := direction * 112.0
			var z := side * 112.0
			var ledge := graph.nearest(Vector3(x, surface_at(x, z), z))
			graph.add_interest(RouteGraph.HIGH_GROUND, -1, ledge)
	var north := graph.nearest(Vector3(0, SPAN_DECK, -SPAN_BANK))
	var south := graph.nearest(Vector3(0, SPAN_DECK, SPAN_BANK))
	var previous := north
	for z: float in [-56.0, -28.0, 0.0, 28.0, 56.0]:
		var point := graph.add_point(Vector3(0, SPAN_DECK, z))
		graph.add_link(previous, point, RouteGraph.Kind.RUN)
		graph.add_link(point, previous, RouteGraph.Kind.RUN)
		previous = point
	graph.add_link(previous, south, RouteGraph.Kind.RUN)
	graph.add_link(south, previous, RouteGraph.Kind.RUN)
	return graph


func _dress(parent: Node3D) -> void:
	var details := []
	_service_span(parent, details)
	for direction: float in [-1.0, 1.0]:
		for side: float in [-1.0, 1.0]:
			_bridge_stub(parent, direction * BRIDGE_X, side, details)
			prop(parent, Vector2(direction * 47.0, side * 31.0), Vector3(9.6, 3.1, 4.3), BRIDGE_FRAME, direction * side * 0.26)
			prop(parent, Vector2(direction * 194.0, side * 46.0), Vector3(7.0, 4.6, 3.8), BRIDGE_DECK, -direction * side * 0.37)
			prop(parent, Vector2(direction * 143.0, side * 124.0), Vector3(10.0, 4.2, 4.8), BRIDGE_FRAME, -direction * side * 0.2)
	var view := MeshInstance3D.new()
	view.mesh = Cel.merged(details)
	view.material_override = Cel.material(Color.WHITE, 0.0, false, true)
	parent.add_child(view)


func _service_span(parent: Node3D, details: Array) -> void:
	# The intact span lets a carrier change ledges above the canyon floor.
	var centre := Vector3(0.0, SPAN_DECK - 0.9, 0.0)
	_box(parent, Vector3(13.0, 1.8, SPAN_BANK * 2.0), Transform3D(Basis.IDENTITY, centre), Cel.material(BRIDGE_DECK))
	for edge: float in [-1.0, 1.0]:
		var at := centre + Vector3(edge * 6.0, -1.35, 0.0)
		_box(parent, Vector3(0.85, 1.35, SPAN_BANK * 2.0), Transform3D(Basis.IDENTITY, at), Cel.material(BRIDGE_FRAME))
		for z: float in [-64.0, -32.0, 0.0, 32.0, 64.0]:
			_detail(details, Vector3(0.36, 0.03, 13.0), Vector3(edge * 5.85, SPAN_DECK + 0.02, z), BRIDGE_MARK)


func _bridge_stub(parent: Node3D, x: float, side: float, details: Array) -> void:
	var deck := ground_height(x, side * BRIDGE_BANK) + 0.28
	var length := BRIDGE_BANK - BRIDGE_TIP
	var middle := Vector3(x, deck - 0.8, side * (BRIDGE_BANK + BRIDGE_TIP) * 0.5)
	_box(parent, Vector3(11.0, 1.6, length), Transform3D(Basis.IDENTITY, middle), Cel.material(BRIDGE_DECK))
	var pedestal_z := side * 60.0
	var ground := ground_height(x, pedestal_z) - 2.0
	var height := deck - 1.2 - ground
	_box(parent, Vector3(6.0, height, 5.5),
		Transform3D(Basis.IDENTITY, Vector3(x, ground + height * 0.5, pedestal_z)), Cel.material(BRIDGE_FRAME))
	for edge: float in [-1.0, 1.0]:
		var rail_x := x + edge * 5.2
		var rail := Vector3(rail_x, deck + 0.46, middle.z + side * 2.0)
		_box(parent, Vector3(0.64, 0.92, length - 4.0), Transform3D(Basis.IDENTITY, rail), Cel.material(BRIDGE_FRAME))
		_detail(details, Vector3(0.16, 0.16, length - 7.0), rail + Vector3(edge * 0.36, 0.18, 0), BRIDGE_MARK)
		var tip := Vector3(rail_x, deck - 2.15, side * (BRIDGE_TIP - 2.4))
		var tilt := Basis(Vector3.RIGHT, side * (0.22 if edge < 0.0 else 0.42))
		_box(parent, Vector3(1.15, 1.1, 7.1), Transform3D(tilt, tip), Cel.material(BRIDGE_FRAME))
		var brace_top := Vector3(rail_x, deck - 1.9, side * (BRIDGE_TIP + 4.0))
		var brace_base := Vector3(x + edge * 2.7, maxf(ground + 0.5, deck - 15.0), pedestal_z)
		var brace := Transform3D(Basis.IDENTITY, brace_top.lerp(brace_base, 0.5)).looking_at(brace_top)
		_box(parent, Vector3(1.2, 1.3, brace_top.distance_to(brace_base)), brace, Cel.material(BRIDGE_FRAME))
	for offset: float in [-3.5, 0.0, 3.5]:
		_detail(details, Vector3(1.6, 0.06, 0.67), Vector3(x + offset, deck - 0.02, side * (BRIDGE_TIP + 2.2)), BRIDGE_MARK)


static func _detail(parts: Array, size: Vector3, at: Vector3, colour: Color) -> void:
	parts.append([Cel.box(size), Transform3D(Basis.IDENTITY, at), Color(colour, 0.0)])
