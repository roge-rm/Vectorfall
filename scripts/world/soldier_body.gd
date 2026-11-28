class_name SoldierBody
extends Node3D

## A soldier's body seen from outside, facing -z with its feet at the origin.
## Each moving part (hips, thighs, shins, torso with pack, head, arms) is one
## mesh merged from bevelled boxes and turned shapes, coloured by its vertex
## colours, so a soldier is about ten draw calls. Each part comes in two
## versions: the detailed one up close and a cheaper one past FAR_DISTANCE,
## with fewer, plainer pieces and more team colour so the team reads at
## range. Only one of the two draws at a time. The build depends on the
## armour (light lean, heavy bulky) and the team (lime angular, blue
## rounded, each with its own helmet, shoulders, pack and chest mark). Each
## frame it reads the soldier and poses itself: a run cycle, a crouched ski
## stance with sparks, legs tucked in the air, a jet flame and a fall when
## dead. The pack carried shows as a small part on the back, merged into the
## torso, and a shield or jammer that's on shows a shell or a flickering
## antenna tip. Only for looks; nothing here is match state.

enum Armour { LIGHT, MEDIUM, HEAVY }

## Undersuit, secondary plates, belts and vents, markings and visor.
const LIMB := Color(0.38, 0.37, 0.44, 0.0)
const PLATE := Color(0.8, 0.79, 0.82, 0.0)
const DARK := Color(0.15, 0.14, 0.18, 0.0)
const PALE := Color(0.98, 0.96, 0.9, 0.0)
const VISOR := Color(1.0, 0.86, 0.4, 0.0)
## Packs and tanks, lighter than the undersuit so they read from behind.
const PACK := Color(0.58, 0.57, 0.64, 0.0)
const ARMOUR_TRIM := Color(0.48, 0.47, 0.57, 0.0)
const UPRIGHT := Basis(Vector3.RIGHT, -PI * 0.5)
## White with full team amount: takes the team colour.
const TEAM := Color(1.0, 1.0, 1.0, 1.0)
## The undersuit in the far version: half team colour, so the whole figure
## reads as its team at range.
const FAR_LIMB := Color(0.6, 0.6, 0.64, 0.7)
const FLAME := Color(1.0, 0.55, 0.15)
const FLAME_CORE := Color(1.0, 0.95, 0.6)
const SPARK := Color(1.0, 0.92, 0.55)
const SHIELD_FLASH_TIME := 0.18
## Pack part colours: the repair cross and the ammo crate.
const CROSS := Color(0.92, 0.2, 0.32, 0.0)
const CRATE := Color(0.66, 0.58, 0.34, 0.0)
const JAM_TIP := Color(1.0, 0.95, 0.75)
## Past this many metres from the camera the far version draws instead.
const FAR_DISTANCE := 25.0
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

## How much detail the near version has: 0 the main shapes only, 1 the
## phone look with plates, pouches, belts, pads and vents, 2 adds cables,
## antennas and small slats. Each piece says the level it needs, so a
## graphics setting can set this before soldiers are made.
static var detail := 1
## Meshes shared by every soldier, by part, team, armour and detail.
static var _meshes: Dictionary[String, ArrayMesh] = {}
## While building: the far version, and the detail level wanted.
static var _far := false
static var _level := 1
static var _pack := -1
## The shield shell's look: see-through with a rim in the team colour.
static var _shell_shader: Shader
static var _shells: Dictionary[String, ShaderMaterial] = {}

var soldier: Soldier
var team := 0
var armour := Armour.MEDIUM
## The pack on the back, a Pack slot or Loadout.NO_PACK.
var pack := Loadout.NO_PACK
var pose: Node3D
var hips: Node3D
var torso: Node3D
var head: Node3D
var aim: Node3D
var legs: Array[Node3D] = []
var knees: Array[Node3D] = []
var flame: MeshInstance3D
var sparks: MeshInstance3D
## Shown while a shield is on, and the glowing tip of a jammer's antenna
## while it's on.
var shell: MeshInstance3D
var jam_tip: MeshInstance3D
## Gun models for the carried weapons, by weapon slot, set by set_weapons().
var guns: Dictionary[int, Node3D] = {}
## Near and far views by part.
var _views: Dictionary[String, Array] = {}
var _far_views: Dictionary[String, Array] = {}
var _layer := 1
var _team_colour := Color.WHITE
var _phase := 0.0
## How much of each pose shows, eased towards the soldier's state.
var _run := 0.0
var _ski := 0.0
var _air := 0.0
var _jet := 0.0
var _fallen := 0.0
var _flicker := RandomNumberGenerator.new()
var _shield_flash_left := 0.0
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
		var leg := _joint(hips, Vector3(side * 0.12, 0.0, 0.0), "thigh_r" if side > 0.0 else "thigh_l")
		var knee := _joint(leg, Vector3(0.0, -THIGH, 0.0), "shin")
		legs.append(leg)
		knees.append(knee)
	torso = _joint(pose, Vector3(0.0, HIP_HEIGHT, 0.0), "torso")
	head = _joint(torso, Vector3(0.0, 0.62, 0.0), "head")
	# Arms and gun turn together with the look pitch, about the shoulders.
	aim = _joint(torso, Vector3(0.0, 0.52, 0.0), "arms")

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
	shell = MeshInstance3D.new()
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.mesh = Cel.sphere(1.0, 2.0, 16)
	shell.visible = false
	pose.add_child(shell)
	jam_tip = _view(torso, "jam_tip")
	jam_tip.material_override = Cel.glow(Color.WHITE, true)
	jam_tip.visible = false
	_flicker.seed = 1
	set_look(0, Armour.MEDIUM)


