extends SceneTree

var checks := TestWorld.Checks.new()
var game: Match
var director: BotDirector
var ferry_pad: VehiclePad
var wing_pad: VehiclePad
var floor: StaticBody3D


func _initialize() -> void:
	_run.call_deferred()


func _setup() -> void:
	floor = TestWorld.flat_ground(root)
	game = Match.new(27)
	root.add_child(game)
	game.add_flag(0, Vector3(-105, 0.5, 0), Vector3(-105, 0.5, 0))
	game.add_flag(1, Vector3(155, 0.5, 0), Vector3(155, 0.5, 0))
	wing_pad = game.fleet.add_pad(0, Vehicle.Kind.GUNSHIP, Vector3(-153, 0, -18), -PI * 0.5)
	ferry_pad = game.fleet.add_pad(0, Vehicle.Kind.TRANSPORT, Vector3(-153, 0, 21), -PI * 0.5)
	var graph := RouteGraph.new()
	for x in range(-160, 161, 20):
		for z in range(-40, 41, 20):
			graph.add_point(Vector3(x, 0.05, z))
	graph.auto_link(31.0, func(_x: float, _z: float) -> float: return 0.0, func(_x: float, _z: float) -> bool: return false)
	director = BotDirector.new(game, graph)
	for k in 8:
		var at := Vector3(-178.0 - (k % 3) * 3.0, 0.05, 14.0 + k * 3.0 if k < 4 else -12.0 - k * 3.0)
		director.add_bot(0, Transform3D(Basis.IDENTITY, at))


func _run() -> void:
	_setup()
	var crew_ready := false
	var rider_id := 0
	for i in 60 * 25:
		await physics_frame
		var ferry: Vehicle = game.fleet.hulls.get(ferry_pad.hull_id)
		var wing: Vehicle = game.fleet.hulls.get(wing_pad.hull_id)
		if ferry != null and wing != null and wing.crew[0] != 0 and ferry.crew[0] != 0 and ferry.crew[1] != 0:
			crew_ready = true
			rider_id = ferry.crew[1]
			break
	checks.check(crew_ready, "bots board a gunship and crew a transport with a passenger")
	if not crew_ready:
		checks.finish(self)
		return
	var wing: Vehicle = game.fleet.hulls[wing_pad.hull_id]
	var ferry: Vehicle = game.fleet.hulls[ferry_pad.hull_id]
	var original_range := wing.position.distance_to(game.stands[0])
	var enemy := game.add_soldier(1, Transform3D(Basis.IDENTITY, Vector3(7.0, 0.05, -75.0)))
	game._take_flag(game.flags[0], enemy)
	var closest := INF
	var altitude := 0.0
	var delivered := false
	var fired := false
	var drop := director.commander(0).vehicle_destination(Vehicle.Kind.TRANSPORT)
	game.fired.connect(func(_id: int, weapon: int) -> void:
		if weapon == Weapon.TURRET:
			set_meta("wing_fired", true))
	for i in 60 * 35:
		await physics_frame
		closest = minf(closest, wing.position.distance_to(enemy.position))
		altitude = maxf(altitude, ferry.position.y)
		var rider := game.soldier(rider_id)
		delivered = delivered or (rider.vehicle_id == 0 and rider.position.distance_to(drop) < 30.0)
		fired = has_meta("wing_fired")
		if delivered and fired:
			break
	checks.check(closest < 90.0 and wing.position.distance_to(game.stands[0]) > original_range + 10.0 and fired, "the gunship follows and fires on the enemy carrier (closest %.1f m)" % closest)
	checks.check(delivered and altitude > 12.0, "a bot flies the transport and unloads its passenger near the enemy base (height %.1f m)" % altitude)
	var wing_pilot := game.soldier(wing.crew[0])
	var boss := director.commander(0)
	boss._lock(director.brain_of(wing_pilot.entity_id), BotBrain.Role.DEFENCE, 0, -1, Orders.Kind.SET_ROLE, 0)
	for i in 60 * 12:
		await physics_frame
		if wing_pilot.vehicle_id == 0:
			break
	checks.check(wing_pilot.vehicle_id == 0 and wing.crew[0] == 0, "a gunship pilot lands and exits for an order on foot")
	await _ochre_fold()
	checks.finish(self)


func _ochre_fold() -> void:
	game.free()
	floor.free()
	var map := OchreFold.new()
	root.add_child(map)
	game = Match.new(27)
	game.terrain = map.terrain
	for team in 2:
		game.spawns[team] = map.spawn_points(team)
		game.add_flag(team, map.stand_point(team), map.flag_rest(team))
		map.add_vehicle_pads(game, team)
	root.add_child(game)
	director = BotDirector.new(game, map.route_graph)
	for team in 2:
		for k in 8:
			director.add_bot(team, map.spawn_point(team, k))
	game.prepare_terrain()
	var pilots := [false, false]
	for i in 60 * 45:
		await physics_frame
		for craft: Vehicle in game.fleet.hulls.values():
			if craft.crew[0] != 0 and craft.flies() and craft.position.y > game.fleet.pads[craft.pad_id].position.y + 8.0:
				pilots[craft.team] = true
		if pilots[0] and pilots[1]:
			break
	checks.check(pilots[0] and pilots[1], "bots on both teams reach and fly their vehicles from the usual Ochre Fold spawns (%s)" % str(pilots))
