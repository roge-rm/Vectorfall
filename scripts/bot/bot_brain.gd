class_name BotBrain
extends CommandSource

## A bot: it only ever makes PlayerCommands, like a player's input. It thinks
## a few times a second (looks and listens, picks a goal, plans a route over
## the route graph) and steers every tick. For now its goal is a loop: to the
## enemy flag stand, back to its own, and again. Everything that changes what
## it does is in get_state(), and its only random numbers are the match's.

## POINT is a route graph point given by go_to(), and HOLD standing still
## after reaching it.
enum Goal { NONE, ENEMY_STAND, HOME_STAND, POINT, HOLD }
const GOAL_NAMES: Array[String] = ["none", "enemy stand", "home stand", "point", "hold"]
enum Escape { NONE, HOP, BACK_OFF, OTHER_WAY }
const ESCAPE_NAMES: Array[String] = ["", "hop", "back off", "other way"]

## Seconds with no progress towards the next point before the bot is stuck.
const STUCK_TIME := 2.5
## Metres closer to the next point that count as progress, or a speed
## towards it in m/s.
const PROGRESS := 1.0
const CLOSING_SPEED := 3.0
## Seconds on one leg, at least, before the bot counts as stuck on it.
const LEG_TIME := 20.0
## Ticks an escape move lasts.
const ESCAPE_TICKS := 60
## Seconds a link the bot got stuck on stays avoided.
const AVOID_TIME := 60.0
## Off the route by more than this, in metres, and the bot plans again.
const OFF_ROUTE := 25.0
## Below the route by more than this, in metres, and the bot plans again.
const OFF_ROUTE_BELOW := 10.0
## Close enough to a goal, flat and up or down, in metres.
const ARRIVE_RANGE := 6.0
const ARRIVE_HEIGHT := 4.0

var director: BotDirector
var game: Match
var soldier: Soldier
## 0 for a beginner to 1 for an expert.
var skill := 0.5
## Which tick of every BotDirector.THINK_TICKS this bot thinks on.
var think_offset := 0
var perception := BotPerception.new()
var steering := BotSteering.new()

var goal := Goal.NONE
## The route graph point the goal is at.
var goal_point := -1
## Route graph points to go through, and the one being steered towards.
var path: Array[int] = []
var path_index := 0
## Where the bot was when it planned, the start of the first leg.
var path_start := Vector3.ZERO
## Links got stuck on, as "from:to", to the tick they stop being avoided.
var avoid := {}
## Closest the bot has been to the point it's steering towards.
var best_distance := INF
## The point the stuck check is timing, and ticks spent heading for it.
var leg_target := -1
var leg_ticks := 0
var no_progress := 0.0
## Escapes tried since the last progress, which picks the next one.
var escapes := 0
var escape := Escape.NONE
var escape_ticks := 0
## Which side an escape move goes, -1 or 1.
var escape_side := 1.0
var stuck := false
var was_dead := false
var last_position := Vector3.ZERO
var goal_started := 0
## For the bot match report.
var stats := {}


## Back to the start of the goal loop, after spawning or respawning.
func reset() -> void:
	goal = Goal.NONE
	goal_point = -1
	path.clear()
	path_index = 0
	escape = Escape.NONE
	escape_ticks = 0
	stuck = false
	no_progress = 0.0
	best_distance = INF
	escapes = 0
	steering.reset()
	if soldier != null:
		last_position = soldier.global_position
		yaw = soldier.yaw
	if stats.is_empty():
		stats = {
			"distance": 0.0,
			"speed_sum": 0.0,
			"ticks": 0,
			"top_speed": 0.0,
			"time_stuck": 0.0,
			"stuck_spots": [],
			"routes": 0,
			"route_seconds": [],
		}


func make_command(delta: float) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.yaw = yaw
	command.pitch = pitch
	if soldier == null or game == null:
		return command
	if soldier.dead:
		was_dead = true
		return command
	if was_dead:
		was_dead = false
		reset()
	_track(delta)
	if (game.tick + think_offset) % BotDirector.THINK_TICKS == 0:
		think()
	if goal_point >= 0 and _near(director.graph.points[goal_point]):
		_arrived()
	if path.is_empty():
		return command
	_check_stuck(delta)
	if escape_ticks > 0:
		command = _escape_command()
		escape_ticks -= 1
		if escape_ticks == 0 and escape == Escape.OTHER_WAY:
			replan()
	else:
		command = steering.steer(self, delta)
	yaw = command.yaw
	pitch = command.pitch
	return command