func _joint(parent: Node3D, at: Vector3, part: String) -> Node3D:
	var joint := Node3D.new()
	joint.position = at
	parent.add_child(joint)
	var view := _view(joint, part)
	view.material_override = Cel.material(Color.WHITE, 1.0, true, true, false, true, false, true)
	view.visibility_range_end = FAR_DISTANCE
	var far := _view(joint, part, true)
	far.material_override = view.material_override
	far.visibility_range_begin = FAR_DISTANCE
	return joint


func _view(parent: Node3D, part: String, far := false) -> MeshInstance3D:
	var view := MeshInstance3D.new()
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(view)
	var views := _far_views if far else _views
	if not views.has(part):
		views[part] = []
	views[part].append(view)
	return view


## Builds the body for a team, armour and pack (a Pack slot or
## Loadout.NO_PACK), in the team's colour. Leaving out the pack keeps the one
## it has.
func set_look(new_team: int, new_armour: Armour, new_pack := -2) -> void:
	team = new_team
	armour = new_armour
	if new_pack != -2:
		pack = new_pack
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
			view.mesh = mesh(part, team, armour, false, pack)
	for part: String in _far_views:
		for view: MeshInstance3D in _far_views[part]:
			view.mesh = mesh(part, team, armour, true, pack)
	# The shell sits round the body from the knees to above the helmet.
	var width := 0.4 + 0.12 * float(build.width) + 0.06 * float(build.shoulder)
	shell.scale = Vector3(width, 1.05 * sqrt(leg), 0.42 + 0.06 * float(build.pack))
	shell.position.y = _hip_height + 0.12
	jam_tip.position = _antenna_tip(build)
	set_team_colour(Palette.team(team))
	set_render_layer(_layer)


## Puts a different pack on the back, a Pack slot or Loadout.NO_PACK.
func set_pack(new_pack: int) -> void:
	if new_pack != pack:
		set_look(team, armour, new_pack)


## Builds gun models for these weapon slots and drops the rest. The meshes
## are shared, so this only makes a few nodes.
func set_weapons(slots: Array[int]) -> void:
	for slot: int in guns.keys():
		if not slots.has(slot):
			guns[slot].visible = false
			guns[slot].queue_free()
			guns.erase(slot)
	for slot in slots:
		if guns.has(slot):
			continue
		var gun := WeaponModels.build(slot)
		gun.position = GUN_AT
		gun.visible = false
		aim.add_child(gun)
		guns[slot] = gun
		for view: GeometryInstance3D in _meshes_under(gun):
			Cel.set_team(view, _team_colour)
			view.layers = _layer


func set_team_colour(colour: Color) -> void:
	_team_colour = colour
	for view: GeometryInstance3D in _meshes_under(self):
		if view != shell and view != jam_tip:
			Cel.set_team(view, colour)
	shell.material_override = shell_material(colour, _shield_flash_left > 0.0)


func flash_shield() -> void:
	if _shield_flash_left <= 0.0:
		shell.material_override = shell_material(_team_colour, true)
	_shield_flash_left = SHIELD_FLASH_TIME


## A see-through shell in a team colour, faint in the middle and stronger at
## the rim, with a thin ink edge. Shared by colour and hit state.
static func shell_material(colour: Color, flashing := false) -> ShaderMaterial:
	var key := "%s/%s" % [colour.to_html(), flashing]
	if _shells.has(key):
		return _shells[key]
	if _shell_shader == null:
		_shell_shader = Shader.new()
		_shell_shader.code = """shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec3 colour : source_color;
uniform vec3 ink : source_color;
uniform float flash = 0.0;
void fragment() {
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	float edge = smoothstep(0.86, 0.9, rim);
	ALBEDO = mix(mix(colour, vec3(1.0), flash * 0.68), ink, edge);
	ALPHA = mix(0.12 + flash * 0.4 + 0.6 * pow(rim, 2.5), 0.8, edge);
}
"""
	var made := ShaderMaterial.new()
	made.shader = _shell_shader
	made.set_shader_parameter("colour", colour.lightened(0.25))
	made.set_shader_parameter("ink", Color(0.14, 0.04, 0.18))
	made.set_shader_parameter("flash", 1.0 if flashing else 0.0)
	_shells[key] = made
	return made


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


