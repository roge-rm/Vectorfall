class_name BotOverlay
extends Node3D

## The bots' debug overlay, shown and hidden with F3: the route graph (run
## links white, ski blue, jet orange, walls red, points of interest yellow
## posts), each bot's planned route in its team's colour, and a label over
## each bot with its role (and who it escorts or chases), goal, what it's
## doing, who it's fighting, its speed, energy and health, and over each flag
## stand what that team's commander wants and its last few decisions.

const LIFT := 0.4
const KIND_COLOURS: Array[Color] = [Color(0.9, 0.9, 0.9, 0.5), Color(0.3, 0.8, 1.0, 0.7), Color(1.0, 0.65, 0.2, 0.7)]
const WALL_COLOUR := Color(1.0, 0.2, 0.2, 0.9)
const INTEREST_COLOUR := Color(1.0, 0.95, 0.2)

var director: BotDirector
var _routes := ImmediateMesh.new()
var _labels: Dictionary[BotBrain, Label3D] = {}
var _team_labels: Dictionary[int, Label3D] = {}


func _init(bots: BotDirector) -> void:
	name = "BotOverlay"
	director = bots
	visible = false


func _ready() -> void:
	var graph_view := MeshInstance3D.new()
	graph_view.mesh = _graph_mesh(director.graph)
	graph_view.material_override = _line_material(false)
	add_child(graph_view)
	var routes_view := MeshInstance3D.new()
	routes_view.mesh = _routes
	routes_view.material_override = _line_material(true)
	add_child(routes_view)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_F3:
		visible = not visible


func _process(_delta: float) -> void:
	if not visible:
		return
	_routes.clear_surfaces()
	_show_commanders()
	var graph := director.graph
	var drew := false
	for brain in director.brains:
		var s := brain.soldier
		var label: Label3D = _labels.get(brain)
		if label == null:
			label = _make_label(s.team)
			_labels[brain] = label
		label.visible = not s.dead
		label.position = s.global_position + Vector3.UP * 2.6
		label.text = brain.describe()
		if s.dead or (brain.path.is_empty() and not brain.direct):
			continue
		if not drew:
			_routes.surface_begin(Mesh.PRIMITIVE_LINES)
			drew = true
		var colour := Palette.team(s.team).lightened(0.3)
		var last := s.global_position + Vector3.UP
		if brain.direct:
			# Straight for the goal, off the graph.
			_routes.surface_set_color(colour)
			_routes.surface_add_vertex(last)
			_routes.surface_set_color(colour)
			_routes.surface_add_vertex(brain.goal_target + Vector3.UP)
			continue
		for k in range(brain.path_index, brain.path.size()):
			var next := graph.points[brain.path[k]] + Vector3.UP
			_routes.surface_set_color(colour)
			_routes.surface_add_vertex(last)
			_routes.surface_set_color(colour)
			_routes.surface_add_vertex(next)
			last = next
	if drew:
		_routes.surface_end()


func _show_commanders() -> void:
	for team: int in director.commanders:
		var boss: TeamCommander = director.commanders[team]
		if not director.game.stands.has(team):
			continue
		var label: Label3D = _team_labels.get(team)
		if label == null:
			label = _make_label(team)
			label.font_size = 32
			_team_labels[team] = label
		label.position = director.game.stands[team] + Vector3.UP * 14.0
		var lines: Array[String] = ["%s wants %s" % [Soldier.TEAM_NAMES[team], boss.plan_text]]
		for k in range(maxi(boss.decisions.size() - 3, 0), boss.decisions.size()):
			lines.append("%.0f s  %s" % [boss.decisions[k].seconds, boss.decisions[k].text])
		label.text = "\n".join(lines)


func _make_label(team: int) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0012
	label.font_size = 28
	label.outline_size = 8
	label.modulate = Palette.team(team).lightened(0.4)
	add_child(label)
	return label


static func _line_material(on_top: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = on_top
	return material


static func _graph_mesh(graph: RouteGraph) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colours := PackedColorArray()
	for link in graph.links:
		vertices.append(graph.points[link.from] + Vector3.UP * LIFT)
		vertices.append(graph.points[link.to] + Vector3.UP * LIFT)
		var colour := WALL_COLOUR if link.must_jet else KIND_COLOURS[link.kind]
		colours.append(colour)
		colours.append(colour)
	for entry in graph.interest:
		var at := graph.points[entry.point]
		vertices.append(at)
		vertices.append(at + Vector3.UP * 4.0)
		colours.append(INTEREST_COLOUR)
		colours.append(INTEREST_COLOUR)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh
