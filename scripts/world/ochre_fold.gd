class_name OchreFold
extends GameMap

## Ochre Fold, the first full size map: 1.5 km of folded sand between two
## bases on high ground at x = ±560 m. Built from noise and shaped features:
##   - Ridges across the middle every 187 m, broad on top, with the bases on
##     the outermost pair. Skiing down from a base and jetting over each ridge
##     is the short, open way across.
##   - A long winding canyon to the north (+z), sinking gently to the middle:
##     longer and sheltered, a carrier's back road.
##   - A high spine to the south (−z) joining the two bases' ridges, with
##     saddles along its top: exposed, with sniper perches along it.
##   - Four flat topped mesas in the middle for cover and perches, boulders
##     and rock spires scattered over it all.
##   - Mountains round the edge with an invisible wall past them.
## The map is mirrored in x, so both teams have the same ground.

const CELLS := 384
const CELL := 4.0
const HALF := CELLS * CELL * 0.5
const BASE_X := 560.0
const BASE_GROUND := 46.0
const MAP_SEED := 31
## Ridges between the middle and each base, counting the middle one.
const RIDGE_CYCLES := 3.0
## Ridge to valley height in the middle, in metres.
const RIDGE_HEIGHT := 36.0
## How much higher the ground round the bases is than the middle.
const BASE_LIFT := 46.0
## The flat ground round each base and where it blends into the hills.
const BASE_FLAT := 50.0
const BASE_BLEND := 110.0
## The playable area, past which the edge mountains rise.
const PLAY_X := 690.0
const PLAY_Z := 590.0
## The invisible wall at the edge.
const WALL := 742.0
## Route graph lattice spacing, and how far its links reach, in metres.
const LATTICE := 32.0
const LINK_REACH := 74.0
## Ground sampling steps for links, near buildings and elsewhere, in metres.
const LINK_STEP := 1.5
const LINK_FLAT_STEP := 4.0
## Rock and spire views stop being drawn this far away, in metres.
const PROP_RANGE := 380.0
## Where the baked route links are kept (tools/bake-routes.sh).
const ROUTES_FILE := "res://maps/ochre_fold.routes"

## Mesas as (x, z, top height above the ground round them).
const MESAS: Array[Vector3] = [Vector3(250.0, -105.0, 16.0), Vector3(-250.0, -105.0, 16.0), Vector3(150.0, 120.0, 14.0), Vector3(-150.0, 120.0, 14.0)]
const MESA_TOP := 15.0
const MESA_FOOT := 25.0

## Extra points of interest, kept as data for later milestones.
var vehicle_pads: Array[Vector3] = []
var deploy_spots: Array[Vector3] = []

var broad := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var patch_noise := FastNoiseLite.new()
## Seconds spent cutting the terrain into chunks and meshes.
var terrain_seconds := 0.0
## Each mesa's top height, worked out from the ground round it.
var _mesa_tops: Array[float] = []
## False builds the route links from the ground, as the baking tool does.
static var use_baked_routes := true
## The key the baked links must match, the range of them in the graph, and whether they were loaded from the file.
var route_key := ""
var route_first_link := 0
var route_end_link := 0
var routes_loaded := false


## with_graph false leaves out the route graph, for a backdrop with no bots.
func _init(colours: Palette = null, with_graph := true) -> void:
	name = "OchreFold"
	title = "Ochre Fold"
	var started := Time.get_ticks_usec()
	base_distance = BASE_X
	base_ground = BASE_GROUND
	# Spawns are 200 m out to the side, on the flat spine top to the south
	# and the canyon floor to the north, so a carrier at the stand isn't next
	# to enemies coming back to life.
	spawn_side = 200.0
	spawn_back = 20.0
	deck_depth = 6.0
	palette = colours if colours != null else OchreFold.palette_for_map()
	rng.seed = MAP_SEED
	broad.seed = MAP_SEED
	broad.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	broad.frequency = 0.0035
	broad.fractal_octaves = 3
	detail.seed = MAP_SEED + 1
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.frequency = 0.016
	detail.fractal_octaves = 2
	patch_noise.seed = MAP_SEED + 2
	patch_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	patch_noise.frequency = 0.018
	for mesa in MESAS:
		_mesa_tops.append(_shape(mesa.x, mesa.y, false) + mesa.z)
	atmosphere = Atmosphere.new(palette)
	add_child(atmosphere)
	var t := Time.get_ticks_usec()
	_build_ground()
	if Prof.on:
		Prof.add("build.ground_heights", int(Time.get_ticks_usec() - t - terrain_seconds * 1000000.0))
		Prof.add("build.terrain_chunks", int(terrain_seconds * 1000000.0))
		t = Time.get_ticks_usec()
	for team in 2:
		_build_base(team)
	if Prof.on:
		Prof.add("build.bases", Time.get_ticks_usec() - t)
		t = Time.get_ticks_usec()
	_build_props()
	if Prof.on:
		Prof.add("build.props", Time.get_ticks_usec() - t)
		t = Time.get_ticks_usec()
	_build_walls()
	if Prof.on:
		Prof.add("build.walls", Time.get_ticks_usec() - t)
	var graph_started := Time.get_ticks_usec()
	if with_graph:
		route_graph = build_route_graph()
	graph_seconds = (Time.get_ticks_usec() - graph_started) / 1000000.0
	build_seconds = (Time.get_ticks_usec() - started) / 1000000.0


