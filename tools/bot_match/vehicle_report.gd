extends RefCounted

## Observe completed simulation ticks without changing vehicle decisions.
const SAMPLE_TICKS := 15
const STALL_TICKS := 600

var _game: Match
var _director: BotDirector
var _reservations := {}
var _riders := {}
var _trips := {}
var _delivered := {}
var _events: Array[Dictionary] = []
var _finished: Array[Dictionary] = []
var _last_kill_weapon := -1
var totals := {
	"reservations": 0, "reservations_boarded": 0, "launches": 0, "ferry_launches": 0,
	"empty_ferry_launches": 0, "ferry_passengers_delivered": 0,
	"confirmed_enemy_end_drops": 0, "delivered_passengers_reached_attack": 0,
	"interception_attempts": 0, "interceptions_in_range": 0,
	"interception_shots": 0, "interception_hits": 0, "interception_stops": 0,
	"failed_landings": 0, "ground_stalls": 0, "tank_holds": 0, "objectives_reached": 0,
}


func _init(game: Match, director: BotDirector) -> void:
	_game = game
	_director = director
	game.fired.connect(_on_fired)
	game.hit.connect(_on_hit)
	game.killed.connect(_on_killed)
	game.carrier_stopped.connect(_on_carrier_stopped)


func _gunship_for(id: int) -> Vehicle:
	var who := _game.soldier(id)
	var hull: Vehicle = _game.fleet.hulls.get(who.vehicle_id) if who != null else null
	return hull if hull != null and hull.kind == Vehicle.Kind.GUNSHIP else null


func _on_fired(id: int, weapon: int) -> void:
	if weapon != Weapon.TURRET:
		return
	var hull := _gunship_for(id)
	if hull != null and _director.commander(hull.team).vehicle_carrier() != null:
		totals.interception_shots += 1


func _on_hit(attacker: int, victim: int, weapon: int) -> void:
	if weapon == Weapon.TURRET and _game.soldier(attacker) != null and _game.carried_flag(victim) != null:
		totals.interception_hits += 1


func _on_killed(_victim: int, _attacker: int, weapon: int) -> void:
	_last_kill_weapon = weapon


func _on_carrier_stopped(_victim: int, attacker: int) -> void:
	# Match emits this immediately after the kill.
	if _last_kill_weapon == Weapon.TURRET and _game.soldier(attacker) != null:
		totals.interception_stops += 1


func observe() -> void:
	for brain: BotBrain in _director.brains:
		var who := brain.soldier
		_observe_rider(who)
		_observe_reservation(who)
	for id: int in _trips.keys():
		var hull: Vehicle = _game.fleet.hulls.get(id)
		var trip: Dictionary = _trips[id]
		if hull == null or hull.crew[0] != trip.pilot:
			_finish(id, "destroyed" if hull == null else "pilot_left")
	for hull: Vehicle in _game.fleet.hulls.values():
		if hull.crew[0] == 0:
			continue
		if not _trips.has(hull.entity_id):
			_start(hull)
		if _game.tick % SAMPLE_TICKS == 0:
			_observe_trip(hull, _trips[hull.entity_id])
	if _game.tick % SAMPLE_TICKS == 0:
		_observe_attack_support()


func _observe_reservation(who: Soldier) -> void:
	var jobs := _director.vehicle_orders.jobs
	var job: Dictionary = jobs.get(who.entity_id, {})
	var old: Dictionary = _reservations.get(who.entity_id, {})
	if not old.is_empty() and (job.get("hull", 0) != old.hull or job.get("until", -1) != old.until or who.vehicle_id == old.hull):
		var outcome := "boarded" if who.vehicle_id == old.hull else "cancelled"
		if outcome == "boarded":
			totals.reservations_boarded += 1
		elif who.dead:
			outcome = "died"
		elif _game.tick >= old.until:
			outcome = "expired"
		_events.append({"tick": _game.tick, "event": "reservation_ended", "soldier": who.entity_id,
			"hull": old.hull, "mission": old.mission, "result": outcome,
			"wait_seconds": (_game.tick - int(old.tick)) / 60.0})
		_reservations.erase(who.entity_id)
	if not job.is_empty() and who.vehicle_id == 0 and not _reservations.has(who.entity_id):
		var hull: Vehicle = _game.fleet.hulls.get(job.hull)
		if hull != null:
			totals.reservations += 1
			_reservations[who.entity_id] = {"tick": _game.tick, "until": job.until,
				"hull": job.hull, "mission": _mission(hull)}