## Looks and listens, picks a goal and plans a route to it when it needs one.
func think() -> void:
	perception.update(soldier, game, director)
	if goal == Goal.NONE:
		_set_goal(Goal.ENEMY_STAND)
	elif goal == Goal.HOLD:
		return
	elif path.is_empty() or _off_route() or _cant_turn():
		replan()


## Sends the bot to a route graph point, where it stops and holds.
func go_to(point: int) -> void:
	goal = Goal.POINT
	goal_point = point
	goal_started = game.tick
	replan()


func _set_goal(next: Goal) -> void:
	goal = next
	var team := 1 - soldier.team if next == Goal.ENEMY_STAND else soldier.team
	var stands := director.graph.interest_points(RouteGraph.FLAG_STAND, team)
	goal_point = stands[0] if not stands.is_empty() else -1
	goal_started = game.tick
	replan()


func _arrived() -> void:
	stats.routes += 1
	stats.route_seconds.append((game.tick - goal_started) / 60.0)
	if goal == Goal.POINT:
		goal = Goal.HOLD
		goal_point = -1
		path.clear()
		return
	_set_goal(Goal.HOME_STAND if goal == Goal.ENEMY_STAND else Goal.ENEMY_STAND)


func _near(point: Vector3) -> bool:
	var to := point - soldier.global_position
	return Vector2(to.x, to.z).length() < ARRIVE_RANGE and absf(to.y) < ARRIVE_HEIGHT


## Plans a route to the goal from the nearest point ahead, at the bot's speed and
## energy, keeping away from links it got stuck on.
func replan() -> void:
	var old_target: int = path[path_index] if path_index < path.size() else -1
	var old_best := best_distance
	var old_no_progress := no_progress
	path.clear()
	path_index = 0
	if goal_point < 0:
		return
	var graph := director.graph
	var avoid_links := {}
	for key: String in avoid.keys():
		if avoid[key] <= game.tick:
			avoid.erase(key)
			continue
		var ends := key.split(":")
		var link := graph.link_between(int(ends[0]), int(ends[1]))
		if link != null:
			avoid_links[link] = RoutePlanner.AVOID_COST
	var start := graph.start_point(soldier.global_position, soldier.velocity)
	path = director.plan(start, goal_point, soldier.velocity, soldier.energy, avoid_links)
	path_start = soldier.global_position
	best_distance = INF
	no_progress = 0.0
	advance()
	if old_target >= 0 and path_index < path.size() and path[path_index] == old_target:
		# Still heading for the same point, so it's still as stuck as it was.
		best_distance = old_best
		no_progress = old_no_progress


## The point being steered towards.
func target() -> Vector3:
	return director.graph.points[path[path_index]]


## The start of the leg being steered along.
func leg_start() -> Vector3:
	return director.graph.points[path[path_index - 1]] if path_index > 0 else path_start


## The link being followed, or null on the way to the first point.
func current_link() -> RouteGraph.Link:
	if path_index == 0:
		return null
	return director.graph.link_between(path[path_index - 1], path[path_index])


## Moves on to the next point once the bot is close to this one, or past it
## along the next leg.
func advance() -> void:
	var graph := director.graph
	var pos := soldier.global_position
	var speed := soldier.horizontal_speed()
	while path_index < path.size() - 1:
		var p := graph.points[path[path_index]]
		var q := graph.points[path[path_index + 1]]
		var to_p := Vector2(p.x - pos.x, p.z - pos.z)
		var reach := maxf(4.0, speed * 0.3)
		var passed := false
		var leg := Vector2(q.x - p.x, q.z - p.z)
		var from_p := Vector2(pos.x - p.x, pos.z - p.z)
		if leg.length() > 0.1 and from_p.dot(leg) > 0.0:
			var side := absf(from_p.cross(leg.normalized()))
			passed = side < 5.0 and absf(pos.y - p.y) < 15.0
		# Gone past it to one side: turning back costs more than going on.
		var start := leg_start()
		var leg_in := Vector2(p.x - start.x, p.z - start.z)
		if leg_in.length() > 0.1 and from_p.dot(leg_in) > 0.0 and to_p.length() < 15.0 and absf(pos.y - p.y) < 15.0:
			passed = true
		if to_p.length() < reach or passed:
			path_index += 1
			best_distance = INF
			no_progress = 0.0
			escapes = 0
		else:
			break


