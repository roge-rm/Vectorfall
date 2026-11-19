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
## Speed the search guesses the rest of the way at, in m/s. About what
## long routes average, so a little quick for some: the search stays short
## and finds a route close to the quickest.
const GUESS_SPEED := 26.0
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


## A search that can be run a few hundred points at a time, so a long one
## spreads over ticks. Stepping it to the end gives the same route as plan().
class Search:
	extends RefCounted
	var graph: RouteGraph
	var start := -1
	var goal := -1
	var speed := 0.0
	var energy := 0.0
	var avoid := {}
	var heading := Vector2.ZERO
	## What BotDirector keeps the route under once found, or empty.
	var key := []
	## Points taken off the heap so far, the work done.
	var expanded := 0
	var done := false
	## The route once done, empty if there's no way.
	var result: Array[int] = []
	var cost := PackedFloat32Array()
	var speeds := PackedFloat32Array()
	var energies := PackedFloat32Array()
	var came := PackedInt32Array()
	var closed := PackedByteArray()
	## A binary heap of estimates with their points, kept in step.
	var heap_key := PackedFloat64Array()
	var heap_at := PackedInt32Array()
	var heap_n := 0

	## The search as plain data for a saved state, without the graph.
	func to_state() -> Dictionary:
		return {
			"start": start, "goal": goal, "speed": speed, "energy": energy,
			"avoid": avoid.duplicate(), "heading": heading, "key": key.duplicate(),
			"expanded": expanded, "done": done, "result": PackedInt32Array(result),
			"cost": cost.duplicate(), "speeds": speeds.duplicate(), "energies": energies.duplicate(),
			"came": came.duplicate(), "closed": closed.duplicate(),
			"heap_key": heap_key.duplicate(), "heap_at": heap_at.duplicate(), "heap_n": heap_n,
		}

	## A search made from to_state() data that carries on by itself.
	static func from_state(on: RouteGraph, state: Dictionary) -> Search:
		var search := Search.new()
		search.graph = on
		for field: String in ["start", "goal", "speed", "energy", "heading", "expanded", "done", "heap_n"]:
			search.set(field, state[field])
		search.avoid = state.avoid.duplicate()
		search.key = state.key.duplicate()
		search.result.assign(Array(state.result))
		for field: String in ["cost", "speeds", "energies", "came", "closed", "heap_key", "heap_at"]:
			search.set(field, state[field].duplicate())
		return search


## The quickest list of points from start to goal, or an empty list if
## there's no way. avoid maps links to extra seconds, and heading is the
## flat direction the bot is moving in, if it's moving.
func plan(graph: RouteGraph, start: int, goal: int, speed: float, energy: float, avoid := {}, heading := Vector2.ZERO) -> Array[int]:
	var search := begin(graph, start, goal, speed, energy, avoid, heading)
	step(search, -1)
	return search.result


## A search for plan() to run with step().
func begin(graph: RouteGraph, start: int, goal: int, speed: float, energy: float, avoid := {}, heading := Vector2.ZERO) -> Search:
	var search := Search.new()
	search.graph = graph
	search.start = start
	search.goal = goal
	search.speed = speed
	search.energy = energy
	search.avoid = avoid
	search.heading = heading
	if start < 0 or goal < 0 or not graph.reachable(start, goal):
		search.done = true
		return search
	var n := graph.points.size()
	search.cost.resize(n)
	search.cost.fill(INF)
	search.speeds.resize(n)
	search.energies.resize(n)
	search.came.resize(n)
	search.came.fill(-1)
	search.closed.resize(n)
	search.cost[start] = 0.0
	search.speeds[start] = speed
	search.energies[start] = energy
	search.heap_key = PackedFloat64Array([_guess(graph.points[start], graph.points[goal])])
	search.heap_at = PackedInt32Array([start])
	search.heap_n = 1
	return search


