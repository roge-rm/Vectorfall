extends SceneTree

var checks := TestWorld.Checks.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for map_name in GameMap.CONTROL_ARENAS:
		var holder := Node.new()
		root.add_child(holder)
		var arena := GameMap.make(map_name)
		holder.add_child(arena)
		var game := ArenaMatch.make(holder, arena, 5, 1, 1, 8, true, true)
		game.running = false
		checks.check(game.flags.is_empty() and game.hold_points.size() == 3,
			"%s starts with three control points and no flags" % arena.title)
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
			checks.check(who.ammo[0] == who.max_ammo(0) and who.grenades == 0 and who.mines == 0
				and not who.deploy_ready and not who.next_loadout.equals(who.loadout) and game.station_under(who) == null,
				"the neutral pad refills weapon ammo without power or loadout changes")
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
		holder.queue_free()
		await process_frame
	checks.finish(self)
