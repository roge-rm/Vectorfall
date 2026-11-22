class_name CalderaRelay
extends ArenaMap

const RIM_HEIGHT := 57.0
const RELAY_FRAME := Color("68617a")
const RELAY_SIGNAL := Color("ffc28a")


func _init() -> void:
	super("Caldera Relay", 390.0, RIM_HEIGHT, 96.0, 809, _colours(), Vector2(489, 264),
		["north rim", "crater floor", "south rim"])


static func _colours() -> Palette:
	var made := Palette.paperback()
	made.title = "Caldera Relay"
	made.zenith = Color("35284d")
	made.sky_middle = Color("885877")
	made.horizon = Color("efb192")
	made.fog_colour = Color("a187a0")
	made.fog_density = 0.0018
	made.far_range = Color("9f7188")
	made.near_range = Color("644965")
	made.ambient = Color("b4a2c9")
	made.grass = Color("675568")
	made.grass_dark = Color("57495f")
	made.dirt = Color("9b6a6d")
	made.rock = Color("453c52")
	made.rock_alt = Color("765464")
	made.strata = 4.8
	made.strata_fade_distance = 335.0
	made.low = Color("8f756d")
	made.low_height = -3.0
	made.high = Color("877080")
	made.high_height = 58.0
	made.patch_colour = Color("b98f75")
	made.patch_size = 15.0
	made.patch_amount = 0.13
	made.variation_colour = Color("d2b3b6")
	made.variation = 0.26
	made.variation_size = 33.0
	made.structure = Color("cab6b3")
	made.boulder = Color("594757")
	made.tech_glow = Color("ffbd8c")
	return made


func _lane_offsets() -> Vector3:
	return Vector3(-157.0, 0.0, 157.0)


func _land(x: float, z: float) -> float:
	var radius := Vector2(x, z * 1.76).length()
	var floor_y := -10.0 + 1.9 * cos(x * 0.033) * cos(z * 0.051)
	var wall := smoothstep(113.0, 321.0, radius)
	# The crest screens the longer routes along its outside shoulder.
	var rim := smoothstep(243.0, 310.0, radius) * (1.0 - smoothstep(321.0, 382.0, radius))
	var lip := (12.0 + 6.0 * cos(x * 0.043 + z * 0.025)) * rim
	# The plug splits the bowl into two ski runs and screens the opposite rim.
	var plug_radius := Vector2(x * 0.76, (z - 8.0) * 1.16).length()
	var plug := 56.0 * (1.0 - smoothstep(12.0, 66.0, plug_radius))
	return lerpf(floor_y, RIM_HEIGHT, wall) + lip + plug


func _dress(parent: Node3D) -> void:
	var lamps := []
	for team: float in [-1.0, 1.0]:
		for side: float in [-1.0, 1.0]:
			for step in 3:
				var at := Vector2(team * (92.0 + step * 7.2), side * (69.0 + step * 4.9))
				var tall := 5.0 + step * 2.4
				var radius := 2.8 + step * 0.5
				var centre := Vector3(at.x, ground_height(at.x, at.y) + tall * 0.5 - 0.8, at.y)
				_pillar(parent, centre, radius, tall)
				obstacles.append(Vector3(at.x, at.y, radius))
			_relay(parent, Vector2(team * 175.0, side * 158.0), lamps)
			prop(parent, Vector2(team * 268.0, side * 184.0), Vector3(18.0, 2.9, 4.2), RELAY_FRAME, team * side * -0.26)
	var signals := MeshInstance3D.new()
	signals.mesh = Cel.merged(lamps)
	signals.material_override = Cel.glow(RELAY_SIGNAL)
	parent.add_child(signals)


func _relay(parent: Node3D, at: Vector2, lamps: Array) -> void:
	var ground := ground_height(at.x, at.y)
	prop(parent, at, Vector3(3.8, 14.6, 4.8), RELAY_FRAME)
	for side: float in [-1.0, 1.0]:
		var rib := Vector3(at.x + side * 3.3, ground + 12.3, at.y)
		var tilt := Basis(Vector3.BACK, -side * 0.46)
		_box(parent, Vector3(0.92, 7.8, 2.6), Transform3D(tilt, rib), Cel.material(RELAY_FRAME))
		var light_at := rib + tilt * Vector3(0.0, 3.25, 0.0)
		lamps.append([Cel.box(Vector3(1.0, 0.86, 2.68)), Transform3D(tilt, light_at), Color.WHITE])


func control_sites() -> Array[Vector2]:
	return [Vector2(0, -176), Vector2(0, -68), Vector2(0, 176)]
