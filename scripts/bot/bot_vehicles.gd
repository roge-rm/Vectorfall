class_name BotVehicles
extends RefCounted

## The commander assigns crews on the main thread. A bot on foot still
## routes and steers itself, using the assigned hull's last position.
const ASSIGN_TICKS := 30
const BOARD_TICKS := 45 * 60
const TAKEOFF_WAIT := 7 * 60
const FOOT_SUPPORT_TICKS := 18 * 60
const COVER_WAIT_TICKS := 12 * 60
const INTERCEPT_BOARD_TICKS := 4 * 60
const INTERCEPT_PAD_REACH := 20.0

enum Departure { WAIT, LAUNCH, ABORT }

var director: BotDirector
var ferry := BotFerry.new()
var combat := BotCombatVehicles.new()
var jobs: Dictionary = {}
var positions: Dictionary[int, Vector3] = {}
var missions: Dictionary = {}
var delivered: Dictionary = {}
var _board_now: Dictionary[int, int] = {}
var boarded_since: Dictionary[int, int] = {}


func _init(owner: BotDirector) -> void:
	director = owner


func update() -> void:
	var game := director.game
	if game.fleet.pads.is_empty():
		return
	_update_delivered(game)
	if not jobs.is_empty():
		_prune_jobs(game)
	if game.tick % ASSIGN_TICKS == 1:
		_assign(game)
	positions.clear()
	_board_now.clear()
	for id: int in jobs:
		var job: Dictionary = jobs[id]
		var hull: Vehicle = game.fleet.hulls[job.hull]
		positions[id] = hull.position
		if hull.open_seat() == int(job.get("seat", hull.open_seat())):
			_board_now[id] = hull.entity_id


func _prune_jobs(game: Match) -> void:
	for id: int in jobs.keys():
		var job: Dictionary = jobs[id]
		var brain := director.brain_of(id)
		var hull: Vehicle = game.fleet.hulls.get(job.hull)
		var boss := director.commander(brain.soldier.team) if brain != null else null
		if boss == null or not _available_at_pad(game, hull) or game.tick >= job.until or not _crew_candidate(boss, brain, mission_kind(hull)):
			jobs.erase(id)
			continue
		var seat: int = job.get("seat", hull.open_seat())
		if hull.crew[seat] != 0 or (hull.crew[0] != 0 and boss.is_person(hull.crew[0])):
			jobs.erase(id)


func _assign(game: Match) -> void:
	ferry.prune(game)
	combat.prune(game)
	for id in boarded_since.keys():
		if not game.fleet.hulls.has(id) or game.fleet.hulls[id].empty():
			boarded_since.erase(id)
	for id: int in missions.keys():
		var hull: Vehicle = game.fleet.hulls.get(id)
		if hull == null:
			_cancel_mission(id)
			continue
		var boss := director.commander(hull.team)
		if boss == null or (hull.empty() and not _has_pilot_reservation(id)) or (hull.crew[0] != 0 and boss.is_person(hull.crew[0])):
			_cancel_mission(id)
		elif hull.kind == Vehicle.Kind.TRANSPORT and _near_pad(game, hull):
			var runner := game.soldier(missions[id].target)
			var enemy_flag: Flag = game.flags.get(1 - hull.team)
			if runner == null or runner.dead or enemy_flag == null or enemy_flag.mode == Flag.Mode.CARRIED:
				_cancel_mission(id)
		elif hull.kind == Vehicle.Kind.GUNSHIP:
			var target := _gunship_target(boss, _attacking_runner(boss))
			var mission: Dictionary = missions[id]
			if target != null:
				var intercept := target.team != hull.team
				if intercept and mission.kind != "intercept" and hull.crew[0] == 0:
					_cancel_mission(id)
					continue
				mission.target = target.entity_id
				mission.kind = "intercept" if intercept else "cover"
				if hull.crew[0] != 0:
					mission.hold_until = game.tick + COVER_WAIT_TICKS
			elif _near_pad(game, hull):
				_cancel_mission(id)
			else:
				mission.target = 0
				mission.kind = "hold" if game.tick < int(mission.get("hold_until", 0)) else "return"
		elif hull.kind == Vehicle.Kind.TANK:
			var threats := boss.threats(145.0)
			if threats.is_empty():
				_cancel_mission(id)
			else:
				missions[id].target = threats[0][0]
				missions[id].objective = threats[0][1]
		elif hull.kind == Vehicle.Kind.BOMBER:
			var target_id: int = missions[id].target
			var turret := game.asset(target_id if target_id != 0 else boss._flag_turret())
			if turret == null or turret.destroyed or not game.powered(turret.team):
				_cancel_mission(id)
	for team in 2:
		var boss := director.commander(team)
		if boss != null and game.stands.has(team) and game.stands.has(1 - team):
			_assign_team(boss)


