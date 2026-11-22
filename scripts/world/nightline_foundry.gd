class_name NightlineFoundry
extends ArenaMap

## A low foundry yard between short ramps up to the bases. Open casting
## bays give infantry cover, and the service roads go round either side.

const FRAME := Color("44445a")
const CLADDING := Color("756a81")
const CASTING := Color("5a374c")
const SAFETY := Color("edaa61")
const LAMP := Color("ffbd79")


func _init() -> void:
	super("Nightline Foundry", 186.0, 16.0, 77.0, 54, _night_palette(),
		Vector2(266, 148), ["north service road", "casting yard", "south service road"])


static func _night_palette() -> Palette:
	var made := Palette.neon_frontier()
	made.title = "Nightline Foundry"
	made.zenith = Color("201634")
	made.horizon = Color("db8097")
	made.sky_middle = Color("793a68")
	made.fog_colour = Color("865471")
	made.fog_density = 0.0039
	made.sun_colour = Color("ffd4ae")
	made.ambient = Color("a49bd0")
	made.ambient_energy = 0.65
	made.hatching = false
	made.line_brush = 0.0
	made.line_width = 1.12
	made.figure_line_scale = 0.82
	made.grass = Color("80747f")
	made.grass_dark = Color("766979")
	made.patch_colour = Color("736278")
	made.patch_amount = 0.09
	made.patch_size = 15.0
	made.dirt = Color("6c5365")
	made.rock = Color("624963")
	made.strata = 0.0
	made.structure = Color("9e929f")
	made.tech_glow = Color("f9a664")
	return made


func _land(x: float, z: float) -> float:
	var along := absf(x)
	var across := absf(z)
	var grade := 5.5 * smoothstep(48.0, 167.0, along)
	var shoulders := smoothstep(33.0, 59.0, across) - smoothstep(92.0, 116.0, across)
	var berm := 7.0 * smoothstep(109.0, 151.0, across)
	return 10.5 + grade - 1.6 * shoulders + berm


func _lane_offsets() -> Vector3:
	return Vector3(-78.0, 0.0, 78.0)


func ctf_respawn_points(team: int, count: int) -> Array[Transform3D]:
	return flank_spawns(team, count, 100.0, 84.0)


func stand_top(team: int) -> Vector3:
	return base_place(team, -1.0, 0.0, deck_height() + STAND_HEIGHT)


func generator_offset() -> Vector2:
	return Vector2(-19, -48)


func turret_points(team: int) -> Array[Vector3]:
	var guard := base_place(team, -6, -43, 0)
	guard.y = surface_at(guard.x, guard.z)
	var front_post := base_place(team, 28, 19, 0)
	front_post.y = surface_at(front_post.x, front_post.z)
	return [front_post, guard]


