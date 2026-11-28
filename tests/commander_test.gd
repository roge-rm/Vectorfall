extends SceneTree

## Checks the team commander: its role counts for each situation, reading a
## person's role from how they move, holding roles for a while before moving
## bots, learning lanes from carriers, and, on Ochre Fold with a scripted
## stand-in player, that bots escort a person who takes the enemy flag, that
## fewer bots defend while a person sits at home and that one warns and covers
## it, that bots go after the
## carrier of our flag and split up to cut it off, that roles get their
## loadouts and a bot whose role changes near a station goes and changes,
## that it sends a raid on the enemy base and a repair bot to our generator
## when it's down, that the orders to attack the generator and repair the
## base send bots to do it, and that the commander's state saves and loads
## whole.
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
	await _escorts_bot_runner()
	await _large_flag_push()
	await _escorts_person()
	await _person_defends()
	await _chases_carrier()
	_loadout_table()
	await _roles_wear_loadouts()
	await _deploys_on_ochre_fold()
	await _changes_at_station()
	await _sends_raid()
	await _raid_through_opening()
	await _repairs_generator()
	await _base_orders()
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
	checks.check(_counts(plan.call(8, { "own_taken": true })) == [0, 1, 4, 0, 0, 3], "our flag taken: three chase and midfield covers the lanes")
	checks.check(_counts(plan.call(8, { "own_taken": true, "committed": 3 })) == [3, 1, 1, 0, 0, 3], "our flag taken with 3 offence close to theirs: they keep attacking and three chase")
	checks.check(_counts(plan.call(8, { "own_taken": true, "we_carry": true })) == [1, 1, 2, 1, 0, 3], "both flags out: the carrier, one escort and one at home, three chase and two screen midfield")
	checks.check(_counts(plan.call(8, { "we_carry": true })) == [3, 1, 0, 3, 1, 0], "we carry theirs: three escorts from the offence")
	checks.check(_counts(plan.call(8, { "runner": true })) == [5, 1, 0, 1, 1, 0], "a person runs for their flag: one escort")
	checks.check(_counts(plan.call(16, {})) == [10, 2, 2, 0, 2, 0], "16 even: two defenders, two midfield, two light defence and ten offence")
	checks.check(_counts(plan.call(16, { "own_taken": true })) == [0, 2, 9, 0, 0, 5], "16 with our flag taken: a chase squad and midfield cover")
	checks.check(_counts(plan.call(16, { "own_taken": true, "we_carry": true })) == [1, 2, 5, 3, 0, 5], "16 with both flags taken: three escorts and a chase squad")
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
func _match(team0: int, team1: int, match_seed := 3, base_power := false) -> Dictionary:
	var holder := Node3D.new()
	root.add_child(holder)
	var game := Match.new(match_seed)
	game.terrain = map.terrain
	for team in 2:
		game.spawns[team] = map.spawn_points(team)
		game.add_flag(team, map.stand_point(team), map.flag_rest(team))
		if base_power:
			for at in map.station_points(team):
				game.add_station(team, at)
			map.add_base_power(game, team)
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


