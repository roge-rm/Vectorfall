class_name BotVehicles
extends RefCounted

## The commander assigns crews on the main thread. A bot on foot still
## routes and steers itself, using the assigned hull's last position.
const ASSIGN_TICKS := 30
const BOARD_TICKS := 45 * 60
const TAKEOFF_WAIT := 7 * 60
const GROUND_STALL_TICKS := 10 * 60

var director: BotDirector
var jobs: Dictionary = {}
var positions: Dictionary[int, Vector3] = {}
var boarded_since: Dictionary[int, int] = {}
var ground_progress: Dictionary[int, Vector2] = {}


func _init(owner: BotDirector) -> void:
	director = owner


func update() -> void:
	var game := director.game
	if game.fleet.pads.is_empty():
		return
	if game.tick % ASSIGN_TICKS == 1:
		_assign(game)
	positions.clear()
	for id: int in jobs:
		var hull: Vehicle = game.fleet.hulls.get(jobs[id].hull)
		if _available_at_pad(game, hull):
			positions[id] = hull.position


func _assign(game: Match) -> void:
	for id in boarded_since.keys():
		if not game.fleet.hulls.has(id) or game.fleet.hulls[id].empty():
			boarded_since.erase(id)
	for id in ground_progress.keys():
		if not game.fleet.hulls.has(id) or game.fleet.hulls[id].empty():
			ground_progress.erase(id)
	for id in jobs.keys():
		var brain := director.brain_of(id)
		var hull: Vehicle = game.fleet.hulls.get(jobs[id].hull)
		if brain == null or brain.soldier.dead or brain.is_flag_runner() or not _available_at_pad(game, hull) or brain.soldier.vehicle_id != 0 or game.tick >= jobs[id].until:
			jobs.erase(id)
	for team in 2:
		var boss := director.commander(team)
		if boss == null:
			continue
		var infantry := boss.brains().size()
		var reserved := 0
		for brain: BotBrain in boss.brains():
			if brain.soldier.vehicle_id != 0 or jobs.has(brain.soldier.entity_id):
				reserved += 1
		var budget := floori(infantry * 0.5) - reserved
		if budget <= 0:
			continue
		var gunship := _at_pad(game, team, Vehicle.Kind.GUNSHIP)
		if gunship != null:
			var seat_count := 2 if boss.vehicle_carrier() != null else 1
			budget -= _reserve(boss, gunship, mini(budget, seat_count), 265.0)
		var transport := _at_pad(game, team, Vehicle.Kind.TRANSPORT)
		if budget > 0 and infantry >= 5 and transport != null:
			budget -= _reserve(boss, transport, mini(budget, 3), 265.0)
		if budget <= 0:
			continue
		# Take another hull when an unassigned bot is already near its pad.
		for kind in [Vehicle.Kind.BIKE, Vehicle.Kind.TANK, Vehicle.Kind.BOMBER]:
			var hull := _at_pad(game, team, kind)
			if hull != null and _reserve(boss, hull, 1, 70.0) > 0:
				break


func _at_pad(game: Match, team: int, kind: Vehicle.Kind) -> Vehicle:
	for pad: VehiclePad in game.fleet.pads.values():
		if pad.team != team or pad.kind != kind:
			continue
		var hull: Vehicle = game.fleet.hulls.get(pad.hull_id)
		if _available_at_pad(game, hull):
			return hull
	return null


func _available_at_pad(game: Match, hull: Vehicle) -> bool:
	return hull != null and hull.open_seat() >= 0 and hull.position.distance_to(game.fleet.pads[hull.pad_id].position) < 8.0


func _reserve(boss: TeamCommander, hull: Vehicle, want: int, reach: float) -> int:
	for job: Dictionary in jobs.values():
		if job.hull == hull.entity_id:
			want -= 1
	var available := clampi(want, 0, hull.crew.count(0))
	var assigned := 0
	for seat in available:
		var best: BotBrain
		var best_distance := reach
		for brain: BotBrain in boss.brains():
			var who := brain.soldier
			if who.dead or who.vehicle_id != 0 or brain.is_flag_runner() or jobs.has(who.entity_id) or boss.order_locks.has(who.entity_id):
				continue
			var guard := hull.kind == Vehicle.Kind.GUNSHIP and brain.role == BotBrain.Role.LIGHT_DEFENCE
			if not guard and brain.role not in [BotBrain.Role.OFFENCE, BotBrain.Role.MIDFIELD]:
				continue
			if boss.game.carried_flag(who.entity_id) != null:
				continue
			var distance := who.at().distance_to(hull.position)
			var cost := distance - (50.0 if guard else 0.0)
			if distance < reach and cost < best_distance:
				best = brain
				best_distance = cost
		if best == null:
			break
		jobs[best.soldier.entity_id] = {"hull": hull.entity_id, "until": boss.game.tick + BOARD_TICKS}
		assigned += 1
	return assigned