func _build_service_bays(base: Node3D, team: int, structure: Material, trim: Material) -> void:
	var deck := deck_height()
	var frame := Cel.material(FRAME)
	var cladding := Cel.material(CLADDING)
	var stripe := Cel.material(SAFETY)
	var glow := Cel.glow(LAMP)
	# Three loading aisles cross the covered stand.
	for along: float in [-8.0, 8.0]:
		base_piece(base, team, Vector3(along, deck + 7.15, 0), Vector3(2.4, 1.0, 29.0), frame)
		for side: float in [-1.0, 1.0]:
			base_piece(base, team, Vector3(along, deck + 3.4, side * 12.8), Vector3(1.6, 6.8, 1.9), trim, true)
			base_piece(base, team, Vector3(along, deck + 1.55, side * 12.8), Vector3(1.66, 0.22, 1.96), stripe)
		base_piece(base, team, Vector3(along, deck + 6.60, 0), Vector3(0.24, 0.11, 23.0), glow)
	base_piece(base, team, Vector3(0, deck + 7.8, 0), Vector3(18.5, 0.6, 28.5), cladding)
	for side: float in [-1.0, 1.0]:
		base_piece(base, team, Vector3(0, deck + 7.4, side * 14.1), Vector3(18.6, 0.22, 0.2), stripe)
	for side: float in [-1.0, 1.0]:
		base_piece(base, team, Vector3(10.0, deck + 1.25, side * 7.0), Vector3(1.7, 2.5, 4.5), structure, true)
		# The yard can't fire straight down the side exit.
		base_piece(base, team, Vector3(9.0, base_ground + 1.85, side * 25.0), Vector3(2.0, 3.7, 16.0), frame, true)
		base_piece(base, team, Vector3(9.0, base_ground + 3.75, side * 25.0), Vector3(2.1, 0.12, 16.0), stripe)

	# The service road reaches the reactor without crossing the flag stand.
	var gen := generator_offset()
	base_piece(base, team, Vector3(gen.x, base_ground + 7.0, gen.y), Vector3(29.0, 0.85, 20.0), cladding)
	for side: float in [-1.0, 1.0]:
		var z := gen.y + side * 8.8
		base_piece(base, team, Vector3(gen.x, base_ground + 6.35, z), Vector3(29.5, 0.48, 1.4), frame)
		for end: float in [-1.0, 1.0]:
			var x := gen.x + end * 12.0
			base_piece(base, team, Vector3(x, base_ground + 3.15, z), Vector3(1.7, 6.3, 1.8), trim, true)
			base_piece(base, team, Vector3(x, base_ground + 1.55, z), Vector3(1.75, 0.22, 1.85), stripe)
		base_piece(base, team, Vector3(gen.x, base_ground + 6.55, z - side), Vector3(25.0, 0.12, 0.18), glow)
	base_piece(base, team, Vector3(gen.x, base_ground + 2.2, gen.y + 8.8), Vector3(13.0, 4.4, 1.1), frame, true)
	base_piece(base, team, Vector3(gen.x - 5, base_ground + 1.65, gen.y - 8.8), Vector3(7.0, 3.3, 1.1), structure, true)


func add_base_points(graph: RouteGraph) -> void:
	super(graph)
	for team in 2:
		# The side exits open under the roof and between its corner pillars.
		for side: float in [-1.0, 1.0]:
			for edge: float in [12.0, 19.0, 33.0]:
				var at := base_place(team, -1.0, side * edge, 0)
				var point := _point(graph, at.x, at.z)
				graph.add_interest(RouteGraph.WAY_IN, team, point)
				if edge == 12.0:
					graph.add_interest(RouteGraph.FLAG_ENTRY, team, point)
				if edge == 19.0:
					graph.add_interest(RouteGraph.FLAG_EXIT, team, point)
		for along: float in [-37.0, -4.0, 10.0]:
			var at := base_place(team, along, generator_offset().y, 0)
			graph.add_interest(RouteGraph.WAY_IN, team, _point(graph, at.x, at.z))


func _dress(parent: Node3D) -> void:
	var finishes := []
	var lights := []
	for side: float in [-1.0, 1.0]:
		_furnace(parent, side, finishes, lights)
		for lane: float in [-1.0, 1.0]:
			var bay := Vector2(side * 60.0, lane * 27.0)
			_casting_bay(parent, bay, finishes, lights)
			# Low castings break sightlines without narrowing either road.
			prop(parent, Vector2(side * 110.0, lane * 37.0), Vector3(15.0, 3.0, 5.0), CASTING)
			prop(parent, Vector2(side * 13.0, lane * 48.0), Vector3(12.0, 2.3, 5.0), CLADDING)
			_road_markings(side, lane, finishes)
	_add_details(parent, finishes, Cel.material(Color.WHITE, 0.0, false, true))
	_add_details(parent, lights, Cel.glow(LAMP))


func _furnace(parent: Node3D, side: float, finishes: Array, lights: Array) -> void:
	var x := side * 28.0
	var floor := ground_height(x, 0.0)
	# Each furnace splits the approach, with a cross aisle between them.
	prop(parent, Vector2(x, 0.0), Vector3(9.0, 10.0, 38.0), FRAME)
	for z: float in [-12.0, 0.0, 12.0]:
		var face := Vector3(x + side * 4.52, floor + 3.8, z)
		_detail(finishes, Vector3(0.13, 4.8, 7.6), face, CASTING)
		_detail(lights, Vector3(0.12, 0.4, 5.5), face + Vector3(side * 0.13, 0.6, 0), Color.WHITE)


