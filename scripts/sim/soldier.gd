class_name Soldier
extends CharacterBody3D

## A soldier, moved only by simulate() with one PlayerCommand per physics
## tick. Its origin is at its feet. Everything simulate() reads is in
## get_state(), so a copy given the same state and commands moves the same.

## The usual team colours. A map's palette can set its own, read through
## Palette.team().
const TEAM_COLOURS: Array[Color] = [Color("a0ff40"), Color("2f6bff")]
const TEAM_NAMES: Array[String] = ["Lime", "Blue"]
const PITCH_LIMIT := 1.45
## Render layer for your own body, which your camera leaves out.
const OWN_BODY_LAYER := 2
## The gun's muzzle from the eye, in look space: right, down and ahead.
const MUZZLE := Vector3(0.22, -0.2, -0.6)
## Where thrown things leave the hand from the eye, in look space.
const THROW_HAND := Vector3(-0.2, -0.1, -0.4)
## Seconds after switching weapons before the new one can fire.
const SWITCH_TIME := 0.3
## Seconds after throwing a hand grenade or placing a mine before the next.
const THROW_TIME := 0.5
## No throw waiting, for throw_pending.
const NO_THROW := -1

var entity_id := 0
var team := 0
var display_name := ""
## The match this soldier is in, for firing and respawning.
var game: Match
var tuning := MovementTuning.new()
var yaw := 0.0
var pitch := 0.0
var energy := 0.0
## Seconds since the jet was last on, for the refill delay.
var since_jet := 0.0
## On the ground after the last tick. Kept here rather than read from
## is_on_floor() so set_state() can restore it.
var grounded := false
var jetting := false
## The jump button was held last tick, so holding it jumps only once.
var jump_held := false
## The ski button is held, on the ground or not.
var ski_held := false
## Skiing on the ground this tick.
var skiing := false
## The ground's normal after the last tick, straight up in the air.
var floor_normal := Vector3.UP

var health := 0.0
var dead := false
## Seconds left until a dead soldier respawns.
var respawn_in := 0.0
## What the soldier carries now, set with set_loadout().
var loadout := Loadout.standard()
## The loadout the soldier wants: put on at the next respawn, or at once on
## one of its team's inventory stations. A command's loadout sets it.
var next_loadout := Loadout.standard()
## Weapon slots carried (indexes into Weapon.all), a copy of loadout.weapons.
var weapons: Array[int] = []
## The weapon in hand, an index into weapons.
var weapon := 0
## Rounds left for each carried weapon, in the order of weapons, 0 for one
## that runs on energy.
var ammo: Array[int] = []
## Seconds until the weapon in hand can fire again.
var cooldown := 0.0
## How far a weapon that spins up has spun, 0 to 1.
var spin := 0.0
## Shots fired since the start, so the view model can kick on each one.
var shots := 0
## Hand grenades and mines left.
var grenades := 0
var mines := 0
## Seconds until the next throw.
var throw_cooldown := 0.0
## The grenade and mine buttons were held last tick, so holding throws once.
var grenade_held := false
var mine_held := false
## A throw pressed during throw_cooldown, done when it ends: NO_THROW,
## Weapon.HAND_GRENADE or Weapon.MINE.
var throw_pending := NO_THROW
## A shield or jammer switched on, or a repair pack repairing this tick.
var pack_on := false
## The use button was held last tick, so a press toggles a pack once.
var use_held := false
## Who the repair pack healed this tick: this soldier's id, a teammate's, or
## 0 for no one.
var repair_target := 0

var body: SoldierBody
var blob: BlobShadow

## While true, at(), vel() and the rest give the copy take_snapshot() made at
## the start of the tick instead of reading the node. BotDirector sets it for
## the bot phase, so bot code on worker threads never touches a node. The copy
## isn't in the state: it's made again each tick.
static var use_snapshot := false
var _seen_pos := Vector3.ZERO
var _seen_vel := Vector3.ZERO
var _seen_back := Vector3.BACK
## Normals of the walls the last move slid along.
var _seen_walls := PackedVector3Array()


func _init() -> void:
	tuning = MovementTuning.for_armour(loadout.armour)
	weapons = loadout.weapons.duplicate()
	for slot in weapons:
		ammo.append(Weapon.all[slot].ammo)
	grenades = loadout.grenades
	mines = loadout.mines
	energy = tuning.energy_max
	since_jet = tuning.refill_delay
	health = tuning.health_max
	floor_snap_length = tuning.floor_snap
	floor_max_angle = deg_to_rad(50.0)
	floor_constant_speed = true
	collision_layer = Match.SOLDIER_LAYER
	collision_mask = Match.WORLD_LAYER | Match.SOLDIER_LAYER
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = tuning.radius
	capsule.height = tuning.height
	shape.shape = capsule
	shape.position.y = tuning.height * 0.5
	add_child(shape)

	body = SoldierBody.new()
	body.soldier = self
	add_child(body)
	body.set_weapons(weapons)

	blob = BlobShadow.new()
	add_child(blob)


func _ready() -> void:
	set_team(team)


func set_team(value: int) -> void:
	team = value
	body.set_look(team, loadout.armour, loadout.pack)


## Puts on a loadout at once, trimmed to its armour: its movement numbers,
## health and energy kept as shares of the new maximums, full ammo and the
## body look. It's also the loadout for the next respawn. The weapon in hand
## stays if it's still carried. With keep_stock, ammo, grenades and mines are
## carried over instead, held to the new maximums, and a weapon not carried
## before starts empty.
func set_loadout(value: Loadout, keep_stock := false) -> void:
	var fixed := value.fixed()
	var old_weapons := weapons.duplicate()
	var old_ammo := ammo.duplicate()
	var old_grenades := grenades
	var old_mines := mines
	var health_share := health / tuning.health_max
	var energy_share := energy / tuning.energy_max
	var in_hand := weapon_slot()
	var armour_changed := fixed.armour != loadout.armour
	if fixed.pack != loadout.pack:
		pack_on = false
		repair_target = 0
	loadout = fixed
	next_loadout = fixed.duplicate()
	tuning = MovementTuning.for_armour(fixed.armour)
	health = health_share * tuning.health_max
	energy = energy_share * tuning.energy_max
	weapons = fixed.weapons.duplicate()
	ammo.clear()
	for k in weapons.size():
		if not keep_stock:
			ammo.append(max_ammo(k))
			continue
		var before := old_weapons.find(weapons[k])
		ammo.append(mini(old_ammo[before], max_ammo(k)) if before >= 0 else 0)
	grenades = Pack.scaled(fixed.grenades, fixed.pack)
	mines = Pack.scaled(fixed.mines, fixed.pack)
	if keep_stock:
		grenades = mini(old_grenades, grenades)
		mines = mini(old_mines, mines)
	weapon = maxi(weapons.find(in_hand), 0)
	if weapon_slot() != in_hand:
		spin = 0.0
	if armour_changed:
		body.set_look(team, fixed.armour, fixed.pack)
	else:
		body.set_pack(fixed.pack)
	body.set_weapons(weapons)


## The pack carried, or null for none.
func pack() -> Pack:
	return Pack.get_pack(loadout.pack)


## True while a shield pack is on.
func shielded() -> bool:
	return pack_on and loadout.pack == Pack.SHIELD


## True while a sensor jammer is on.
func jamming() -> bool:
	return pack_on and loadout.pack == Pack.JAMMER


## Rounds a full load gives the carried weapon at an index, more with an
## ammo pack.
func max_ammo(k: int) -> int:
	return Pack.scaled(Weapon.all[weapons[k]].ammo, loadout.pack)


## Seconds after the jet stops before energy refills, and energy a second it
## refills at, both quicker with an energy pack.
func refill_delay() -> float:
	var p := pack()
	return tuning.refill_delay * (p.delay_scale if p != null else 1.0)


func refill_rate() -> float:
	var p := pack()
	return tuning.energy_refill * (p.refill_scale if p != null else 1.0)


## Slot in Weapon.all of the weapon in hand.
func weapon_slot() -> int:
	return weapons[weapon] if weapon < weapons.size() else Weapon.DISC


## Index in weapons of a carried weapon slot, or -1 if it isn't carried.
func carried(slot: int) -> int:
	return weapons.find(slot)


## Rounds left for a weapon slot, 0 if it isn't carried.
func ammo_for(slot: int) -> int:
	var k := weapons.find(slot)
	return ammo[k] if k >= 0 else 0


## True if a weapon slot is carried and has the ammo or energy for a shot.
func loaded(slot: int) -> bool:
	var k := weapons.find(slot)
	if k < 0:
		return false
	var w := Weapon.all[slot]
	return energy >= w.energy_per_shot if w.uses_energy() else ammo[k] > 0


## Hides your own body from your camera.
func set_first_person(on: bool) -> void:
	body.set_render_layer(OWN_BODY_LAYER if on else 1)


## The middle of the body, where blasts push from.
func centre() -> Vector3:
	return global_position + Vector3.UP * tuning.height * 0.5


## Distance from a point to the body's capsule, 0 inside it.
func distance_to_body(point: Vector3) -> float:
	var r := tuning.radius
	var bottom := global_position + Vector3.UP * r
	var top := global_position + Vector3.UP * (tuning.height - r)
	var closest := Geometry3D.get_closest_point_to_segment(point, bottom, top)
	return maxf(point.distance_to(closest) - r, 0.0)


## A push in kg·m/s. One with enough lift takes you off the ground, so a
## blast under your feet throws you up.
func push(impulse: Vector3) -> void:
	var change := impulse / tuning.mass
	velocity += change
	if change.y > 1.0:
		grounded = false
		floor_normal = Vector3.UP


func die() -> void:
	dead = true
	health = 0.0
	respawn_in = Match.RESPAWN_DELAY
	jetting = false
	skiing = false
	spin = 0.0
	pack_on = false
	repair_target = 0
	throw_pending = NO_THROW
	_set_alive_layers(false)


## Full ammo, hand grenades and mines for the loadout worn.
func restock() -> void:
	for k in weapons.size():
		ammo[k] = max_ammo(k)
	grenades = Pack.scaled(loadout.grenades, loadout.pack)
	mines = Pack.scaled(loadout.mines, loadout.pack)


## Back at a spawn point in next_loadout, with full health, energy and ammo.
func revive(where: Transform3D) -> void:
	dead = false
	if not next_loadout.equals(loadout):
		set_loadout(next_loadout)
	health = tuning.health_max
	energy = tuning.energy_max
	since_jet = tuning.refill_delay
	restock()
	pack_on = false
	repair_target = 0
	throw_cooldown = 0.0
	throw_pending = NO_THROW
	cooldown = 0.0
	spin = 0.0
	respawn_in = 0.0
	global_position = where.origin
	velocity = Vector3.ZERO
	yaw = where.basis.get_euler().y
	pitch = 0.0
	rotation = Vector3(0.0, yaw, 0.0)
	grounded = false
	floor_normal = Vector3.UP
	_set_alive_layers(true)


func _set_alive_layers(alive: bool) -> void:
	collision_layer = Match.SOLDIER_LAYER if alive else 0
	collision_mask = Match.WORLD_LAYER | Match.SOLDIER_LAYER if alive else Match.WORLD_LAYER


func eye_transform() -> Transform3D:
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	return Transform3D(basis, at() + Vector3.UP * tuning.eye_height)


func horizontal_speed() -> float:
	var v := vel()
	return Vector2(v.x, v.z).length()


## Copies what bot threads read from the node. Main thread only.
func take_snapshot() -> void:
	_seen_pos = global_position
	_seen_vel = velocity
	_seen_back = transform.basis.z
	_seen_walls = _wall_normals()


## The position, from the snapshot in the bot phase. Off it, main thread only.
func at() -> Vector3:
	if use_snapshot:
		return _seen_pos
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id(), "a node read off the main thread")
	return global_position


func vel() -> Vector3:
	if use_snapshot:
		return _seen_vel
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id(), "a node read off the main thread")
	return velocity


## The body's back, its basis z.
func back() -> Vector3:
	if use_snapshot:
		return _seen_back
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id(), "a node read off the main thread")
	return transform.basis.z


## Normals of the walls the last move slid along.
func wall_normals() -> PackedVector3Array:
	if use_snapshot:
		return _seen_walls
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id(), "a node read off the main thread")
	return _wall_normals()


func _wall_normals() -> PackedVector3Array:
	var normals := PackedVector3Array()
	if is_on_wall():
		for k in get_slide_collision_count():
			normals.append(get_slide_collision(k).get_normal())
	return normals


func simulate(command: PlayerCommand, delta: float) -> void:
	if not command.loadout.is_empty():
		next_loadout = Loadout.from_dict(command.loadout).fixed()
	if dead:
		# A body only falls and slides until it's time to respawn.
		var still := PlayerCommand.new()
		still.yaw = yaw
		still.pitch = pitch
		command = still
	var t := tuning
	yaw = wrapf(command.yaw, -PI, PI)
	pitch = clampf(command.pitch, -PITCH_LIMIT, PITCH_LIMIT)
	rotation = Vector3(0.0, yaw, 0.0)
	var move := command.move.limit_length(1.0)
	var wish := Basis(Vector3.UP, yaw) * Vector3(move.x, 0.0, -move.y)
	var wish_dir := wish.normalized() if wish.length() > 0.01 else Vector3.ZERO
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var v_y := velocity.y
	var jump_pressed := command.has(PlayerCommand.JUMP) and not jump_held
	jump_held = command.has(PlayerCommand.JUMP)
	ski_held = command.has(PlayerCommand.SKI)

	jetting = command.has(PlayerCommand.JET) and energy > 0.0
	skiing = grounded and ski_held and not jetting
	if skiing:
		_ski(wish_dir, delta)
		if jump_pressed:
			velocity = velocity.slide(floor_normal) + Vector3.UP * t.jump_speed
			grounded = false
	elif grounded and not jetting:
		var speed := horizontal.length()
		var target := wish * t.run_speed
		if speed > t.run_speed + 0.01 and horizontal.dot(wish) >= 0.0:
			# Above run speed you keep your speed, fading slowly, and only braking
			# by pulling back takes it off faster.
			horizontal = horizontal.normalized() * maxf(speed - t.overspeed_decay * delta, t.run_speed)
		else:
			var rate := t.ground_accel if wish_dir != Vector3.ZERO else t.ground_friction
			horizontal = horizontal.move_toward(target, rate * delta)
		if jump_pressed:
			v_y = t.jump_speed
			grounded = false
	elif jetting and (ski_held or horizontal.length() > t.jet_side_speed):
		# At speed some of the jet pushes you forward, so you can climb the next
		# hill without losing your speed.
		var ahead := wish_dir if wish_dir != Vector3.ZERO else Basis(Vector3.UP, yaw) * Vector3.FORWARD
		horizontal += ahead * t.jet_forward_accel * delta
	elif wish_dir != Vector3.ZERO:
		# In the air you keep your momentum and can only add a little speed
		# towards where you steer, more while jetting.
		var cap := t.jet_side_speed if jetting else t.air_control_speed
		var accel := t.jet_side_accel if jetting else t.air_accel
		var add := clampf(cap - horizontal.dot(wish_dir), 0.0, accel * delta)
		horizontal += wish_dir * add

	if jetting:
		energy = maxf(energy - t.energy_drain * delta, 0.0)
		since_jet = 0.0
		if v_y < t.jet_max_rise:
			v_y = minf(v_y + t.jet_up_accel * delta, t.jet_max_rise)
		grounded = false
	else:
		since_jet += delta
		if since_jet >= refill_delay():
			energy = minf(energy + refill_rate() * delta, t.energy_max)

	if not skiing:
		v_y -= t.gravity * delta
		velocity = Vector3(horizontal.x, v_y, horizontal.z)
	_drag(delta)
	var before := velocity
	var was_grounded := grounded
	# Skiing fast barely holds on to the ground, so a crest throws you.
	floor_snap_length = t.ski_snap if ski_held and before.length() > t.ski_launch_speed else t.floor_snap
	floor_stop_on_slope = not skiing
	floor_constant_speed = not skiing
	if Prof.on:
		var prof_t := Time.get_ticks_usec()
		move_and_slide()
		Prof.add("move_and_slide", Time.get_ticks_usec() - prof_t)
		Prof.count("move_and_slide")
	else:
		move_and_slide()
	grounded = is_on_floor()
	floor_normal = get_floor_normal() if grounded else Vector3.UP
	if grounded and ski_held:
		# move_and_slide() drops the vertical part of your speed on the floor,
		# which would stop you skiing downhill, so keep the part along the slope.
		# Landing this way only loses the part into the slope, so a downhill
		# keeps or adds speed and flat ground loses the fall.
		velocity = _along_ground(before)
	elif grounded and not was_grounded:
		# Landing on a slope turns the fall into speed along it, so landing on a
		# downhill keeps your speed and can add to it.
		var along := before.slide(floor_normal)
		var kept := Vector3(along.x, 0.0, along.z)
		if kept.length() > horizontal_speed():
			velocity.x = kept.x
			velocity.z = kept.z
	if dead:
		respawn_in -= delta
		if respawn_in <= 0.0 and game != null:
			game.respawn(self)
	else:
		_use_weapon(command, delta)
		_throw(command, delta)
		_use_pack(command, delta)


