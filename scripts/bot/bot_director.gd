class_name BotDirector
extends Node

## Looks after a match's bots: adds them, shares the route graph and planner,
## spreads their thinking over the ticks, hands out the ray cast budget and
## collects the sounds they can hear. A TeamCommander per team hands out
## roles, and the director keeps each bot's tally of shots, hits, kills and flags for the reports. It
## adds itself under the match, and goes with it.

## Line of sight ray casts all the bots may make in one tick.
const RAYS_PER_TICK := 8
## Ray casts for disc shot checks in one tick, on top of RAYS_PER_TICK, so
## sight rays never use them all. Disc checks take these first, then what
## sight rays left.
const DISC_RAYS_PER_TICK := 4
## Bots think every this many ticks, 4 times a second, each on its own tick.
const THINK_TICKS := 15
## Points of a route search taken when it starts, which finishes most, and
## on each tick after, so a long search spreads over ticks instead of holding
## one up. All of a tick's search points share SEARCH_POINTS_PER_TICK: searches
## carried on from earlier ticks are handed theirs before the bots work, and
## searches begun in the work get what's left after it. Both go round the bots
## from a turn that moves on to the first bot left without points, kept for
## each of the WORK_TICKS ticks, so every search gets its go. Points a search
## takes outside the bot phase, as go_to() does, come off the next tick's
## pool. A point is about 40 us on a desktop and several times that on a
## Fire HD 8.
const SEARCH_FIRST := 250
const SEARCH_POINTS := 50
const SEARCH_POINTS_PER_TICK := 250
## Seconds a sound is kept for bots to hear.
const SOUND_TIME := 1.0
## Bot skill for each level, beginner to expert, and the levels' names.
const SKILLS: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]
const SKILL_NAMES: Array[String] = ["beginner", "easy", "normal", "hard", "expert"]
const NORMAL := 2
## Personalities handed out round a team, from a place picked by the seed.
const PERSONALITY_ROUND: Array[int] = [BotBrain.Personality.DEFAULT, BotBrain.Personality.AGGRESSIVE, BotBrain.Personality.CAREFUL, BotBrain.Personality.SNIPER, BotBrain.Personality.DEFAULT, BotBrain.Personality.AGGRESSIVE, BotBrain.Personality.CAREFUL, BotBrain.Personality.DEFAULT]
## How far shots and blasts are heard, in metres.
const SHOT_RANGE := 120.0
const BLAST_RANGE := 160.0

## Bots work out their commands on WorkerThreadPool when true, one after
## another on the main thread when false. Both give the same match.
static var threads := true
## Threads the bots' work is spread over at most. More is slower here: GDScript
## threads fight over Godot's object lookups, and the work is small.
const MAX_THREADS := 4

var game: Match
var graph: RouteGraph
var planner := RoutePlanner.new()
## Each team's skill level, an index into SKILLS, for bots added without one.
var skill_levels: Array[int] = [NORMAL, NORMAL]
## Bots get personalities; off, they're all the default.
var personalities := true
var brains: Array[BotBrain] = []
## Recent sounds, each { seq, tick, position, source, range }. source is the
## shooter's id, or 0 for a blast.
var sounds: Array[Dictionary] = []
## Sounds made so far, numbering each.
var sound_count := 0
var _ray_tick := -1
var _rays_left := 0
var _disc_rays_left := 0
## Per tick of every BotBrain.WORK_TICKS, the bot index the search points are
## handed out from.
var _search_turns: Array[int] = []
## Search points taken outside the bot phase, owed by the next ticks' pools.
var _points_owed := 0
## The delta run_bots() was given, and the order bots are handed to the
## threads in, for _work().
var _delta := 0.0
var _order := PackedInt32Array()
## The bots that began a search in this tick's work, in bot order.
var _starts := PackedInt32Array()
## Each bot's work time this tick, by place in _order, for Prof. Each thread
## writes only its own bots' entries.
var _work_usec := PackedInt64Array()
## soldiers() as last made, and the match's next_id and entity count then.
var _soldiers: Array[Soldier] = []
var _soldiers_made := Vector2i(-1, -1)
## Routes already planned, by start, goal, speed and energy, rounded.
var _plans := {}
## Per team, the links ending near its spawn points, found once.
var _spawn_links := {}
## Per team, the sniper perches its snipers hold, found once, guarded by
## _perches_lock for bot threads.
var _perches := {}
var _perches_lock := Mutex.new()
## Team to its commander, made with the team's first bot.
var commanders := {}
## Team to the tops of its stations' pads, made on the main thread when the
## stations change, for bots to read in work().
var _pads := {}
var _pads_made := -1
var _lanes: Lanes
## The last tick the commanders were given, so they run once a tick.
var _commanded_tick := -1