func _assign_team(boss: TeamCommander) -> void:
	var crew := boss.brains()
	var living := 0
	var reserved := 0
	for brain: BotBrain in crew:
		if brain.soldier.dead:
			continue
		living += 1
		if brain.soldier.vehicle_id != 0 or jobs.has(brain.soldier.entity_id):
			reserved += 1
	# Leave at least half the living bots on foot and don't crew at all while
	# the team is down to its runner and a defender.
	var budget := floori(living * 0.5) - reserved if living >= 3 else 0
	var runner := _attacking_runner(boss)
	var target := _gunship_target(boss, runner)
	var carrier := boss.vehicle_carrier()
	if carrier != null and budget > 0:
		budget -= _start_mission(boss, Vehicle.Kind.GUNSHIP, "intercept", carrier.at(), carrier.entity_id, 1, 1, INTERCEPT_PAD_REACH)

	var enemy_flag: Flag = boss.game.flags.get(1 - boss.team)
	if runner != null and budget >= 2 and living >= 5 and enemy_flag != null and enemy_flag.mode != Flag.Mode.CARRIED:
		var approach := boss.vehicle_destination(Vehicle.Kind.TRANSPORT)
		if boss.lanes != null and boss.lanes.in_lanes(runner.at()):
			var lane := boss.lanes.lane_of(runner.at())
			var lane_end := boss.lanes.approach(1 - boss.team, lane)
			approach.z = lane_end.z
		budget -= _start_mission(boss, Vehicle.Kind.TRANSPORT, "deliver", approach, runner.entity_id, 2, 2, 265.0)

	if target != null and target.team == boss.team and budget > 0:
		budget -= _start_mission(boss, Vehicle.Kind.GUNSHIP, "cover", target.at(), target.entity_id, 1, 1, 265.0)
	if budget <= 0:
		return
	var threats := boss.threats(145.0)
	if not threats.is_empty():
		var contact: Array = threats[0]
		budget -= _start_mission(boss, Vehicle.Kind.TANK, "support", contact[1], contact[0], 1, 1, 95.0)
	if budget <= 0 or runner == null or enemy_flag == null or enemy_flag.mode != Flag.Mode.HOME:
		return
	var turret := boss.game.asset(boss._flag_turret())
	if turret != null and not turret.destroyed:
		budget -= _start_mission(boss, Vehicle.Kind.BOMBER, "support", turret.pivot(), turret.entity_id, 1, 1, 95.0)
	if budget > 0:
		_start_mission(boss, Vehicle.Kind.BIKE, "support", boss.vehicle_destination(Vehicle.Kind.BIKE), runner.entity_id, 1, 1, 70.0)


func _attacking_runner(boss: TeamCommander) -> Soldier:
	if not boss.game.stands.has(boss.team) or not boss.game.stands.has(1 - boss.team):
		return null
	var forward := signf(boss.game.stands[1 - boss.team].x - boss.game.stands[boss.team].x)
	for brain: BotBrain in boss.brains():
		var runner := brain.soldier
		if not brain.is_flag_runner() or runner.dead or runner.vehicle_id != 0:
			continue
		if brain.attacking or brain.goal == BotBrain.Goal.TAKE_FLAG or (brain.goal == BotBrain.Goal.RALLY and runner.vel().x * forward > 3.0):
			return runner
	return null


func _gunship_target(boss: TeamCommander, runner: Soldier) -> Soldier:
	var carrier := boss.vehicle_carrier()
	if carrier != null:
		return carrier
	var flag: Flag = boss.game.flags.get(1 - boss.team)
	if flag != null and flag.mode == Flag.Mode.CARRIED:
		return boss.game.soldier(flag.carrier_id)
	return runner