## The foot runner stages with escorts while a separate squad raids the base.
func _escorts_bot_runner() -> void:
	var setup := _match(8, 0, 3, true)
	var game: Match = setup.game
	var director: BotDirector = setup.director
	var boss := director.commander(0)
	var reserved: BotBrain
	var delivered: BotBrain
	for brain in boss.brains():
		if brain.is_flag_runner():
			reserved = brain
		elif brain.role == R.OFFENCE:
			delivered = brain
	checks.check(reserved != null and delivered != null, "the opening has infantry for vehicle jobs and a flag run")
	if reserved == null or delivered == null:
		await _done(setup)
		return
	var reserved_id := reserved.soldier.entity_id
	var delivered_id := delivered.soldier.entity_id
	director.vehicle_orders.jobs[reserved_id] = {}
	director.vehicle_orders.delivered[delivered_id] = {}
	boss.think(true)
	checks.check(not reserved.is_flag_runner() and not delivered.is_flag_runner(), "ordinary runner selection leaves vehicle work in place")
	await ticks(TeamCommander.PUSH_FIRST + 2)
	var runner := director.brain_of(boss.push_runner)
	var escorts: Array[BotBrain] = []
	for brain in boss.brains():
		if brain.role == R.ESCORT and brain.role_target == boss.push_runner:
			escorts.append(brain)
	checks.check(runner != null and runner.is_flag_runner() and escorts.size() == 2 and _role_count(director, 0, [R.DEFENCE]) == 1, "eight bots plan a foot runner with two escorts and a defender")
	checks.check(reserved.role == R.OFFENCE and delivered.role == R.OFFENCE and not escorts.has(reserved) and not escorts.has(delivered), "the early push leaves pending crew and delivered ferry support in place")
	if runner == null or escorts.is_empty():
		await _done(setup)
		return
	var escort := escorts[0]
	runner.soldier.global_position = boss.push_point + Vector3.UP
	boss.think(true)
	var approach_goal := runner._role_goal()
	checks.check(not boss.push_launched and boss.push_deadline <= game.tick + TeamCommander.PUSH_WAIT and approach_goal == [BotBrain.Goal.RALLY, boss.push_point] and escort._role_goal()[1].distance_to(game.stands[1]) < TeamCommander.PUSH_SCREEN_RANGE, "runner waits at the approach while the escort moves up")
	escort.soldier.global_position = escort._role_goal()[1]
	boss.think(true)
	var escort_goal := escort._role_goal()
	checks.check(boss.push_launched and runner._role_goal()[0] == BotBrain.Goal.TAKE_FLAG and escort_goal[0] == BotBrain.Goal.ESCORT and escort_goal[1].distance_to(game.stands[1]) < 20.0, "arrival of an escort sends both ahead to the flag stand")
	# Another bot takes the flag between commander ticks.
	var enemy_flag: Flag = game.flags[1]
	enemy_flag.mode = Flag.Mode.CARRIED
	enemy_flag.carrier_id = delivered.soldier.entity_id
	checks.check(escort._role_goal() == [BotBrain.Goal.ESCORT, escort._escort_spot(delivered.soldier)], "a staged escort follows the actual carrier before the next commander tick")
	enemy_flag.mode = Flag.Mode.HOME
	enemy_flag.carrier_id = 0
	var reserved_at := reserved.soldier.global_position
	var delivered_at := delivered.soldier.global_position
	var generator := game.generator(1)
	reserved.soldier.global_position = generator.global_position + Vector3.UP
	delivered.soldier.global_position = generator.global_position + Vector3(1.0, 1.0, 0.0)
	boss.next_raid = game.tick
	boss.think(true)
	checks.check(not boss.raiders.is_empty() and not boss.raiders.has(runner.soldier.entity_id) and not boss.raiders.has(escort.soldier.entity_id) and boss.raid_target == generator.entity_id, "separate infantry head for the generator during the push")
	checks.check(not boss.raiders.has(reserved_id) and not boss.raiders.has(delivered_id), "the automatic raid leaves both vehicle assignments in place")
	director.vehicle_orders.jobs.erase(reserved_id)
	director.vehicle_orders.delivered.erase(delivered_id)
	reserved.soldier.global_position = reserved_at
	delivered.soldier.global_position = delivered_at
	escort.soldier.global_position = map.spawn_point(0, 0).origin
	boss.push_launched = false
	boss.push_deadline = game.tick
	boss.think(true)
	checks.check(boss.push_launched, "the runner goes ahead after the wait expires")
	var runner_id := runner.soldier.entity_id
	for brain in boss.brains():
		if brain != runner:
			brain.soldier.dead = true
	boss.think(true)
	checks.check(boss.push_runner == 0 and runner.is_flag_runner(), "the last living runner stays on offence")
	for brain in boss.brains():
		brain.soldier.dead = false
	boss.think(true)
	game.waypoints[runner_id] = {"by": 0, "at": boss.push_point, "until": game.tick + Match.WAYPOINT_TICKS}
	boss.think(true)
	checks.check(boss.push_runner != runner_id and runner._choose_goal()[0] == BotBrain.Goal.WAYPOINT, "a team waypoint takes priority over the automatic flag run")
	await _done(setup)


func _large_flag_push() -> void:
	var setup := _match(16, 0, 3, true)
	var game: Match = setup.game
	var director: BotDirector = setup.director
	var boss := director.commander(0)
	game.tick = TeamCommander.PUSH_FIRST + 1
	boss.think(true)
	var runner := director.brain_of(boss.push_runner)
	var escorts: Array[BotBrain] = []
	for brain in boss.brains():
		if brain.role == R.ESCORT and brain.role_target == boss.push_runner:
			escorts.append(brain)
	checks.check(runner != null and escorts.size() == 3, "sixteen bots send a runner and three escorts")
	if runner != null and escorts.size() == 3:
		runner.soldier.global_position = boss.push_point + Vector3.UP
		boss.think(true)
		var stand: Vector3 = game.stands[1]
		var escort := escorts[0]
		var cover: Vector3 = escort._role_goal()[1]
		var second: Vector3 = escorts[1]._role_goal()[1]
		checks.check(boss.push_screening and not boss.push_launched and cover.distance_to(stand) < TeamCommander.PUSH_SCREEN_RANGE
			and cover.distance_to(second) >= 11.0, "the escorts spread out ahead of a large team's staged runner")
		escort.soldier.global_position = cover
		boss.think(true)
		checks.check(not boss.push_launched, "one escort does not send in the large team's runner")
		escorts[1].soldier.global_position = second
		boss.think(true)
		checks.check(boss.push_launched and runner._role_goal()[0] == BotBrain.Goal.TAKE_FLAG,
			"cover near the stand launches the large team's runner")
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
	var stand_in := _add_stand_in(setup, 0, Vector3(map.base_x(0) + 8.0, map.deck_height() + 0.3, 8.0))
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
	# After 12 s the nearest bot is about COVER_RANGE away, give or take its
	# route, so one is put 40 m off to have a bot in range.
	var near: BotBrain = setup.director.brains[0]
	near.soldier.global_position = me.global_position + Vector3(0.0, 0.0, 40.0)
	var enemy := Soldier.new()
	enemy.team = 1
	game.entities[999] = enemy
	boss._help_people()
	game.entities.erase(999)
	enemy.free()
	checks.check(warnings == [[me.entity_id, 999]], "an enemy the team knows of behind it sends it a warning")
	checks.check(boss.covers.get(near.soldier.entity_id, 0) == me.entity_id, "and a bot nearby covers it")
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
	checks.check(grabbed >= 0 and chasing == 3, "within 1 s of our flag being taken, %d bots chase" % chasing)
	checks.check(defence == 1, "and one stays home on defence")
	var boss := director.commander(0)
	var jammer := BotLoadouts.loadout(BotLoadouts.Kit.RUNNER_JAMMER)
	thief.soldier.set_loadout(jammer)
	thief.soldier.pack_on = true
	boss.known.erase(thief.soldier.entity_id)
	checks.check(not boss.enemy_flag_carrier_position().is_finite() and boss.vehicle_carrier() == null, "a jammer hides the carrier from unseen chasers")
	boss.known[thief.soldier.entity_id] = {"tick": game.tick, "position": thief.soldier.at(), "velocity": Vector3.ZERO}
	checks.check(boss.enemy_flag_carrier_position().is_equal_approx(thief.soldier.at()), "a sighting gives the chasers a position for the jammed carrier")
	await _done(setup)


