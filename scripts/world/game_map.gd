class_name GameMap
extends Node3D

## What every map has: two bases on the x axis, team 0's at -x and team 1's at
## +x, each a raised deck with a ramp at the front, a tower at the back and the
## flag stand in the middle, spawn points to the side of the base, things the bots
## can't pass, and the bots' route graph. A map script extends it and builds
## its ground, props and route graph.

const BASE_SIZE := 30.0
const STAND_HEIGHT := 0.5
## The ramp up the front of each base: its length along the ground and its
## slope, for 14 m at 12°.
const RAMP_RUN := 13.69
const RAMP_SLOPE := 0.2126
## Ramp centre in z and width, in metres.
const BASE_RAMPS: Array[Vector2] = [Vector2(0, 10), Vector2(-10.5, 6.5), Vector2(10.5, 6.5)]
## Grid cell size for looking up obstacles, in metres.
const OBSTACLE_CELL := 10.0
## The generator room under the back of each base's deck. Places in it are
## given relative to the base's middle as (along, side), with along towards
## the other base. Its floor is ROOM_DEPTH below the deck top, under a 1 m
## ceiling, and it reaches ROOM_HALF to each side. The ground under it is cut
## or lowered, so a map's ground cells must be no wider than 4 m for the
## room's footprint grown by a cell to stay under the deck.
const ROOM_DEPTH := 4.0
const ROOM_BACK := -7.5
const ROOM_FRONT := 0.5
const ROOM_HALF := 7.5
## The two ways into the room, 3 m square holes in the deck at its back
## corners, each closed by a force field: the middle of the one on the +side
## side, and their size.
const OPENING_AT := Vector2(-6.0, 6.0)
const OPENING := 3.0
## The room turret only fires at enemies within this many metres of one of
## its base's openings across the ground, so it guards the way in and leaves
## the flag to the other turret.
const ROOM_GUARD := 6.0
## A force field's box: it fills its opening, as deep as the ceiling.
const FIELD_SIZE := Vector3(3.0, 1.0, 3.0)
## The map main.gd loads when nothing else is asked for.
const DEFAULT := "ochre_fold"
## Arenas with a neutral midfield ammo station.
const RESUPPLY_ARENAS: Array[String] = ["nightline_foundry", "gannet_reach"]
const NAMES: Array[String] = [
	"ochre_fold", "test", "saltwake_flats", "nightline_foundry", "copper_steps",
	"caldera_relay", "gannet_reach", "white_signal", "glass_ravine", "greenfall_terraces", "beacon_wreck",
]

## The map to load next, set by a tool or test before the main scene loads.
## Empty means the --map argument or DEFAULT.
static var chosen := ""

var _ramp_slopes: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
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
		"saltwake_flats":
			return SaltwakeFlats.new()
		"nightline_foundry":
			return NightlineFoundry.new()
		"copper_steps":
			return CopperSteps.new()
		"caldera_relay":
			return CalderaRelay.new()
		"gannet_reach":
			return GannetReach.new()
		"white_signal":
			return WhiteSignal.new()
		"glass_ravine":
			return GlassRavine.new()
		"greenfall_terraces":
			return GreenfallTerraces.new()
		"beacon_wreck":
			return BeaconWreck.new()
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


func midfield_supply() -> Vector2:
	return Vector2.INF


func control_sites() -> Array[Vector2]:
	return []


func tactical_bounds() -> Rect2:
	var half := Vector2(OchreFold.PLAY_X, OchreFold.PLAY_Z)
	if self is ArenaMap:
		half = (self as ArenaMap).play_half
	elif self is TestMap:
		half = Vector2(TestMap.LENGTH, TestMap.WIDTH) * 0.5
	return Rect2(-half, half * 2.0)


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


## Where a team's soldiers start, in two rows beside the flag stand facing the other base.
func spawn_point(team: int, slot := 0) -> Transform3D:
	var side := 1.0 if slot % 2 == 0 else -1.0
	var row := slot / 2
	var x := base_x(team) + (row - 1.5) * 4.0 - front(team) * spawn_back
	var z := side * (spawn_side + (row % 2) * 3.0)
	var facing := -PI * 0.5 if team == 0 else PI * 0.5
	return Transform3D(Basis(Vector3.UP, facing), Vector3(x, surface_at(x, z) + 0.3, z))