## The merged mesh for one part of a soldier, made once and shared: the
## near version at the current detail level, or the far version. Only the
## torso depends on the pack.
static func mesh(part: String, for_team: int, for_armour: Armour, far := false, with_pack := -1) -> ArrayMesh:
	var level := -1 if far else detail
	if part != "torso":
		with_pack = -1
	var key := "%s/%d/%d/%d/%d" % [part, for_team, for_armour, level, with_pack]
	if not _meshes.has(key):
		_far = far
		_level = 0 if far else detail
		_pack = with_pack
		var parts := _parts(part, for_team, BUILDS[for_armour], not far)
		_meshes[key] = Cel.merged(parts, part == "flame" or part == "sparks" or part == "jam_tip")
		_far = false
		_pack = -1
	return _meshes[key]


static func _at(x: float, y: float, z: float, basis := Basis.IDENTITY) -> Transform3D:
	return Transform3D(basis, Vector3(x, y, z))


## Adds a piece if the detail level has it, recoloured for the far version.
static func _add(parts: Array, piece: Mesh, where: Transform3D, colour: Color, level := 0) -> void:
	if level > _level:
		return
	if _far and colour == LIMB:
		colour = FAR_LIMB
	parts.append([piece, where, colour])


## A bevelled box, or a plain one in the far version.
static func _block(size: Vector3, bevel := 0.02) -> Mesh:
	return Cel.box(size) if _far else Cel.bevel_box(size, bevel)


## A short cylinder along y with bevelled rims, plainer far away.
static func _drum(radius: float, height: float, bevel := 0.012) -> Mesh:
	return Cel.cylinder(radius, radius, height, 6) if _far else Cel.bevel_cylinder(radius, height, bevel, 10)


## A turned shape from a (radius, height) profile, bottom up.
static func _turned(profile: PackedVector2Array) -> Mesh:
	return Cel.lathe(profile, 6 if _far else 12)


