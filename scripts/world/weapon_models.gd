class_name WeaponModels
extends RefCounted

## Weapon meshes merged from boxes and cylinders, used both in soldiers' hands
## and as the first person view model. The grip is at the origin and the
## barrel points down -z. Parts in the team's colour get it from
## Cel.set_team, so call that on every mesh under the model.

const BODY := Color(0.78, 0.8, 0.82)
const DARK := Color(0.42, 0.44, 0.5)
const PALE := Color(0.96, 0.94, 0.88)
const DISC_GLOW := Color(0.7, 1.0, 1.0)


## A model for a weapon slot: one merged mesh, plus one for a chaingun's
## barrels under a node named "Spinner", turned about z to spin them. near is
## for the first person view, with thinner outlines.
static func build(slot: int, near := false) -> Node3D:
	var model := Node3D.new()
	model.name = Weapon.all[slot].short_name.capitalize()
	var body := MeshInstance3D.new()
	body.mesh = mesh(slot, false)
	body.material_override = Cel.material(Color.WHITE, 1.0, true, true, near, not near)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(body)
	if slot == Weapon.CHAINGUN:
		var spinner := Node3D.new()
		spinner.name = "Spinner"
		spinner.position = Vector3(0.0, 0.02, -0.25)
		model.add_child(spinner)
		var barrels := MeshInstance3D.new()
		barrels.mesh = mesh(slot, true)
		barrels.material_override = body.material_override
		barrels.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spinner.add_child(barrels)
	return model


static var _meshes: Dictionary[String, ArrayMesh] = {}


## The merged mesh for a weapon, or for its spinning barrels.
static func mesh(slot: int, barrels: bool) -> ArrayMesh:
	var key := "%d/%s" % [slot, barrels]
	if not _meshes.has(key):
		var parts := []
		if slot == Weapon.DISC:
			_disc_launcher(parts)
		elif not barrels:
			_chaingun(parts)
		else:
			_barrels(parts)
		_meshes[key] = Cel.merged(parts)
	return _meshes[key]


static func _at(x: float, y: float, z: float, basis := Basis.IDENTITY) -> Transform3D:
	return Transform3D(basis, Vector3(x, y, z))


## A grip sloping back under the receiver, with a trigger guard.
static func _grip(parts: Array) -> void:
	var dark := Color(DARK, 0.0)
	parts.append([Cel.box(Vector3(0.055, 0.15, 0.075)), _at(0.0, -0.085, 0.03, Basis(Vector3.RIGHT, 0.3)), dark])
	parts.append([Cel.box(Vector3(0.03, 0.025, 0.1)), _at(0.0, -0.06, -0.06), dark])


## A squat receiver with a team colour cover, and a disc held between two
## jaws at the front, team colour on top and dark below.
static func _disc_launcher(parts: Array) -> void:
	var body := Color(BODY, 0.0)
	var dark := Color(DARK, 0.0)
	var team := Color(1.0, 1.0, 1.0, 1.0)
	var pale := Color(PALE, 0.0)
	parts.append([Cel.box(Vector3(0.12, 0.12, 0.36)), _at(0.0, 0.03, -0.07), body])
	parts.append([Cel.box(Vector3(0.13, 0.035, 0.26)), _at(0.0, 0.105, -0.1), team])
	parts.append([Cel.box(Vector3(0.11, 0.03, 0.1)), _at(0.0, 0.09, 0.06, Basis(Vector3.RIGHT, -0.45)), team])
	for side: float in [1.0, -1.0]:
		parts.append([Cel.box(Vector3(0.012, 0.06, 0.16)), _at(side * 0.062, 0.03, -0.1), team])
		parts.append([Cel.box(Vector3(0.014, 0.018, 0.16)), _at(side * 0.062, -0.012, -0.1), pale])
	# Coils between the receiver and the jaws.
	var turn_x := Basis(Vector3.RIGHT, PI * 0.5)
	for k in 2:
		parts.append([Cel.cylinder(0.068, 0.068, 0.025, 10), _at(0.0, 0.03, -0.27 - k * 0.045, turn_x), dark])
	# The jaws: wide flat plates that taper at the front.
	parts.append([Cel.box(Vector3(0.18, 0.035, 0.22)), _at(0.0, 0.09, -0.42), team])
	parts.append([Cel.box(Vector3(0.14, 0.03, 0.06)), _at(0.0, 0.09, -0.55), team])
	parts.append([Cel.box(Vector3(0.18, 0.035, 0.22)), _at(0.0, -0.03, -0.42), dark])
	parts.append([Cel.box(Vector3(0.05, 0.09, 0.2)), _at(0.0, 0.03, -0.4), dark])
	parts.append([Cel.cylinder(0.12, 0.12, 0.04, 16), _at(0.0, 0.03, -0.46), Color(DISC_GLOW, 0.0)])
	# A small sight on top, and a charge window in the back plate.
	parts.append([Cel.box(Vector3(0.025, 0.04, 0.05)), _at(0.0, 0.14, 0.0), dark])
	parts.append([Cel.box(Vector3(0.09, 0.08, 0.02)), _at(0.0, 0.03, 0.115), dark])
	parts.append([Cel.box(Vector3(0.05, 0.025, 0.02)), _at(0.0, 0.045, 0.122), Color(DISC_GLOW, 0.0)])
	_grip(parts)