func _init(match_node: Match, route_graph: RouteGraph) -> void:
	name = "BotDirector"
	game = match_node
	graph = route_graph
	# Done now, while the map loads, so the first bot to plan doesn't stall a
	# tick on them.
	graph.packed()
	for team: int in [0, 1]:
		links_near_spawns(team, BotBrain.CARRIER_KEEP_OFF)
	game.add_child(self)
	game.bots = self
	game.fired.connect(_on_fired)
	game.impacted.connect(_on_impacted)
	game.damaged.connect(_on_damaged)
	game.hit.connect(_on_hit)
	game.killed.connect(_on_killed)
	game.flag_taken.connect(_on_flag_taken)
	game.flag_returned.connect(_on_flag_returned)
	game.flag_captured.connect(_on_flag_captured)


## Adds a bot soldier to the match at a spawn point. skill is 0 for a
## beginner to 1 for an expert, or below 0 for its team's skill level.
func add_bot(team: int, spawn: Transform3D, skill := -1.0) -> BotBrain:
	var brain := BotBrain.new()
	brain.director = self
	brain.game = game
	if skill < 0.0:
		skill = SKILLS[clampi(skill_levels[team], 0, SKILLS.size() - 1)]
	brain.skill = skill
	brain.perception.reaction_time = BotPerception.reaction_for(skill)
	brain.perception.view_range = BotPerception.view_range_for(skill)
	if personalities:
		var on_team := 0
		for other in brains:
			if other.soldier.team == team:
				on_team += 1
		brain.personality = personality_for(game.seed_value, team, on_team)
	# Every 7th tick in turn spreads them evenly over THINK_TICKS.
	brain.think_offset = (brains.size() * 7) % THINK_TICKS
	brain.work_parity = (brains.size() + 1) % BotBrain.WORK_TICKS
	brain.soldier = game.add_soldier(team, spawn, brain)
	brain.soldier.display_name = "Bot %d" % brain.soldier.entity_id
	brain.rng.seed = hash([game.seed_value, brain.soldier.entity_id])
	brain.kit_rng.seed = hash([brain.rng.seed, "kit"])
	brain.reset()
	brains.append(brain)
	if not commanders.has(team):
		commanders[team] = TeamCommander.new(team, self)
		commanders[team].watch()
	assign_roles()
	if game.tick == 0:
		# Before the match starts every bot wears its role's loadout.
		for other in brains:
			other.dress()
	return brain


## The personality of a team's nth bot in a match with this seed.
static func personality_for(match_seed: int, team: int, nth: int) -> int:
	var start := posmod(match_seed * 5 + team * 3, PERSONALITY_ROUND.size())
	return PERSONALITY_ROUND[(start + nth) % PERSONALITY_ROUND.size()]


## The skill level nearest a skill from 0 to 1.
static func skill_level(skill: float) -> int:
	return clampi(roundi(skill * (SKILLS.size() - 1)), 0, SKILLS.size() - 1)


## Has both commanders hand out roles again at once, counting every soldier,
## people too, ignoring how long bots have been in their roles.
func assign_roles() -> void:
	for team: int in [0, 1]:
		if commanders.has(team):
			commanders[team].think(true)


