class_name WeaponModels
extends RefCounted

## Weapon meshes built from boxes and cylinders, used both in soldiers' hands
## and as the first person view model. The grip is at the origin and the
## barrel points down -z. Parts in the team's colour get it from
## Cel.set_team, so call that on every mesh under the model.

const BODY := Color(0.3, 0.32, 0.36)
const DARK := Color(0.18, 0.19, 0.22)
const DISC_GLOW := Color(0.7, 1.0, 1.0)


## A model for a weapon slot. A chaingun's barrels are under a node named
## "Spinner", turned about z to spin them. near is for the first person
## view, with thinner outlines.
static func build(slot: int, near := false) -> Node3D:
	var model := Node3D.new()
	model.name = Weapon.all[slot].short_name.capitalize()
	if slot == Weapon.DISC:
		_part(model, Cel.box(Vector3(0.13, 0.15, 0.56)), Vector3(0.0, 0.03, -0.22), _material(BODY, 0.0, near))
		_part(model, Cel.box(Vector3(0.15, 0.05, 0.3)), Vector3(0.0, 0.12, -0.12), _material(Color.WHITE, 1.0, near))
		var drum := _part(model, Cel.cylinder(0.12, 0.12, 0.17, 10), Vector3(0.0, 0.0, -0.06), _material(DARK, 0.0, near))
		drum.rotation.z = PI * 0.5
		# A disc sits ready in the open muzzle.
		_part(model, Cel.cylinder(0.11, 0.11, 0.035, 12), Vector3(0.0, 0.03, -0.5), Cel.glow(DISC_GLOW))
		_part(model, Cel.box(Vector3(0.06, 0.15, 0.08)), Vector3(0.0, -0.1, 0.02), _material(DARK, 0.0, near))
	else:
		_part(model, Cel.box(Vector3(0.14, 0.16, 0.34)), Vector3(0.0, 0.02, -0.08), _material(BODY, 0.0, near))
		_part(model, Cel.box(Vector3(0.15, 0.04, 0.2)), Vector3(0.0, 0.11, -0.06), _material(Color.WHITE, 1.0, near))
		_part(model, Cel.box(Vector3(0.06, 0.15, 0.08)), Vector3(0.0, -0.1, 0.02), _material(DARK, 0.0, near))
		var spinner := Node3D.new()
		spinner.name = "Spinner"
		spinner.position = Vector3(0.0, 0.02, -0.25)
		model.add_child(spinner)
		for k in 4:
			var angle := k * TAU / 4.0
			var barrel := _part(spinner, Cel.cylinder(0.022, 0.022, 0.46, 6), Vector3(cos(angle), sin(angle), 0.0) * 0.045 + Vector3(0.0, 0.0, -0.23), _material(DARK, 0.0, near))
			barrel.rotation.x = PI * 0.5
		var collar := _part(spinner, Cel.cylinder(0.08, 0.08, 0.05, 10), Vector3(0.0, 0.0, -0.4), _material(BODY, 0.0, near))
		collar.rotation.x = PI * 0.5
	return model


static func _part(parent: Node3D, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.position = at
	view.material_override = material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(view)
	return view


static func _material(colour: Color, team_amount: float, near: bool) -> ShaderMaterial:
	return Cel.material(colour, team_amount, true, false, near)
