extends SceneTree

var checks := TestWorld.Checks.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for map_name in GameMap.NAMES:
		var holder := Node.new()
		root.add_child(holder)
		var arena := GameMap.make(map_name)
		holder.add_child(arena)
		var game := ArenaMatch.make(holder, arena, 5, 1, 1, 8, true, true)
		game.running = false
		checks.check(game.flags.is_empty() and game.hold_points.size() == 3,
			"%s starts with three control points and no flags" % arena.title)
		await _check_sites(game, arena)
		checks.check((game.neutral_station != null) == GameMap.RESUPPLY_ARENAS.has(map_name),
			"%s only spawns an ammo pad if the map supports it" % arena.title)
		var ctf := ArenaMatch.make(holder, arena, 5, 1)
		ctf.running = false
		checks.check(ctf.flags.size() == 2 and ctf.hold_points.is_empty(),
			"%s can still play Capture the Flag" % arena.title)
		ctf.free()
		if map_name not in GameMap.RESUPPLY_ARENAS:
			holder.queue_free()
			await process_frame
			continue
		var director := BotDirector.new(game, arena.route_graph)
		var lime := director.add_bot(0, arena.spawn_point(0, 0))
		var blue := director.add_bot(1, arena.spawn_point(1, 0))
		var support := director.add_bot(0, arena.spawn_point(0, 1))
		checks.check(lime._control_goal()[0] == BotBrain.Goal.TAKE_POINT and lime._control_goal()[1] != support._control_goal()[1],
			"bots split up to take points")
		var point := game.hold_points[0]
		var side_point := game.hold_points[1]
		side_point.owning_team = 0
		checks.check(support._control_goal()[1] == game.hold_points[2].spot,
			"the spare bot takes another point in a small team")
		side_point.owning_team = -1
		lime.goal = BotBrain.Goal.HOLD_POINT
		lime.goal_target = point.spot
		lime.at_goal = true
		lime.soldier.position = point.spot + Vector3.RIGHT * (HoldPoint.RADIUS + 1.0)
		lime._check_goal()
		checks.check(not lime.at_goal, "a defender walks back into range after being knocked out")
		lime.goal = BotBrain.Goal.NONE
		lime.soldier.position = point.position
		blue.soldier.position = point.position + Vector3.UP * 12
		game._step_objectives(1.0)
		checks.check(point.challenger == 0 and not point.contested, "flying above a point does not contest it")
		blue.soldier.position = point.position
		game._step_objectives(2.0)
		checks.check(point.contested and point.owning_team == -1 and point.progress == 0.0,
			"both teams contest a point and interrupt capture")
		blue.soldier.position = arena.spawn_point(1, 0).origin
		for tick in 180:
			game._step_objectives(1.0 / 60.0)
		checks.check(point.owning_team == 0 and lime._control_goal()[0] == BotBrain.Goal.HOLD_POINT
			and blue._control_goal()[0] == BotBrain.Goal.RETAKE_POINT,
			"three seconds takes a point and changes both bot duties")
		lime.soldier.position = arena.spawn_point(0, 0).origin
		for tick in 300:
			game._step_objectives(1.0 / 60.0)
		checks.check(game.scores == [1, 0] and not game.over, "an empty owned point scores after five seconds")
		blue.soldier.position = point.position
		game._step_objectives(2.0)
		checks.check(game.scores == [1, 0] and point.challenger == 1, "a challenge pauses scoring")
		var state := game.get_state(false)
		game._step_objectives(1.0)
		checks.check(point.owning_team == 1, "the other team retakes a point")
		game.set_state(state)
		checks.check(point.owning_team == 0 and point.challenger == 1 and point.progress == 2.0,
			"ownership and progress survive a match snapshot")
		game.time_left = 1.0
		game._step_objectives(1.0)
		checks.check(game.over and game.winner == 0, "the team with the most points wins at time up")

		var pad := game.neutral_station
		var controlled := map_name == "nightline_foundry"
		checks.check((pad.control_index >= 0) == controlled, "only the Foundry pad is controlled by a point")
		if controlled:
			checks.check(not game.station_working(pad) and pad.control_index == 1
				and HoldPoint.contains(pad.position, side_point.position), "Foundry's B ammo starts off inside the control area")
			side_point.owning_team = 0
		lime.soldier.position = pad.position + Vector3(6, 0, 0)
		lime.soldier.ammo[0] = 0
		lime._think_ctf()
		checks.check(lime.goal == BotBrain.Goal.AMMO and lime.goal_target == pad.position and lime.direct,
			"low ammo sends a bot onto the nearby pad")
		for bot in [lime, blue]:
			var who: Soldier = bot.soldier
			who.position = pad.position + Vector3.UP * InventoryStation.PAD_TOP
			who.ammo[0] = 0
			who.grenades = 0
			who.mines = 0
			who.deploy_ready = false
			var next := who.loadout.duplicate()
			next.pack = Pack.REPAIR if who.loadout.pack != Pack.REPAIR else Pack.AMMO
			who.next_loadout = next
			game.generator(who.team).destroyed = true
		game._step_stations(0.0, game.entities.keys())
		for bot in [lime, blue]:
			var who: Soldier = bot.soldier
			var ammo := 0 if controlled and who.team == 1 else who.max_ammo(0)
			checks.check(who.ammo[0] == ammo and who.grenades == 0 and who.mines == 0
				and not who.deploy_ready and not who.next_loadout.equals(who.loadout) and game.station_under(who) == null,
				"the pad refills only allowed players without generator power or loadout changes")
		lime.soldier.ammo[0] = 0
		lime.soldier.position = arena.spawn_point(0, 0).origin
		game._step_stations(2.0, game.entities.keys())
		lime.soldier.position = pad.position
		game._step_stations(0.0, game.entities.keys())
		checks.check(lime.soldier.ammo[0] == 0, "a quick return cannot reuse the neutral pad")
		game._step_stations(InventoryStation.AMMO_COOLDOWN, game.entities.keys())
		checks.check(lime.soldier.ammo[0] == 0, "staying on the pad does not refill ammo")
		lime.soldier.position = arena.spawn_point(0, 0).origin
		game._step_stations(0.0, game.entities.keys())
		lime.soldier.position = pad.position
		game._step_stations(0.0, game.entities.keys())
		checks.check(lime.soldier.ammo[0] == lime.soldier.max_ammo(0), "the pad refills on re-entry once ready")
		if controlled:
			side_point.contested = true
			game._step_stations(0.0, game.entities.keys())
			checks.check(not game.station_working(pad) and blue.soldier.ammo[0] == 0, "contesting B pauses ammo")
			side_point.contested = false
			side_point.owning_team = 1
			var retaken := game.get_state(false)
			side_point.owning_team = -1
			pad.control_index = -1
			game.set_state(retaken)
			game._step_stations(0.0, game.entities.keys())
			checks.check(game.station_team(pad) == 1 and blue.soldier.ammo[0] == blue.soldier.max_ammo(0),
				"retaking B transfers ammo access and both survive a snapshot")
		holder.queue_free()
		await process_frame
	checks.finish(self)


