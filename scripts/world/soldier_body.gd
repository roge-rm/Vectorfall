class_name SoldierBody
extends Node3D

## A soldier's body seen from outside, facing -z with its feet at the origin.
## Each moving part (hips, thighs, shins, torso with pack, head, arms) is one
## mesh merged from boxes, spheres and cylinders, coloured by its vertex
## colours, so a soldier is about ten draw calls. The build depends on the
## armour (light lean, heavy bulky) and the team (orange angular, blue
## rounded, each with its own helmet, shoulders, pack and chest mark). Each
## frame it reads the soldier and poses itself: a run cycle, a crouched ski
## stance with sparks, legs tucked in the air, a jet flame and a fall when
## dead. Only for looks; nothing here is match state.

enum Armour { LIGHT, MEDIUM, HEAVY }

const LIMB := Color(0.26, 0.28, 0.32, 0.0)
const PLATE := Color(0.72, 0.72, 0.7, 0.0)
const PALE := Color(0.96, 0.94, 0.88, 0.0)
const VISOR := Color(0.98, 0.96, 0.82, 0.0)
## White with full team amount: takes the team colour.
const TEAM := Color(1.0, 1.0, 1.0, 1.0)
const FLAME := Color(1.0, 0.55, 0.15)
const FLAME_CORE := Color(1.0, 0.95, 0.6)
const SPARK := Color(1.0, 0.92, 0.55)
## Medium armour's leg; the others scale it by their "leg" size.
const HIP_HEIGHT := 0.97
const THIGH := 0.46
const SHIN := 0.44
const FOOT := HIP_HEIGHT - THIGH - SHIN
## Right and left hands in aim space, and where the gun's grip sits.
const HANDS := [Vector3(0.17, -0.2, -0.3), Vector3(0.1, -0.15, -0.62)]
const GUN_AT := Vector3(0.17, -0.18, -0.36)
## Sizes by armour: torso width, limb thickness, shoulders, pack, helmet,
## chest depth and leg length. Light is slim and tall with a small pack,
## heavy is wide and squat with big shoulders, pack and legs, so each reads
## from its outline alone at 50 m.
const BUILDS := {
	Armour.LIGHT: {"width": 0.7, "limb": 0.66, "shoulder": 0.45, "pack": 0.58, "helmet": 0.88, "depth": 0.8, "leg": 1.12},
	Armour.MEDIUM: {"width": 1.0, "limb": 1.0, "shoulder": 1.0, "pack": 1.0, "helmet": 1.0, "depth": 1.0, "leg": 1.0},
	Armour.HEAVY: {"width": 1.42, "limb": 1.6, "shoulder": 2.1, "pack": 1.7, "helmet": 1.14, "depth": 1.35, "leg": 0.94},
}

## Meshes shared by every soldier, by part, team and armour.
static var _meshes: Dictionary[String, ArrayMesh] = {}

var soldier: Soldier
var team := 0
var armour := Armour.MEDIUM
var pose: Node3D
var hips: Node3D
var torso: Node3D
var head: Node3D
var aim: Node3D
var legs: Array[Node3D] = []
var knees: Array[Node3D] = []
var flame: MeshInstance3D
var sparks: MeshInstance3D
var guns: Array[Node3D] = []
var _views: Dictionary[String, Array] = {}
var _layer := 1
var _phase := 0.0
## How much of each pose shows, eased towards the soldier's state.
var _run := 0.0
var _ski := 0.0
var _air := 0.0
var _jet := 0.0
var _fallen := 0.0
var _flicker := RandomNumberGenerator.new()
## This armour's leg, in metres.
var _hip_height := HIP_HEIGHT
var _thigh := THIGH
var _shin := SHIN


func _init() -> void:
	name = "Body"
	pose = Node3D.new()
	add_child(pose)
	hips = _joint(pose, Vector3(0.0, HIP_HEIGHT, 0.0), "hips")
	for side: float in [1.0, -1.0]:
		var leg := _joint(hips, Vector3(side * 0.12, 0.0, 0.0), "thigh")
		var knee := _joint(leg, Vector3(0.0, -THIGH, 0.0), "shin")
		legs.append(leg)
		knees.append(knee)
	torso = _joint(pose, Vector3(0.0, HIP_HEIGHT, 0.0), "torso")
	head = _joint(torso, Vector3(0.0, 0.62, 0.0), "head")
	# Arms and gun turn together with the look pitch, about the shoulders.
	aim = _joint(torso, Vector3(0.0, 0.52, 0.0), "arms")
	for slot in Weapon.all.size():
		var gun := WeaponModels.build(slot)
		gun.position = GUN_AT
		aim.add_child(gun)
		guns.append(gun)

	# Both jet flames as one glowing mesh under the pack's nozzles.
	flame = _view(torso, "flame")
	flame.position = Vector3(0.0, 0.0, 0.26)
	flame.material_override = Cel.glow(Color.WHITE, true)
	flame.visible = false
	# Sparks off the skis, behind the feet.
	sparks = _view(pose, "sparks")
	sparks.position = Vector3(0.0, 0.04, 0.2)
	sparks.material_override = Cel.glow(Color.WHITE, true)
	sparks.visible = false
	_flicker.seed = 1
	set_look(0, Armour.MEDIUM)


func _joint(parent: Node3D, at: Vector3, part: String) -> Node3D:
	var joint := Node3D.new()
	joint.position = at
	parent.add_child(joint)
	var view := _view(joint, part)
	view.material_override = Cel.material(Color.WHITE, 1.0, true, true, false, true)
	return joint


func _view(parent: Node3D, part: String) -> MeshInstance3D:
	var view := MeshInstance3D.new()
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(view)
	if not _views.has(part):
		_views[part] = []
	_views[part].append(view)
	return view


## Builds the body for a team and armour, in the team's colour.
func set_look(new_team: int, new_armour: Armour) -> void:
	team = new_team
	armour = new_armour
	var build: Dictionary = BUILDS[armour]
	var leg: float = build.leg
	_thigh = THIGH * leg
	_shin = SHIN * leg
	_hip_height = _thigh + _shin + FOOT
	hips.position.y = _hip_height
	torso.position.y = _hip_height
	for k in 2:
		legs[k].position.x = (1.0 if k == 0 else -1.0) * 0.12 * sqrt(float(build.width))
		knees[k].position.y = -_thigh
	for part: String in _views:
		for view: MeshInstance3D in _views[part]:
			view.mesh = mesh(part, team, armour)
	set_team_colour(Soldier.TEAM_COLOURS[team % Soldier.TEAM_COLOURS.size()])
	set_render_layer(_layer)


func set_team_colour(colour: Color) -> void:
	for view: GeometryInstance3D in _meshes_under(self):
		Cel.set_team(view, colour)


func set_render_layer(layer: int) -> void:
	_layer = layer
	for view: GeometryInstance3D in _meshes_under(self):
		view.layers = layer


static func _meshes_under(node: Node, found: Array[GeometryInstance3D] = []) -> Array[GeometryInstance3D]:
	for child in node.get_children():
		if child is GeometryInstance3D:
			found.append(child)
		_meshes_under(child, found)
	return found


## The merged mesh for one part of a soldier, made once and shared.
static func mesh(part: String, for_team: int, for_armour: Armour) -> ArrayMesh:
	var key := "%s/%d/%d" % [part, for_team, for_armour]
	if not _meshes.has(key):
		var parts := _parts(part, for_team, BUILDS[for_armour])
		_meshes[key] = Cel.merged(parts, part == "flame" or part == "sparks")
	return _meshes[key]


static func _at(x: float, y: float, z: float, basis := Basis.IDENTITY) -> Transform3D:
	return Transform3D(basis, Vector3(x, y, z))


## The pieces of each part in its joint's space, as [mesh, transform, colour].
static func _parts(part: String, for_team: int, b: Dictionary) -> Array:
	var w: float = b.width
	var l: float = b.limb
	var s: float = b.shoulder
	var p: float = b.pack
	var h: float = b.helmet
	var d: float = b.depth
	var thigh: float = THIGH * float(b.leg)
	var shin: float = SHIN * float(b.leg)
	var angular := for_team == 0
	var parts := []
	match part:
		"hips":
			parts.append([Cel.box(Vector3(0.36 * w, 0.18, 0.22 * d)), _at(0, 0, 0), LIMB])
		"thigh":
			parts.append([Cel.box(Vector3(0.16 * l, thigh, 0.18 * l)), _at(0, -thigh * 0.5, 0), LIMB])
			parts.append([Cel.box(Vector3(0.19 * l, 0.17, 0.21 * l)), _at(0, -thigh * 0.35, -0.01), TEAM])
		"shin":
			parts.append([Cel.box(Vector3(0.15 * l, shin, 0.17 * l)), _at(0, -shin * 0.5, 0), PLATE])
			parts.append([Cel.box(Vector3(0.17 * l, 0.1, 0.28)), _at(0, -shin + 0.02, -0.05), LIMB])
			if l > 1.1:
				# Heavy: armoured knees.
				parts.append([Cel.box(Vector3(0.19 * l, 0.14, 0.08)), _at(0, -0.04, -0.1 * l), TEAM])
		"torso":
			_torso(parts, angular, w, s, p, d)
		"head":
			parts.append([Cel.box(Vector3(0.1, 0.08, 0.1)), _at(0, -0.02, 0), LIMB])
			if angular:
				parts.append([Cel.box(Vector3(0.27, 0.25, 0.3) * h), _at(0, 0.13, 0.01), TEAM])
				parts.append([Cel.box(Vector3(0.05, 0.09, 0.32) * h), _at(0, 0.28 * h, 0.02), LIMB])
				parts.append([Cel.box(Vector3(0.2, 0.045, 0.04) * h), _at(0, 0.14, -0.15 * h), VISOR])
			else:
				parts.append([Cel.sphere(0.16 * h, 0.3 * h, 10), _at(0, 0.13, 0.01), TEAM])
				parts.append([Cel.box(Vector3(0.27, 0.08, 0.1) * h), _at(0, 0.13, -0.11 * h), VISOR])
		"arms":
			for k in 2:
				var from := Vector3((0.27 if k == 0 else -0.27) * w, 0.0, 0.0)
				var to: Vector3 = HANDS[k]
				var basis := Basis.looking_at(to - from, Vector3.UP)
				parts.append([Cel.box(Vector3(0.12 * l, 0.12 * l, from.distance_to(to) + 0.06)), Transform3D(basis, (from + to) * 0.5), LIMB])
				parts.append([Cel.box(Vector3(0.13, 0.13, 0.13) * l), _at(to.x, to.y, to.z), PLATE])
		"flame":
			for side: float in [1.0, -1.0]:
				parts.append([Cel.cylinder(0.065 * p, 0.0, 0.55, 8), _at(side * 0.11 * p, -0.275, 0), FLAME])
				parts.append([Cel.cylinder(0.035 * p, 0.0, 0.3, 6), _at(side * 0.11 * p, -0.15, -0.02), FLAME_CORE])
		"sparks":
			# Short streaks fanning back from both feet.
			for k in 6:
				var side := 1.0 if k % 2 == 0 else -1.0
				var fan := Basis(Vector3.UP, side * (0.15 + 0.12 * (k / 2))) * Basis(Vector3.RIGHT, 0.25)
				var length := 0.25 + 0.12 * ((k * 7) % 3)
				parts.append([Cel.box(Vector3(0.025, 0.025, length)), Transform3D(fan, Vector3(side * 0.12, 0.0, length * 0.5 + 0.05 * (k / 2))), SPARK])
	return parts


static func _torso(parts: Array, angular: bool, w: float, s: float, p: float, d: float) -> void:
	parts.append([Cel.box(Vector3(0.34 * w, 0.16, 0.22 * d)), _at(0, 0.1, 0), LIMB])
	parts.append([Cel.box(Vector3(0.48 * w, 0.42, 0.3 * d)), _at(0, 0.36, 0), TEAM])
	var front := -0.15 * d - 0.01
	# The pack grows wider and deeper faster than it grows taller.
	var tall := sqrt(p)
	if p > 1.4:
		# Heavy: a block between the two halves of the pack.
		parts.append([Cel.box(Vector3(0.2 * p, 0.42 * tall, 0.12 * p)), _at(0, 0.34, 0.22 * d), LIMB])
	if angular:
		# Orange: slab shoulders sloping out, twin fin pack, a chevron.
		for side: float in [1.0, -1.0]:
			var slope := Basis(Vector3.BACK, side * -0.35)
			parts.append([Cel.box(Vector3(0.22, 0.08, 0.28) * Vector3(s, sqrt(s), s)), Transform3D(slope, Vector3(side * (0.27 * w + 0.06 * s), 0.6, 0)), TEAM])
			parts.append([Cel.box(Vector3(0.11 * p, 0.6 * tall, 0.16 * p)), _at(side * 0.12 * p, 0.36, 0.24 * d), LIMB])
			parts.append([Cel.box(Vector3(0.12 * p, 0.08 * tall, 0.18 * p)), _at(side * 0.12 * p, 0.36 + 0.3 * tall, 0.24 * d), TEAM])
			parts.append([Cel.box(Vector3(0.05, 0.22, 0.02)), Transform3D(Basis(Vector3.BACK, side * 0.75), Vector3(side * 0.065, 0.38, front)), PALE])
	else:
		# Blue: round shoulders, twin tank pack, a ring.
		for side: float in [1.0, -1.0]:
			parts.append([Cel.sphere(0.12 * s, 0.2 * s, 10), _at(side * (0.27 * w + 0.05 * s), 0.56, 0), TEAM])
			parts.append([Cel.cylinder(0.09 * p, 0.09 * p, 0.5 * tall, 10), _at(side * 0.1 * p, 0.34, 0.25 * d), LIMB])
			parts.append([Cel.sphere(0.09 * p, 0.12 * p, 10), _at(side * 0.1 * p, 0.34 + 0.25 * tall, 0.25 * d), TEAM])
		var flat := Basis(Vector3.RIGHT, PI * 0.5)
		parts.append([Cel.cylinder(0.09, 0.09, 0.02, 12), Transform3D(flat, Vector3(0, 0.4, front)), PALE])
		parts.append([Cel.cylinder(0.05, 0.05, 0.03, 10), Transform3D(flat, Vector3(0, 0.4, front - 0.005)), TEAM])
	# Nozzles at the bottom of the pack, where the flames come out.
	for side: float in [1.0, -1.0]:
		parts.append([Cel.cylinder(0.05 * p, 0.07 * p, 0.12, 8), _at(side * 0.11 * p, 0.06, 0.26), LIMB])


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
		reach = maxf(reach, _thigh * cos(hip_angles[k]) + _shin * cos(hip_angles[k] + knee_angles[k]))
	var drop := (_thigh + _shin - reach) * (1.0 - _air)
	var bob := absf(sin(_phase)) * 0.05 * _run
	hips.position.y = _hip_height - drop + bob
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
	flame.visible = _jet > 0.5
	flame.scale = Vector3(1.0, _flicker.randf_range(0.75, 1.15), 1.0)
	sparks.visible = on_ground and s.skiing and speed > 10.0
	if sparks.visible:
		var size := clampf(speed / 30.0, 0.6, 1.6)
		sparks.scale = Vector3(1.0, 1.0, size * _flicker.randf_range(0.6, 1.2))
		sparks.rotation.y = _flicker.randf_range(-0.15, 0.15)
		sparks.position.y = 0.04 - drop * 0.2
