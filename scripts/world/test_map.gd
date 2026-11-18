class_name TestMap
extends Node3D

## A greybox map built in code: a long valley between the bases to ski down, ramps, rocks
## and pillars, and a base platform with a tower at each end. Team 0's base is
## at -x and team 1's at +x.

const LENGTH := 520.0
const WIDTH := 200.0
const CELL := 3.0
const BASE_X := 200.0
const BASE_HEIGHT := 6.0
const BASE_SIZE := 24.0
const MAP_SEED := 7
const STAND_HEIGHT := 0.5
## Three rolling hills between the bases, each about HILL_HEIGHT from ridge
## to valley and a third of the way across, with the bases on the ridge tops
## at each end. A soldier who skis down and jets up each one builds speed
## over the run.
const HILL_HEIGHT := 38.0
const HILLS := 3
## The ramp up the front of each base: its length along the ground and its
## slope, for 14 m at 12°.
const RAMP_RUN := 13.69
const RAMP_SLOPE := 0.2126
## Grid cell size for looking up obstacles, in metres.
const OBSTACLE_CELL := 10.0


## The map's colours and light.
var palette: Palette
var noise := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()
var ground: StaticBody3D
## Things the bots can't pass, as (x, z, radius) circles, kept for the route
## graph.
var obstacles: Array[Vector3] = []
## The bots' route graph, made with the map.
var route_graph: RouteGraph
## The ground's height at each corner of its mesh, row by row along x.
var heights := PackedFloat32Array()
## Obstacles by grid cell, for blocked_at().
var _obstacle_cells := {}


func _init(colours: Palette = null) -> void:
	name = "TestMap"
	palette = colours if colours != null else Palette.desert()
	noise.seed = MAP_SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.006
	noise.fractal_octaves = 2
	rng.seed = MAP_SEED
	add_child(Atmosphere.new(palette))
	_build_ground()
	for team in 2:
		_build_base(team)
	_build_props()
	route_graph = build_route_graph()


## Ground height: long ridges across the map, bent and varied along z with a
## little smooth noise on top, flattened around each base and raised at the
## edges into a bowl.
func height_at(x: float, z: float) -> float:
	var bent := x + 14.0 * sin(z * 0.025)
	var depth := HILL_HEIGHT * (1.0 + 0.08 * sin(z * 0.035 + 1.0))
	# 1 on a ridge top and -1 in a valley, with a ridge at each base.
	var valley := cos(TAU * HILLS * (bent + BASE_X) / (BASE_X * 2.0))
	# Broad ridge tops that don't throw you, and tighter valleys.
	var ridge := 1.0 - pow(1.0 - (valley + 1.0) * 0.5, 1.5)
	var h := BASE_HEIGHT + (ridge - 1.0) * depth + noise.get_noise_2d(x, z) * 3.0
	for team in 2:
		var d := Vector2(x - base_x(team), z).length()
		var t := smoothstep(BASE_SIZE * 0.9, BASE_SIZE * 2.2, d)
		h = lerpf(BASE_HEIGHT, h, t)
	var edge_x := absf(x) / (LENGTH * 0.5)
	var edge_z := absf(z) / (WIDTH * 0.5)
	var edge := maxf(smoothstep(0.8, 1.0, edge_x), smoothstep(0.7, 1.0, edge_z))
	return h + edge * edge * 35.0


func base_x(team: int) -> float:
	return -BASE_X if team == 0 else BASE_X


## How far to the side of the flag stand the spawn points are, in metres.
const SPAWN_SIDE := 40.0

## Where a team's soldiers start: on the ridge 40 m beside their flag stand in
## two groups of four, one each side, facing the other base.
func spawn_point(team: int, slot := 0) -> Transform3D:
	var side := 1.0 if slot % 2 == 0 else -1.0
	var row := slot / 2
	var x := base_x(team) + (row - 1.5) * 4.0
	var z := side * (SPAWN_SIDE + (row % 2) * 3.0)
	var facing := -PI * 0.5 if team == 0 else PI * 0.5
	return Transform3D(Basis(Vector3.UP, facing), Vector3(x, surface_at(x, z) + 0.3, z))


