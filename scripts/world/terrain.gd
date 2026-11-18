class_name Terrain
extends Node3D

## A big heightfield cut into chunks. Each chunk has a mesh per level of
## detail, picked by the camera's distance through visibility ranges, with
## skirts hanging from its edges so levels that meet never show a gap.
## Collision is only built near things that move: keep_collision_near() puts
## collision chunks under the soldiers and flags each tick, and raycast()
## follows the heightfield itself, so shots hit the ground anywhere.
##
## Heights are kept row by row along x, (cells + 1) by (cells + 1) of them,
## from the corner at origin. Each cell is two triangles split from its +x
## corner to its +z corner.

## Cells per side of a drawn chunk.
const CHUNK_CELLS := 48
## Cells between vertices at each level of detail.
const LOD_STEPS: Array[int] = [1, 2, 4, 8]
## Distance from the camera to a chunk's middle where each level ends, in
## metres. The last level runs to the view distance.
const LOD_ENDS: Array[float] = [260.0, 520.0, 950.0]
## Cells per side of a collision chunk.
const COLLISION_CELLS := 16
## Collision is kept this far around each thing that moves, in metres, plus
## half a second at its speed.
const COLLISION_REACH := 36.0
## Ticks a collision chunk stays after nothing needs it, so one on the edge
## of someone's reach isn't added and taken away every tick.
const COLLISION_LINGER := 30

var cells := 0
## Metres per cell.
var cell := 4.0
## The x and z of the first height.
var origin := Vector2.ZERO
var heights := PackedFloat32Array()
## Per height, the ground shader's patch value (0 to 1).
var patches := PackedFloat32Array()
## Per height, the smoothed up direction.
var normals := PackedVector3Array()
## Per chunk (row by row along x), its MeshInstance3D per level.
var chunk_views: Array[Array] = []
## Per chunk, the skirt depth at each level, in metres.
var skirt_depths: Array[PackedFloat32Array] = []
var view_distance := 1200.0
var material: ShaderMaterial
## Collision chunk key to its StaticBody3D, made the first time it's needed.
var _collision: Dictionary[Vector2i, StaticBody3D] = {}
## Collision chunk key to the tick it was last needed, for those in the tree.
var _active: Dictionary[Vector2i, int] = {}
var _tick := 0


## Builds the drawn chunks from a heightfield. height_values and
## patch_values have (cell_count + 1)² entries.
func _init(cell_count := 0, cell_size := 4.0, corner := Vector2.ZERO, height_values := PackedFloat32Array(), patch_values := PackedFloat32Array()) -> void:
	name = "Terrain"
	if cell_count == 0:
		return
	cells = cell_count
	cell = cell_size
	origin = corner
	heights = height_values
	patches = patch_values
	material = Cel.ground_material()
	_build_normals()
	_build_chunks()


func size() -> float:
	return cells * cell


func chunks_per_side() -> int:
	return ceili(float(cells) / CHUNK_CELLS)


func height_index(i: int, j: int) -> float:
	return heights[j * (cells + 1) + i]


## The height of the full detail mesh at a point, clamped to the edge.
func height_at(x: float, z: float) -> float:
	var gx := clampf((x - origin.x) / cell, 0.0, cells - 0.0001)
	var gz := clampf((z - origin.y) / cell, 0.0, cells - 0.0001)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - i
	var fz := gz - j
	var row := cells + 1
	var a := heights[j * row + i]
	var b := heights[j * row + i + 1]
	var c := heights[(j + 1) * row + i]
	var d := heights[(j + 1) * row + i + 1]
	if fx + fz <= 1.0:
		return a + (b - a) * fx + (c - a) * fz
	return d + (c - d) * (1.0 - fx) + (b - d) * (1.0 - fz)


## The up direction of the triangle under a point.
func normal_at(x: float, z: float) -> Vector3:
	var gx := clampf((x - origin.x) / cell, 0.0, cells - 0.0001)
	var gz := clampf((z - origin.y) / cell, 0.0, cells - 0.0001)
	var i := int(gx)
	var j := int(gz)
	var row := cells + 1
	var a := heights[j * row + i]
	var b := heights[j * row + i + 1]
	var c := heights[(j + 1) * row + i]
	var d := heights[(j + 1) * row + i + 1]
	if (gx - i) + (gz - j) <= 1.0:
		return Vector3(a - b, cell, a - c).normalized()
	return Vector3(c - d, cell, b - d).normalized()


