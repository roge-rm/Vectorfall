class_name BotCombatVehicles
extends RefCounted

## Navigation runs on the main thread before the rest of the bot's work.
const PROBE_TICKS := 12
const GROUND_STALL_TICKS := 10 * 60
const BOMB_LINEUP := 95.0
const BOMB_CLEAR := 110.0

enum BombPhase { LINE_UP, RUN, CLEAR }

var probes: Dictionary = {}
var ground_progress: Dictionary = {}
var bombing: Dictionary = {}
var tank_sight: Dictionary = {}


func prune(game: Match) -> void:
	for table: Dictionary in [probes, ground_progress, bombing, tank_sight]:
		for id: int in table.keys():
			var hull: Vehicle = game.fleet.hulls.get(id)
			if hull == null or hull.crew[0] == 0:
				table.erase(id)


func pilot(hull: Vehicle, command: PlayerCommand, boss: TeamCommander, enemy: Soldier, objective: Vector3) -> void:
	match hull.kind:
		Vehicle.Kind.GUNSHIP:
			_gunship(hull, command, boss, enemy, objective)
		Vehicle.Kind.BOMBER:
			_bomber(hull, command, boss, objective)
		_:
			_ground(hull, command, boss, enemy, objective)


func _gunship(hull: Vehicle, command: PlayerCommand, boss: TeamCommander, enemy: Soldier, objective: Vector3) -> void:
	var carrier := boss.vehicle_carrier()
	var direct := flat(objective - hull.position)
	var aim_point := objective
	if carrier != null:
		var lead_time := clampf(direct.length() / Vehicle.SPEED[hull.kind], 0.25, 2.0)
		aim_point += flat(carrier.vel()).limit_length(50.0) * lead_time
	var to := flat(aim_point - hull.position)
	var clearance := 24.0
	var stand_off := 42.0 if carrier != null else 32.0
	var near := to.length() < stand_off + 12.0
	var heading := to
	if near and to.length_squared() > 1.0:
		# Cross the target's path so the gunner keeps a view of it.
		var side := Vector3(-to.z, 0.0, to.x).normalized()
		var radius := clampf(to.length() - stand_off, -19.0, 19.0)
		heading = side * 28.0 + to.normalized() * radius
	course(hull, command, heading, heading.length(), 0.62 if near else 1.0)
	if enemy != null and hull.weapon_seat() == 0:
		# Without a gunner the fixed gun must follow the nose.
		var from := hull.to_global(Vehicle.MUZZLE[hull.kind])
		var aim := lead(from, enemy, Weapon.TURRET, hull.velocity)
		if from.distance_squared_to(enemy.centre()) < 95.0 * 95.0 and aim.y >= -flat(aim).length() * tan(0.9):
			point_at(command, aim)
			if enemy == carrier:
				var desired := flat(carrier.vel()) + direct.normalized() * clampf((direct.length() - stand_off) * 1.3, -22.0, 46.0)
				var local := Basis(Vector3.UP, hull.yaw).inverse() * desired / Vehicle.SPEED[hull.kind]
				var side := signf(local.x) if absf(local.x) > 0.12 else 1.0
				command.move = Vector2(side * maxf(absf(local.x) / 0.7, 0.32), maxf(-local.z, -0.32))
			elif near:
				command.move = Vector2(0.62, -0.28 if to.length() < 24.0 else 0.0)
			fire_if_aligned(hull, command, boss, enemy, from, aim)
	_flight(hull, command, boss, clearance)


func _bomber(hull: Vehicle, command: PlayerCommand, boss: TeamCommander, objective: Vector3) -> void:
	var state: Dictionary = bombing.get(hull.entity_id, {})
	if state.is_empty() or state.target.distance_squared_to(objective) > 20.0 * 20.0:
		var axis := flat(objective - hull.position).normalized()
		if axis == Vector3.ZERO:
			axis = BaseAsset.direction(hull.yaw, 0.0)
		state = {"phase": BombPhase.LINE_UP, "axis": axis, "target": objective}
		bombing[hull.entity_id] = state
	var axis: Vector3 = state.axis
	var along := flat(hull.position - objective).dot(axis)
	var line_up := objective - axis * BOMB_LINEUP
	var clear_point := objective + axis * BOMB_CLEAR
	if state.phase == BombPhase.LINE_UP and flat(line_up - hull.position).length() < 21.0:
		state.phase = BombPhase.RUN
	elif state.phase == BombPhase.CLEAR and along > 80.0:
		state.phase = BombPhase.LINE_UP
		axis = -axis
		state.axis = axis
		line_up = objective - axis * BOMB_LINEUP
		clear_point = objective + axis * BOMB_CLEAR
	var target := line_up if state.phase == BombPhase.LINE_UP else clear_point
	var to := flat(target - hull.position)
	course(hull, command, to, to.length(), 0.72)
	if state.phase == BombPhase.RUN:
		var speed := flat(hull.velocity).length()
		var aim := bomb_landing(hull, objective.y)
		var reached_release := flat(aim - objective).length_squared() < 6.0 * 6.0
		if reached_release and speed > 12.0 and hull.position.y - objective.y > 15.0 and hull.cooldown <= 0.0:
			command.buttons |= PlayerCommand.FIRE
			state.phase = BombPhase.CLEAR
		elif along > 24.0:
			state.phase = BombPhase.CLEAR
	_flight(hull, command, boss, 30.0)