## The director's state, commanders too, saves and loads whole.
## The role to loadout table: armour and the pack or weapon each role is for.
func _loadout_table() -> void:
	var P := BotBrain.Personality
	var A := SoldierBody.Armour
	var ok := true
	for personality in BotBrain.PERSONALITY_NAMES.size():
		for kit in BotLoadouts.choices(R.DEFENCE, personality):
			ok = ok and BotLoadouts.loadout(kit).armour == A.HEAVY and BotLoadouts.loadout(kit).weapons.has(Weapon.MORTAR)
		for role: int in [R.LIGHT_DEFENCE, R.CHASE]:
			for kit in BotLoadouts.choices(role, personality):
				ok = ok and BotLoadouts.loadout(kit).armour == A.LIGHT
		for kit in BotLoadouts.choices(R.ESCORT, personality):
			ok = ok and BotLoadouts.loadout(kit).armour == A.MEDIUM
	checks.check(ok, "defence is heavy with a mortar, light defence and chase light, escorts medium")
	var sniper := BotLoadouts.loadout(BotLoadouts.choices(R.MIDFIELD, P.SNIPER)[0])
	checks.check(sniper.weapons.has(Weapon.SNIPER) and sniper.pack == Pack.JAMMER, "a sniper in midfield carries the sniper rifle and a jammer")
	var runner := BotLoadouts.loadout(BotLoadouts.choices(R.OFFENCE, P.AGGRESSIVE)[0])
	checks.check(runner.armour == A.LIGHT and runner.pack == Pack.ENERGY, "an aggressive runner is light with an energy pack")
	var repair := BotLoadouts.loadout(BotLoadouts.choices(R.REPAIR, P.DEFAULT)[0])
	checks.check(repair.pack == Pack.REPAIR and repair.armour == A.MEDIUM, "repair is medium with the repair pack")


## Every bot starts in a loadout its role and personality choose, and sends
## a new role's loadout for its respawn within a think.
func _roles_wear_loadouts() -> void:
	var setup := _match(8, 8)
	var director: BotDirector = setup.director
	var ok := true
	var heavy := 0
	var engineers := 0
	for brain in director.brains:
		var worn := brain.soldier.loadout
		var kit: int = brain.kit_picks.get(brain.role, -1)
		ok = ok and BotLoadouts.choices(brain.role, brain.personality, true).has(kit) and worn.equals(brain.wanted_loadout())
		if (brain.role == R.DEFENCE and worn.pack == Pack.TURRET) or (brain.role == R.LIGHT_DEFENCE and worn.pack == Pack.SENSOR):
			engineers += 1
		if brain.role == R.DEFENCE and worn.armour == SoldierBody.Armour.HEAVY:
			heavy += 1
	checks.check(ok and heavy == 2, "every bot starts in a loadout for its role, both defences heavy (%d)" % heavy)
	checks.check(engineers == 4, "each team starts with a turret and sensor pack (%d)" % engineers)
	var brain: BotBrain = null
	for other in director.brains:
		if other.soldier.team == 0 and other.role == R.OFFENCE:
			brain = other
			break
	director.commander(0)._lock(brain, R.LIGHT_DEFENCE, 0, -1, 0, 0)
	await ticks(BotDirector.THINK_TICKS + 2)
	var next := brain.soldier.next_loadout
	checks.check(next.armour == SoldierBody.Armour.LIGHT and next.equals(brain.wanted_loadout()), "a bot moved to light defence sends its loadout for the next respawn (%s)" % BotLoadouts.describe(next, false))
	await _done(setup)


func _deploys_on_ochre_fold() -> void:
	var setup := _match(8, 8, 3, true)
	var game: Match = setup.game
	game.prepare_terrain()
	var deployed := [0, 0]
	for i in 45 * 60:
		await physics_frame
		deployed[0] = game.deploy_count(0, BaseAsset.Kind.TURRET) + game.deploy_count(0, BaseAsset.Kind.SENSOR)
		deployed[1] = game.deploy_count(1, BaseAsset.Kind.TURRET) + game.deploy_count(1, BaseAsset.Kind.SENSOR)
		if deployed[0] > 0 and deployed[1] > 0:
			break
	checks.check(deployed[0] > 0 and deployed[1] > 0, "defensive bots deploy on Ochre Fold (%s)" % str(deployed))
	await _done(setup)


