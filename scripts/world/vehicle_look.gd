class_name VehicleLook
extends RefCounted

## Parts are merged per hull and turret. Team colour is in the vertex alpha.
const PLATE := Color(0.79, 0.77, 0.85, 0.0)
const DARK := Color(0.18, 0.16, 0.22, 0.0)
const GLASS := Color(0.25, 0.73, 0.8, 0.0)
const TEAM := Color(1.0, 1.0, 1.0, 1.0)
const PALE := Color(1.0, 0.88, 0.54, 0.0)
const ENGINE := Color(0.43, 0.4, 0.51, 0.0)
const FAR_DISTANCE := 72.0

static var _meshes := {}


static func build(vehicle: Vehicle) -> Node3D:
	var kind := vehicle.kind
	if not _meshes.has(kind):
		_meshes[kind] = _hull(kind)
	var far_key := "far%d" % kind
	if not _meshes.has(far_key):
		_meshes[far_key] = _hull(kind, true)
	var near := _view(vehicle, _meshes[kind], vehicle.team, true)
	var far := _view(vehicle, _meshes[far_key], vehicle.team, true)
	var bounds := near.get_aabb().merge(far.get_aabb())
	near.custom_aabb = bounds
	far.custom_aabb = bounds
	near.visibility_range_end = FAR_DISTANCE
	far.visibility_range_begin = FAR_DISTANCE
	if kind not in [Vehicle.Kind.TANK, Vehicle.Kind.GUNSHIP]:
		return null
	var mount := Node3D.new()
	mount.position = Vehicle.MUZZLE[kind]
	vehicle.add_child(mount)
	var key := "gun%d" % kind
	if not _meshes.has(key):
		var parts := []
		if kind == Vehicle.Kind.GUNSHIP:
			var cowling := Cel.loft([
				Vector4(0.21, 0.13, -0.57, 0), Vector4(0.38, 0.17, -0.14, 0),
				Vector4(0.33, 0.14, 0.44, 0),
			], 0.85)
			parts.append([cowling, Transform3D.IDENTITY, TEAM])
			_box(parts, Vector3(0.32, 0.15, 0.83), Vector3(0, 0.0, -0.91), ENGINE)
			_box(parts, Vector3(0.41, 0.22, 0.23), Vector3(0, 0.0, -1.32), PLATE)
		else:
			_box(parts, Vector3(1.15, 0.43, 1.15), Vector3.ZERO, TEAM)
			_box(parts, Vector3(0.24, 0.24, 1.4), Vector3(0, 0.02, -0.94), DARK)
			_box(parts, Vector3(0.35, 0.31, 0.24), Vector3(0, 0.02, -1.31), PLATE)
		_meshes[key] = Cel.merged(parts)
	_view(mount, _meshes[key], vehicle.team, true)
	return mount


static func _view(parent: Node3D, mesh: Mesh, team: int, figure := false) -> MeshInstance3D:
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = Cel.material(Color.WHITE, 1.0, true, true, false, figure)
	parent.add_child(view)
	Cel.set_team(view, Palette.team(team))
	return view


static func _box(parts: Array, size: Vector3, at: Vector3, colour: Color, yaw := 0.0, roll := 0.0) -> void:
	var bevel := minf(0.18, minf(size.x, minf(size.y, size.z)) * 0.22)
	parts.append([Cel.bevel_box(size, bevel), Transform3D(Basis.from_euler(Vector3(0, yaw, roll)), at), colour])


static func _skin(parts: Array, sections: Array[Vector4], colour: Color, at := Vector3.ZERO, basis := Basis.IDENTITY) -> void:
	parts.append([Cel.loft(sections, 0.75), Transform3D(basis, at), colour])


static func _hull(kind: int, far := false) -> ArrayMesh:
	var parts: Array
	match kind:
		Vehicle.Kind.BIKE: parts = _sled(far)
		Vehicle.Kind.GUNSHIP: parts = _needlewing(far)
		Vehicle.Kind.BOMBER: parts = _kite(far)
		Vehicle.Kind.TRANSPORT: parts = _ferry(far)
		_: parts = _crawler(far)
	return Cel.merged(parts)


static func _sled(far: bool) -> Array:
	var parts := []
	_skin(parts, [
		Vector4(0.13, 0.08, -1.72, 0),
		Vector4(0.34, 0.24, -0.62, 0),
		Vector4(0.38, 0.19, 0.51, 0),
		Vector4(0.19, 0.105, 1.59, 0),
	], TEAM)
	_skin(parts, [
		Vector4(0.10, 0.04, -1.29, 0),
		Vector4(0.25, 0.17, -0.60, 0),
		Vector4(0.19, 0.12, -0.23, 0),
	], GLASS, Vector3.UP * 0.22)
	_box(parts, Vector3(0.44, 0.14, 0.81), Vector3(0, 0.22, 0.27), ENGINE)
	for side: float in [-1, 1]:
		var runner := Vector3(side * 0.58, -0.17, 0)
		_skin(parts, [
			Vector4(0.09, 0.09, -1.35, 0),
			Vector4(0.26, 0.18, -0.40, 0),
			Vector4(0.20, 0.155, 1.37, 0),
		], PLATE, runner, Basis(Vector3.UP, side * 0.12))
		if not far:
			parts.append([Cel.box(Vector3(0.21, 0.10, 0.025)), Transform3D(Basis.IDENTITY, runner + Vector3(-side * 0.16, 0, 1.38)), PALE])
	return parts