## Uses the downward launch speed and horizontal inheritance in VehicleFleet.
static func bomb_landing(hull: Vehicle, target_y: float) -> Vector3:
	var start := hull.to_global(Vehicle.MUZZLE[Vehicle.Kind.BOMBER]) + Vector3.DOWN * 0.3
	var height := maxf(start.y - target_y, 0.0)
	var downward := 5.0 - minf(hull.velocity.y, 0.0)
	var gravity := Weapon.all[Weapon.MORTAR].gravity
	var fall := 2.0 * height / (sqrt(downward * downward + 2.0 * gravity * height) + downward)
	return start + flat(hull.velocity) * 0.72 * fall


func _flight(hull: Vehicle, command: PlayerCommand, boss: TeamCommander, clearance: float) -> void:
	var game := boss.game
	var id := hull.entity_id
	var state: Dictionary = probes.get(id, {})
	if state.is_empty() or game.tick >= state.next:
		var forward := BaseAsset.direction(command.yaw, 0.0)
		if command.move.length_squared() > 0.02:
			forward = Basis(Vector3.UP, command.yaw) * Vector3(command.move.x, 0.0, -command.move.y).normalized()
		var ahead := hull.position + forward * (26.0 + minf(flat(hull.velocity).length(), 35.0))
		var ground := game.fleet.ground_at(hull.position)
		var high := ground
		if game.terrain != null:
			for share: float in [0.4, 0.7, 1.0]:
				var sample := hull.position.lerp(ahead, share)
				high = maxf(high, game.terrain.height_at(sample.x, sample.z))
		var blocked := false
		if boss.director.take_ray():
			blocked = not game.world_ray(hull.position, ahead, Match.WORLD_LAYER | Match.ASSET_LAYER | Vehicle.HULL_LAYER, [hull.get_rid()]).is_empty()
		state = {"next": game.tick + PROBE_TICKS, "ground": ground, "high": high, "blocked": blocked}
		probes[id] = state
	var desired := float(state.high) + clearance
	if state.blocked or hull.position.y < desired - 2.0:
		command.buttons |= PlayerCommand.JET
	elif hull.position.y > desired + 5.0:
		command.buttons |= PlayerCommand.JUMP
	var above_ground := hull.position.y - float(state.ground)
	if state.blocked or above_ground < 8.0:
		command.move *= 0.12
	elif hull.position.y < float(state.high) + 10.0:
		command.move *= 0.35


func _ground(hull: Vehicle, command: PlayerCommand, boss: TeamCommander, enemy: Soldier, objective: Vector3) -> void:
	var game := boss.game
	var id := hull.entity_id
	var to := flat(objective - hull.position)
	var distance := to.length()
	var tank := hull.kind == Vehicle.Kind.TANK
	if tank and enemy != null:
		var from := hull.to_global(Vehicle.MUZZLE[hull.kind])
		var aim := lead(from, enemy, Weapon.DISC, hull.velocity)
		var range_to := flat(enemy.centre() - hull.position).length()
		if range_to <= 80.0 and _tank_can_see(hull, boss, enemy, from):
			point_at(command, aim)
			# Keep the tank behind its firing position when the enemy closes.
			if range_to < 26.0 and absf(angle_difference(hull.yaw, command.yaw)) < 0.35:
				var sight: Dictionary = tank_sight[id]
				if game.tick % PROBE_TICKS == id % PROBE_TICKS and _clear_ground(hull, boss, hull.yaw + PI, 7.0) == 1:
					sight.reverse_until = game.tick + PROBE_TICKS
				if game.tick < int(sight.get("reverse_until", 0)):
					command.move.y = -0.32
			fire_if_aligned(hull, command, boss, enemy, from, aim)
			ground_progress.erase(id)
			probes.erase(id)
			return
	var stop := 44.0 if tank else 16.0
	course(hull, command, to, distance - stop, 0.58 if tank else 0.84)
	if distance <= stop:
		ground_progress.erase(id)
		if not tank:
			_exit_when_slow(hull, command, game.tick)
		return
	var progress: Vector2 = ground_progress.get(id, Vector2(INF, game.tick))
	if distance < progress.x - 3.0:
		progress = Vector2(distance, game.tick)
		ground_progress[id] = progress
	var stalled := game.tick - int(progress.y)
	if stalled >= GROUND_STALL_TICKS:
		_exit_when_slow(hull, command, game.tick)
		return
	var state: Dictionary = probes.get(id, {})
	if state.is_empty() or game.tick >= state.next:
		var yaw := command.yaw
		var length := 9.0 + minf(flat(hull.velocity).length() * 0.65, 16.0)
		var side := 1.0 if hull.team == 0 else -1.0
		if not state.is_empty() and absf(float(state.offset)) > 0.1:
			side = signf(float(state.offset))
		var offset := 0.0
		var direction := 0.0
		var previous := float(state.get("offset", 0.0))
		var detour_until := int(state.get("detour_until", 0))
		var first := previous if game.tick < detour_until else 0.0
		if stalled >= 2 * 60 and not state.is_empty() and state.direction <= 0.0:
			if _clear_ground(hull, boss, hull.yaw + PI, 7.0) == 1:
				direction = -1.0
		for angle: float in ([first, side * 0.75, -side * 0.75, side * 1.45, -side * 1.45] if direction == 0.0 else []):
			var clear := _clear_ground(hull, boss, yaw + angle, length)
			if clear < 0:
				break
			if clear > 0:
				offset = angle
				direction = 1.0
				if absf(angle) > 0.1 and game.tick >= detour_until:
					detour_until = game.tick + 48
				break
		if direction == 0.0 and _clear_ground(hull, boss, hull.yaw + PI, 7.0) == 1:
			direction = -1.0
		state = {"next": game.tick + PROBE_TICKS, "offset": offset, "direction": direction, "detour_until": detour_until}
		probes[id] = state
	var direction: float = state.direction
	if direction < 0.0:
		command.yaw = hull.yaw
		command.move.y = -0.5
	else:
		command.yaw += float(state.offset)
		command.move.y *= direction * maxf(cos(angle_difference(hull.yaw, command.yaw)), 0.0)