## Switching between the carried weapons and firing, after moving so a shot
## leaves from where you are now with the speed you have now.
func _use_weapon(command: PlayerCommand, delta: float) -> void:
	var count := weapons.size()
	var wanted := weapon
	if command.weapon >= 0 and command.weapon < count:
		wanted = command.weapon
	if command.has(PlayerCommand.NEXT_WEAPON):
		wanted = (wanted + 1) % count
	if command.has(PlayerCommand.PREV_WEAPON):
		wanted = (wanted + count - 1) % count
	if wanted != weapon:
		weapon = wanted
		spin = 0.0
		cooldown = maxf(cooldown, SWITCH_TIME)
	cooldown = maxf(cooldown - delta, 0.0)
	var w := Weapon.all[weapons[weapon]]
	var trigger := command.has(PlayerCommand.FIRE) and loaded(w.slot)
	if w.spin_up > 0.0:
		spin = move_toward(spin, 1.0, delta / w.spin_up) if trigger else move_toward(spin, 0.0, delta / w.spin_down)
	if trigger and cooldown <= 0.0 and spin >= w.spin_to_fire and game != null:
		# The shot reads the energy before it's taken, for damage that scales
		# with it.
		game.fire(self)
		if w.uses_energy():
			energy = maxf(energy - w.energy_per_shot, 0.0)
		else:
			ammo[weapon] -= 1
		shots += 1
		cooldown = w.interval_at(spin)


## Throws a hand grenade or places a mine, once per press of its button. A
## press during throw_cooldown waits for it to end, the latest press winning.
func _throw(command: PlayerCommand, delta: float) -> void:
	if command.has(PlayerCommand.GRENADE) and not grenade_held:
		throw_pending = Weapon.HAND_GRENADE
	elif command.has(PlayerCommand.MINE) and not mine_held:
		throw_pending = Weapon.MINE
	grenade_held = command.has(PlayerCommand.GRENADE)
	mine_held = command.has(PlayerCommand.MINE)
	throw_cooldown = maxf(throw_cooldown - delta, 0.0)
	if throw_cooldown > 0.0 or game == null:
		return
	var pending := throw_pending
	throw_pending = NO_THROW
	if pending == Weapon.HAND_GRENADE and grenades > 0:
		game.throw(self, Weapon.HAND_GRENADE)
		grenades -= 1
		throw_cooldown = THROW_TIME
	elif pending == Weapon.MINE and mines > 0:
		game.throw(self, Weapon.MINE)
		mines -= 1
		throw_cooldown = THROW_TIME


## Works the pack: repair while use is held, a shield or jammer switched with
## each press, and the energy they take. A shield or jammer goes off at no
## energy, and repairing stops.
func _use_pack(command: PlayerCommand, delta: float) -> void:
	var pressed := command.has(PlayerCommand.USE) and not use_held
	use_held = command.has(PlayerCommand.USE)
	repair_target = 0
	var p := pack()
	if p == null or p.use == Pack.Use.ALWAYS:
		pack_on = false
		return
	if p.use == Pack.Use.TOGGLE:
		if pressed:
			switch_pack(not pack_on and energy > 0.0)
	elif use_held and energy > 0.0 and game != null:
		# A hurt teammate in front of you first, then yourself.
		var target := game.repair_target(self, p.reach)
		if target == null and health < tuning.health_max:
			target = self
		if target != null:
			var rate := p.self_repair if target == self else p.other_repair
			target.health = minf(target.health + rate * delta, target.tuning.health_max)
			repair_target = target.entity_id
		switch_pack(target != null)
	else:
		switch_pack(false)
	if pack_on:
		energy = maxf(energy - p.drain * delta, 0.0)
	if energy <= 0.0 and p.use == Pack.Use.TOGGLE:
		switch_pack(false)


