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
const DEEP := Color(0.21, 0.19, 0.25)
const PALE := Color(0.98, 0.96, 0.9)
const DISC_GLOW := Color(0.7, 1.0, 1.0)
const LENS := Color(1.0, 0.86, 0.4)
const PLASMA_GLOW := Color(1.0, 0.32, 0.74)
const SNIPER_GLOW := Color(0.85, 0.95, 1.0)
const BLASTER_GLOW := Color(1.0, 0.24, 0.2)
const SHELL := Color(1.0, 0.45, 0.22)

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
		if barrels:
			_barrels(parts)
		else:
			match slot:
				Weapon.CHAINGUN:
					_chaingun(parts)
					if far:
						# The far version's barrels are part of the body.
						_add(parts, Cel.box(Vector3(0.1, 0.1, 0.4)), _at(0.0, 0.02, -0.44), DARK)
				Weapon.GRENADE_LAUNCHER:
					_grenade_launcher(parts)
				Weapon.MORTAR:
					_mortar(parts)
				Weapon.PLASMA:
					_plasma_gun(parts)
				Weapon.SNIPER:
					_sniper_rifle(parts)
				Weapon.BLASTER:
					_blaster(parts)
				_:
					_disc_launcher(parts)
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


## Long plates taper into the muzzle and stock. The far receiver stays a box.
static func _receiver(size: Vector3, nose: Vector2, heel: Vector2) -> Mesh:
	if _far:
		return Cel.box(size)
	var h := size * 0.5
	return Cel.loft([
		Vector4(h.x * nose.x, h.y * nose.y, -h.z, 0),
		Vector4(h.x, h.y, -h.z * 0.36, 0),
		Vector4(h.x * heel.x, h.y * heel.y, h.z, 0),
	], 0.7)


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
	_add(parts, _receiver(Vector3(0.12, 0.12, 0.36), Vector2(0.84, 0.7), Vector2(0.68, 0.90)), _at(0.0, 0.03, -0.07), body)
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
	_add(parts, _receiver(Vector3(0.14, 0.14, 0.3), Vector2(0.85, 0.87), Vector2(0.80, 0.94)), _at(0.0, 0.02, -0.04), body)
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


