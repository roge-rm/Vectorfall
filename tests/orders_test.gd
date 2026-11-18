extends SceneTree

## Checks orders, bots' lines, commander mode and skill: an order given in a
## command at a tick moves the nearest bots to its role and keeps them there,
## and a match with orders replays the same from the same seed; the right
## lines are said when our flag is taken and returned and when an enemy comes
## up behind a person, and reports keep their gaps; a role a person hands out
## in commander mode stays while the rest are planned round it, an escort
## lock goes with its person, and escort or cover orders from the dead do
## nothing; an expert
## lands more discs than a beginner on the same target.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/orders_test.gd

const R := BotBrain.Role
const L := BotLines.Line

var checks := TestWorld.Checks.new()
var map: GameMap


## A person's stand-in that stands still and gives orders at set ticks.
class Orderer:
	extends CommandSource
	var game: Match
	## Tick to [order, arg].
	var orders := {}

	func make_command(_delta: float) -> PlayerCommand:
		var command := PlayerCommand.new()
		command.yaw = yaw
		if orders.has(game.tick):
			command.order = orders[game.tick][0]
			command.order_arg = orders[game.tick][1]
		return command


func _initialize() -> void:
	_run.call_deferred()


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


## Waits until the match has stepped tick n.
func until(game: Match, n: int) -> void:
	while game.tick < n:
		await physics_frame


func _run() -> void:
	map = OchreFold.new()
	root.add_child(map)
	_personalities()
	await _orders_move_bots()
	await _orders_replay()
	await _reports()
	await _commander_locks()
	await _skill_duel()
	checks.finish(self)


## A match on Ochre Fold, on the shared map or, with fresh, one of its own
## so terrain collision left from another match can't change it.
func _match(team0: int, team1: int, match_seed := 3, fresh := false) -> Dictionary:
	var holder := Node3D.new()
	root.add_child(holder)
	var on := map
	if fresh:
		on = OchreFold.new()
		holder.add_child(on)
	var game := Match.new(match_seed)
	game.terrain = on.terrain
	for team in 2:
		game.spawns[team] = on.spawn_points(team)
		game.add_flag(team, on.stand_point(team), on.flag_rest(team))
	holder.add_child(game)
	var director := BotDirector.new(game, on.route_graph)
	for k in team0:
		director.add_bot(0, on.spawn_point(0, k))
	for k in team1:
		director.add_bot(1, on.spawn_point(1, k))
	return { "holder": holder, "game": game, "director": director }


func _add_orderer(setup: Dictionary, team: int, at: Vector3) -> Orderer:
	var orderer := Orderer.new()
	var game: Match = setup.game
	orderer.game = game
	var s := game.add_soldier(team, Transform3D(Basis.IDENTITY, at), orderer)
	s.display_name = "Stand-in"
	s.health = 100000.0
	setup.director.assign_roles()
	return orderer


func _done(setup: Dictionary) -> void:
	setup.holder.free()
	await ticks(2)


func _in_role(director: BotDirector, team: int, role: int) -> Array[int]:
	var ids: Array[int] = []
	for brain in director.brains:
		if brain.soldier.team == team and brain.role == role:
			ids.append(brain.soldier.entity_id)
	return ids


func _said(boss: TeamCommander, line: int) -> int:
	var n := 0
	for entry: Dictionary in boss.chat:
		if entry.line == line:
			n += 1
	return n


## Personalities come from the seed, the same each time, with all four on a
## team of 8.
func _personalities() -> void:
	var a: Array[int] = []
	var b: Array[int] = []
	for k in 8:
		a.append(BotDirector.personality_for(7, 1, k))
		b.append(BotDirector.personality_for(7, 1, k))
	var kinds := {}
	for p in a:
		kinds[p] = true
	checks.check(a == b and kinds.size() == 4, "personalities come from the seed, all four on a team of 8 (%s)" % str(a))
	checks.check(BotDirector.personality_for(1, 0, 0) != BotDirector.personality_for(2, 0, 0), "and a different seed starts the round somewhere else")


