extends SceneTree

## Checks the team commander: its role counts for each situation, reading a
## person's role from how they move, holding roles for a while before moving
## bots, learning lanes from carriers, and, on Ochre Fold with a scripted
## stand-in player, that bots escort a person who takes the enemy flag, that
## fewer bots defend while a person sits at home and that one warns and covers
## it, that bots go after the
## carrier of our flag and split up to cut it off, and that the commander's
## state saves and loads whole.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/commander_test.gd

const R := BotBrain.Role

var checks := TestWorld.Checks.new()
var map: GameMap


## A person's stand-in: sits still, or walks straight at a spot, looking
## where it goes. It never fires.
class StandIn:
	extends CommandSource
	var soldier: Soldier
	var walk_to := Vector3.INF

	func make_command(_delta: float) -> PlayerCommand:
		var command := PlayerCommand.new()
		command.yaw = yaw
		if soldier != null and walk_to != Vector3.INF:
			var to := walk_to - soldier.global_position
			if Vector2(to.x, to.z).length() > 0.5:
				yaw = atan2(-to.x, -to.z)
				command.yaw = yaw
				command.move = Vector2(0.0, 1.0)
		return command


func _initialize() -> void:
	_run.call_deferred()


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	_plan_counts()
	_read_person()
	map = OchreFold.new()
	root.add_child(map)
	await _holds_roles()
	await _learns_lanes()
	await _escorts_person()
	await _person_defends()
	await _chases_carrier()
	await _state_round_trip()
	checks.finish(self)


func _counts(c: Dictionary) -> Array:
	return [c[R.OFFENCE], c[R.DEFENCE], c[R.MIDFIELD], c[R.ESCORT], c[R.LIGHT_DEFENCE], c[R.CHASE]]


## Counts as [offence, defence, midfield, escort, light defence, chase].
func _plan_counts() -> void:
	var plan := TeamCommander.plan_counts
	checks.check(_counts(plan.call(8, {})) == [6, 1, 0, 0, 1, 0], "8 even: 6 offence, 1 defence, 1 light defence")
	checks.check(_counts(plan.call(8, { "diff": 1 })) == [4, 1, 1, 0, 2, 0], "ahead by one: a light defence and a midfield from the offence")
	checks.check(_counts(plan.call(8, { "diff": 2 })) == [3, 2, 1, 0, 2, 0], "ahead by two: a second defence too")
	checks.check(_counts(plan.call(8, { "diff": -1, "late": true })) == [7, 1, 0, 0, 0, 0], "behind late: all but one go on offence")
	checks.check(_counts(plan.call(8, { "threat": true })) == [5, 1, 0, 0, 2, 0], "enemies near our flag: one more light defence")
	checks.check(_counts(plan.call(8, { "own_taken": true })) == [0, 1, 0, 0, 0, 7], "our flag taken: all but one chase")
	checks.check(_counts(plan.call(8, { "own_taken": true, "committed": 3 })) == [3, 1, 0, 0, 0, 4], "our flag taken with 3 offence close to theirs: they keep attacking, 4 chase")
	checks.check(_counts(plan.call(8, { "own_taken": true, "we_carry": true })) == [1, 1, 0, 1, 0, 5], "both flags out: the carrier, one escort and one at home, the rest chase")
	checks.check(_counts(plan.call(8, { "we_carry": true })) == [3, 1, 0, 3, 1, 0], "we carry theirs: three escorts from the offence")
	checks.check(_counts(plan.call(8, { "runner": true })) == [5, 1, 0, 1, 1, 0], "a person runs for their flag: one escort")
	var small := plan.call(3, {}) as Dictionary
	checks.check(_counts(small) == [2, 1, 0, 0, 0, 0], "a team of 3: 2 offence and 1 defence")


func _read_person() -> void:
	var home := Vector3(-560.0, 46.0, 0.0)
	var away := Vector3(560.0, 46.0, 0.0)
	var at_home := [[0, home + Vector3(20.0, 0.0, 10.0)], [150, home + Vector3(25.0, 0.0, 12.0)], [240, home + Vector3(22.0, 0.0, 8.0)]]
	var going := [[0, Vector3(-300.0, 20.0, 0.0)], [180, Vector3(-240.0, 20.0, 0.0)]]
	var sitting := [[0, Vector3(-100.0, 20.0, 0.0)], [180, Vector3(-101.0, 20.0, 0.0)]]
	var read := TeamCommander.read_person
	checks.check(read.call(at_home, false, home, away, null) == R.DEFENCE, "a person staying by their flag reads as defence")
	checks.check(read.call(going, false, home, away, null) == R.OFFENCE, "a person heading for the enemy flag reads as offence")
	checks.check(read.call(sitting, false, home, away, null) == R.MIDFIELD, "a person holding the middle reads as midfield")
	checks.check(read.call(sitting, true, home, away, null) == R.OFFENCE, "a person carrying the flag reads as offence at once")
	checks.check(read.call(going, false, home, away, Vector3(-200.0, 20.0, 0.0)) == R.CHASE, "a person closing on our flag's carrier reads as chase")
	checks.check(read.call([[0, home]], false, home, away, null) == -1, "one sample is too few to read")


