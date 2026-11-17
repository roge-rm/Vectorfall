extends SceneTree

## Checks the capture the flag rules: taking the enemy flag, not your own,
## dropping it on death with the carrier's velocity, returning a dropped flag
## by touch and by timeout, capturing only while your flag is home, the
## capture limit, time up with a win and a draw, and flags round-tripping
## through get_state() and set_state() including one mid-tumble.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/flag_test.gd

var checks := TestWorld.Checks.new()
var game: Match
var input_a := TestWorld.Scripted.new()
var input_b := TestWorld.Scripted.new()
## Team 0's soldier and team 1's soldier.
var a: Soldier
var b: Soldier
var events: Array[String] = []

const STAND_0 := Vector3(-100.0, 0.0, 0.0)
const STAND_1 := Vector3(100.0, 0.0, 0.0)


func _initialize() -> void:
	TestWorld.flat_ground(root)
	game = Match.new(5)
	game.spawns[0] = [Transform3D(Basis.IDENTITY, STAND_0 + Vector3(10.0, 0.5, 20.0))]
	game.spawns[1] = [Transform3D(Basis.IDENTITY, STAND_1 + Vector3(-10.0, 0.5, 20.0))]
	game.add_flag(0, STAND_0, STAND_0 + Vector3.UP * 2.0)
	game.add_flag(1, STAND_1, STAND_1 + Vector3.UP * 2.0)
	root.add_child(game)
	a = game.add_soldier(0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, 40.0)), input_a)
	b = game.add_soldier(1, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, -40.0)), input_b)
	game.flag_taken.connect(func(team: int, id: int) -> void: events.append("taken %d %d" % [team, id]))
	game.flag_dropped.connect(func(team: int, id: int) -> void: events.append("dropped %d %d" % [team, id]))
	game.flag_returned.connect(func(team: int, id: int) -> void: events.append("returned %d %d" % [team, id]))
	game.flag_captured.connect(func(team: int, id: int) -> void: events.append("captured %d %d" % [team, id]))
	game.match_over.connect(func(team: int) -> void: events.append("over %d" % team))
	_run.call_deferred()


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


## Puts a soldier standing still at a point, alive.
func place(who: Soldier, at: Vector3, velocity := Vector3.ZERO) -> void:
	var state := who.get_state()
	state.position = at
	state.velocity = velocity
	state.grounded = velocity == Vector3.ZERO
	state.floor_normal = Vector3.UP
	state.health = who.tuning.health_max
	state.dead = false
	state.energy = who.tuning.energy_max
	who.set_state(state)


## Everything back to the start, with both soldiers far from the flags.
func reset() -> void:
	for flag in game.flags.values():
		flag.send_home()
	game.scores.assign([0, 0])
	game.over = false
	game.winner = -1
	game.settings = MatchSettings.new()
	game.start_clock()
	place(a, Vector3(0.0, 0.2, 40.0))
	place(b, Vector3(0.0, 0.2, -40.0))
	events.clear()


