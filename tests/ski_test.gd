extends SceneTree

## Checks skiing on built-in slopes: skiing downhill gains speed past run
## speed, uphill loses it, standing on a slope without skiing stays put,
## landing on a downhill keeps the speed, drag tops speed out, the jet helps
## you up a hill, and top speed into a wall or the ground doesn't go through.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/ski_test.gd

const ANGLE := 25.0

var checks := TestWorld.Checks.new()
var game: Match
var input := TestWorld.Scripted.new()
var soldier: Soldier


func _initialize() -> void:
	# A 25° slope down towards +x from the origin, a long 30° one at z = 1000,
	# a wall on flat ground at z = -1000 and triangle mesh ground at z = -2000.
	TestWorld.slope(root, ANGLE)
	# Flat ground before the slope's top edge, making a crest at x = 0.
	var deck := TestWorld.slope(root, 0.0, 100.0)
	deck.position.x = -100.0
	var long := TestWorld.slope(root, 30.0, 4000.0)
	long.position.z = 1000.0
	var flat := TestWorld.flat_ground(root)
	flat.position = Vector3(0.0, 0.0, -1000.0)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 10.0, 20.0)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	wall.position = Vector3(20.5, 5.0, -1000.0)
	root.add_child(wall)
	var mesh := TestWorld.mesh_ground(root, 400.0)
	mesh.position.z = -2000.0
	var bumps := TestWorld.mesh_surface(root, _bump_height, -100.0, 800.0, 4.0)
	bumps.position.z = 3000.0
	game = Match.new(3)
	root.add_child(game)
	soldier = game.add_soldier(0, Transform3D(Basis.IDENTITY, on_slope(30.0) + Vector3.UP * 0.3), input)
	_run.call_deferred()


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


## A point on the 25° slope, x metres from its top edge.
func on_slope(x: float) -> Vector3:
	return Vector3(x, -x * tan(deg_to_rad(ANGLE)), 0.0)


