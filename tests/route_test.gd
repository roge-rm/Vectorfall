extends SceneTree

## Checks the bots' route graph and planner: the test map's graph joins both
## bases with every kind of link, keeps its points of interest and survives
## being saved, and the planner takes a ski line over a flat run, and jets
## over a wall only when it has the energy.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . -s tests/route_test.gd

var checks := TestWorld.Checks.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var map := TestMap.new()
	var graph := map.route_graph
	checks.check(graph.points.size() > 150 and graph.links.size() > 1000, "the test map has a route graph (%d points, %d links)" % [graph.points.size(), graph.links.size()])
	var stands := [graph.interest_points(RouteGraph.FLAG_STAND, 0), graph.interest_points(RouteGraph.FLAG_STAND, 1)]
	checks.check(stands[0].size() == 1 and stands[1].size() == 1, "each base has one flag stand point")
	var on_stand := true
	for team in 2:
		on_stand = on_stand and graph.points[stands[team][0]].distance_to(map.stand_top(team) - Vector3.UP * 0.5) < 1.0
	checks.check(on_stand, "the flag stand points are on the stands")
	for kind in [RouteGraph.SPAWN, RouteGraph.WAY_IN, RouteGraph.DEFENCE, RouteGraph.HIGH_GROUND]:
		checks.check(not graph.interest_points(kind, 0).is_empty() and not graph.interest_points(kind, 1).is_empty(), "both teams have %s points" % kind)
	checks.check(graph.connected(stands[0][0], stands[1][0]) and graph.connected(stands[1][0], stands[0][0]), "the stands are connected both ways")
	var spawn: int = graph.interest_points(RouteGraph.SPAWN, 0)[0]
	checks.check(graph.connected(spawn, stands[1][0]), "team 0's spawn connects to the enemy stand")
	var kinds := {}
	var walls := 0
	for link in graph.links:
		kinds[link.kind] = true
		if link.must_jet:
			walls += 1
	checks.check(kinds.size() == 3, "it has run, ski and jet links")
	checks.check(walls > 0, "the deck edges are jet links (%d)" % walls)
	var copy := RouteGraph.from_dict(graph.to_dict())
	checks.check(copy.points.size() == graph.points.size() and copy.links.size() == graph.links.size() and copy.interest.size() == graph.interest.size(), "the graph saves to plain data and back")

	var planner := RoutePlanner.new()
	var route := planner.plan(graph, spawn, stands[1][0], 0.0, 100.0)
	var ski_links := 0
	for k in route.size() - 1:
		if graph.link_between(route[k], route[k + 1]).kind == RouteGraph.Kind.SKI:
			ski_links += 1
	checks.check(route.size() > 2 and route[0] == spawn and route[-1] == stands[1][0], "a route plans from the spawn to the enemy stand (%d points)" % route.size())
	checks.check(ski_links >= 2, "it skis down %d links" % ski_links)
	map.free()

	# A flat run straight across, or a dip that's longer but downhill first.
	var test := RouteGraph.new()
	var a := test.add_point(Vector3(0.0, 0.0, 0.0))
	var flat := test.add_point(Vector3(100.0, 0.0, 0.0))
	var dip := test.add_point(Vector3(100.0, -30.0, 50.0))
	var b := test.add_point(Vector3(200.0, 0.0, 0.0))
	test.add_link(a, flat, RouteGraph.Kind.RUN)
	test.add_link(flat, b, RouteGraph.Kind.RUN)
	test.add_link(a, dip, RouteGraph.Kind.SKI)
	test.add_link(dip, b, RouteGraph.Kind.JET)
	checks.check(planner.plan(test, a, b, 0.0, 100.0) == [a, dip, b], "the planner takes the ski line over the flat run")
	checks.check(planner.plan(test, a, b, 0.0, 0.0) == [a, dip, b], "and even with no energy, running up the far side")

	# Straight over a wall, or round by a ramp.
	var wall := RouteGraph.new()
	var c := wall.add_point(Vector3(0.0, 0.0, 0.0))
	var top := wall.add_point(Vector3(10.0, 14.0, 0.0))
	var ramp := wall.add_point(Vector3(5.0, 0.0, 15.0))
	var d := wall.add_point(Vector3(20.0, 14.0, 0.0))
	wall.add_link(c, top, RouteGraph.Kind.JET, true)
	wall.add_link(top, d, RouteGraph.Kind.RUN)
	wall.add_link(c, ramp, RouteGraph.Kind.RUN)
	wall.add_link(ramp, d, RouteGraph.Kind.RUN)
	checks.check(planner.plan(wall, c, d, 0.0, 100.0) == [c, top, d], "with energy it jets over the wall")
	checks.check(planner.plan(wall, c, d, 0.0, 0.0) == [c, ramp, d], "with none it goes round by the ramp")
	var avoid := { wall.link_between(c, top): RoutePlanner.AVOID_COST }
	checks.check(planner.plan(wall, c, d, 0.0, 100.0, avoid) == [c, ramp, d], "a link it got stuck on is avoided")
	checks.finish(self)
