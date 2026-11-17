class_name Soldier
extends CharacterBody3D

## A soldier, moved only by simulate() with one PlayerCommand per physics
## tick. Its origin is at its feet. Everything simulate() reads is in
## get_state(), so a copy given the same state and commands moves the same.

const TEAM_COLOURS: Array[Color] = [Color(1.0, 0.45, 0.15), Color(0.2, 0.6, 1.0)]
const TEAM_NAMES: Array[String] = ["Orange", "Blue"]
const PITCH_LIMIT := 1.45
## Render layer for your own body, which your camera leaves out.
const OWN_BODY_LAYER := 2
## The gun's muzzle from the eye, in look space: right, down and ahead.
const MUZZLE := Vector3(0.22, -0.2, -0.6)
## Seconds after switching weapons before the new one can fire.
const SWITCH_TIME := 0.3

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
## Slot of the weapon in hand, an index into Weapon.all.
var weapon := 0
## Rounds left for each weapon slot.
var ammo: Array[int] = []
## Seconds until the weapon in hand can fire again.
var cooldown := 0.0
## How far a weapon that spins up has spun, 0 to 1.
var spin := 0.0
## Shots fired since the start, so the view model can kick on each one.
var shots := 0

var body: SoldierBody
var blob: BlobShadow


func _init() -> void:
	energy = tuning.energy_max
	since_jet = tuning.refill_delay
	health = tuning.health_max
	for w in Weapon.all:
		ammo.append(w.ammo)
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

	blob = BlobShadow.new()
	add_child(blob)


func _ready() -> void:
	set_team(team)


func set_team(value: int) -> void:
	team = value
	body.set_team_colour(TEAM_COLOURS[team % TEAM_COLOURS.size()])


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
	_set_alive_layers(false)


## Back to full health, energy and ammo at a spawn point.
func revive(where: Transform3D) -> void:
	dead = false
	health = tuning.health_max
	energy = tuning.energy_max
	since_jet = tuning.refill_delay
	for k in Weapon.all.size():
		ammo[k] = Weapon.all[k].ammo
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
	return Transform3D(basis, global_position + Vector3.UP * tuning.eye_height)


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func simulate(command: PlayerCommand, delta: float) -> void:
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
		if since_jet >= t.refill_delay:
			energy = minf(energy + t.energy_refill * delta, t.energy_max)

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
	blob.follow(self)
	if dead:
		respawn_in -= delta
		if respawn_in <= 0.0 and game != null:
			game.respawn(self)
	else:
		_use_weapon(command, delta)


## Switching weapons and firing, after moving so a shot leaves from where you
## are now with the speed you have now.
func _use_weapon(command: PlayerCommand, delta: float) -> void:
	var count := Weapon.all.size()
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
	var w := Weapon.all[weapon]
	var trigger := command.has(PlayerCommand.FIRE) and ammo[weapon] > 0
	if w.spin_up > 0.0:
		spin = move_toward(spin, 1.0, delta / w.spin_up) if trigger else move_toward(spin, 0.0, delta / w.spin_down)
	if trigger and cooldown <= 0.0 and spin >= w.spin_to_fire and game != null:
		game.fire(self)
		ammo[weapon] -= 1
		shots += 1
		cooldown = w.interval_at(spin)


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
		"weapon": weapon,
		"ammo": ammo.duplicate(),
		"cooldown": cooldown,
		"spin": spin,
		"shots": shots,
	}


func set_state(state: Dictionary) -> void:
	entity_id = state.id
	if state.team != team:
		set_team(state.team)
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
	_set_alive_layers(not dead)