func _run() -> void:
	var t := soldier.tuning
	await ticks(60)
	checks.check(soldier.grounded, "the soldier stands on the slope")
	var rest := soldier.global_position
	await ticks(120)
	checks.check(soldier.global_position.distance_to(rest) < 0.05, "standing on a slope without skiing stays put (moved %.3f m)" % soldier.global_position.distance_to(rest))

	input.command.buttons = PlayerCommand.SKI
	await ticks(120)
	var speed := soldier.velocity.length()
	checks.check(speed > t.run_speed + 4.0, "skiing down a slope for 2 s passes run speed (%.1f m/s)" % speed)
	checks.check(soldier.skiing and soldier.velocity.x > 0.0, "and is skiing downhill")

	# Skiing uphill at 25 m/s, with and without the jet.
	var uphill := Vector3(-cos(deg_to_rad(ANGLE)), sin(deg_to_rad(ANGLE)), 0.0) * 25.0
	soldier.set_state(_state_with(on_slope(150.0) + Vector3.UP * 0.05, uphill))
	await ticks(60)
	var slowed := soldier.velocity.length()
	checks.check(slowed < 25.0 - 5.0 and soldier.velocity.x < 0.0, "skiing uphill loses speed (25 to %.1f m/s)" % slowed)
	input.command.buttons = PlayerCommand.SKI | PlayerCommand.JET
	input.command.yaw = PI * 0.5
	soldier.set_state(_state_with(on_slope(150.0) + Vector3.UP * 0.05, uphill))
	await ticks(60)
	var jetted := soldier.horizontal_speed()
	checks.check(jetted > 25.0 * cos(deg_to_rad(ANGLE)), "jetting while skiing uphill keeps your speed (%.1f m/s)" % jetted)
	input.command.buttons = PlayerCommand.SKI
	input.command.yaw = 0.0

	# Landing on the downhill while skiing keeps nearly all the speed.
	var falling := Vector3(20.0, -10.0, 0.0)
	soldier.set_state(_state_with(on_slope(60.0) + Vector3.UP * 3.0, falling))
	while not soldier.grounded:
		await ticks(1)
	speed = soldier.velocity.length()
	checks.check(speed > falling.length() * 0.95, "landing on a downhill while skiing keeps the speed (%.1f of %.1f m/s)" % [speed, falling.length()])
	# Landing on flat ground loses only the fall.
	soldier.set_state(_state_with(Vector3(0.0, 3.0, -1000.0), falling))
	while not soldier.grounded:
		await ticks(1)
	speed = soldier.horizontal_speed()
	checks.check(speed > 19.5 and absf(soldier.velocity.y) < 1.0, "landing flat while skiing loses only the fall (%.1f m/s)" % speed)

	# Over the crest at 40 m/s you fly; at a slow ski you follow the ground.
	for pace: float in [40.0, 6.0]:
		soldier.set_state(_state_with(Vector3(-30.0, 0.05, 0.0), Vector3(pace, 0.0, 0.0)))
		var flew := false
		while soldier.global_position.x < 3.0:
			await ticks(1)
			if soldier.global_position.x > 0.5 and not soldier.grounded:
				flew = true
		if pace > 20.0:
			checks.check(flew, "skiing over a crest at %.0f m/s launches you" % pace)
		else:
			checks.check(not flew, "skiing over a crest at %.0f m/s follows the ground" % pace)

	# Four hills in a row, skiing down each and jetting up the next: the speed at
	# each ridge top goes up, and passes 50 m/s.
	input.command.buttons = PlayerCommand.SKI
	input.command.yaw = -PI * 0.5
	input.command.move = Vector2(0.0, 1.0)
	soldier.set_state(_state_with(Vector3(0.0, _bump_height(0.0, 0.0) + 0.05, 3000.0), Vector3.ZERO))
	# The fastest speed on each hill, counting the hill from one ridge top to the
	# next.
	var hill_tops: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var fastest := 0.0
	for i in 3000:
		# Jet when the ground ahead is higher, but not while high above it.
		var ground := _bump_height(soldier.global_position.x, 0.0)
		var x := soldier.global_position.x
		var rising := _bump_height(x + 4.0, 0.0) > ground
		# Jet on the way up a hill, and in the air when the ground ahead is about to meet the flight.
		var climbing := rising and (soldier.global_position.y < ground + 3.0 or _bump_height(x + soldier.velocity.x * 0.5, 0.0) > soldier.global_position.y + soldier.velocity.y * 0.5 - 1.0)
		input.command.buttons = PlayerCommand.SKI | (PlayerCommand.JET if climbing else 0)
		await ticks(1)
		if soldier.global_position.x >= 4.0 * HILL_PERIOD:
			break
		var hill := clampi(int(soldier.global_position.x / HILL_PERIOD), 0, 3)
		hill_tops[hill] = maxf(hill_tops[hill], soldier.velocity.length())
		fastest = maxf(fastest, soldier.velocity.length())
	var tops := hill_tops.map(func(v: float) -> String: return "%.1f" % v)
	checks.check(hill_tops[1] > hill_tops[0] + 8.0 and hill_tops[2] > hill_tops[0] + 6.0, "the top speed goes up from the first hill to the next (%s m/s)" % [tops])
	checks.check(maxf(hill_tops[1], hill_tops[2]) > 45.0 and fastest <= 81.0, "and passes 45 m/s by the third hill (%.1f m/s)" % maxf(hill_tops[1], hill_tops[2]))
	input.command.move = Vector2.ZERO
	input.command.yaw = 0.0

	# Skiing a long 30° slope tops out under the drag cap.
	soldier.set_state(_state_with(Vector3(5.0, -5.0 * tan(deg_to_rad(30.0)) + 0.05, 1000.0), Vector3.ZERO))
	var top := 0.0
	for i in 20:
		await ticks(60)
		top = maxf(top, soldier.velocity.length())
	checks.check(soldier.skiing and top > 60.0 and top <= 81.0, "skiing a long 30° slope reaches %.1f m/s and the limit holds" % top)
	# Falling from high up tops out too.
	input.command.buttons = 0
	soldier.set_state(_state_with(Vector3(0.0, 9000.0, 3000.0), Vector3.ZERO))
	top = 0.0
	for i in 10:
		await ticks(60)
		top = maxf(top, soldier.velocity.length())
	checks.check(top > 70.0 and top <= 81.0, "falling reaches %.1f m/s and the limit holds" % top)

	# 75 m/s into a wall and into the ground, box and triangle mesh: nothing
	# goes through.
	input.command.buttons = PlayerCommand.SKI
	soldier.set_state(_state_with(Vector3(0.0, 0.05, -1000.0), Vector3(75.0, 0.0, 0.0)))
	await ticks(30)
	checks.check(soldier.global_position.x < 20.0 - t.radius + 0.05, "skiing at top speed into a wall stops at it (x %.2f)" % soldier.global_position.x)
	soldier.set_state(_state_with(Vector3(-100.0, 30.0, -1000.0), Vector3(50.0, -55.0, 0.0)))
	await ticks(60)
	checks.check(soldier.global_position.y > -0.05, "75 m/s into box ground stays on top (y %.2f)" % soldier.global_position.y)
	soldier.set_state(_state_with(Vector3(-100.0, 30.0, -2000.0), Vector3(50.0, -55.0, 0.0)))
	await ticks(60)
	checks.check(soldier.global_position.y > -0.05, "75 m/s into mesh ground stays on top (y %.2f)" % soldier.global_position.y)
	soldier.set_state(_state_with(on_slope(10.0) + Vector3(0.0, 40.0, 0.0), Vector3(20.0, -70.0, 0.0)))
	await ticks(60)
	var surface := on_slope(soldier.global_position.x).y
	checks.check(soldier.global_position.y > surface - 0.05, "diving into the slope stays on top (%.2f m above)" % (soldier.global_position.y - surface))
	checks.finish(self)


## Four hills 150 m apart and 38 m high along x, a ridge at x = 0.
const HILL_PERIOD := 150.0
const HILL_HEIGHT := 38.0


func _bump_height(x: float, _z: float) -> float:
	if x < 0.0:
		return HILL_HEIGHT
	# Broad ridge tops that don't throw you, and tighter valleys.
	var t := (cos(TAU * x / HILL_PERIOD) + 1.0) * 0.5
	return HILL_HEIGHT * (1.0 - pow(1.0 - t, 1.5))


func _state_with(position: Vector3, velocity: Vector3) -> Dictionary:
	var state := soldier.get_state()
	state.position = position
	state.velocity = velocity
	state.grounded = false
	state.energy = soldier.tuning.energy_max
	return state
