class_name RouteGraph
extends RefCounted

## The bots' map of where they can go: points at foot height joined by one way
## links, each typed by how you cross it, and points of interest such as each
## base's flag stand. A map's script makes it when the map is built, never
## while playing. to_dict() and from_dict() keep it in plain data, so a map
## builder can save one.

enum Kind { RUN, SKI, JET }
const KIND_NAMES: Array[String] = ["run", "ski", "jet"]

## Points of interest. A team of -1 is for either team.
const FLAG_STAND := "flag_stand"
const SPAWN := "spawn"
const WAY_IN := "way_in"
const DEFENCE := "defence"
const HIGH_GROUND := "high_ground"
## Perches with a long view, ways to a team's flag, and where vehicle pads
## and deployables will go in later milestones.
const SNIPER := "sniper"
const FLAG_APPROACH := "flag_approach"
const VEHICLE_PAD := "vehicle_pad"
const DEPLOY := "deploy"

## Energy a jet climb costs per metre of height, from standing. The jet lifts
## you at about 8 m/s on average and drains 40 a second.
const ENERGY_PER_METRE := 5.0
## A rise steeper than this between two samples is a wall you can't run up,
## about 50°, the steepest floor a soldier stands on.
const WALL_SLOPE := 1.2
## Ground steeper than this, about 45°, is too steep to run up for long.
const STEEP_SLOPE := 1.0
## A step up this much more than the one before it, in metres, is a wall.
const WALL_KINK := 1.0
## Metres to each side of a link that are checked for walls.
const SIDE_CHECK := 2.0
## Links climbing more steeply than this on average are jet links.
const JET_SLOPE := 0.35
## Links falling more steeply than this on average are ski links.
const SKI_SLOPE := -0.08


class Link:
	extends RefCounted
	var from := 0
	var to := 0
	var kind := Kind.RUN
	## Horizontal length in metres.
	var length := 0.0
	## Height of the end above the start, negative going down.
	var climb := 0.0
	## Straight line length in metres.
	var distance := 0.0
	## Estimated jet energy to cross from standing.
	var energy := 0.0
	## A wall or gap on the way that you have to jet or jump over.
	var must_jet := false
	## Metres of height on stretches too steep to run up, which need speed or
	## the jet.
	var steep := 0.0


var points := PackedVector3Array()
var links: Array[Link] = []
## Per point, the links leaving it.
var out_links: Array[Array] = []
## Each is { kind, team, point }.
var interest: Array[Dictionary] = []
## While linking, whether there were links already to keep from doubling.
var _check_existing := true


func add_point(at: Vector3) -> int:
	points.append(at)
	out_links.append([])
	return points.size() - 1


func add_link(from: int, to: int, kind: Kind, must_jet := false, steep := 0.0) -> Link:
	var link := Link.new()
	link.from = from
	link.to = to
	link.kind = kind
	var a := points[from]
	var b := points[to]
	link.length = Vector2(b.x - a.x, b.z - a.z).length()
	link.climb = b.y - a.y
	link.distance = a.distance_to(b)
	link.must_jet = must_jet
	link.steep = steep
	link.energy = maxf(link.climb + 1.0, 0.0) * ENERGY_PER_METRE if kind == Kind.JET else 0.0
	links.append(link)
	out_links[from].append(link)
	return link


func add_interest(kind: String, team: int, point: int) -> void:
	interest.append({ "kind": kind, "team": team, "point": point })


## Points of interest of one kind for a team, with those for either team.
func interest_points(kind: String, team := -1) -> Array[int]:
	var found: Array[int] = []
	for entry in interest:
		if entry.kind == kind and (team < 0 or entry.team == team or entry.team < 0):
			found.append(entry.point)
	return found


func link_between(from: int, to: int) -> Link:
	for link: Link in out_links[from]:
		if link.to == to:
			return link
	return null


## The point closest to a position, weighting height double so a point on a
## deck above isn't taken for one on the ground below.
func nearest(at: Vector3) -> int:
	var best := -1
	var best_d := INF
	for k in points.size():
		var d := points[k] - at
		d.y *= 2.0
		var dd := d.length_squared()
		if dd < best_d:
			best_d = dd
			best = k
	return best


## The point to start a route from: the nearest, or when moving fast the
## nearest one not behind, so a bot doesn't turn back to start its route.
func start_point(at: Vector3, velocity: Vector3) -> int:
	var heading := Vector2(velocity.x, velocity.z)
	if heading.length() < 10.0:
		return nearest(at)
	heading = heading.normalized()
	var best := -1
	var best_d := INF
	for k in points.size():
		var d := points[k] - at
		var flat := Vector2(d.x, d.z)
		if flat.length() > 6.0 and flat.normalized().dot(heading) < 0.5:
			continue
		d.y *= 2.0
		var dd := d.length_squared()
		if dd < best_d:
			best_d = dd
			best = k
	return best if best >= 0 and best_d < 60.0 * 60.0 else nearest(at)


