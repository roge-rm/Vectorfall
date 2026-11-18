class_name WeaponModels
extends RefCounted

## Weapon meshes merged from bevelled boxes and turned shapes, used both in
## soldiers' hands and as the first person view model. The grip is at the
## origin and the barrel points down -z. Parts in the team's colour get it
## from Cel.set_team, so call that on every mesh under the model. Pieces
## carry a detail level like SoldierBody's, and guns in soldiers' hands get
## a plainer far version past SoldierBody.FAR_DISTANCE.

const BODY := Color(0.8, 0.8, 0.84)
const DARK := Color(0.3, 0.3, 0.36)
const DEEP := Color(0.14, 0.13, 0.17)
const PALE := Color(0.98, 0.96, 0.9)
const DISC_GLOW := Color(0.7, 1.0, 1.0)
const LENS := Color(1.0, 0.86, 0.4)

## How much detail guns have, as SoldierBody.detail.
static var detail := 1
static var _meshes: Dictionary[String, ArrayMesh] = {}
## While building: the far version, and the detail level wanted.
static var _far := false
static var _level := 1


## A model for a weapon slot: one merged mesh, plus one for a chaingun's
## barrels under a node named "Spinner", turned about z to spin them. near is
## for the first person view, with thinner outlines and no far version.
static func build(slot: int, near := false) -> Node3D:
	var model := Node3D.new()
	model.name = Weapon.all[slot].short_name.capitalize()
	var material := Cel.material(Color.WHITE, 1.0, true, true, near, not near)
	var body := _view(model, mesh(slot, false), material)
	if slot == Weapon.CHAINGUN:
		var spinner := Node3D.new()
		spinner.name = "Spinner"
		spinner.position = Vector3(0.0, 0.02, -0.25)
		model.add_child(spinner)
		var barrels := _view(spinner, mesh(slot, true), material)
		if not near:
			barrels.visibility_range_end = SoldierBody.FAR_DISTANCE
	if not near:
		body.visibility_range_end = SoldierBody.FAR_DISTANCE
		var far := _view(model, mesh(slot, false, true), material)
		far.visibility_range_begin = SoldierBody.FAR_DISTANCE
	return model


static func _view(parent: Node3D, piece: Mesh, material: Material) -> MeshInstance3D:
	var view := MeshInstance3D.new()
	view.mesh = piece
	view.material_override = material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(view)
	return view


## The merged mesh for a weapon, or for its spinning barrels, near at the
## current detail level or far.
static func mesh(slot: int, barrels: bool, far := false) -> ArrayMesh:
	var key := "%d/%s/%d" % [slot, barrels, -1 if far else detail]
	if not _meshes.has(key):
		_far = far
		_level = 0 if far else detail
		var parts := []
		if slot == Weapon.DISC:
			_disc_launcher(parts)
		elif not barrels:
			_chaingun(parts)
			if far:
				# The far version's barrels are part of the body.
				_add(parts, Cel.box(Vector3(0.1, 0.1, 0.4)), _at(0.0, 0.02, -0.44), DARK)
		else:
			_barrels(parts)
		_meshes[key] = Cel.merged(parts)
		_far = false
	return _meshes[key]


static func _at(x: float, y: float, z: float, basis := Basis.IDENTITY) -> Transform3D:
	return Transform3D(basis, Vector3(x, y, z))


## Adds a piece if the detail level has it. Colours with alpha 1 take the
## team colour.
## The far version has no dark parts, so the gun doesn't hide the chest.
static func _add(parts: Array, piece: Mesh, where: Transform3D, colour: Color, level := 0) -> void:
	if level <= _level:
		if _far and colour.a == 0.0:
			colour = Color(BODY, 0.0)
		parts.append([piece, where, colour])


static func _block(size: Vector3, bevel := 0.008) -> Mesh:
	return Cel.box(size) if _far else Cel.bevel_box(size, bevel)


