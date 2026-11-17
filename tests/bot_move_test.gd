extends SceneTree

## Checks bots getting around: a bot goes from its base to the enemy flag
## stand on the test map in good time without getting stuck, skiing and
## jetting past 40 m/s on the way and back, a bot boxed in by tall walls
## notices it's stuck and gets out another way, and the same seed moves bots
## the same way.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/bot_move_test.gd

var checks := TestWorld.Checks.new()


func _initialize() -> void:
	_run.call_deferred()


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


## A test map and a match with no flags and some bots, all under one node.
func _test_map_match(match_seed: int, bots_per_team: int) -> Dictionary:
	var holder := Node3D.new()
	root.add_child(holder)
	var map := TestMap.new()
	holder.add_child(map)
	var game := Match.new(match_seed)
	for team in 2:
		game.spawns[team] = map.spawn_points(team)
	holder.add_child(game)
	var director := BotDirector.new(game, map.route_graph)
	for team in 2:
		for k in bots_per_team:
			director.add_bot(team, map.spawn_point(team, k))
	return { "holder": holder, "map": map, "game": game, "director": director }


func _run() -> void:
	await _base_to_base()
	await _boxed_in()
	await _same_seed()
	checks.finish(self)


func _base_to_base() -> void:
	var setup := _test_map_match(3, 0)
	var map: TestMap = setup.map
	var director: BotDirector = setup.director
	var brain := director.add_bot(0, map.spawn_point(0, 3))
	var s := brain.soldier
	var reached := -1.0
	var top := 0.0
	var skied := false
	var jetted := false
	var routes_at_top := 0
	for i in 60 * 90:
		await physics_frame
		if s.velocity.length() > top:
			top = s.velocity.length()
			routes_at_top = brain.stats.routes
		skied = skied or s.skiing
		jetted = jetted or s.jetting
		if reached < 0.0 and brain.stats.routes >= 1:
			reached = i / 60.0
		if brain.stats.routes >= 2:
			break
	var stand := map.stand_top(1)
	checks.check(reached > 0.0 and reached < 45.0, "a bot gets from its base to the enemy stand in %.1f s" % reached)
	checks.check(brain.stats.stuck_spots.is_empty(), "without getting stuck (%d stuck spots)" % brain.stats.stuck_spots.size())
	checks.check(skied and jetted, "skiing and jetting on the way")
	checks.check(top >= 40.0, "it reaches %.1f m/s, on route %d" % [top, routes_at_top + 1])
	checks.check(brain.stats.routes >= 2, "and gets home again (%d routes)" % brain.stats.routes)
	checks.check(stand.x > 0.0, "the enemy stand is the far one")
	setup.holder.free()
	await ticks(2)


## A bot facing into a box of tall walls open behind it, sent to a point past
## the far wall.
func _boxed_in() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	TestWorld.flat_ground(holder)
	for wall: Array in [[Vector3(5.0, 20.0, 0.0), Vector3(1.0, 40.0, 12.0)], [Vector3(1.25, 20.0, 5.0), Vector3(8.5, 40.0, 1.0)], [Vector3(1.25, 20.0, -5.0), Vector3(8.5, 40.0, 1.0)], [Vector3(1.25, 40.5, 0.0), Vector3(8.5, 1.0, 11.0)]]:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = wall[1]
		shape.shape = box
		body.position = wall[0]
		body.add_child(shape)
		holder.add_child(body)
	var graph := RouteGraph.new()
	var inside := graph.add_point(Vector3(0.0, 0.0, 0.0))
	var beyond := graph.add_point(Vector3(60.0, 0.0, 0.0))
	var round := graph.add_point(Vector3(-30.0, 0.0, 30.0))
	graph.add_link(inside, beyond, RouteGraph.Kind.RUN)
	graph.add_link(inside, round, RouteGraph.Kind.RUN)
	graph.add_link(round, beyond, RouteGraph.Kind.RUN)
	var game := Match.new(5)
	holder.add_child(game)
	var director := BotDirector.new(game, graph)
	var brain := director.add_bot(0, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-1.0, 0.2, 0.0)))
	await physics_frame
	brain.go_to(beyond)
	var freed := -1.0
	for i in 60 * 60:
		await physics_frame
		if brain.goal == BotBrain.Goal.HOLD:
			freed = i / 60.0
			break
	var spots: Array = brain.stats.stuck_spots
	checks.check(not spots.is_empty(), "a boxed in bot notices it's stuck (%d times)" % spots.size())
	var escapes := []
	for spot: Dictionary in spots:
		escapes.append(spot.escape)
	checks.check(escapes.has("other way"), "and tries another way (%s)" % ", ".join(escapes))
	checks.check(freed > 0.0, "and gets out to the point past the box in %.1f s" % freed)
	checks.check(brain.stats.time_stuck > 0.0, "the time it was stuck is counted (%.1f s)" % brain.stats.time_stuck)
	holder.free()
	await ticks(2)


## Two runs from the same seed end with every bot in the same place.
func _same_seed() -> void:
	var runs := []
	for run in 2:
		var setup := _test_map_match(11, 2)
		var game: Match = setup.game
		await ticks(900)
		var positions := []
		var ids := game.entities.keys()
		ids.sort()
		for id: int in ids:
			positions.append(game.soldier(id).global_position)
		runs.append(positions)
		setup.holder.free()
		await ticks(2)
	var same: bool = runs[0].size() == 4 and runs[0] == runs[1]
	var moved: bool = runs[0].size() == 4 and runs[0][0].distance_to(Vector3(-194.0, 8.0, -8.75)) > 20.0
	checks.check(same, "the same seed puts the bots in the same places after 15 s")
	checks.check(moved, "and they've moved away from their base")