## A drum fed launcher: a squat receiver with team colour cover, a fat
## revolving drum under a short wide barrel with a team colour muzzle, a
## leaf sight, a front grip and a padded stock.
static func _grenade_launcher(parts: Array) -> void:
	var body := Color(BODY, 0.0)
	var dark := Color(DARK, 0.0)
	var deep := Color(DEEP, 0.0)
	var team := _team()
	var pale := Color(PALE, 0.0)
	var turn_x := Basis(Vector3.RIGHT, PI * 0.5)
	_add(parts, _receiver(Vector3(0.11, 0.12, 0.3), Vector2(0.9, 0.82), Vector2(0.67, 0.82)), _at(0.0, 0.03, -0.02), body)
	_add(parts, _block(Vector3(0.12, 0.03, 0.22), 0.01), _at(0.0, 0.105, -0.04), team)
	_add(parts, _block(Vector3(0.1, 0.03, 0.08), 0.008), _at(0.0, 0.09, 0.1, Basis(Vector3.RIGHT, -0.4)), team)
	for side: float in [1.0, -1.0]:
		_add(parts, _block(Vector3(0.012, 0.055, 0.14), 0.004), _at(side * 0.057, 0.03, -0.03), team)
		_add(parts, Cel.box(Vector3(0.014, 0.016, 0.14)), _at(side * 0.057, -0.01, -0.03), pale, 1)
	_seams(parts, 0.056, [0.07, -0.02], 0.0, 0.26)
	# The drum, with grooves along it, rims and the rounds' caps on its face.
	_add(parts, _ring(0.09, 0.15, 0.014, 12), _at(0.0, -0.03, -0.235, turn_x), dark)
	for z: float in [-0.163, -0.307]:
		_add(parts, _ring(0.094, 0.014, 0.004, 12), _at(0.0, -0.03, z, turn_x), body, 1)
	for k in 6:
		var angle := k * TAU / 6.0 + PI / 6.0
		var round_at := Vector3(cos(angle) * 0.056, -0.03 + sin(angle) * 0.056, -0.312)
		_add(parts, Cel.cylinder(0.022, 0.022, 0.012, 8), Transform3D(turn_x, round_at), Color(LENS, 0.0), 1)
		_add(parts, Cel.box(Vector3(0.014, 0.014, 0.12)), Transform3D(Basis(Vector3.BACK, angle), Vector3(cos(angle) * 0.088, -0.03 + sin(angle) * 0.088, -0.235)), deep, 1)
	# The short wide barrel over the drum, with bands and a team muzzle.
	_add(parts, _ring(0.045, 0.3, 0.008, 12), _at(0.0, 0.085, -0.33, turn_x), dark)
	for z: float in [-0.36, -0.42]:
		_add(parts, _ring(0.048, 0.016, 0.004, 12), _at(0.0, 0.085, z, turn_x), body, 1)
	_add(parts, _ring(0.062, 0.06, 0.01, 12), _at(0.0, 0.085, -0.5, turn_x), team)
	_add(parts, Cel.cylinder(0.036, 0.036, 0.062, 10), _at(0.0, 0.085, -0.5, turn_x), deep)
	# A folding leaf sight and a rear sight.
	_add(parts, _block(Vector3(0.05, 0.06, 0.012), 0.003), _at(0.0, 0.155, -0.16, Basis(Vector3.RIGHT, -0.25)), dark, 1)
	_add(parts, Cel.box(Vector3(0.052, 0.01, 0.014)), _at(0.0, 0.17, -0.163), pale, 1)
	_add(parts, _block(Vector3(0.03, 0.04, 0.04), 0.005), _at(0.0, 0.135, 0.04), dark, 1)
	# A front grip under the drum.
	_add(parts, _block(Vector3(0.04, 0.1, 0.05), 0.01), _at(0.0, -0.16, -0.24, Basis(Vector3.RIGHT, -0.2)), dark, 1)
	# The back plate, struts and a padded stock.
	_add(parts, _block(Vector3(0.09, 0.09, 0.02), 0.005), _at(0.0, 0.03, 0.135), dark)
	for y: float in [0.06, -0.01]:
		_add(parts, _block(Vector3(0.022, 0.022, 0.13), 0.005), _at(0.0, y, 0.2), dark, 1)
	_add(parts, _block(Vector3(0.055, 0.13, 0.04), 0.012), _at(0.0, 0.025, 0.28), dark)
	_add(parts, _block(Vector3(0.058, 0.11, 0.014), 0.004), _at(0.0, 0.025, 0.303), team, 1)
	_grip(parts)


