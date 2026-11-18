class_name WeaponModels
extends RefCounted

## Weapon meshes merged from boxes and cylinders, used both in soldiers' hands
## and as the first person view model. The grip is at the origin and the
## barrel points down -z. Parts in the team's colour get it from
## Cel.set_team, so call that on every mesh under the model.

const BODY := Color(0.52, 0.54, 0.58)
const DARK := Color(0.3, 0.31, 0.35)
const DISC_GLOW := Color(0.7, 1.0, 1.0)


## A model for a weapon slot: one merged mesh, plus one for a chaingun's
## barrels under a node named "Spinner", turned about z to spin them. near is
## for the first person view, with thinner outlines.
static func build(slot: int, near := false) -> Node3D:
	var model := Node3D.new()
	model.name = Weapon.all[slot].short_name.capitalize()
	var body := MeshInstance3D.new()
	body.mesh = mesh(slot, false)
	body.material_override = Cel.material(Color.WHITE, 1.0, true, true, near)
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
	if _meshes.has(key):
		return _meshes[key]
	var body := Color(BODY, 0.0)
	var dark := Color(DARK, 0.0)
	var team := Color(1.0, 1.0, 1.0, 1.0)
	var turn_z := Basis(Vector3.BACK, PI * 0.5)
	var turn_x := Basis(Vector3.RIGHT, PI * 0.5)
	var parts := []
	if slot == Weapon.DISC:
		parts.append([Cel.box(Vector3(0.13, 0.15, 0.56)), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.03, -0.22)), body])
		parts.append([Cel.box(Vector3(0.15, 0.05, 0.3)), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.12, -0.12)), team])
		parts.append([Cel.cylinder(0.12, 0.12, 0.17, 10), Transform3D(turn_z, Vector3(0.0, 0.0, -0.06)), dark])
		# A disc sits ready in the open muzzle.
		parts.append([Cel.cylinder(0.11, 0.11, 0.035, 12), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.03, -0.5)), Color(DISC_GLOW, 0.0)])
		parts.append([Cel.box(Vector3(0.06, 0.15, 0.08)), Transform3D(Basis.IDENTITY, Vector3(0.0, -0.1, 0.02)), dark])
	elif not barrels:
		parts.append([Cel.box(Vector3(0.14, 0.16, 0.34)), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.02, -0.08)), body])
		parts.append([Cel.box(Vector3(0.15, 0.04, 0.2)), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.11, -0.06)), team])
		parts.append([Cel.box(Vector3(0.06, 0.15, 0.08)), Transform3D(Basis.IDENTITY, Vector3(0.0, -0.1, 0.02)), dark])
	else:
		for k in 4:
			var angle := k * TAU / 4.0
			parts.append([Cel.cylinder(0.022, 0.022, 0.46, 6), Transform3D(turn_x, Vector3(cos(angle), sin(angle), 0.0) * 0.045 + Vector3(0.0, 0.0, -0.23)), dark])
		parts.append([Cel.cylinder(0.08, 0.08, 0.05, 10), Transform3D(turn_x, Vector3(0.0, 0.0, -0.4)), body])
	_meshes[key] = Cel.merged(parts)
	return _meshes[key]
