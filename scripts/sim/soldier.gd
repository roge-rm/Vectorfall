class_name Soldier
extends CharacterBody3D

## A soldier, moved only by simulate() with one PlayerCommand per physics
## tick. Its origin is at its feet. Everything simulate() reads is in
## get_state(), so a copy given the same state and commands moves the same.

const TEAM_COLOURS: Array[Color] = [Color(1.0, 0.45, 0.15), Color(0.2, 0.6, 1.0)]
const PITCH_LIMIT := 1.45
## Render layer for your own body, which your camera leaves out.
const OWN_BODY_LAYER := 2

var entity_id := 0
var team := 0
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

var body_mesh: MeshInstance3D
var blob: BlobShadow


func _init() -> void:
	energy = tuning.energy_max
	since_jet = tuning.refill_delay
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)
	floor_constant_speed = true
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = tuning.radius
	capsule.height = tuning.height
	shape.shape = capsule
	shape.position.y = tuning.height * 0.5
	add_child(shape)

	# A stand-in body until soldiers get real ones.
	body_mesh = MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius = tuning.radius
	body.height = tuning.height
	body.radial_segments = 16
	body.rings = 6
	body_mesh.mesh = body
	body_mesh.position.y = tuning.height * 0.5
	body_mesh.material_override = Cel.material(Color(0.85, 0.85, 0.85), 0.8)
	add_child(body_mesh)

	blob = BlobShadow.new()
	add_child(blob)


func _ready() -> void:
	set_team(team)


func set_team(value: int) -> void:
	team = value
	body_mesh.set_instance_shader_parameter("team_colour", TEAM_COLOURS[team % TEAM_COLOURS.size()])


## Hides your own body from your camera.
func set_first_person(on: bool) -> void:
	body_mesh.layers = OWN_BODY_LAYER if on else 1


func eye_transform() -> Transform3D:
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	return Transform3D(basis, global_position + Vector3.UP * tuning.eye_height)


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func simulate(command: PlayerCommand, delta: float) -> void:
	var t := tuning
	yaw = wrapf(command.yaw, -PI, PI)
	pitch = clampf(command.pitch, -PITCH_LIMIT, PITCH_LIMIT)
	rotation = Vector3(0.0, yaw, 0.0)
	var move := command.move.limit_length(1.0)
	var wish := Basis(Vector3.UP, yaw) * Vector3(move.x, 0.0, -move.y)
	var wish_dir := wish.normalized() if wish.length() > 0.01 else Vector3.ZERO
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var v_y := velocity.y

	jetting = command.has(PlayerCommand.JET) and energy > 0.0
	if grounded and not jetting:
		var speed := horizontal.length()
		var target := wish * t.run_speed
		if speed > t.run_speed + 0.01 and horizontal.dot(wish) >= 0.0:
			# Above run speed you keep your speed, fading slowly, and only braking
			# by pulling back takes it off faster.
			horizontal = horizontal.normalized() * maxf(speed - t.overspeed_decay * delta, t.run_speed)
		else:
			var rate := t.ground_accel if wish_dir != Vector3.ZERO else t.ground_friction
			horizontal = horizontal.move_toward(target, rate * delta)
		if command.has(PlayerCommand.JUMP):
			v_y = t.jump_speed
			grounded = false
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

	v_y -= t.gravity * delta
	var before := Vector3(horizontal.x, v_y, horizontal.z)
	velocity = before
	var was_grounded := grounded
	move_and_slide()
	grounded = is_on_floor()
	if grounded and not was_grounded:
		# Landing on a slope turns the fall into speed along it, so landing on a
		# downhill keeps your speed and can add to it.
		var along := before.slide(get_floor_normal())
		var kept := Vector3(along.x, 0.0, along.z)
		if kept.length() > horizontal_speed():
			velocity.x = kept.x
			velocity.z = kept.z
	blob.follow(self)


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