## A long fat tube with a flared muzzle and team colour bands over a heavy
## breech, a shell box on the left with the shells' noses showing, a sight
## on the right, a carry grip under the tube and a shoulder pad.
static func _mortar(parts: Array) -> void:
	var body := Color(BODY, 0.0)
	var dark := Color(DARK, 0.0)
	var deep := Color(DEEP, 0.0)
	var team := _team()
	var pale := Color(PALE, 0.0)
	var turn_x := Basis(Vector3.RIGHT, PI * 0.5)
	var tube_y := 0.1
	# The breech block and its cover.
	_add(parts, _receiver(Vector3(0.14, 0.13, 0.28), Vector2(0.73, 0.84), Vector2(0.91, 0.80)), _at(0.0, 0.0, -0.02), body)
	_add(parts, _block(Vector3(0.012, 0.07, 0.18), 0.004), _at(0.071, 0.0, -0.03), team)
	_add(parts, _block(Vector3(0.012, 0.07, 0.18), 0.004), _at(-0.071, 0.0, -0.03), team)
	_seams(parts, 0.07, [0.045, -0.045], -0.02, 0.24)
	# The tube, turned along z: the flare at the front end, a collar at the
	# back.
	var profile := PackedVector2Array([Vector2(0.098, -0.37), Vector2(0.118, -0.34), Vector2(0.118, -0.3), Vector2(0.086, -0.26), Vector2(0.076, -0.2), Vector2(0.076, 0.3), Vector2(0.088, 0.32), Vector2(0.088, 0.37), Vector2(0.07, 0.39)])
	_add(parts, Cel.lathe(profile, 6 if _far else 14), _at(0.0, tube_y, -0.31, turn_x), body)
	_add(parts, Cel.cylinder(0.076, 0.076, 0.012, 6 if _far else 12), _at(0.0, tube_y, -0.684, turn_x), deep)
	for z: float in [-0.46, -0.1]:
		_add(parts, _ring(0.081, 0.045, 0.006, 14), _at(0.0, tube_y, z, turn_x), team)
	_add(parts, _ring(0.079, 0.014, 0.003, 14), _at(0.0, tube_y, -0.38, turn_x), pale, 1)
	# A shell box on the left with three noses showing.
	_add(parts, _block(Vector3(0.06, 0.1, 0.17), 0.012), _at(-0.1, -0.02, -0.1), dark)
	_add(parts, _block(Vector3(0.064, 0.02, 0.174), 0.005), _at(-0.1, 0.03, -0.1), team, 1)
	for k in 3:
		_add(parts, Cel.cylinder(0.016, 0.022, 0.03, 8), _at(-0.1, 0.055, -0.15 + k * 0.05), Color(SHELL, 0.0), 1)
	# A sight on a post on the right.
	_add(parts, _block(Vector3(0.02, 0.07, 0.02), 0.004), _at(0.09, 0.1, -0.02), dark, 1)
	_add(parts, _block(Vector3(0.04, 0.045, 0.1), 0.006), _at(0.1, 0.15, -0.03), dark, 1)
	_add(parts, Cel.cylinder(0.014, 0.014, 0.102, 8), _at(0.1, 0.155, -0.03, turn_x), Color(LENS, 0.0), 1)
	# A clamp round the tube with a carry grip under it.
	_add(parts, _ring(0.086, 0.03, 0.005, 14), _at(0.0, tube_y, -0.27, turn_x), dark, 1)
	_add(parts, _block(Vector3(0.04, 0.13, 0.05), 0.01), _at(0.0, -0.04, -0.28, Basis(Vector3.RIGHT, -0.15)), dark, 1)
	# Recoil rods along the underside of the tube.
	for side: float in [1.0, -1.0]:
		_add(parts, Cel.cylinder(0.009, 0.009, 0.3, 6), _at(side * 0.05, tube_y - 0.07, -0.33, turn_x), deep, 2)
	# Vent slats on the breech, the back plate and a shoulder pad.
	for k in 3:
		_add(parts, Cel.box(Vector3(0.144, 0.01, 0.012)), _at(0.0, -0.045, 0.04 + k * 0.025), deep, 1)
	_add(parts, _block(Vector3(0.12, 0.12, 0.02), 0.005), _at(0.0, 0.0, 0.13), dark)
	_add(parts, _block(Vector3(0.09, 0.11, 0.04), 0.012), _at(0.0, 0.02, 0.16), dark)
	_add(parts, _block(Vector3(0.094, 0.03, 0.044), 0.006), _at(0.0, 0.05, 0.16), team, 1)
	_grip(parts)