## The pieces of each part in its joint's space, as [mesh, transform, colour].
static func _parts(part: String, for_team: int, b: Dictionary, shaped: bool) -> Array:
	var w: float = b.width
	var l: float = b.limb
	var h: float = b.helmet
	var thigh: float = THIGH * float(b.leg)
	var shin: float = SHIN * float(b.leg)
	var heavy := l > 1.1
	var angular := for_team == 0
	var parts := []
	match part:
		"hips":
			_add(parts, _block(Vector3(0.36 * w, 0.18, 0.22 * b.depth)), _at(0, 0, 0), LIMB)
			# A plate in front and tassets over each hip.
			_add(parts, _block(Vector3(0.14 * w, 0.12, 0.04), 0.012), _at(0, -0.05, -0.11 * b.depth - 0.012), PLATE, 1)
			for side: float in [1.0, -1.0]:
				var tilt := Basis(Vector3.BACK, side * 0.18)
				_add(parts, _block(Vector3(0.05, 0.15, 0.18 * b.depth), 0.012), Transform3D(tilt, Vector3(side * (0.18 * w + 0.02), -0.04, -0.01)), TEAM, 0 if heavy else 1)
		"thigh_r", "thigh_l":
			var side := 1.0 if part == "thigh_r" else -1.0
			_add(parts, _block(Vector3(0.16 * l, thigh, 0.18 * l), 0.025), _at(0, -thigh * 0.5, 0), LIMB)
			if shaped:
				_add(parts, Cel.loft([
					Vector4(0.061 * l, 0.077 * l, -thigh * 0.217, 0), Vector4(0.102 * l, 0.093 * l, thigh * 0.043, 0),
					Vector4(0.086 * l, 0.09 * l, thigh * 0.228, 0),
				], 0.75), _at(0, -thigh * 0.35, -0.02 * l, UPRIGHT), TEAM)
			else:
				_add(parts, _block(Vector3(0.19 * l, 0.17, 0.21 * l), 0.03), _at(0, -thigh * 0.35, -0.01), TEAM)
			# A strap and a pouch on the outside.
			_add(parts, Cel.box(Vector3(0.16 * l + 0.012, 0.03, 0.18 * l + 0.012)), _at(0, -thigh * 0.72, 0), DARK, 1)
			_add(parts, _block(Vector3(0.05, 0.1, 0.11), 0.012), _at(side * (0.08 * l + 0.025), -thigh * 0.66, 0.0), PLATE, 1)
		"shin":
			_add(parts, _block(Vector3(0.15 * l, shin, 0.17 * l), 0.025), _at(0, -shin * 0.5, 0), ARMOUR_TRIM if shaped else LIMB)
			if shaped:
				_add(parts, Cel.loft([
					Vector4(0.051 * l, 0.030 * l, -shin * 0.318, 0), Vector4(0.077 * l, 0.056 * l, -shin * 0.091, 0),
					Vector4(0.086 * l, 0.061 * l, shin * 0.239, 0),
				], 0.84), _at(0, -shin * 0.46, -0.065 * l, UPRIGHT), PLATE)
			else:
				_add(parts, _block(Vector3(0.16 * l, shin * 0.62, 0.05), 0.015), _at(0, -shin * 0.42, -0.085 * l), PLATE)
			# Knee pads, bigger and always there on heavy.
			if heavy:
				_add(parts, _block(Vector3(0.19 * l, 0.15, 0.08), 0.025), _at(0, -0.03, -0.1 * l), TEAM)
			else:
				_add(parts, _block(Vector3(0.17 * l, 0.11, 0.07), 0.02), _at(0, -0.03, -0.09 * l), TEAM, 1)
			# Boot with a cuff, toe cap and sole.
			_add(parts, _block(Vector3(0.17 * l, 0.12, 0.28), 0.025), _at(0, -shin + 0.02, -0.05), DARK)
			_add(parts, Cel.box(Vector3(0.17 * l + 0.016, 0.04, 0.17 * l + 0.016)), _at(0, -shin + 0.1, 0), PLATE, 1)
			_add(parts, _block(Vector3(0.17 * l + 0.01, 0.07, 0.08), 0.015), _at(0, -shin - 0.005, -0.165), PLATE, 1)
			_add(parts, Cel.box(Vector3(0.18 * l, 0.03, 0.3)), _at(0, -shin - 0.045, -0.05), LIMB, 1)
			# Vent lines down the shin guard.
			for k in 2:
				_add(parts, Cel.box(Vector3(0.012, shin * 0.36, 0.012)), _at((k - 0.5) * 0.05 * l, -shin * 0.42, -0.085 * l - 0.03), DARK, 2)
		"torso":
			_torso(parts, angular, b, shaped)
			_pack_part(parts, b)
		"jam_tip":
			parts.append([Cel.sphere(0.035, 0.07, 6), Transform3D.IDENTITY, JAM_TIP])
			for k in 3:
				var spoke := Basis(Vector3.UP, k * PI / 3.0) * Basis(Vector3.BACK, PI * 0.5)
				parts.append([Cel.box(Vector3(0.012, 0.16, 0.012)), Transform3D(spoke, Vector3.ZERO), JAM_TIP])
		"head":
			_head(parts, angular, h)
		"arms":
			for k in 2:
				var from := Vector3((0.27 if k == 0 else -0.27) * w, 0.0, 0.0)
				var to: Vector3 = HANDS[k]
				var basis := Basis.looking_at(to - from, Vector3.UP)
				var length := from.distance_to(to)
				var along := func(t: float) -> Transform3D: return Transform3D(basis, from.lerp(to, t))
				_add(parts, _block(Vector3(0.12 * l, 0.12 * l, length + 0.06), 0.02), along.call(0.5), LIMB)
				_add(parts, _block(Vector3(0.13, 0.13, 0.13) * l, 0.025), _at(to.x, to.y, to.z), PLATE)
				# Elbow pad, forearm guard in team colour and a wrist strap.
				_add(parts, _block(Vector3(0.15 * l, 0.15 * l, 0.09), 0.02), along.call(0.42), PLATE, 1)
				if shaped and _level > 0:
					var sweep := -0.018 * l if angular else 0.012 * l
					var guard := Cel.loft([
						Vector4(0.044 * l, 0.038 * l, -length * 0.17, sweep),
						Vector4(0.076 * l, 0.049 * l, -length * 0.04, 0),
						Vector4(0.068 * l, 0.066 * l, length * 0.18, 0),
					], 0.42 if angular else 0.88)
					var plate: Transform3D = along.call(0.71)
					plate.origin += plate.basis.y * 0.028 * l
					_add(parts, guard, plate, TEAM, 1)
				_add(parts, Cel.box(Vector3(0.135 * l, 0.135 * l, 0.025)), along.call(0.9), DARK, 2)
		"flame":
			var p: float = b.pack
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


## Lime: a box helmet with a crest, a slit visor, cheek plates and side
## vents. Blue: a dome with a visor band, ear discs, a brim and a ridge.
static func _head(parts: Array, angular: bool, h: float) -> void:
	_add(parts, Cel.box(Vector3(0.1, 0.08, 0.1)), _at(0, -0.02, 0), LIMB)
	if angular:
		if _far:
			_add(parts, _block(Vector3(0.27, 0.25, 0.3) * h, 0.035), _at(0, 0.13, 0.01), TEAM)
		else:
			var helmet := Cel.loft([
				Vector4(0.092 * h, 0.095 * h, -0.145 * h, 0),
				Vector4(0.136 * h, 0.119 * h, -0.047 * h, 0),
				Vector4(0.122 * h, 0.116 * h, 0.096 * h, 0),
				Vector4(0.091 * h, 0.085 * h, 0.15 * h, 0),
			], 0.67)
			_add(parts, helmet, _at(0, 0.13, 0.01), TEAM)
		_add(parts, _block(Vector3(0.05, 0.09, 0.32) * h, 0.012), _at(0, 0.28 * h, 0.02), LIMB)
		_add(parts, _block(Vector3(0.21, 0.05, 0.04) * h, 0.01), _at(0, 0.14, -0.15 * h), VISOR)
		_add(parts, _block(Vector3(0.17, 0.07, 0.06) * h, 0.015), _at(0, 0.045, -0.14 * h), PLATE, 1)
		for side: float in [1.0, -1.0]:
			_add(parts, _block(Vector3(0.035, 0.12, 0.2) * h, 0.01), _at(side * 0.14 * h, 0.07, -0.02), PLATE, 1)
			for k in 2:
				_add(parts, Cel.box(Vector3(0.012, 0.016, 0.11) * h), _at(side * (0.135 * h + 0.006), 0.17 + k * 0.035 * h, 0.03), DARK, 1)
		_add(parts, Cel.box(Vector3(0.012, 0.2, 0.012)), _at(-0.1 * h, 0.3 * h, 0.1 * h), DARK, 2)
	else:
		var dome := PackedVector2Array([Vector2(0.15, -0.02), Vector2(0.165, 0.06), Vector2(0.165, 0.13), Vector2(0.15, 0.2), Vector2(0.11, 0.255), Vector2(0.0, 0.28)])
		for k in dome.size():
			dome[k] *= h
		_add(parts, _turned(dome), _at(0, 0.0, 0.01), TEAM)
		if _far:
			_add(parts, _block(Vector3(0.28, 0.075, 0.1) * h, 0.02), _at(0, 0.13 * h, -0.115 * h), VISOR)
		else:
			var lens := Cel.loft([
				Vector4(0.094 * h, 0.031 * h, -0.067 * h, 0),
				Vector4(0.133 * h, 0.046 * h, -0.012 * h, 0),
				Vector4(0.141 * h, 0.047 * h, 0.05 * h, 0),
			], 0.87)
			_add(parts, lens, _at(0, 0.134 * h, -0.108 * h), VISOR)
		var sideways := Basis(Vector3.BACK, PI * 0.5)
		for side: float in [1.0, -1.0]:
			_add(parts, _drum(0.06 * h, 0.04), Transform3D(sideways, Vector3(side * 0.165 * h, 0.1 * h, 0.02)), PLATE, 1)
		_add(parts, _drum(0.172 * h, 0.03, 0.008), _at(0, 0.0, 0.01), PLATE, 1)
		_add(parts, _block(Vector3(0.04, 0.035, 0.22) * h, 0.01), _at(0, 0.272 * h, 0.03), DARK, 1)
		_add(parts, Cel.box(Vector3(0.012, 0.2, 0.012)), _at(-0.12 * h, 0.26 * h, 0.08 * h), DARK, 2)


## Yaw points the loft out along the arm. A shallow downward slope and
## a rearward sweep keep its top below the helmet.
static func _shoulder(parts: Array, build: Dictionary, angular: bool, side: float) -> void:
	var width: float = build.width
	var shoulder: float = build.shoulder
	var depth: float = build.depth
	var span := 0.116 + 0.075 * shoulder
	var height := 0.027 + 0.014 * sqrt(shoulder)
	var sweep := -side * (0.022 if angular else 0.071) * depth
	var root := Vector3(side * 0.18 * width, 0.545, -0.022 * depth)
	var direction := Basis(Vector3.BACK, -side * 0.30) * Basis(Vector3.UP, side * PI * 0.5)
	var profile: Array[Vector4] = [
		Vector4(0.108 * depth, height * 0.8, 0, 0),
		Vector4(0.137 * depth, height, span * 0.52, sweep * 0.26),
		Vector4((0.092 if angular else 0.071) * depth, height * 0.48, span, sweep),
	]
	if _far:
		profile[0].x = profile[1].x
		profile.remove_at(1)
	var cut := 0.4 if angular else 0.9
	_add(parts, Cel.loft(profile, cut), Transform3D(direction, root), TEAM)
	if _far or shoulder < 0.8:
		return
	# The lower plate overlaps the shell while descending along the arm.
	var lower_span := span * (0.82 if shoulder > 1.4 else 0.68)
	var lower := Cel.loft([
		Vector4(0.105 * depth, 0.031, 0, sweep * 0.15),
		Vector4(0.114 * depth, 0.036, lower_span * 0.52, sweep * 0.44),
		Vector4(0.070 * depth, 0.019, lower_span, sweep * 0.76),
	], cut)
	var lower_root := root + direction.z * (span * 0.28) + Vector3.DOWN * 0.048
	_add(parts, lower, Transform3D(direction, lower_root), ARMOUR_TRIM, 1)


