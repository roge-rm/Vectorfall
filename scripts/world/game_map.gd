class_name GameMap
extends Node3D

## What every map has: two bases on the x axis, team 0's at -x and team 1's at
## +x, each a raised deck with a ramp at the front, a tower at the back and the
## flag stand in the middle, spawn points to the side of the base, things the bots
## can't pass, and the bots' route graph. A map script extends it and builds
## its ground, props and route graph.

const BASE_SIZE := 24.0
const STAND_HEIGHT := 0.5
## The ramp up the front of each base: its length along the ground and its
## slope, for 14 m at 12°.
const RAMP_RUN := 13.69
const RAMP_SLOPE := 0.2126
## Grid cell size for looking up obstacles, in metres.
const OBSTACLE_CELL := 10.0
## The map main.gd loads when nothing else is asked for.
const DEFAULT := "ochre_fold"
const NAMES: Array[String] = ["ochre_fold", "test"]

## The map to load next, set by a tool or test before the main scene loads.
## Empty means the --map argument or DEFAULT.
static var chosen := ""

var title := ""
## The map's colours and light.
var palette: Palette
var atmosphere: Atmosphere
var rng := RandomNumberGenerator.new()
## How far each base is from the middle along x, in metres.
var base_distance := 200.0
## The ground the base deck stands on; its top is 2 m higher.
var base_ground := 6.0
## How far to the side of the flag stand the spawn points are, and how far
## back from it, away from the enemy, in metres.
var spawn_side := 40.0
var spawn_back := 0.0
## How far the base deck reaches below the ground it stands on, in metres.
var deck_depth := 0.0
## The chunked ground, on maps that have one.
var terrain: Terrain
## Things the bots can't pass, as (x, z, radius) circles, kept for the route
## graph.
var obstacles: Array[Vector3] = []
## The bots' route graph, made with the map.
var route_graph: RouteGraph
## Seconds the map took to build, and the route graph's share of it.
var build_seconds := 0.0
var graph_seconds := 0.0
## Obstacles by grid cell, for blocked_at().
var _obstacle_cells := {}


## A new map by name, the default if the name isn't known.
static func make(map_name: String) -> GameMap:
	match map_name:
		"test":
			return TestMap.new()
	return OchreFold.new()


## The map asked for: chosen, else --map NAME after -- on the command line,
## else fallback.
static func chosen_name(fallback := DEFAULT) -> String:
	if chosen != "":
		return chosen
	var args := OS.get_cmdline_user_args()
	for k in args.size() - 1:
		if args[k] == "--map":
			return args[k + 1]
	return fallback


## The ground's height, smooth, from the map's shape.
func height_at(x: float, z: float) -> float:
	return ground_height(x, z)


## The height of the ground's mesh, what you stand on.
func ground_height(_x: float, _z: float) -> float:
	return 0.0


func base_x(team: int) -> float:
	return -base_distance if team == 0 else base_distance


## Which way a team's base faces along x: towards the other base.
func front(team: int) -> float:
	return 1.0 if team == 0 else -1.0


func deck_height() -> float:
	return base_ground + 2.0


## Where a team's soldiers start: spawn_side m to the side of their flag stand in two groups
## of four, one each side, facing the other base.
func spawn_point(team: int, slot := 0) -> Transform3D:
	var side := 1.0 if slot % 2 == 0 else -1.0
	var row := slot / 2
	var x := base_x(team) + (row - 1.5) * 4.0 - front(team) * spawn_back
	var z := side * (spawn_side + (row % 2) * 3.0)
	var facing := -PI * 0.5 if team == 0 else PI * 0.5
	return Transform3D(Basis(Vector3.UP, facing), Vector3(x, surface_at(x, z) + 0.3, z))


## Every place a team's soldiers respawn.
func spawn_points(team: int) -> Array[Transform3D]:
	var points: Array[Transform3D] = []
	for slot in 8:
		points.append(spawn_point(team, slot))
	return points


## The top of a team's flag stand, in the middle of its base deck.
func stand_top(team: int) -> Vector3:
	return Vector3(base_x(team), deck_height() + STAND_HEIGHT, 0.0)


## Where a team's two inventory stations stand: on the deck between the flag
## stand and the tower, one each side, clear of the route points on the deck
## and the tower's foot. Maps with other bases override it.
func station_points(team: int) -> Array[Vector3]:
	var x := base_x(team) - front(team) * 4.0
	return [Vector3(x, deck_height(), -5.0), Vector3(x, deck_height(), 5.0)]


## The spot a carrier touches to score.
func stand_point(team: int) -> Vector3:
	return stand_top(team) + Vector3.UP * 0.5


## Where the team's flag rests, its middle, on the stand.
func flag_rest(team: int) -> Vector3:
	return stand_top(team) + Vector3.UP * (Flag.POLE * 0.5)


## Where you'd stand: the ground, or the base deck or its ramp above it.
func surface_at(x: float, z: float) -> float:
	var h := ground_height(x, z)
	if absf(z) > BASE_SIZE * 0.5 or absf(absf(x) - base_distance) > BASE_SIZE * 0.5 + RAMP_RUN:
		return h
	var deck := deck_height()
	for team in 2:
		var dx := x - base_x(team)
		if absf(dx) <= BASE_SIZE * 0.5 and absf(z) <= BASE_SIZE * 0.5:
			return deck
		var along := dx * front(team) - BASE_SIZE * 0.5
		if along > 0.0 and along < RAMP_RUN and absf(z) <= 5.0:
			h = maxf(h, deck - along * RAMP_SLOPE)
	return h


## Sets how far you can see, in metres: the fog thickens so it's nearly
## solid there, and chunked ground isn't drawn past it.
func set_view_distance(metres: float) -> void:
	if atmosphere != null:
		atmosphere.environment.fog_density = maxf(palette.fog_density, 3.0 / metres)
	if terrain != null:
		terrain.set_view_distance(metres)


## True inside a rock, pillar, tower or anything else you can't walk through,
## with room for a soldier.
func blocked_at(x: float, z: float) -> bool:
	if _obstacle_cells.is_empty():
		_sort_obstacles()
	var cell := Vector2i(floori(x / OBSTACLE_CELL), floori(z / OBSTACLE_CELL))
	for o: Vector3 in _obstacle_cells.get(cell, []):
		var dx := x - o.x
		var dz := z - o.y
		if dx * dx + dz * dz < o.z * o.z:
			return true
	return false


## Puts each obstacle, grown by the room a soldier needs, in every cell of a
## grid it touches, so blocked_at() only checks the few nearby.
func _sort_obstacles() -> void:
	_obstacle_cells.clear()
	for o in obstacles:
		var r := o.z + 1.0
		for i in range(floori((o.x - r) / OBSTACLE_CELL), floori((o.x + r) / OBSTACLE_CELL) + 1):
			for j in range(floori((o.y - r) / OBSTACLE_CELL), floori((o.y + r) / OBSTACLE_CELL) + 1):
				var key := Vector2i(i, j)
				if not _obstacle_cells.has(key):
					_obstacle_cells[key] = []
				_obstacle_cells[key].append(Vector3(o.x, o.y, r))


