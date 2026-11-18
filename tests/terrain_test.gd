extends SceneTree

## Checks the chunked terrain on a small made up heightfield: the height
## lookup matches the mesh, chunks at every pair of detail levels meet with
## their skirts covering any gap, collision is under a soldier and nowhere
## near nothing, a shot hits the ground far from any collision, and skiing
## across collision chunk edges at speed is smooth.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/terrain_test.gd

const CELLS := 144
const CELL := 4.0

var checks := TestWorld.Checks.new()
var terrain: Terrain
var game: Match
var input := TestWorld.Scripted.new()


func _initialize() -> void:
	_run.call_deferred()


## Rolling hills falling gently towards +x, steep in places.
static func hills(x: float, z: float) -> float:
	return 30.0 * sin(x * 0.021) * cos(z * 0.017) + 12.0 * sin(x * 0.06 + z * 0.045) - x * 0.15


func _run() -> void:
	var row := CELLS + 1
	var heights := PackedFloat32Array()
	var patches := PackedFloat32Array()
	var corner := Vector2(-CELLS * CELL * 0.5, -CELLS * CELL * 0.5)
	for j in row:
		for i in row:
			heights.append(hills(corner.x + i * CELL, corner.y + j * CELL))
			patches.append(0.5)
	terrain = Terrain.new(CELLS, CELL, corner, heights, patches)
	root.add_child(terrain)
	game = Match.new(3)
	game.terrain = terrain
	root.add_child(game)
	await physics_frame

	_check_height_matches_mesh()
	_check_seams()
	await _check_collision()
	await _check_far_shot()
	await _check_ski_across_chunks()
	checks.finish(self)


func _check_height_matches_mesh() -> void:
	# The full detail mesh of every chunk as collision, to cast rays down on.
	var body := StaticBody3D.new()
	body.collision_layer = 8
	for views in terrain.chunk_views:
		var view: MeshInstance3D = views[0]
		var shape := CollisionShape3D.new()
		shape.shape = view.mesh.create_trimesh_shape()
		shape.position = view.position
		body.add_child(shape)
	root.add_child(body)
	var space := body.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var worst := 0.0
	var missed := 0
	var half := CELLS * CELL * 0.5 - 1.0
	for k in 400:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var query := PhysicsRayQueryParameters3D.create(Vector3(x, 500.0, z), Vector3(x, -500.0, z), 8)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			missed += 1
			continue
		worst = maxf(worst, absf(hit.position.y - terrain.height_at(x, z)))
	body.free()
	checks.check(missed == 0 and worst < 0.01, "height_at() matches the full detail mesh at 400 points (worst %.4f m)" % worst)


## The height along a chunk's edge in one level's mesh, at each full detail
## point from its first corner.
func _edge(views: Array, level: int, axis: int, at: float) -> Dictionary:
	var view: MeshInstance3D = views[level]
	var arrays := view.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var step := Terrain.LOD_STEPS[level]
	var per_side := Terrain.CHUNK_CELLS / step + 1
	var points := {}
	for k in per_side * per_side:
		var p := vertices[k] + view.position
		var along := p.z if axis == 0 else p.x
		var across := p.x if axis == 0 else p.z
		if absf(across - at) < 0.01:
			points[roundi(along / CELL)] = p.y
	var keys := points.keys()
	keys.sort()
	var heights := {}
	for n in keys.size() - 1:
		var a: int = keys[n]
		var b: int = keys[n + 1]
		for k in range(a, b + 1):
			heights[k] = lerpf(points[a], points[b], float(k - a) / (b - a))
	return heights


func _check_seams() -> void:
	var per_side := terrain.chunks_per_side()
	var levels := Terrain.LOD_STEPS.size()
	var worst_gap := 0.0
	var uncovered := 0
	var edges := 0
	for cj in per_side:
		for ci in per_side:
			var here: Array = terrain.chunk_views[cj * per_side + ci]
			# The neighbour to +x shares the edge at x, the one to +z at z.
			for axis in 2:
				var ni := ci + (1 if axis == 0 else 0)
				var nj := cj + (1 if axis == 1 else 0)
				if ni >= per_side or nj >= per_side:
					continue
				var there: Array = terrain.chunk_views[nj * per_side + ni]
				var at := terrain.origin.x + ni * Terrain.CHUNK_CELLS * CELL if axis == 0 else terrain.origin.y + nj * Terrain.CHUNK_CELLS * CELL
				for la in levels:
					for lb in levels:
						var a := _edge(here, la, axis, at)
						var b := _edge(there, lb, axis, at)
						edges += 1
						var depth_a: float = terrain.skirt_depths[cj * per_side + ci][la]
						var depth_b: float = terrain.skirt_depths[nj * per_side + ni][lb]
						for k: int in a:
							var gap: float = a[k] - b[k]
							worst_gap = maxf(worst_gap, absf(gap))
							if (gap > 0.0 and gap > depth_a) or (gap < 0.0 and -gap > depth_b):
								uncovered += 1
	checks.check(edges > 0 and uncovered == 0, "%d chunk edges at every pair of levels: skirts cover every gap (largest %.2f m)" % [edges, worst_gap])