static func _torso(parts: Array, angular: bool, b: Dictionary, shaped: bool) -> void:
	var w: float = b.width
	var p: float = b.pack
	var d: float = b.depth
	var front := -0.15 * d - 0.01
	_add(parts, _block(Vector3(0.34 * w, 0.16, 0.22 * d), 0.025), _at(0, 0.1, 0), LIMB)
	if shaped:
		_add(parts, Cel.loft([
			Vector4(0.164 * w, 0.109 * d, -0.21, 0), Vector4(0.212 * w, 0.137 * d, -0.09, 0),
			Vector4(0.238 * w, 0.157 * d, 0.128, 0), Vector4(0.166 * w, 0.108 * d, 0.21, 0),
		], 0.81), _at(0, 0.36, 0, UPRIGHT), TEAM)
	else:
		_add(parts, _block(Vector3(0.48 * w, 0.42, 0.3 * d), 0.045), _at(0, 0.36, 0), TEAM)
	# A second chest plate over the top, side panels, a collar, and a belt
	# with a buckle and pouches.
	_add(parts, _block(Vector3(0.44 * w, 0.15, 0.06), 0.02), _at(0, 0.48, front - 0.005), TEAM, 1)
	for side: float in [1.0, -1.0]:
		_add(parts, _block(Vector3(0.04, 0.26, 0.2 * d), 0.012), _at(side * (0.24 * w + 0.012), 0.33, 0), PLATE, 1)
		_add(parts, _block(Vector3(0.08, 0.08, 0.06), 0.014), _at(side * 0.11 * w, 0.02, -0.12 * d - 0.03), PLATE, 1)
		for k in 3:
			_add(parts, Cel.box(Vector3(0.1 * w, 0.012, 0.02)), _at(side * 0.15 * w, 0.2 + k * 0.03, front + 0.002), DARK, 2)
		# Cables from the pack over the shoulders.
		_add(parts, Cel.box(Vector3(0.025, 0.025, 0.32 * d)), _at(side * 0.13 * w, 0.585, 0.02), DARK, 2)
	if shaped:
		var collar := Cel.loft([
			Vector4(0.08 * w, 0.018, -0.133 * d, 0),
			Vector4(0.143 * w, 0.029, -0.045 * d, 0),
			Vector4(0.103 * w, 0.023, 0.097 * d, 0),
		], 0.5 if angular else 0.88)
		_add(parts, collar, _at(0, 0.56, 0), ARMOUR_TRIM, 1)
	for side: float in [-1, 1]:
		_shoulder(parts, b, angular, side)
	_add(parts, Cel.box(Vector3(0.37 * w, 0.055, 0.24 * d)), _at(0, 0.03, 0), DARK, 1)
	_add(parts, _block(Vector3(0.07, 0.05, 0.02), 0.008), _at(0, 0.03, -0.12 * d - 0.01), PALE, 1)
	# The pack grows wider and deeper faster than it grows taller.
	var tall := sqrt(p)
	if p > 1.4:
		# Heavy: a block between the two halves of the pack.
		_add(parts, _block(Vector3(0.2 * p, 0.42 * tall, 0.12 * p), 0.03), _at(0, 0.34, 0.22 * d), PACK)
	if angular:
		# Lime's twin pack has fins and a chevron on the chest.
		for side: float in [1.0, -1.0]:
			_add(parts, _block(Vector3(0.11 * p, 0.6 * tall, 0.16 * p), 0.02), _at(side * 0.12 * p, 0.36, 0.24 * d), PACK)
			_add(parts, _block(Vector3(0.12 * p, 0.08 * tall, 0.18 * p), 0.015), _at(side * 0.12 * p, 0.36 + 0.3 * tall, 0.24 * d), TEAM)
			var fin := Basis(Vector3.BACK, side * 0.35)
			_add(parts, _block(Vector3(0.022, 0.24 * tall, 0.15 * p), 0.008), Transform3D(fin, Vector3(side * 0.2 * p, 0.24, 0.26 * d)), TEAM, 1)
			if shaped:
				var mark := Color(0.78, 0.76, 0.85, 0.35)
				_add(parts, _block(Vector3(0.055 * p, 0.32 * tall, 0.014), 0.004), _at(side * 0.12 * p, 0.35, 0.24 * d + 0.084 * p), mark, 1)
			for k in 3:
				_add(parts, Cel.box(Vector3(0.07 * p, 0.014, 0.012)), _at(side * 0.12 * p, 0.42 + k * 0.035, 0.24 * d + 0.08 * p + 0.004), DARK, 2)
			_add(parts, _block(Vector3(0.05, 0.22, 0.02), 0.006), Transform3D(Basis(Vector3.BACK, side * 0.75), Vector3(side * 0.065, 0.32, front - 0.002)), PALE)
		_add(parts, _block(Vector3(0.1 * p, 0.4 * tall, 0.04), 0.01), _at(0, 0.34, 0.17 * d + 0.02), DARK, 1)
	else:
		# Blue's twin tanks have bands and valves, with a ring on the chest.
		for side: float in [1.0, -1.0]:
			var tank := Vector3(side * 0.1 * p, 0.34, 0.25 * d)
			var r := 0.09 * p
			var half := 0.25 * tall
			_add(parts, _turned(PackedVector2Array([Vector2(r * 0.6, -half), Vector2(r, -half + r * 0.4), Vector2(r, half)])), Transform3D(Basis.IDENTITY, tank), PACK)
			_add(parts, Cel.sphere(r, 0.12 * p, 6 if _far else 12), Transform3D(Basis.IDENTITY, tank + Vector3(0, half, 0)), TEAM)
			for k in 2:
				var band := (TEAM if k == 0 else ARMOUR_TRIM) if shaped else DARK
				_add(parts, _drum(r * 1.08, 0.03, 0.006), Transform3D(Basis.IDENTITY, tank + Vector3(0, half * (0.5 - k * 0.9), 0)), band, 1)
			_add(parts, _drum(0.022, 0.05, 0.005), Transform3D(Basis.IDENTITY, tank + Vector3(0, half + 0.065 * p, 0)), PLATE, 1)
		_add(parts, Cel.box(Vector3(0.2 * p, 0.025, 0.025)), _at(0, 0.34 + 0.25 * tall * 0.6, 0.25 * d), DARK, 2)
		var flat := Basis(Vector3.RIGHT, PI * 0.5)
		_add(parts, _drum(0.09, 0.02, 0.005), Transform3D(flat, Vector3(0, 0.33, front)), PALE)
		_add(parts, _drum(0.05, 0.03, 0.005), Transform3D(flat, Vector3(0, 0.33, front - 0.005)), TEAM)
	# Bell nozzles at the bottom of the pack, where the flames come out.
	var bell := PackedVector2Array([Vector2(0.055 * p, -0.06), Vector2(0.072 * p, -0.06), Vector2(0.05 * p, 0.03), Vector2(0.04 * p, 0.06)])
	for side: float in [1.0, -1.0]:
		_add(parts, _turned(bell), _at(side * 0.11 * p, 0.06, 0.26), DARK)