## A rounded receiver with team colour cover, a glowing pink chamber held in
## a cage, a short barrel ringed with cooling fins and a team colour muzzle,
## a coolant tank on the right and a short stock.
static func _plasma_gun(parts: Array) -> void:
	var body := Color(BODY, 0.0)
	var dark := Color(DARK, 0.0)
	var deep := Color(DEEP, 0.0)
	var team := _team()
	var pale := Color(PALE, 0.0)
	var glow := Color(PLASMA_GLOW, 0.0)
	var turn_x := Basis(Vector3.RIGHT, PI * 0.5)
	_add(parts, _receiver(Vector3(0.12, 0.12, 0.22), Vector2(0.75, 0.72), Vector2(0.78, 0.94)), _at(0.0, 0.03, 0.0), body)
	_add(parts, _block(Vector3(0.13, 0.035, 0.18), 0.012), _at(0.0, 0.105, 0.0), team)
	_add(parts, _block(Vector3(0.1, 0.03, 0.07), 0.008), _at(0.0, 0.09, 0.1, Basis(Vector3.RIGHT, -0.45)), team)
	_add(parts, Cel.box(Vector3(0.124, 0.016, 0.16)), _at(0.0, -0.01, 0.0), pale, 1)
	_seams(parts, 0.061, [0.07], 0.0, 0.18)
	# The chamber: a glowing ball between two collars, held by three bars.
	_add(parts, Cel.sphere(0.088, 0.16, 6 if _far else 12), _at(0.0, 0.03, -0.18), glow)
	for z: float in [-0.11, -0.25]:
		_add(parts, _ring(0.07, 0.03, 0.008, 12), _at(0.0, 0.03, z, turn_x), dark)
	for k in 3:
		var angle := k * TAU / 3.0 + PI * 0.5
		_add(parts, _block(Vector3(0.018, 0.018, 0.15), 0.004), Transform3D(Basis(Vector3.BACK, angle), Vector3(cos(angle) * 0.07, 0.03 + sin(angle) * 0.07, -0.18)), dark)
	# The barrel with its fins, and the muzzle.
	_add(parts, _ring(0.032, 0.24, 0.006, 10), _at(0.0, 0.03, -0.37, turn_x), dark)
	for k in 5:
		_add(parts, _ring(0.058, 0.012, 0.003, 12), _at(0.0, 0.03, -0.29 - k * 0.034, turn_x), body, 0 if k % 2 == 0 else 1)
	_add(parts, _ring(0.046, 0.05, 0.008, 12), _at(0.0, 0.03, -0.49, turn_x), team)
	_add(parts, Cel.cylinder(0.024, 0.024, 0.052, 8), _at(0.0, 0.03, -0.49, turn_x), glow, 1)
	# A coolant tank on the right with bands, and a hose to the chamber.
	_add(parts, _ring(0.032, 0.15, 0.008, 10), _at(0.085, -0.02, -0.02, turn_x), team, 1)
	for z: float in [-0.07, 0.03]:
		_add(parts, _ring(0.034, 0.014, 0.003, 10), _at(0.085, -0.02, z, turn_x), dark, 1)
	_add(parts, Cel.box(Vector3(0.016, 0.016, 0.1)), _at(0.06, 0.0, -0.13, Basis(Vector3.UP, 0.4)), deep, 2)
	# A reflex sight with a pink glass.
	_add(parts, _block(Vector3(0.036, 0.04, 0.05), 0.006), _at(0.0, 0.14, -0.02), dark, 1)
	_add(parts, Cel.box(Vector3(0.026, 0.026, 0.052)), _at(0.0, 0.145, -0.02), glow, 1)
	# A front grip, the back plate and a short stock.
	_add(parts, _block(Vector3(0.04, 0.09, 0.045), 0.01), _at(0.0, -0.08, -0.15, Basis(Vector3.RIGHT, -0.2)), dark, 1)
	_add(parts, _block(Vector3(0.09, 0.09, 0.02), 0.005), _at(0.0, 0.03, 0.12), dark)
	_add(parts, _block(Vector3(0.06, 0.1, 0.11), 0.014), _at(0.0, 0.02, 0.18), dark)
	_add(parts, _block(Vector3(0.064, 0.03, 0.06), 0.006), _at(0.0, 0.06, 0.19), team, 1)
	_grip(parts)


