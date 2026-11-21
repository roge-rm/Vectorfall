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
	await _check_crew_reservations()
	_setup()
	var crew_ready := false
	var rider_id := 0
	var runner_reserved := false
	for i in 60 * 45:
		await physics_frame
		for brain: BotBrain in director.brains:
			if brain.is_flag_runner() and director.vehicle_orders.jobs.has(brain.soldier.entity_id):
				runner_reserved = true
		var ferry: Vehicle = game.fleet.hulls.get(ferry_pad.hull_id)
		var wing: Vehicle = game.fleet.hulls.get(wing_pad.hull_id)
		if ferry != null and wing != null and wing.crew[0] != 0 and ferry.crew[0] != 0 and ferry.crew[1] != 0:
			crew_ready = true
			rider_id = ferry.crew[1]
			break
	checks.check(crew_ready, "bots board a gunship and crew a transport with a passenger")
	checks.check(not runner_reserved, "the flag runner has no vehicle boarding job")
	if not crew_ready:
		checks.finish(self)
		return
	var wing: Vehicle = game.fleet.hulls[wing_pad.hull_id]
	var ferry: Vehicle = game.fleet.hulls[ferry_pad.hull_id]
	var original_range := wing.position.distance_to(game.stands[0])
	var escape := TestWorld.Scripted.new()
	escape.command.yaw = PI
	escape.command.move.y = 1.0
	escape.command.buttons = PlayerCommand.SKI
	var enemy := game.add_soldier(1, Transform3D(Basis.IDENTITY, Vector3(7.0, 0.05, -75.0)), escape)
	enemy.velocity = Vector3(0, 0, 25)
	game._take_flag(game.flags[0], enemy)
	var closest := INF
	var furthest := original_range
	var altitude := 0.0
	var delivered := false
	var fired := false
	var drop := director.vehicle_orders.mission_objective(ferry, director.commander(0))
	game.fired.connect(func(_id: int, weapon: int) -> void:
		if weapon == Weapon.TURRET:
			set_meta("wing_fired", true))
	game.hit.connect(func(_attacker: int, victim: int, weapon: int) -> void:
		if victim == enemy.entity_id and weapon == Weapon.TURRET and game.carried_flag(victim) != null and enemy.velocity.length() >= 18.0:
			set_meta("wing_hit_carrier", true))
	for i in 60 * 35:
		await physics_frame
		closest = minf(closest, wing.position.distance_to(enemy.position))
		furthest = maxf(furthest, wing.position.distance_to(game.stands[0]))
		altitude = maxf(altitude, ferry.position.y)
		var rider := game.soldier(rider_id)
		delivered = delivered or (rider.vehicle_id == 0 and rider.position.distance_to(drop) < 30.0)
		fired = has_meta("wing_fired")
		if delivered and has_meta("wing_hit_carrier"):
			break
	checks.check(closest < 90.0 and furthest > original_range + 10.0 and fired, "the gunship follows and fires on the enemy carrier (closest %.1f m, advanced %.1f m, fired %s)" % [closest, furthest - original_range, fired])
	checks.check(has_meta("wing_hit_carrier"), "the gunship lands a hit while the carrier is skiing at speed")
	checks.check(delivered and altitude > 12.0, "a bot flies the transport and unloads its passenger near the enemy base (height %.1f m)" % altitude)
	await physics_frame
	checks.check(not director.vehicle_orders.foot_support(rider_id).is_empty(), "an unloaded passenger has a time-limited task on foot")
	var wing_pilot := game.soldier(wing.crew[0])
	if wing_pilot != null:
		var boss := director.commander(0)
		boss._lock(director.brain_of(wing_pilot.entity_id), BotBrain.Role.DEFENCE, 0, -1, Orders.Kind.SET_ROLE, 0)
		for i in 60 * 12:
			await physics_frame
			if wing_pilot.vehicle_id == 0:
				break
	checks.check(wing_pilot != null and wing_pilot.vehicle_id == 0 and wing.crew[0] == 0, "a gunship pilot lands and exits for an order on foot")
	await _ochre_fold()
	checks.finish(self)