## The paperback look, with pale sand on the canyon floor and the deepest
## valleys, and turquoise on the mountain tops.
static func palette_for_map() -> Palette:
	var made := Palette.paperback()
	made.title = "Ochre Fold"
	made.low_height = -16.0
	made.high_height = 80.0
	return made


## Where the canyon runs, its middle in z for a point along x.
static func canyon_z(x: float) -> float:
	return 270.0 + 30.0 * cos(x / 160.0)


## Where the spine runs, its middle in z for a point along x.
static func spine_z(x: float) -> float:
	return -230.0 - 50.0 * cos(x * PI / (BASE_X * 2.0))


func height_at(x: float, z: float) -> float:
	return terrain.height_at(x, z) if terrain != null else _shape(x, z)


func ground_height(x: float, z: float) -> float:
	return terrain.height_at(x, z) if terrain != null else _shape(x, z)


## The ground's shape before it's cut into a mesh. Mirrored in x, so noise is
## read at |x|.
func _shape(x: float, z: float, mesas := true) -> float:
	var ax := absf(x)
	var az := absf(z)
	# Ridges across the map, bent along z away from the middle one.
	var bend := (16.0 * sin(z * 0.011) + 9.0 * sin(z * 0.029 + 1.3)) * smoothstep(0.0, 120.0, ax)
	var wave := cos(TAU * RIDGE_CYCLES * (ax + bend) / BASE_X)
	# Broad ridge tops that don't throw you, and tighter valleys.
	var ridge := 1.0 - pow(1.0 - (wave + 1.0) * 0.5, 1.5)
	var vary := broad.get_noise_2d(ax, z)
	var depth := RIDGE_HEIGHT * (0.85 + 0.3 * vary) * lerpf(1.0, 0.6, smoothstep(300.0, 520.0, ax))
	var h := (ridge - 1.0) * depth + BASE_LIFT * smoothstep(100.0, 620.0, ax)
	h += vary * 6.0 + detail.get_noise_2d(ax, z) * 1.8
	# The canyon to the north, sinking towards the middle.
	var canyon := 1.0 - smoothstep(45.0, 125.0, absf(z - canyon_z(x)))
	if canyon > 0.0:
		var floor_h := -18.0 + 40.0 * smoothstep(250.0, 600.0, ax) + vary * 2.0
		h = lerpf(h, floor_h, canyon * canyon * (3.0 - 2.0 * canyon))
	# The spine to the south, with saddles along its top.
	var spine := 1.0 - smoothstep(18.0, 115.0, absf(z - spine_z(x)))
	if spine > 0.0:
		var top := 30.0 + 14.0 * smoothstep(200.0, 560.0, ax) + 6.0 * cos(ax / 70.0) + vary * 3.0
		h = maxf(h, lerpf(h, top, spine * spine * (3.0 - 2.0 * spine)))
	if mesas:
		for k in MESAS.size():
			var m := MESAS[k]
			var d := Vector2(ax - absf(m.x), z - m.y).length()
			if d < MESA_FOOT:
				var up := 1.0 - smoothstep(MESA_TOP, MESA_FOOT, d)
				h = maxf(h, lerpf(h, _mesa_tops[k], up))
	# Flat round each base.
	var to_base := Vector2(ax - BASE_X, z).length()
	h = lerpf(BASE_GROUND, h, smoothstep(BASE_FLAT, BASE_BLEND, to_base))
	# Lumpy mountains round the edge, rising over about 150 m.
	var edge := maxf(smoothstep(PLAY_X - 70.0, HALF + 30.0, ax), smoothstep(PLAY_Z - 70.0, HALF + 30.0, az))
	return h + edge * edge * (100.0 + 50.0 * vary + 25.0 * detail.get_noise_2d(ax * 0.3, z * 0.3))