## The top of a team's flag stand, in the middle of its base deck.
func stand_top(team: int) -> Vector3:
	return Vector3(base_x(team), BASE_HEIGHT + 2.0 + STAND_HEIGHT, 0.0)


## The spot a carrier touches to score.
func stand_point(team: int) -> Vector3:
	return stand_top(team) + Vector3.UP * 0.5


## Where the team's flag rests, its middle, on the stand.
func flag_rest(team: int) -> Vector3:
	return stand_top(team) + Vector3.UP * (Flag.POLE * 0.5)


## Every place a team's soldiers respawn.
func spawn_points(team: int) -> Array[Transform3D]:
	var points: Array[Transform3D] = []
	for slot in 8:
		points.append(spawn_point(team, slot))
	return points


## The height of the ground's mesh, which is flat between its corners, so
## quicker than height_at() and closer to what you stand on.
func ground_height(x: float, z: float) -> float:
	var nx := int(LENGTH / CELL)
	var nz := int(WIDTH / CELL)
	var gx := clampf((x + LENGTH * 0.5) / CELL, 0.0, nx - 0.001)
	var gz := clampf((z + WIDTH * 0.5) / CELL, 0.0, nz - 0.001)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - i
	var fz := gz - j
	var a := heights[j * (nx + 1) + i]
	var b := heights[j * (nx + 1) + i + 1]
	var c := heights[(j + 1) * (nx + 1) + i]
	var d := heights[(j + 1) * (nx + 1) + i + 1]
	# Each cell is two triangles split from b to c, like the mesh.
	if fx + fz <= 1.0:
		return a + (b - a) * fx + (c - a) * fz
	return d + (c - d) * (1.0 - fx) + (b - d) * (1.0 - fz)


## Where you'd stand: the ground, or the base deck or its ramp above it.
func surface_at(x: float, z: float) -> float:
	var h := ground_height(x, z)
	if absf(z) > BASE_SIZE * 0.5 or absf(absf(x) - BASE_X) > BASE_SIZE * 0.5 + RAMP_RUN:
		return h
	for team in 2:
		var dx := x - base_x(team)
		if absf(dx) <= BASE_SIZE * 0.5 and absf(z) <= BASE_SIZE * 0.5:
			return BASE_HEIGHT + 2.0
		var front := 1.0 if team == 0 else -1.0
		var along := dx * front - BASE_SIZE * 0.5
		if along > 0.0 and along < RAMP_RUN and absf(z) <= 5.0:
			h = maxf(h, BASE_HEIGHT + 2.0 - along * RAMP_SLOPE)
	return h


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
	for o in obstacles:
		var r := o.z + 1.0
		for i in range(floori((o.x - r) / OBSTACLE_CELL), floori((o.x + r) / OBSTACLE_CELL) + 1):
			for j in range(floori((o.y - r) / OBSTACLE_CELL), floori((o.y + r) / OBSTACLE_CELL) + 1):
				var key := Vector2i(i, j)
				if not _obstacle_cells.has(key):
					_obstacle_cells[key] = []
				_obstacle_cells[key].append(Vector3(o.x, o.y, r))