## A short cylinder along z with bevelled rims.
static func _ring(radius: float, length: float, bevel := 0.006, sides := 12) -> Mesh:
	return Cel.cylinder(radius, radius, length, 6) if _far else Cel.bevel_cylinder(radius, length, bevel, sides)


static func _team() -> Color:
	return Color(1.0, 1.0, 1.0, 1.0)


## A grip sloping back under the receiver with finger ridges, and a trigger
## guard with its trigger.
static func _grip(parts: Array) -> void:
	var grip := Basis(Vector3.RIGHT, 0.3)
	_add(parts, _block(Vector3(0.055, 0.15, 0.075), 0.01), _at(0.0, -0.085, 0.03, grip), Color(DARK, 0.0))
	for k in 3:
		_add(parts, Cel.box(Vector3(0.058, 0.012, 0.012)), Transform3D(grip, Vector3(0.0, -0.05 - k * 0.035, 0.0) + grip * Vector3(0.0, 0.0, -0.035)), Color(DEEP, 0.0), 1)
	_add(parts, _block(Vector3(0.03, 0.022, 0.1), 0.006), _at(0.0, -0.06, -0.06), Color(DARK, 0.0))
	_add(parts, Cel.box(Vector3(0.012, 0.04, 0.012)), _at(0.0, -0.035, -0.035), Color(DEEP, 0.0), 1)


## Thin dark lines along a side of a receiver, panel seams.
static func _seams(parts: Array, x: float, ys: Array, z: float, length: float) -> void:
	for y: float in ys:
		for side: float in [1.0, -1.0]:
			_add(parts, Cel.box(Vector3(0.006, 0.006, length)), _at(side * x, y, z), Color(DEEP, 0.0), 1)