func _observe_rider(who: Soldier) -> void:
	var old: Dictionary = _riders.get(who.entity_id, {})
	if not old.is_empty() and who.vehicle_id != old.hull:
		var hull: Vehicle = _game.fleet.hulls.get(old.hull)
		var trip: Dictionary = _trips.get(old.hull, {})
		var boss := _director.commander(who.team)
		var reason := "crew_exit"
		if who.dead:
			reason = "died"
		elif hull == null:
			reason = "hull_lost"
		elif boss.order_locks.has(who.entity_id):
			reason = "foot_order"
		elif old.kind == Vehicle.Kind.TRANSPORT and not trip.is_empty() and trip.landed:
			reason = "ferry_drop"
			if old.seat > 0 and _horizontal(who.position, _game.stands[1 - who.team]) <= 130.0:
				totals.ferry_passengers_delivered += 1
		elif not trip.is_empty() and trip.stalled:
			reason = "ground_stall"
		elif not trip.is_empty() and trip.reached:
			reason = "objective"
		var exit_event := {"tick": _game.tick, "event": "exit", "soldier": who.entity_id,
			"hull": old.hull, "vehicle": Vehicle.NAMES[old.kind], "seat": old.seat, "reason": reason,
			"position": [who.position.x, who.position.y, who.position.z]}
		if old.kind == Vehicle.Kind.TRANSPORT and hull != null:
			var height := hull.position.y - _game.fleet.ground_at(hull.position)
			var speed := hull.velocity.length()
			exit_event["hull_height"] = height
			exit_event["hull_speed"] = speed
			if old.seat > 0 and not who.dead and reason != "foot_order" and height <= 4.0 and speed <= 5.5:
				var stand: Vector3 = _game.stands[1 - who.team]
				if _horizontal(who.position, stand) <= 130.0:
					totals.confirmed_enemy_end_drops += 1
					_delivered[who.entity_id] = _game.tick
		_events.append(exit_event)
		_riders.erase(who.entity_id)
	if who.vehicle_id != 0 and not _riders.has(who.entity_id):
		var hull: Vehicle = _game.fleet.hulls.get(who.vehicle_id)
		if hull != null:
			_riders[who.entity_id] = {"hull": hull.entity_id, "kind": hull.kind, "seat": who.vehicle_seat}


func _observe_attack_support() -> void:
	for id: int in _delivered.keys():
		var who := _game.soldier(id)
		if who == null or who.dead or who.vehicle_id != 0 or _game.tick - int(_delivered[id]) > 45 * 60:
			_delivered.erase(id)
			continue
		var stand: Vector3 = _game.stands[1 - who.team]
		var reached := who.position.distance_to(stand) <= 60.0
		for brain: BotBrain in _director.commander(who.team).brains():
			var runner := brain.soldier
			if brain.is_flag_runner() and not runner.dead and runner.position.distance_to(stand) <= 130.0 and runner.position.distance_to(who.position) <= 60.0:
				reached = true
				break
		if reached:
			totals.delivered_passengers_reached_attack += 1
			_events.append({"tick": _game.tick, "event": "attack_reached", "soldier": id,
				"seconds_after_drop": (_game.tick - int(_delivered[id])) / 60.0})
			_delivered.erase(id)


func _mission(hull: Vehicle) -> String:
	var orders := _director.vehicle_orders
	if orders.has_method("mission_kind"):
		var name: String = orders.call("mission_kind", hull)
		if not name.is_empty():
			return name
	match hull.kind:
		Vehicle.Kind.TRANSPORT:
			return "ferry assault"
		Vehicle.Kind.GUNSHIP:
			return "intercept" if _director.commander(hull.team).vehicle_carrier() != null else "gunship cover"
		Vehicle.Kind.BOMBER:
			return "bombing"
		_:
			return "ground assault"


func _start(hull: Vehicle) -> void:
	_trips[hull.entity_id] = {
		"hull": hull.entity_id, "pilot": hull.crew[0], "team": hull.team, "kind": hull.kind,
		"vehicle": Vehicle.NAMES[hull.kind], "mission": _mission(hull), "start_tick": _game.tick,
		"launch_tick": -1, "passengers_at_launch": 0, "reached": false, "landing_approach": false,
		"landed": false, "stalled": false, "carrier": 0, "carrier_reached": false,
		"progress_at": hull.position, "progress_tick": _game.tick,
	}


func _observe_trip(hull: Vehicle, trip: Dictionary) -> void:
	var boss := _director.commander(hull.team)
	var pad: VehiclePad = _game.fleet.pads[hull.pad_id]
	var height := hull.position.y - _game.fleet.ground_at(hull.position) if hull.flies() else 0.0
	if trip.launch_tick < 0 and (_horizontal(pad.position, hull.position) > 12.0 or hull.position.y > pad.position.y + 12.0):
		trip.launch_tick = _game.tick
		trip.passengers_at_launch = hull.crew.size() - hull.crew.count(0) - 1
		totals.launches += 1
		if hull.kind == Vehicle.Kind.TRANSPORT:
			totals.ferry_launches += 1
			if trip.passengers_at_launch == 0:
				totals.empty_ferry_launches += 1
	if trip.launch_tick < 0:
		return
	var target := _objective(hull, boss)
	if target != Vector3.INF:
		var distance := _horizontal(hull.position, target)
		if not trip.reached and distance <= 24.0:
			trip.reached = true
			totals.objectives_reached += 1
		if hull.kind == Vehicle.Kind.TRANSPORT:
			trip.landing_approach = trip.landing_approach or distance <= 30.0
			trip.landed = trip.landed or (trip.landing_approach and distance < 30.0 and height <= 4.0 and hull.velocity.length() < 5.5)
	if not hull.flies():
		var orders := _director.vehicle_orders
		var holding := hull.kind == Vehicle.Kind.TANK and orders.mission_kind(hull) == "support" and not orders.combat.ground_progress.has(hull.entity_id)
		if holding and not trip.get("held", false):
			trip.held = true
			totals.tank_holds += 1
		if holding or _horizontal(hull.position, trip.progress_at) > 6.0:
			trip.progress_at = hull.position
			trip.progress_tick = _game.tick
		elif not trip.stalled and not trip.reached and _game.tick - int(trip.progress_tick) >= STALL_TICKS:
			trip.stalled = true
			totals.ground_stalls += 1
	if hull.kind == Vehicle.Kind.GUNSHIP:
		var carrier := boss.vehicle_carrier()
		var carrier_id := carrier.entity_id if carrier != null else 0
		if carrier_id != trip.carrier:
			trip.carrier = carrier_id
			trip.carrier_reached = false
			if carrier_id != 0:
				totals.interception_attempts += 1
		if carrier != null and not trip.carrier_reached and hull.position.distance_to(carrier.position) <= 90.0:
			trip.carrier_reached = true
			totals.interceptions_in_range += 1


func _objective(hull: Vehicle, boss: TeamCommander) -> Vector3:
	var orders := _director.vehicle_orders
	if not orders.has_method("mission_objective"):
		return boss.vehicle_destination(hull.kind)
	if hull.kind == Vehicle.Kind.TRANSPORT:
		var ferry: Variant = orders.get("ferry")
		if ferry != null:
			var trip: Dictionary = ferry.trips.get(hull.entity_id, {})
			var drop: Vector3 = trip.get("drop", Vector3.INF)
			if drop != Vector3.INF:
				return drop
	return orders.call("mission_objective", hull, boss)


func _finish(id: int, reason: String) -> void:
	var trip: Dictionary = _trips[id]
	_trips.erase(id)
	if trip.landing_approach and not trip.landed and reason != "time_limit":
		totals.failed_landings += 1
	trip["end_tick"] = _game.tick
	trip["end_reason"] = reason
	trip.erase("progress_at")
	trip.erase("progress_tick")
	_finished.append(trip)


func report() -> Dictionary:
	for id: int in _trips.keys():
		_finish(id, "time_limit")
	return {"totals": totals, "trips": _finished, "events": _events}


static func _horizontal(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