func _check_collision() -> void:
	var at := Vector3(100.0, 0.0, -60.0)
	at.y = terrain.height_at(at.x, at.z) + 1.0
	var soldier := game.add_soldier(0, Transform3D(Basis.IDENTITY, at), input)
	for i in 60:
		await physics_frame
	var key := terrain.collision_key(soldier.global_position.x, soldier.global_position.z)
	var active := terrain.active_collision()
	checks.check(active.has(key), "the collision chunk under the soldier is there (%d chunks in all)" % active.size())
	checks.check(soldier.grounded and absf(soldier.global_position.y - terrain.height_at(soldier.global_position.x, soldier.global_position.z)) < 0.2, "the soldier stands on the ground")
	var far := terrain.collision_key(-250.0, 250.0)
	checks.check(not active.has(far), "there's no collision far from the soldier")
	var space := soldier.get_world_3d().direct_space_state
	var p := soldier.global_position + Vector3(3.0, 0.0, 3.0)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 50.0, p + Vector3.DOWN * 50.0, Match.WORLD_LAYER, [soldier.get_rid()]))
	checks.check(not hit.is_empty() and absf(hit.position.y - terrain.height_at(p.x, p.z)) < 0.01, "a ray beside the soldier hits the collision at the ground's height")


func _check_far_shot() -> void:
	# A disc dropped onto a hillside far from the soldier, where there's no
	# collision.
	var target := Vector3(-220.0, 0.0, 220.0)
	target.y = terrain.height_at(target.x, target.z)
	var shot := Projectile.new()
	shot.weapon = Weapon.DISC
	shot.position = target + Vector3(-30.0, 40.0, 0.0)
	shot.velocity = (target - shot.position).normalized() * 65.0
	game.projectiles.append(shot)
	var impacts: Array[Vector3] = []
	var on_impact := func(_weapon: int, where: Vector3, _normal: Vector3) -> void: impacts.append(where)
	game.impacted.connect(on_impact)
	for i in 120:
		await physics_frame
	game.impacted.disconnect(on_impact)
	var no_collision := not terrain.active_collision().has(terrain.collision_key(target.x, target.z))
	checks.check(no_collision and impacts.size() == 1 and impacts[0].distance_to(target) < 1.5, "a shot hits the ground far from any collision, %.2f m from where it was aimed" % (impacts[0].distance_to(target) if impacts.size() > 0 else -1.0))
	var a := Vector3(-300.0, 200.0, 0.0)
	var b := Vector3(-300.0, -200.0, 0.0)
	checks.check(not game.line_clear(a, b) and game.line_clear(a, a + Vector3.RIGHT * 50.0), "sight lines are blocked by the ground and clear above it")


func _check_ski_across_chunks() -> void:
	# A flat slope down along +x, 6°, crossing several collision chunks.
	var row := CELLS + 1
	var heights := PackedFloat32Array()
	var patches := PackedFloat32Array()
	var corner := Vector2(-CELLS * CELL * 0.5, -CELLS * CELL * 0.5)
	for j in row:
		for i in row:
			heights.append(-(corner.x + i * CELL) * tan(deg_to_rad(6.0)))
			patches.append(0.5)
	var slope := Terrain.new(CELLS, CELL, corner, heights, patches)
	root.add_child(slope)
	var match_node := Match.new(4)
	match_node.terrain = slope
	terrain.free()
	game.free()
	root.add_child(match_node)
	var ski := TestWorld.Scripted.new()
	var start := Vector3(-250.0, 0.0, 10.0)
	start.y = slope.height_at(start.x, start.z) + 0.3
	var soldier := match_node.add_soldier(0, Transform3D(Basis(Vector3.UP, -PI * 0.5), start), ski)
	soldier.velocity = Vector3(40.0, 0.0, 0.0)
	ski.command.yaw = -PI * 0.5
	ski.command.move = Vector2(0.0, 1.0)
	ski.command.buttons = PlayerCommand.SKI
	var last := 0.0
	var worst_drop := 0.0
	var airborne := 0
	var crossed := {}
	for i in 420:
		await physics_frame
		var speed := Vector3(soldier.velocity.x, 0.0, soldier.velocity.z).length()
		if i > 30:
			worst_drop = maxf(worst_drop, last - speed)
			if not soldier.grounded:
				airborne += 1
		last = speed
		crossed[slope.collision_key(soldier.global_position.x, soldier.global_position.z)] = true
		if soldier.global_position.x > 250.0:
			break
	checks.check(crossed.size() >= 5 and worst_drop < 0.5 and airborne < 10, "skiing at %.0f m/s over %d collision chunks never loses more than %.2f m/s in a tick, %d ticks in the air" % [last, crossed.size(), worst_drop, airborne])