func _at_pad(game: Match, team: int, kind: Vehicle.Kind) -> Vehicle:
	for pad: VehiclePad in game.fleet.pads.values():
		if pad.team != team or pad.kind != kind:
			continue
		var hull: Vehicle = game.fleet.hulls.get(pad.hull_id)
		if _available_at_pad(game, hull) and hull.empty() and not missions.has(hull.entity_id):
			return hull
	return null


func _near_pad(game: Match, hull: Vehicle) -> bool:
	if hull == null:
		return false
	var pad: VehiclePad = game.fleet.pads.get(hull.pad_id)
	return pad != null and hull.position.distance_squared_to(pad.position) < 64.0


func _available_at_pad(game: Match, hull: Vehicle) -> bool:
	return _near_pad(game, hull) and hull.open_seat() >= 0


func _has_reservation(hull_id: int) -> bool:
	for job: Dictionary in jobs.values():
		if job.hull == hull_id:
			return true
	return false


func _has_pilot_reservation(hull_id: int) -> bool:
	for job: Dictionary in jobs.values():
		if job.hull == hull_id and int(job.get("seat", 0)) == 0:
			return true
	return false


func _cancel_mission(hull_id: int) -> void:
	missions.erase(hull_id)
	for id: int in jobs.keys():
		if jobs[id].hull == hull_id:
			jobs.erase(id)


func _crew_candidate(boss: TeamCommander, brain: BotBrain, job_kind: String) -> bool:
	var who := brain.soldier
	var id := who.entity_id
	var regular_crew := brain.role in [BotBrain.Role.OFFENCE, BotBrain.Role.MIDFIELD]
	var intercept_crew := job_kind == "intercept" and brain.role in [BotBrain.Role.LIGHT_DEFENCE, BotBrain.Role.CHASE]
	return (regular_crew or intercept_crew) and not who.dead and who.vehicle_id == 0 and not brain.is_flag_runner() and not boss.order_locks.has(id) and not delivered.has(id) and boss.game.carried_flag(id) == null


func _start_mission(boss: TeamCommander, kind: Vehicle.Kind, job_kind: String, objective: Vector3, target: int, minimum: int, want: int, reach: float) -> int:
	var hull := _at_pad(boss.game, boss.team, kind)
	if hull == null or not objective.is_finite():
		return 0
	var crew: Array[BotBrain] = []
	for brain: BotBrain in boss.brains():
		if jobs.has(brain.soldier.entity_id) or not _crew_candidate(boss, brain, job_kind):
			continue
		if brain.soldier.at().distance_squared_to(hull.position) < reach * reach:
			crew.append(brain)
	crew.sort_custom(func(a: BotBrain, b: BotBrain) -> bool:
		var da := a.soldier.at().distance_squared_to(hull.position)
		var db := b.soldier.at().distance_squared_to(hull.position)
		return da < db or (da == db and a.soldier.entity_id < b.soldier.entity_id))
	var count := mini(want, crew.size())
	if count < minimum:
		return 0
	var deadline := boss.game.tick + (INTERCEPT_BOARD_TICKS if job_kind == "intercept" else BOARD_TICKS)
	missions[hull.entity_id] = {"kind": job_kind, "objective": objective, "target": target, "deadline": deadline}
	for seat in count:
		jobs[crew[seat].soldier.entity_id] = {"hull": hull.entity_id, "until": deadline, "seat": seat}
	return count


func mission_kind(hull: Vehicle) -> String:
	return missions.get(hull.entity_id, {}).get("kind", "")


func mission_objective(hull: Vehicle, boss: TeamCommander) -> Vector3:
	var mission: Dictionary = missions.get(hull.entity_id, {})
	if hull.kind == Vehicle.Kind.GUNSHIP:
		var focus := _live_gunship_target(hull, boss)
		if focus != null:
			if focus.team == hull.team:
				var home: Vector3 = boss.game.stands[hull.team]
				return focus.at() + BotCombatVehicles.flat(home - focus.at()).limit_length(70.0)
			return focus.at()
		return boss.vehicle_destination(hull.kind)
	return mission.get("objective", boss.vehicle_destination(hull.kind))


func _live_gunship_target(hull: Vehicle, boss: TeamCommander) -> Soldier:
	var carrier := boss.vehicle_carrier()
	if carrier != null and not carrier.dead:
		return carrier
	var mission: Dictionary = missions.get(hull.entity_id, {})
	var target := boss.game.soldier(mission.get("target", 0))
	return target if target != null and not target.dead and target.team == hull.team else null