## Orders at set ticks, between the commander's thinks: defend the flag,
## escort me, take the flag.
func _orders_move_bots() -> void:
	var setup := _match(7, 3)
	var game: Match = setup.game
	var director: BotDirector = setup.director
	var boss: TeamCommander = director.commander(0)
	var orderer := _add_orderer(setup, 0, Vector3(-250.0, map.surface_at(-250.0, 0.0) + 1.0, 0.0))
	var me: int = game.sources.find_key(orderer)
	orderer.orders = { 155: [Orders.Kind.DEFEND_FLAG, 0], 185: [Orders.Kind.ESCORT_ME, 0], 215: [Orders.Kind.TAKE_FLAG, 0] }
	await until(game, 154)
	var defence_before := _in_role(director, 0, R.DEFENCE).size()
	await until(game, 155)
	var defence_now := _in_role(director, 0, R.DEFENCE).size()
	checks.check(game.tick == 155 and defence_now == defence_before + 2, "defend the flag at tick 155 sends 2 more bots to defence that tick (%d to %d)" % [defence_before, defence_now])
	checks.check(_said(boss, L.DEFENCE_YES) == 1, "and one answers \"On defence\"")
	await until(game, 185)
	var escorts := 0
	for id: int in boss.order_locks:
		var brain := director.brain_of(id)
		if boss.order_locks[id].order == Orders.Kind.ESCORT_ME and brain.role == R.ESCORT and brain.role_target == me:
			escorts += 1
	checks.check(escorts == 2 and _said(boss, L.ESCORT_YES) == 1, "escort me sends 2 bots to escort the person (%d)" % escorts)
	await until(game, 214)
	var offence_before := _in_role(director, 0, R.OFFENCE).size()
	await until(game, 215)
	var offence_after := _in_role(director, 0, R.OFFENCE).size()
	checks.check(offence_after == offence_before + 1 and boss.attack_now(), "take the flag sends one more to offence and makes it urgent (%d to %d)" % [offence_before, offence_after])
	var locked := boss.order_locks.keys()
	locked.sort()
	# Well past the 10 s a role is held, the ordered bots are still where
	# they were sent.
	await ticks(60 * 20)
	var kept := 0
	for id: int in locked:
		var brain := director.brain_of(id)
		if brain.role == boss.order_locks.get(id, {}).get("role", -1):
			kept += 1
	checks.check(locked.size() == 5 and kept == locked.size() - _taken_off(boss, locked), "20 s on, the ordered bots keep their roles (%d of %d)" % [kept, locked.size()])
	await ticks(int(TeamCommander.ORDER_TIME * 60.0) - 60 * 20 + 60)
	checks.check(boss.order_locks.is_empty() and not boss.attack_now(), "and after %.0f s the orders are over" % TeamCommander.ORDER_TIME)
	await _done(setup)


## Ordered bots whose order is already done: taking the flag ends that one.
func _taken_off(boss: TeamCommander, ids: Array) -> int:
	var n := 0
	for id: int in ids:
		if not boss.order_locks.has(id):
			n += 1
	return n


## The same seed and the same orders play out the same.
func _orders_replay() -> void:
	var states := []
	for run in 2:
		var setup := _match(5, 5, 11, true)
		var game: Match = setup.game
		var orderer := _add_orderer(setup, 0, Vector3(-300.0, map.surface_at(-300.0, 40.0) + 1.0, 40.0))
		orderer.orders = { 90: [Orders.Kind.ESCORT_ME, 0], 400: [Orders.Kind.TAKE_FLAG, 0], 700: [Orders.Kind.SET_ROLE, Orders.role_arg(0, R.DEFENCE)] }
		await ticks(60 * 20)
		var director: BotDirector = setup.director
		var positions := []
		for id: int in game.entities:
			positions.append([id, game.entities[id].global_position])
		states.append([director.get_state(), positions, game.tick])
		await _done(setup)
	var same: bool = states[0][0] == states[1][0] and states[0][1] == states[1][1]
	var orders: int = states[0][0].commanders[0][1].decisions.filter(func(d: Dictionary) -> bool: return d.text.contains("orders")).size()
	checks.check(orders == 3, "three orders reach the commander from the commands (%d)" % orders)
	checks.check(same, "a match with orders plays out the same from the same seed")