## A boxy receiver with team colour cover and side panels, a collar the
## barrels spin in, and an ammo box on the right.
static func _chaingun(parts: Array) -> void:
	var body := Color(BODY, 0.0)
	var dark := Color(DARK, 0.0)
	var team := Color(1.0, 1.0, 1.0, 1.0)
	var pale := Color(PALE, 0.0)
	var turn_x := Basis(Vector3.RIGHT, PI * 0.5)
	parts.append([Cel.box(Vector3(0.14, 0.14, 0.3)), _at(0.0, 0.02, -0.04), body])
	parts.append([Cel.box(Vector3(0.15, 0.04, 0.22)), _at(0.0, 0.1, -0.06), team])
	parts.append([Cel.box(Vector3(0.1, 0.03, 0.08)), _at(0.0, 0.1, 0.09, Basis(Vector3.RIGHT, -0.4)), team])
	for side: float in [1.0, -1.0]:
		parts.append([Cel.box(Vector3(0.012, 0.07, 0.18)), _at(side * 0.072, 0.02, -0.05), team])
	parts.append([Cel.box(Vector3(0.014, 0.018, 0.18)), _at(-0.073, -0.03, -0.05), pale])
	# The collar the barrels come out of.
	parts.append([Cel.cylinder(0.085, 0.085, 0.07, 12), _at(0.0, 0.02, -0.215, turn_x), dark])
	# Ammo box on the right side.
	parts.append([Cel.box(Vector3(0.07, 0.1, 0.13)), _at(0.1, -0.03, -0.06), dark])
	parts.append([Cel.box(Vector3(0.074, 0.025, 0.134)), _at(0.1, 0.0, -0.06), team])
	# A back plate with a pale stripe.
	parts.append([Cel.box(Vector3(0.1, 0.09, 0.02)), _at(0.0, 0.01, 0.115), dark])
	parts.append([Cel.box(Vector3(0.07, 0.018, 0.02)), _at(0.0, 0.03, 0.122), pale])
	_grip(parts)


## Six barrels about the spin axis, held by two rings, in the Spinner's space.
static func _barrels(parts: Array) -> void:
	var body := Color(BODY, 0.0)
	var dark := Color(DARK, 0.0)
	var turn_x := Basis(Vector3.RIGHT, PI * 0.5)
	for k in 6:
		var angle := k * TAU / 6.0
		parts.append([Cel.cylinder(0.016, 0.016, 0.38, 6), _at(cos(angle) * 0.045, sin(angle) * 0.045, -0.19, turn_x), dark])
	parts.append([Cel.cylinder(0.07, 0.07, 0.035, 12), _at(0.0, 0.0, -0.17, turn_x), body])
	parts.append([Cel.cylinder(0.072, 0.072, 0.045, 12), _at(0.0, 0.0, -0.36, turn_x), body])