## True if you can get from one point to the other along links.
func connected(from: int, to: int) -> bool:
	var seen := { from: true }
	var queue: Array[int] = [from]
	while not queue.is_empty():
		var at: int = queue.pop_back()
		if at == to:
			return true
		for link: Link in out_links[at]:
			if not seen.has(link.to):
				seen[link.to] = true
				queue.append(link.to)
	return false


## Links every pair of points closer than max_length both ways, unless the
## way between them is blocked, typing each from the ground's height along
## it. surface(x, z) is the height you'd stand at, and blocked(x, z) is true
## inside anything you can't pass, such as a rock or a tower.
func auto_link(max_length: float, surface: Callable, blocked: Callable, step := 1.5) -> void:
	# Points by grid cell max_length wide, so each only looks at its own
	# cell and the eight round it.
	var cells := {}
	for k in points.size():
		var key := Vector2i(floori(points[k].x / max_length), floori(points[k].z / max_length))
		if not cells.has(key):
			cells[key] = PackedInt32Array()
		cells[key].append(k)
	for a in points.size():
		var pa := points[a]
		var home := Vector2i(floori(pa.x / max_length), floori(pa.z / max_length))
		var near := PackedInt32Array()
		for dj in range(-1, 2):
			for di in range(-1, 2):
				near.append_array(cells.get(home + Vector2i(di, dj), PackedInt32Array()))
		# In point order, so links come out the same as checking every pair.
		near.sort()
		for b in near:
			if a == b:
				continue
			var pb := points[b]
			var flat := Vector2(pb.x - pa.x, pb.z - pa.z)
			if flat.length() > max_length or link_between(a, b) != null:
				continue
			var profile := _profile(pa, pb, surface, blocked, step)
			if profile.is_empty():
				continue
			add_link(a, b, profile.kind, profile.must_jet, profile.steep)


## Like auto_link(), but quicker on a big map: the ground between each pair is
## sampled once for both directions, every step metres with the lines to
## each side where near(a, b) is true, such as round buildings, and every
## coarse_step metres along the middle only elsewhere. mirror, if given,
## holds each point's twin on a map mirrored in x (or -1), and a pair's twin
## gets the same links without sampling again. Links come out a to b, then
## b to a.
func auto_link_pairs(max_length: float, surface: Callable, blocked: Callable, step: float, coarse_step: float, near: Callable, mirror := PackedInt32Array()) -> void:
	var cells := {}
	for k in points.size():
		var key := Vector2i(floori(points[k].x / max_length), floori(points[k].z / max_length))
		if not cells.has(key):
			cells[key] = PackedInt32Array()
		cells[key].append(k)
	var twins := not mirror.is_empty()
	_check_existing = not links.is_empty()
	for a in points.size():
		var pa := points[a]
		var home := Vector2i(floori(pa.x / max_length), floori(pa.z / max_length))
		var close := PackedInt32Array()
		for dj in range(-1, 2):
			for di in range(-1, 2):
				close.append_array(cells.get(home + Vector2i(di, dj), PackedInt32Array()))
		close.sort()
		for b in close:
			if b <= a:
				continue
			var pb := points[b]
			if Vector2(pb.x - pa.x, pb.z - pa.z).length() > max_length:
				continue
			var ma := mirror[a] if twins else -1
			var mb := mirror[b] if twins else -1
			# The twin pair, if it comes first, has done this one already.
			if ma >= 0 and mb >= 0 and mini(ma, mb) * points.size() + maxi(ma, mb) < a * points.size() + b:
				continue
			var fine: bool = near.call(pa, pb)
			var both := _profile_both(pa, pb, surface, blocked, step if fine else coarse_step, fine)
			_add_pair(a, b, both)
			if ma >= 0 and mb >= 0 and not (ma == a and mb == b) and not (ma == b and mb == a):
				_add_pair(ma, mb, both)


func _add_pair(a: int, b: int, both: Array) -> void:
	var there: Dictionary = both[0]
	var back: Dictionary = both[1]
	if not there.is_empty() and (not _check_existing or link_between(a, b) == null):
		add_link(a, b, there.kind, there.must_jet, there.steep)
	if not back.is_empty() and (not _check_existing or link_between(b, a) == null):
		add_link(b, a, back.kind, back.must_jet, back.steep)