func _check_sites(game: Match, arena: GameMap) -> void:
	if arena.terrain != null:
		var sites := PackedVector3Array()
		var speeds := PackedFloat32Array()
		for point in game.hold_points:
			sites.append(point.position)
			speeds.append(0.0)
		arena.terrain.keep_collision_near(sites, speeds, false)
	await physics_frame
	await physics_frame
	var graph := arena.route_graph
	var bounds := arena.tactical_bounds()
	for point in game.hold_points:
		var at := point.position
		var hit := game.world_ray(at + Vector3.UP * 4.0, at + Vector3.DOWN * 2.0, Match.WORLD_LAYER)
		var grounded: bool = not hit.is_empty() and absf(hit.position.y - at.y) < 0.1 and hit.normal.y >= 0.7
		var target := graph.nearest(at)
		var clear := bounds.has_point(Vector2(at.x, at.z)) and not arena.blocked_at(at.x, at.z)
		var reachable := target >= 0 and graph.points[target].distance_to(at) < 36.0
		for team in 2:
			var start := graph.nearest(arena.spawn_point(team, 0).origin)
			reachable = reachable and start >= 0 and graph.reachable(start, target)
		checks.check(clear and grounded and reachable, "%s point %s has a clear, walkable site and bot routes from both bases" % [arena.title, point.letter])
		for other in game.hold_points:
			if other.letter > point.letter:
				var separation := Vector2(other.position.x - at.x, other.position.z - at.z)
				checks.check(separation.length() > HoldPoint.RADIUS * 2.0,
					"%s points %s and %s have separate capture areas" % [arena.title, point.letter, other.letter])