## A match on Ochre Fold with bots on each team, and a stand-in for the
## person on team 0 if person_at is set.
func _match(team0: int, team1: int, match_seed := 3) -> Dictionary:
	var holder := Node3D.new()
	root.add_child(holder)
	var game := Match.new(match_seed)
	game.terrain = map.terrain
	for team in 2:
		game.spawns[team] = map.spawn_points(team)
		game.add_flag(team, map.stand_point(team), map.flag_rest(team))
	holder.add_child(game)
	var director := BotDirector.new(game, map.route_graph)
	for k in team0:
		director.add_bot(0, map.spawn_point(0, k))
	for k in team1:
		director.add_bot(1, map.spawn_point(1, k))
	return { "holder": holder, "game": game, "director": director }


func _add_stand_in(setup: Dictionary, team: int, at: Vector3) -> StandIn:
	var stand_in := StandIn.new()
	var game: Match = setup.game
	stand_in.soldier = game.add_soldier(team, Transform3D(Basis.IDENTITY, at), stand_in)
	stand_in.soldier.display_name = "Stand-in"
	stand_in.soldier.health = 100000.0
	setup.director.assign_roles()
	return stand_in


func _done(setup: Dictionary) -> void:
	setup.holder.free()
	await ticks(2)


func _role_count(director: BotDirector, team: int, roles: Array) -> int:
	var n := 0
	for brain in director.brains:
		if brain.soldier.team == team and roles.has(brain.role):
			n += 1
	return n


## Bots stay in a role at least MIN_ROLE_TIME before the commander moves them
## for a change in the score.
func _holds_roles() -> void:
	var setup := _match(8, 0)
	var game: Match = setup.game
	var director: BotDirector = setup.director
	var boss := director.commander(0)
	await ticks(2)
	game.scores[0] = 1
	boss.think()
	var early := _role_count(director, 0, [R.LIGHT_DEFENCE])
	for id: int in boss.role_since:
		boss.role_since[id] -= int(TeamCommander.MIN_ROLE_TIME * 60.0) + 1
	boss.think()
	var later := _role_count(director, 0, [R.LIGHT_DEFENCE])
	checks.check(early == 1 and later == 2, "ahead, a second light defence waits until the roles have been held long enough (%d then %d)" % [early, later])
	await _done(setup)


## Captures and deaths in lanes change the carriers' route costs, and enemy
## carriers' lanes order the chase.
func _learns_lanes() -> void:
	var setup := _match(2, 2)
	var director: BotDirector = setup.director
	var game: Match = setup.game
	var boss := director.commander(0)
	await ticks(2)
	var lanes := boss.lanes
	checks.check(lanes != null and lanes.count == 3, "Ochre Fold has three lanes (%s)" % str(lanes.middles if lanes != null else []))
	# Our carrier died in the north lane, another scored by the south.
	boss.carrier_lanes[101] = [0]
	boss._on_flag_dropped(1, 101)
	boss.carrier_lanes[102] = [2]
	boss._on_flag_captured(0, 102)
	var costs := boss.carry_costs()
	var north: RouteGraph.Link = lanes.lane_links[0][0]
	var south: RouteGraph.Link = lanes.lane_links[2][0]
	checks.check(costs.get(north, 0.0) > 0.0 and not costs.has(south), "a carrier's route costs more through the lane where one died than the one that scored")
	# Enemy carriers have gone home by the south lane before.
	boss.escape_lanes[2] += 10.0
	var flag: Flag = game.flags[0]
	var thief := game.soldier(director.commander(1).brains()[0].soldier.entity_id)
	thief.global_position = Vector3(0.0, map.surface_at(0.0, 0.0) + 1.0, 0.0)
	flag.mode = Flag.Mode.CARRIED
	flag.carrier_id = thief.entity_id
	flag.global_position = thief.global_position
	boss._plan_chase()
	checks.check(not boss.escape_order.is_empty() and boss.escape_order[0] == 2, "the chase expects the lane enemy carriers used before (%s)" % str(boss.escape_order))
	var far := Vector3(-300.0, 20.0, 0.0)
	# On its way home.
	thief.velocity = Vector3(20.0, 0.0, 0.0)
	var cut1: Array = boss.chase_point(1, far)
	var cut2: Array = boss.chase_point(2, far)
	var trail: Array = boss.chase_point(0, far)
	checks.check(cut1[1] and cut2[1] and not trail[1] and cut1[0].distance_to(cut2[0]) > 50.0, "chasers split: one trails and two cut off different lanes")
	# Home and waiting for its own flag: everyone goes for it.
	var home: Vector3 = game.stands[1]
	thief.global_position = home + Vector3(60.0, 1.0, 30.0)
	flag.global_position = thief.global_position
	thief.velocity = Vector3.ZERO
	checks.check(not boss.chase_point(1, far)[1] and not boss.chase_point(2, far)[1], "a carrier waiting at home has every chaser go for it")
	await _done(setup)