## The bots' route graph: a grid of points every 20 m over the ground, points
## on each base's deck and its ramp, and the points of interest, all linked to
## their neighbours up to 46 m away.
func build_route_graph() -> RouteGraph:
	var graph := RouteGraph.new()
	for i in range(-12, 13):
		for j in range(-4, 5):
			var x := i * 20.0
			var z := j * 20.0
			var on_base := false
			for team in 2:
				on_base = on_base or (absf(x - base_x(team)) < BASE_SIZE * 0.5 + 2.0 and absf(z) < BASE_SIZE * 0.5 + 2.0)
			if on_base or blocked_at(x, z):
				continue
			graph.add_point(Vector3(x, surface_at(x, z), z))
	var deck := BASE_HEIGHT + 2.0
	for team in 2:
		var x := base_x(team)
		var front := 1.0 if team == 0 else -1.0
		graph.add_interest(RouteGraph.FLAG_STAND, team, graph.add_point(Vector3(x, deck, 0.0)))
		for side in [-1.0, 1.0]:
			var spawn_z: float = side * SPAWN_SIDE
			graph.add_interest(RouteGraph.SPAWN, team, graph.add_point(Vector3(x, surface_at(x, spawn_z), spawn_z)))
		for corner in [Vector2(7.0, 7.0), Vector2(7.0, -7.0), Vector2(-7.0, 7.0), Vector2(-7.0, -7.0)]:
			graph.add_interest(RouteGraph.DEFENCE, team, graph.add_point(Vector3(x + corner.x, deck, corner.y)))
		# The ramp up the front of the deck is the way in without a jet.
		var ramp_top := graph.add_point(Vector3(x + front * 10.5, deck, 0.0))
		var foot_x := x + front * 27.0
		var ramp_foot := graph.add_point(Vector3(foot_x, surface_at(foot_x, 0.0), 0.0))
		graph.add_interest(RouteGraph.WAY_IN, team, ramp_top)
		graph.add_interest(RouteGraph.WAY_IN, team, ramp_foot)
		for side in [-1.0, 1.0]:
			var side_z: float = side * (BASE_SIZE * 0.5 + 6.0)
			graph.add_interest(RouteGraph.WAY_IN, team, graph.add_point(Vector3(x, surface_at(x, side_z), side_z)))
	for side in [-1.0, 1.0]:
		for z in [-40.0, 40.0]:
			var x: float = side * BASE_X / 3.0
			if not blocked_at(x, z):
				graph.add_interest(RouteGraph.HIGH_GROUND, -1, graph.add_point(Vector3(x, surface_at(x, z), z)))
	graph.auto_link(46.0, surface_at, blocked_at)
	# The deck on top of each tower, jetted up to from beside it and dropped
	# off back to the same spot.
	for team in 2:
		var front := 1.0 if team == 0 else -1.0
		var back := base_x(team) - front * (BASE_SIZE * 0.5 - 4.0)
		var top := graph.add_point(Vector3(back, BASE_HEIGHT + 17.0, 3.75))
		var foot := graph.add_point(Vector3(back, deck, 8.0))
		graph.add_interest(RouteGraph.HIGH_GROUND, team, top)
		graph.add_interest(RouteGraph.DEFENCE, team, top)
		graph.add_link(foot, top, RouteGraph.Kind.JET, true)
		graph.add_link(top, foot, RouteGraph.Kind.RUN)
		var near := graph.nearest(Vector3(back + front * 3.0, deck, 7.0))
		if near != foot:
			graph.add_link(foot, near, RouteGraph.Kind.RUN)
			graph.add_link(near, foot, RouteGraph.Kind.RUN)
	return graph


func _build_ground() -> void:
	var nx := int(LENGTH / CELL)
	var nz := int(WIDTH / CELL)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	for j in nz + 1:
		for i in nx + 1:
			var x := -LENGTH * 0.5 + i * CELL
			var z := -WIDTH * 0.5 + j * CELL
			var h := height_at(x, z)
			heights.append(h)
			vertices.append(Vector3(x, h, z))
			var normal := Vector3(height_at(x - 1.0, z) - height_at(x + 1.0, z), 2.0, height_at(x, z - 1.0) - height_at(x, z + 1.0)).normalized()
			normals.append(normal)
			# The ground shader picks its colour from these per pixel.
			var patch := noise.get_noise_2d(x * 3.0 + 500.0, z * 3.0)
			colours.append(Color(normal.y, patch * 0.5 + 0.5, 0.0))
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			var b := a + 1
			var c := a + nx + 1
			var d := c + 1
			indices.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := Cel.ground_material()
	mesh.surface_set_material(0, material)

	ground = StaticBody3D.new()
	ground.name = "Ground"
	var view := MeshInstance3D.new()
	view.mesh = mesh
	ground.add_child(view)
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	ground.add_child(shape)
	add_child(ground)


