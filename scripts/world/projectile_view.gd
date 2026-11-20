class_name ProjectileView
extends Node3D

## Draws every shot in flight with a MultiMesh per kind of shot (discs,
## disc trails, chaingun tracers, grenades, mortar shells, plasma balls and
## blaster bolts, hand grenades), so hundreds of rounds cost a draw call and
## its ink outline each. Mines, thrown or stuck, are drawn per team with a
## blinking light. Sniper shots are drawn as a beam by Effects. It only reads
## the match.

const MAX_SHOTS := 512
## Length of a chaingun tracer and of a disc's trail in metres.
const TRACER_LENGTH := 3.5
const TRAIL_LENGTH := 4.0
const BOLT_LENGTH := 1.6
const PLASMA_RADIUS := 0.17
## MultiMesh per kind of shot.
enum Kind { DISC, TRACER, TRAIL, GRENADE, SHELL, PLASMA, BOLT, HAND_GRENADE }
const GRENADE_COLOUR := Color(1.0, 0.82, 0.25)
const SHELL_COLOUR := WeaponModels.SHELL
const PLASMA_COLOUR := WeaponModels.PLASMA_GLOW
const BOLT_COLOUR := WeaponModels.BLASTER_GLOW
## Kind for each weapon slot, -1 for not drawn here.
const KINDS: Array[int] = [Kind.DISC, Kind.TRACER, Kind.GRENADE, Kind.SHELL, Kind.PLASMA, -1, Kind.BOLT, Kind.HAND_GRENADE, -1, Kind.PLASMA]
const MAX_MINES := 128
## A mine's light blinks for BLINK_ON seconds every BLINK_EVERY, twice as
## often while it arms.
const BLINK_EVERY := 1.0
const BLINK_ON := 0.15

var game: Match
var _views: Array[MultiMeshInstance3D] = []
## Per team: mine bodies and their lights.
var _mines: Array[MultiMeshInstance3D] = []
var _blinks: Array[MultiMeshInstance3D] = []


func _init() -> void:
	name = "ProjectileView"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.2
	disc.bottom_radius = 0.2
	disc.height = 0.06
	disc.radial_segments = 12
	disc.rings = 1
	disc.material = Cel.glow(WeaponModels.DISC_GLOW)
	var tracer := BoxMesh.new()
	tracer.size = Vector3(0.07, 0.07, 1.0)
	tracer.material = Cel.glow(Color(1.0, 0.9, 0.45))
	# A cone 1 m long from the disc back along +z, scaled to the trail.
	var trail_cone := CylinderMesh.new()
	trail_cone.top_radius = 0.0
	trail_cone.bottom_radius = 0.12
	trail_cone.height = 1.0
	trail_cone.radial_segments = 6
	trail_cone.rings = 1
	var trail := ArrayMesh.new()
	var arrays := trail_cone.get_mesh_arrays()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var lay := Basis(Vector3.RIGHT, PI * 0.5)
	for k in points.size():
		points[k] = lay * points[k] + Vector3(0.0, 0.0, 0.5)
		normals[k] = lay * normals[k]
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	trail.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	trail.surface_set_material(0, Cel.glow(Color(0.9, 1.0, 1.0)))
	var bolt := BoxMesh.new()
	bolt.size = Vector3(0.08, 0.08, 1.0)
	bolt.material = Cel.glow(BOLT_COLOUR)
	var inked := Cel.material(Color.WHITE, 1.0, true, true, false, false, true)
	var meshes: Array[Mesh] = [disc, tracer, trail, Cel.sphere(0.11, 0.22, 8), Cel.sphere(0.2, 0.4, 10), Effects.lumpy_ball(10, 5, 0.45, 2), bolt, hand_grenade_mesh()]
	var overrides: Array = [null, null, null, Cel.glow(GRENADE_COLOUR), Cel.glow(SHELL_COLOUR), Cel.glow(PLASMA_COLOUR), null, inked]
	for k in meshes.size():
		_views.append(_multi(meshes[k], overrides[k], MAX_SHOTS))
	for team in 2:
		var body := _multi(mine_mesh(), inked, MAX_MINES)
		Cel.set_team(body, Palette.team(team))
		_mines.append(body)
		_blinks.append(_multi(Cel.sphere(0.045, 0.06, 8), Cel.glow(Palette.team(team).lightened(0.3)), MAX_MINES))


func _multi(mesh: Mesh, material: Material, count: int) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = count
	multi.visible_instance_count = 0
	var view := MultiMeshInstance3D.new()
	view.multimesh = multi
	view.material_override = material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Shots fly across the whole map, so don't let culling hide them.
	view.custom_aabb = AABB(Vector3(-5000, -5000, -5000), Vector3(10000, 10000, 10000))
	add_child(view)
	return view


## A hand grenade: a pale ribbed body with a dark cap and lever, about 13 cm
## tall.
static func hand_grenade_mesh() -> ArrayMesh:
	var parts := []
	parts.append([Cel.sphere(0.055, 0.12, 8), Transform3D.IDENTITY, Color(WeaponModels.BODY, 0.0)])
	parts.append([Cel.cylinder(0.058, 0.058, 0.025, 8), Transform3D.IDENTITY, Color(WeaponModels.DARK, 0.0)])
	parts.append([Cel.cylinder(0.025, 0.03, 0.035, 6), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.07, 0.0)), Color(WeaponModels.DEEP, 0.0)])
	parts.append([Cel.box(Vector3(0.018, 0.08, 0.012)), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.035, 0.06)), Color(WeaponModels.DARK, 0.0)])
	return Cel.merged(parts)