## A stand-in on team 0 takes the enemy flag: bots are given to escort it.
func _escorts_person() -> void:
	var setup := _match(7, 4)
	var game: Match = setup.game
	var director: BotDirector = setup.director
	var stand: Vector3 = game.stands[1]
	var stand_in := _add_stand_in(setup, 0, stand + Vector3(0.0, 1.0, 8.0))
	stand_in.walk_to = game.flags[1].global_position
	var grabbed := -1
	var escorts := 0
	var heading := 0
	for i in 60 * 10:
		await physics_frame
		if grabbed < 0 and game.flags[1].mode == Flag.Mode.CARRIED and game.flags[1].carrier_id == stand_in.soldier.entity_id:
			grabbed = i
			stand_in.walk_to = game.stands[0]
		if grabbed >= 0 and i - grabbed >= 60 * 3:
			for brain in director.brains:
				if brain.soldier.team == 0 and brain.role == R.ESCORT and brain.role_target == stand_in.soldier.entity_id:
					escorts += 1
					if brain.goal == BotBrain.Goal.ESCORT:
						heading += 1
			break
	checks.check(grabbed >= 0, "the stand-in takes the enemy flag")
	checks.check(escorts >= 3 and heading >= 3, "within 3 s, 3 or more bots escort it (%d, %d on their way)" % [escorts, heading])
	await _done(setup)


## Bot defenders with a stand-in sitting at home against 8 bots alone.
func _person_defends() -> void:
	var alone := _match(8, 0)
	await ticks(60 * 12)
	var without := _role_count(alone.director, 0, [R.DEFENCE, R.LIGHT_DEFENCE])
	await _done(alone)
	var setup := _match(7, 0)
	var game: Match = setup.game
	var stand_in := _add_stand_in(setup, 0, map.spawn_point(0, 7).origin)
	await ticks(60 * 12)
	var boss: TeamCommander = setup.director.commander(0)
	var read: int = boss.people[stand_in.soldier.entity_id].role
	var with := _role_count(setup.director, 0, [R.DEFENCE, R.LIGHT_DEFENCE])
	checks.check(read == R.DEFENCE, "a stand-in sitting at home reads as defence (%s)" % BotBrain.ROLE_NAMES[read])
	checks.check(with < without, "and fewer bots defend: %d with it, %d without" % [with, without])
	# An enemy the team knows of comes up behind it.
	var me := stand_in.soldier
	var behind := me.global_position + Vector3(sin(me.yaw), 0.0, cos(me.yaw)) * 25.0
	var warnings := []
	boss.warned.connect(func(_team: int, person: int, enemy: int) -> void: warnings.append([person, enemy]))
	boss.known[999] = { "position": behind, "velocity": Vector3.ZERO, "tick": game.tick, "approach": -1 }
	var enemy := Soldier.new()
	enemy.team = 1
	game.entities[999] = enemy
	boss._help_people()
	game.entities.erase(999)
	enemy.free()
	checks.check(warnings == [[me.entity_id, 999]], "an enemy the team knows of behind it sends it a warning")
	checks.check(boss.covers.values().has(me.entity_id), "and a bot nearby covers it")
	await _done(setup)


## An enemy stand-in takes our flag: the commander moves bots to chase.
func _chases_carrier() -> void:
	var setup := _match(8, 0)
	var game: Match = setup.game
	var director: BotDirector = setup.director
	await ticks(60 * 2)
	var thief := _add_stand_in(setup, 1, game.flags[0].global_position + Vector3(0.0, 0.5, 3.0))
	thief.walk_to = game.flags[0].global_position
	var grabbed := -1
	var chasing := 0
	for i in 60 * 6:
		await physics_frame
		if grabbed < 0 and game.flags[0].mode == Flag.Mode.CARRIED:
			grabbed = i
			thief.walk_to = game.stands[1]
		if grabbed >= 0 and i - grabbed >= 60:
			chasing = _role_count(director, 0, [R.CHASE])
			break
	var defence := _role_count(director, 0, [R.DEFENCE])
	checks.check(grabbed >= 0 and chasing >= 6, "within 1 s of our flag being taken, %d bots chase" % chasing)
	checks.check(defence == 1, "and one stays home on defence")
	await _done(setup)


## The director's state, commanders too, saves and loads whole.
func _state_round_trip() -> void:
	var setup := _match(4, 4)
	var director: BotDirector = setup.director
	await ticks(60 * 3)
	var saved := director.get_state()
	director.commander(0).attack_lanes[0] += 5.0
	director.set_state(saved)
	checks.check(director.get_state() == saved, "the director's state with its commanders saves and loads whole")
	await _done(setup)