func _build_base(team: int) -> void:
	var x := base_x(team)
	var base := Node3D.new()
	base.name = "Base%d" % team
	add_child(base)
	# The platform, a raised deck with a ramp up its front.
	_box(base, Vector3(BASE_SIZE, 2.0, BASE_SIZE), Transform3D(Basis.IDENTITY, Vector3(x, BASE_HEIGHT + 1.0, 0.0)), Cel.material(palette.structure))
	var front := 1.0 if team == 0 else -1.0
	# Its top meets the deck's edge, with no lip to catch on.
	var tilt := deg_to_rad(12.0)
	var ramp_basis := Basis(Vector3.FORWARD, front * tilt)
	var ramp_centre := Vector3(x + front * (BASE_SIZE * 0.5 + 7.0 * cos(tilt) - 0.5 * sin(tilt)), BASE_HEIGHT + 2.0 - 7.0 * sin(tilt) - 0.5 * cos(tilt), 0.0)
	_box(base, Vector3(14.0, 1.0, 10.0), Transform3D(ramp_basis, ramp_centre), Cel.material(palette.structure))
	# A tower at the back with a deck on top, in a dark team colour so the
	# flag in front stands out from it.
	var team_wall := Cel.team_material(Soldier.TEAM_COLOURS[team].lerp(palette.structure, 0.35).darkened(0.3))
	_build_stand(base, team)
	var back := x - front * (BASE_SIZE * 0.5 - 4.0)
	_box(base, Vector3(4.0, 14.0, 4.0), Transform3D(Basis.IDENTITY, Vector3(back, BASE_HEIGHT + 9.0, 0.0)), team_wall)
	obstacles.append(Vector3(back, 0.0, 2.9))
	_box(base, Vector3(10.0, 1.0, 10.0), Transform3D(Basis.IDENTITY, Vector3(back, BASE_HEIGHT + 16.5, 0.0)), Cel.material(palette.structure))
	for side in [-1.0, 1.0]:
		_box(base, Vector3(3.0, 4.0, 3.0), Transform3D(Basis.IDENTITY, Vector3(x, BASE_HEIGHT + 4.0, side * (BASE_SIZE * 0.5 - 2.0))), team_wall)
		obstacles.append(Vector3(x, side * (BASE_SIZE * 0.5 - 2.0), 2.2))


## A round pad in the team's colour with a ring of light around it, for the
## flag to stand on. It has no collision, so nothing catches on it.
func _build_stand(base: Node3D, team: int) -> void:
	var colour := Soldier.TEAM_COLOURS[team]
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


func _build_props() -> void:
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)
	# Ramps along the middle, angled to launch you towards the other base.
	for k in 6:
		var x := rng.randf_range(-140.0, 140.0)
		var z := rng.randf_range(-60.0, 60.0)
		var heading := rng.randf_range(0.0, TAU)
		var tilt := deg_to_rad(rng.randf_range(14.0, 24.0))
		var basis := Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, tilt)
		_box(props, Vector3(6.0, 1.0, 14.0), Transform3D(basis, Vector3(x, height_at(x, z) + 1.0, z)), Cel.material(palette.structure))
		obstacles.append(Vector3(x, z, 7.5))
	for k in 18:
		var x := rng.randf_range(-165.0, 165.0)
		var z := rng.randf_range(-75.0, 75.0)
		var size := rng.randf_range(2.0, 5.0)
		_rock(props, Vector3(x, height_at(x, z) - 0.5, z), size)
		obstacles.append(Vector3(x, z, size * 1.2))
	for k in 8:
		var x := rng.randf_range(-150.0, 150.0)
		var z := rng.randf_range(-70.0, 70.0)
		var tall := rng.randf_range(8.0, 18.0)
		_pillar(props, Vector3(x, height_at(x, z) - 1.0 + tall * 0.5, z), 1.6, tall)
		obstacles.append(Vector3(x, z, 1.6))


func _box(parent: Node3D, size: Vector3, where: Transform3D, material: Material) -> void:
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


func _pillar(parent: Node3D, at: Vector3, radius: float, tall: float) -> void:
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


## A lumpy low-poly rock: a coarse sphere with its points pushed in and out,
## with flat faces.
func _rock(parent: Node3D, at: Vector3, size: float) -> void:
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
