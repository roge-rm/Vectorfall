class_name HoldPoint
extends Node3D

const RADIUS := 14.0
const HEIGHT := 5.0
const CAPTURE_SECONDS := 3.0
const SCORE_SECONDS := 5.0
const NEUTRAL := Color("ffc47d")

var letter := ""
var spot := Vector3.ZERO
var owning_team := -1
var challenger := -1
var contested := false
var progress := 0.0
var held_seconds := 0.0
var arena: GameMap
var _beacon: MeshInstance3D
var _boundary: MeshInstance3D
var _shown := Color.TRANSPARENT


func _ready() -> void:
	var marker := CylinderMesh.new()
	marker.top_radius = 0.48
	marker.bottom_radius = 0.85
	marker.height = 4.0
	marker.radial_segments = 6
	_beacon = MeshInstance3D.new()
	_beacon.mesh = marker
	_beacon.position.y = 2.0
	add_child(_beacon)
	if arena != null:
		_make_boundary()
	var label := Label3D.new()
	label.text = letter
	label.font = InkUi.face(InkUi.Face.BLACK)
	label.font_size = 84
	label.pixel_size = 0.035
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 5.0
	add_child(label)


func _process(_delta: float) -> void:
	var tint := colour()
	if _shown != tint:
		_shown = tint
		_beacon.material_override = Cel.glow(tint)
		if _boundary != null:
			_boundary.material_override = _beacon.material_override


func _make_boundary() -> void:
	var ring := ImmediateMesh.new()
	ring.surface_begin(Mesh.PRIMITIVE_LINES)
	for index in 36:
		for end in [0.0, 0.65]:
			var angle: float = (index + end) * TAU / 36.0
			var at := Vector2(cos(angle), sin(angle)) * RADIUS
			var y := arena.surface_at(position.x + at.x, position.z + at.y) - position.y
			ring.surface_add_vertex(Vector3(at.x, y + 0.16, at.y))
	ring.surface_end()
	_boundary = MeshInstance3D.new()
	_boundary.mesh = ring
	_boundary.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_boundary)


func colour() -> Color:
	return NEUTRAL if owning_team < 0 or contested else Palette.team(owning_team)


func status() -> String:
	if contested:
		return "Contested"
	if challenger >= 0:
		return "%s taking %d%%" % [Soldier.TEAM_NAMES[challenger], int(progress * 100.0 / CAPTURE_SECONDS)]
	return "Neutral" if owning_team < 0 else Soldier.TEAM_NAMES[owning_team]


static func contains(at: Vector3, centre: Vector3, radius := RADIUS) -> bool:
	var offset := at - centre
	return absf(offset.y) <= HEIGHT and Vector2(offset.x, offset.z).length_squared() <= radius * radius


func advance(delta: float, sides: int) -> int:
	contested = sides == 3
	var alone := 0 if sides == 1 else (1 if sides == 2 else -1)
	if alone >= 0 and alone != owning_team:
		if challenger != alone:
			challenger = alone
			progress = 0.0
		progress += delta
		if progress + 0.0001 < CAPTURE_SECONDS:
			return -1
		owning_team = challenger
		held_seconds = 0.0
		delta = 0.0
	challenger = -1
	progress = 0.0
	if contested or owning_team < 0:
		return -1
	held_seconds += delta
	if held_seconds + 0.0001 < SCORE_SECONDS:
		return -1
	held_seconds = maxf(0.0, held_seconds - SCORE_SECONDS)
	return owning_team


func get_state() -> Dictionary:
	return {"letter": letter, "position": position, "owning_team": owning_team, "challenger": challenger,
		"contested": contested, "progress": progress, "held": held_seconds}


func set_state(state: Dictionary) -> void:
	owning_team = state.owning_team
	challenger = state.challenger
	contested = state.contested
	progress = state.progress
	held_seconds = state.held
