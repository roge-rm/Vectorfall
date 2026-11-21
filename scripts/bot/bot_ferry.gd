class_name BotFerry
extends RefCounted

## Flight and landing plans are made on the main thread in tick order.
enum Phase { CRUISE, DESCEND, UNLOAD, RETURN, RECOVER }

const PROBE_TICKS := 10
const LAND_RECHECK_TICKS := 30
const LAND_RADIUS := 2.5
const UNLOAD_SPEED := 4.5
const CLEARANCE := 20.0
const MAX_SITES := 10
const MAX_FOOT_POINTS := 96
const MAX_RETRIES := 3
const RETURN_RETRIES := 2
const RECOVERY_RETRIES := 2
const LAND_TICKS := 6 * 60
const STALL_TICKS := 8 * 60

var trips: Dictionary = {}


func prune(game: Match) -> void:
	for id: int in trips.keys():
		var hull: Vehicle = game.fleet.hulls.get(id)
		if hull == null or hull.crew[0] == 0 or game.bots.brain_of(hull.crew[0]) == null:
			trips.erase(id)


func pilot(hull: Vehicle, command: PlayerCommand, boss: TeamCommander, objective: Vector3, returning: bool) -> void:
	var game := boss.game
	var pad: VehiclePad = game.fleet.pads[hull.pad_id]
	var id := hull.entity_id
	var trip: Dictionary = trips.get(id, {})
	if trip.is_empty() or trip.pilot != hull.crew[0]:
		trip = _new_trip(hull, returning, game.tick)
		trips[id] = trip
	elif returning and not trip.returning:
		trip = _new_trip(hull, true, game.tick)
		trips[id] = trip
	if trip.drop == Vector3.INF:
		_find_drop(game, boss.director.graph, hull, trip, pad.position if trip.returning else objective)
		if trip.drop == Vector3.INF:
			command.yaw = hull.yaw
			if trip.settle:
				command.buttons |= PlayerCommand.JUMP
				if not _has_bot_passengers(hull, boss) and ready_to_exit(game, hull):
					_exit(command, game.tick)
			return

	var drop: Vector3 = trip.drop
	var distance := _flat_distance(hull.position, drop)
	if distance < trip.progress - 2.0:
		trip.progress = distance
		trip.last_progress = game.tick
	if trip.phase == Phase.UNLOAD:
		if not _has_bot_passengers(hull, boss) and distance < LAND_RADIUS and _low_and_slow(hull, drop.y):
			_exit(command, game.tick)
			return
		if game.tick - int(trip.phase_tick) >= LAND_TICKS:
			_retry(trip, game.tick)
			return
	elif trip.phase == Phase.DESCEND and game.tick - int(trip.phase_tick) >= LAND_TICKS:
		_retry(trip, game.tick)
		return

	if not trip.check.is_empty() and _work_site(game, hull, trip.check):
		var read: Vector3 = trip.check.result
		var clear := read != Vector3.INF and absf(read.y - drop.y) <= 1.0
		trip.check.clear()
		if not clear:
			_retry(trip, game.tick)
			return
	if distance <= LAND_RADIUS + 8.0 and trip.check.is_empty() and game.tick >= trip.next_check:
		trip.next_check = game.tick + LAND_RECHECK_TICKS
		trip.check = _site_probe(drop)
	if game.tick >= trip.next_probe:
		trip.next_probe = game.tick + PROBE_TICKS
		if distance > LAND_RADIUS:
			_probe(game, hull, trip, drop)
		if game.tick - int(trip.last_progress) >= STALL_TICKS and distance > LAND_RADIUS:
			_retry(trip, game.tick)
			return

	var speed := Vector2(hull.velocity.x, hull.velocity.z).length()
	if distance < LAND_RADIUS and speed < 3.0:
		if trip.phase in [Phase.CRUISE, Phase.RETURN, Phase.RECOVER]:
			trip.phase = Phase.DESCEND
			trip.phase_tick = game.tick
		command.yaw = hull.yaw
		command.buttons |= PlayerCommand.JUMP
		if trip.check.is_empty() and _low_and_slow(hull, drop.y):
			if trip.phase != Phase.UNLOAD:
				trip.phase = Phase.UNLOAD
				trip.phase_tick = game.tick
			if not _has_bot_passengers(hull, boss):
				_exit(command, game.tick)
		return

	var aim: Vector3 = trip.waypoint if trip.waypoint != Vector3.INF else drop
	var to := Vector3(aim.x - hull.position.x, 0.0, aim.z - hull.position.z)
	command.yaw = atan2(-to.x, -to.z)
	var alignment := maxf(0.0, cos(angle_difference(hull.yaw, command.yaw)))
	var goal_speed := minf(Vehicle.SPEED[hull.kind], sqrt(2.0 * Vehicle.ACCEL[hull.kind] * maxf(to.length() - 1.0, 0.0)) * 0.68)
	goal_speed = minf(goal_speed, to.length() * 1.5)
	var cruise: float = maxf(drop.y + CLEARANCE if distance < 65.0 else -INF, trip.cruise)
	if hull.position.y < cruise:
		command.buttons |= PlayerCommand.JET
	elif hull.position.y > cruise + 8.0:
		command.buttons |= PlayerCommand.JUMP
	var scale := 0.0 if trip.blocked else clampf((hull.position.y - cruise + 15.0) / 15.0, 0.0, 1.0)
	command.move.y = goal_speed / Vehicle.SPEED[hull.kind] * alignment * alignment * scale


