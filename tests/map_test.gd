extends SceneTree

## Checks the test map: every spawn point is on its own team's base deck,
## and skiing straight down from a base reaches about 30 m/s.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/map_test.gd

var checks := TestWorld.Checks.new()
var map: TestMap
var game: Match
var input := TestWorld.Scripted.new()


func _initialize() -> void:
	map = TestMap.new()
	root.add_child(map)
	game = Match.new(2)
	root.add_child(game)
	_run.call_deferred()


func _run() -> void:
	for team in 2:
		var good := map.spawn_points(team).size() == 8
		for point in map.spawn_points(team):
			var away := Vector2(point.origin.x - map.base_x(team), point.origin.z).length()
			good = good and away > 30.0 and away < 50.0 and not map.blocked_at(point.origin.x, point.origin.z)
			good = good and absf(point.origin.y - map.surface_at(point.origin.x, point.origin.z)) < 1.0
		checks.check(good, "team %d's 8 spawn points are 30 to 50 m from its flag, clear and on the ground" % team)
		var ramps_work := true
		for ramp in GameMap.BASE_RAMPS:
			var ramp_middle := map.base_place(team, GameMap.BASE_SIZE * 0.5 + GameMap.RAMP_RUN * 0.5, ramp.x, map.deck_height())
			var hit := game.world_ray(ramp_middle + Vector3.UP, ramp_middle - Vector3.UP * 3.0, Match.WORLD_LAYER)
			var top := map.base_place(team, GameMap.BASE_SIZE * 0.5 - 2.0, ramp.x, map.deck_height())
			var foot := map.base_place(team, GameMap.BASE_SIZE * 0.5 + GameMap.RAMP_RUN + 1.5, ramp.x, 0.0)
			foot.y = map.surface_at(foot.x, foot.z)
			var link := map.route_graph.link_between(map.route_graph.nearest(foot), map.route_graph.nearest(top))
			ramps_work = ramps_work and not hit.is_empty() and absf(hit.position.y - map.surface_at(ramp_middle.x, ramp_middle.z)) < 0.02
			ramps_work = ramps_work and link != null and not link.must_jet
		checks.check(ramps_work, "team %d has three ramps with collision and bot routes up to the deck" % team)

	var x := map.base_x(0) + 20.0
	var soldier := game.add_soldier(0, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(x, map.height_at(x, 0.0) + 1.0, 0.0)), input)
	input.command.yaw = -PI * 0.5
	input.command.move = Vector2(0.0, 1.0)
	input.command.buttons = PlayerCommand.SKI
	var top := 0.0
	for i in 600:
		await physics_frame
		top = maxf(top, soldier.velocity.length())
	checks.check(top > 25.0, "skiing straight down from the base reaches %.1f m/s" % top)
	checks.finish(self)