func _build_ground() -> void:
	var row := CELLS + 1
	var heights := PackedFloat32Array()
	var patches := PackedFloat32Array()
	var shown := PackedFloat32Array()
	var middle := CELLS / 2
	# Under each generator room the ground drops below the room's floor, so
	# it doesn't show or collide inside. Every corner of a cell that reaches
	# into the room drops, so no slope comes up inside; that stays under the
	# deck as the room is more than a cell from the deck's edges. The coarser
	# levels of detail keep the ground as it was, so they show no dip by the
	# base from far off.
	var dropped := room_floor() - 1.5
	# The map is mirrored in x, so work out the +x half and copy it over. Rows
	# are worked out on worker threads, which only read the noise and each
	# fill their own slot of rows.
	var rows: Array = []
	rows.resize(row)
	var fill_row := func(j: int) -> void:
		var z := -HALF + j * CELL
		var h := PackedFloat32Array()
		var p := PackedFloat32Array()
		var d := PackedFloat32Array()
		h.resize(row)
		p.resize(row)
		d.resize(row)
		for i in range(middle, row):
			var x := -HALF + i * CELL
			var dv := _shape(x, z)
			var hv := minf(dv, dropped) if under_room(x, z, CELL) else dv
			var pv := patch_noise.get_noise_2d(x, z) * 0.5 + 0.5
			h[i] = hv
			p[i] = pv
			d[i] = dv
			h[CELLS - i] = hv
			p[CELLS - i] = pv
			d[CELLS - i] = dv
		rows[j] = [h, p, d]
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(fill_row, row))
	heights.clear()
	patches.clear()
	for j in row:
		heights.append_array(rows[j][0])
		patches.append_array(rows[j][1])
		shown.append_array(rows[j][2])
	var shaped := Time.get_ticks_usec()
	terrain = Terrain.new(CELLS, CELL, Vector2(-HALF, -HALF), heights, patches, shown)
	add_child(terrain)
	terrain_seconds = (Time.get_ticks_usec() - shaped) / 1000000.0


## Boulders and spires for cover, kept off the bases, the mesas and the
## middle of the canyon floor. Mirrored, so each team has the same.
func _build_props() -> void:
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)
	var placed := 0
	var tries := 0
	while placed < 26 and tries < 400:
		tries += 1
		var x := rng.randf_range(60.0, 520.0)
		var z := rng.randf_range(-520.0, 520.0)
		if not _prop_spot(x, z):
			continue
		var size := rng.randf_range(2.5, 6.0)
		for side in [-1.0, 1.0]:
			var at := Vector3(side * x, ground_height(side * x, z) - size * 0.3, z)
			_far_cut(_rock(props, at, size))
			obstacles.append(Vector3(side * x, z, size * 1.2))
		placed += 1
	# Rocks round the foot of each mesa.
	for k in MESAS.size():
		var m := MESAS[k]
		for n in 3:
			var angle := rng.randf_range(0.0, TAU)
			var x := m.x + cos(angle) * (MESA_FOOT + 4.0)
			var z := m.y + sin(angle) * (MESA_FOOT + 4.0)
			var size := rng.randf_range(2.5, 4.5)
			_far_cut(_rock(props, Vector3(x, ground_height(x, z) - size * 0.3, z), size))
			obstacles.append(Vector3(x, z, size * 1.2))
		obstacles.append(Vector3(m.x, m.y, MESA_FOOT - 4.0))
	placed = 0
	tries = 0
	while placed < 5 and tries < 200:
		tries += 1
		var x := rng.randf_range(80.0, 480.0)
		var z := rng.randf_range(-480.0, 480.0)
		if not _prop_spot(x, z):
			continue
		var tall := rng.randf_range(10.0, 22.0)
		for side in [-1.0, 1.0]:
			var at := Vector3(side * x, ground_height(side * x, z) - 1.0 + tall * 0.5, z)
			_far_cut(_pillar(props, at, 1.8, tall))
			obstacles.append(Vector3(side * x, z, 1.8))
		placed += 1