func ferry_departure(hull: Vehicle) -> Departure:
	var game := director.game
	if not _near_pad(game, hull):
		return Departure.LAUNCH
	var mission: Dictionary = missions.get(hull.entity_id, {})
	var has_passenger := hull.crew.count(0) < hull.crew.size() - 1
	if mission.is_empty():
		return Departure.ABORT
	var boarded: int = boarded_since.get(hull.entity_id, game.tick)
	var deadline := mini(mission.deadline, boarded + TAKEOFF_WAIT)
	if game.tick < deadline and _has_reservation(hull.entity_id):
		return Departure.WAIT
	return Departure.LAUNCH if has_passenger else Departure.ABORT


func board_target(id: int) -> Vector3:
	return positions.get(id, Vector3.INF)


func is_intercept_job(id: int) -> bool:
	var job: Dictionary = jobs.get(id, {})
	return not job.is_empty() and missions.get(job.hull, {}).get("kind", "") == "intercept"


func foot_support(id: int) -> Dictionary:
	var job: Dictionary = delivered.get(id, {})
	return job if not job.is_empty() and job.hull == 0 else {}


func _update_delivered(game: Match) -> void:
	for id: int in delivered.keys():
		var job: Dictionary = delivered[id]
		var who := game.soldier(id)
		if who == null or who.dead or game.tick >= job.until:
			delivered.erase(id)
		elif job.hull != 0:
			if who.vehicle_id == 0 and game.fleet.hulls.has(job.hull):
				job.hull = 0
			else:
				delivered.erase(id)


func request_board(brain: BotBrain, command: PlayerCommand) -> void:
	if brain.goal != BotBrain.Goal.VEHICLE:
		return
	var id := brain.soldier.entity_id
	if brain.combat.fighting(brain) and not is_intercept_job(id):
		return
	var at := board_target(id)
	if at.distance_squared_to(brain.soldier.at()) <= 39.0 and _board_now.has(id) and brain.game.tick % 10 == 0:
		command.buttons |= PlayerCommand.BOARD
		command.board_id = _board_now[id]


func rider_command(brain: BotBrain) -> PlayerCommand:
	var who := brain.soldier
	var game := brain.game
	var hull: Vehicle = game.fleet.hulls.get(who.vehicle_id)
	var command := PlayerCommand.new()
	command.yaw = who.yaw
	command.pitch = who.pitch
	if hull == null:
		return command
	var boss := director.commander(who.team)
	var foot_order := boss.order_locks.has(who.entity_id)
	if hull.kind == Vehicle.Kind.TRANSPORT and who.vehicle_seat == 0:
		_ferry_pilot(hull, command, boss, foot_order)
		return command
	if hull.kind == Vehicle.Kind.TRANSPORT:
		var unplanned := mission_kind(hull).is_empty() or hull.crew[0] == 0
		var unload := ferry.passenger_exit(game, hull)
		if unload or ((unplanned or foot_order) and ferry.ready_to_exit(game, hull)):
			_exit(command, game.tick)
			if unload and not unplanned and not foot_order and command.has(PlayerCommand.BOARD):
				var trip: Dictionary = ferry.trips[hull.entity_id]
				if not trip.returning:
					var mission: Dictionary = missions[hull.entity_id]
					delivered[who.entity_id] = {"hull": hull.entity_id, "target": mission.target, "objective": mission.objective, "until": game.tick + FOOT_SUPPORT_TICKS}
			return command
	if foot_order and hull.kind != Vehicle.Kind.TRANSPORT:
		command.yaw = hull.yaw
		if who.vehicle_seat == 0 and hull.flies() and hull.position.y - game.fleet.ground_at(hull.position) > 3.5:
			command.buttons |= PlayerCommand.JUMP
		elif who.vehicle_seat > 0 or hull.velocity.length() <= Vehicle.BOARD_SPEED:
			_exit(command, game.tick)
		return command
	if mission_kind(hull).is_empty() and hull.kind in [Vehicle.Kind.TANK, Vehicle.Kind.BOMBER]:
		if who.vehicle_seat == 0 and hull.flies():
			ferry.pilot(hull, command, boss, Vector3.INF, true)
		elif who.vehicle_seat > 0 or hull.velocity.length() <= Vehicle.BOARD_SPEED:
			_exit(command, game.tick)
		return command
	var enemy: Soldier
	var objective: Vector3
	if hull.kind == Vehicle.Kind.GUNSHIP:
		var target := _live_gunship_target(hull, boss)
		var holding := mission_kind(hull) == "hold"
		if target == null and not holding:
			if who.vehicle_seat == 0:
				ferry.pilot(hull, command, boss, Vector3.INF, true)
			elif ferry.passenger_exit(game, hull) or (hull.crew[0] == 0 and ferry.ready_to_exit(game, hull)):
				_exit(command, game.tick)
			return command
		ferry.trips.erase(hull.entity_id)
		enemy = target if target == boss.vehicle_carrier() else null
		objective = mission_objective(hull, boss)
	else:
		objective = mission_objective(hull, boss)
	if objective == Vector3.INF:
		return command
	var from := hull.seat_eye(who.vehicle_seat)
	if enemy == null and mission_kind(hull) != "hold":
		enemy = _target(boss, from, 105.0)
	if who.vehicle_seat == 0:
		combat.pilot(hull, command, boss, enemy, objective)
	elif hull.kind != Vehicle.Kind.TRANSPORT and hull.crew[0] == 0:
		_exit(command, game.tick)
	if enemy != null and who.vehicle_seat > 0:
		if hull.kind == Vehicle.Kind.GUNSHIP:
			from = hull.to_global(Vehicle.MUZZLE[hull.kind])
			var aim := BotCombatVehicles.lead(from, enemy, Weapon.TURRET, hull.velocity)
			BotCombatVehicles.point_at(command, aim)
			if from.distance_squared_to(enemy.centre()) <= 95.0 * 95.0:
				BotCombatVehicles.fire_if_aligned(hull, command, boss, enemy, from, aim)
		elif from.distance_squared_to(enemy.centre()) <= 95.0 * 95.0 and director.take_ray() and game.line_clear(from, enemy.centre()):
			BotCombatVehicles.point_at(command, BotCombatVehicles.lead(from, enemy, who.weapon_slot(), hull.velocity, false))
			command.buttons |= PlayerCommand.FIRE
	return command