## Where the segment from a to b first goes into the ground, as
## { position, normal }, or an empty dictionary. It samples every half cell
## and closes in on the crossing.
func raycast(a: Vector3, b: Vector3) -> Dictionary:
	if a.y < height_at(a.x, a.z):
		return { "position": a, "normal": normal_at(a.x, a.z) }
	var length := a.distance_to(b)
	var count := maxi(ceili(length / (cell * 0.5)), 1)
	var last := 0.0
	for k in range(1, count + 1):
		var t := float(k) / count
		var p := a.lerp(b, t)
		if p.y < height_at(p.x, p.z):
			var lo := last
			var hi := t
			for n in 10:
				var mid := (lo + hi) * 0.5
				var q := a.lerp(b, mid)
				if q.y < height_at(q.x, q.z):
					hi = mid
				else:
					lo = mid
			var at := a.lerp(b, hi)
			return { "position": at, "normal": normal_at(at.x, at.z) }
		last = t
	return {}


## Sets how far the ground is drawn, in metres.
func set_view_distance(metres: float) -> void:
	view_distance = metres
	for views in chunk_views:
		var last: MeshInstance3D = views[-1]
		last.visibility_range_end = metres + CHUNK_CELLS * cell * 0.7


## Puts collision under every point in points, with speeds (m/s, one per
## point) widening the reach, and takes it away from where nothing is.
## Call it once a tick, before anything moves.
func keep_collision_near(points: PackedVector3Array, speeds: PackedFloat32Array) -> void:
	_tick += 1
	var span := COLLISION_CELLS * cell
	var count := ceili(float(cells) / COLLISION_CELLS)
	for k in points.size():
		var p := points[k]
		var reach := COLLISION_REACH + speeds[k] * 0.5
		var i0 := clampi(floori((p.x - reach - origin.x) / span), 0, count - 1)
		var i1 := clampi(floori((p.x + reach - origin.x) / span), 0, count - 1)
		var j0 := clampi(floori((p.z - reach - origin.y) / span), 0, count - 1)
		var j1 := clampi(floori((p.z + reach - origin.y) / span), 0, count - 1)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var key := Vector2i(i, j)
				if not _active.has(key):
					add_child(_collision_body(key))
				_active[key] = _tick
	for key: Vector2i in _active.keys():
		if _tick - _active[key] > COLLISION_LINGER:
			remove_child(_collision[key])
			_active.erase(key)


## Collision chunks in the tree now.
func active_collision() -> Array[Vector2i]:
	var keys: Array[Vector2i] = []
	keys.assign(_active.keys())
	return keys


## The collision chunk a point is in.
func collision_key(x: float, z: float) -> Vector2i:
	var span := COLLISION_CELLS * cell
	return Vector2i(floori((x - origin.x) / span), floori((z - origin.y) / span))


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for key in _collision:
			if not _active.has(key):
				_collision[key].free()


func _collision_body(key: Vector2i) -> StaticBody3D:
	if _collision.has(key):
		return _collision[key]
	var faces := PackedVector3Array()
	var i0 := key.x * COLLISION_CELLS
	var j0 := key.y * COLLISION_CELLS
	var i1 := mini(i0 + COLLISION_CELLS, cells)
	var j1 := mini(j0 + COLLISION_CELLS, cells)
	for j in range(j0, j1):
		for i in range(i0, i1):
			var a := _point(i, j)
			var b := _point(i + 1, j)
			var c := _point(i, j + 1)
			var d := _point(i + 1, j + 1)
			faces.append_array([a, b, c, b, d, c])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.name = "Collision%d_%d" % [key.x, key.y]
	body.collision_layer = 1
	body.collision_mask = 0
	var holder := CollisionShape3D.new()
	holder.shape = shape
	body.add_child(holder)
	_collision[key] = body
	return body


func _point(i: int, j: int) -> Vector3:
	return Vector3(origin.x + i * cell, heights[j * (cells + 1) + i], origin.y + j * cell)


func _build_normals() -> void:
	var row := cells + 1
	normals.resize(row * row)
	for j in row:
		for i in row:
			var l := heights[j * row + maxi(i - 1, 0)]
			var r := heights[j * row + mini(i + 1, cells)]
			var u := heights[maxi(j - 1, 0) * row + i]
			var d := heights[mini(j + 1, cells) * row + i]
			normals[j * row + i] = Vector3(l - r, 2.0 * cell, u - d).normalized()


