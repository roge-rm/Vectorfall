class_name CopperSteps
extends ArenaMap

## Three rock steps on each side of the basin. Two ramps wind up to the
## shelves below the flag decks. The troop ferries start on those shelves.

const FLAG_X := 402.0
const SUMMIT := 91.0
const PAD_X := 359.0
const PAD_Z := 126.0


func _init() -> void:
	super("Copper Steps", FLAG_X, SUMMIT, 96.0, 73, _copper_palette(), Vector2(501.0, 290.0),
		["north ledge", "straight climb", "south ledge"])


static func _copper_palette() -> Palette:
	var made := Palette.paperback()
	made.title = "Copper Steps"
	made.zenith = Color(0.19, 0.39, 0.48)
	made.horizon = Color(0.98, 0.83, 0.65)
	made.sky_middle = Color(0.42, 0.61, 0.62, 1.0)
	made.far_range = Color(0.47, 0.44, 0.58, 1.0)
	made.near_range = Color(0.37, 0.32, 0.46, 1.0)
	made.fog_colour = Color(0.79, 0.67, 0.65)
	made.fog_density = 0.0016
	made.ambient_energy = 0.52
	made.shade_dark = 0.40
	made.figure_line_scale = 0.8
	made.grass = Color(0.81, 0.45, 0.33)
	made.grass_dark = Color(0.73, 0.39, 0.31)
	made.dirt = Color(0.63, 0.34, 0.33)
	made.rock = Color(0.53, 0.28, 0.35)
	made.rock_alt = Color(0.65, 0.36, 0.36)
	made.strata = 7.8
	made.strata_fade_distance = 340.0
	made.low = Color(0.96, 0.69, 0.48)
	made.low_height = 19.0
	made.high = Color(0.92, 0.61, 0.42)
	made.high_height = 79.0
	made.patch_colour = Color(0.73, 0.49, 0.46)
	made.patch_amount = 0.15
	made.patch_size = 13.0
	made.variation_size = 36.0
	made.structure = Color(0.88, 0.79, 0.71)
	made.boulder = Color(0.53, 0.35, 0.41)
	return made


func _lane_offsets() -> Vector3:
	return Vector3(-120.0, 0.0, 120.0)


func _vehicle_pad_at(team: int, kind: Vehicle.Kind, at: Vector2) -> Vector2:
	if kind == Vehicle.Kind.TRANSPORT:
		return Vector2(-front(team) * PAD_X, PAD_Z)
	return at


func _routes() -> RouteGraph:
	var graph := super()
	for team in 2:
		var at := _vehicle_pad_at(team, Vehicle.Kind.TRANSPORT, Vector2.ZERO)
		var nearest := graph.nearest(Vector3(at.x, surface_at(at.x, at.y), at.y))
		graph.add_interest(RouteGraph.VEHICLE_PAD, team, nearest)
	return graph


func _land(x: float, z: float) -> float:
	var along := absf(x)
	var across := absf(z)
	var ledge_z := 119.0 + 22.0 * sin(along * 0.023 - 0.8)
	var lane_distance := minf(across, absf(across - ledge_z))
	# The steep face spreads out into a ski slope along each lane.
	var ramp_width := lerpf(71.0, 16.0, smoothstep(24.0, 62.0, lane_distance))
	var bend := 20.0 * sin(z * 0.022)
	var level := 12.0
	level += _riser(along, 91.0 + bend, ramp_width) * 24.0
	level += _riser(along, 180.0 - bend * 0.8, ramp_width) * 27.0
	level += _riser(along, 268.0 + bend * 0.6, ramp_width) * 28.0
	level += 2.6 * cos(along * 0.028) * sin(z * 0.012)
	# Four level shelves are wide enough for a loaded ferry to touch down.
	var shelf := (1.0 - smoothstep(30.0, 64.0, absf(along - PAD_X))) * (
		1.0 - smoothstep(27.0, 63.0, absf(across - PAD_Z)))
	level = lerpf(level, SUMMIT - 1.5, shelf)
	# Far from the approaches, weathered side walls rise above the basin.
	level += smoothstep(207.0, 283.0, across) * (20.0 + 8.0 * cos(along * 0.025))
	return level


static func _riser(along: float, centre: float, width: float) -> float:
	var half := width * 0.5
	return smoothstep(centre - half, centre + half, along)


func _dress(parent: Node3D) -> void:
	var copper := Color("945c53")
	var pale := Color("edc9a7")
	for direction: float in [-1.0, 1.0]:
		for side: float in [-1.0, 1.0]:
			_landing_marks(parent, Vector2(direction * PAD_X, side * PAD_Z), pale)
			# Perch cover on the terrace between the direct and side routes.
			prop(parent, Vector2(direction * 137.0, side * 61.0),
				Vector3(10.0, 4.4, 5.0), copper, side * 0.22)
			prop(parent, Vector2(direction * 233.0, side * 74.0),
				Vector3(7.0, 5.8, 9.0), copper.darkened(0.12), side * -0.27)
			prop(parent, Vector2(direction * 325.0, side * 174.0),
				Vector3(9.0, 6.5, 7.0), copper)
			# The low pylons mark the back edge of the landing area.
			prop(parent, Vector2(direction * (PAD_X + 22.0), side * (PAD_Z + 21.0)),
				Vector3(2.8, 2.2, 2.8), pale)


func _landing_marks(parent: Node3D, at: Vector2, pale: Color) -> void:
	var strips := []
	var paint := Color(pale, 0.0)
	for side: float in [-1.0, 1.0]:
		var bar := Cel.box(Vector3(22.0, 0.035, 0.52))
		strips.append([bar, Transform3D(Basis.IDENTITY, Vector3(0, 0, side * 7.8)), paint])
	var crossbar := Cel.box(Vector3(0.58, 0.035, 15.4))
	strips.append([crossbar, Transform3D.IDENTITY, paint])
	var view := MeshInstance3D.new()
	view.mesh = Cel.merged(strips)
	view.material_override = Cel.material(Color.WHITE, 0.0, false, true)
	view.position = Vector3(at.x, ground_height(at.x, at.y) + 0.045, at.y)
	view.visibility_range_end = 355.0
	parent.add_child(view)