## Every place a team's soldiers respawn.
func spawn_points(team: int, count := 8) -> Array[Transform3D]:
	var points: Array[Transform3D] = []
	for slot in count:
		points.append(spawn_point(team, slot))
	return points


## The top of a team's flag stand, in the middle of its base deck.
func stand_top(team: int) -> Vector3:
	return Vector3(base_x(team), deck_height() + STAND_HEIGHT, 0.0)


## The inventory stations under the two service bay roofs.
func station_points(team: int) -> Array[Vector3]:
	return [base_place(team, 1.0, -10.5, deck_height()), base_place(team, 1.0, 10.5, deck_height())]


## The top of the generator room's floor.
func room_floor() -> float:
	return deck_height() - ROOM_DEPTH


## A place in a team's base, given as (along, side) from its middle, at a
## height.
func base_place(team: int, along: float, side: float, y: float) -> Vector3:
	return Vector3(base_x(team) + front(team) * along, y, side)


## Where a team's generator stands: on the floor of its room, in the middle
## of its back half.
func generator_point(team: int) -> Vector3:
	return base_place(team, -4.5, 0.0, room_floor())


## The middles of a team's generator room openings, on the deck.
func opening_points(team: int) -> Array[Vector3]:
	var y := deck_height()
	return [base_place(team, OPENING_AT.x, -OPENING_AT.y, y), base_place(team, OPENING_AT.x, OPENING_AT.y, y)]


## The middle of each of a team's two force fields, filling the openings
## into its generator room.
func field_points(team: int) -> Array[Vector3]:
	var y := deck_height() - FIELD_SIZE.y * 0.5
	return [base_place(team, OPENING_AT.x, -OPENING_AT.y, y), base_place(team, OPENING_AT.x, OPENING_AT.y, y)]


## True over either base's generator room, its footprint grown by margin
## metres each way.
func under_room(x: float, z: float, margin := 0.0) -> bool:
	if absf(z) > ROOM_HALF + margin:
		return false
	for team in 2:
		var along := (x - base_x(team)) * front(team)
		if along >= ROOM_BACK - margin and along <= ROOM_FRONT + margin:
			return true
	return false


## True over one of the openings into a generator room.
func in_opening(x: float, z: float) -> bool:
	var half := OPENING * 0.5
	if absf(absf(z) - OPENING_AT.y) > half:
		return false
	for team in 2:
		var along := (x - base_x(team)) * front(team)
		if absf(along - OPENING_AT.x) <= half:
			return true
	return false


## Where a team's two turrets stand on the deck: one by the flag stand, one
## at a back corner near the ways into the generator room, both clear of the
## route points and the stations. The corner one only guards the openings
## (ROOM_GUARD).
func turret_points(team: int) -> Array[Vector3]:
	var x := base_x(team)
	var ahead := front(team)
	return [Vector3(x, deck_height(), -4.5), Vector3(x - ahead * 9.5, deck_height(), -9.5)]


## Where a team's sensor stands: on the deck on top of its tower, on the side
## away from the route point there.
func sensor_point(team: int) -> Vector3:
	var back := base_x(team) - front(team) * (BASE_SIZE * 0.5 - 4.0)
	return Vector3(back, base_ground + 17.0, -3.0)


## The yaw a team's base assets face: towards the other base.
func asset_facing(team: int) -> float:
	return -PI * 0.5 if team == 0 else PI * 0.5


## Puts a team's generator, turrets, sensor and force fields in a match.
func add_base_power(game: Match, team: int) -> void:
	var facing := asset_facing(team)
	game.add_asset(team, BaseAsset.Kind.GENERATOR, generator_point(team), facing)
	var turrets := turret_points(team)
	for k in turrets.size():
		var turret := game.add_asset(team, BaseAsset.Kind.TURRET, turrets[k], facing)
		if k == 1:
			turret.guard_points = opening_points(team)
			turret.guard_radius = ROOM_GUARD
	game.add_asset(team, BaseAsset.Kind.SENSOR, sensor_point(team), facing)
	for at in field_points(team):
		game.add_field(team, at, FIELD_SIZE)


