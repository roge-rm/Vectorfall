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
		var on_deck := true
		for point in map.spawn_points(team):
			var off := point.origin - Vector3(map.base_x(team), 0.0, 0.0)
			on_deck = on_deck and absf(off.x) < TestMap.BASE_SIZE * 0.5 and absf(off.z) < TestMap.BASE_SIZE * 0.5
		checks.check(on_deck and map.spawn_points(team).size() == 8, "team %d's 8 spawn points are on its base" % team)

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
