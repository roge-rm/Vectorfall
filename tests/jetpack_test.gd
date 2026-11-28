extends SceneTree

## Checks the jetpack and moving through the air: jetting lifts you and
## drains energy, energy refills only after a delay, an empty tank can't lift
## you, and speed is kept in the air and on landing.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/jetpack_test.gd

var checks := TestWorld.Checks.new()
var game: Match
var input := TestWorld.Scripted.new()
var soldier: Soldier


func _initialize() -> void:
	TestWorld.flat_ground(root)
	game = Match.new(5)
	root.add_child(game)
	soldier = game.add_soldier(0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0)), input)
	_run.call_deferred()


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	var t := soldier.tuning
	await ticks(30)
	checks.check(soldier.grounded and absf(soldier.global_position.y) < 0.05, "the soldier stands on the ground")
	checks.check(soldier.energy == t.energy_max, "the tank starts full")

	input.command.buttons = PlayerCommand.JET
	await ticks(60)
	var expected := t.energy_max - t.energy_drain
	checks.check(absf(soldier.energy - expected) < 1.0, "a second of jetting drains %.0f energy (%.1f left)" % [t.energy_drain, soldier.energy])
	checks.check(soldier.global_position.y > 2.0, "jetting for a second gains height (%.2f m)" % soldier.global_position.y)
	checks.check(soldier.velocity.y > 0.0, "still rising while jetting")

	input.command.buttons = 0
	var held := soldier.energy
	await ticks(int(t.refill_delay * 60.0) - 6)
	checks.check(soldier.energy == held, "energy doesn't refill before the delay")
	await ticks(60)
	checks.check(soldier.energy > held + t.energy_refill * 0.8, "energy refills after the delay (%.1f to %.1f)" % [held, soldier.energy])
	await ticks(400)
	checks.check(soldier.energy == t.energy_max, "energy refills to full and stops there")
	checks.check(soldier.grounded, "back on the ground after the jet")

	# Hold the jet until the tank runs dry: you fall once it's empty.
	input.command.buttons = PlayerCommand.JET
	await ticks(int(t.energy_max / t.energy_drain * 60.0) + 5)
	checks.check(soldier.energy == 0.0, "holding the jet empties the tank")
	var rise := soldier.velocity.y
	await ticks(30)
	var fallen := rise - soldier.velocity.y
	checks.check(absf(fallen - t.gravity * 0.5) < 0.5, "an empty tank can't hold you up (%.2f m/s lost in half a second)" % fallen)
	await ticks(400)
	checks.check(soldier.grounded and soldier.energy == 0.0, "holding the jet keeps the tank empty, so no refill")

	# On the ground with an empty tank, jet does nothing.
	var ground_y := soldier.global_position.y
	await ticks(30)
	checks.check(absf(soldier.global_position.y - ground_y) < 0.01, "can't jet off the ground at zero energy")
	input.command.buttons = 0
	await ticks(10)

	# Speed is kept in the air: launch sideways and don't steer.
	soldier.set_state(_state_with(Vector3(0.0, 15.0, 0.0), Vector3(20.0, 0.0, 0.0)))
	await ticks(30)
	checks.check(soldier.horizontal_speed() > 19.9, "no speed lost in the air (%.2f m/s)" % soldier.horizontal_speed())
	# Facing +x and steering right, towards +z.
	input.command.move = Vector2(1.0, 0.0)
	input.command.yaw = -PI * 0.5
	await ticks(30)
	var after := soldier.horizontal_speed()
	var side := soldier.velocity.z
	checks.check(side > 1.0 and side <= t.air_control_speed + 0.01, "steering in the air turns you a little (%.2f m/s sideways)" % side)
	checks.check(after > 19.9 and soldier.velocity.x > 19.9, "and keeps your speed (%.2f m/s)" % after)
	input.command.move = Vector2.ZERO
	while not soldier.grounded:
		await ticks(1)
	await ticks(2)
	checks.check(soldier.horizontal_speed() > t.run_speed + 3.0, "landing on flat ground keeps your speed (%.2f m/s)" % soldier.horizontal_speed())

	# Landing on a downhill keeps the fall as speed along the slope.
	var hill := TestWorld.slope(root, 25.0)
	hill.position += Vector3(0.0, 60.0, 300.0)
	soldier.set_state(_state_with(Vector3(30.0, 50.0, 300.0), Vector3(10.0, -12.0, 0.0)))
	while not soldier.grounded:
		await ticks(1)
	checks.check(soldier.horizontal_speed() > 10.0, "landing on a downhill keeps and adds speed (%.2f m/s)" % soldier.horizontal_speed())
	await _check_bodies_settle()
	await _check_fall_damage()
	checks.finish(self)


func _check_bodies_settle() -> void:
	soldier.velocity = Vector3(55.0, 0.0, 0.0)
	var death_at := soldier.global_position
	soldier.die()
	await ticks(30)
	var skid := soldier.global_position.x - death_at.x
	checks.check(skid > 0.4 and skid < 1.3 and soldier.velocity.is_zero_approx(),
		"a fast soldier dying on a slope skids briefly (%.2f m)" % skid)

	var start := Vector3(30.0, 50.0, 300.0)
	for speed: float in [0.0, 20.0]:
		soldier.revive(Transform3D(Basis.IDENTITY, start))
		soldier.velocity = Vector3(speed, -12.0, 0.0)
		soldier.die()
		for i in 90:
			await ticks(1)
			if soldier.grounded:
				break
		checks.check(soldier.grounded and soldier.global_position.y < start.y, "a body killed in the air lands on the slope")
		var landing := soldier.global_position
		await ticks(30)
		skid = soldier.global_position.x - landing.x
		if speed > 0.0:
			checks.check(skid > 0.4 and skid < 1.3, "a moving body skids briefly on landing (%.2f m)" % skid)
		else:
			checks.check(absf(skid) < 0.1, "a body falling straight down doesn't start sliding")
		var settled := soldier.global_position
		await ticks(30)
		checks.check(soldier.velocity.is_zero_approx() and soldier.global_position.distance_to(settled) < 0.1,
			"the body stays where it settled")


func _state_with(position: Vector3, velocity: Vector3) -> Dictionary:
	var state := soldier.get_state()
	state.position = position
	state.velocity = velocity
	state.grounded = false
	state.energy = soldier.tuning.energy_max
	return state


func _check_fall_damage() -> void:
	var high := Transform3D(Basis.IDENTITY, Vector3(0.0, 25.0, 0.0))
	var fall := Vector3.DOWN * 26.0
	soldier.revive(high)
	soldier.velocity = fall
	await ticks(55)
	var after := soldier.health
	checks.check(soldier.grounded and after > 0.0 and after < soldier.tuning.health_max, "a hard landing hurts a living soldier")
	await ticks(30)
	checks.check(soldier.health == after, "standing after a hard landing deals damage only once")

	soldier.revive(high)
	soldier.velocity = fall
	input.command.buttons = PlayerCommand.JET
	for i in 120:
		await ticks(1)
		if soldier.grounded:
			break
	checks.check(soldier.grounded and soldier.health == soldier.tuning.health_max, "jet braking makes the same fall safe")
	input.command.buttons = 0

	var near_floor := Vector3(0.0, 0.7, 0.0)
	soldier.set_state(_state_with(near_floor, Vector3(42.0, -8.0, 0.0)))
	await ticks(12)
	checks.check(soldier.grounded and soldier.health == soldier.tuning.health_max and soldier.horizontal_speed() > 35.0,
		"a shallow landing at ski speed keeps momentum and causes no damage")

	game.running = false
	soldier.set_state(_state_with(near_floor, Vector3.DOWN * 52.0))
	for i in 3:
		await ticks(1)
		soldier.simulate(PlayerCommand.new(), 1.0 / 60.0, true)
	checks.check(soldier.grounded and soldier.health == soldier.tuning.health_max, "movement prediction leaves fall damage to the host")
	soldier.set_state(_state_with(near_floor, Vector3.DOWN * 52.0))
	game.running = true
	await ticks(3)
	checks.check(soldier.dead, "a severe impact can kill a full-health soldier")
