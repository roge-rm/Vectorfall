extends SceneTree

var checks := TestWorld.Checks.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TestWorld.flat_ground(root)
	_box(Vector3(100, 4, 0), Vector3(8, 8, 8))
	_box(Vector3(0, 5, 0), Vector3(4, 10, 20))
	var game := Match.new()
	game.running = false
	root.add_child(game)
	var pad := game.fleet.add_pad(0, Vehicle.Kind.TRANSPORT, Vector3(-80, 0, 0), -PI * 0.5)
	var hull := game.fleet._make_hull(game.next_id, pad, pad.position + Vector3.UP * Vehicle.ride_height(Vehicle.Kind.TRANSPORT))
	game.next_id += 1
	var graph := RouteGraph.new()
	var blocked := graph.add_point(Vector3(100, 0, 0))
	var clear := graph.add_point(Vector3(75, 0, 0))
	graph.add_link(clear, blocked, RouteGraph.Kind.RUN)
	graph.add_link(blocked, clear, RouteGraph.Kind.RUN)
	var director := BotDirector.new(game, graph)
	var boss := TeamCommander.new(0, director)
	var ferry := director.vehicle_orders.ferry
	hull.crew[0] = 100
	var passenger := director.add_bot(0, Transform3D(Basis.IDENTITY, Vector3(-90, 0.05, 0))).soldier
	hull.crew[1] = passenger.entity_id
	await physics_frame
	await physics_frame
	var aim := graph.points[blocked]
	for i in BotDirector.RAYS_PER_TICK:
		director.take_ray()
	ferry.pilot(hull, PlayerCommand.new(), boss, aim, false)
	var waiting: Dictionary = ferry.trips[hull.entity_id]
	checks.check(waiting.drop == Vector3.INF and waiting.site.step == 0,
		"the ferry waits to probe if the shared query budget is spent")
	var highest := hull.position.y
	var furthest := hull.position.x
	var unloaded := false
	var early_exit := false
	for i in 60 * 35:
		await physics_frame
		game.tick += 1
		var command := PlayerCommand.new()
		ferry.pilot(hull, command, boss, aim, false)
		hull.drive(command, game.fleet.ground_at(hull.position), 1.0 / 60.0)
		highest = maxf(highest, hull.position.y)
		furthest = maxf(furthest, hull.position.x)
		if command.has(PlayerCommand.BOARD):
			early_exit = true
		if ferry.passenger_exit(game, hull):
			unloaded = true
			break
	var trip: Dictionary = ferry.trips[hull.entity_id]
	var drop: Vector3 = trip.drop
	checks.check(drop.is_equal_approx(graph.points[clear]), "the ferry skips an obstructed drop and finds connected ground")
	checks.check(highest > 14.0 and unloaded and hull.position.distance_to(drop) < 5.0,
		"the ferry clears a wall and slows to unload (height %.1f m, furthest x %.1f, position %s, phase %d, retries %d)" %
		[highest, furthest, hull.position, trip.phase, trip.retries])
	checks.check(not early_exit, "the pilot stays at the controls until the passengers have left")
	if unloaded:
		var state := director.vehicle_orders.get_state()
		ferry.trips.clear()
		director.vehicle_orders.set_state(state)
		checks.check(ferry.passenger_exit(game, hull), "the planned landing survives a state round trip")
		hull.velocity = Vector3.RIGHT * 8.0
		checks.check(not ferry.passenger_exit(game, hull), "a ferry moving too fast can't unload")
		hull.velocity = Vector3.ZERO
		var recovery: Dictionary = ferry.trips[hull.entity_id]
		game.tick += BotFerry.LAND_TICKS + 8 - game.tick % 8
		var human := game.add_soldier(0, Transform3D(Basis.IDENTITY, hull.position))
		hull.crew[1] = human.entity_id
		human.mount(hull.entity_id, 1)
		var park := PlayerCommand.new()
		ferry.pilot(hull, park, boss, aim, false)
		checks.check(park.has(PlayerCommand.BOARD) and recovery.phase == BotFerry.Phase.UNLOAD and recovery.drop == drop,
			"the pilot leaves the ferry parked when its only passenger is a person")
		hull.crew[1] = passenger.entity_id
		recovery.drop = Vector3.INF
		recovery.returning = true
		recovery.recovering = true
		recovery.sites_ready = true
		recovery.sites.clear()
		recovery.site.clear()
		recovery.next_probe = 0
		game.tick += 8 - game.tick % 8
		var command := PlayerCommand.new()
		ferry.pilot(hull, command, boss, Vector3.INF, true)
		checks.check(recovery.settle and command.has(PlayerCommand.JUMP) and ferry.passenger_exit(game, hull),
			"exhausted return sites fall back to a low and slow release")
		hull.crew[1] = 0
		ferry.pilot(hull, command, boss, Vector3.INF, true)
		checks.check(command.has(PlayerCommand.BOARD), "the pilot can leave after the last passenger")
	boss = null
	director = null
	game.free()
	checks.finish(self)


func _box(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	root.add_child(body)
