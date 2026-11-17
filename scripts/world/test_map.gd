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

const GRASS := Color(0.45, 0.62, 0.32)
const GRASS_DARK := Color(0.36, 0.52, 0.28)
const DIRT := Color(0.62, 0.55, 0.4)
const ROCK := Color(0.55, 0.53, 0.5)
const CONCRETE := Color(0.72, 0.72, 0.7)

var noise := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()
var ground: StaticBody3D


func _init() -> void:
	name = "TestMap"
	noise.seed = MAP_SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.006
	noise.fractal_octaves = 2
	rng.seed = MAP_SEED
	add_child(Atmosphere.new())
	_build_ground()
	for team in 2:
		_build_base(team)
	_build_props()


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


## Where a team's soldiers start: on their base platform, facing the other base.
func spawn_point(team: int, slot := 0) -> Transform3D:
	var x := base_x(team) + (6.0 if team == 0 else -6.0)
	var z := (slot - 3.5) * 2.5
	var facing := -PI * 0.5 if team == 0 else PI * 0.5
	return Transform3D(Basis(Vector3.UP, facing), Vector3(x, BASE_HEIGHT + 2.2, z))


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
	material.set_shader_parameter("grass", GRASS)
	material.set_shader_parameter("grass_dark", GRASS_DARK)
	material.set_shader_parameter("dirt", DIRT)
	material.set_shader_parameter("rock", ROCK)
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
	var colour := Soldier.TEAM_COLOURS[team]
	var base := Node3D.new()
	base.name = "Base%d" % team
	add_child(base)
	# The platform, a raised deck with a ramp up its front.
	_box(base, Vector3(BASE_SIZE, 2.0, BASE_SIZE), Transform3D(Basis.IDENTITY, Vector3(x, BASE_HEIGHT + 1.0, 0.0)), CONCRETE)
	var front := 1.0 if team == 0 else -1.0
	# Its top meets the deck's edge, with no lip to catch on.
	var tilt := deg_to_rad(12.0)
	var ramp_basis := Basis(Vector3.FORWARD, front * tilt)
	var ramp_centre := Vector3(x + front * (BASE_SIZE * 0.5 + 7.0 * cos(tilt) - 0.5 * sin(tilt)), BASE_HEIGHT + 2.0 - 7.0 * sin(tilt) - 0.5 * cos(tilt), 0.0)
	_box(base, Vector3(14.0, 1.0, 10.0), Transform3D(ramp_basis, ramp_centre), CONCRETE)
	# A tower at the back with a deck on top, in the team's colour.
	_build_stand(base, team)
	var back := x - front * (BASE_SIZE * 0.5 - 4.0)
	_box(base, Vector3(4.0, 14.0, 4.0), Transform3D(Basis.IDENTITY, Vector3(back, BASE_HEIGHT + 9.0, 0.0)), colour)
	_box(base, Vector3(10.0, 1.0, 10.0), Transform3D(Basis.IDENTITY, Vector3(back, BASE_HEIGHT + 16.5, 0.0)), CONCRETE)
	for side in [-1.0, 1.0]:
		_box(base, Vector3(3.0, 4.0, 3.0), Transform3D(Basis.IDENTITY, Vector3(x, BASE_HEIGHT + 4.0, side * (BASE_SIZE * 0.5 - 2.0))), colour)


## A round pad in the team's colour with a ring of light around it, for the
## flag to stand on. It has no collision, so nothing catches on it.
func _build_stand(base: Node3D, team: int) -> void:
	var colour := Soldier.TEAM_COLOURS[team]
	var top := stand_top(team)
	var pad := MeshInstance3D.new()
	pad.mesh = Cel.cylinder(2.0, 2.4, STAND_HEIGHT, 12)
	pad.material_override = Cel.material(colour.darkened(0.2))
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
		_box(props, Vector3(6.0, 1.0, 14.0), Transform3D(basis, Vector3(x, height_at(x, z) + 1.0, z)), CONCRETE)
	for k in 18:
		var x := rng.randf_range(-165.0, 165.0)
		var z := rng.randf_range(-75.0, 75.0)
		_rock(props, Vector3(x, height_at(x, z) - 0.5, z), rng.randf_range(2.0, 5.0))
	for k in 8:
		var x := rng.randf_range(-150.0, 150.0)
		var z := rng.randf_range(-70.0, 70.0)
		var tall := rng.randf_range(8.0, 18.0)
		_pillar(props, Vector3(x, height_at(x, z) - 1.0 + tall * 0.5, z), 1.6, tall)


func _box(parent: Node3D, size: Vector3, where: Transform3D, colour: Color) -> void:
	var body := StaticBody3D.new()
	body.transform = where
	var view := MeshInstance3D.new()
	view.mesh = Cel.box(size)
	view.material_override = Cel.material(colour)
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
	view.material_override = Cel.material(ROCK.lightened(0.15))
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
	view.material_override = Cel.material(ROCK)
	body.add_child(view)
	var shape := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	convex.points = points
	shape.shape = convex
	body.add_child(shape)
	parent.add_child(body)