## A squat receiver with a team colour cover, a skeleton stock, a power
## cell underneath, coils, and a disc held between two jaws at the front,
## team colour on top and dark below.
static func _disc_launcher(parts: Array) -> void:
	var body := Color(BODY, 0.0)
	var dark := Color(DARK, 0.0)
	var deep := Color(DEEP, 0.0)
	var team := _team()
	var pale := Color(PALE, 0.0)
	var glow := Color(DISC_GLOW, 0.0)
	var turn_x := Basis(Vector3.RIGHT, PI * 0.5)
	_add(parts, _block(Vector3(0.12, 0.12, 0.36), 0.014), _at(0.0, 0.03, -0.07), body)
	_add(parts, _block(Vector3(0.13, 0.035, 0.26), 0.01), _at(0.0, 0.105, -0.1), team)
	_add(parts, _block(Vector3(0.11, 0.03, 0.1), 0.01), _at(0.0, 0.09, 0.06, Basis(Vector3.RIGHT, -0.45)), team)
	for side: float in [1.0, -1.0]:
		_add(parts, _block(Vector3(0.012, 0.06, 0.16), 0.004), _at(side * 0.062, 0.03, -0.1), team)
		_add(parts, Cel.box(Vector3(0.014, 0.018, 0.16)), _at(side * 0.062, -0.012, -0.1), pale, 1)
		# Vent slats behind the side panels.
		for k in 3:
			_add(parts, Cel.box(Vector3(0.008, 0.05, 0.008)), _at(side * 0.062, 0.03, 0.0 + k * 0.022), deep, 1)
	_seams(parts, 0.061, [0.075, -0.024], -0.06, 0.3)
	# Coils between the receiver and the jaws, with glowing rings between.
	for k in 3:
		_add(parts, _ring(0.068, 0.022), _at(0.0, 0.03, -0.265 - k * 0.04, turn_x), dark, 0 if k < 2 else 1)
		if k < 2:
			_add(parts, _ring(0.058, 0.016, 0.003), _at(0.0, 0.03, -0.285 - k * 0.04, turn_x), glow, 1)
	# The jaws: wide flat plates that taper at the front.
	_add(parts, _block(Vector3(0.18, 0.035, 0.22), 0.01), _at(0.0, 0.09, -0.42), team)
	_add(parts, _block(Vector3(0.14, 0.03, 0.06), 0.008), _at(0.0, 0.09, -0.55), team)
	_add(parts, _block(Vector3(0.18, 0.035, 0.22), 0.01), _at(0.0, -0.03, -0.42), dark)
	_add(parts, _block(Vector3(0.05, 0.09, 0.2), 0.008), _at(0.0, 0.03, -0.4), dark)
	_add(parts, Cel.cylinder(0.12, 0.12, 0.04, 8 if _far else 16), _at(0.0, 0.03, -0.46), glow)
	# Rivets on the top jaw and a pale stripe across it.
	for side: float in [1.0, -1.0]:
		for k in 2:
			_add(parts, Cel.box(Vector3(0.012, 0.008, 0.012)), _at(side * 0.07, 0.11, -0.34 - k * 0.12), pale, 2)
	_add(parts, Cel.box(Vector3(0.182, 0.037, 0.025)), _at(0.0, 0.09, -0.36), pale, 1)
	# A sight on a rail on top, with a lens.
	_add(parts, _block(Vector3(0.03, 0.02, 0.16), 0.004), _at(0.0, 0.13, -0.08), dark, 1)
	_add(parts, _block(Vector3(0.03, 0.045, 0.05), 0.006), _at(0.0, 0.15, 0.0), dark)
	_add(parts, _ring(0.02, 0.05, 0.004, 10), _at(0.0, 0.18, -0.01, turn_x), deep, 1)
	_add(parts, Cel.cylinder(0.014, 0.014, 0.052, 8), _at(0.0, 0.18, -0.01, turn_x), Color(LENS, 0.0), 1)
	# A power cell under the front with a glowing window, and a cable to the
	# jaws.
	_add(parts, _block(Vector3(0.07, 0.07, 0.13), 0.012), _at(0.0, -0.06, -0.17), dark, 1)
	_add(parts, Cel.box(Vector3(0.074, 0.02, 0.07)), _at(0.0, -0.055, -0.17), glow, 1)
	_add(parts, Cel.box(Vector3(0.018, 0.018, 0.14)), _at(0.04, -0.04, -0.3), deep, 2)
	# The back plate with a charge window, and a skeleton stock.
	_add(parts, _block(Vector3(0.09, 0.08, 0.02), 0.005), _at(0.0, 0.03, 0.115), dark)
	_add(parts, Cel.box(Vector3(0.05, 0.025, 0.02)), _at(0.0, 0.045, 0.122), glow)
	for y: float in [0.06, -0.01]:
		_add(parts, _block(Vector3(0.02, 0.02, 0.11), 0.005), _at(0.0, y, 0.17), dark, 1)
	_add(parts, _block(Vector3(0.045, 0.11, 0.03), 0.01), _at(0.0, 0.025, 0.235), dark, 1)
	_grip(parts)


