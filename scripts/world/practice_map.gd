class_name PracticeMap
extends GameMap

const START_X := -120.0
const SKI_X := -65.0
const CREST_X := 37.0
const FLAG_X := 108.0
const RUNOUT_X := 198.0
const HALF_LANE := 13.0


func _init() -> void:
	name = "PracticeMap"
	title = "Ski practice"
	palette = Palette.paperback()
	atmosphere = Atmosphere.new(palette)
	add_child(atmosphere)

	const CELLS := 120
	const CELL := 3.0
	var corner := Vector2(-144.0, -180.0)
	var heights := PackedFloat32Array()
	var patches := PackedFloat32Array()
	for row in CELLS + 1:
		var z := corner.y + row * CELL
		for column in CELLS + 1:
			var x := corner.x + column * CELL
			var slope := 33.0 * (1.0 - smoothstep(-114.0, -45.0, x))
			var crest := 12.0 * smoothstep(-30.0, CREST_X, x)
			# The flat landing takes a fast skier, with an uphill runout past the flag.
			var runout := 18.0 * smoothstep(124.0, RUNOUT_X, x)
			var sides := 18.0 * smoothstep(HALF_LANE, 48.0, absf(z))
			heights.append(slope + crest + runout + sides)
			patches.append(0.5 + 0.23 * sin(x * 0.29) * cos(z * 0.39))
	terrain = Terrain.new(CELLS, CELL, corner, heights, patches)
	add_child(terrain)

	_gate(START_X + 8.0, 5.0, InkUi.CREAM)
	_gate(SKI_X, 6.0, InkUi.ORANGE)
	_gate(CREST_X, 10.0, InkUi.PINK)
	_gate(FLAG_X, 6.0, Palette.team(1))
	for x: float in [-93.0, -45.0, -18.0, 12.0, 63.0, 84.0, 124.0, 149.0, 174.0]:
		for side: float in [-1.0, 1.0]:
			var z := side * HALF_LANE
			_view(Vector3(x, ground_height(x, z) + 0.45, z), Vector3(0.65, 0.9, 0.65), Cel.material(palette.structure))


func ground_height(x: float, z: float) -> float:
	return terrain.height_at(x, z)


func spawn_transform() -> Transform3D:
	var position := Vector3(START_X, ground_height(START_X, 0.0) + 0.3, 0.0)
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), position)


func flag_position() -> Vector3:
	return Vector3(FLAG_X, ground_height(FLAG_X, 0.0), 0.0)


func _gate(x: float, height: float, colour: Color) -> void:
	var ground := ground_height(x, 0.0)
	var post := Cel.material(palette.structure)
	var light := Cel.glow(colour)
	for side: float in [-1.0, 1.0]:
		var z := side * HALF_LANE
		_view(Vector3(x, ground + height * 0.5, z), Vector3(0.5, height, 0.65), post)
		_view(Vector3(x, ground + height - 0.55, z), Vector3(0.72, 0.8, 0.82), light)
	_view(Vector3(x, ground + height, 0.0), Vector3(0.22, 0.22, HALF_LANE * 2.0), light)


func _view(at: Vector3, size: Vector3, material: Material) -> void:
	var view := MeshInstance3D.new()
	view.mesh = Cel.box(size)
	view.material_override = material
	view.position = at
	add_child(view)