func commander(team: int) -> TeamCommander:
	return commanders.get(team)


## Works out every bot's command for this tick, before any soldier moves.
## Called by the match each tick before it asks for commands. Main thread.
##
## Serial first, in bot order: a snapshot of every soldier and flag, the
## commanders, sight line rays for the bots that think this tick, and the
## route search points for searches carried on, handed out from the turn.
## Then each bot's work on its
## own fields, reading only the snapshot and what nothing writes meanwhile
## (other bots as they were before it, the commanders, the route graph and
## route store, sounds), on WorkerThreadPool or serially. Then searches bots
## began get points from what's left of the pool, and run the same way.
## Then, in bot order, the rays bots asked for and the routes they
## found go into the store.
## Nothing in it depends on which thread runs what or when.
func run_bots(delta: float) -> void:
	_delta = delta
	var prof_t := Time.get_ticks_usec() if Prof.on else 0
	for other in soldiers():
		other.take_snapshot()
	for team: int in game.flags:
		game.flags[team].take_snapshot()
	if _pads_made != game.stations.size():
		_make_pads()
	if Prof.on:
		Prof.add("bots.snapshot", Time.get_ticks_usec() - prof_t)
		var commander_t := Time.get_ticks_usec()
		before_tick()
		Prof.add("bot.commander", Time.get_ticks_usec() - commander_t)
	else:
		before_tick()
	Soldier.use_snapshot = true
	for brain in brains:
		brain.before_work()
	var pool := maxi(SEARCH_POINTS_PER_TICK - _points_owed, 0)
	_points_owed = maxi(_points_owed - SEARCH_POINTS_PER_TICK, 0)
	_search_turns.resize(BotBrain.WORK_TICKS)
	var parity := game.tick % BotBrain.WORK_TICKS
	var turn := _search_turns[parity] if _search_turns[parity] < brains.size() else 0
	var left_out := -1
	for n in brains.size():
		var k := (turn + n) % brains.size()
		if brains[k].wants_points():
			if pool <= 0 and left_out < 0:
				left_out = k
			pool = brains[k].allow_carry(pool)
	if Prof.on:
		Prof.add("bots.serial_before", Time.get_ticks_usec() - prof_t)
		prof_t = Time.get_ticks_usec()
	# Bots with the most to do first, so they don't start last and hold up
	# the rest.
	_order.clear()
	for k in brains.size():
		if brains[k].busy():
			_order.append(k)
	for k in brains.size():
		if not brains[k].busy():
			_order.append(k)
	if Prof.on:
		_work_usec.resize(_order.size())
	_run_group(_work, _order.size())
	if Prof.on:
		Prof.add("bots.work", Time.get_ticks_usec() - prof_t)
		var sum := 0
		for usec in _work_usec:
			sum += usec
		Prof.add("bots.work_sum", sum)
		prof_t = Time.get_ticks_usec()
	_starts.clear()
	for n in brains.size():
		var k := (turn + n) % brains.size()
		if brains[k].started_search():
			if pool <= 0 and left_out < 0:
				left_out = k
			pool = brains[k].allow_start(pool)
			_starts.append(k)
	# Next time this parity comes round, start from the first bot left out.
	if left_out >= 0:
		_search_turns[parity] = left_out
	if not _starts.is_empty():
		_run_group(_work_start, _starts.size())
		if Prof.on:
			Prof.add("bots.starts", Time.get_ticks_usec() - prof_t)
			prof_t = Time.get_ticks_usec()
	for brain in brains:
		brain.after_work()
		for search in brain.found:
			_keep_plan(search)
		brain.found.clear()
	Soldier.use_snapshot = false
	if Prof.on:
		Prof.add("bots.serial_after", Time.get_ticks_usec() - prof_t)