## Every chunk at every level, with the skirt on each edge as deep as the
## worst gap any two levels could leave there.
func _build_chunks() -> void:
	var count := chunks_per_side()
	for cj in count:
		for ci in count:
			var i0 := ci * CHUNK_CELLS
			var j0 := cj * CHUNK_CELLS
			var i1 := mini(i0 + CHUNK_CELLS, cells)
			var j1 := mini(j0 + CHUNK_CELLS, cells)
			# Skirt depth per edge: -z, +z, -x, +x.
			var edges := [
				_edge_error(i0, j0, 1, 0, i1 - i0), _edge_error(i0, j1, 1, 0, i1 - i0),
				_edge_error(i0, j0, 0, 1, j1 - j0), _edge_error(i1, j0, 0, 1, j1 - j0),
			]
			var depth := 0.5
			for e: float in edges:
				depth = maxf(depth, e * 2.0 + 0.5)
			var centre := Vector3(origin.x + (i0 + i1) * 0.5 * cell, 0.0, origin.y + (j0 + j1) * 0.5 * cell)
			var views: Array[MeshInstance3D] = []
			var depths := PackedFloat32Array()
			for level in LOD_STEPS.size():
				var view := MeshInstance3D.new()
				view.name = "Chunk%d_%d_%d" % [ci, cj, level]
				view.mesh = _chunk_mesh(i0, j0, i1, j1, LOD_STEPS[level], depth, centre)
				view.position = centre
				view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				view.visibility_range_begin = 0.0 if level == 0 else LOD_ENDS[level - 1]
				view.visibility_range_end = LOD_ENDS[level] if level < LOD_ENDS.size() else view_distance + CHUNK_CELLS * cell * 0.7
				add_child(view)
				views.append(view)
				depths.append(depth)
			chunk_views.append(views)
			skirt_depths.append(depths)


## The largest height difference along an edge between the full detail and
## any level, over steps cells from (i, j) in direction (di, dj).
func _edge_error(i: int, j: int, di: int, dj: int, steps: int) -> float:
	var worst := 0.0
	for step: int in LOD_STEPS:
		for k in steps + 1:
			var k0 := (k / step) * step
			var k1 := mini(k0 + step, steps)
			var t := 0.0 if k1 == k0 else float(k - k0) / (k1 - k0)
			var coarse := lerpf(height_index(i + di * k0, j + dj * k0), height_index(i + di * k1, j + dj * k1), t)
			worst = maxf(worst, absf(coarse - height_index(i + di * k, j + dj * k)))
	return worst


## One chunk's mesh at one level: a grid every step cells, then the skirt,
## a strip down from each edge facing both ways, coloured like the edge.
func _chunk_mesh(i0: int, j0: int, i1: int, j1: int, step: int, depth: float, centre: Vector3) -> ArrayMesh:
	var row := cells + 1
	var xs: Array[int] = []
	var zs: Array[int] = []
	for i in range(i0, i1, step):
		xs.append(i)
	xs.append(i1)
	for j in range(j0, j1, step):
		zs.append(j)
	zs.append(j1)
	var nx := xs.size()
	var nz := zs.size()
	var vertices := PackedVector3Array()
	var vertex_normals := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	for j: int in zs:
		for i: int in xs:
			var k := j * row + i
			vertices.append(Vector3(origin.x + i * cell, heights[k], origin.y + j * cell) - centre)
			vertex_normals.append(normals[k])
			# The ground shader picks its colour from these per pixel.
			colours.append(Color(normals[k].y, patches[k], 0.0))
	for b in nz - 1:
		for a in nx - 1:
			var p := b * nx + a
			var q := p + 1
			var r := p + nx
			var s := r + 1
			indices.append_array([p, q, r, q, s, r])
	# Skirts round the edge, in order: along -z, +x, +z backwards, -x backwards.
	var ring: Array[int] = []
	for a in nx:
		ring.append(a)
	for b in range(1, nz):
		ring.append(b * nx + nx - 1)
	for a in range(nx - 2, -1, -1):
		ring.append((nz - 1) * nx + a)
	for b in range(nz - 2, -1, -1):
		ring.append(b * nx)
	var first := vertices.size()
	for k: int in ring:
		vertices.append(vertices[k] + Vector3.DOWN * depth)
		vertex_normals.append(vertex_normals[k])
		colours.append(colours[k])
	for n in ring.size() - 1:
		var top0 := ring[n]
		var top1 := ring[n + 1]
		var low0 := first + n
		var low1 := first + n + 1
		indices.append_array([top0, top1, low0, top1, low1, low0])
		indices.append_array([top0, low0, top1, top1, low0, low1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = vertex_normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh
