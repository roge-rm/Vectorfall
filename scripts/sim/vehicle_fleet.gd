class_name VehicleFleet
extends RefCounted

const BOARD_REACH := 3.0
const RETURN_AFTER := 30.0
const SHOT_INHERIT := 0.38
## Closing speed in m/s below which a bump does no damage.
const IMPACT_SPEED := 8.0
## A ram is survivable at full health even in light armour.
const MAX_RAM_DAMAGE := 70.0
## A shove can briefly separate the soldier from the hull as it passes.
const RAM_REPEAT_TICKS := 18

var game: Match
var pads: Dictionary[int, VehiclePad] = {}
var hulls: Dictionary[int, Vehicle] = {}
var _commands: Dictionary[int, PlayerCommand] = {}


func _init(match_node: Match) -> void:
	game = match_node


func add_pad(team: int, kind: Vehicle.Kind, at: Vector3, yaw: float) -> VehiclePad:
	var pad := _make_pad(game.next_id, team, kind, at, yaw)
	game.next_id += 1
	return pad


func _make_pad(id: int, team: int, kind: Vehicle.Kind, at: Vector3, yaw: float) -> VehiclePad:
	var pad := VehiclePad.new()
	pad.entity_id = id
	pad.team = team
	pad.kind = kind
	pad.position = at
	pad.yaw = yaw
	game.add_child(pad)
	pads[id] = pad
	return pad


func _make_hull(id: int, pad: VehiclePad, at: Vector3) -> Vehicle:
	var hull := Vehicle.new()
	hull.entity_id = id
	hull.pad_id = pad.entity_id
	hull.kind = pad.kind
	hull.team = pad.team
	hull.health = Vehicle.MAX_HEALTH[pad.kind]
	hull.yaw = pad.yaw
	hull.gun_yaw = pad.yaw
	hull.position = at
	hull.crew.resize(Vehicle.SEATS[pad.kind])
	hull.crew.fill(0)
	game.add_child(hull)
	hulls[id] = hull
	pad.hull_id = id
	return hull


## The usable hull closest to the soldier, or its requested hull for a bot.
## Used for the prompt as well as the boarding command during the tick.
func nearby(who: Soldier, requested := 0) -> Vehicle:
	if who.dead or who.vehicle_id != 0 or game.carried_flag(who.entity_id) != null:
		return null
	var best: Vehicle = null
	var best_distance := BOARD_REACH
	for hull: Vehicle in hulls.values():
		if requested != 0 and hull.entity_id != requested:
			continue
		if hull.team != who.team or hull.open_seat() < 0 or hull.velocity.length() > Vehicle.BOARD_SPEED:
			continue
		var at := who.centre()
		var distance := hull.distance_to_body(at)
		if distance <= best_distance and game.line_clear(at, hull.seat_eye(0)):
			if distance < best_distance or best == null or hull.entity_id < best.entity_id:
				best = hull
				best_distance = distance
	return best


## Handles boarding before walking and keeps commands for crew until the
## hulls have moved. Every foot soldier still simulates in entity order.
func command(who: Soldier, input: PlayerCommand, delta: float) -> void:
	var pressed := input.has(PlayerCommand.BOARD) and not who.board_held
	who.board_held = input.has(PlayerCommand.BOARD)
	var hull: Vehicle = hulls.get(who.vehicle_id)
	if hull == null and pressed and not game.over:
		hull = nearby(who, input.board_id)
		if hull != null:
			var seat := hull.open_seat()
			hull.crew[seat] = who.entity_id
			hull.unattended = 0.0
			who.mount(hull.entity_id, seat)
	elif hull != null and (pressed or who.dead):
		if eject(hull, who, who.dead):
			hull = null
		elif who.dead:
			who.mount(0, -1)
			hull = null
	if hull == null:
		who.simulate(input, delta)
	else:
		_commands[who.entity_id] = input