## The route graph points every base has: the flag stand, the spawns, the deck
## corners to defend, the ramp and the sides as ways in, and the tower top,
## jetted up to from beside it. Call it before auto_link(), and
## link_tower_tops() after.
func add_base_points(graph: RouteGraph) -> void:
	var deck := deck_height()
	for team in 2:
		var x := base_x(team)
		var ahead := front(team)
		graph.add_interest(RouteGraph.FLAG_STAND, team, graph.add_point(Vector3(x, deck, 0.0)))
		for side in [-1.0, 1.0]:
			var spawn_x := x - ahead * spawn_back
			var spawn_z: float = side * spawn_side
			graph.add_interest(RouteGraph.SPAWN, team, graph.add_point(Vector3(spawn_x, surface_at(spawn_x, spawn_z), spawn_z)))
		for corner in [Vector2(7.0, 7.0), Vector2(7.0, -7.0), Vector2(-7.0, 7.0), Vector2(-7.0, -7.0)]:
			graph.add_interest(RouteGraph.DEFENCE, team, graph.add_point(Vector3(x + corner.x, deck, corner.y)))
		# The ramp up the front of the deck is the way in without a jet.
		var ramp_top := graph.add_point(Vector3(x + ahead * 10.5, deck, 0.0))
		var foot_x := x + ahead * 27.0
		var ramp_foot := graph.add_point(Vector3(foot_x, surface_at(foot_x, 0.0), 0.0))
		graph.add_interest(RouteGraph.WAY_IN, team, ramp_top)
		graph.add_interest(RouteGraph.WAY_IN, team, ramp_foot)
		for side in [-1.0, 1.0]:
			var side_z: float = side * (BASE_SIZE * 0.5 + 6.0)
			graph.add_interest(RouteGraph.WAY_IN, team, graph.add_point(Vector3(x, surface_at(x, side_z), side_z)))


## The deck on top of each tower, jetted up to from beside it and dropped off
## back to the same spot.
func link_tower_tops(graph: RouteGraph) -> void:
	var deck := deck_height()
	for team in 2:
		var ahead := front(team)
		var back := base_x(team) - ahead * (BASE_SIZE * 0.5 - 4.0)
		var top := graph.add_point(Vector3(back, base_ground + 17.0, 3.75))
		var foot := graph.add_point(Vector3(back, deck, 8.0))
		graph.add_interest(RouteGraph.HIGH_GROUND, team, top)
		graph.add_interest(RouteGraph.DEFENCE, team, top)
		graph.add_link(foot, top, RouteGraph.Kind.JET, true)
		graph.add_link(top, foot, RouteGraph.Kind.RUN)
		var near := graph.nearest(Vector3(back + ahead * 3.0, deck, 7.0))
		if near != foot:
			graph.add_link(foot, near, RouteGraph.Kind.RUN)
			graph.add_link(near, foot, RouteGraph.Kind.RUN)


## True on a base's deck or close round it, where the lattice of route points
## leaves room for the base's own.
func near_base(x: float, z: float, margin := 2.0) -> bool:
	for team in 2:
		if absf(x - base_x(team)) < BASE_SIZE * 0.5 + margin and absf(z) < BASE_SIZE * 0.5 + margin:
			return true
	return false


func _build_base(team: int) -> void:
	var x := base_x(team)
	var base := Node3D.new()
	base.name = "Base%d" % team
	add_child(base)
	var ground := base_ground
	# The platform, a raised deck with a ramp up its front, reaching
	# deck_depth below the ground so a slope under it never shows a gap.
	var tall := 2.0 + deck_depth
	_box(base, Vector3(BASE_SIZE, tall, BASE_SIZE), Transform3D(Basis.IDENTITY, Vector3(x, ground + 2.0 - tall * 0.5, 0.0)), Cel.material(palette.structure))
	var ahead := front(team)
	# Its top meets the deck's edge, with no lip to catch on.
	var tilt := deg_to_rad(12.0)
	var ramp_basis := Basis(Vector3.FORWARD, ahead * tilt)
	var ramp_centre := Vector3(x + ahead * (BASE_SIZE * 0.5 + 7.0 * cos(tilt) - 0.5 * sin(tilt)), ground + 2.0 - 7.0 * sin(tilt) - 0.5 * cos(tilt), 0.0)
	_box(base, Vector3(14.0, 1.0, 10.0), Transform3D(ramp_basis, ramp_centre), Cel.material(palette.structure))
	# A tower at the back with a deck on top, in a dark team colour so the
	# flag in front stands out from it.
	var team_wall := Cel.team_material(Palette.team(team).lerp(palette.structure, 0.35).darkened(0.3))
	_build_stand(base, team)
	var back := x - ahead * (BASE_SIZE * 0.5 - 4.0)
	_box(base, Vector3(4.0, 14.0, 4.0), Transform3D(Basis.IDENTITY, Vector3(back, ground + 9.0, 0.0)), team_wall)
	obstacles.append(Vector3(back, 0.0, 2.9))
	_box(base, Vector3(10.0, 1.0, 10.0), Transform3D(Basis.IDENTITY, Vector3(back, ground + 16.5, 0.0)), Cel.material(palette.structure))
	for side in [-1.0, 1.0]:
		_box(base, Vector3(3.0, 4.0, 3.0), Transform3D(Basis.IDENTITY, Vector3(x, ground + 4.0, side * (BASE_SIZE * 0.5 - 2.0))), team_wall)
		obstacles.append(Vector3(x, side * (BASE_SIZE * 0.5 - 2.0), 2.2))