static func _kite(far: bool) -> Array:
	var parts := []
	_skin(parts, [
		Vector4(0.23, 0.14, -2.59, 0),
		Vector4(0.61, 0.32, -1.47, 0),
		Vector4(1.16, 0.51, 0.65, 0),
		Vector4(0.79, 0.31, 2.51, 0),
	], PLATE)
	_skin(parts, [
		Vector4(0.26, 0.10, -1.99, 0),
		Vector4(0.48, 0.21, -1.39, 0),
		Vector4(0.52, 0.16, -0.6, 0),
	], GLASS, Vector3.UP * 0.38)
	_skin(parts, [
		Vector4(0.47, 0.06, -1.17, 0),
		Vector4(0.67, 0.09, -0.01, 0),
		Vector4(0.56, 0.05, 1.41, 0),
	], ENGINE, Vector3.DOWN * 0.39)
	for side: float in [-1, 1]:
		var sweep := Basis(Vector3.UP, side * PI * 0.5)
		_skin(parts, [
			Vector4(1.39, 0.19, 0, 0),
			Vector4(0.88, 0.14, 0.91, -side * 0.38),
			Vector4(0.24, 0.07, 1.86, -side * 1.00),
		], TEAM, Vector3(side * 0.75, -0.12, 0.28), sweep)
		_skin(parts, [
			Vector4(0.25, 0.19, -0.39, 0),
			Vector4(0.38, 0.27, 0.68, 0),
			Vector4(0.29, 0.24, 1.82, 0),
		], ENGINE, Vector3(side * 1.11, -0.1, 0.57))
		if not far:
			_box(parts, Vector3(0.24, 0.12, 0.04), Vector3(side * 1.11, -0.11, 2.40), PALE)
			parts.append([Cel.box(Vector3(0.17, 0.025, 1.23)), Transform3D(Basis(Vector3.UP, side * 0.65), Vector3(side * 1.83, 0.03, 0.95)), PLATE])
	return parts


static func _ferry(far: bool) -> Array:
	var parts := []
	_skin(parts, [
		Vector4(0.98, 0.39, -3.18, 0),
		Vector4(1.37, 0.63, -1.74, 0),
		Vector4(1.44, 0.67, 1.66, 0),
		Vector4(1.12, 0.46, 2.89, 0),
	], PLATE)
	_skin(parts, [
		Vector4(0.63, 0.14, -2.92, 0),
		Vector4(0.95, 0.31, -2.28, 0),
		Vector4(0.93, 0.29, -1.01, 0),
	], GLASS, Vector3.UP * 0.61)
	_box(parts, Vector3(2.14, 0.16, 1.11), Vector3(0, -0.37, 2.62), ENGINE)
	_box(parts, Vector3(1.7, 0.49, 0.09), Vector3(0, 0.04, 2.86), ENGINE)
	for side: float in [-1, 1]:
		var nacelle := Vector3(side * 1.80, -0.05, 0.08)
		_skin(parts, [
			Vector4(0.31, 0.22, -2.13, 0),
			Vector4(0.54, 0.42, -1.19, 0),
			Vector4(0.53, 0.39, 1.74, 0),
			Vector4(0.39, 0.28, 2.51, 0),
		], TEAM, nacelle)
		_box(parts, Vector3(0.45, 0.22, 0.13), nacelle + Vector3(0, 0, 2.51), ENGINE)
		if not far:
			for k in 3:
				parts.append([Cel.box(Vector3(0.05, 0.15, 0.30)), Transform3D(Basis.IDENTITY, Vector3(side * 1.40, 0.58, -0.19 + k * 0.54)), ENGINE])
			parts.append([Cel.box(Vector3(0.15, 0.16, 0.024)), Transform3D(Basis.IDENTITY, Vector3(side * 0.98, 0.12, 2.87)), PALE])
	return parts


static func _crawler(far: bool) -> Array:
	var parts := []
	_skin(parts, [
		Vector4(0.94, 0.32, -2.41, 0),
		Vector4(1.34, 0.47, -1.24, 0),
		Vector4(1.36, 0.46, 1.29, 0),
		Vector4(1.15, 0.35, 2.31, 0),
	], PLATE, Vector3.UP * 0.18)
	_skin(parts, [
		Vector4(0.61, 0.10, -2.11, 0),
		Vector4(0.86, 0.17, -1.51, 0),
		Vector4(0.85, 0.13, -1.11, 0),
	], TEAM, Vector3.UP * 0.52)
	for side: float in [-1, 1]:
		var at := Vector3(side * 1.45, -0.29, 0)
		_skin(parts, [
			Vector4(0.28, 0.21, -2.42, 0),
			Vector4(0.47, 0.46, -1.78, 0),
			Vector4(0.46, 0.46, 1.68, 0),
			Vector4(0.29, 0.22, 2.34, 0),
		], DARK.lightened(0.07), at)
		_skin(parts, [
			Vector4(0.31, 0.06, -2.05, 0),
			Vector4(0.46, 0.145, -1.43, 0),
			Vector4(0.46, 0.13, 1.74, 0),
			Vector4(0.32, 0.055, 2.17, 0),
		], TEAM, at + Vector3.UP * 0.52)
		if not far:
			for k in 5:
				parts.append([Cel.box(Vector3(0.05, 0.25, 0.44)), Transform3D(Basis.IDENTITY, Vector3(side * 1.91, -0.30, (k - 2) * 0.66)), ENGINE])
			_box(parts, Vector3(0.21, 0.13, 0.06), Vector3(side * 0.91, 0.28, -2.40), PALE)
	return parts


