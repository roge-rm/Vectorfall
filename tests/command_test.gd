extends SceneTree

## Checks that soldiers move only from their commands, that commands move them
## the right way, that the input map is there, and that soldier and match
## state round-trip through get_state() and set_state() and replay the same.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/command_test.gd

var checks := TestWorld.Checks.new()
var game: Match
var input := TestWorld.Scripted.new()
var soldier: Soldier


func _initialize() -> void:
	TestWorld.flat_ground(root)
	game = Match.new(42)
	root.add_child(game)
	soldier = game.add_soldier(0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0)), input)
	_run.call_deferred()


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "look_left", "look_right", "look_up", "look_down", "fire", "jet", "jump", "use", "deploy", "ski", "pause", "weapon_1", "weapon_2", "weapon_3", "weapon_4", "loadout", "grenade", "mine", "next_weapon", "prev_weapon"]:
		checks.check(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(), "the input map has %s" % action)
	var kinds := {}
	for event in InputMap.action_get_events("jet"):
		kinds[event.get_class()] = true
	checks.check(kinds.size() == 4, "jet is on the mouse, keyboard, gamepad trigger and shoulder")

	var command := PlayerCommand.new()
	command.move = Vector2(0.5, -0.25)
	command.yaw = 1.25
	command.pitch = -0.5
	command.buttons = PlayerCommand.JET | PlayerCommand.FIRE
	var copy := PlayerCommand.from_dict(command.to_dict())
	checks.check(copy.to_dict() == command.to_dict() and copy.has(PlayerCommand.JET) and not copy.has(PlayerCommand.JUMP), "a command round-trips through a dictionary")

	await ticks(30)
	var rest := soldier.global_position
	# Pressed actions don't reach a soldier whose commands come from elsewhere.
	for action in ["move_forward", "move_right", "jet", "jump"]:
		Input.action_press(action)
	await ticks(60)
	for action in ["move_forward", "move_right", "jet", "jump"]:
		Input.action_release(action)
	checks.check(soldier.global_position.distance_to(rest) < 0.001, "pressed keys don't move a soldier driven by other commands")
	checks.check(soldier.energy == soldier.tuning.energy_max, "pressed keys don't use its jet")

	# With the match stopped, nothing moves it even with a command waiting.
	game.running = false
	input.command.move = Vector2(0.0, 1.0)
	await ticks(30)
	checks.check(soldier.global_position.distance_to(rest) < 0.001, "a soldier only moves when the match steps it")
	game.running = true

	input.command.yaw = 0.0
	await ticks(60)
	var moved := soldier.global_position - rest
	checks.check(moved.z < -5.0 and absf(moved.x) < 0.05, "forward at yaw 0 runs towards -z (%s)" % moved)
	checks.check(absf(soldier.horizontal_speed() - soldier.tuning.run_speed) < 0.01, "running reaches run speed")
	input.command.yaw = PI * 0.5
	input.command.move = Vector2.ZERO
	await ticks(30)
	var stopped := soldier.global_position
	input.command.move = Vector2(0.0, 1.0)
	await ticks(30)
	moved = soldier.global_position - stopped
	checks.check(moved.x < -2.0 and absf(moved.z) < 0.05, "forward at yaw 90 degrees runs towards -x (%s)" % moved)
	input.command.move = Vector2(1.0, 0.0)
	stopped = soldier.global_position
	await ticks(30)
	moved = soldier.global_position - stopped
	checks.check(moved.z < -1.0, "right at yaw 90 degrees strafes towards -z (%s)" % moved)
	input.command.move = Vector2.ZERO
	input.command.pitch = 3.0
	await ticks(2)
	checks.check(soldier.pitch == Soldier.PITCH_LIMIT, "pitch stops short of straight up")
	input.command.pitch = 0.0

	# Soldier state: take it mid-jet, run on, then put it back and replay the
	# same commands. The ends have to match.
	input.command.buttons = PlayerCommand.JET
	input.command.move = Vector2(0.3, 1.0)
	await ticks(20)
	game.running = false
	var saved := soldier.get_state()
	var run := func() -> Dictionary:
		for i in 40:
			game.step(1.0 / 60.0)
		return soldier.get_state()
	var first: Dictionary = run.call()
	soldier.set_state(saved)
	checks.check(soldier.get_state() == saved, "set_state then get_state gives back the same soldier state")
	var second: Dictionary = run.call()
	checks.check(first.position.distance_to(second.position) < 1e-4 and is_equal_approx(first.energy, second.energy), "replaying from a saved state ends in the same place (%s, %s)" % [first.position, second.position])

	# Match state into a fresh match in its own world, then both step the same.
	game.rng.randi()
	var view := SubViewport.new()
	view.own_world_3d = true
	root.add_child(view)
	TestWorld.flat_ground(view)
	var other := Match.new(1)
	other.running = false
	view.add_child(other)
	var state := game.get_state()
	other.set_state(state)
	checks.check(other.get_state() == state, "a fresh match takes another's state whole, soldiers too")
	checks.check(other.rng.randi() == game.rng.randi() and other.rng.randi() == game.rng.randi(), "the match random numbers carry on the same")
	var copy_soldier: Soldier = other.entities[soldier.entity_id]
	var scripted := TestWorld.Scripted.new()
	scripted.command = input.command.duplicate()
	other.sources[soldier.entity_id] = scripted
	for i in 30:
		game.step(1.0 / 60.0)
		other.step(1.0 / 60.0)
	checks.check(copy_soldier.global_position.distance_to(soldier.global_position) < 1e-4, "the copy moves the same as the original from the same commands")
	checks.check(other.tick == game.tick, "both matches count the same ticks")
	checks.finish(self)
