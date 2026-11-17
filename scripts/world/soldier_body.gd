class_name SoldierBody
extends Node3D

## A soldier's body seen from outside, built from boxes, spheres and
## cylinders, facing -z with its feet at the origin. Each frame it reads the
## soldier and poses itself: a run cycle, a crouched ski stance, legs tucked
## in the air, a jet flame and a fall when dead. Only for looks; nothing here
## is match state.

const LIMB := Color(0.26, 0.28, 0.32)
const ARMOUR := Color(0.78, 0.78, 0.76)
const VISOR := Color(0.55, 0.95, 1.0)
const FLAME := Color(1.0, 0.55, 0.15)
const FLAME_CORE := Color(1.0, 0.95, 0.6)
const HIP_HEIGHT := 0.97
const THIGH := 0.46
const SHIN := 0.44
## Right and left shoulders and hands in aim space.
const SHOULDERS := [Vector3(0.27, 0.0, 0.0), Vector3(-0.27, 0.0, 0.0)]
const HANDS := [Vector3(0.17, -0.2, -0.3), Vector3(0.1, -0.15, -0.62)]
const GUN_AT := Vector3(0.17, -0.18, -0.36)

var soldier: Soldier
var pose: Node3D
var hips: Node3D
var torso: Node3D
var head: Node3D
var aim: Node3D
var legs: Array[Node3D] = []
var knees: Array[Node3D] = []
var flames: Array[Node3D] = []
var guns: Array[Node3D] = []
var _phase := 0.0
## How much of each pose shows, eased towards the soldier's state.
var _run := 0.0
var _ski := 0.0
var _air := 0.0
var _jet := 0.0
var _fallen := 0.0
var _flicker := RandomNumberGenerator.new()


func _init() -> void:
	name = "Body"
	pose = Node3D.new()
	add_child(pose)
	hips = Node3D.new()
	hips.position.y = HIP_HEIGHT
	pose.add_child(hips)
	_part(hips, Cel.box(Vector3(0.36, 0.18, 0.22)), Vector3.ZERO, Cel.material(LIMB))
	for side: float in [1.0, -1.0]:
		var leg := Node3D.new()
		leg.position.x = side * 0.12
		hips.add_child(leg)
		_part(leg, Cel.box(Vector3(0.16, THIGH, 0.18)), Vector3(0.0, -THIGH * 0.5, 0.0), Cel.material(LIMB))
		_part(leg, Cel.box(Vector3(0.18, 0.16, 0.2)), Vector3(0.0, -THIGH * 0.35, -0.01), Cel.material(ARMOUR, 1.0))
		var knee := Node3D.new()
		knee.position.y = -THIGH
		leg.add_child(knee)
		_part(knee, Cel.box(Vector3(0.15, SHIN, 0.17)), Vector3(0.0, -SHIN * 0.5, 0.0), Cel.material(ARMOUR))
		_part(knee, Cel.box(Vector3(0.17, 0.1, 0.28)), Vector3(0.0, -SHIN + 0.02, -0.05), Cel.material(LIMB))
		legs.append(leg)
		knees.append(knee)

	torso = Node3D.new()
	torso.position.y = HIP_HEIGHT
	pose.add_child(torso)
	_part(torso, Cel.box(Vector3(0.34, 0.16, 0.22)), Vector3(0.0, 0.1, 0.0), Cel.material(LIMB))
	_part(torso, Cel.box(Vector3(0.48, 0.42, 0.3)), Vector3(0.0, 0.36, 0.0), Cel.material(ARMOUR, 1.0))
	for side: float in [1.0, -1.0]:
		_part(torso, Cel.box(Vector3(0.18, 0.12, 0.24)), Vector3(side * 0.31, 0.56, 0.0), Cel.material(ARMOUR, 1.0))
	head = Node3D.new()
	head.position.y = 0.62
	torso.add_child(head)
	_part(head, Cel.box(Vector3(0.1, 0.08, 0.1)), Vector3(0.0, -0.02, 0.0), Cel.material(LIMB))
	_part(head, Cel.sphere(0.16, 0.3, 10), Vector3(0.0, 0.13, 0.01), Cel.material(ARMOUR, 1.0))
	_part(head, Cel.box(Vector3(0.24, 0.08, 0.08)), Vector3(0.0, 0.14, -0.12), Cel.glow(VISOR))

	# The jetpack on the back, with a nozzle and a flame on each side.
	var pack := Node3D.new()
	pack.position = Vector3(0.0, 0.34, 0.24)
	torso.add_child(pack)
	_part(pack, Cel.box(Vector3(0.4, 0.46, 0.18)), Vector3.ZERO, Cel.material(LIMB))
	_part(pack, Cel.box(Vector3(0.42, 0.08, 0.2)), Vector3(0.0, 0.12, 0.0), Cel.material(ARMOUR, 1.0))
	for side: float in [1.0, -1.0]:
		_part(pack, Cel.cylinder(0.05, 0.07, 0.12, 8), Vector3(side * 0.11, -0.28, 0.02), Cel.material(LIMB))
		var flame := Node3D.new()
		flame.position = Vector3(side * 0.11, -0.34, 0.02)
		pack.add_child(flame)
		_part(flame, Cel.cylinder(0.065, 0.0, 0.55, 8), Vector3(0.0, -0.275, 0.0), Cel.glow(FLAME))
		_part(flame, Cel.cylinder(0.035, 0.0, 0.3, 6), Vector3(0.0, -0.15, 0.0), Cel.glow(FLAME_CORE))
		flame.visible = false
		flames.append(flame)

	# Arms and gun turn together with the look pitch, about the shoulders.
	aim = Node3D.new()
	aim.position.y = 0.52
	torso.add_child(aim)
	for k in 2:
		var from: Vector3 = SHOULDERS[k]
		var to: Vector3 = HANDS[k]
		var arm := _part(aim, Cel.box(Vector3(0.12, 0.12, from.distance_to(to) + 0.06)), (from + to) * 0.5, Cel.material(LIMB))
		arm.basis = Basis.looking_at(to - from, Vector3.UP)
		_part(aim, Cel.box(Vector3(0.13, 0.13, 0.13)), to, Cel.material(ARMOUR))
	for slot in Weapon.all.size():
		var gun := WeaponModels.build(slot)
		gun.position = GUN_AT
		gun.scale = Vector3.ONE * 1.0
		aim.add_child(gun)
		guns.append(gun)
	_flicker.seed = 1