## The base's vehicle pads, clear of the flag deck.
func add_vehicle_pads(game: Match, team: int) -> void:
	var anchors := route_graph.interest_points(RouteGraph.VEHICLE_PAD, team)
	var lineup := [Vehicle.Kind.BIKE, Vehicle.Kind.TANK, Vehicle.Kind.GUNSHIP, Vehicle.Kind.BOMBER, Vehicle.Kind.TRANSPORT]
	var sides: Array[Vector2] = [Vector2(-13, -24), Vector2(-13, 24), Vector2(6, -27), Vector2(6, 27), Vector2(-13, 57)]
	for i in lineup.size():
		var x := base_x(team) + front(team) * sides[i].x
		var z: float = sides[i].y
		if not anchors.is_empty():
			x = route_graph.points[anchors[0]].x
			z = (i - 2) * 13.0
		var pad := _vehicle_pad_at(team, lineup[i], Vector2(x, z))
		var at := Vector3(pad.x, surface_at(pad.x, pad.y), pad.y)
		var facing := asset_facing(team)
		var basis := Basis(Vector3.UP, facing)
		var extent := VehiclePad.rail_extent(lineup[i]) + Vector2(0.4, 0.35)
		# Sample across the frame, including the end blocks and the ground under the hull.
		for side: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			for end: float in [-1.0, -0.75, -0.5, -0.25, 0.0, 0.25, 0.5, 0.75, 1.0]:
				var sample := at + basis * Vector3(side * extent.x, 0, end * extent.y)
				at.y = maxf(at.y, surface_at(sample.x, sample.z))
		at.y += VehiclePad.FRAME_CLEARANCE
		game.fleet.add_pad(team, lineup[i], at, facing)


func _vehicle_pad_at(_team: int, _kind: Vehicle.Kind, at: Vector2) -> Vector2:
	return at


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
			return room_floor() if in_opening(x, z) else deck
		var along := dx * front(team) - BASE_SIZE * 0.5
		if along > 0.0 and along < RAMP_RUN:
			for index in BASE_RAMPS.size():
				var ramp := BASE_RAMPS[index]
				if absf(z - ramp.x) <= ramp.y * 0.5:
					return maxf(h, deck - along * _ramp_slopes[team][index])
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
## corners to defend, the ramp and the sides as ways in, a point on the deck
## beside each opening into the generator room, and the tower top, jetted up
## to from beside it. Call it before auto_link(), and link_tower_tops() and
## link_generator_rooms() after.
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
		# The back corners sit behind the openings into the generator room.
		for corner in [Vector2(7.0, 7.0), Vector2(7.0, -7.0), Vector2(-10.0, 6.5), Vector2(-10.0, -6.5)]:
			graph.add_interest(RouteGraph.DEFENCE, team, graph.add_point(base_place(team, corner.x, corner.y, deck)))
		for side in [-1.0, 1.0]:
			graph.add_point(_beside_opening(team, side))
		for ramp in BASE_RAMPS:
			var top := base_place(team, BASE_SIZE * 0.5 - 2.0, ramp.x, deck)
			var foot := base_place(team, BASE_SIZE * 0.5 + RAMP_RUN + 1.5, ramp.x, 0.0)
			foot.y = surface_at(foot.x, foot.z)
			graph.add_interest(RouteGraph.WAY_IN, team, graph.add_point(top))
			graph.add_interest(RouteGraph.WAY_IN, team, graph.add_point(foot))
		for side in [-1.0, 1.0]:
			var side_z: float = side * (BASE_SIZE * 0.5 + 6.0)
			graph.add_interest(RouteGraph.WAY_IN, team, graph.add_point(Vector3(x, surface_at(x, side_z), side_z)))