## Lines for our flag taken and back, the enemy carrier's lane, and a warning,
## with reports kept apart.
func _reports() -> void:
	var setup := _match(4, 0)
	var game: Match = setup.game
	var director: BotDirector = setup.director
	var boss: TeamCommander = director.commander(0)
	var heard := []
	boss.said.connect(func(team: int, speaker: int, line: int, text: String) -> void: heard.append([team, speaker, line, text]))
	await ticks(30)
	# An enemy stand-in holds our flag where it stands.
	var thief := _add_orderer(setup, 1, game.flags[0].global_position + Vector3(0.0, 0.5, 0.0))
	var thief_soldier: Soldier = game.soldier(game.sources.find_key(thief))
	game._take_flag(game.flags[0], thief_soldier)
	checks.check(_said(boss, L.FLAG_TAKEN) == 1 and heard.size() == 1 and heard[0][0] == 0 and director.brain_of(heard[0][1]) != null, "a bot on the team says our flag's taken (%s)" % str(heard))
	game._return_flag(game.flags[0], 0)
	checks.check(_said(boss, L.FLAG_RETURNED) == 0, "the flag back straight after waits for the gap between reports")
	game._take_flag(game.flags[0], thief_soldier)
	checks.check(_said(boss, L.FLAG_TAKEN) == 1, "taken again so soon isn't said twice")
	await ticks(60 * 8)
	var lane_lines := boss.chat.filter(func(e: Dictionary) -> bool: return e.line == L.CARRIER_LANE)
	var titles := ["north canyon", "middle", "south spine"]
	checks.check(lane_lines.size() == 1 and titles.any(func(t: String) -> bool: return lane_lines[0].text.ends_with(t)), "the carrier's lane is reported by name (%s)" % str(lane_lines.map(func(e: Dictionary) -> String: return e.text)))
	game._return_flag(game.flags[0], 0)
	checks.check(_said(boss, L.FLAG_RETURNED) == 1, "and once the gap is past, our flag's back is said")
	# A person on team 0 with an enemy the team knows of behind it.
	var person := _add_orderer(setup, 0, Vector3(-400.0, map.surface_at(-400.0, 0.0) + 1.0, 0.0))
	var me: Soldier = game.soldier(game.sources.find_key(person))
	await ticks(2)
	boss.known[thief_soldier.entity_id] = { "position": me.global_position + Vector3(sin(me.yaw), 0.0, cos(me.yaw)) * 25.0, "velocity": Vector3.ZERO, "tick": game.tick, "approach": -1 }
	boss._help_people()
	boss._help_people()
	checks.check(_said(boss, L.BEHIND_YOU) == 1, "an enemy behind a person gets \"Behind you\", once")
	# Every report keeps REPORT_GAP from the one before.
	var last := -1000.0
	var spaced := true
	for entry: Dictionary in boss.chat:
		if entry.line in [L.FLAG_TAKEN, L.FLAG_RETURNED, L.CARRIER_LANE, L.WE_HAVE_FLAG]:
			spaced = spaced and entry.seconds - last >= TeamCommander.REPORT_GAP - 0.05
			last = entry.seconds
	checks.check(spaced, "reports are at least %.0f s apart" % TeamCommander.REPORT_GAP)
	await _done(setup)