## A long slim rifle: a thin receiver with a team colour cover, a long
## barrel in a vented shroud with glowing coils near the front and a muzzle
## brake, a big scope, an energy cell on the left and a skeleton stock.
static func _sniper_rifle(parts: Array) -> void:
	var body := Color(BODY, 0.0)
	var dark := Color(DARK, 0.0)
	var deep := Color(DEEP, 0.0)
	var team := _team()
	var pale := Color(PALE, 0.0)
	var glow := Color(SNIPER_GLOW, 0.0)
	var turn_x := Basis(Vector3.RIGHT, PI * 0.5)
	_add(parts, _receiver(Vector3(0.08, 0.1, 0.34), Vector2(0.62, 0.69), Vector2(0.82, 0.86)), _at(0.0, 0.03, -0.05), body)
	_add(parts, _block(Vector3(0.09, 0.03, 0.26), 0.008), _at(0.0, 0.09, -0.06), team)
	_add(parts, Cel.box(Vector3(0.084, 0.014, 0.3)), _at(0.0, -0.005, -0.05), pale, 1)
	_seams(parts, 0.041, [0.055], -0.05, 0.3)
	# The barrel, its shroud with vent slots, the coils and the brake.
	_add(parts, _ring(0.02, 0.66, 0.004, 8), _at(0.0, 0.04, -0.54, turn_x), dark)
	_add(parts, _block(Vector3(0.06, 0.06, 0.28), 0.01), _at(0.0, 0.04, -0.35), body)
	for side: float in [1.0, -1.0]:
		for k in 4:
			_add(parts, Cel.box(Vector3(0.008, 0.026, 0.035)), _at(side * 0.03, 0.04, -0.27 - k * 0.055), deep, 1)
	for k in 3:
		_add(parts, _ring(0.034, 0.016, 0.004, 10), _at(0.0, 0.04, -0.55 - k * 0.045, turn_x), glow, 0 if k == 1 else 1)
	_add(parts, _block(Vector3(0.05, 0.04, 0.08), 0.008), _at(0.0, 0.04, -0.88), dark)
	for side: float in [1.0, -1.0]:
		_add(parts, Cel.box(Vector3(0.008, 0.022, 0.016)), _at(side * 0.025, 0.04, -0.87), deep, 1)
	# The scope on two mounts, with a bell at the front, an eyepiece, a lens
	# and a turret.
	_add(parts, _ring(0.03, 0.24, 0.006, 10), _at(0.0, 0.16, -0.08, turn_x), dark)
	_add(parts, _ring(0.042, 0.06, 0.008, 12), _at(0.0, 0.16, -0.22, turn_x), dark)
	_add(parts, _ring(0.036, 0.04, 0.006, 10), _at(0.0, 0.16, 0.06, turn_x), dark)
	_add(parts, Cel.cylinder(0.034, 0.034, 0.062, 10), _at(0.0, 0.16, -0.22, turn_x), Color(LENS, 0.0), 1)
	for z: float in [-0.15, 0.0]:
		_add(parts, _block(Vector3(0.026, 0.05, 0.03), 0.005), _at(0.0, 0.115, z), deep)
	_add(parts, _ring(0.016, 0.03, 0.004, 8), _at(0.0, 0.195, -0.08), deep, 1)
	_add(parts, _ring(0.033, 0.014, 0.003, 10), _at(0.0, 0.16, -0.12, turn_x), team, 1)
	# The energy cell on the left with a glowing window.
	_add(parts, _block(Vector3(0.03, 0.06, 0.16), 0.008), _at(-0.052, 0.01, -0.1), dark)
	_add(parts, Cel.box(Vector3(0.006, 0.02, 0.1)), _at(-0.068, 0.015, -0.1), glow, 1)
	# A folded bipod under the shroud.
	for side: float in [1.0, -1.0]:
		_add(parts, Cel.box(Vector3(0.012, 0.012, 0.2)), _at(side * 0.018, 0.0, -0.4), deep, 2)
	# The skeleton stock with a cheek rest and a butt plate.
	_add(parts, _block(Vector3(0.07, 0.08, 0.02), 0.005), _at(0.0, 0.03, 0.13), dark)
	_add(parts, _block(Vector3(0.035, 0.03, 0.15), 0.006), _at(0.0, 0.06, 0.2), dark)
	_add(parts, _block(Vector3(0.03, 0.025, 0.16), 0.006), _at(0.0, -0.03, 0.2, Basis(Vector3.RIGHT, 0.12)), dark, 1)
	_add(parts, _block(Vector3(0.05, 0.03, 0.08), 0.006), _at(0.0, 0.085, 0.2), team, 1)
	_add(parts, _block(Vector3(0.05, 0.14, 0.035), 0.01), _at(0.0, 0.015, 0.285), dark)
	_grip(parts)