## The deck on top of each tower, jetted up to from beside it and dropped off
## back to the same spot, which is joined to the back corner on that side.
func link_tower_tops(graph: RouteGraph) -> void:
	var deck := deck_height()
	for team in 2:
		var back := base_x(team) - front(team) * (BASE_SIZE * 0.5 - 4.0)
		var top := graph.add_point(Vector3(back, base_ground + 17.0, 3.75))
		var foot := graph.add_point(Vector3(back, deck, 9.5))
		graph.add_interest(RouteGraph.HIGH_GROUND, team, top)
		graph.add_interest(RouteGraph.DEFENCE, team, top)
		graph.add_link(foot, top, RouteGraph.Kind.JET, true)
		graph.add_link(top, foot, RouteGraph.Kind.RUN)
		var near := graph.nearest(base_place(team, -10.0, 6.5, deck))
		if near != foot:
			graph.add_link(foot, near, RouteGraph.Kind.RUN)
			graph.add_link(near, foot, RouteGraph.Kind.RUN)


## The point on the deck beside an opening into a team's generator room, on
## its outer side, side -1 or 1.
func _beside_opening(team: int, side: float) -> Vector3:
	return base_place(team, OPENING_AT.x, side * (OPENING_AT.y + OPENING * 0.5 + 1.25), deck_height())


## Points in each generator room: one under each opening and one in front of
## the generator, the room's GENERATOR point. You drop in from the point beside
## each opening and jet back out to it; those links are the room team's field
## links, which enemy bots don't take while its field is on. Call it after
## auto_link(), since the deck above the room would fool it.
func link_generator_rooms(graph: RouteGraph) -> void:
	var floor_y := room_floor()
	for team in 2:
		var middle := graph.add_point(base_place(team, -1.5, 0.0, floor_y))
		graph.add_interest(RouteGraph.GENERATOR, team, middle)
		graph.add_interest(RouteGraph.DEFENCE, team, middle)
		graph.set_room(middle, team)
		for side in [-1.0, 1.0]:
			var below := graph.add_point(base_place(team, OPENING_AT.x, side * OPENING_AT.y, floor_y))
			graph.set_room(below, team)
			var above := graph.nearest(_beside_opening(team, side))
			graph.add_link(above, below, RouteGraph.Kind.RUN).field = team
			graph.add_link(below, above, RouteGraph.Kind.JET, true).field = team
			graph.add_link(below, middle, RouteGraph.Kind.RUN)
			graph.add_link(middle, below, RouteGraph.Kind.RUN)


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
	_build_deck(base, team)
	var ahead := front(team)
	var structure := Cel.material(palette.structure)
	var team_colour := Palette.team(team).lerp(palette.structure, 0.42).darkened(0.12)
	var team_wall := Cel.team_material(team_colour)
	for ramp in BASE_RAMPS:
		# The top meets the deck and the bottom reaches the terrain across the lane.
		var toe := base_place(team, BASE_SIZE * 0.5 + RAMP_RUN, ramp.x, 0.0)
		var floor_y := ground_height(toe.x, toe.z)
		for side: float in [-1.0, 1.0]:
			floor_y = minf(floor_y, ground_height(toe.x, toe.z + side * ramp.y * 0.5))
		var slope := maxf(RAMP_SLOPE, (deck_height() - floor_y + 0.05) / RAMP_RUN)
		_ramp_slopes[team].append(slope)
		var tilt := atan(slope)
		var length := RAMP_RUN / cos(tilt)
		var ramp_basis := Basis(Vector3.FORWARD, ahead * tilt)
		var centre := base_place(team, BASE_SIZE * 0.5 + RAMP_RUN * 0.5 - 0.5 * sin(tilt),
			ramp.x, deck_height() - RAMP_RUN * slope * 0.5 - 0.5 * cos(tilt))
		var ramp_body := _box(base, Vector3(length, 1.0, ramp.y), Transform3D(ramp_basis, centre), structure)
		var strip := MeshInstance3D.new()
		strip.mesh = Cel.box(Vector3(12.0, 0.025, 0.28))
		strip.position = Vector3(0.0, 0.51, ramp.y * 0.5 - 0.45)
		strip.material_override = team_wall
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ramp_body.add_child(strip)
	# A tower at the back with a deck on top, in a dark team colour so the
	# flag in front stands out from it.
	_build_stand(base, team)
	var back := x - ahead * (BASE_SIZE * 0.5 - 4.0)
	_box(base, Vector3(4.0, 14.0, 4.0), Transform3D(Basis.IDENTITY, Vector3(back, ground + 9.0, 0.0)), team_wall)
	obstacles.append(Vector3(back, 0.0, 2.9))
	_box(base, Vector3(10.0, 1.0, 10.0), Transform3D(Basis.IDENTITY, Vector3(back, ground + 16.5, 0.0)), structure)
	_build_service_bays(base, team, structure, team_wall)