func _tank_can_see(hull: Vehicle, boss: TeamCommander, enemy: Soldier, from: Vector3) -> bool:
	var tick := boss.game.tick
	var read: Dictionary = tank_sight.get(hull.entity_id, {})
	if read.get("target", 0) == enemy.entity_id and tick < int(read.next):
		return read.clear
	if not boss.director.take_ray():
		return false
	var clear := boss.game.line_clear(from, enemy.centre())
	tank_sight[hull.entity_id] = {"target": enemy.entity_id, "next": tick + 8, "clear": clear, "reverse_until": read.get("reverse_until", 0)}
	return clear


## 1 is clear, 0 is blocked, -1 means the shared ray budget ran out.
func _clear_ground(hull: Vehicle, boss: TeamCommander, yaw: float, length: float) -> int:
	var game := boss.game
	var forward := BaseAsset.direction(yaw, 0.0)
	var side := Vector3(-forward.z, 0.0, forward.x) * (Vehicle.SIZE[hull.kind].x * 0.5 + 0.3)
	var centre := hull.position + Vector3.UP * 0.12
	var exclude: Array[RID] = [hull.get_rid()]
	for across: float in [0.0, -1.0, 1.0]:
		var start := centre + side * across
		if game.terrain != null:
			for share: float in [0.35, 0.75, 1.0]:
				var sample := start + forward * (length * share)
				var normal := game.terrain.normal_at(sample.x, sample.z)
				if normal.y < (0.77 if hull.kind == Vehicle.Kind.TANK else 0.68):
					return 0
		if not boss.director.take_ray():
			return -1
		var hit := game.world_ray(start, start + forward * length, Match.WORLD_LAYER | Match.ASSET_LAYER | Vehicle.HULL_LAYER, exclude)
		if not hit.is_empty() and (hit.collider != null or hit.normal.y < 0.72):
			return 0
	return 1


static func fire_if_aligned(hull: Vehicle, command: PlayerCommand, boss: TeamCommander, enemy: Soldier, from: Vector3, aim: Vector3) -> void:
	if hull.cooldown > 0.0 or BaseAsset.direction(hull.gun_yaw, hull.gun_pitch).angle_to(aim) > 0.15:
		return
	if boss.director.take_ray() and boss.game.line_clear(from, enemy.centre()):
		command.buttons |= PlayerCommand.FIRE


static func _exit_when_slow(hull: Vehicle, command: PlayerCommand, tick: int) -> void:
	command.move = Vector2.ZERO
	if hull.velocity.length() < 5.0 and tick % 8 == 0:
		command.buttons |= PlayerCommand.BOARD


static func course(hull: Vehicle, command: PlayerCommand, to: Vector3, distance: float, throttle: float) -> void:
	point_at(command, to)
	var brake := flat(hull.velocity).length_squared() / (2.0 * Vehicle.ACCEL[hull.kind])
	var alignment := maxf(cos(angle_difference(hull.yaw, command.yaw)), 0.0)
	command.move.y = clampf((distance - brake * 0.65) / 22.0, 0.0, throttle) * alignment


static func point_at(command: PlayerCommand, to: Vector3) -> void:
	if to.length_squared() <= 0.0001:
		return
	command.yaw = atan2(-to.x, -to.z)
	command.pitch = atan2(to.y, flat(to).length())


static func lead(from: Vector3, who: Soldier, slot: int, motion: Vector3, mounted := true) -> Vector3:
	var weapon := Weapon.all[slot]
	var fall := who.tuning.gravity if not who.grounded and not who.jetting and who.vehicle_id == 0 else 0.0
	var inherit := VehicleFleet.SHOT_INHERIT if mounted else weapon.inherit
	return BotCombat.lead(from, motion, who.centre(), who.vel(), fall, weapon, inherit) - from


static func flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)