func board_target(id: int) -> Vector3:
	return positions.get(id, Vector3.INF)


func request_board(brain: BotBrain, command: PlayerCommand) -> void:
	if brain.goal != BotBrain.Goal.VEHICLE or brain.combat.fighting(brain):
		return
	var id := brain.soldier.entity_id
	var at := board_target(id)
	if at.distance_squared_to(brain.soldier.at()) <= 39.0 and brain.game.tick % 10 == 0:
		command.buttons |= PlayerCommand.BOARD
		command.board_id = jobs[id].hull


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
	if boss.order_locks.has(who.entity_id):
		command.yaw = hull.yaw
		if who.vehicle_seat == 0 and hull.flies() and hull.position.y - game.fleet.ground_at(hull.position) > 3.5:
			command.buttons |= PlayerCommand.JUMP
		elif who.vehicle_seat > 0 or hull.velocity.length() <= Vehicle.BOARD_SPEED:
			_exit(command, game.tick)
		return command
	var enemy := boss.vehicle_carrier() if hull.kind == Vehicle.Kind.GUNSHIP else null
	var objective := boss.vehicle_destination(hull.kind)
	if objective == Vector3.INF:
		return command
	var from := hull.seat_eye(who.vehicle_seat)
	if enemy == null:
		enemy = _target(boss, from, 105.0)
	var to := objective - hull.position
	var horizontal := Vector2(to.x, to.z).length()
	if who.vehicle_seat == 0:
		_pilot(hull, command, boss, enemy, objective, horizontal)
	elif hull.crew[0] == 0 or (hull.kind == Vehicle.Kind.TRANSPORT and horizontal < 20.0 and hull.position.y - game.fleet.ground_at(hull.position) < 4.0):
		_exit(command, game.tick)
	if enemy != null and who.vehicle_seat > 0:
		var slot := Weapon.TURRET if hull.kind == Vehicle.Kind.GUNSHIP else who.weapon_slot()
		_aim(command, _lead(from, enemy, slot, hull.velocity))
		if from.distance_to(enemy.centre()) <= 95.0 and game.line_clear(from, enemy.centre()):
			command.buttons |= PlayerCommand.FIRE
	return command


func _pilot(hull: Vehicle, command: PlayerCommand, boss: TeamCommander, enemy: Soldier, objective: Vector3, distance: float) -> void:
	var game := boss.game
	var height := hull.position.y - game.fleet.ground_at(hull.position)
	var gunship := hull.kind == Vehicle.Kind.GUNSHIP
	var hunting := gunship and boss.vehicle_carrier() != null
	if hull.kind == Vehicle.Kind.TRANSPORT:
		if not boarded_since.has(hull.entity_id):
			boarded_since[hull.entity_id] = game.tick
		if game.tick - boarded_since[hull.entity_id] < TAKEOFF_WAIT and _waiting_for_crew(game, hull):
			command.yaw = hull.yaw
			return
	var to := objective - hull.position
	_aim(command, to)
	command.pitch = 0.0
	var brake := Vector2(hull.velocity.x, hull.velocity.z).length_squared() / (2.0 * Vehicle.ACCEL[hull.kind])
	var stop_distance := 34.0 if hunting else 11.0
	command.move.y = clampf((distance - stop_distance - brake * 0.65) / 28.0, 0.0, 1.0)
	if hull.flies():
		var landing := hull.kind == Vehicle.Kind.TRANSPORT and distance < 19.0
		var over_ground := hull.position + Vector3(to.x, 0.0, to.z).limit_length(36.0)
		var next_ground := game.fleet.ground_at(over_ground)
		var target_y := next_ground + (22.0 if gunship else 27.0)
		if landing or hull.position.y > target_y + 4.0:
			command.buttons |= PlayerCommand.JUMP
		elif hull.position.y < target_y or height < 16.0:
			command.buttons |= PlayerCommand.JET
		if not landing and height < 12.0:
			command.move.y *= 0.12
		if landing and height < 3.5 and hull.velocity.length() < 5.0:
			_exit(command, game.tick)
		if hull.kind == Vehicle.Kind.BOMBER and distance < 24.0 and height >= 14.0:
			command.buttons |= PlayerCommand.FIRE
	else:
		_ground_drive(hull, command, boss, distance, enemy != null)
	if gunship and hunting and distance < 22.0:
		command.move.y = -0.55
	if enemy != null and (hull.kind == Vehicle.Kind.TANK or (gunship and hull.weapon_seat() == 0)):
		var from := hull.to_global(Vehicle.MUZZLE[hull.kind])
		var range_to := from.distance_to(enemy.centre())
		if range_to < 90.0 and game.line_clear(from, enemy.centre()):
			var slot := Vehicle.WEAPONS[hull.kind]
			var aim := _lead(from, enemy, slot, hull.velocity)
			_aim(command, aim)
			if hull.kind == Vehicle.Kind.TANK:
				command.move.y = 0.0
			var barrel := BaseAsset.direction(hull.gun_yaw, hull.gun_pitch)
			if barrel.angle_to(aim) < 0.14:
				command.buttons |= PlayerCommand.FIRE


