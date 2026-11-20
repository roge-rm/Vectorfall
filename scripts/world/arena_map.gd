class_name ArenaMap
extends GameMap

## The new arenas share chunked ground, paired bases and the same bot
## points of interest. Each arena supplies its landform, cover and palette.

const CELL := 4.0
const ROUTE_STEP := 28.0
const ROUTE_REACH := 59.0

var play_half: Vector2
var _lane_titles: Array[String]
var _patch_noise := FastNoiseLite.new()


func _init(map_title: String, base_at: float, elevation: float, spawn_offset: float, seed_value: int, colours: Palette, play: Vector2, lanes: Array[String]) -> void:
	var started := Time.get_ticks_usec()
	title = map_title
	name = title.replace(" ", "")
	base_distance = base_at
	base_ground = elevation
	spawn_side = spawn_offset
	spawn_back = 14.0
	deck_depth = 5.0
	play_half = play
	_lane_titles = lanes
	palette = colours
	rng.seed = seed_value
	_patch_noise.seed = seed_value
	_patch_noise.frequency = 0.019
	atmosphere = Atmosphere.new(palette)
	add_child(atmosphere)
	_build_terrain()
	for team in 2:
		_build_base(team)
	var props := Node3D.new()
	props.name = "Cover"
	add_child(props)
	_dress(props)
	_boundaries()
	var graph_started := Time.get_ticks_usec()
	route_graph = _routes()
	graph_seconds = (Time.get_ticks_usec() - graph_started) / 1000000.0
	build_seconds = (Time.get_ticks_usec() - started) / 1000000.0


func _land(_x: float, _z: float) -> float:
	return 0.0


func _dress(_parent: Node3D) -> void:
	pass


func _lane_offsets() -> Vector3:
	return Vector3(-60, 0, 60)


func ground_height(x: float, z: float) -> float:
	return terrain.height_at(x, z)


func height_at(x: float, z: float) -> float:
	return ground_height(x, z)


func _build_terrain() -> void:
	var chunks := ceili((maxf(play_half.x, play_half.y) + 85.0) * 2.0 / (Terrain.CHUNK_CELLS * CELL))
	var cells := chunks * Terrain.CHUNK_CELLS
	var half := cells * CELL * 0.5
	var row := cells + 1
	var rows: Array = []
	rows.resize(row)
	var floor_y := room_floor() - 1.5
	var fill := func(j: int) -> void:
		var z := j * CELL - half
		var heights := PackedFloat32Array()
		var patches := PackedFloat32Array()
		var shown := PackedFloat32Array()
		heights.resize(row)
		patches.resize(row)
		shown.resize(row)
		for i in range(cells / 2, row):
			var x := i * CELL - half
			var around_base := Vector2(x - base_distance, z * 0.58).length()
			var height := lerpf(base_ground, _land(x, z), smoothstep(64.0, 111.0, around_base))
			var edge := maxf(smoothstep(play_half.x - 26.0, play_half.x + 72.0, x), smoothstep(play_half.y - 20.0, play_half.y + 70.0, absf(z)))
			height += 33.0 * edge * edge
			var solid := minf(height, floor_y) if under_room(x, z, CELL) else height
			var patch := _patch_noise.get_noise_2d(x, z) * 0.5 + 0.5
			for column: int in [i, cells - i]:
				heights[column] = solid
				patches[column] = patch
				shown[column] = height
		rows[j] = [heights, patches, shown]
	var task := WorkerThreadPool.add_group_task(fill, row)
	WorkerThreadPool.wait_for_group_task_completion(task)
	var heights := PackedFloat32Array()
	var patches := PackedFloat32Array()
	var shown := PackedFloat32Array()
	for samples: Array in rows:
		heights.append_array(samples[0])
		patches.append_array(samples[1])
		shown.append_array(samples[2])
	terrain = Terrain.new(cells, CELL, Vector2(-half, -half), heights, patches, shown)
	add_child(terrain)


## A cover piece and its footprint in the route graph.
func prop(parent: Node3D, at: Vector2, size: Vector3, colour: Color, yaw := 0.0) -> void:
	var where := Vector3(at.x, surface_at(at.x, at.y) + size.y * 0.5 - 0.15, at.y)
	var cover := _box(parent, size, Transform3D(Basis(Vector3.UP, yaw), where), Cel.material(colour))
	var view := cover.get_child(0) as MeshInstance3D
	view.mesh = Cel.bevel_box(size, 0.16)
	view.visibility_range_end = 450.0
	obstacles.append(Vector3(at.x, at.y, Vector2(size.x, size.z).length() * 0.5))


func _boundaries() -> void:
	for side: float in [-1.0, 1.0]:
		for along_x in [false, true]:
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(play_half.x * 2.0 + 8.0, 1200.0, 4.0) if along_x else Vector3(4.0, 1200.0, play_half.y * 2.0 + 8.0)
			shape.shape = box
			body.position = Vector3(0, 300, side * (play_half.y + 2.0)) if along_x else Vector3(side * (play_half.x + 2.0), 300, 0)
			body.add_child(shape)
			add_child(body)


func _point(graph: RouteGraph, x: float, z: float) -> int:
	return graph.add_point(Vector3(x, surface_at(x, z), z))


func _routes() -> RouteGraph:
	var graph := RouteGraph.new()
	graph.lane_titles.assign(_lane_titles)
	var span := Vector2i((play_half - Vector2(22, 22)) / ROUTE_STEP)
	for i in range(-span.x, span.x + 1):
		for j in range(-span.y, span.y + 1):
			var x := i * ROUTE_STEP
			var z := j * ROUTE_STEP
			if not near_base(x, z, 5.0) and not blocked_at(x, z) and terrain.normal_at(x, z).y > 0.66:
				_point(graph, x, z)
	add_base_points(graph)
	var lanes := _lane_offsets()
	for team in 2:
		var x := base_x(team)
		var towards := front(team)
		for lane in 3:
			var approach := x + towards * 64.0
			graph.add_interest(RouteGraph.FLAG_APPROACH, team, _point(graph, approach, lanes[lane]))
		graph.add_interest(RouteGraph.VEHICLE_PAD, team, _point(graph, x - towards * 52.0, 0.0))
		for side: float in [-1.0, 1.0]:
			graph.add_interest(RouteGraph.DEPLOY, team, _point(graph, x + towards * 24.0, side * 25.0))
			graph.add_interest(RouteGraph.DEFENCE, team, _point(graph, x + towards * 35.0, side * 22.0))
		graph.add_interest(RouteGraph.HIGH_GROUND, -1, _point(graph, x * 0.47, 0.0))
	graph.auto_link(ROUTE_REACH, surface_at, blocked_at, 3.0)
	link_tower_tops(graph)
	link_generator_rooms(graph)
	return graph