func step(delta: float) -> void:
	var ids := hulls.keys()
	ids.sort()
	var crashed_pairs: Dictionary[Vector2i, bool] = {}
	for id: int in ids:
		var hull: Vehicle = hulls.get(id)
		if hull == null:
			continue
		var pad := pads[hull.pad_id]
		if hull.position.y < -200.0:
			damage(hull, hull.health, 0, -1, Weapon.DISC)
			continue
		if hull.empty() and hull.velocity.length_squared() < 0.001 and hull.kick.length_squared() < 0.001 and hull.position.distance_to(pad.position) < 4.0:
			continue
		var pilot: PlayerCommand = _commands.get(hull.crew[0])
		var probe := hull.position
		if not hull.flies() and pilot != null and pilot.move.length_squared() > 0.01:
			var to := Basis(Vector3.UP, hull.yaw) * Vector3(pilot.move.x, 0.0, -pilot.move.y)
			probe += to.normalized() * Vehicle.SIZE[hull.kind].z * 0.49
		var floor_y := maxf(ground_at(hull.position), ground_at(probe)) if probe != hull.position else ground_at(probe)
		var start := hull.global_position
		var incoming := hull.drive(pilot, floor_y, delta)
		if not game.over:
			if pilot != null and incoming.length_squared() > IMPACT_SPEED * IMPACT_SPEED:
				_ram_soldiers(hull, start, incoming)
			_crash(hull, incoming, crashed_pairs)
		if not hulls.has(id):
			continue
		for seat in hull.crew.size():
			var rider := game.soldier(hull.crew[seat])
			if rider == null:
				continue
			var input: PlayerCommand = _commands.get(rider.entity_id)
			_sync_rider(hull, rider, seat)
			if input == null:
				continue
			rider.simulate_rider(input, delta, hull.uses_personal_weapon(seat))
			if seat == hull.weapon_seat() and Vehicle.WEAPONS[hull.kind] >= 0:
				hull.aim(input, delta)
				if input.has(PlayerCommand.FIRE) and hull.cooldown <= 0.0:
					_fire(hull, rider)
		if hull.empty() and hull.position.distance_to(pad.position) > 8.0:
			hull.unattended += delta
			if hull.unattended >= RETURN_AFTER:
				_remove_hull(hull)
	_commands.clear()
	for pad: VehiclePad in pads.values():
		if pad.hull_id != 0 or not game.powered(pad.team):
			continue
		pad.remaining = maxf(0.0, pad.remaining - delta)
		if pad.remaining <= 0.0:
			_spawn(pad)


func ground_at(at: Vector3) -> float:
	var hit := game.world_ray(at + Vector3.UP * 2.0, at + Vector3.DOWN * 155.0, Match.WORLD_LAYER)
	return hit.position.y if not hit.is_empty() else at.y - 155.0


## Sweep the hull's travelled segment against foot soldiers' body extents.
## The hull still slides past a soldier instead of stopping on their collider.
func _ram_soldiers(hull: Vehicle, start: Vector3, incoming: Vector3) -> void:
	var motion := hull.global_position - start
	if motion.length_squared() < 0.0001:
		return
	var basis := hull.global_basis
	var local_motion := basis.transposed() * motion
	var half := Vehicle.SIZE[hull.kind] * 0.5
	var reach := half.length() + motion.length() + 1.5
	var reach_sq := reach * reach
	var driver := hull.crew[0]
	var weight := sqrt(Vehicle.MASS[hull.kind] / Vehicle.MASS[Vehicle.Kind.GUNSHIP])
	for id: int in game.entities:
		var victim := game.entities[id] as Soldier
		if victim.dead or victim.team == hull.team or victim.vehicle_id != 0 or game.tick < hull.ram_until.get(id, 0):
			continue
		var target := victim.centre()
		if start.distance_squared_to(target) > reach_sq:
			continue
		var end := hull.to_local(target)
		var before := end + local_motion
		var extent := half + Vector3(victim.tuning.radius, victim.tuning.height * 0.5, victim.tuning.radius)
		var box := AABB(-extent, extent * 2.0)
		if box.has_point(before):
			continue
		var contact: Variant = box.intersects_segment(before, end)
		if contact == null:
			continue
		var surface: Vector3 = contact / extent
		var axis := surface.abs().max_axis_index()
		var outward := Vector3.ZERO
		outward[axis] = signf(surface[axis])
		var normal := basis * outward
		var speed := (incoming - victim.velocity).dot(normal)
		if speed <= IMPACT_SPEED or motion.dot(normal) <= 0.0:
			continue
		var contact_center := target - basis * (contact as Vector3)
		if not game.world_ray(contact_center, target, hull.collision_mask, [hull.get_rid()]).is_empty():
			continue
		var amount := minf(MAX_RAM_DAMAGE, (speed - IMPACT_SPEED) * 3.0 * weight)
		hull.ram_until[id] = game.tick + RAM_REPEAT_TICKS
		victim.push(normal * amount * 0.12 * victim.tuning.mass)
		game.damage(victim, amount, driver, Weapon.VEHICLE_IMPACT, contact_center)