## A boxy receiver with team colour cover and side panels, a carry handle
## with a sight, a front grip, a collar the barrels spin in, and an ammo box
## on the right feeding a belt.
static func _chaingun(parts: Array) -> void:
	var body := Color(BODY, 0.0)
	var dark := Color(DARK, 0.0)
	var deep := Color(DEEP, 0.0)
	var team := _team()
	var pale := Color(PALE, 0.0)
	var turn_x := Basis(Vector3.RIGHT, PI * 0.5)
	_add(parts, _block(Vector3(0.14, 0.14, 0.3), 0.016), _at(0.0, 0.02, -0.04), body)
	_add(parts, _block(Vector3(0.15, 0.04, 0.22), 0.01), _at(0.0, 0.1, -0.06), team)
	_add(parts, _block(Vector3(0.1, 0.03, 0.08), 0.008), _at(0.0, 0.1, 0.09, Basis(Vector3.RIGHT, -0.4)), team)
	for side: float in [1.0, -1.0]:
		_add(parts, _block(Vector3(0.012, 0.07, 0.18), 0.004), _at(side * 0.072, 0.02, -0.05), team)
		for k in 4:
			_add(parts, Cel.box(Vector3(0.008, 0.012, 0.03)), _at(side * 0.072, -0.03 + 0.0, -0.11 + k * 0.04), deep, 1)
	_add(parts, Cel.box(Vector3(0.014, 0.018, 0.18)), _at(-0.073, -0.03, -0.05), pale, 1)
	_seams(parts, 0.071, [0.065, -0.045], -0.04, 0.28)
	# The collar the barrels come out of, with a cooling ring.
	_add(parts, _ring(0.085, 0.07, 0.01), _at(0.0, 0.02, -0.215, turn_x), dark)
	_add(parts, _ring(0.09, 0.016, 0.004), _at(0.0, 0.02, -0.19, turn_x), deep, 1)
	# Ammo box on the right side, its lid, and a belt of rounds up into the
	# receiver.
	_add(parts, _block(Vector3(0.07, 0.1, 0.13), 0.01), _at(0.1, -0.03, -0.06), dark)
	_add(parts, _block(Vector3(0.074, 0.025, 0.134), 0.006), _at(0.1, 0.0, -0.06), team)
	_add(parts, Cel.box(Vector3(0.076, 0.012, 0.04)), _at(0.1, -0.05, -0.06), pale, 2)
	for k in 3:
		_add(parts, _block(Vector3(0.03, 0.022, 0.05), 0.005), _at(0.088 - k * 0.006, 0.025 + k * 0.012, -0.06), Color(LENS, 0.0), 1)
	# A carry handle on two posts, with a sight on it.
	for z: float in [0.04, -0.14]:
		_add(parts, _block(Vector3(0.022, 0.05, 0.022), 0.005), _at(0.0, 0.14, z), dark, 1)
	_add(parts, _block(Vector3(0.03, 0.022, 0.22), 0.006), _at(0.0, 0.175, -0.05), dark, 1)
	_add(parts, _block(Vector3(0.026, 0.03, 0.03), 0.005), _at(0.0, 0.2, 0.03), deep, 1)
	# A front grip under the collar.
	_add(parts, _block(Vector3(0.04, 0.1, 0.05), 0.01), _at(0.0, -0.08, -0.17, Basis(Vector3.RIGHT, -0.2)), dark, 1)
	# A back plate with a pale stripe.
	_add(parts, _block(Vector3(0.1, 0.09, 0.02), 0.005), _at(0.0, 0.01, 0.115), dark)
	_add(parts, Cel.box(Vector3(0.07, 0.018, 0.02)), _at(0.0, 0.03, 0.122), pale)
	_grip(parts)


## Six barrels about the spin axis, held by clamps, with a muzzle ring, in
## the Spinner's space.
static func _barrels(parts: Array) -> void:
	var body := Color(BODY, 0.0)
	var dark := Color(DARK, 0.0)
	var deep := Color(DEEP, 0.0)
	var turn_x := Basis(Vector3.RIGHT, PI * 0.5)
	for k in 6:
		var angle := k * TAU / 6.0
		_add(parts, Cel.cylinder(0.016, 0.016, 0.38, 6), _at(cos(angle) * 0.045, sin(angle) * 0.045, -0.19, turn_x), dark)
		_add(parts, Cel.cylinder(0.02, 0.02, 0.03, 6), _at(cos(angle) * 0.045, sin(angle) * 0.045, -0.37, turn_x), deep, 1)
	_add(parts, _ring(0.07, 0.035, 0.008), _at(0.0, 0.0, -0.17, turn_x), body)
	_add(parts, _ring(0.072, 0.045, 0.008), _at(0.0, 0.0, -0.33, turn_x), body)
	_add(parts, _ring(0.03, 0.4, 0.004, 8), _at(0.0, 0.0, -0.19, turn_x), deep, 1)
