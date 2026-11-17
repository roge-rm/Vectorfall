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
	for a in points.size():
		for b in points.size():
			if a == b:
				continue
			var pa := points[a]
			var pb := points[b]
			var flat := Vector2(pb.x - pa.x, pb.z - pa.z)
			if flat.length() > max_length or link_between(a, b) != null:
				continue
			var profile := _profile(pa, pb, surface, blocked, step)
			if profile.is_empty():
				continue
			add_link(a, b, profile.kind, profile.must_jet, profile.steep)


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