func _crash(hull: Vehicle, incoming: Vector3, pairs: Dictionary[Vector2i, bool]) -> void:
	# drive() skips move_and_slide() when stationary, so its contacts can be old.
	if incoming.length_squared() <= 0.0004:
		return
	var wall_speed := 0.0
	for i in hull.get_slide_collision_count():
		var contact := hull.get_slide_collision(i)
		var normal := contact.get_normal()
		hull.velocity -= normal * minf(0.0, hull.velocity.dot(normal))
		var other := contact.get_collider() as Vehicle
		if other == null:
			wall_speed = maxf(wall_speed, -incoming.dot(normal))
			continue
		if not hulls.has(other.entity_id):
			continue
		var speed := (other.velocity - incoming).dot(normal)
		if speed <= IMPACT_SPEED:
			continue
		var pair := Vector2i(mini(hull.entity_id, other.entity_id), maxi(hull.entity_id, other.entity_id))
		if pairs.has(pair):
			continue
		pairs[pair] = true
		var own_mass := Vehicle.MASS[hull.kind]
		var other_mass := Vehicle.MASS[other.kind]
		# The normal points towards this hull. Stop the other one driving back
		# into the same impact on its turn, while preserving sideways motion.
		other.velocity -= normal * maxf(0.0, other.velocity.dot(normal))
		var enemy := hull.team != other.team
		var driver := hull.crew[0] if enemy else 0
		var other_driver := other.crew[0] if enemy else 0
		_crash_damage(other, speed * own_mass / (own_mass + other_mass), driver)
		_crash_damage(hull, speed * other_mass / (own_mass + other_mass), other_driver)
		if not hulls.has(hull.entity_id):
			return
	_crash_damage(hull, wall_speed, 0)


func _crash_damage(hull: Vehicle, speed: float, driver: int) -> void:
	if speed <= IMPACT_SPEED:
		return
	var severity := (speed - IMPACT_SPEED) / 32.0
	var amount := Vehicle.MAX_HEALTH[hull.kind] * 0.55 * severity * severity
	damage(hull, amount, driver, -1, Weapon.VEHICLE_IMPACT)


func _spawn(pad: VehiclePad) -> void:
	var size := Vehicle.SIZE[pad.kind]
	var basis := Basis(Vector3.UP, pad.yaw)
	var floor_y := maxf(pad.position.y, ground_at(pad.position))
	for side: float in [-1, 1]:
		for end: float in [-1, 1]:
			var corner := pad.position + basis * Vector3(side * size.x * 0.49, 0, end * size.z * 0.49)
			floor_y = maxf(floor_y, ground_at(corner))
	var at := Vector3(pad.position.x, floor_y + Vehicle.ride_height(pad.kind), pad.position.z)
	var box := BoxShape3D.new()
	box.size = size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(basis, at)
	query.collision_mask = Match.WORLD_LAYER | Match.SOLDIER_LAYER | Match.ASSET_LAYER | Vehicle.HULL_LAYER
	if game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		_make_hull(game.next_id, pad, at)
		game.next_id += 1


func _sync_rider(hull: Vehicle, who: Soldier, seat: int) -> void:
	who.position = hull.seat_eye(seat) - Vector3.UP * who.tuning.eye_height
	who.velocity = hull.velocity


func _fire(hull: Vehicle, shooter: Soldier) -> void:
	var slot := Vehicle.WEAPONS[hull.kind]
	var weapon := Weapon.all[slot]
	var drop := hull.kind == Vehicle.Kind.BOMBER
	var direction := Vector3.DOWN if drop else BaseAsset.direction(hull.gun_yaw, hull.gun_pitch)
	var start := hull.to_global(Vehicle.MUZZLE[hull.kind])
	var muzzle := start + direction * (0.3 if drop else 1.45)
	# A turret pointing through a wall cannot fire from the far side.
	if not game.line_clear(start, muzzle):
		return
	var shot := Projectile.new()
	shot.id = game.next_id
	game.next_id += 1
	shot.weapon = slot
	shot.shooter = shooter.entity_id
	shot.vehicle_id = hull.entity_id
	shot.team = shooter.team
	shot.position = muzzle
	shot.velocity = direction * weapon.speed + hull.velocity * SHOT_INHERIT
	if drop:
		shot.velocity = Vector3(hull.velocity.x * 0.72, minf(0.0, hull.velocity.y) - 5.0, hull.velocity.z * 0.72)
	shot.damage = weapon.damage
	shot.bounces_left = weapon.bounces
	game.projectiles.append(shot)
	hull.cooldown = 2.2 if drop else (1.35 if hull.kind == Vehicle.Kind.TANK else 0.38)
	game.fired.emit(shooter.entity_id, slot)