func _casting_bay(parent: Node3D, at: Vector2, finishes: Array, lights: Array) -> void:
	var floor := ground_height(at.x, at.y)
	var roof := floor + 9.8
	for x_side: float in [-1.0, 1.0]:
		for z_side: float in [-1.0, 1.0]:
			var corner := at + Vector2(x_side * 13.0, z_side * 9.0)
			prop(parent, corner, Vector3(1.5, 10.1, 1.5), FRAME)
			var mark := Vector3(corner.x, ground_height(corner.x, corner.y) + 1.7, corner.y)
			_detail(finishes, Vector3(1.54, 0.31, 1.54), mark, SAFETY)
		var cross := Vector3(at.x + x_side * 13.0, roof, at.y)
		_box(parent, Vector3(2.2, 0.87, 20.0), Transform3D(Basis.IDENTITY, cross), Cel.material(FRAME))
		_detail(lights, Vector3(0.14, 0.08, 14.0), cross - Vector3.UP * 0.46, Color.WHITE)
		var canopy := cross - Vector3.RIGHT * (x_side * 2.8) + Vector3.UP * 0.74
		_box(parent, Vector3(8.1, 0.66, 20.4), Transform3D(Basis.IDENTITY, canopy), Cel.material(CLADDING))
		_detail(finishes, Vector3(0.16, 0.25, 18.0),
			canopy + Vector3(x_side * 4.02, -0.06, 0), SAFETY)
	# High ducts along the bay, with gaps between them for pilots to see
	# the yard. Only the support feet are obstacles for bots on the ground.
	for side: float in [-1.0, 1.0]:
		var rail := Vector3(at.x, roof + 0.36, at.y + side * 8.8)
		_box(parent, Vector3(27.8, 0.77, 1.7), Transform3D(Basis.IDENTITY, rail), Cel.material(CLADDING))
		_detail(finishes, Vector3(23.0, 0.29, 0.035),
			rail + Vector3(0.0, 0.02, side * 0.86), SAFETY)
	var outside := signf(at.y)
	prop(parent, at + Vector2(0, outside * 9.0), Vector3(12.0, 4.0, 1.25), FRAME)
	prop(parent, at + Vector2(0, outside * 3.6), Vector3(8.0, 2.7, 3.0), CASTING)
	var service := Vector3(at.x, floor + 2.32, at.y + outside * 8.30)
	for offset: float in [-3.9, 0.0, 3.9]:
		_detail(finishes, Vector3(2.3, 1.32, 0.12), service + Vector3(offset, 0, 0), CLADDING)
		_detail(lights, Vector3(1.13, 0.09, 0.08), service + Vector3(offset, 0.5, -outside * 0.09), Color.WHITE)


func _road_markings(side: float, lane: float, parts: Array) -> void:
	var z := lane * 72.0
	for offset: float in [30.0, 64.0, 100.0, 135.0]:
		var x := side * offset
		var a := ground_height(x - 2.0, z)
		var b := ground_height(x + 2.0, z)
		var tilt := Basis(Vector3.BACK, atan2(b - a, 4.0))
		parts.append([Cel.box(Vector3(3.9, 0.025, 0.20)),
			Transform3D(tilt, Vector3(x, ground_height(x, z) + 0.11, z)), Color(SAFETY, 0.0)])


static func _detail(parts: Array, size: Vector3, at: Vector3, colour: Color) -> void:
	parts.append([Cel.box(size), Transform3D(Basis.IDENTITY, at), Color(colour, 0.0)])


static func _add_details(parent: Node3D, parts: Array, material: Material) -> void:
	var view := MeshInstance3D.new()
	view.mesh = Cel.merged(parts)
	view.material_override = material
	parent.add_child(view)


func midfield_supply() -> Vector2:
	return Vector2(0, 30)


func controlled_supply_site() -> int:
	return 1


func control_sites() -> Array[Vector2]:
	return [Vector2(0, -81), Vector2.ZERO, Vector2(0, 81)]