func _build_service_bays(base: Node3D, team: int, structure: Material, trim: Material) -> void:
	var deck := deck_height()
	for side: float in [-1.0, 1.0]:
		var roof := _box(base, Vector3(9.5, 0.65, 5.5),
			Transform3D(Basis.IDENTITY, base_place(team, 1.0, side * 11.75, deck + 4.65)), structure)
		var fascia := MeshInstance3D.new()
		fascia.mesh = Cel.box(Vector3(9.55, 0.18, 5.55))
		fascia.position.y = -0.12
		fascia.material_override = trim
		roof.add_child(fascia)
		for along: float in [-2.75, 4.75]:
			var pillar := base_place(team, along, side * 13.45, deck + 2.2)
			_box(base, Vector3(1.3, 4.4, 1.3), Transform3D(Basis.IDENTITY, pillar), trim)
			obstacles.append(Vector3(pillar.x, pillar.z, 0.92))


## The platform, a raised deck reaching deck_depth below the ground, or below
## the room's floor if that's deeper, so a slope under it never shows a gap.
## Under its back half is the generator room, closed by the deck all round,
## with a floor of its own and two openings in its ceiling. Each piece is a
## box given as along and side ranges from the base's middle.
func _build_deck(base: Node3D, team: int) -> void:
	var deck := deck_height()
	var floor_y := room_floor()
	var ceiling := deck - 1.0
	var bottom := minf(base_ground - deck_depth, floor_y - 1.0)
	var half := BASE_SIZE * 0.5
	var hole_back := OPENING_AT.x - OPENING * 0.5
	var hole_front := OPENING_AT.x + OPENING * 0.5
	var hole_in := OPENING_AT.y - OPENING * 0.5
	var structure := Cel.material(palette.structure)
	# The top slab: in front of the openings, behind them, and between and
	# beside them.
	var top_pieces := [
		Rect2(hole_front, -half, half - hole_front, BASE_SIZE),
		Rect2(-half, -half, hole_back + half, BASE_SIZE),
		Rect2(hole_back, -hole_in, OPENING, hole_in * 2.0),
		Rect2(hole_back, -half, OPENING, half - ROOM_HALF),
		Rect2(hole_back, ROOM_HALF, OPENING, half - ROOM_HALF),
	]
	_deck_top(base, team, top_pieces, ceiling, deck, structure)
	# The walls round the room, down from the top slab.
	var wall_pieces := [
		Rect2(ROOM_FRONT, -half, half - ROOM_FRONT, BASE_SIZE),
		Rect2(-half, -half, ROOM_BACK + half, BASE_SIZE),
		Rect2(ROOM_BACK, -half, ROOM_FRONT - ROOM_BACK, half - ROOM_HALF),
		Rect2(ROOM_BACK, ROOM_HALF, ROOM_FRONT - ROOM_BACK, half - ROOM_HALF),
	]
	for piece: Rect2 in wall_pieces:
		_deck_box(base, team, piece, bottom, ceiling, structure)
	var room := Rect2(ROOM_BACK, -ROOM_HALF, ROOM_FRONT - ROOM_BACK, ROOM_HALF * 2.0)
	_deck_box(base, team, room, floor_y - 1.0, floor_y, Cel.material(palette.structure.darkened(0.4)))
	_dress_room(base, team)