func damage(hull: Vehicle, amount: float, attacker: int, attacker_team: int, slot: int) -> void:
	if amount <= 0.0 or hull.team == attacker_team or not hulls.has(hull.entity_id):
		return
	var loss := minf(hull.health, amount)
	hull.health -= loss
	if slot == Weapon.VEHICLE_IMPACT and loss > 0.0:
		game.vehicle_crashed.emit(hull.crew[0], hull.global_position, loss)
	if hull.health > 0.0:
		return
	var at := hull.position
	for id in hull.crew.duplicate():
		var rider := game.soldier(id)
		if rider != null:
			var escaped := eject(hull, rider, true)
			if not escaped:
				rider.mount(0, -1)
			game.damage(rider, 45.0 if escaped else 1000.0, attacker, slot, at)
	_remove_hull(hull)
	game.impacted.emit(Weapon.MORTAR, at, Vector3.UP)


func eject(hull: Vehicle, who: Soldier, forced := false) -> bool:
	var at := _exit_point(hull, who)
	if at == Vector3.INF:
		if forced:
			hull.crew[who.vehicle_seat] = 0
		return false
	var airborne := hull.flies() and at.y - ground_at(at) > 4.0
	hull.crew[who.vehicle_seat] = 0
	who.mount(0, -1)
	who.position = at
	who.velocity = (hull.velocity * 0.65).limit_length(36.0)
	if airborne or forced:
		who.velocity.y = maxf(who.velocity.y, 9.0)
	return true


func _exit_point(hull: Vehicle, who: Soldier) -> Vector3:
	var shape := CapsuleShape3D.new()
	shape.radius = who.tuning.radius
	shape.height = who.tuning.height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = Match.WORLD_LAYER | Match.ASSET_LAYER | Match.SOLDIER_LAYER | Vehicle.HULL_LAYER | Match.enemy_fields(who.team)
	var half := Vehicle.SIZE[hull.kind] * 0.5
	var side := half.x + who.tuning.radius + 0.55
	for offset in [Vector3(side, 0, 0), Vector3(-side, 0, 0), Vector3(0, 0, half.z + 1.0), Vector3(0, half.y + 0.45, 0)]:
		var at := hull.to_global(offset)
		var ray_end := at + Vector3.UP * who.tuning.height * 0.5
		query.transform.origin = ray_end
		var blocks := game.world_ray(hull.seat_eye(who.vehicle_seat), ray_end, query.collision_mask, [hull.get_rid(), who.get_rid()])
		if blocks.is_empty() and game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return at
	return Vector3.INF


func _remove_hull(hull: Vehicle) -> void:
	var pad := pads[hull.pad_id]
	pad.hull_id = 0
	pad.remaining = VehiclePad.RESPAWN
	hulls.erase(hull.entity_id)
	game.remove_child(hull)
	hull.queue_free()


func get_state() -> Dictionary:
	var pad_states := {}
	for id in pads:
		pad_states[id] = pads[id].get_state()
	var hull_states := {}
	for id in hulls:
		hull_states[id] = hulls[id].get_state()
	return {"pads": pad_states, "hulls": hull_states}


func set_state(state: Dictionary) -> void:
	_commands.clear()
	var pad_states: Dictionary = state.get("pads", {})
	var hull_states: Dictionary = state.get("hulls", {})
	for id in hulls.keys():
		var hull := hulls[id]
		var saved: Dictionary = hull_states.get(id, {})
		if saved.is_empty() or saved.pad != hull.pad_id:
			game.remove_child(hull)
			hull.queue_free()
			hulls.erase(id)
	for id in pads.keys():
		if not pad_states.has(id):
			game.remove_child(pads[id])
			pads[id].queue_free()
			pads.erase(id)
	for id: int in pad_states:
		var saved: Dictionary = pad_states[id]
		if not pads.has(id):
			_make_pad(id, saved.team, saved.kind, saved.position, saved.yaw)
		pads[id].set_state(saved)
	for id: int in hull_states:
		var saved: Dictionary = hull_states[id]
		if not hulls.has(id):
			_make_hull(id, pads[saved.pad], saved.position)
		hulls[id].set_state(saved)