func _run() -> void:
	await ticks(20)
	var flag0 := game.flags[0]
	var flag1 := game.flags[1]
	var home1 := flag1.home

	# Pick up the enemy flag.
	place(a, STAND_1 + Vector3(0.0, 0.0, 1.0))
	await ticks(3)
	checks.check(flag1.mode == Flag.Mode.CARRIED and flag1.carrier_id == a.entity_id, "touching the enemy flag picks it up")
	checks.check(events.has("taken 1 %d" % a.entity_id), "taking it sends flag_taken with the flag's team and the carrier")
	place(a, STAND_1 + Vector3(-30.0, 0.0, 0.0))
	await ticks(3)
	checks.check(flag1.global_position.distance_to(a.global_position + Vector3.UP * 1.7) < 1.0, "the flag follows its carrier")

	# Your own flag at home can't be taken.
	reset()
	place(a, STAND_0 + Vector3(0.0, 0.0, 1.0))
	await ticks(5)
	checks.check(flag0.mode == Flag.Mode.HOME and events.is_empty(), "your own flag at home isn't picked up")

	# Dropped on death with the carrier's velocity.
	reset()
	place(a, Vector3(0.0, 30.0, 0.0), Vector3(20.0, 5.0, -10.0))
	flag1.global_position = a.global_position
	game._take_flag(flag1, a)
	await ticks(2)
	var speed_before := a.velocity
	game.damage(a, 1000.0, b.entity_id, Weapon.DISC, b.global_position)
	var drop_velocity := flag1.linear_velocity
	checks.check(flag1.mode == Flag.Mode.DROPPED and flag1.carrier_id == 0, "a carrier dying drops the flag")
	checks.check(events.has("dropped 1 %d" % a.entity_id), "dropping sends flag_dropped with the carrier")
	checks.check(drop_velocity.distance_to(speed_before) < 3.0, "it keeps the carrier's velocity (%s from %s)" % [drop_velocity, speed_before])
	var start_x := flag1.global_position.x
	await ticks(60)
	checks.check(flag1.global_position.x > start_x + 8.0, "it carries on moving the same way")
	await ticks(240)
	checks.check(flag1.sleeping or flag1.linear_velocity.length() < 0.5, "it tumbles to rest")
	checks.check(flag1.global_position.y < 3.0 and flag1.global_position.y > -0.5, "and lies on the ground (y %.2f)" % flag1.global_position.y)

	# Your team touching it returns it.
	var lying := flag1.global_position
	place(b, lying + Vector3(0.0, 0.0, 1.0))
	await ticks(3)
	checks.check(flag1.mode == Flag.Mode.HOME and flag1.global_position.distance_to(home1) < 0.1, "touching your dropped flag returns it to its stand")
	checks.check(events.has("returned 1 %d" % b.entity_id), "returning sends flag_returned with the soldier")

	# Back by itself after the timeout, never sooner.
	reset()
	game.respawn(a)
	place(a, Vector3(0.0, 0.2, 40.0))
	flag1.global_position = Vector3(0.0, 5.0, 0.0)
	game._take_flag(flag1, a)
	game.damage(a, 1000.0, b.entity_id, Weapon.DISC, b.global_position)
	await ticks(29 * 60)
	checks.check(flag1.mode == Flag.Mode.DROPPED, "a dropped flag is still there after 29 s")
	await ticks(2 * 60)
	checks.check(flag1.mode == Flag.Mode.HOME and events.has("returned 1 0"), "and goes home by itself after 30 s")

	# Capture only while your flag is home.
	reset()
	game._take_flag(flag1, a)
	place(a, STAND_0 + Vector3(0.0, 0.0, 1.0))
	flag0.global_position = Vector3(0.0, 3.0, 0.0)
	game._take_flag(flag0, b)
	await ticks(5)
	checks.check(game.scores[0] == 0 and flag1.mode == Flag.Mode.CARRIED, "no capture while your own flag is taken")
	game._drop_flag(flag0, b)
	await ticks(1)
	game.damage(b, 1000.0, a.entity_id, Weapon.DISC, a.global_position)
	flag0.send_home()
	await ticks(5)
	checks.check(game.scores[0] == 1 and flag1.mode == Flag.Mode.HOME, "touching your stand with your flag home scores and sends their flag home")
	checks.check(events.has("captured 0 %d" % a.entity_id), "a capture sends flag_captured with the team and carrier")

	# The capture limit ends the match.
	reset()
	game.settings.capture_limit = 2
	game.scores[0] = 1
	game._take_flag(flag1, a)
	place(a, STAND_0 + Vector3(0.0, 0.0, 1.0))
	await ticks(5)
	checks.check(game.over and game.winner == 0 and events.has("over 0"), "reaching the capture limit ends the match for that team")
	place(b, STAND_0 + Vector3(0.0, 0.0, -1.0))
	await ticks(5)
	checks.check(flag0.mode == Flag.Mode.HOME, "flags stop once it's over")

	# Time up: most captures wins, a tie is a draw.
	reset()
	game.settings.time_limit = 2.0
	game.start_clock()
	game.scores[1] = 1
	await ticks(130)
	checks.check(game.over and game.winner == 1 and events.has("over 1"), "time up with the most captures wins")
	reset()
	game.settings.time_limit = 2.0
	game.start_clock()
	game.scores.assign([2, 2])
	await ticks(130)
	checks.check(game.over and game.winner == -1 and events.has("over -1"), "time up with a tie is a draw")

	# State round trips, home, carried, and a dropped flag mid tumble.
	reset()
	place(a, Vector3(0.0, 30.0, 0.0), Vector3(15.0, 8.0, 3.0))
	game._take_flag(flag1, a)
	await ticks(10)
	game.damage(a, 1000.0, b.entity_id, Weapon.DISC, b.global_position)
	game.scores.assign([3, 1])
	game.time_left = 777.5
	await ticks(25)
	checks.check(flag1.mode == Flag.Mode.DROPPED and not flag1.sleeping, "the flag is mid tumble to save")
	var saved := game.get_state()
	await ticks(20)
	var later := game.get_state()
	game.set_state(saved)
	var back := game.get_state()
	checks.check(_same(saved.flags, back.flags) and back.scores[0] == 3 and back.scores[1] == 1 and is_equal_approx(back.time_left, saved.time_left), "set_state puts the flags, score and clock back as saved")
	await ticks(20)
	var again := game.get_state()
	checks.check(again.flags[1].position.distance_to(later.flags[1].position) < 0.5 and again.flags[1].mode == later.flags[1].mode, "a restored flag carries on as it did (%.3f m apart)" % again.flags[1].position.distance_to(later.flags[1].position))
	reset()
	game._take_flag(flag0, b)
	var carried := game.get_state()
	game._return_flag(flag0, 0)
	game.set_state(carried)
	checks.check(flag0.mode == Flag.Mode.CARRIED and flag0.carrier_id == b.entity_id, "a carried flag restores with its carrier")
	checks.finish(self)


func _same(x: Dictionary, y: Dictionary) -> bool:
	for team in x:
		for key in x[team]:
			var p = x[team][key]
			var q = y[team][key]
			if p is Vector3 or p is Quaternion:
				if not p.is_equal_approx(q):
					return false
			elif p is float:
				if not is_equal_approx(p, q):
					return false
			elif p != q:
				return false
	return true