## A mine, lying on +y: a squat dark disc with a team colour rim, a pale top
## plate, three prongs and the light's housing in the middle.
static func mine_mesh() -> ArrayMesh:
	var parts := []
	parts.append([Cel.bevel_cylinder(0.2, 0.07, 0.015, 12), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.035, 0.0)), Color(WeaponModels.DARK, 0.0)])
	# A wide team band round the side, so the team reads from a few metres.
	parts.append([Cel.cylinder(0.212, 0.212, 0.045, 12), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.035, 0.0)), Color(1.0, 1.0, 1.0, 1.0)])
	parts.append([Cel.bevel_cylinder(0.13, 0.03, 0.008, 12), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.08, 0.0)), Color(WeaponModels.BODY, 0.0)])
	parts.append([Cel.cylinder(0.04, 0.05, 0.03, 8), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.1, 0.0)), Color(WeaponModels.DEEP, 0.0)])
	for k in 3:
		var turn := Basis(Vector3.UP, TAU * k / 3.0)
		parts.append([Cel.box(Vector3(0.02, 0.05, 0.02)), Transform3D(turn, turn * Vector3(0.0, 0.11, 0.09)), Color(WeaponModels.DEEP, 0.0)])
	return Cel.merged(parts)


func _process(_delta: float) -> void:
	if game == null:
		return
	var counts: Array[int] = []
	counts.resize(_views.size())
	# Mine bodies and lights per team.
	var mine_counts: Array[int] = [0, 0, 0, 0]
	for shot in game.projectiles:
		if shot.weapon == Weapon.MINE:
			# Tumbling in flight, no light yet.
			var turn := Basis.from_euler(Vector3(shot.age * 6.0, shot.age * 4.0, 0.0))
			_place_mine(shot.team, mine_counts, Transform3D(turn, shot.visual_position()), false)
			continue
		var kind := KINDS[shot.weapon] if shot.weapon < KINDS.size() else Kind.TRACER
		if kind < 0 or counts[kind] >= MAX_SHOTS:
			continue
		var at := shot.visual_position()
		var dir := shot.velocity.normalized() if shot.velocity.length() > 0.01 else Vector3.FORWARD
		var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
		var basis := Basis.looking_at(dir, up)
		match kind:
			Kind.DISC:
				var trail_length := minf(TRAIL_LENGTH, shot.age * shot.velocity.length() * 0.5)
				if trail_length > 0.3 and counts[Kind.TRAIL] < MAX_SHOTS:
					_place(Kind.TRAIL, counts, Transform3D(basis.scaled_local(Vector3(1.0, 1.0, trail_length)), at))
				# Lies flat along its path, spinning.
				basis = basis * Basis(Vector3.UP, shot.age * 25.0)
			Kind.TRACER, Kind.BOLT:
				var longest := TRACER_LENGTH if kind == Kind.TRACER else BOLT_LENGTH
				var length := minf(longest, shot.age * shot.velocity.length())
				basis = basis.scaled_local(Vector3(1.0, 1.0, maxf(length, 0.2)))
				at -= dir * length * 0.5
			_:
				# Grenades, shells and plasma tumble as they go.
				basis = Basis.from_euler(Vector3(shot.age * 11.0, shot.age * 7.0, 0.0))
				if kind == Kind.PLASMA:
					basis = basis.scaled(Vector3.ONE * PLASMA_RADIUS)
		_place(kind, counts, Transform3D(basis, at))
	for mine in game.mines:
		var up := mine.normal.normalized()
		var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
		var basis := Basis(side, up, side.cross(up))
		var every := BLINK_EVERY if mine.armed() else BLINK_EVERY * 0.5
		_place_mine(mine.team, mine_counts, Transform3D(basis, mine.position - up * 0.04), fmod(mine.age, every) < BLINK_ON)
	for kind in _views.size():
		_views[kind].multimesh.visible_instance_count = counts[kind]
	for team in 2:
		_mines[team].multimesh.visible_instance_count = mine_counts[team]
		_blinks[team].multimesh.visible_instance_count = mine_counts[2 + team]


## A mine body for a team, and its light if lit. mine_counts holds bodies
## then lights by team.
func _place_mine(team: int, mine_counts: Array[int], where: Transform3D, lit: bool) -> void:
	team = clampi(team, 0, 1)
	if mine_counts[team] >= MAX_MINES:
		return
	_mines[team].multimesh.set_instance_transform(mine_counts[team], where)
	mine_counts[team] += 1
	if lit:
		_blinks[team].multimesh.set_instance_transform(mine_counts[2 + team], where * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.12, 0.0)))
		mine_counts[2 + team] += 1


func _place(kind: int, counts: Array[int], where: Transform3D) -> void:
	_views[kind].multimesh.set_instance_transform(counts[kind], where)
	counts[kind] += 1
