class_name DuoPanel
extends RefCounted

const PLUGIN := &"VectorfallDuo"
const REFRESH_SECONDS := 0.2

var _native: Object
var _game: Match
var _viewer: Soldier
var _bounds: Rect2
var _relief := ""
var _screen := ""
var _refresh_in := 0.0


func _init(game: Match, viewer: Soldier) -> void:
	_native = Engine.get_singleton(PLUGIN)
	_game = game
	_viewer = viewer
	_bounds = game.arena.tactical_bounds()


func update(delta: float) -> void:
	_refresh_in -= delta
	if _refresh_in > 0.0:
		return
	_refresh_in = REFRESH_SECONDS
	if not _native.call(&"isAvailable"):
		return
	if _game.over:
		if _screen != "results":
			_show(results_snapshot(_game, _viewer))
		return
	var snapshot := map_snapshot(_game, _viewer, _bounds)
	if _screen != "map":
		if _relief.is_empty():
			var image := TeamMap.Chart.relief_image(_game.arena, _bounds)
			_relief = Marshalls.raw_to_base64(image.save_png_to_buffer())
		snapshot["relief"] = _relief
	_show(snapshot)


func _show(snapshot: Dictionary) -> void:
	_screen = snapshot.type
	_native.call(&"setPanel", JSON.stringify(snapshot))


func clear() -> void:
	if not _screen.is_empty():
		_native.call(&"clearPanel")
		_screen = ""


static func map_snapshot(game: Match, viewer: Soldier, bounds: Rect2) -> Dictionary:
	var markers: Array[Dictionary] = []
	for who: Soldier in game.entities.values():
		if not game.tactical_soldier_visible(viewer, who):
			continue
		var friendly := who.team == viewer.team
		var kind := "you" if who == viewer else ("ally" if friendly else "contact")
		markers.append(_marker(bounds, who.at(), who.team, kind, who.display_name if friendly else ""))
		var waypoint: Dictionary = game.waypoints.get(who.entity_id, {})
		if friendly and not waypoint.is_empty():
			markers.append(_marker(bounds, waypoint.at, who.team, "waypoint", ""))
	for flag: Flag in game.flags.values():
		if game.tactical_flag_visible(viewer, flag):
			markers.append(_marker(bounds, flag.global_position, flag.team, "flag", ""))
	for point: HoldPoint in game.hold_points:
		var team := -1 if point.contested else point.owning_team
		markers.append(_marker(bounds, point.position, team, "hold", point.letter))
	return {
		"type": "map", "title": game.arena.title, "scores": game.scores,
		"seconds": int(ceil(maxf(game.time_left, 0.0))),
		"powers": [game.powered(0), game.powered(1)],
		"aspect": bounds.size.x / bounds.size.y, "markers": markers,
	}


static func _marker(bounds: Rect2, world: Vector3, team: int, kind: String, label: String) -> Dictionary:
	var at := ((Vector2(world.x, world.z) - bounds.position) / bounds.size).clamp(Vector2.ZERO, Vector2.ONE)
	return {"x": at.x, "y": at.y, "team": team, "kind": kind, "label": label}


static func results_snapshot(game: Match, viewer: Soldier) -> Dictionary:
	var rows: Array[Dictionary] = []
	for who: Soldier in game.entities.values():
		rows.append({
			"team": who.team, "name": "You" if who == viewer else who.display_name,
			"counts": game.results.counts.get(who.entity_id, MatchResults.empty_row()),
		})
	for previous in game.results.former:
		rows.append({"team": previous.team, "name": "%s (previous)" % previous.name, "counts": previous.counts})
	return {
		"type": "results", "title": game.arena.title, "scores": game.scores, "winner": game.winner,
		"hold": not game.hold_points.is_empty(), "rows": rows,
	}