func _make_pads() -> void:
	_pads_made = game.stations.size()
	_pads = { 0: [] as Array[Vector3], 1: [] as Array[Vector3] }
	var ids := game.stations.keys()
	ids.sort()
	for id: int in ids:
		var station := game.stations[id]
		if _pads.has(station.team):
			_pads[station.team].append(station.position + Vector3.UP * InventoryStation.PAD_TOP)


## The tops of a team's station pads, as of this tick's bot phase.
func station_pads(team: int) -> Array[Vector3]:
	var none: Array[Vector3] = []
	return _pads.get(team, none)


## Calls work(k) for k from 0 to count - 1, on WorkerThreadPool or serially.
func _run_group(work: Callable, count: int) -> void:
	if threads and count > 1:
		var task := WorkerThreadPool.add_group_task(work, count, mini(MAX_THREADS, OS.get_processor_count()), true, "bots")
		WorkerThreadPool.wait_for_group_task_completion(task)
	else:
		for k in count:
			work.call(k)


## The kth bot in _starts runs the search it began this tick.
func _work_start(k: int) -> void:
	brains[_starts[k]].work_start()


## The kth bot in _order's work for the tick, on a worker thread or not.
func _work(k: int) -> void:
	if Prof.on:
		var t := Time.get_ticks_usec()
		brains[_order[k]].work(_delta)
		_work_usec[k] = Time.get_ticks_usec() - t
	else:
		brains[_order[k]].work(_delta)


## Lets each commander think on its tick. Called once a tick by run_bots();
## only the first call in a tick does anything.
func before_tick() -> void:
	if _commanded_tick == game.tick:
		return
	_commanded_tick = game.tick
	for team: int in [0, 1]:
		if commanders.has(team):
			commanders[team].tick()


## The map's lanes, made the first time they're needed.
func lanes() -> Lanes:
	if _lanes == null:
		_lanes = Lanes.new(graph, game.stands)
	return _lanes


func brain_of(id: int) -> BotBrain:
	var source: CommandSource = game.sources.get(id)
	return source as BotBrain


## Plans a route over the graph all in one go, as begin_plan() and
## run_plan() do over ticks.
func plan(start: int, goal: int, velocity: Vector3, energy: float, avoid := {}) -> Array[int]:
	var search := begin_plan(start, goal, velocity, energy, avoid)
	while not run_plan(search, -1):
		pass
	var path: Array[int] = []
	path.assign(search.result)
	return path


## Starts planning a route over the graph, taking up to first points of the
## search now. Safe from bot threads: it only reads the route store. Speed, energy and heading are rounded so routes can be
## kept and shared between bots; a route got from the store is the same one
## planning again would give. Routes avoiding links aren't kept. The search
## comes back done, or for run_plan() to carry on each tick.
func begin_plan(start: int, goal: int, velocity: Vector3, energy: float, avoid := {}, first := SEARCH_FIRST) -> RoutePlanner.Search:
	var speed := Vector2(velocity.x, velocity.z).length()
	var speed_step := int(speed / 5.0)
	var energy_step := int(energy / 20.0)
	# One of 8 headings, or none when slow.
	var heading_step := -1
	var heading := Vector2.ZERO
	if speed > 10.0:
		heading_step = posmod(roundi(atan2(velocity.z, velocity.x) / (TAU / 8.0)), 8)
		heading = Vector2.from_angle(heading_step * TAU / 8.0)
	var rounded_speed := speed_step * 5.0 + 2.5
	var rounded_energy := energy_step * 20.0 + 10.0
	var key := []
	if avoid.is_empty():
		key = [start, goal, speed_step, energy_step, heading_step]
		if _plans.has(key):
			if Prof.on:
				Prof.count("astar_cached")
			var kept := RoutePlanner.Search.new()
			kept.start = start
			kept.goal = goal
			kept.done = true
			kept.result.assign(_plans[key])
			return kept
	if Prof.on:
		Prof.count("astar_avoid" if not avoid.is_empty() else "astar_new")
	var t := Time.get_ticks_usec() if Prof.on else 0
	var search := planner.begin(graph, start, goal, rounded_speed, rounded_energy, avoid, heading)
	if Prof.on:
		Prof.add("bot.replan.begin", Time.get_ticks_usec() - t)
	search.key = key
	run_plan(search, first)
	return search