## Commander mode: a person gives a bot a role, which stays while the
## commander plans the rest round it, until they give it back.
func _commander_locks() -> void:
	var setup := _match(7, 0)
	var game: Match = setup.game
	var director: BotDirector = setup.director
	var boss: TeamCommander = director.commander(0)
	var orderer := _add_orderer(setup, 0, Vector3(0.0, map.surface_at(0.0, 0.0) + 1.0, 0.0))
	await ticks(10)
	var pick := director.brain_of(_in_role(director, 0, R.OFFENCE)[0])
	var id := pick.soldier.entity_id
	var start := game.tick
	orderer.orders = { start + 5: [Orders.Kind.SET_ROLE, Orders.role_arg(id, R.DEFENCE)] }
	await ticks(10)
	checks.check(pick.role == R.DEFENCE and boss.order_locks.has(id) and boss.order_locks[id].until == -1, "a person in commander mode puts a bot on defence")
	for k in 3:
		for other: int in boss.role_since:
			boss.role_since[other] -= int(TeamCommander.MIN_ROLE_TIME * 60.0) + 1
		boss.think()
	var defence := _in_role(director, 0, R.DEFENCE)
	checks.check(defence == [id], "it stays there, and the commander moves the other defence away to fill the plan (%s)" % str(defence))
	orderer.orders = { game.tick + 2: [Orders.Kind.SET_ROLE, Orders.role_arg(id, Orders.AUTO)] }
	await ticks(4)
	checks.check(not boss.order_locks.has(id) and _said(boss, L.AUTO_YES) == 1, "and given back, the lock goes")
	# The nearest bot to the person, by 0.
	orderer.orders = { game.tick + 2: [Orders.Kind.SET_ROLE, Orders.role_arg(0, R.MIDFIELD)] }
	await ticks(4)
	var me: Soldier = game.soldier(game.sources.find_key(orderer))
	var closest: BotBrain = null
	for brain in boss.brains():
		if closest == null or brain.soldier.global_position.distance_to(me.global_position) < closest.soldier.global_position.distance_to(me.global_position):
			closest = brain
	checks.check(boss.order_locks.has(closest.soldier.entity_id) and closest.role == R.MIDFIELD, "\"nearest bot\" gives the role to the bot nearest the person")
	# A commander mode escort of someone who leaves the match is let go.
	var guard := closest.soldier.entity_id
	orderer.orders = { game.tick + 2: [Orders.Kind.SET_ROLE, Orders.role_arg(guard, R.ESCORT)] }
	await ticks(4)
	var held: bool = boss.order_locks.has(guard) and boss.order_locks[guard].target == me.entity_id
	game.entities.erase(me.entity_id)
	game.sources.erase(me.entity_id)
	boss.think()
	checks.check(held and not boss.order_locks.has(guard), "an escort lock goes when the person it escorts leaves the match")
	game.entities[me.entity_id] = me
	game.sources[me.entity_id] = orderer
	# Escort me and cover me from a dead person do nothing.
	var said_before := boss.chat.size()
	var locks_before := boss.order_locks.size()
	me.health = 0.0
	me.die()
	boss._on_ordered(me.entity_id, Orders.Kind.ESCORT_ME, 0)
	boss._on_ordered(me.entity_id, Orders.Kind.COVER_ME, 0)
	checks.check(boss.chat.size() == said_before and boss.order_locks.size() == locks_before, "escort me and cover me from a dead person send no one and get no answer")
	await _done(setup)


## An expert and a beginner each shoot at the same enemy running across in
## front of them for 24 s; the expert lands more.
func _skill_duel() -> void:
	var results := []
	for level in [4, 0]:
		var holder := Node3D.new()
		root.add_child(holder)
		TestWorld.flat_ground(holder)
		var game := Match.new(6)
		holder.add_child(game)
		var director := BotDirector.new(game, RouteGraph.new())
		director.skill_levels[0] = level
		var brain := director.add_bot(0, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(0.0, 0.2, 0.0)))
		var runner := TestWorld.Scripted.new()
		var target := game.add_soldier(1, Transform3D(Basis.IDENTITY, Vector3(40.0, 0.2, 0.0)), runner)
		target.health = 100000.0
		var hits := [0]
		game.hit.connect(func(attacker: int, _victim: int, _weapon: int) -> void:
			if attacker == brain.soldier.entity_id:
				hits[0] += 1)
		for i in 60 * 24:
			runner.command.move = Vector2(0.0, 1.0 if (i / 180) % 2 == 0 else -1.0)
			# Hits knock it about; it's kept on its line 40 m out.
			if absf(target.global_position.x - 40.0) > 2.0 or target.global_position.y > 3.0:
				target.global_position = Vector3(40.0, 0.2, clampf(target.global_position.z, -30.0, 30.0))
				target.velocity = Vector3.ZERO
			await physics_frame
		results.append([brain.skill, brain.perception.view_range, hits[0], brain.stats.shots[Weapon.DISC] + brain.stats.shots[Weapon.CHAINGUN]])
		holder.free()
		await ticks(2)
	checks.check(results[0][0] == 1.0 and results[1][0] == 0.0 and results[0][1] > results[1][1], "the team's skill level sets the bot's skill and how far it sees (%s)" % str(results))
	checks.check(results[0][2] > results[1][2], "an expert lands more hits than a beginner on the same runner (%d to %d)" % [results[0][2], results[1][2]])
