class_name BeaconWreck
extends ArenaMap

const FRAME := Color("3b464f")
const HULL := Color("aab3ac")
const BELT := Color("657a7c")
const MARK := Color("d8ad72")
const SIGNAL := Color("ffe3ae")
const CORE_Z := -6.0
const CORE_HALF := Vector2(12.0, 34.0)


func _init() -> void:
	super("Beacon Wreck", 294.0, 36.0, 98.0, 267, _colours(), Vector2(398, 218),
		["north dunes", "cargo bays", "south dunes"])


static func _colours() -> Palette:
	var made := Palette.desert()
	made.title = "Beacon Wreck"
	made.zenith = Color("333954")
	made.horizon = Color("e3bb9a")
	made.sky_middle = Color("918196")
	made.far_range = Color("978288")
	made.near_range = Color("776773")
	made.near_range_height = 0.1
	made.fog_colour = Color("c9a5a5")
	made.fog_density = 0.0018
	made.sun_direction = Vector3(-0.45, 0.62, 0.64)
	made.sun_colour = Color("ffe1b7")
	made.ambient = Color("a6a2c4")
	made.ambient_energy = 0.57
	made.shade_dark = 0.34
	made.shade_colour = Color(0.34, 0.26, 0.48, 0.55)
	made.grass = Color("d0a385")
	made.grass_dark = Color("bb8879")
	made.dirt = Color("aa7770")
	made.rock = Color("775565")
	made.rock_alt = Color("906f77")
	made.low = Color("d6b399")
	made.low_height = 9.0
	made.high = Color("d9b498")
	made.high_height = 27.0
	made.variation_colour = Color("e9a6ae")
	made.variation = 0.22
	made.variation_size = 47.0
	made.strata = 3.5
	made.patch_colour = Color("ba8d7e")
	made.patch_amount = 0.07
	made.patch_size = 18.0
	made.hatching = false
	made.structure = Color("c1bfb8")
	made.tech_glow = Color("f0cf9a")
	return made


func _lane_offsets() -> Vector3:
	return Vector3(-100, 0, 100)


func _land(x: float, z: float) -> float:
	var across := absf(z)
	var rise := 28.0 * smoothstep(117.0, 245.0, x)
	var dune := 11.0 * sin((x * 0.65 + across) * 0.035) + 4.5 * sin((across - x * 0.82) * 0.024)
	var wash := smoothstep(26.0, 66.0, across)
	var rim := 23.0 * smoothstep(148.0, 221.0, across)
	return 8.0 + rise + wash * (13.0 + dune) + rim


func blocked_at(x: float, z: float) -> bool:
	# The collapsed drive closes the spine between the two sets of bays.
	if absf(x) < CORE_HALF.x and absf(z - CORE_Z) < CORE_HALF.y:
		return true
	return super(x, z)


func _dress(parent: Node3D) -> void:
	var finishes := []
	var lights := []
	var floor_y := ground_height(0.0, 0.0)
	for side: float in [-1.0, 1.0]:
		for bank: float in [-1.0, 1.0]:
			_cargo_bay(parent, side, bank, floor_y, finishes, lights)
			# Scattered plating sits between the wreck and the dune runs.
			prop(parent, Vector2(side * 31.0, bank * 41.0), Vector3(9.0, 3.8, 4.1), BELT, side * bank * 0.4)
			prop(parent, Vector2(side * 146.0, bank * 54.0), Vector3(14.0, 5.2, 5.5), HULL, -side * bank * 0.44)
		_beacon(parent, side, floor_y, finishes, lights)
	_drive_wreck(parent, floor_y, finishes, lights)
	_add_details(parent, finishes, Cel.material(Color.WHITE, 0.0, false, true))
	_add_details(parent, lights, Cel.glow(SIGNAL))


