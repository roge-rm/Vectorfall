class_name Lanes
extends RefCounted

## The ways across a map from base to base, for the commanders' learning: one
## lane per flag approach (on Ochre Fold the spine, the front and the canyon),
## told apart by how far north or south a spot is, since bases face each other
## along x. Maps without flag approaches get three lanes 60 m apart.

## Spots closer than this to a stand are in the base, not a lane, in metres.
const BASE_RANGE := 120.0

var count := 0
## Each lane's middle in z, north (−z) to south.
var middles := PackedFloat32Array()
## Team to its flag's approach point in each lane, north to south.
var approaches := {}
var stands := {}
var names: Array[String] = []
## What bots call each lane when they talk: the map's own names if its route
## graph has one for each lane, or "north lane" and the like.
var titles: Array[String] = []
## Each lane's route graph links, those with their middle away from the bases.
var lane_links: Array[Array] = []


func _init(graph: RouteGraph, stand_points: Dictionary) -> void:
	var teams := stand_points.keys()
	teams.sort()
	for team: int in teams:
		stands[team] = stand_points[team]
	for team: int in teams:
		var found: Array[Vector3] = []
		for point in graph.interest_points(RouteGraph.FLAG_APPROACH, team):
			if graph.interest.any(func(e: Dictionary) -> bool: return e.point == point and e.team == team):
				found.append(graph.points[point])
		if found.size() < 2:
			found.clear()
			var stand: Vector3 = stands[team]
			var other: Vector3 = stands.get(1 - team, Vector3.ZERO)
			var ahead := 1.0 if other.x >= stand.x else -1.0
			for z in [-60.0, 0.0, 60.0]:
				found.append(Vector3(stand.x + ahead * 100.0, stand.y, stand.z + z))
		found.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z < b.z)
		approaches[team] = found
	if teams.is_empty():
		return
	count = approaches[teams[0]].size()
	for team: int in teams:
		count = mini(count, approaches[team].size())
	middles.resize(count)
	for k in count:
		var z := 0.0
		for team: int in teams:
			z += approaches[team][k].z / teams.size()
		middles[k] = z
	names.assign(["north", "middle", "south"] if count == 3 else range(count).map(func(k: int) -> String: return "lane %d" % k))
	if graph.lane_titles.size() == count:
		titles.assign(graph.lane_titles)
	else:
		titles.assign(names.map(func(n: String) -> String: return n if n.begins_with("lane") else n + " lane"))
	for k in count:
		lane_links.append([])
	for link: RouteGraph.Link in graph.links:
		var mid := (graph.points[link.from] + graph.points[link.to]) * 0.5
		if in_lanes(mid):
			lane_links[lane_of(mid)].append(link)


## The lane a spot is in, by its z.
func lane_of(at: Vector3) -> int:
	var best := 0
	var best_d := INF
	for k in count:
		var d := absf(at.z - middles[k])
		if d < best_d:
			best_d = d
			best = k
	return best


## True away from both bases, where a lane means something.
func in_lanes(at: Vector3) -> bool:
	for team: int in stands:
		var stand: Vector3 = stands[team]
		if Vector2(at.x - stand.x, at.z - stand.z).length() < BASE_RANGE:
			return false
	return true


## A team's flag approach in a lane.
func approach(team: int, lane: int) -> Vector3:
	return approaches[team][clampi(lane, 0, count - 1)]


func name_of(lane: int) -> String:
	return names[lane] if lane >= 0 and lane < names.size() else "?"


func title_of(lane: int) -> String:
	return titles[lane] if lane >= 0 and lane < titles.size() else "?"
