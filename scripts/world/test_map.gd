class_name TestMap
extends GameMap

## A greybox map built in code: a long valley between the bases to ski down, ramps, rocks
## and pillars, and a base platform with a tower at each end. Team 0's base is
## at -x and team 1's at +x.

const LENGTH := 520.0
const WIDTH := 200.0
const CELL := 3.0
const BASE_X := 200.0
const BASE_HEIGHT := 6.0
const MAP_SEED := 7
## Three rolling hills between the bases, each about HILL_HEIGHT from ridge
## to valley and a third of the way across, with the bases on the ridge tops
## at each end. A soldier who skis down and jets up each one builds speed
## over the run.
const HILL_HEIGHT := 38.0
const HILLS := 3


var noise := FastNoiseLite.new()
var ground: StaticBody3D
## The ground's height at each corner of its mesh, row by row along x.
var heights := PackedFloat32Array()


func _init(colours: Palette = null) -> void:
	name = "TestMap"
	title = "Test map"
	var started := Time.get_ticks_usec()
	base_distance = BASE_X
	base_ground = BASE_HEIGHT
	spawn_side = SPAWN_SIDE
	palette = colours if colours != null else Palette.paperback()
	noise.seed = MAP_SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.006
	noise.fractal_octaves = 2
	rng.seed = MAP_SEED
	atmosphere = Atmosphere.new(palette)
	add_child(atmosphere)
	_build_ground()
	for team in 2:
		_build_base(team)
	_build_props()
	var graph_started := Time.get_ticks_usec()
	route_graph = build_route_graph()
	graph_seconds = (Time.get_ticks_usec() - graph_started) / 1000000.0
	build_seconds = (Time.get_ticks_usec() - started) / 1000000.0


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


## How far to the side of the flag stand the spawn points are, in metres.
const SPAWN_SIDE := 40.0

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
	add_base_points(graph)
	for side in [-1.0, 1.0]:
		for z in [-40.0, 40.0]:
			var x: float = side * BASE_X / 3.0
			if not blocked_at(x, z):
				graph.add_interest(RouteGraph.HIGH_GROUND, -1, graph.add_point(Vector3(x, surface_at(x, z), z)))
	graph.auto_link(46.0, surface_at, blocked_at)
	link_tower_tops(graph)
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