static func _needlewing(far: bool) -> Array:
	var parts := []
	var fuselage: Array[Vector4] = [
		Vector4(0.23, 0.14, -2.36, 0), Vector4(0.53, 0.29, -1.61, 0),
		Vector4(0.75, 0.39, 0.64, 0), Vector4(0.44, 0.22, 2.27, 0),
	]
	if far:
		fuselage.remove_at(1)
	parts.append([Cel.loft(fuselage), Transform3D.IDENTITY, PLATE])
	var canopy := Cel.loft([
		Vector4(0.26, 0.09, -1.77, 0), Vector4(0.44, 0.23, -1.02, 0), Vector4(0.34, 0.18, 0.04, 0),
	])
	parts.append([canopy, Transform3D(Basis.IDENTITY, Vector3(0, 0.38, 0)), Color(0.33, 0.64, 0.78, 0.0)])
	var collar := Cel.bevel_cylinder(0.23, 0.21, 0.04, 8)
	parts.append([collar, Transform3D(Basis.IDENTITY, Vector3(0, 0.59, -1.1)), ENGINE])
	for side: float in [-1, 1]:
		var sweep := Basis(Vector3.UP, side * PI * 0.5)
		var wing := Cel.loft([
			Vector4(0.88, 0.13, 0, 0), Vector4(0.57, 0.10, 0.74, -side * 0.31),
			Vector4(0.28, 0.065, 1.41, -side * 0.68),
		], 0.7)
		parts.append([wing, Transform3D(sweep, Vector3(side * 0.52, -0.05, 0.03)), TEAM])
		var nacelle := Cel.loft([
			Vector4(0.17, 0.14, -0.95, 0), Vector4(0.29, 0.25, -0.40, 0),
			Vector4(0.25, 0.22, 1.17, 0),
		], 0.62)
		var pod := Vector3(side * 1.57, 0.04, 0.52)
		parts.append([nacelle, Transform3D(Basis.IDENTITY, pod), ENGINE])
		var fin_shape: Array[Vector4] = [
			Vector4(0.045, 0.065, 0.64, 0), Vector4(0.058, 0.30, 1.17, 0),
			Vector4(0.036, 0.235, 1.84, 0),
		]
		var cant := Basis(Vector3.BACK, -side * 0.42)
		parts.append([Cel.loft(fin_shape, 0.8), Transform3D(cant, Vector3(side * 0.71, 0.43, 0)), TEAM])
		if far:
			continue
		var exhaust := Cel.loft([
			Vector4(0.23, 0.20, 0, 0), Vector4(0.20, 0.17, 0.21, 0),
		], 0.65)
		parts.append([exhaust, Transform3D(Basis.IDENTITY, pod + Vector3(0, 0, 1.15)), PLATE])
		parts.append([Cel.box(Vector3(0.19, 0.09, 0.025)), Transform3D(Basis.IDENTITY, pod + Vector3(0, -0.022, 1.37)), PALE])
		parts.append([Cel.box(Vector3(0.13, 0.02, 0.59)), Transform3D(Basis(Vector3.UP, side * -0.42), Vector3(side * 1.21, 0.075, 0.44)), PLATE])
	return parts


static func pad(parent: Node3D, kind: int, team: int) -> MeshInstance3D:
	var parts := []
	var wide := Vehicle.SIZE[kind].x * 0.5 + 1.1
	var deep := Vehicle.SIZE[kind].z * 0.5 + 1.0
	for side: float in [-1, 1]:
		_box(parts, Vector3(0.47, 0.18, deep * 2.0), Vector3(side * wide, 0.02, 0), DARK)
		for end: float in [-1, 1]:
			_box(parts, Vector3(0.8, 0.27, 0.7), Vector3(side * wide, 0.05, end * deep), TEAM)
	_box(parts, Vector3(wide * 1.8, 0.12, 0.35), Vector3(0, 0.04, deep), PLATE)
	_view(parent, Cel.merged(parts), team)
	var lamp := MeshInstance3D.new()
	lamp.mesh = Cel.bevel_box(Vector3(0.82, 0.15, 0.29), 0.04)
	lamp.position = Vector3(0, 0.17, deep)
	lamp.material_override = Cel.glow(Palette.team(team))
	parent.add_child(lamp)
	return lamp