## True where a prop can go: off the bases, mesas, canyon floor and other props.
func _prop_spot(x: float, z: float) -> bool:
	if Vector2(x - BASE_X, z).length() < BASE_BLEND + 20.0:
		return false
	if absf(z - canyon_z(x)) < 30.0:
		return false
	for m in MESAS:
		if Vector2(x - absf(m.x), z - m.y).length() < MESA_FOOT + 12.0:
			return false
	for o in obstacles:
		if Vector2(x - o.x, z - o.y).length() < o.z + 25.0:
			return false
	return true


## Stops drawing a prop far away, where it's under a pixel or two.
func _far_cut(body: StaticBody3D) -> void:
	for child in body.get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).visibility_range_end = PROP_RANGE


## Invisible walls just inside the map's edge, past the mountains.
func _build_walls() -> void:
	for k in 4:
		var along_x := k < 2
		var side := -1.0 if k % 2 == 0 else 1.0
		var body := StaticBody3D.new()
		body.name = "Wall%d" % k
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(HALF * 2.0, 1200.0, 10.0) if along_x else Vector3(10.0, 1200.0, HALF * 2.0)
		shape.shape = box
		body.add_child(shape)
		body.position = Vector3(0.0, 300.0, side * (WALL + 5.0)) if along_x else Vector3(side * (WALL + 5.0), 300.0, 0.0)
		add_child(body)


## Each route point's twin across x = 0, or -1, matched by position.
func _mirrors(graph: RouteGraph) -> PackedInt32Array:
	var by_place := {}
	for k in graph.points.size():
		by_place[Vector2i(roundi(graph.points[k].x * 10.0), roundi(graph.points[k].z * 10.0))] = k
	var twins := PackedInt32Array()
	for k in graph.points.size():
		twins.append(by_place.get(Vector2i(roundi(-graph.points[k].x * 10.0), roundi(graph.points[k].z * 10.0)), -1))
	return twins


## The ground's height and whether it's blocked at a spread of spots between
## the route points, and the link rules, as text for the baked links' key.
func _probe() -> String:
	var text := "%s %s %s %s %s %s" % [RouteGraph.WALL_SLOPE, RouteGraph.STEEP_SLOPE, RouteGraph.WALL_KINK, RouteGraph.SIDE_CHECK, RouteGraph.JET_SLOPE, RouteGraph.SKI_SLOPE]
	for k in 97:
		var x := fposmod(k * 137.5, 1380.0) - 690.0 + 0.37 * k
		var z := fposmod(k * 71.3, 1180.0) - 590.0 + 0.11 * k
		text += " %.3f %d" % [surface_at(x, z), 1 if blocked_at(x, z) else 0]
	# The deck over each generator room and its openings.
	for team in 2:
		for at in [base_place(team, OPENING_AT.x, OPENING_AT.y, 0.0), base_place(team, -2.0, 0.0, 0.0)]:
			text += " %.3f" % surface_at(at.x, at.z)
	return text


## True for a link near a base or a mesa, where the ground beside it can
## hide a wall, so it's checked in finer steps and to each side. The rest of
## the ground is too smooth to.
func _needs_sides(a: Vector3, b: Vector3) -> bool:
	for p in [a, b]:
		if Vector2(absf(p.x) - BASE_X, p.z).length() < 90.0:
			return true
		for m in MESAS:
			if Vector2(p.x - m.x, p.z - m.y).length() < MESA_FOOT + 30.0:
				return true
	return false