func _waiting_for_crew(game: Match, hull: Vehicle) -> bool:
	if hull.open_seat() < 0:
		return false
	for id: int in jobs:
		if jobs[id].hull == hull.entity_id and game.soldier(id).vehicle_id == 0:
			return true
	return false


func _ground_drive(hull: Vehicle, command: PlayerCommand, boss: TeamCommander, distance: float, fighting: bool) -> void:
	var game := boss.game
	var progress: Vector2 = ground_progress.get(hull.entity_id, Vector2(INF, game.tick))
	if distance < progress.x - 4.0 or fighting:
		progress = Vector2(distance, game.tick)
		ground_progress[hull.entity_id] = progress
	if distance < 17.0 or game.tick - int(progress.y) >= GROUND_STALL_TICKS:
		command.move = Vector2.ZERO
		if hull.velocity.length() < 5.0:
			_exit(command, game.tick)
		return
	var turn := 0.65 if hull.team == 0 else -0.65
	for offset: float in [0.0, turn, -turn, turn * 2.0, -turn * 2.0]:
		var yaw := command.yaw + offset
		var from := hull.position + Vector3.UP * 0.4
		var to := from + BaseAsset.direction(yaw, 0.0) * 11.0
		var hit := game.world_ray(from, to, Match.WORLD_LAYER | Match.ASSET_LAYER | Vehicle.HULL_LAYER, [hull.get_rid()])
		if hit.is_empty() or hit.normal.y > 0.68:
			command.yaw = yaw
			return
	command.move.y *= 0.2


func _target(boss: TeamCommander, from: Vector3, reach: float) -> Soldier:
	var best: Soldier
	for id: int in boss.known:
		var other := boss.game.soldier(id)
		if other == null or other.dead:
			continue
		var distance := from.distance_to(other.at())
		if distance < reach and boss.game.line_clear(from, other.centre()):
			best = other
			reach = distance
	return best


func _lead(from: Vector3, who: Soldier, slot: int, motion: Vector3) -> Vector3:
	var weapon := Weapon.all[slot]
	var fall := who.tuning.gravity if not who.grounded and not who.jetting and who.vehicle_id == 0 else 0.0
	return BotCombat.lead(from, motion, who.centre(), who.vel(), fall, weapon) - from


func _aim(command: PlayerCommand, to: Vector3) -> void:
	command.yaw = atan2(-to.x, -to.z)
	command.pitch = atan2(to.y, Vector2(to.x, to.z).length())


func _exit(command: PlayerCommand, tick: int) -> void:
	if tick % 8 == 0:
		command.buttons |= PlayerCommand.BOARD


func get_state() -> Dictionary:
	return {"jobs": jobs.duplicate(true), "boarded_since": boarded_since.duplicate(), "ground_progress": ground_progress.duplicate()}


func set_state(state: Dictionary) -> void:
	jobs = state.get("jobs", {}).duplicate(true)
	boarded_since.assign(state.get("boarded_since", {}))
	ground_progress.assign(state.get("ground_progress", {}))
	positions.clear()