func _part(parent: Node3D, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.position = at
	view.material_override = material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(view)
	return view


func set_team_colour(colour: Color) -> void:
	for view: GeometryInstance3D in _meshes(self):
		view.set_instance_shader_parameter("team_colour", colour)


func set_render_layer(layer: int) -> void:
	for view: GeometryInstance3D in _meshes(self):
		view.layers = layer


static func _meshes(node: Node, found: Array[GeometryInstance3D] = []) -> Array[GeometryInstance3D]:
	for child in node.get_children():
		if child is GeometryInstance3D:
			found.append(child)
		_meshes(child, found)
	return found


func _process(delta: float) -> void:
	if soldier == null:
		return
	var s := soldier
	var speed := s.horizontal_speed()
	var blend := minf(delta * 10.0, 1.0)
	var on_ground := s.grounded and not s.dead
	_run = lerpf(_run, clampf(speed / s.tuning.run_speed, 0.0, 1.0) if on_ground and not s.skiing else 0.0, blend)
	_ski = lerpf(_ski, 1.0 if on_ground and s.skiing else 0.0, blend)
	_air = lerpf(_air, 1.0 if not s.grounded and not s.dead else 0.0, blend)
	_jet = lerpf(_jet, 1.0 if s.jetting and not s.dead else 0.0, blend)
	_fallen = move_toward(_fallen, 1.0 if s.dead else 0.0, delta * (2.5 if s.dead else 100.0))
	# About one stride every 2.2 m.
	_phase = wrapf(_phase + speed * delta * TAU / 2.2, 0.0, TAU)

	var swing := sin(_phase)
	var hip_angles := [swing * 0.7 * _run, -swing * 0.7 * _run]
	var knee_angles := [-(0.15 + 0.7 * maxf(0.0, -cos(_phase))) * _run, -(0.15 + 0.7 * maxf(0.0, cos(_phase))) * _run]
	# Skiing: crouched, one foot a little ahead. In the air: knees tucked,
	# straighter while jetting.
	var air_hips := [lerpf(0.45, 0.15, _jet), lerpf(0.1, -0.1, _jet)]
	var air_knees := [lerpf(-0.6, -0.3, _jet), lerpf(-0.95, -0.4, _jet)]
	for k in 2:
		hip_angles[k] += [0.55, 0.35][k] * _ski + air_hips[k] * _air
		knee_angles[k] += [-0.85, -0.75][k] * _ski + air_knees[k] * _air
		legs[k].rotation = Vector3(hip_angles[k] * (1.0 - _fallen), 0.0, (1.0 if k == 0 else -1.0) * 0.06 * (_ski + _air))
		knees[k].rotation.x = knee_angles[k] * (1.0 - _fallen)
	# Lower the hips so bent legs keep the feet on the ground.
	var reach := 0.0
	for k in 2:
		reach = maxf(reach, THIGH * cos(hip_angles[k]) + SHIN * cos(hip_angles[k] + knee_angles[k]))
	var drop := (THIGH + SHIN - reach) * (1.0 - _air)
	var bob := absf(sin(_phase)) * 0.05 * _run
	hips.position.y = HIP_HEIGHT - drop + bob
	torso.position.y = hips.position.y
	torso.rotation.x = -0.12 * _run - 0.3 * _ski - 0.1 * _air
	var look := s.pitch * (1.0 - _fallen)
	head.rotation.x = clampf(look * 0.5, -0.5, 0.5) - torso.rotation.x * 0.5
	aim.rotation.x = look - torso.rotation.x
	# Dead: tip over backwards onto the ground.
	pose.rotation.x = _fallen * PI * 0.48
	pose.position.y = _fallen * 0.28
	for k in guns.size():
		guns[k].visible = k == s.weapon
	var spinner := guns[Weapon.CHAINGUN].get_node("Spinner") as Node3D
	spinner.rotation.z += s.spin * delta * 40.0
	for flame in flames:
		flame.visible = _jet > 0.5
		flame.scale = Vector3(1.0, _flicker.randf_range(0.75, 1.15), 1.0)
