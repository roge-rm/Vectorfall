class_name TeamCalls
extends RefCounted

const LIFETIME := 22 * 60
const CALL_GAP := 5 * 60
const SAME_KIND_GAP := 4 * 60
const COVER_REACH := 75.0

# One active marker per kind and team keeps the map readable in a full match.
var by_team := {}
var _last_sent := {}
var _next_id := 1


func active(team: int) -> Dictionary:
	return by_team.get(team, {})


func can_send(game: Match, sender: Soldier, kind: int) -> bool:
	if sender.dead or game.over or game.arena == null:
		return false
	match kind:
		Orders.Kind.FLAG_RUN:
			return game.stands.has(1 - sender.team) and game.hold_points.is_empty()
		Orders.Kind.COVER_EXIT:
			return true
		Orders.Kind.REPAIR_GENERATOR:
			return game.generator(sender.team) != null
	return false


func latest(viewer: Soldier, unacknowledged := false) -> Dictionary:
	var latest := {}
	for call: Dictionary in active(viewer.team).values():
		if unacknowledged and (call.by == viewer.entity_id or viewer.entity_id in call.acks):
			continue
		if latest.is_empty() or call.id > latest.id:
			latest = call
	return latest


func apply(game: Match, sender: Soldier, command: PlayerCommand) -> void:
	if game.over or sender == null or sender.dead or game.sources.get(sender.entity_id) is BotBrain:
		return
	if command.order == Orders.Kind.ACK_CALL:
		_acknowledge(sender, command.order_arg)
		return
	var kind := command.order
	if not can_send(game, sender, kind) or game.tick - int(_last_sent.get(sender.entity_id, -CALL_GAP)) < CALL_GAP:
		return
	var calls := active(sender.team)
	var previous: Dictionary = calls.get(kind, {})
	if not previous.is_empty() and game.tick - int(previous.started) < SAME_KIND_GAP:
		return
	var point := _target(game, sender, command)
	var bounds := game.arena.tactical_bounds()
	if not point.is_finite() or not bounds.has_point(Vector2(point.x, point.z)):
		return
	calls[kind] = {"id": _next_id, "kind": kind, "by": sender.entity_id, "at": point,
		"started": game.tick, "acks": PackedInt32Array()}
	by_team[sender.team] = calls
	_next_id += 1
	_last_sent[sender.entity_id] = game.tick


func _target(game: Match, sender: Soldier, command: PlayerCommand) -> Vector3:
	match command.order:
		Orders.Kind.FLAG_RUN:
			return game.stands[1 - sender.team]
		Orders.Kind.REPAIR_GENERATOR:
			return game.generator(sender.team).centre()
		Orders.Kind.COVER_EXIT:
			var origin := sender.eye_transform().origin
			var aim := Basis.from_euler(Vector3(command.pitch, command.yaw, 0.0))
			var hit := game.world_ray(origin, origin - aim.z * COVER_REACH, Match.WORLD_LAYER)
			return hit.get("position", sender.at())
	return Vector3.INF


func _acknowledge(sender: Soldier, id: int) -> void:
	for call: Dictionary in active(sender.team).values():
		if call.id == id and call.by != sender.entity_id and sender.entity_id not in call.acks \
				and call.acks.size() < MatchProtocol.MAX_TEAM_SIZE - 1:
			var acks: PackedInt32Array = call.acks
			acks.append(sender.entity_id)
			call.acks = acks
			return


func expire(tick: int, over: bool) -> void:
	for team: int in by_team.keys():
		var calls: Dictionary = by_team[team]
		for kind: int in calls.keys():
			if over or tick - int(calls[kind].started) >= LIFETIME:
				calls.erase(kind)
		if calls.is_empty():
			by_team.erase(team)


func change_occupant(who: Soldier) -> void:
	_last_sent.erase(who.entity_id)
	var calls := active(who.team)
	for kind: int in calls.keys():
		var call: Dictionary = calls[kind]
		if call.by == who.entity_id:
			calls.erase(kind)
		else:
			var acks: PackedInt32Array = call.acks
			var index := acks.find(who.entity_id)
			if index >= 0:
				acks.remove_at(index)
				call.acks = acks


func get_state() -> Dictionary:
	return {"teams": by_team.duplicate(true), "next_id": _next_id, "last_sent": _last_sent.duplicate()}


func set_state(state: Dictionary) -> void:
	by_team = state.get("teams", {}).duplicate(true)
	_next_id = state.get("next_id", 1)
	_last_sent = state.get("last_sent", {}).duplicate()