## A bot moved to defence beside its base's station walks onto the pad and
## comes off it heavy.
func _changes_at_station() -> void:
	var setup := _match(1, 0)
	var game: Match = setup.game
	var director: BotDirector = setup.director
	for team in 2:
		for at in map.station_points(team):
			game.add_station(team, at)
	var brain: BotBrain = director.brains[0]
	brain.soldier.set_loadout(Loadout.standard())
	var start := Vector3(map.base_x(0) + map.front(0) * 8.0, 0.0, -12.0)
	start.y = map.surface_at(start.x, start.z) + 0.2
	brain.soldier.global_position = start
	brain.soldier.velocity = Vector3.ZERO
	director.commander(0)._lock(brain, R.DEFENCE, 0, -1, 0, 0)
	var went := false
	for i in 60 * 20:
		await physics_frame
		went = went or brain.goal == BotBrain.Goal.STATION
		if brain.soldier.loadout.armour == SoldierBody.Armour.HEAVY:
			break
	checks.check(went and brain.soldier.loadout.equals(brain.wanted_loadout()), "a bot moved to defence by its base goes to a station and changes to %s" % BotLoadouts.describe(brain.soldier.loadout, false))
	await _done(setup)


## A raid goes for their generator with two offence bots, who head for the
## perches beside its room's openings; with it destroyed, for their turrets.
func _sends_raid() -> void:
	var setup := _match(8, 8, 3, true)
	var game: Match = setup.game
	var director: BotDirector = setup.director
	var boss := director.commander(0)
	await ticks(60)
	var flag_turret := boss._flag_turret()
	var aimed := 0
	var runner: BotBrain
	for brain in director.brains:
		if brain.soldier.team != 0 or brain.role != R.OFFENCE:
			continue
		if brain.is_flag_runner():
			runner = brain
		elif brain.role_target == flag_turret:
			aimed += 1
	var aims_for_flag := false
	if runner != null:
		var was_attacking := runner.attacking
		runner.attacking = true
		aims_for_flag = runner._role_goal()[0] == BotBrain.Goal.TAKE_FLAG
		runner.attacking = was_attacking
	checks.check(aims_for_flag and flag_turret != 0 and game.asset(flag_turret).guard_points.is_empty() and aimed == _role_count(director, 0, [R.OFFENCE]) - 1 and aimed > 0, "one flag runner and %d offence bots targeting its turret" % aimed)
	boss.next_raid = game.tick
	boss.think(true)
	var target := game.asset(boss.raid_target)
	var raiding := _role_count(director, 0, [R.GENERATOR])
	checks.check(boss.raiders.size() == 2 and raiding == 2 and target != null and target == game.generator(1), "a raid goes for their generator (%d raiders, target %s)" % [raiding, BaseAsset.NAMES[target.kind] if target != null else "none"])
	await ticks(60)
	var info := director.asset_info(boss.raid_target)
	var perched := 0
	for brain in director.brains:
		if brain.role == R.GENERATOR and brain.role_target == boss.raid_target and brain.goal == BotBrain.Goal.RAID:
			for at: Vector3 in info.perches:
				if brain.goal_target.distance_to(at) < 0.5:
					perched += 1
	checks.check(info.perches.size() == 2 and info.lobs.size() == 2 and perched == 2, "and the raiders head for a perch beside an opening (%d)" % perched)
	boss._end_raid()
	game.damage_asset(game.generator(1), 1000.0, 0, 0, Vector3.ZERO)
	target = game.asset(boss._raid_target())
	checks.check(target != null and target.kind == BaseAsset.Kind.TURRET, "with it destroyed, a raid would go for a turret")
	await _done(setup)


## Ordered to attack the generator, two heavies near their base destroy it
## from the deck, shooting down through its room's openings with the fields
## on.
func _raid_through_opening() -> void:
	var setup := _match(3, 0, 3, true)
	var game: Match = setup.game
	var director: BotDirector = setup.director
	var boss := director.commander(0)
	await ticks(2)
	var near := map.stand_point(1) + Vector3(map.front(1) * 10.0, 0.5, 0.0)
	var person := _add_stand_in(setup, 0, map.spawn_point(0, 6).origin + Vector3.UP)
	boss._on_ordered(person.soldier.entity_id, Orders.Kind.ATTACK_GENERATOR, 0)
	var generator := game.generator(1)
	for brain in director.brains:
		if boss.raiders.has(brain.soldier.entity_id):
			brain.soldier.set_loadout(BotLoadouts.loadout(BotLoadouts.Kit.HEAVY_SHIELD))
			brain.soldier.tuning.health_max = 100000.0
			brain.soldier.health = 100000.0
			var state := brain.soldier.get_state()
			state.position = near
			state.velocity = Vector3.ZERO
			brain.soldier.set_state(state)
	var seconds := -1.0
	for i in 60 * 90:
		await physics_frame
		if generator.destroyed:
			seconds = i / 60.0
			break
	var on := game.fields.values().filter(func(f: ForceField) -> bool: return f.team == 1).size()
	checks.check(boss.raiders.size() == 2 and generator.destroyed, "two heavies ordered on a raid destroy their generator through its openings in %.1f s (%d fields)" % [seconds, on])
	await _done(setup)