## A round pad in the team's colour with a ring of light around it, for the
## flag to stand on. It has no collision, so nothing catches on it.
func _build_stand(base: Node3D, team: int) -> void:
	var colour := Palette.team(team)
	var top := stand_top(team)
	var pad := MeshInstance3D.new()
	pad.mesh = Cel.cylinder(2.0, 2.4, STAND_HEIGHT, 12)
	pad.material_override = Cel.team_material(colour.darkened(0.2))
	pad.position = top - Vector3.UP * STAND_HEIGHT * 0.5
	base.add_child(pad)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.5
	torus.outer_radius = 3.0
	torus.rings = 24
	torus.ring_segments = 4
	ring.mesh = torus
	ring.material_override = Cel.glow(colour.lightened(0.3))
	ring.scale = Vector3(1.0, 0.1, 1.0)
	ring.position = top - Vector3.UP * (STAND_HEIGHT - 0.08)
	base.add_child(ring)


func _box(parent: Node3D, size: Vector3, where: Transform3D, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.transform = where
	var view := MeshInstance3D.new()
	view.mesh = Cel.box(size)
	view.material_override = material
	body.add_child(view)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	return body


func _pillar(parent: Node3D, at: Vector3, radius: float, tall: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	var view := MeshInstance3D.new()
	view.mesh = Cel.cylinder(radius * 0.8, radius, tall)
	view.material_override = Cel.material(palette.boulder.lightened(0.15))
	body.add_child(view)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = tall
	shape.shape = cylinder
	body.add_child(shape)
	parent.add_child(body)
	return body


## A lumpy low-poly rock: a coarse sphere with its points pushed in and out,
## with flat faces.
func _rock(parent: Node3D, at: Vector3, size: float) -> StaticBody3D:
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 1.4
	sphere.radial_segments = 7
	sphere.rings = 4
	var arrays := sphere.get_mesh_arrays()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# The same spot can appear more than once in the sphere (the seam and the
	# poles), so push by position to keep it closed.
	var push := {}
	for k in points.size():
		var p := points[k]
		var key := Vector3i((p * 100.0).round())
		if not push.has(key):
			push[key] = rng.randf_range(0.75, 1.2)
		points[k] = p * push[key]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in indices:
		tool.add_vertex(points[k])
	tool.generate_normals()
	var body := StaticBody3D.new()
	body.position = at
	body.rotation.y = rng.randf_range(0.0, TAU)
	var view := MeshInstance3D.new()
	view.mesh = Cel.hull_mesh(tool.commit())
	view.material_override = Cel.material(palette.boulder)
	body.add_child(view)
	var shape := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	convex.points = points
	shape.shape = convex
	body.add_child(shape)
	parent.add_child(body)
	return body