## Carries a search on by up to budget points, or all of it for -1. A route
## found is kept in the store at once on the main thread; in the bot phase
## it's the bot's job to hand it to run_bots(), which keeps it. True once
## it's done.
func run_plan(search: RoutePlanner.Search, budget := SEARCH_POINTS) -> bool:
	if search.done:
		return true
	if budget == 0:
		return false
	var t := Time.get_ticks_usec() if Prof.on else 0
	var done := planner.step(search, budget)
	if Prof.on:
		Prof.add("bot.replan.astar", Time.get_ticks_usec() - t)
	if done and not Soldier.use_snapshot:
		_keep_plan(search)
	return done


## Keeps a finished search's route in the store. Main thread.
func _keep_plan(search: RoutePlanner.Search) -> void:
	if search.key.is_empty():
		return
	if _plans.size() > 4000:
		_plans.clear()
	_plans[search.key] = search.result.duplicate()


## Every soldier in the match, dead or alive, by id. Made again only when
## entities come or go.
func soldiers() -> Array[Soldier]:
	var made := Vector2i(game.next_id, game.entities.size())
	if made != _soldiers_made:
		_soldiers_made = made
		_soldiers.clear()
		var ids := game.entities.keys()
		ids.sort()
		for id: int in ids:
			var other := game.soldier(id)
			if other != null:
				_soldiers.append(other)
	return _soldiers


## Takes one ray cast from this tick's budget, or false if it's used up. A
## disc check takes from its own budget first.
func take_ray(for_disc := false) -> bool:
	if _ray_tick != game.tick:
		_ray_tick = game.tick
		_rays_left = RAYS_PER_TICK
		_disc_rays_left = DISC_RAYS_PER_TICK
	if for_disc and _disc_rays_left > 0:
		_disc_rays_left -= 1
		return true
	if _rays_left <= 0:
		return false
	_rays_left -= 1
	return true


## Notes search points taken outside the bot phase, for the next ticks' pools.
func owe_points(points: int) -> void:
	_points_owed += points


func _add_sound(at: Vector3, source: int, reach: float) -> void:
	sound_count += 1
	sounds.append({ "seq": sound_count, "tick": game.tick, "position": at, "source": source, "range": reach })
	while not sounds.is_empty() and (game.tick - sounds[0].tick) / 60.0 > SOUND_TIME:
		sounds.pop_front()


func _on_fired(soldier_id: int, weapon: int) -> void:
	var shooter := game.soldier(soldier_id)
	if shooter != null:
		_add_sound(shooter.eye_transform().origin, soldier_id, SHOT_RANGE)
	var brain := brain_of(soldier_id)
	if brain != null:
		brain.stats.shots[weapon] += 1


func _on_damaged(victim_id: int, attacker_id: int, _amount: float, _from: Vector3) -> void:
	var victim := brain_of(victim_id)
	var attacker := game.soldier(attacker_id)
	if victim != null and attacker != null and attacker.team != victim.soldier.team:
		# Being hit tells you roughly where from, like a player's hit marker.
		victim.combat.hurt(attacker_id, game.tick)
		victim.perception.hear(attacker_id, attacker.at(), attacker.vel(), game.tick)


func _on_hit(attacker_id: int, _victim_id: int, weapon: int) -> void:
	var brain := brain_of(attacker_id)
	if brain != null:
		brain.stats.hits[weapon] += 1