func _ferry_pilot(hull: Vehicle, command: PlayerCommand, boss: TeamCommander, foot_order: bool) -> void:
	var game := boss.game
	var objective := mission_objective(hull, boss)
	var returning := foot_order or mission_kind(hull).is_empty() or objective == Vector3.INF
	if _near_pad(game, hull) and not returning:
		if not boarded_since.has(hull.entity_id):
			boarded_since[hull.entity_id] = game.tick
		match ferry_departure(hull):
			Departure.WAIT:
				command.yaw = hull.yaw
				return
			Departure.ABORT:
				returning = true
	ferry.pilot(hull, command, boss, objective, returning)


func _target(boss: TeamCommander, from: Vector3, reach: float) -> Soldier:
	var best: Soldier
	for id: int in boss.known:
		var other := boss.game.soldier(id)
		if other == null or other.dead:
			continue
		var distance := from.distance_to(other.at())
		if distance < reach:
			best = other
			reach = distance
	return best


func _exit(command: PlayerCommand, tick: int) -> void:
	if tick % 8 == 0:
		command.buttons |= PlayerCommand.BOARD


func get_state() -> Dictionary:
	return {
		"jobs": jobs.duplicate(true), "missions": missions.duplicate(true),
		"delivered": delivered.duplicate(true),
		"ferry_trips": ferry.trips.duplicate(true), "boarded_since": boarded_since.duplicate(),
		"ground_progress": combat.ground_progress.duplicate(), "combat_probes": combat.probes.duplicate(true),
		"bombing": combat.bombing.duplicate(true), "tank_sight": combat.tank_sight.duplicate(true),
	}


func set_state(state: Dictionary) -> void:
	jobs = state.get("jobs", {}).duplicate(true)
	missions = state.get("missions", {}).duplicate(true)
	delivered = state.get("delivered", {}).duplicate(true)
	ferry.trips = state.get("ferry_trips", {}).duplicate(true)
	boarded_since.assign(state.get("boarded_since", {}))
	combat.ground_progress = state.get("ground_progress", {}).duplicate()
	combat.probes = state.get("combat_probes", {}).duplicate(true)
	combat.bombing = state.get("bombing", {}).duplicate(true)
	combat.tank_sight = state.get("tank_sight", {}).duplicate(true)
	positions.clear()
	_board_now.clear()