## Trim in the generator room as one ink mesh with no collision: a dark
## skirting and a team coloured stripe round the walls, ribs up them, pipes
## under the ceiling, beams across it clear of the openings, lamps and a
## team coloured plate under the generator. Built with along as x and side
## as z, then turned to face the base's way.
func _dress_room(base: Node3D, team: int) -> void:
	var dark := Color(0.17, 0.16, 0.2, 0.0)
	var rib := palette.structure.darkened(0.15)
	rib.a = 0.0
	var lamp := Color(1.0, 0.95, 0.7, 0.0)
	var stripe := Color(1.0, 1.0, 1.0, 1.0)
	var floor_y := room_floor()
	var high := ROOM_DEPTH - 1.0
	var length := ROOM_FRONT - ROOM_BACK
	var middle := (ROOM_FRONT + ROOM_BACK) * 0.5
	var parts := []
	# Skirting and stripe on the front and back walls, then the side walls.
	for end: float in [ROOM_BACK, ROOM_FRONT]:
		var inward := 1.0 if end == ROOM_BACK else -1.0
		parts.append([Cel.box(Vector3(0.1, 0.3, ROOM_HALF * 2.0)), Transform3D(Basis.IDENTITY, Vector3(end + inward * 0.05, floor_y + 0.15, 0.0)), dark])
		parts.append([Cel.box(Vector3(0.06, 0.14, ROOM_HALF * 2.0)), Transform3D(Basis.IDENTITY, Vector3(end + inward * 0.03, floor_y + 1.5, 0.0)), stripe])
		for k in 5:
			var side := -6.0 + k * 3.0
			parts.append([Cel.box(Vector3(0.18, high, 0.35)), Transform3D(Basis.IDENTITY, Vector3(end + inward * 0.09, floor_y + high * 0.5, side)), rib])
	for edge: float in [-ROOM_HALF, ROOM_HALF]:
		var inward := 1.0 if edge < 0.0 else -1.0
		parts.append([Cel.box(Vector3(length, 0.3, 0.1)), Transform3D(Basis.IDENTITY, Vector3(middle, floor_y + 0.15, edge + inward * 0.05)), dark])
		parts.append([Cel.box(Vector3(length, 0.14, 0.06)), Transform3D(Basis.IDENTITY, Vector3(middle, floor_y + 1.5, edge + inward * 0.03)), stripe])
		for along: float in [-1.5, -3.5]:
			parts.append([Cel.box(Vector3(0.35, high, 0.18)), Transform3D(Basis.IDENTITY, Vector3(along, floor_y + high * 0.5, edge + inward * 0.09)), rib])
			parts.append([Cel.box(Vector3(0.22, 0.12, 0.06)), Transform3D(Basis.IDENTITY, Vector3(along + 1.0, floor_y + 2.2, edge + inward * 0.03)), lamp])
		# Two pipes along the side wall under the ceiling.
		for k in 2:
			var pipe := Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(middle, floor_y + high - 0.25 - k * 0.28, edge + inward * (0.3 + k * 0.05)))
			parts.append([Cel.cylinder(0.09, 0.09, length, 6), pipe, dark])
	# Beams across the ceiling in front of the openings.
	for along: float in [-1.5, -3.75]:
		parts.append([Cel.box(Vector3(0.4, 0.3, ROOM_HALF * 2.0)), Transform3D(Basis.IDENTITY, Vector3(along, floor_y + high - 0.15, 0.0)), rib])
	# Lamps on the back wall either side of the generator.
	for side: float in [-3.0, 3.0]:
		parts.append([Cel.box(Vector3(0.06, 0.12, 0.3)), Transform3D(Basis.IDENTITY, Vector3(ROOM_BACK + 0.03, floor_y + 2.2, side)), lamp])
	# The plate the generator stands on, with a dark rim.
	var under := Vector2(-4.5, 0.0)
	parts.append([Cel.box(Vector3(3.6, 0.04, 3.6)), Transform3D(Basis.IDENTITY, Vector3(under.x, floor_y + 0.02, under.y)), dark])
	parts.append([Cel.box(Vector3(3.2, 0.06, 3.2)), Transform3D(Basis.IDENTITY, Vector3(under.x, floor_y + 0.03, under.y)), stripe])
	var view := MeshInstance3D.new()
	view.name = "RoomTrim"
	view.mesh = Cel.merged(parts)
	view.material_override = Cel.material(Color.WHITE, 1.0, true, true)
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.position = Vector3(base_x(team), 0.0, 0.0)
	view.rotation.y = 0.0 if front(team) > 0.0 else PI
	base.add_child(view)
	Cel.set_team(view, Palette.team(team).darkened(0.2))