## Where the pack part sits on the back of the torso: x, y and the z of its
## front face.
static func _pack_mount(b: Dictionary) -> Vector3:
	var p: float = b.pack
	var d: float = b.depth
	return Vector3(0.0, 0.34 + 0.06 * sqrt(p), 0.24 * d + 0.07 * p)


## Top of the jammer's antenna in torso space.
static func _antenna_tip(b: Dictionary) -> Vector3:
	var at := _pack_mount(b)
	return Vector3(-0.1 * float(b.pack) - 0.02, at.y + 0.62, at.z + 0.05)


## The pack's part on the back, between and behind the two halves of the
## pack: a pale box with a red cross for repair, a team coloured dish for the
## shield, an upright cell with amber bands for energy, a strapped crate for
## ammo and a box with an antenna for the jammer.
static func _pack_part(parts: Array, b: Dictionary) -> void:
	var p: float = b.pack
	var k := sqrt(p)
	var at := _pack_mount(b)
	var flat := Basis(Vector3.RIGHT, PI * 0.5)
	match _pack:
		Pack.REPAIR:
			var size := Vector3(0.22, 0.2, 0.12) * k
			var c := at + Vector3(0, 0, size.z * 0.5)
			_add(parts, _block(size, 0.02), _at(c.x, c.y, c.z), PALE)
			_add(parts, Cel.box(Vector3(0.05, 0.15, 0.02) * k), _at(c.x, c.y, c.z + size.z * 0.5), CROSS)
			_add(parts, Cel.box(Vector3(0.15, 0.05, 0.02) * k), _at(c.x, c.y, c.z + size.z * 0.5), CROSS)
			# A coiled hose to the side.
			_add(parts, _drum(0.05 * k, 0.05, 0.01), Transform3D(Basis(Vector3.BACK, PI * 0.5), c + Vector3(size.x * 0.5 + 0.025, -0.04, 0)), DARK, 1)
		Pack.SHIELD:
			var c := at + Vector3(0, 0.02, 0.03)
			_add(parts, _block(Vector3(0.12, 0.14, 0.06) * k, 0.015), _at(c.x, c.y, c.z), DARK)
			_add(parts, _drum(0.13 * k, 0.04, 0.012), Transform3D(flat, c + Vector3(0, 0, 0.05)), PLATE)
			_add(parts, _drum(0.09 * k, 0.05, 0.01), Transform3D(flat, c + Vector3(0, 0, 0.06)), TEAM)
			_add(parts, _drum(0.03 * k, 0.07, 0.006), Transform3D(flat, c + Vector3(0, 0, 0.07)), PALE, 1)
		Pack.ENERGY:
			var c := at + Vector3(0, 0, 0.07 * k)
			var r := 0.07 * k
			var half := 0.17 * k
			_add(parts, _turned(PackedVector2Array([Vector2(r * 0.7, -half), Vector2(r, -half + 0.02), Vector2(r, half - 0.02), Vector2(r * 0.7, half)])), _at(c.x, c.y, c.z), DARK)
			for n in 3:
				_add(parts, _drum(r * 1.12, 0.035, 0.008), _at(c.x, c.y + (n - 1) * half * 0.6, c.z), VISOR)
			_add(parts, _drum(0.025 * k, 0.06, 0.006), _at(c.x, c.y + half + 0.03, c.z), PLATE, 1)
		Pack.AMMO:
			var size := Vector3(0.3, 0.24, 0.16) * k
			var c := at + Vector3(0, -0.02, size.z * 0.5 + 0.02)
			_add(parts, _block(size, 0.02), _at(c.x, c.y, c.z), CRATE)
			for side: float in [1.0, -1.0]:
				_add(parts, Cel.box(Vector3(0.035 * k, size.y + 0.012, size.z + 0.012)), _at(c.x + side * size.x * 0.3, c.y, c.z), DARK)
			_add(parts, Cel.box(Vector3(size.x * 0.3, 0.025, 0.012)), _at(c.x, c.y + size.y * 0.2, c.z + size.z * 0.5 + 0.002), PALE, 1)
			_add(parts, Cel.box(Vector3(size.x * 0.3, 0.025, 0.012)), _at(c.x, c.y - size.y * 0.1, c.z + size.z * 0.5 + 0.002), PALE, 1)
		Pack.JAMMER:
			var size := Vector3(0.18, 0.18, 0.1) * k
			var c := at + Vector3(0, -0.02, size.z * 0.5)
			_add(parts, _block(size, 0.018), _at(c.x, c.y, c.z), DARK)
			_add(parts, _block(Vector3(0.12, 0.03, 0.02) * k, 0.006), _at(c.x, c.y + 0.03, c.z + size.z * 0.5), VISOR, 1)
			# A thin mast from the box's top corner, up past the helmet.
			var tip := _antenna_tip(b)
			var foot := Vector3(tip.x, c.y + size.y * 0.5, tip.z)
			var mast := tip.y - foot.y
			_add(parts, Cel.box(Vector3(0.02, mast, 0.02)), _at(foot.x, foot.y + mast * 0.5, foot.z), DARK)
			_add(parts, _drum(0.03, 0.05, 0.006), _at(foot.x, foot.y + 0.02, foot.z), PLATE)
			_add(parts, _drum(0.05, 0.015, 0.004), _at(tip.x, tip.y - mast * 0.35, tip.z), PLATE, 1)

		Pack.TURRET, Pack.SENSOR, Pack.STATION:
			var size := Vector3(0.28, 0.32, 0.15) * k
			var c := at + Vector3.BACK * size.z * 0.5
			_add(parts, _block(size, 0.025), Transform3D(Basis.IDENTITY, c), PLATE)
			_add(parts, _block(Vector3(size.x * 0.9, 0.065, size.z + 0.02), 0.012), Transform3D(Basis.IDENTITY, c), TEAM)
			var latch := c + Vector3(0.0, 0.09, size.z * 0.5)
			_add(parts, _block(Vector3(0.095, 0.07, 0.045) * k, 0.01), Transform3D(Basis.IDENTITY, latch), DARK)


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
	for slot: int in guns:
		guns[slot].visible = slot == s.weapon_slot()
	if guns.has(Weapon.CHAINGUN):
		var spinner := guns[Weapon.CHAINGUN].get_node("Spinner") as Node3D
		spinner.rotation.z += s.spin * delta * 40.0
	flame.visible = _jet > 0.5
	if _shield_flash_left > 0.0:
		_shield_flash_left = maxf(0.0, _shield_flash_left - delta)
		if _shield_flash_left == 0.0:
			shell.material_override = shell_material(_team_colour)
	shell.visible = s.shielded() or _shield_flash_left > 0.0
	jam_tip.visible = s.jamming() and _flicker.randf() < 0.7
	if jam_tip.visible:
		jam_tip.scale = Vector3.ONE * _flicker.randf_range(0.6, 1.3)
		jam_tip.rotation.y = _flicker.randf_range(0.0, PI)
	flame.scale = Vector3(1.0, _flicker.randf_range(0.75, 1.15), 1.0)
	sparks.visible = on_ground and s.skiing and speed > 10.0
	if sparks.visible:
		var size := clampf(speed / 30.0, 0.6, 1.6)
		sparks.scale = Vector3(1.0, 1.0, size * _flicker.randf_range(0.6, 1.2))
		sparks.rotation.y = _flicker.randf_range(-0.15, 0.15)
		sparks.position.y = 0.04 - drop * 0.2