func _has_bot_passengers(hull: Vehicle, boss: TeamCommander) -> bool:
	for seat in range(1, hull.crew.size()):
		if boss.director.brain_of(hull.crew[seat]) != null:
			return true
	return false


func passenger_exit(game: Match, hull: Vehicle) -> bool:
	var trip: Dictionary = trips.get(hull.entity_id, {})
	if trip.get("settle", false):
		return ready_to_exit(game, hull)
	return not trip.is_empty() and trip.phase == Phase.UNLOAD and trip.check.is_empty() and _flat_distance(hull.position, trip.drop) < LAND_RADIUS and _low_and_slow(hull, trip.drop.y)


func ready_to_exit(game: Match, hull: Vehicle) -> bool:
	return hull.velocity.length_squared() <= UNLOAD_SPEED * UNLOAD_SPEED and game.bots.take_ray() and _low_and_slow(hull, game.fleet.ground_at(hull.position))


func _low_and_slow(hull: Vehicle, floor_y: float) -> bool:
	return hull.velocity.length_squared() <= UNLOAD_SPEED * UNLOAD_SPEED and hull.position.y - floor_y <= 3.2


func _find_drop(game: Match, graph: RouteGraph, hull: Vehicle, trip: Dictionary, objective: Vector3) -> void:
	if trip.settle or game.tick < int(trip.next_probe):
		return
	if not trip.sites_ready:
		trip.sites = _recovery_sites(game, hull, trip.rejected) if trip.recovering else _drop_sites(graph, objective, trip.rejected, trip.returning)
		trip.sites_ready = true
	if trip.site.is_empty():
		if trip.sites.is_empty():
			_fallback(trip)
			return
		trip.site = _site_probe(trip.sites.pop_front(), trip.recovering)
	if not _work_site(game, hull, trip.site):
		return
	trip.drop = trip.site.result
	trip.site.clear()
	if trip.drop != Vector3.INF:
		trip.progress = INF
		trip.last_progress = game.tick


func _drop_sites(graph: RouteGraph, objective: Vector3, rejected: Array, returning: bool) -> Array[Vector3]:
	var sites: Array[Vector3] = []
	if returning and not _rejected(objective, rejected):
		sites.append(objective)
	var target := graph.nearest(objective)
	if target < 0:
		return sites
	var near: Array[Vector2] = []
	for i: int in _walking_zone(graph, target):
		var point := graph.points[i]
		var distance := _flat_distance(point, objective)
		if distance <= 100.0 and graph.room_of(i) == -1 and not _rejected(point, rejected):
			near.append(Vector2(distance + 0.4 * absf(point.y - objective.y), i))
	near.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	for candidate in near:
		sites.append(graph.points[int(candidate.y)])
		if sites.size() >= MAX_SITES:
			break
	return sites


func _recovery_sites(game: Match, hull: Vehicle, rejected: Array) -> Array[Vector3]:
	var sites: Array[Vector3] = []
	for offset: Vector3 in [Vector3.ZERO, Vector3(12, 0, 0), Vector3(-12, 0, 0), Vector3(0, 0, 12), Vector3(0, 0, -12)]:
		var at := hull.position + offset
		if game.terrain != null:
			at.y = game.terrain.height_at(at.x, at.z)
		if not _rejected(at, rejected):
			sites.append(at)
	return sites


static func _rejected(point: Vector3, rejected: Array) -> bool:
	return rejected.any(func(at: Vector3) -> bool: return _flat_distance(point, at) < 8.0)


## Walk the local graph backwards from the objective. Drop sites must have
## a route towards it without jumping off a roof or opening a field.
func _walking_zone(graph: RouteGraph, target: int) -> Array[int]:
	var found: Array[int] = [target]
	var seen := {target: true}
	var index := 0
	while index < found.size() and found.size() < MAX_FOOT_POINTS:
		var point := found[index]
		index += 1
		for outward: RouteGraph.Link in graph.out_links[point]:
			var friend := outward.to
			if seen.has(friend) or graph.room_of(friend) != -1:
				continue
			if _flat_distance(graph.points[friend], graph.points[target]) > 120.0:
				continue
			var inward := graph.link_between(friend, point)
			if inward != null and inward.kind != RouteGraph.Kind.JET and inward.field == -1:
				seen[friend] = true
				found.append(friend)
				if found.size() >= MAX_FOOT_POINTS:
					break
	return found


static func _site_probe(at: Vector3, allow_level_change := false) -> Dictionary:
	return {"at": at, "step": 0, "result": Vector3.INF, "allow_level_change": allow_level_change}


## Spend at most one shared query on a site each tick.
func _work_site(game: Match, hull: Vehicle, site: Dictionary) -> bool:
	if not game.bots.take_ray():
		return false
	var at: Vector3 = site.at
	var step: int = site.step
	if step == 0:
		var floor_y := game.fleet.ground_at(at + Vector3.UP * 2.0)
		if floor_y <= at.y - 150.0 or (not site.allow_level_change and absf(floor_y - at.y) > 2.0):
			return true
		at.y = floor_y
		site.at = at
	elif step <= 4:
		var offset := Vector3(-5.0 if step <= 2 else 5.0, 0, -5.0 if step % 2 == 0 else 5.0)
		if absf(game.fleet.ground_at(at + offset) - at.y) > 1.0:
			return true
	else:
		var box := BoxShape3D.new()
		box.size = Vector3(11.0, 21.0, 11.0)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = box
		query.transform.origin = at + Vector3.UP * 11.7
		query.exclude = [hull.get_rid()]
		query.collision_mask = _obstacles(hull)
		if game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			site.result = at
		return true
	site.step += 1
	return false