## Our generator destroyed, the bot carrying a repair pack goes and repairs
## it, and power comes back.
func _repairs_generator() -> void:
	var setup := _match(3, 0, 3, true)
	var game: Match = setup.game
	var director: BotDirector = setup.director
	var boss := director.commander(0)
	var fixer: BotBrain = director.brains[1]
	fixer.soldier.set_loadout(BotLoadouts.loadout(BotLoadouts.Kit.MEDIUM_REPAIR))
	await ticks(2)
	var own := game.generator(0)
	game.damage_asset(own, 10000.0, 0, 1, own.centre())
	boss.think(true)
	checks.check(boss.repairers.has(fixer.soldier.entity_id) and fixer.role == R.REPAIR and fixer.role_target == own.entity_id, "with our generator down, the bot with a repair pack is sent to repair it")
	var seconds := -1.0
	for i in 60 * 150:
		await physics_frame
		if not own.destroyed:
			seconds = i / 60.0
			break
	checks.check(not own.destroyed and game.powered(0), "and it repairs it and power comes back in %.1f s" % seconds)
	await ticks(60)
	checks.check(boss.repairers.is_empty(), "and its repair is over")
	checks.check(_said(boss, BotLines.Line.GENERATOR_DOWN) and _said(boss, BotLines.Line.GENERATOR_BACK), "a bot says our generator's down, and back up")
	await _done(setup)


func _said(boss: TeamCommander, line: int) -> bool:
	for said: Dictionary in boss.chat:
		if said.line == line:
			return true
	return false


## "Attack the generator" sends two bots on a raid and "Repair the base" one
## to our base assets, each answering.
func _base_orders() -> void:
	var setup := _match(6, 6, 3, true)
	var game: Match = setup.game
	var director: BotDirector = setup.director
	var boss := director.commander(0)
	await ticks(30)
	var person := _add_stand_in(setup, 0, map.spawn_point(0, 7).origin + Vector3.UP)
	boss._on_ordered(person.soldier.entity_id, Orders.Kind.ATTACK_GENERATOR, 0)
	var raiders := 0
	for brain in director.brains:
		if brain.soldier.team == 0 and brain.role == R.GENERATOR and boss.raiders.has(brain.soldier.entity_id) and boss.order_locks.has(brain.soldier.entity_id):
			raiders += 1
	var target := game.asset(boss.raid_target)
	checks.check(raiders == 2 and target != null and target.team == 1 and _said(boss, BotLines.Line.ATTACK_YES), "attack the generator sends two bots on a raid on their base (%d)" % raiders)
	boss._on_ordered(person.soldier.entity_id, Orders.Kind.REPAIR_BASE, 0)
	var fixers := 0
	for brain in director.brains:
		if brain.soldier.team == 0 and brain.role == R.REPAIR and boss.repairers.has(brain.soldier.entity_id):
			fixers += 1
	checks.check(fixers == 1 and _said(boss, BotLines.Line.REPAIR_YES), "repair the base sends a bot to repair it (%d)" % fixers)
	boss.think(true)
	var kept := _role_count(director, 0, [R.GENERATOR, R.REPAIR])
	checks.check(kept == 3, "and they keep those roles when the commander thinks again (%d)" % kept)
	await _done(setup)


func _state_round_trip() -> void:
	var setup := _match(4, 4)
	var director: BotDirector = setup.director
	await ticks(60 * 3)
	var saved := director.get_state()
	director.commander(0).attack_lanes[0] += 5.0
	director.set_state(saved)
	checks.check(director.get_state() == saved, "the director's state with its commanders saves and loads whole")
	await _done(setup)