## _profile() both ways along a straight line, from one set of samples, as
## [a to b, b to a].
static func _profile_both(a: Vector3, b: Vector3, surface: Callable, blocked: Callable, step: float, with_sides: bool) -> Array:
	var flat := Vector2(b.x - a.x, b.z - a.z)
	var count := maxi(int(ceil(flat.length() / step)), 1)
	var gap := flat.length() / count
	var side := Vector2(-flat.y, flat.x).normalized() * SIDE_CHECK
	var lines := 3 if with_sides else 1
	var middle := 1 if with_sides else 0
	var stuck := PackedByteArray()
	stuck.resize(count + 1)
	var heights: Array[PackedFloat32Array] = []
	for line in lines:
		var row := PackedFloat32Array()
		row.resize(count + 1)
		heights.append(row)
	for k in count + 1:
		var t := float(k) / count
		var x := lerpf(a.x, b.x, t)
		var z := lerpf(a.z, b.z, t)
		stuck[k] = 1 if (k > 0 and k < count and blocked.call(x, z)) else 0
		for line in lines:
			var off := side * (line - middle)
			heights[line][k] = surface.call(x + off.x, z + off.y)
	if blocked.call(b.x, b.z):
		stuck[count] = 1
	if blocked.call(a.x, a.z):
		stuck[0] = 1
	heights[middle][0] = a.y
	heights[middle][count] = b.y
	return [_walk(heights, stuck, middle, count, gap, a.y, b.y, flat.length(), true), _walk(heights, stuck, middle, count, gap, b.y, a.y, flat.length(), false)]


static func _walk(heights: Array[PackedFloat32Array], stuck: PackedByteArray, middle: int, count: int, gap: float, start: float, end: float, length: float, forward: bool) -> Dictionary:
	var lines := heights.size()
	var last := PackedFloat32Array()
	var last_rise := PackedFloat32Array()
	last.resize(lines)
	last_rise.resize(lines)
	last.fill(start)
	var must_jet := false
	var steep := 0.0
	for n in range(1, count + 1):
		var k := n if forward else count - n
		if stuck[k] != 0:
			return {}
		for line in lines:
			var h := heights[line][k]
			var rise := h - last[line]
			if (n < count or line == middle) and n > 1 and rise / gap > WALL_SLOPE and rise - last_rise[line] > WALL_KINK and last_rise[line] / gap > -0.3:
				must_jet = true
			if line == middle and rise / gap > STEEP_SLOPE:
				steep += rise
			last_rise[line] = rise
			last[line] = h
	var slope := (end - start) / maxf(length, 0.01)
	var kind := Kind.RUN
	if must_jet or slope > JET_SLOPE:
		kind = Kind.JET
	elif slope < SKI_SLOPE:
		kind = Kind.SKI
	return { "kind": kind, "must_jet": must_jet, "steep": snappedf(steep, 0.1) }


## How a straight way from a to b goes: its kind and whether it has a wall,
## or an empty dictionary if it's blocked.
static func _profile(a: Vector3, b: Vector3, surface: Callable, blocked: Callable, step: float) -> Dictionary:
	var flat := Vector2(b.x - a.x, b.z - a.z)
	var count := maxi(int(ceil(flat.length() / step)), 1)
	var gap := flat.length() / count
	# Walls are looked for a little to each side too, since a bot doesn't
	# keep exactly to the line.
	var side := Vector2(-flat.y, flat.x).normalized() * SIDE_CHECK
	var last := [a.y, a.y, a.y]
	var last_rise := [0.0, 0.0, 0.0]
	var must_jet := false
	var steep := 0.0
	for k in range(1, count + 1):
		var t := float(k) / count
		var x := lerpf(a.x, b.x, t)
		var z := lerpf(a.z, b.z, t)
		if blocked.call(x, z):
			return {}
		for line in 3:
			var off := side * (line - 1)
			var h: float = b.y if k == count and line == 1 else surface.call(x + off.x, z + off.y)
			var rise: float = h - last[line]
			# A wall is a sudden step up from fairly level ground, too steep to
			# stand on. Steep hillsides and valley bottoms can be skied up.
			if (k < count or line == 1) and k > 1 and rise / gap > WALL_SLOPE and rise - last_rise[line] > WALL_KINK and last_rise[line] / gap > -0.3:
				must_jet = true
			if line == 1 and rise / gap > STEEP_SLOPE:
				steep += rise
			last_rise[line] = rise
			last[line] = h
	var slope := (b.y - a.y) / maxf(flat.length(), 0.01)
	var kind := Kind.RUN
	if must_jet or slope > JET_SLOPE:
		kind = Kind.JET
	elif slope < SKI_SLOPE:
		kind = Kind.SKI
	return { "kind": kind, "must_jet": must_jet, "steep": snappedf(steep, 0.1) }


func to_dict() -> Dictionary:
	var link_data := []
	for link in links:
		link_data.append([link.from, link.to, KIND_NAMES[link.kind], link.must_jet, link.steep])
	return { "points": Array(points), "links": link_data, "interest": interest.duplicate(true) }


static func from_dict(data: Dictionary) -> RouteGraph:
	var graph := RouteGraph.new()
	for p: Vector3 in data.points:
		graph.add_point(p)
	for entry: Array in data.links:
		graph.add_link(entry[0], entry[1], KIND_NAMES.find(entry[2]) as Kind, entry[3], entry[4])
	for entry: Dictionary in data.interest:
		graph.add_interest(entry.kind, entry.team, entry.point)
	return graph