## A point lookahead metres further along the route from where the bot is,
## for it to steer at.
func aim_point(lookahead: float) -> Vector3:
	var graph := director.graph
	var pos := soldier.global_position
	var a := leg_start()
	var b := target()
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var t := 0.0
	if ab.length_squared() > 0.01:
		t = clampf(Vector2(pos.x - a.x, pos.z - a.z).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var at := a.lerp(b, t)
	var left := lookahead
	var k := path_index
	var before := a
	while true:
		var next := graph.points[path[k]]
		var step := Vector2(next.x - at.x, next.z - at.z).length()
		if step >= left:
			return at.lerp(next, left / step)
		left -= step
		at = next
		k += 1
		if k >= path.size():
			return at
		# Don't look round a sharp corner, so the bot doesn't cut it into
		# whatever's on the inside.
		var into := Vector2(next.x - before.x, next.z - before.z)
		var after := graph.points[path[k]]
		var out := Vector2(after.x - next.x, after.z - next.z)
		if into.length() > 0.1 and out.length() > 0.1 and absf(into.angle_to(out)) > deg_to_rad(35.0):
			return at
		before = next
	return at


## Going too fast to make the turn to the next point, so a route that
## carries on more the way it's going is better.
func _cant_turn() -> bool:
	var v := Vector2(soldier.velocity.x, soldier.velocity.z)
	var to := Vector2(target().x - soldier.global_position.x, target().z - soldier.global_position.z)
	return v.length() > 20.0 and to.length() > 1.0 and absf(v.angle_to(to)) > deg_to_rad(70.0)


func _off_route() -> bool:
	var pos := soldier.global_position
	var a := leg_start()
	var b := target()
	var closest := Geometry3D.get_closest_point_to_segment(Vector3(pos.x, 0.0, pos.z), Vector3(a.x, 0.0, a.z), Vector3(b.x, 0.0, b.z))
	if closest.distance_to(Vector3(pos.x, 0.0, pos.z)) > OFF_ROUTE:
		return true
	# Slid well below both ends of the leg, say back down a slope it couldn't
	# get up. A dip between the ends is fine.
	return minf(a.y, b.y) - pos.y > OFF_ROUTE_BELOW


## Counts no progress towards the next point, and picks an escape move when
## there's been none for STUCK_TIME: a hop with the jet, then backing off to
## one side, then another way round with the link avoided.
func _check_stuck(delta: float) -> void:
	advance()
	var to := target() - soldier.global_position
	var distance := to.length()
	# Heading back after going wide is progress too. Only across the ground,
	# so bobbing up and down under a ledge isn't.
	var flat := Vector3(to.x, 0.0, to.z)
	var closing := Vector3(soldier.velocity.x, 0.0, soldier.velocity.z).dot(flat / maxf(flat.length(), 0.01))
	# Too long on one leg is stuck too, say sliding back down each time it
	# nearly makes a climb.
	if path[path_index] != leg_target:
		leg_target = path[path_index]
		leg_ticks = 0
	leg_ticks += 1
	var leg_limit := maxf(LEG_TIME, leg_start().distance_to(target()) / 3.0)
	if leg_ticks > int(leg_limit * 60.0) and escape_ticks == 0:
		leg_ticks = 0
		no_progress = STUCK_TIME
	elif distance < best_distance - PROGRESS or (closing > CLOSING_SPEED and escape_ticks == 0):
		best_distance = distance
		no_progress = 0.0
		stuck = false
		return
	no_progress += delta
	if stuck:
		stats.time_stuck += delta
	if no_progress < STUCK_TIME or escape_ticks > 0:
		return
	if not stuck:
		stats.time_stuck += STUCK_TIME
	stuck = true
	no_progress = 0.0
	best_distance = distance
	escapes += 1
	escape = [Escape.HOP, Escape.BACK_OFF, Escape.OTHER_WAY][(escapes - 1) % 3]
	escape_ticks = ESCAPE_TICKS
	escape_side = -1.0 if game.rng.randf() < 0.5 else 1.0
	var from := path[path_index - 1] if path_index > 0 else -1
	var pos := soldier.global_position
	stats.stuck_spots.append({
		"tick": game.tick,
		"bot": soldier.entity_id,
		"position": [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1), snappedf(pos.z, 0.1)],
		"link": [from, path[path_index]],
		"escape": ESCAPE_NAMES[escape],
	})
	if escape == Escape.OTHER_WAY and from >= 0:
		avoid["%d:%d" % [from, path[path_index]]] = game.tick + int(AVOID_TIME * 60.0)


func _escape_command() -> PlayerCommand:
	var command := PlayerCommand.new()
	var to := target() - soldier.global_position
	var heading := atan2(-to.x, -to.z)
	command.yaw = heading
	command.pitch = 0.0
	var done := ESCAPE_TICKS - escape_ticks
	match escape:
		Escape.HOP:
			# Jump and jet up and over, a little to one side.
			command.move = Vector2(escape_side * 0.4, 1.0).normalized()
			if done < 2:
				command.buttons |= PlayerCommand.JUMP
			if soldier.energy > 5.0:
				command.buttons |= PlayerCommand.JET
		Escape.BACK_OFF, Escape.OTHER_WAY:
			# Back away to one side, then jet up for a fresh line.
			command.move = Vector2(escape_side * 0.7, -1.0).normalized()
			if done > ESCAPE_TICKS * 2 / 3 and soldier.energy > 20.0:
				command.buttons |= PlayerCommand.JET
	return command


func _track(delta: float) -> void:
	var pos := soldier.global_position
	var moved := pos.distance_to(last_position)
	# Respawning or being set somewhere isn't travel.
	if moved < soldier.tuning.max_speed * delta * 2.0:
		stats.distance += moved
	last_position = pos
	var speed := soldier.velocity.length()
	stats.speed_sum += speed
	stats.ticks += 1
	stats.top_speed = maxf(stats.top_speed, speed)


## A line for the debug overlay on what the bot is doing.
func describe() -> String:
	var doing := ESCAPE_NAMES[escape] if escape_ticks > 0 else steering.doing
	return "%s: %s\n%.0f m/s  energy %.0f  knows %d" % [GOAL_NAMES[goal], doing, soldier.velocity.length(), soldier.energy, perception.known_count()]


func get_state() -> Dictionary:
	return {
		"yaw": yaw,
		"pitch": pitch,
		"skill": skill,
		"think_offset": think_offset,
		"goal": goal,
		"goal_point": goal_point,
		"path": path.duplicate(),
		"path_index": path_index,
		"path_start": path_start,
		"avoid": avoid.duplicate(),
		"best_distance": best_distance,
		"leg_target": leg_target,
		"leg_ticks": leg_ticks,
		"no_progress": no_progress,
		"escapes": escapes,
		"escape": escape,
		"escape_ticks": escape_ticks,
		"escape_side": escape_side,
		"stuck": stuck,
		"was_dead": was_dead,
		"last_position": last_position,
		"goal_started": goal_started,
		"perception": perception.get_state(),
		"steering": steering.get_state(),
		"stats": stats.duplicate(true),
	}


func set_state(state: Dictionary) -> void:
	yaw = state.yaw
	pitch = state.pitch
	skill = state.skill
	think_offset = state.think_offset
	goal = state.goal
	goal_point = state.goal_point
	path.assign(state.path)
	path_index = state.path_index
	path_start = state.path_start
	avoid = state.avoid.duplicate()
	best_distance = state.best_distance
	leg_target = state.leg_target
	leg_ticks = state.leg_ticks
	no_progress = state.no_progress
	escapes = state.escapes
	escape = state.escape
	escape_ticks = state.escape_ticks
	escape_side = state.escape_side
	stuck = state.stuck
	was_dead = state.was_dead
	last_position = state.last_position
	goal_started = state.goal_started
	perception.set_state(state.perception)
	steering.set_state(state.steering)
	stats = state.stats.duplicate(true)