## A box in a team's base from along and side ranges (a Rect2 of along by
## side, from the base's middle) and a bottom and top height.
func _deck_box(base: Node3D, team: int, piece: Rect2, y0: float, y1: float, material: Material) -> void:
	var middle := piece.get_center()
	var at := base_place(team, middle.x, middle.y, (y0 + y1) * 0.5)
	_box(base, Vector3(piece.size.x, y1 - y0, piece.size.y), Transform3D(Basis.IDENTITY, at), material)


## The deck's top slab from along and side pieces that tile it round the
## openings, as one body with a box shape per piece and one mesh with no
## faces between the pieces, so their joins draw no ink lines.
func _deck_top(base: Node3D, team: int, pieces: Array, y0: float, y1: float, material: Material) -> void:
	var body := StaticBody3D.new()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edges: Array[Rect2] = []
	for piece: Rect2 in pieces:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var middle := piece.get_center()
		box.size = Vector3(piece.size.x, y1 - y0, piece.size.y)
		shape.shape = box
		shape.position = base_place(team, middle.x, middle.y, (y0 + y1) * 0.5)
		body.add_child(shape)
		for y: float in [y0, y1]:
			var corners: Array[Vector3] = [
				base_place(team, piece.position.x, piece.position.y, y),
				base_place(team, piece.end.x, piece.position.y, y),
				base_place(team, piece.end.x, piece.end.y, y),
				base_place(team, piece.position.x, piece.end.y, y),
			]
			Cel._quad(tool, corners, Vector3.UP if y == y1 else Vector3.DOWN)
		edges.append(piece)
	# Side faces only where a piece's edge has no piece beyond it: each edge
	# is cut where other pieces' corners fall on it, and each bit is kept if
	# its middle, nudged outwards, is in no piece.
	for piece: Rect2 in edges:
		var sides := [
			[Vector2(piece.position.x, piece.position.y), Vector2(piece.end.x, piece.position.y), Vector2(0.0, -1.0)],
			[Vector2(piece.end.x, piece.position.y), Vector2(piece.end.x, piece.end.y), Vector2(1.0, 0.0)],
			[Vector2(piece.end.x, piece.end.y), Vector2(piece.position.x, piece.end.y), Vector2(0.0, 1.0)],
			[Vector2(piece.position.x, piece.end.y), Vector2(piece.position.x, piece.position.y), Vector2(-1.0, 0.0)],
		]
		for side: Array in sides:
			var a: Vector2 = side[0]
			var b: Vector2 = side[1]
			var out: Vector2 = side[2]
			var cuts: Array[float] = [0.0, 1.0]
			for other: Rect2 in edges:
				for corner: Vector2 in [other.position, other.end, Vector2(other.position.x, other.end.y), Vector2(other.end.x, other.position.y)]:
					var t := (corner - a).dot(b - a) / (b - a).length_squared()
					if t > 0.001 and t < 0.999 and (a.lerp(b, t) - corner).length() < 0.001:
						cuts.append(t)
			cuts.sort()
			for k in cuts.size() - 1:
				var p := a.lerp(b, cuts[k])
				var q := a.lerp(b, cuts[k + 1])
				if p.distance_to(q) < 0.001:
					continue
				var probe := (p + q) * 0.5 + out * 0.01
				var covered := false
				for other: Rect2 in edges:
					covered = covered or other.has_point(probe)
				if covered:
					continue
				var normal := base_place(team, out.x, out.y, 0.0) - base_place(team, 0.0, 0.0, 0.0)
				var corners: Array[Vector3] = [
					base_place(team, p.x, p.y, y0),
					base_place(team, q.x, q.y, y0),
					base_place(team, q.x, q.y, y1),
					base_place(team, p.x, p.y, y1),
				]
				Cel._quad(tool, corners, normal.normalized())
	var view := MeshInstance3D.new()
	view.mesh = Cel.hull_mesh(tool.commit())
	view.material_override = material
	body.add_child(view)
	base.add_child(body)


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