func _probe(game: Match, hull: Vehicle, trip: Dictionary, drop: Vector3) -> void:
	var at := hull.position
	var ahead := Vector3(drop.x - at.x, 0.0, drop.z - at.z)
	if trip.waypoint != Vector3.INF:
		if _flat_distance(at, trip.waypoint) < 9.0:
			trip.waypoint = Vector3.INF
			trip.scan_blocks = 0
		else:
			ahead = trip.waypoint - at
			ahead.y = 0.0
	var reach := clampf(Vector2(hull.velocity.x, hull.velocity.z).length() * 1.5, 18.0, 72.0)
	var probe := ahead.limit_length(reach)
	var floor_y := maxf(drop.y, trip.cruise - CLEARANCE)
	if game.terrain != null:
		floor_y = game.terrain.height_at(at.x, at.z)
		for blend: float in [0.32, 0.65, 1.0]:
			var point := at + probe * blend
			floor_y = maxf(floor_y, game.terrain.height_at(point.x, point.z))
	trip.cruise = floor_y + CLEARANCE
	var across: float = [0.0, -1.0, 1.0][trip.scan]
	var clear := _air_clear(game, hull, at, probe, across)
	if clear < 0:
		return
	var bit := 1 << int(trip.scan)
	if clear == 0:
		trip.scan_blocks |= bit
	else:
		trip.scan_blocks &= ~bit
	trip.scan = (trip.scan + 1) % 3
	trip.blocked = trip.scan_blocks != 0
	if not trip.blocked:
		return
	trip.cruise = maxf(trip.cruise, at.y + 10.0)
	if trip.waypoint != Vector3.INF or ahead.length_squared() < 0.1:
		return
	for side: float in [-1.0, 1.0]:
		var detour := ahead.normalized().rotated(Vector3.UP, side * 0.8) * 26.0
		if _air_clear(game, hull, at, detour, 0.0) == 1:
			trip.waypoint = at + detour
			trip.blocked = false
			trip.scan_blocks = 0
			return


## Rotate through the hull centre and the sides instead of casting a burst.
func _air_clear(game: Match, hull: Vehicle, at: Vector3, to: Vector3, across: float) -> int:
	if not game.bots.take_ray():
		return -1
	var side := Vector3.UP.cross(to.normalized()) * (across * Vehicle.SIZE[hull.kind].x * 0.55)
	var start := at + side
	return int(game.world_ray(start, start + to, _obstacles(hull), [hull.get_rid()]).is_empty())


func _obstacles(hull: Vehicle) -> int:
	return Match.WORLD_LAYER | Match.ASSET_LAYER | Vehicle.HULL_LAYER | Match.enemy_fields(hull.team)


func _new_trip(hull: Vehicle, returning: bool, tick: int) -> Dictionary:
	return {
		"pilot": hull.crew[0], "drop": Vector3.INF, "returning": returning,
		"phase": Phase.RETURN if returning else Phase.CRUISE, "phase_tick": tick, "next_check": tick,
		"rejected": [], "retries": 0, "next_probe": tick, "last_progress": tick,
		"progress": INF, "cruise": hull.position.y + CLEARANCE,
		"waypoint": Vector3.INF, "blocked": false, "scan": 0, "scan_blocks": 0,
		"sites_ready": false, "sites": [], "site": {}, "check": {},
		"recovering": false, "settle": false, "phase_retries": 0,
	}


func _retry(trip: Dictionary, tick: int) -> void:
	trip.rejected.append(trip.drop)
	trip.retries += 1
	trip.phase_retries += 1
	var limit := RECOVERY_RETRIES if trip.recovering else (RETURN_RETRIES if trip.returning else MAX_RETRIES)
	if trip.phase_retries >= limit:
		_fallback(trip)
	trip.phase = Phase.RECOVER if trip.recovering else (Phase.RETURN if trip.returning else Phase.CRUISE)
	trip.phase_tick = tick
	trip.drop = Vector3.INF
	trip.waypoint = Vector3.INF
	trip.scan_blocks = 0
	trip.blocked = false
	trip.sites_ready = false
	trip.site.clear()
	trip.check.clear()
	trip.next_probe = tick + PROBE_TICKS


func _fallback(trip: Dictionary) -> void:
	if trip.recovering:
		trip.settle = true
	elif trip.returning:
		trip.recovering = true
		trip.phase = Phase.RECOVER
	else:
		trip.returning = true
		trip.phase = Phase.RETURN
	trip.sites_ready = false
	trip.phase_retries = 0
	trip.rejected.clear()


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _exit(command: PlayerCommand, tick: int) -> void:
	if tick % 8 == 0:
		command.buttons |= PlayerCommand.BOARD
