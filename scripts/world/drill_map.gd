class_name DrillMap
extends GameMap

const FLAG_X := -6.0
const EXIT_X := 35.0
const LANE_HALF_WIDTH := 9.0
const TARGET_Z := -42.0
const GENERATOR := Vector3.ZERO
const ATTACKER := Vector3(15.0, 0.0, 4.0)
const LANDING_LIP := -36.0
const LANDING_START := -26.0
const LANDING_END := 78.0

var start := Transform3D.IDENTITY


func _init(flag_run: bool, repair: bool, landing := false) -> void:
	name = "DrillMap"
	palette = Palette.paperback()
	atmosphere = Atmosphere.new(palette)
	add_child(atmosphere)

	const CELLS := 64
	const CELL := 3.0
	var corner := Vector2.ONE * -CELLS * CELL * 0.5
	var heights := PackedFloat32Array()
	var patches := PackedFloat32Array()
	for row in CELLS + 1:
		var z := corner.y + row * CELL
		for column in CELLS + 1:
			var x := corner.x + column * CELL
			var bank := 22.0 * smoothstep(29.0, 77.0, maxf(absf(x), absf(z)))
			if flag_run:
				bank = 28.0 * (1.0 - smoothstep(-72.0, -15.0, x))
				bank += 11.0 * smoothstep(LANE_HALF_WIDTH, 41.0, absf(z))
				bank += 14.0 * smoothstep(50.0, 90.0, x)
			elif landing:
				bank = 20.0 * (1.0 - smoothstep(-78.0, -39.0, x))
				bank += 38.0 * (1.0 - smoothstep(LANDING_LIP, LANDING_LIP + CELL, x))
				bank += 11.0 * smoothstep(LANE_HALF_WIDTH, 41.0, absf(z))
			heights.append(bank)
			patches.append(0.5 + 0.24 * sin(x * 0.23) * cos(z * 0.42))
	terrain = Terrain.new(CELLS, CELL, corner, heights, patches)
	add_child(terrain)

	if flag_run:
		start = pose(Vector2(-72.0, 0.0), -PI * 0.5)
		_build_flag_lane()
	elif repair:
		start = pose(Vector2(0.0, 14.0))
		_build_repair_bay()
	elif landing:
		start = pose(Vector2(-78.0, 0.0), -PI * 0.5)
		_build_landing_lane()
	else:
		start = pose(Vector2(0.0, 6.0))
		_build_range()


func pose(at: Vector2, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, terrain.height_at(at.x, at.y) + 0.3, at.y))


func _build_flag_lane() -> void:
	var post := Cel.material(palette.structure)
	for x: float in [-66.0, -53.0, -40.0, -27.0, -14.0, 7.0, 19.0]:
		for side: float in [-1.0, 1.0]:
			var at := pose(Vector2(x, side * LANE_HALF_WIDTH)).origin
			_view(at + Vector3.UP * 0.25, Vector3(0.3, 1.1, 0.9), post)
	_gate(FLAG_X, Palette.team(1))
	_gate(EXIT_X, Palette.team(0))


func _gate(x: float, colour: Color) -> void:
	var frame := Cel.material(palette.structure)
	var light := Cel.glow(colour)
	for side: float in [-1.0, 1.0]:
		_view(Vector3(x, 2.0, side * LANE_HALF_WIDTH), Vector3(0.7, 4.0, 0.7), frame)
		_view(Vector3(x, 3.8, side * LANE_HALF_WIDTH), Vector3(0.9, 0.45, 0.9), light)
	_view(Vector3(x, 4.2, 0.0), Vector3(0.34, 0.24, LANE_HALF_WIDTH * 2.0), light)


func _build_range() -> void:
	var frame := Cel.material(palette.structure)
	var light := Cel.glow(InkUi.AMBER)
	for x: float in [-23.0, 0.0, 23.0]:
		var ground := terrain.height_at(x, TARGET_Z)
		_view(Vector3(x, ground + 1.5, TARGET_Z), Vector3(0.9, 3.0, 1.3), frame)
		_view(Vector3(x, ground + 3.0, TARGET_Z), Vector3(1.15, 0.35, 1.5), light)
	_view(Vector3(0.0, 0.05, 4.0), Vector3(10.0, 0.12, 0.28), Cel.glow(Palette.team(0)))


func _build_landing_lane() -> void:
	var edge := Cel.glow(InkUi.AMBER)
	for side: float in [-1.0, 1.0]:
		for x: float in [-69.0, -57.0, -45.0, LANDING_LIP]:
			var post := pose(Vector2(x, side * LANE_HALF_WIDTH)).origin
			_view(post + Vector3.UP * 0.35, Vector3(0.4, 1.3, 0.7), edge)
	var light := Cel.glow(Palette.team(0))
	var length := LANDING_END - LANDING_START
	for side: float in [-1.0, 1.0]:
		_view(Vector3(LANDING_START + length * 0.5, 0.05, side * LANE_HALF_WIDTH), Vector3(length, 0.1, 0.28), light)
	for x: float in [LANDING_START, LANDING_END]:
		_view(Vector3(x, 0.05, 0.0), Vector3(0.28, 0.1, LANE_HALF_WIDTH * 2.0), light)


func _build_repair_bay() -> void:
	var wall := Cel.material(palette.structure)
	var light := Cel.glow(Palette.team(0))
	_box(self, Vector3(0.85, 3.6, 10.0), Transform3D(Basis.IDENTITY, Vector3(3.1, 1.8, 0.0)), wall)
	_box(self, Vector3(7.6, 3.6, 0.85), Transform3D(Basis.IDENTITY, Vector3(-0.3, 1.8, -5.0)), wall)
	_view(Vector3(3.1, 3.65, 0.0), Vector3(0.8, 0.12, 9.9), light)
	for x: float in [-2.4, 2.4]:
		_view(Vector3(x, 0.07, 6.2), Vector3(0.32, 0.14, 1.5), light)


func _view(at: Vector3, size: Vector3, material: Material) -> void:
	var view := MeshInstance3D.new()
	view.position = at
	view.mesh = Cel.box(size)
	view.material_override = material
	add_child(view)
