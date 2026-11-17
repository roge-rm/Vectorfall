class_name RoutePlanner
extends RefCounted

## Finds the quickest way over a route graph with A*. The cost of each link is
## an estimate of the seconds it takes, carried along with the speed and
## energy you'd have on reaching each point, so downhill ski lines that build
## speed win over flat runs, and jet climbs are only cheap while there's
## energy for them.

## Below this speed on a climb the bot jets to keep going, if it has energy.
const CRUISE_SPEED := 20.0
## Share of the speed from a drop that's kept, after steering and crests.
const DROP_KEEP := 0.85
## Share of the speed counted on to carry the bot up a steep stretch. Bots
## reach the bottom of a climb slower than the drop before it suggests, after
## turns and crests, and sliding back down costs far more than a short wait.
const STEEP_CARRY := 0.6
## Seconds for a link too steep to get up at the speed you'd have, so it's
## only taken when there's no other way.
const TOO_STEEP := 600.0
## Speed the search guesses the rest of the way at, in m/s.
const GUESS_SPEED := 35.0
## Seconds added to a link this bot has got stuck on.
const AVOID_COST := 60.0

var tuning := MovementTuning.new()


## Seconds to cross a link starting at speed v0 with energy e0, and the speed
## and energy at its end, as (seconds, speed, energy).
func cross(link: RouteGraph.Link, v0: float, e0: float) -> Vector3:
	var t := tuning
	var run := t.run_speed
	var d3 := link.distance
	if link.must_jet:
		# Walls slow you to running speed, and you may have to wait for energy.
		var wait := 0.0
		if e0 < link.energy:
			wait = (link.energy - e0) / t.energy_refill + t.refill_delay
			e0 = link.energy
		return Vector3(wait + d3 / run, run, e0 - link.energy)
	var g := t.gravity
	var wait := 0.0
	if link.steep > 0.0:
		# The steep part needs speed or the jet, or the bot waits for energy.
		var carry := v0 * STEEP_CARRY
		var need := maxf(link.steep - carry * carry / (2.0 * g), 0.0) * RouteGraph.ENERGY_PER_METRE
		if need > t.energy_max:
			# More than a tank: you'd slide back down from part way.
			return Vector3(TOO_STEEP, run, 0.0)
		if need > e0:
			wait = minf(need - e0, t.energy_max - e0) / t.energy_refill + t.refill_delay
			e0 = minf(need, t.energy_max)
	var v2 := v0 * v0 - 2.0 * g * link.climb * (1.0 if link.climb > 0.0 else DROP_KEEP)
	var energy := e0
	var used := 0.0
	if link.climb > 0.0 and v2 < CRUISE_SPEED * CRUISE_SPEED and energy > 0.0:
		var want := (CRUISE_SPEED * CRUISE_SPEED - v2) / (2.0 * g) * RouteGraph.ENERGY_PER_METRE
		used = minf(want, energy)
		energy -= used
		v2 += used / RouteGraph.ENERGY_PER_METRE * 2.0 * g
	var v1 := clampf(sqrt(maxf(v2, 0.0)), run, t.max_speed * 0.75)
	var seconds := wait + d3 / maxf((maxf(v0, run) + v1) * 0.5, run)
	if used == 0.0:
		energy = minf(energy + t.energy_refill * maxf(seconds - wait - t.refill_delay, 0.0), t.energy_max)
	return Vector3(seconds, v1, energy)


## The quickest list of points from start to goal, or an empty list if
## there's no way. avoid maps links to extra seconds, and heading is the
## flat direction the bot is moving in, if it's moving.
func plan(graph: RouteGraph, start: int, goal: int, speed: float, energy: float, avoid := {}, heading := Vector2.ZERO) -> Array[int]:
	var result: Array[int] = []
	if start < 0 or goal < 0:
		return result
	var n := graph.points.size()
	var goal_at := graph.points[goal]
	var cost := PackedFloat32Array()
	cost.resize(n)
	cost.fill(INF)
	var speeds := PackedFloat32Array()
	speeds.resize(n)
	var energies := PackedFloat32Array()
	energies.resize(n)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	cost[start] = 0.0
	speeds[start] = speed
	energies[start] = energy
	var check_avoid := not avoid.is_empty()
	# A small binary heap of [estimate, point].
	var open: Array = [[_guess(graph.points[start], goal_at), start]]
	while not open.is_empty():
		var item: Array = _pop(open)
		var at: int = item[1]
		if closed[at] != 0:
			continue
		if at == goal:
			break
		closed[at] = 1
		var v0 := speeds[at]
		var e0 := energies[at]
		var from := came[at]
		var arriving := heading
		if from >= 0:
			var p := graph.points[at] - graph.points[from]
			arriving = Vector2(p.x, p.z).normalized()
		var base := cost[at]
		for link: RouteGraph.Link in graph.out_links[at]:
			var to := link.to
			if closed[to] != 0:
				continue
			# Turning loses the speed across the new way, and turning back
			# all but stops you.
			var v_in := v0
			if arriving != Vector2.ZERO and link.length > 0.1:
				var p := graph.points[to] - graph.points[at]
				var along := arriving.dot(Vector2(p.x, p.z) / link.length)
				v_in = maxf(v0 * maxf(along, 0.0), minf(v0, tuning.run_speed))
			var step := cross(link, v_in, e0)
			var g := base + step.x
			if check_avoid:
				g += float(avoid.get(link, 0.0))
			if g < cost[to]:
				cost[to] = g
				speeds[to] = step.y
				energies[to] = step.z
				came[to] = at
				_push(open, [g + _guess(graph.points[to], goal_at), to])
	if cost[goal] == INF:
		return result
	var at := goal
	while at >= 0:
		result.append(at)
		at = came[at]
	result.reverse()
	return result


## Seconds for the straight line at a good skiing speed. Real routes are
## rarely that quick, so this keeps the search short and still finds near
## the quickest.
static func _guess(a: Vector3, b: Vector3) -> float:
	return a.distance_to(b) / GUESS_SPEED


static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var k := heap.size() - 1
	while k > 0:
		var parent := (k - 1) / 2
		if heap[parent][0] <= item[0]:
			break
		heap[k] = heap[parent]
		k = parent
	heap[k] = item


static func _pop(heap: Array) -> Array:
	var first: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return first
	var k := 0
	var n := heap.size()
	while true:
		var child := k * 2 + 1
		if child >= n:
			break
		if child + 1 < n and heap[child + 1][0] < heap[child][0]:
			child += 1
		if heap[child][0] >= last[0]:
			break
		heap[k] = heap[child]
		k = child
	heap[k] = last
	return first