func _check_crew_reservations() -> void:
	_setup()
	var orders := director.vehicle_orders
	var runner: BotBrain
	for i in 20:
		await physics_frame
		for brain: BotBrain in director.brains:
			if brain.is_flag_runner():
				runner = brain
				break
		if runner != null and game.fleet.hulls.has(ferry_pad.hull_id):
			break
	var ferry: Vehicle = game.fleet.hulls.get(ferry_pad.hull_id)
	checks.check(ferry != null and orders.mission_kind(ferry).is_empty(), "an idle flag runner does not call a ferry")
	if runner != null:
		runner.attacking = true
		orders._assign(game)
	var has_delivery := ferry != null and orders.mission_kind(ferry) == "deliver"
	checks.check(has_delivery, "a ferry reserves a pilot and passenger for the flag runner")
	if has_delivery:
		var before := orders.get_state()
		orders.set_state(before)
		checks.check(orders.get_state() == before, "crew missions and reservations round-trip in bot state")
		checks.check(orders.ferry_departure(ferry) == BotVehicles.Departure.WAIT, "the ferry waits for its assigned crew at the pad")
		var human := game.add_soldier(0, Transform3D(Basis.IDENTITY, ferry.position))
		ferry.crew[0] = human.entity_id
		human.mount(ferry.entity_id, 0)
		await physics_frame
		await physics_frame
		var stranded := false
		for job: Dictionary in orders.jobs.values():
			stranded = stranded or job.hull == ferry.entity_id
		checks.check(not stranded and ferry.crew[0] == human.entity_id, "a human pilot cancels the bot reservations without losing the seat")
	var enemy := game.add_soldier(1, Transform3D(Basis.IDENTITY, Vector3(-40.0, 0.05, 0.0)))
	var boss := director.commander(0)
	boss.known[enemy.entity_id] = {"position": enemy.position, "velocity": Vector3.ZERO, "tick": game.tick}
	if runner != null:
		runner.attacking = false
	orders._assign(game)
	var wing: Vehicle = game.fleet.hulls.get(wing_pad.hull_id)
	checks.check(wing != null and orders.mission_kind(wing).is_empty(), "a nearby attacker does not pull a bot off the ground to patrol")
	if wing == null:
		game.free()
		floor.free()
		return
	for brain: BotBrain in director.brains:
		if not brain.is_flag_runner() and brain.soldier.vehicle_id == 0 and not orders.jobs.has(brain.soldier.entity_id):
			brain.role = BotBrain.Role.LIGHT_DEFENCE
			brain.soldier.position = wing.position + Vector3(0, 0, 6)
			break
	for brain: BotBrain in director.brains:
		if brain.soldier.position.distance_to(wing.position) > 10.0:
			brain.soldier.position.x -= 25.0
	game._take_flag(game.flags[0], enemy)
	orders._assign(game)
	orders.update()
	boss.known.erase(enemy.entity_id)
	var boards_to_intercept := false
	var pilot: BotBrain
	for brain: BotBrain in director.brains:
		if orders.is_intercept_job(brain.soldier.entity_id):
			boards_to_intercept = boards_to_intercept or brain._choose_goal()[0] == BotBrain.Goal.VEHICLE
			if orders.jobs[brain.soldier.entity_id].seat == 0:
				pilot = brain
	checks.check(boards_to_intercept, "a reserved gunship crew boards while its flag is out")
	if pilot != null:
		checks.check(orders.jobs[pilot.soldier.entity_id].until == game.tick + BotVehicles.INTERCEPT_BOARD_TICKS, "an interception reserves the close pilot for only a few seconds")
		for i in BotVehicles.INTERCEPT_BOARD_TICKS:
			await physics_frame
			if pilot.soldier.vehicle_id == wing.entity_id:
				break
		var boarded := pilot.soldier.vehicle_id == wing.entity_id
		checks.check(boarded, "the close interceptor boards before its reservation expires")
		if boarded:
			wing.position.y += 25.0
			orders._assign(game)
			game._return_flag(game.flags[0], 0)
			for brain: BotBrain in director.brains:
				if brain.is_flag_runner():
					brain.attacking = false
					brain.goal = BotBrain.Goal.DEFEND
			orders._assign(game)
			checks.check(orders.mission_kind(wing) == "hold", "an airborne interceptor waits briefly for the next assignment")
			game.tick += BotVehicles.COVER_WAIT_TICKS
			orders._assign(game)
			orders.rider_command(pilot)
			checks.check(orders.ferry.trips.get(wing.entity_id, {}).get("returning", false), "a gunship heads for a safe landing when its target is gone")
	for brain: BotBrain in director.brains:
		if brain.soldier.vehicle_id == 0:
			_check_support_expiry(brain)
			break
	game.free()
	floor.free()


func _check_support_expiry(brain: BotBrain) -> void:
	var orders := director.vehicle_orders
	var id := brain.soldier.entity_id
	var drop := Vector3(92.0, 0.05, 32.0)
	brain.role = BotBrain.Role.MIDFIELD
	brain.goal = BotBrain.Goal.NONE
	orders.delivered[id] = {"hull": 0, "target": 0, "objective": drop, "until": game.tick + 1}
	brain.think()
	checks.check(brain.goal_target == drop, "a delivered bot can cover the landing objective while its runner is away")
	game.tick += 1
	orders._update_delivered(game)
	brain.think()
	checks.check(brain.goal_target != drop, "a delivered bot resumes its role when landing support expires")


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
