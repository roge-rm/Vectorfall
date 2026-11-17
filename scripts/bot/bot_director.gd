class_name BotDirector
extends Node

## Looks after a match's bots: adds them, shares the route graph and planner,
## spreads their thinking over the ticks, hands out the ray cast budget and
## collects the sounds they can hear. Later the team brains sit here too. It
## adds itself under the match, and goes with it.

## Line of sight ray casts all the bots may make in one tick.
const RAYS_PER_TICK := 8
## Bots think every this many ticks, 4 times a second, each on its own tick.
const THINK_TICKS := 15
## Seconds a sound is kept for bots to hear.
const SOUND_TIME := 1.0
## How far shots and blasts are heard, in metres.
const SHOT_RANGE := 120.0
const BLAST_RANGE := 160.0

var game: Match
var graph: RouteGraph
var planner := RoutePlanner.new()
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


func _init(match_node: Match, route_graph: RouteGraph) -> void:
	name = "BotDirector"
	game = match_node
	graph = route_graph
	game.add_child(self)
	game.fired.connect(_on_fired)
	game.impacted.connect(_on_impacted)


## Adds a bot soldier to the match at a spawn point. skill is 0 for a
## beginner to 1 for an expert.
func add_bot(team: int, spawn: Transform3D, skill := 0.5) -> BotBrain:
	var brain := BotBrain.new()
	brain.director = self
	brain.game = game
	brain.skill = skill
	brain.perception.reaction_time = lerpf(0.7, 0.15, skill)
	# Every 7th tick in turn spreads them evenly over THINK_TICKS.
	brain.think_offset = (brains.size() * 7) % THINK_TICKS
	brain.soldier = game.add_soldier(team, spawn, brain)
	brain.soldier.display_name = "Bot %d" % brain.soldier.entity_id
	brain.reset()
	brains.append(brain)
	return brain


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


func _on_fired(soldier_id: int, _weapon: int) -> void:
	var shooter := game.soldier(soldier_id)
	if shooter != null:
		_add_sound(shooter.eye_transform().origin, soldier_id, SHOT_RANGE)


func _on_impacted(weapon: int, at: Vector3, _normal: Vector3) -> void:
	if Weapon.all[weapon].splash_radius > 0.0:
		_add_sound(at, 0, BLAST_RANGE)


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
	}


func set_state(state: Dictionary) -> void:
	sounds.assign(state.sounds.duplicate(true))
	sound_count = state.sound_count
	_ray_tick = state.ray_tick
	_rays_left = state.rays_left
	for brain in brains:
		if state.brains.has(brain.soldier.entity_id):
			brain.set_state(state.brains[brain.soldier.entity_id])
