extends SceneTree

## Checks Ochre Fold: it builds in reasonable time, its spawns are on the
## ground beside each flag, both flags can be reached on the route graph
## from the stands and spawns, it has every kind of point of interest, and a
## soldier skiing down from a base gets past 30 m/s.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/ochre_fold_test.gd

var checks := TestWorld.Checks.new()
var map: OchreFold
var game: Match
var input := TestWorld.Scripted.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	map = OchreFold.new()
	root.add_child(map)
	game = Match.new(2)
	game.terrain = map.terrain
	root.add_child(game)
	var graph := map.route_graph
	print("  Ochre Fold built in %.2f s: terrain chunks %.2f s, route graph %.2f s, %d points, %d links" % [map.build_seconds, map.terrain_seconds, map.graph_seconds, graph.points.size(), graph.links.size()])
	checks.check(map.build_seconds < 20.0, "the map builds in %.1f s" % map.build_seconds)
	checks.check(map.terrain.size() >= 1500.0, "the terrain is %.0f m across" % map.terrain.size())

	for team in 2:
		var good := true
		for point in map.spawn_points(team):
			var o := point.origin
			var away := Vector2(o.x - map.base_x(team), o.z).length()
			good = good and away > 30.0 and away < 50.0 and not map.blocked_at(o.x, o.z)
			good = good and absf(o.y - 0.3 - map.surface_at(o.x, o.z)) < 0.05 and absf(o.y - 0.3 - map.ground_height(o.x, o.z)) < 0.05
		checks.check(good, "team %d's 8 spawn points are on the ground 30 to 50 m from its flag" % team)

	var stands := [graph.interest_points(RouteGraph.FLAG_STAND, 0), graph.interest_points(RouteGraph.FLAG_STAND, 1)]
	checks.check(stands[0].size() == 1 and stands[1].size() == 1, "each base has one flag stand point")
	var reach := true
	for team in 2:
		reach = reach and graph.connected(stands[team][0], stands[1 - team][0])
		for spawn in graph.interest_points(RouteGraph.SPAWN, team):
			reach = reach and graph.connected(spawn, stands[1 - team][0]) and graph.connected(spawn, stands[team][0])
	checks.check(reach, "both flags can be reached from both stands and every spawn")
	for kind in [RouteGraph.SPAWN, RouteGraph.WAY_IN, RouteGraph.DEFENCE, RouteGraph.FLAG_APPROACH, RouteGraph.VEHICLE_PAD, RouteGraph.DEPLOY]:
		checks.check(graph.interest_points(kind, 0).size() > 0 and graph.interest_points(kind, 1).size() > 0, "both teams have %s points" % kind)
	var halves := [0, 0]
	for point in graph.interest_points(RouteGraph.HIGH_GROUND, -1):
		if graph.points[point].x < -30.0:
			halves[0] += 1
		elif graph.points[point].x > 30.0:
			halves[1] += 1
	checks.check(halves[0] >= 2 and halves[1] >= 2, "each half has high ground for midfield (%d and %d)" % halves)
	checks.check(graph.interest_points(RouteGraph.SNIPER, -1).size() >= 4, "it has sniper perches")
	var floating := 0
	for k in graph.points.size():
		var p := graph.points[k]
		if p.y < map.ground_height(p.x, p.z) - 0.5:
			floating += 1
	checks.check(floating == 0, "no route point is under the ground")

	var planner := RoutePlanner.new()
	var spawn: int = graph.interest_points(RouteGraph.SPAWN, 0)[0]
	var route := planner.plan(graph, spawn, stands[1][0], 0.0, 100.0)
	var ski_links := 0
	for k in route.size() - 1:
		if graph.link_between(route[k], route[k + 1]).kind == RouteGraph.Kind.SKI:
			ski_links += 1
	checks.check(route.size() > 2 and ski_links >= 3, "a route from the spawn to the enemy stand has %d points and skis %d links" % [route.size(), ski_links])

	var x := map.base_x(0) + 60.0
	var soldier := game.add_soldier(0, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(x, map.height_at(x, 0.0) + 1.0, 0.0)), input)
	input.command.yaw = -PI * 0.5
	input.command.move = Vector2(0.0, 1.0)
	input.command.buttons = PlayerCommand.SKI
	var top := 0.0
	for i in 600:
		await physics_frame
		top = maxf(top, soldier.velocity.length())
	checks.check(top > 30.0, "skiing straight down from the base reaches %.1f m/s" % top)
	checks.finish(self)
