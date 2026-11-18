extends SceneTree

## Checks bots fighting and playing capture the flag: the lead puts a disc
## where a crossing target will be, an expert bot standing still hits an
## enemy running back and forth in front of it with half its discs or more, the commander
## counts a person not read yet as offence, bots with no one against them take the enemy flag and
## capture it, and two seeded matches with fighting and flags play out the
## same.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/bot_fight_test.gd

var checks := TestWorld.Checks.new()


func _initialize() -> void:
	_run.call_deferred()


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	_lead_maths()
	await _hits_crossing_target()
	_roles()
	await _captures_alone()
	await _same_seed_fight()
	checks.finish(self)


## A shot along the lead meets a target moving across, from a moving shooter.
func _lead_maths() -> void:
	var disc := Weapon.all[Weapon.DISC]
	var eye := Vector3(0.0, 1.6, 0.0)
	var shooter_velocity := Vector3(0.0, 0.0, -10.0)
	var at := Vector3(30.0, 0.0, -40.0)
	var velocity := Vector3(-12.0, 0.0, 5.0)
	var aim := BotCombat.lead(eye, shooter_velocity, at, velocity, 0.0, disc)
	var shot := (aim - eye).normalized() * disc.speed + shooter_velocity * disc.inherit
	# Closest the shot gets to the target over its flight.
	var closest := INF
	for k in 200:
		var t := k * 0.01
		closest = minf(closest, (eye + shot * t).distance_to(at + velocity * t))
	checks.check(closest < 0.3, "a led disc passes %.2f m from a crossing target" % closest)


## A bot on flat ground with an enemy running back and forth across in front.
func _hits_crossing_target() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	TestWorld.flat_ground(holder)
	var game := Match.new(6)
	holder.add_child(game)
	var director := BotDirector.new(game, RouteGraph.new())
	var brain := director.add_bot(0, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(0.0, 0.2, 0.0)), 1.0)
	var runner := TestWorld.Scripted.new()
	var target := game.add_soldier(1, Transform3D(Basis.IDENTITY, Vector3(40.0, 0.2, 0.0)), runner)
	target.health = 100000.0
	var hits := [0]
	game.hit.connect(func(attacker: int, _victim: int, weapon: int) -> void:
		if attacker == brain.soldier.entity_id and weapon == Weapon.DISC:
			hits[0] += 1)
	for i in 60 * 12:
		# Runs 3 s one way and 3 s back across the bot's view.
		runner.command.move = Vector2(0.0, 1.0 if (i / 180) % 2 == 0 else -1.0)
		await physics_frame
	var shots: int = brain.stats.shots[Weapon.DISC]
	checks.check(shots >= 4, "an expert bot fires discs at a crossing enemy 40 m away (%d shots)" % shots)
	checks.check(hits[0] * 2 >= shots, "and leads them well enough to hit (%d of %d)" % [hits[0], shots])
	holder.free()
	await ticks(2)


## Roles on a team of 8 bots, and on one of 7 bots and a person.
func _roles() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var game := Match.new(1)
	holder.add_child(game)
	var director := BotDirector.new(game, RouteGraph.new())
	game.add_soldier(0, Transform3D(Basis.IDENTITY, Vector3(0.0, 100.0, 0.0)))
	for k in 7:
		director.add_bot(0, Transform3D(Basis.IDENTITY, Vector3(k * 2.0, 100.0, 0.0)))
	for k in 8:
		director.add_bot(1, Transform3D(Basis.IDENTITY, Vector3(k * 2.0, 100.0, 10.0)))
	var counts := [[], []]
	for team in 2:
		counts[team].resize(BotBrain.ROLE_NAMES.size())
		counts[team].fill(0)
	for brain in director.brains:
		counts[brain.soldier.team][brain.role] += 1
	var R := BotBrain.Role
	checks.check(counts[1].slice(0, 6) == [6, 1, 0, 0, 1, 0], "the commander splits 8 bots into 6 offence, 1 defence and 1 light defence (%s)" % str(counts[1]))
	checks.check(counts[0][R.OFFENCE] == 5 and counts[0][R.DEFENCE] == 1, "with a person on the team, not read yet, the bots take one fewer offence (%s)" % str(counts[0]))
	holder.free()


## Two bots with no enemies on the test map take the flag and score.
func _captures_alone() -> void:
	var setup := _ctf_match(8, 2, 0)
	var game: Match = setup.game
	var captured := -1.0
	for i in 60 * 300:
		await physics_frame
		if game.scores[0] > 0:
			captured = i / 60.0
			break
	checks.check(captured > 0.0, "two bots alone take the enemy flag and capture it in %.1f s" % captured)
	setup.holder.free()
	await ticks(2)


## Two runs of a 4 a side match with flags from the same seed end the same.
func _same_seed_fight() -> void:
	var runs := []
	for run in 2:
		var setup := _ctf_match(12, 4, 4)
		var game: Match = setup.game
		var director: BotDirector = setup.director
		await ticks(60 * 40)
		var result := []
		var ids := game.entities.keys()
		ids.sort()
		for id: int in ids:
			var s := game.soldier(id)
			if s != null:
				result.append([s.global_position, s.health, s.dead])
		var shots := 0
		var deaths := 0
		for brain in director.brains:
			shots += brain.stats.shots[0] + brain.stats.shots[1]
			deaths += brain.stats.deaths
		result.append([game.scores.duplicate(), shots, deaths])
		runs.append(result)
		setup.holder.free()
		await ticks(2)
	var fought: int = runs[0][runs[0].size() - 1][1]
	checks.check(runs[0] == runs[1], "the same seed plays a 4 a side match with flags the same for 40 s")
	checks.check(fought > 0, "and the bots fought in it (%d shots)" % fought)


func _ctf_match(match_seed: int, team0: int, team1: int) -> Dictionary:
	var holder := Node3D.new()
	root.add_child(holder)
	var map := TestMap.new()
	holder.add_child(map)
	var game := Match.new(match_seed)
	for team in 2:
		game.spawns[team] = map.spawn_points(team)
		game.add_flag(team, map.stand_point(team), map.flag_rest(team))
	holder.add_child(game)
	var director := BotDirector.new(game, map.route_graph)
	for k in team0:
		director.add_bot(0, map.spawn_point(0, k))
	for k in team1:
		director.add_bot(1, map.spawn_point(1, k))
	return { "holder": holder, "map": map, "game": game, "director": director }
