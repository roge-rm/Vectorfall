class_name SaltwakeFlats
extends ArenaMap


func _init() -> void:
	super("Saltwake Flats", 430.0, 21.0, 112.0, 481, _colours(), Vector2(525, 260), ["drainage cut", "salt pan", "wind berm"])


static func _colours() -> Palette:
	var made := Palette.paperback()
	made.title = "Saltwake Flats"
	made.grass = Color("#ebe2ce")
	made.grass_dark = Color("#d8cad6")
	made.dirt = Color("#aa91a8")
	made.rock = Color("#627892")
	made.rock_alt = Color("#8296ab")
	made.low_height = -8.0
	made.low = Color("#d4e6e6")
	made.patch_colour = Color("#b3c9cd")
	made.patch_amount = 0.045
	made.variation_colour = Color("#e6efeb")
	made.variation = 0.24
	made.strata = 0.0
	made.horizon = Color("#e6b391")
	made.sky_middle = Color("#be819e")
	made.zenith = Color("#494377")
	made.fog_colour = Color("#c7b2bf")
	made.ambient = Color(0.66, 0.57, 0.76)
	return made


func _land(x: float, z: float) -> float:
	var flat := -8.0 + 0.9 * cos(x * 0.049) * cos(z * 0.061)
	var rim := 30.0 * smoothstep(224.0, 415.0, x)
	# The deep cut hides a return on one side of the exposed pan.
	var channel := absf(z + 112.0 + 9.0 * cos(x * 0.015))
	var hollow := 12.0 * (1.0 - smoothstep(14.0, 36.0, channel))
	# The other flank has a long wind berm with shallow takeoff crests.
	var berm := 1.0 - smoothstep(18.0, 60.0, absf(z - 140.0))
	var crest := 6.0 + 3.0 * cos(x * 0.046)
	var fade := 1.0 - smoothstep(278.0, 370.0, x)
	return flat + rim + fade * (berm * crest - hollow)


func _lane_offsets() -> Vector3:
	return Vector3(-112, 0, 140)


func _dress(parent: Node3D) -> void:
	for side: float in [-1.0, 1.0]:
		for x: float in [75.0, 169.0, 257.0]:
			# Windbreaks sit between the open salt and the lowered lanes.
			prop(parent, Vector2(side * x, -53.0), Vector3(3.6, 3.1, 15.0), Color("#879da6"), side * 0.32)
			prop(parent, Vector2(side * (x + 13.0), 66.0), Vector3(4.0, 3.9, 14.0), Color("#a596af"), side * -0.24)
		for z: float in [-186.0, 194.0]:
			prop(parent, Vector2(side * 214.0, z), Vector3(6.0, 8.4, 5.3), Color("#748e9f"), side * 0.22)


func control_sites() -> Array[Vector2]:
	return [Vector2(0, -121), Vector2.ZERO, Vector2(0, 140)]