## Turns the pack on or off, telling the match when it changes.
func switch_pack(on: bool) -> void:
	if on == pack_on:
		return
	pack_on = on
	if game != null:
		game.pack_switched.emit(entity_id, on)


## Skiing on the ground: speed along the slope only, gravity along the slope
## speeds you up or slows you down, little friction, and pushing only steers.
func _ski(wish_dir: Vector3, delta: float) -> void:
	var t := tuning
	var n := floor_normal
	var v := velocity.slide(n)
	v += Vector3.DOWN.slide(n) * t.gravity * delta
	var speed := v.length()
	if speed > 0.0:
		v *= maxf(speed - t.ski_friction * delta, 0.0) / speed
	if wish_dir != Vector3.ZERO:
		var dir := wish_dir.slide(n).normalized()
		var add := clampf(t.ski_steer_speed - v.dot(dir), 0.0, t.ski_steer_accel * delta)
		v += dir * add
	velocity = v - n * t.ski_press


## A velocity from before the move, slid along the floor and off any walls
## the move hit.
func _along_ground(v: Vector3) -> Vector3:
	v = v.slide(floor_normal)
	for k in get_slide_collision_count():
		var normal := get_slide_collision(k).get_normal()
		if normal.angle_to(up_direction) > floor_max_angle + 0.01 and v.dot(normal) < 0.0:
			v = v.slide(normal)
	return v


## Drag that grows with the square of speed above drag_free_speed.
func _drag(delta: float) -> void:
	var t := tuning
	var speed := velocity.length()
	if speed <= t.drag_free_speed:
		return
	var over := speed - t.drag_free_speed
	var slowed := minf(maxf(speed - t.drag * over * over * delta, t.drag_free_speed), t.max_speed)
	velocity *= slowed / speed


func get_state() -> Dictionary:
	return {
		"kind": "soldier",
		"id": entity_id,
		"team": team,
		"position": global_position,
		"velocity": velocity,
		"yaw": yaw,
		"pitch": pitch,
		"energy": energy,
		"since_jet": since_jet,
		"grounded": grounded,
		"jetting": jetting,
		"jump_held": jump_held,
		"ski_held": ski_held,
		"skiing": skiing,
		"floor_normal": floor_normal,
		"health": health,
		"dead": dead,
		"respawn_in": respawn_in,
		"loadout": loadout.to_dict(),
		"next_loadout": next_loadout.to_dict(),
		"weapon": weapon,
		"ammo": ammo.duplicate(),
		"cooldown": cooldown,
		"spin": spin,
		"shots": shots,
		"grenades": grenades,
		"mines": mines,
		"throw_cooldown": throw_cooldown,
		"grenade_held": grenade_held,
		"mine_held": mine_held,
		"throw_pending": throw_pending,
		"pack_on": pack_on,
		"use_held": use_held,
		"repair_target": repair_target,
	}


func set_state(state: Dictionary) -> void:
	entity_id = state.id
	if state.team != team:
		set_team(state.team)
	var worn := Loadout.from_dict(state.loadout)
	if not worn.equals(loadout):
		set_loadout(worn)
	next_loadout = Loadout.from_dict(state.next_loadout)
	global_position = state.position
	velocity = state.velocity
	yaw = state.yaw
	pitch = state.pitch
	rotation = Vector3(0.0, yaw, 0.0)
	energy = state.energy
	since_jet = state.since_jet
	grounded = state.grounded
	jetting = state.jetting
	jump_held = state.jump_held
	ski_held = state.ski_held
	skiing = state.skiing
	floor_normal = state.floor_normal
	health = state.health
	dead = state.dead
	respawn_in = state.respawn_in
	weapon = state.weapon
	ammo.assign(state.ammo)
	cooldown = state.cooldown
	spin = state.spin
	shots = state.shots
	grenades = state.get("grenades", loadout.grenades)
	mines = state.get("mines", loadout.mines)
	throw_cooldown = state.get("throw_cooldown", 0.0)
	grenade_held = state.get("grenade_held", false)
	mine_held = state.get("mine_held", false)
	throw_pending = state.get("throw_pending", NO_THROW)
	pack_on = state.get("pack_on", false)
	use_held = state.get("use_held", false)
	repair_target = state.get("repair_target", 0)
	_set_alive_layers(not dead)
