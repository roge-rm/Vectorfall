class_name BotDirector
extends Node

## Looks after a match's bots: adds them, shares the route graph and planner,
## spreads their thinking over the ticks, hands out the ray cast budget and
## collects the sounds they can hear. A TeamCommander per team hands out
## roles, and the director keeps each bot's tally of shots, hits, kills and flags for the reports. It
## adds itself under the match, and goes with it.

## Line of sight ray casts all the bots may make in one tick.
const RAYS_PER_TICK := 8
## Bots think every this many ticks, 4 times a second, each on its own tick.
const THINK_TICKS := 15
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
## Routes already planned, by start, goal, speed and energy, rounded.
var _plans := {}
## Per team, the links ending near its spawn points, found once.
var _spawn_links := {}
## Per team, the sniper perches its snipers hold, found once.
var _perches := {}
## Team to its commander, made with the team's first bot.
var commanders := {}
var _lanes: Lanes
## The last tick the commanders were given, so they run once a tick.
var _commanded_tick := -1


func _init(match_node: Match, route_graph: RouteGraph) -> void:
	name = "BotDirector"
	game = match_node
	graph = route_graph
	game.add_child(self)
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
	brain.soldier = game.add_soldier(team, spawn, brain)
	brain.soldier.display_name = "Bot %d" % brain.soldier.entity_id
	brain.reset()
	brains.append(brain)
	if not commanders.has(team):
		commanders[team] = TeamCommander.new(team, self)
		commanders[team].watch()
	assign_roles()
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


## Lets each commander think on its tick. Called by every bot each tick; only
## the first call in a tick does anything.
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


## Plans a route over the graph. Speed, energy and heading are rounded so
## routes can be kept and shared between bots; a route got from the store is
## the same one planning again would give. Routes avoiding links aren't kept.
func plan(start: int, goal: int, velocity: Vector3, energy: float, avoid := {}) -> Array[int]:
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
	if not avoid.is_empty():
		return planner.plan(graph, start, goal, rounded_speed, rounded_energy, avoid, heading)
	var key := [start, goal, speed_step, energy_step, heading_step]
	if not _plans.has(key):
		if _plans.size() > 4000:
			_plans.clear()
		_plans[key] = planner.plan(graph, start, goal, rounded_speed, rounded_energy, {}, heading)
	var path: Array[int] = []
	path.assign(_plans[key])
	return path


## Takes one ray cast from this tick's budget, or false if it's used up.
func take_ray() -> bool:
	if _ray_tick != game.tick:
		_ray_tick = game.tick
		_rays_left = RAYS_PER_TICK
	if _rays_left <= 0:
		return false
	_rays_left -= 1
	return true


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
		victim.perception.hear(attacker_id, attacker.global_position, attacker.velocity, game.tick)


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
	return _perches[team]


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
		"brains": brain_states,
		"commanded_tick": _commanded_tick,
		"commanders": commanders.keys().map(func(team: int) -> Array: return [team, commanders[team].get_state()]),
	}


func set_state(state: Dictionary) -> void:
	sounds.assign(state.sounds.duplicate(true))
	sound_count = state.sound_count
	_ray_tick = state.ray_tick
	_rays_left = state.rays_left
	_commanded_tick = state.commanded_tick
	for pair: Array in state.commanders:
		if commanders.has(pair[0]):
			commanders[pair[0]].set_state(pair[1])
	for brain in brains:
		if state.brains.has(brain.soldier.entity_id):
			brain.set_state(state.brains[brain.soldier.entity_id])