## A compact energy pistol: a short body with a team colour top sloping
## down at the front, an emitter with three prongs round a glowing red tip,
## cooling fins on top, a cell under the front and a glowing back window.
static func _blaster(parts: Array) -> void:
	var body := Color(BODY, 0.0)
	var dark := Color(DARK, 0.0)
	var deep := Color(DEEP, 0.0)
	var team := _team()
	var pale := Color(PALE, 0.0)
	var glow := Color(BLASTER_GLOW, 0.0)
	var turn_x := Basis(Vector3.RIGHT, PI * 0.5)
	_add(parts, _receiver(Vector3(0.09, 0.1, 0.22), Vector2(0.67, 0.85), Vector2(0.89, 0.71)), _at(0.0, 0.03, -0.06), body)
	_add(parts, _block(Vector3(0.1, 0.03, 0.17), 0.008), _at(0.0, 0.095, -0.04), team)
	_add(parts, _block(Vector3(0.09, 0.03, 0.07), 0.008), _at(0.0, 0.075, -0.15, Basis(Vector3.RIGHT, 0.5)), team)
	_add(parts, Cel.box(Vector3(0.094, 0.014, 0.18)), _at(0.0, -0.005, -0.06), pale, 1)
	_seams(parts, 0.046, [0.06], -0.06, 0.18)
	# The emitter, its prongs and the glowing tip.
	_add(parts, _ring(0.036, 0.1, 0.008, 10), _at(0.0, 0.03, -0.21, turn_x), dark)
	_add(parts, _ring(0.04, 0.016, 0.004, 10), _at(0.0, 0.03, -0.18, turn_x), deep, 1)
	_add(parts, Cel.cylinder(0.024, 0.024, 0.02, 8), _at(0.0, 0.03, -0.265, turn_x), glow)
	for k in 3:
		var angle := k * TAU / 3.0 + PI * 0.5
		_add(parts, _block(Vector3(0.014, 0.014, 0.07), 0.003), Transform3D(Basis(Vector3.BACK, angle), Vector3(cos(angle) * 0.034, 0.03 + sin(angle) * 0.034, -0.29)), dark, 0 if k == 0 else 1)
	# Cooling fins across the top.
	for k in 4:
		_add(parts, Cel.box(Vector3(0.07, 0.028, 0.01)), _at(0.0, 0.122, 0.0 - k * 0.03), dark, 1)
	# A cell under the front with a red window.
	_add(parts, _block(Vector3(0.05, 0.05, 0.08), 0.008), _at(0.0, -0.04, -0.14), dark, 1)
	_add(parts, Cel.box(Vector3(0.054, 0.014, 0.04)), _at(0.0, -0.035, -0.14), glow, 1)
	# The back plate with its glowing window, and a hammer.
	_add(parts, _block(Vector3(0.08, 0.08, 0.02), 0.005), _at(0.0, 0.03, 0.055), dark)
	_add(parts, Cel.box(Vector3(0.04, 0.02, 0.02)), _at(0.0, 0.045, 0.062), glow)
	_add(parts, _block(Vector3(0.02, 0.04, 0.03), 0.005), _at(0.0, 0.09, 0.07, Basis(Vector3.RIGHT, -0.4)), deep, 1)
	_grip(parts)