## Takes up to budget points off the heap (all of them for -1), and returns
## true once the search is done.
func step(search: Search, budget: int) -> bool:
	if search.done:
		return true
	var graph := search.graph
	var goal := search.goal
	var heading := search.heading
	var avoid := search.avoid
	var points := graph.points
	var goal_at := points[goal]
	# Taken out of the search while working on them, so writes don't copy them.
	var cost := search.cost
	var speeds := search.speeds
	var energies := search.energies
	var came := search.came
	var closed := search.closed
	var heap_key := search.heap_key
	var heap_at := search.heap_at
	search.cost = PackedFloat32Array()
	search.speeds = PackedFloat32Array()
	search.energies = PackedFloat32Array()
	search.came = PackedInt32Array()
	search.closed = PackedByteArray()
	search.heap_key = PackedFloat64Array()
	search.heap_at = PackedInt32Array()
	var heap_n := search.heap_n
	var expanded := 0
	var finished := false
	var check_avoid := not avoid.is_empty()
	var out_first := graph.out_first
	var slot_to := graph.slot_to
	var slot_dir := graph.slot_dir
	var slot_distance := graph.slot_distance
	var slot_climb := graph.slot_climb
	var slot_steep := graph.slot_steep
	var slot_energy := graph.slot_energy
	var slot_must_jet := graph.slot_must_jet
	var slot_link := graph.slot_link
	var t := tuning
	var run := t.run_speed
	var gravity := t.gravity
	var refill := t.energy_refill
	var refill_delay := t.refill_delay
	var energy_max := t.energy_max
	var top := t.max_speed * 0.75
	while true:
		if heap_n == 0:
			finished = true
			break
		if budget >= 0 and expanded >= budget:
			break
		# Pop the smallest.
		var at := heap_at[0]
		heap_n -= 1
		if heap_n > 0:
			var last_key := heap_key[heap_n]
			var last_at := heap_at[heap_n]
			var k := 0
			while true:
				var child := k * 2 + 1
				if child >= heap_n:
					break
				if child + 1 < heap_n and heap_key[child + 1] < heap_key[child]:
					child += 1
				if heap_key[child] >= last_key:
					break
				heap_key[k] = heap_key[child]
				heap_at[k] = heap_at[child]
				k = child
			heap_key[k] = last_key
			heap_at[k] = last_at
		if closed[at] != 0:
			continue
		if at == goal:
			finished = true
			break
		closed[at] = 1
		expanded += 1
		if Prof.on:
			Prof.count("astar_expanded")
		var v0 := speeds[at]
		var e0 := energies[at]
		var from := came[at]
		var arriving := heading
		if from >= 0:
			var p := points[at] - points[from]
			arriving = Vector2(p.x, p.z).normalized()
		var base := cost[at]
		for s in range(out_first[at], out_first[at + 1]):
			var to := slot_to[s]
			if closed[to] != 0:
				continue
			# Turning loses the speed across the new way, and turning back
			# all but stops you.
			var v_in := v0
			var dir := slot_dir[s]
			if arriving != Vector2.ZERO and dir != Vector2.ZERO:
				v_in = maxf(v0 * maxf(arriving.dot(dir), 0.0), minf(v0, run))
			# cross(), written out here as it's the inner loop.
			var e_in := e0
			var crossed: Vector3
			if slot_must_jet[s] != 0:
				var need_jet := slot_energy[s]
				var wait_jet := 0.0
				if e_in < need_jet:
					wait_jet = (need_jet - e_in) / refill + refill_delay
					e_in = need_jet
				crossed = Vector3(wait_jet + slot_distance[s] / run, run, e_in - need_jet)
			else:
				var wait := 0.0
				var too_steep := false
				var steep := slot_steep[s]
				if steep > 0.0:
					var carry := v_in * STEEP_CARRY
					var need := maxf(steep - carry * carry / (2.0 * gravity), 0.0) * RouteGraph.ENERGY_PER_METRE
					if need > energy_max:
						too_steep = true
					elif need > e_in:
						wait = minf(need - e_in, energy_max - e_in) / refill + refill_delay
						e_in = minf(need, energy_max)
				if too_steep:
					crossed = Vector3(TOO_STEEP, run, 0.0)
				else:
					var climb := slot_climb[s]
					var v2 := v_in * v_in - 2.0 * gravity * climb * (1.0 if climb > 0.0 else DROP_KEEP)
					var left := e_in
					var used := 0.0
					if climb > 0.0 and v2 < CRUISE_SPEED * CRUISE_SPEED and left > 0.0:
						var want := (CRUISE_SPEED * CRUISE_SPEED - v2) / (2.0 * gravity) * RouteGraph.ENERGY_PER_METRE
						used = minf(want, left)
						left -= used
						v2 += used / RouteGraph.ENERGY_PER_METRE * 2.0 * gravity
					var v1 := clampf(sqrt(maxf(v2, 0.0)), run, top)
					var seconds := wait + slot_distance[s] / maxf((maxf(v_in, run) + v1) * 0.5, run)
					if used == 0.0:
						left = minf(left + refill * maxf(seconds - wait - refill_delay, 0.0), energy_max)
					crossed = Vector3(seconds, v1, left)
			var g := base + crossed.x
			if check_avoid:
				g += float(avoid.get(slot_link[s], 0.0))
			if g < cost[to]:
				cost[to] = g
				speeds[to] = crossed.y
				energies[to] = crossed.z
				came[to] = at
				# Push.
				var key := g + points[to].distance_to(goal_at) / GUESS_SPEED
				if heap_n == heap_key.size():
					heap_key.append(key)
					heap_at.append(to)
				var k := heap_n
				heap_n += 1
				while k > 0:
					var parent := (k - 1) / 2
					if heap_key[parent] <= key:
						break
					heap_key[k] = heap_key[parent]
					heap_at[k] = heap_at[parent]
					k = parent
				heap_key[k] = key
				heap_at[k] = to
	search.expanded += expanded
	search.heap_n = heap_n
	if not finished:
		search.cost = cost
		search.speeds = speeds
		search.energies = energies
		search.came = came
		search.closed = closed
		search.heap_key = heap_key
		search.heap_at = heap_at
		return false
	search.done = true
	if cost[goal] == INF:
		return true
	var at := goal
	while at >= 0:
		search.result.append(at)
		at = came[at]
	search.result.reverse()
	return true


## Seconds for the straight line at GUESS_SPEED.
static func _guess(a: Vector3, b: Vector3) -> float:
	return a.distance_to(b) / GUESS_SPEED
