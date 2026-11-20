class_name VehicleLook
extends RefCounted

## Parts are merged per hull and turret. Team colour is in the vertex alpha.
const PLATE := Color(0.79, 0.77, 0.85, 0.0)
const DARK := Color(0.18, 0.16, 0.22, 0.0)
const GLASS := Color(0.25, 0.73, 0.8, 0.0)
const TEAM := Color(1.0, 1.0, 1.0, 1.0)
const PALE := Color(1.0, 0.88, 0.54, 0.0)

static var _meshes := {}


static func build(vehicle: Vehicle) -> Node3D:
	var kind := vehicle.kind
	if not _meshes.has(kind):
		_meshes[kind] = _hull(kind)
	_view(vehicle, _meshes[kind], vehicle.team)
	if kind not in [Vehicle.Kind.TANK, Vehicle.Kind.GUNSHIP]:
		return null
	var mount := Node3D.new()
	mount.position = Vehicle.MUZZLE[kind]
	vehicle.add_child(mount)
	var key := "gun%d" % kind
	if not _meshes.has(key):
		var parts := []
		_box(parts, Vector3(1.15, 0.43, 1.15), Vector3.ZERO, TEAM)
		var size := Vector3(0.24, 0.24, 1.4) if kind == Vehicle.Kind.TANK else Vector3(0.5, 0.24, 0.9)
		_box(parts, size, Vector3(0, 0.02, -0.94), DARK)
		_box(parts, Vector3(size.x + 0.11, 0.31, 0.24), Vector3(0, 0.02, -1.31), PLATE)
		_meshes[key] = Cel.merged(parts)
	_view(mount, _meshes[key], vehicle.team)
	return mount


static func _view(parent: Node3D, mesh: Mesh, team: int) -> MeshInstance3D:
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = Cel.material(Color.WHITE, 1.0, true, true)
	parent.add_child(view)
	Cel.set_team(view, Palette.team(team))
	return view


static func _box(parts: Array, size: Vector3, at: Vector3, colour: Color, yaw := 0.0, roll := 0.0) -> void:
	var bevel := minf(0.18, minf(size.x, minf(size.y, size.z)) * 0.22)
	parts.append([Cel.bevel_box(size, bevel), Transform3D(Basis.from_euler(Vector3(0, yaw, roll)), at), colour])


static func _hull(kind: int) -> ArrayMesh:
	var parts := []
	match kind:
		Vehicle.Kind.BIKE:
			_box(parts, Vector3(0.76, 0.46, 2.65), Vector3.ZERO, TEAM)
			_box(parts, Vector3(0.52, 0.28, 1.07), Vector3(0, 0.29, -0.95), GLASS)
			_box(parts, Vector3(0.56, 0.2, 0.94), Vector3(0, 0.25, 0.3), DARK)
			for side: float in [-1, 1]:
				_box(parts, Vector3(0.52, 0.38, 2.28), Vector3(side * 0.66, -0.18, 0.13), PLATE, side * 0.18)
				_box(parts, Vector3(0.36, 0.14, 0.2), Vector3(side * 0.71, -0.12, 1.22), PALE)
		Vehicle.Kind.GUNSHIP:
			_box(parts, Vector3(1.46, 0.86, 4.4), Vector3.ZERO, PLATE)
			_box(parts, Vector3(0.92, 0.48, 1.58), Vector3(0, 0.48, -1.33), GLASS)
			for side: float in [-1, 1]:
				_box(parts, Vector3(1.65, 0.28, 1.24), Vector3(side * 1.39, -0.13, 0.13), TEAM, side * -0.34)
				_box(parts, Vector3(0.6, 0.57, 2.55), Vector3(side * 1.79, -0.05, 0.26), DARK)
				_box(parts, Vector3(0.43, 0.28, 0.15), Vector3(side * 1.79, -0.03, 1.55), PALE)
				_box(parts, Vector3(0.12, 0.75, 1.22), Vector3(side * 0.64, 0.47, 1.5), TEAM, side * 0.18, side * -0.33)
		Vehicle.Kind.BOMBER:
			_box(parts, Vector3(2.27, 0.84, 4.6), Vector3(0, 0.05, 0), DARK)
			_box(parts, Vector3(1.42, 0.49, 2.8), Vector3(0, 0.44, -0.43), TEAM)
			_box(parts, Vector3(1.2, 0.22, 0.92), Vector3(0, 0.65, -1.14), GLASS)
			for side: float in [-1, 1]:
				_box(parts, Vector3(2.35, 0.41, 2.09), Vector3(side * 1.79, -0.07, 0.46), TEAM, side * 0.63)
				_box(parts, Vector3(0.63, 0.55, 2.07), Vector3(side * 1.22, -0.21, 0.87), PLATE)
				_box(parts, Vector3(0.45, 0.31, 0.18), Vector3(side * 1.24, -0.21, 1.94), PALE)
				_box(parts, Vector3(0.1, 0.1, 2.15), Vector3(side * 1.98, 0.16, 0.41), PLATE, side * 0.63)
		Vehicle.Kind.TRANSPORT:
			_box(parts, Vector3(2.75, 1.24, 5.52), Vector3.ZERO, PLATE)
			_box(parts, Vector3(1.9, 0.74, 2.53), Vector3(0, 0.72, -1.5), DARK)
			_box(parts, Vector3(1.73, 0.45, 0.58), Vector3(0, 0.78, -2.65), GLASS)
			_box(parts, Vector3(2.4, 0.17, 1.11), Vector3(0, -0.43, 2.62), DARK)
			for side: float in [-1, 1]:
				_box(parts, Vector3(0.81, 0.72, 4.56), Vector3(side * 1.99, -0.11, 0.09), TEAM)
				_box(parts, Vector3(0.51, 0.33, 0.24), Vector3(side * 2.01, -0.1, 2.4), PALE)
				_box(parts, Vector3(0.21, 0.22, 2.67), Vector3(side * 1.44, 0.48, 1.16), TEAM)
		Vehicle.Kind.TANK:
			_box(parts, Vector3(2.52, 0.87, 4.5), Vector3(0, 0.24, 0), PLATE)
			_box(parts, Vector3(1.92, 0.45, 3.0), Vector3(0, 0.62, 0.12), DARK)
			_box(parts, Vector3(1.61, 0.26, 0.92), Vector3(0, 0.6, -1.63), TEAM)
			for side: float in [-1, 1]:
				_box(parts, Vector3(0.87, 0.93, 4.86), Vector3(side * 1.46, -0.33, 0), DARK)
				_box(parts, Vector3(0.94, 0.33, 4.22), Vector3(side * 1.45, 0.24, -0.02), TEAM)
				for k in 5:
					_box(parts, Vector3(0.09, 0.39, 0.38), Vector3(side * 1.9, -0.33, (k - 2) * 0.78), PLATE)
	return Cel.merged(parts)


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
