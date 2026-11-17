class_name TestMap
extends Node3D

## A greybox map built in code: rolling ground from noise, ramps, rocks and
## pillars, and a base platform with a tower at each end. Team 0's base is at
## -x and team 1's at +x.

const LENGTH := 360.0
const WIDTH := 180.0
const CELL := 3.0
const BASE_X := 150.0
const BASE_HEIGHT := 6.0
const BASE_SIZE := 24.0
const MAP_SEED := 7

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
	noise.frequency = 0.007
	noise.fractal_octaves = 3
	rng.seed = MAP_SEED
	add_child(Atmosphere.new())
	_build_ground()
	for team in 2:
		_build_base(team)
	_build_props()


## Ground height from the noise, flattened around each base and raised at the
## edges into a bowl.
func height_at(x: float, z: float) -> float:
	var h := noise.get_noise_2d(x, z) * 16.0 + 4.0
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
			var patch := noise.get_noise_2d(x * 3.0 + 500.0, z * 3.0)
			var colour := GRASS if patch > 0.0 else GRASS_DARK
			if normal.y < 0.82:
				colour = ROCK
			elif normal.y < 0.9:
				colour = DIRT
			colours.append(colour)
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
	mesh.surface_set_material(0, Cel.material(Color.WHITE, 0.0, false, true))

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
	var ramp_basis := Basis(Vector3.FORWARD, front * deg_to_rad(12.0))
	_box(base, Vector3(14.0, 1.0, 10.0), Transform3D(ramp_basis, Vector3(x + front * (BASE_SIZE * 0.5 + 6.0), BASE_HEIGHT + 0.6, 0.0)), CONCRETE)
	# A tower at the back with a deck on top, in the team's colour.
	var back := x - front * (BASE_SIZE * 0.5 - 4.0)
	_box(base, Vector3(4.0, 14.0, 4.0), Transform3D(Basis.IDENTITY, Vector3(back, BASE_HEIGHT + 9.0, 0.0)), colour)
	_box(base, Vector3(10.0, 1.0, 10.0), Transform3D(Basis.IDENTITY, Vector3(back, BASE_HEIGHT + 16.5, 0.0)), CONCRETE)
	for side in [-1.0, 1.0]:
		_box(base, Vector3(3.0, 4.0, 3.0), Transform3D(Basis.IDENTITY, Vector3(x, BASE_HEIGHT + 4.0, side * (BASE_SIZE * 0.5 - 2.0))), colour)


func _build_props() -> void:
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)
	# Ramps along the middle, angled to launch you towards the other base.
	for k in 6:
		var x := rng.randf_range(-100.0, 100.0)
		var z := rng.randf_range(-55.0, 55.0)
		var heading := rng.randf_range(0.0, TAU)
		var tilt := deg_to_rad(rng.randf_range(14.0, 24.0))
		var basis := Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, tilt)
		_box(props, Vector3(6.0, 1.0, 14.0), Transform3D(basis, Vector3(x, height_at(x, z) + 1.0, z)), CONCRETE)
	for k in 14:
		var x := rng.randf_range(-125.0, 125.0)
		var z := rng.randf_range(-70.0, 70.0)
		_rock(props, Vector3(x, height_at(x, z) - 0.5, z), rng.randf_range(2.0, 5.0))
	for k in 6:
		var x := rng.randf_range(-110.0, 110.0)
		var z := rng.randf_range(-65.0, 65.0)
		var tall := rng.randf_range(8.0, 18.0)
		_pillar(props, Vector3(x, height_at(x, z) - 1.0 + tall * 0.5, z), 1.6, tall)


func _box(parent: Node3D, size: Vector3, where: Transform3D, colour: Color) -> void:
	var body := StaticBody3D.new()
	body.transform = where
	var view := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	view.mesh = mesh
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
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.8
	mesh.bottom_radius = radius
	mesh.height = tall
	mesh.radial_segments = 8
	mesh.rings = 1
	view.mesh = mesh
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
	view.mesh = tool.commit()
	view.material_override = Cel.material(ROCK)
	body.add_child(view)
	var shape := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	convex.points = points
	shape.shape = convex
	body.add_child(shape)
	parent.add_child(body)