func _drive_wreck(parent: Node3D, floor_y: float, finishes: Array, lights: Array) -> void:
	var centre := Vector3(0.0, floor_y + 5.0, CORE_Z)
	_box(parent, Vector3(22.0, 14.0, 65.0), Transform3D(Basis.IDENTITY, centre), Cel.material(FRAME))
	var shell := centre + Vector3.UP * 7.55
	_detail(finishes, Vector3(19.0, 1.1, 59.0), Transform3D(Basis.IDENTITY, shell), HULL)
	for z: float in [-19.0, 0.0, 19.0]:
		var rib := shell + Vector3(0, 0.8, z)
		_detail(finishes, Vector3(20.0, 0.7, 3.2), Transform3D(Basis.IDENTITY, rib), BELT)
		_detail(lights, Vector3(13.0, 0.12, 0.42), Transform3D(Basis.IDENTITY, rib + Vector3.UP * 0.39), Color.WHITE)
	for side: float in [-1.0, 1.0]:
		var edge := centre + Vector3(side * 10.85, 1.0, 0)
		_detail(finishes, Vector3(0.3, 4.4, 59.0), Transform3D(Basis.IDENTITY, edge), BELT)
		_detail(finishes, Vector3(0.4, 0.65, 32.0), Transform3D(Basis.IDENTITY, edge + Vector3.UP * 1.5), MARK)


func _cargo_bay(parent: Node3D, side: float, bank: float, floor_y: float, finishes: Array, lights: Array) -> void:
	var tilt := Basis(Vector3.RIGHT, bank * 0.22)
	for bay: float in [43.0, 105.0]:
		var wall_z := bank * 22.5
		prop(parent, Vector2(side * bay, wall_z), Vector3(36.0, 12.5, 1.45), FRAME)
		var roof := Transform3D(tilt, Vector3(side * bay, floor_y + 14.45, bank * 11.9))
		_box(parent, Vector3(39.0, 0.92, 24.0), roof, Cel.material(HULL))
		# The gap between bays opens from the cargo spine to the dunes.
		var sill := Vector3(side * bay, floor_y + 4.2, wall_z)
		_detail(finishes, Vector3(32.0, 2.1, 1.6), Transform3D(Basis.IDENTITY, sill), BELT)
		_detail(lights, Vector3(14.0, 0.13, 1.62), Transform3D(Basis.IDENTITY, sill + Vector3.UP * 1.12), Color.WHITE)
		for rail: float in [-1.0, 1.0]:
			_detail(finishes, Vector3(0.9, 0.47, 24.4), roof.translated_local(Vector3(side * rail * 16.8, 0.61, 0)), FRAME)
		for stripe: float in [0.0, 3.4]:
			var mark := roof.translated_local(Vector3(side * (8.0 + stripe), 0.49, bank * 2.0))
			_detail(finishes, Vector3(1.25, 0.04, 13.0), mark, MARK)
		var lane_mark := Vector3(side * bay, floor_y + 0.025, bank * 5.7)
		_detail(finishes, Vector3(17.0, 0.025, 0.22), Transform3D(Basis.IDENTITY, lane_mark), MARK)
		prop(parent, Vector2(side * (bay + 6.2), bank * 13.3), Vector3(9.3, 3.1, 5.0), BELT, side * bank * 0.15)
	# A bent bulkhead marks the end of each torn hull.
	var end := Vector3(side * 26.0, floor_y + 8.55, bank * 20.4)
	var lean := Basis(Vector3.FORWARD, side * 0.29)
	_box(parent, Vector3(3.0, 17.5, 3.0), Transform3D(lean, end), Cel.material(BELT))
	obstacles.append(Vector3(end.x, end.z, 4.6))


func _beacon(parent: Node3D, side: float, floor_y: float, finishes: Array, lights: Array) -> void:
	var roof := Vector3(side * 45.0, floor_y + 14.7, 5.2)
	var aim := Basis(Vector3.FORWARD, side * 0.2)
	_box(parent, Vector3(2.2, 14.0, 2.2), Transform3D(aim, roof + Vector3.UP * 7.2), Cel.material(FRAME))
	var head := roof + Vector3(side * 1.7, 14.2, 0)
	_detail(finishes, Vector3(4.0, 2.3, 4.0), Transform3D(aim, head), HULL)
	_detail(lights, Vector3(4.1, 0.72, 4.1), Transform3D(aim, head + Vector3.UP * 0.37), Color.WHITE)
	_detail(finishes, Vector3(0.65, 4.0, 0.65), Transform3D(aim, head + Vector3.UP * 2.9), BELT)


static func _detail(parts: Array, size: Vector3, placement: Transform3D, colour: Color) -> void:
	parts.append([Cel.box(size), placement, Color(colour, 0.0)])


static func _add_details(parent: Node3D, parts: Array, material: Material) -> void:
	var view := MeshInstance3D.new()
	view.mesh = Cel.merged(parts)
	view.material_override = material
	parent.add_child(view)


func control_sites() -> Array[Vector2]:
	return [Vector2(0, -100), Vector2(0, 68), Vector2(0, 118)]