## The bots' route graph: a lattice every 32 m over the playable ground, the
## base points, and the points of interest, linked to neighbours up to 74 m
## away.
func build_route_graph() -> RouteGraph:
	var graph_t := Time.get_ticks_usec()
	var graph := RouteGraph.new()
	graph.lane_titles.assign(["north canyon", "middle", "south spine"])
	var reach_x := int(PLAY_X / LATTICE)
	var reach_z := int(PLAY_Z / LATTICE)
	for i in range(-reach_x, reach_x + 1):
		for j in range(-reach_z, reach_z + 1):
			var x := i * LATTICE
			var z := j * LATTICE
			if near_base(x, z, 6.0) or blocked_at(x, z):
				continue
			# Too steep to stand on.
			if terrain.normal_at(x, z).y < 0.64:
				continue
			graph.add_point(Vector3(x, surface_at(x, z), z))
	add_base_points(graph)
	for team in 2:
		var bx := base_x(team)
		var ahead := front(team)
		# Spots round the base to hold, on the flat ground off the deck.
		for spot in [Vector2(30.0, 25.0), Vector2(30.0, -25.0)]:
			var x: float = bx + ahead * spot.x
			graph.add_interest(RouteGraph.DEFENCE, team, graph.add_point(Vector3(x, surface_at(x, spot.y), spot.y)))
		# The three ways to the flag: straight up the front, from the canyon
		# and from the spine.
		var approaches := [Vector2(bx + ahead * 120.0, 0.0), Vector2(bx + ahead * 70.0, canyon_z(bx + ahead * 70.0) - 60.0), Vector2(bx + ahead * 70.0, spine_z(bx) + 30.0)]
		for a: Vector2 in approaches:
			graph.add_interest(RouteGraph.FLAG_APPROACH, team, graph.add_point(Vector3(a.x, surface_at(a.x, a.y), a.y)))
		# Behind the base for vehicle pads later, and spots to deploy on.
		var pad := Vector3(bx - ahead * 60.0, 0.0, 0.0)
		pad.y = surface_at(pad.x, pad.z)
		vehicle_pads.append(pad)
		graph.add_interest(RouteGraph.VEHICLE_PAD, team, graph.add_point(pad))
		for spot in [Vector2(-20.0, 32.0), Vector2(-20.0, -32.0), Vector2(36.0, 0.0)]:
			var at := Vector3(bx + ahead * spot.x, 0.0, spot.y)
			at.y = surface_at(at.x, at.z)
			deploy_spots.append(at)
			graph.add_interest(RouteGraph.DEPLOY, team, graph.add_point(at))
	# Ridge tops in the middle of each half, for midfield and the offence's
	# rally.
	for side in [-1.0, 1.0]:
		for spot in [Vector2(187.0, -50.0), Vector2(187.0, 50.0), Vector2(373.0, 0.0)]:
			var x: float = side * spot.x
			graph.add_interest(RouteGraph.HIGH_GROUND, -1, graph.add_point(Vector3(x, surface_at(x, spot.y), spot.y)))
		var on_spine := Vector2(side * 300.0, spine_z(300.0))
		graph.add_interest(RouteGraph.SNIPER, -1, graph.add_point(Vector3(on_spine.x, surface_at(on_spine.x, on_spine.y), on_spine.y)))
	if Prof.on:
		Prof.add("build.graph.points", Time.get_ticks_usec() - graph_t)
		graph_t = Time.get_ticks_usec()
	var twins := _mirrors(graph)
	if Prof.on:
		Prof.add("build.graph.mirrors", Time.get_ticks_usec() - graph_t)
		graph_t = Time.get_ticks_usec()
	route_first_link = graph.links.size()
	route_key = RouteBake.key_for(graph.points, "%d %d %s %s %s %s" % [MAP_SEED, graph.links.size(), LINK_REACH, LINK_STEP, LINK_FLAT_STEP, _probe()])
	routes_loaded = use_baked_routes and RouteBake.load_into(ROUTES_FILE, route_key, graph)
	if not routes_loaded:
		if use_baked_routes:
			push_warning("Ochre Fold: baked route links missing or out of date, building them (run tools/bake-routes.sh)")
		graph.auto_link_pairs(LINK_REACH, surface_at, blocked_at, LINK_STEP, LINK_FLAT_STEP, _needs_sides, twins)
	route_end_link = graph.links.size()
	if Prof.on:
		Prof.add("build.graph.auto_link_pairs", Time.get_ticks_usec() - graph_t)
		graph_t = Time.get_ticks_usec()
	# Each mesa top, jetted up to from a point at its foot on the side
	# facing the middle, and dropped off back to it.
	for k in MESAS.size():
		var m := MESAS[k]
		var top := graph.add_point(Vector3(m.x, _mesa_tops[k], m.y))
		graph.add_interest(RouteGraph.SNIPER, -1, top)
		var toward := Vector2(-m.x, -m.y).normalized()
		var foot_at := Vector2(m.x, m.y) + toward * (MESA_FOOT + 3.0)
		var foot := graph.nearest(Vector3(foot_at.x, surface_at(foot_at.x, foot_at.y), foot_at.y))
		graph.add_link(foot, top, RouteGraph.Kind.JET, true)
		graph.add_link(top, foot, RouteGraph.Kind.SKI)
	link_tower_tops(graph)
	link_generator_rooms(graph)
	if Prof.on:
		Prof.add("build.graph.mesas_towers", Time.get_ticks_usec() - graph_t)
	return graph