func _on_killed(victim_id: int, killer_id: int, _weapon: int) -> void:
	var victim := brain_of(victim_id)
	if victim != null:
		victim.stats.deaths += 1
	var killer := brain_of(killer_id)
	var dead := game.soldier(victim_id)
	if killer != null and killer_id != victim_id and dead != null and dead.team != killer.soldier.team:
		killer.stats.kills += 1


func _on_flag_taken(_team: int, soldier_id: int) -> void:
	var brain := brain_of(soldier_id)
	if brain != null:
		brain.stats.grabs += 1


func _on_flag_returned(_team: int, soldier_id: int) -> void:
	var brain := brain_of(soldier_id)
	if brain != null:
		brain.stats.returns += 1


func _on_flag_captured(_team: int, soldier_id: int) -> void:
	var brain := brain_of(soldier_id)
	if brain != null:
		brain.stats.captures += 1


func _on_impacted(weapon: int, at: Vector3, _normal: Vector3) -> void:
	if Weapon.all[weapon].splash_radius > 0.0:
		_add_sound(at, 0, BLAST_RANGE)


## Sniper perches on a team's half, short of its base, that a link leads to
## without a must-jet climb, found once.
func perches(team: int) -> Array[int]:
	_perches_lock.lock()
	if not _perches.has(team):
		var found: Array[int] = []
		var home_x: float = game.stands[team].x
		var reachable := {}
		for link: RouteGraph.Link in graph.links:
			if not link.must_jet:
				reachable[link.to] = true
		for point in graph.interest_points(RouteGraph.SNIPER, -1):
			var p := graph.points[point]
			if reachable.has(point) and signf(p.x) == signf(home_x) and absf(p.x) < absf(home_x) - 30.0:
				found.append(point)
		_perches[team] = found
	var kept: Array[int] = _perches[team]
	_perches_lock.unlock()
	return kept


## The links ending within reach of a team's spawn points, once per spawn
## they're near, in link order.
func links_near_spawns(team: int, reach: float) -> Array[RouteGraph.Link]:
	if not _spawn_links.has(team):
		var found: Array[RouteGraph.Link] = []
		for spawn in graph.interest_points(RouteGraph.SPAWN, team):
			var at := graph.points[spawn]
			for link: RouteGraph.Link in graph.links:
				var end := graph.points[link.to]
				if Vector2(end.x - at.x, end.z - at.z).length() < reach:
					found.append(link)
		_spawn_links[team] = found
	return _spawn_links[team]


## Every stuck spot the bots have logged, oldest first.
func stuck_spots() -> Array[Dictionary]:
	var spots: Array[Dictionary] = []
	for brain in brains:
		spots.append_array(brain.stats.stuck_spots)
	spots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.tick < b.tick)
	return spots


func get_state() -> Dictionary:
	var brain_states := {}
	for brain in brains:
		brain_states[brain.soldier.entity_id] = brain.get_state()
	return {
		"sounds": sounds.duplicate(true),
		"sound_count": sound_count,
		"ray_tick": _ray_tick,
		"rays_left": _rays_left,
		"disc_rays_left": _disc_rays_left,
		"search_turns": _search_turns.duplicate(),
		"points_owed": _points_owed,
		"brains": brain_states,
		"commanded_tick": _commanded_tick,
		"commanders": commanders.keys().map(func(team: int) -> Array: return [team, commanders[team].get_state()]),
	}


func set_state(state: Dictionary) -> void:
	sounds.assign(state.sounds.duplicate(true))
	sound_count = state.sound_count
	_ray_tick = state.ray_tick
	_rays_left = state.rays_left
	_disc_rays_left = state.get("disc_rays_left", 0)
	_search_turns.assign(state.get("search_turns", []))
	_points_owed = state.get("points_owed", 0)
	_commanded_tick = state.commanded_tick
	for pair: Array in state.commanders:
		if commanders.has(pair[0]):
			commanders[pair[0]].set_state(pair[1])
	for brain in brains:
		if state.brains.has(brain.soldier.entity_id):
			brain.set_state(state.brains[brain.soldier.entity_id])
