class_name AssetLook
extends Node3D

## The look of a base asset in merged ink meshes in the team's colour with
## dark trim: a generator with two housings round a glowing core, a turret's
## post with a swivelling twin barrel head, and a sensor's mast with a
## turning dish. Its origin is the asset's foot and it faces -z. Each frame
## it shows how the asset is: working, unpowered (its lights off and the
## sensor still) or destroyed (darker, lights off, smoke and sparks). A
## working generator lights its room through glow point Cel.set_glow(team).
##
## Draw calls: a generator 2 (body and core), a turret 2 (post and head), a
## sensor 2 (mast and dish), each with its outline pass, plus the smoke and
## sparks only while destroyed.

enum Shown { WORKING, UNPOWERED, DESTROYED }

const TRIM := Color(0.15, 0.14, 0.18, 0.0)
const PALE := Color(0.82, 0.8, 0.86, 0.0)
const TEAM_PART := Color(1.0, 1.0, 1.0, 1.0)
## Team colour half mixed with a dark grey, for the generator's housings so
## its core stands out.
const TEAM_DARK := Color(0.3, 0.3, 0.36, 0.6)
const LIGHT_ON := Color(1.0, 0.96, 0.62, 0.0)
const LIGHT_OFF := Color(0.24, 0.23, 0.27, 0.0)
## A destroyed asset's colours are darkened this much and lose this share of
## their team colour.
const DARKEN := 0.55
const TEAM_LOSS := 0.5
## How fast a working sensor's dish turns, in radians a second.
const DISH_TURN := 1.2
## The generator's light on its room: radius in metres and strength.
const ROOM_GLOW := 9.0
const ROOM_GLOW_STRENGTH := 0.8

## Meshes by kind, part and Shown, shared by every asset.
static var _meshes: Dictionary[String, ArrayMesh] = {}

var asset: BaseAsset
var shown := -1
var _body: MeshInstance3D
var _head: MeshInstance3D
var _core: MeshInstance3D
var _smoke: CPUParticles3D
var _sparks: CPUParticles3D


## Adds the look under an asset and gives back a turret's head, or null.
static func build(parent: BaseAsset, kind: int, team: int) -> Node3D:
	var made := AssetLook.new()
	made.name = "AssetLook"
	made.asset = parent
	parent.add_child(made)
	made._body = made._view("Body", made)
	if kind == BaseAsset.Kind.GENERATOR:
		made._core = MeshInstance3D.new()
		made._core.name = "Core"
		made._core.mesh = _mesh(kind, "core", Shown.WORKING)
		made._core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		made.add_child(made._core)
	elif kind == BaseAsset.Kind.TURRET:
		made._head = made._view("Head", parent)
		made._head.position = Vector3.UP * BaseAsset.HEIGHT[kind] * BaseAsset.PIVOT_SHARE
	else:
		made._head = made._view("Dish", made)
		made._head.position = Vector3.UP * BaseAsset.HEIGHT[kind] * 0.86
	made._show(Shown.WORKING, team)
	return made._head if kind == BaseAsset.Kind.TURRET else null


func _view(view_name: String, under: Node3D) -> MeshInstance3D:
	var view := MeshInstance3D.new()
	view.name = view_name
	view.material_override = Cel.material(Color.WHITE, 1.0, true, true, false, true)
	under.add_child(view)
	return view


func _process(delta: float) -> void:
	if asset == null:
		return
	var want := Shown.WORKING
	if asset.destroyed:
		want = Shown.DESTROYED
	else:
		var game := asset.get_parent() as Match
		if game != null and not game.asset_powered(asset):
			want = Shown.UNPOWERED
	if want != shown:
		_show(want, asset.team)
	if asset.kind == BaseAsset.Kind.SENSOR and shown == Shown.WORKING:
		_head.rotate_y(DISH_TURN * delta)


func _exit_tree() -> void:
	if asset != null and asset.kind == BaseAsset.Kind.GENERATOR and shown == Shown.WORKING:
		Cel.set_glow(asset.team, Vector3.ZERO, 0.0, Color(0.0, 0.0, 0.0, 0.0))


func _show(state: int, team: int) -> void:
	shown = state
	var kind := asset.kind
	var colour := Palette.team(team)
	_body.mesh = _mesh(kind, "body", state)
	Cel.set_team(_body, colour)
	if _head != null:
		_head.mesh = _mesh(kind, "head", state)
		Cel.set_team(_head, colour)
	if _core != null:
		if state == Shown.WORKING:
			_core.material_override = Cel.glow(colour.lightened(0.65), true)
		else:
			_core.material_override = Cel.material(TRIM.darkened(0.3), 0.0)
	if kind == BaseAsset.Kind.GENERATOR and is_inside_tree():
		var at := global_position + Vector3.UP * 1.2
		if state == Shown.WORKING:
			var light := colour.lightened(0.3)
			light.a = ROOM_GLOW_STRENGTH
			Cel.set_glow(team, at, ROOM_GLOW, light)
		else:
			Cel.set_glow(team, at, 0.0, Color(0.0, 0.0, 0.0, 0.0))
	if state == Shown.DESTROYED and _smoke == null:
		_make_wreck_effects()
	if _smoke != null:
		_smoke.emitting = state == Shown.DESTROYED
		_sparks.emitting = state == Shown.DESTROYED


## Thin dark smoke rising from the top and a few sparks now and then, each
## one instanced draw call.
func _make_wreck_effects() -> void:
	var top := BaseAsset.HEIGHT[asset.kind]
	_smoke = CPUParticles3D.new()
	_smoke.name = "Smoke"
	_smoke.mesh = Effects.lumpy_ball(6, 3, 0.4, 2.0)
	_smoke.material_override = Cel.material(Color(0.2, 0.19, 0.21), 0.0, false)
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke.amount = 8
	_smoke.lifetime = 2.4
	_smoke.position = Vector3.UP * top * 0.85
	_smoke.direction = Vector3.UP
	_smoke.spread = 12.0
	_smoke.gravity = Vector3.UP * 0.4
	_smoke.initial_velocity_min = 0.5
	_smoke.initial_velocity_max = 0.9
	_smoke.scale_amount_min = 0.3
	_smoke.scale_amount_max = 0.5
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.3))
	grow.add_point(Vector2(0.5, 1.0))
	grow.add_point(Vector2(1.0, 0.0))
	_smoke.scale_amount_curve = grow
	add_child(_smoke)
	_sparks = CPUParticles3D.new()
	_sparks.name = "Sparks"
	_sparks.mesh = Cel.box(Vector3(0.05, 0.05, 0.05))
	_sparks.material_override = Cel.glow(Color(1.0, 0.85, 0.4))
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sparks.amount = 5
	_sparks.lifetime = 0.6
	_sparks.explosiveness = 0.9
	_sparks.position = Vector3.UP * top * 0.6
	_sparks.direction = Vector3.UP
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 1.5
	_sparks.initial_velocity_max = 3.0
	_sparks.gravity = Vector3.DOWN * 9.8
	add_child(_sparks)


## A part's mesh for a kind and Shown, made once. part is "body", "head"
## or "core".
static func _mesh(kind: int, part: String, state: int) -> ArrayMesh:
	var key := "%d/%s/%d" % [kind, part, state]
	if _meshes.has(key):
		return _meshes[key]
	var parts := []
	match kind:
		BaseAsset.Kind.GENERATOR:
			parts = _generator_core() if part == "core" else _generator()
		BaseAsset.Kind.TURRET:
			parts = _turret_head() if part == "head" else _turret_post()
		_:
			parts = _sensor_dish() if part == "head" else _sensor_mast()
	var for_glow := part == "core"
	for each: Array in parts:
		var colour: Color = each[2]
		if colour == LIGHT_ON and state != Shown.WORKING:
			colour = LIGHT_OFF
		if state == Shown.DESTROYED and not for_glow:
			var team_amount := colour.a * (1.0 - TEAM_LOSS)
			colour = colour.darkened(DARKEN)
			colour.a = team_amount
		each[2] = colour
	var made := Cel.merged(parts, for_glow)
	_meshes[key] = made
	return made


static func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


## Along -z, for barrels.
static func _forward(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, y, z))


## A chunky machine: a plinth, two team coloured housings with vents either
## side of the core, a pale cap with a stack on top and pipes front and back.
static func _generator() -> Array:
	var parts := []
	parts.append([Cel.bevel_box(Vector3(2.8, 0.25, 2.3), 0.04), _at(0.0, 0.125, 0.0), TRIM])
	for side: float in [-1.0, 1.0]:
		var shell := Cel.loft([
			Vector4(0.30, 0.61, -1.0, 0), Vector4(0.375, 0.80, -0.66, 0),
			Vector4(0.375, 0.80, 0.68, 0), Vector4(0.30, 0.61, 1.0, 0),
		], 0.6)
		parts.append([shell, _at(side * 0.95, 1.05, 0.0), TEAM_DARK])
		for k in 3:
			parts.append([Cel.box(Vector3(0.06, 0.1, 1.4)), _at(side * 1.33, 0.7 + k * 0.25, 0.0), TRIM])
		parts.append([Cel.box(Vector3(0.4, 0.08, 0.04)), _at(side * 0.95, 1.55, -1.01), LIGHT_ON])
		parts.append([Cel.box(Vector3(0.4, 0.08, 0.04)), _at(side * 0.95, 1.55, 1.01), LIGHT_ON])
		for end: float in [-1.0, 1.0]:
			parts.append([Cel.cylinder(0.07, 0.07, 1.5, 6), _at(side * 0.42, 1.0, end * 0.95), TRIM])
	parts.append([Cel.bevel_box(Vector3(2.7, 0.3, 2.2), 0.05), _at(0.0, 2.0, 0.0), PALE])
	parts.append([Cel.cylinder(0.6, 0.6, 0.14, 10), _at(0.0, 0.32, 0.0), TRIM])
	parts.append([Cel.cylinder(0.6, 0.6, 0.14, 10), _at(0.0, 1.78, 0.0), TRIM])
	parts.append([Cel.cylinder(0.25, 0.32, 0.3, 8), _at(0.0, 2.3, 0.0), TRIM])
	return parts


## The core between the housings, with bands round it.
static func _generator_core() -> Array:
	var core := Color(1.0, 1.0, 1.0)
	return [
		[Cel.cylinder(0.42, 0.42, 1.32, 10), _at(0.0, 1.05, 0.0), core],
		[Cel.cylinder(0.47, 0.47, 0.08, 10), _at(0.0, 0.8, 0.0), core.darkened(0.15)],
		[Cel.cylinder(0.47, 0.47, 0.08, 10), _at(0.0, 1.3, 0.0), core.darkened(0.15)],
	]


## A round foot, a pale post with a team coloured collar and a light.
static func _turret_post() -> Array:
	var parts := []
	parts.append([Cel.bevel_cylinder(0.75, 0.25, 0.04, 10), _at(0.0, 0.125, 0.0), TRIM])
	parts.append([Cel.cylinder(0.32, 0.48, 0.9, 8), _at(0.0, 0.7, 0.0), PALE])
	parts.append([Cel.cylinder(0.5, 0.5, 0.14, 10), _at(0.0, 1.2, 0.0), TEAM_PART])
	parts.append([Cel.box(Vector3(0.16, 0.08, 0.04)), _at(0.0, 0.85, -0.43), LIGHT_ON])
	return parts


## Placed from the swivel point: a team coloured block with side pods and
## two barrels out the front, and a light slit over them.
static func _turret_head() -> Array:
	var parts := []
	var cowling := Cel.loft([
		Vector4(0.34, 0.17, -0.45, 0), Vector4(0.46, 0.24, -0.12, 0),
		Vector4(0.39, 0.23, 0.45, 0),
	], 0.65)
	parts.append([cowling, _at(0.0, 0.05, 0.0), TEAM_PART])
	parts.append([Cel.bevel_box(Vector3(0.61, 0.075, 0.56), 0.03), _at(0.0, 0.29, 0.05), PALE])
	for side: float in [-1.0, 1.0]:
		parts.append([Cel.bevel_box(Vector3(0.2, 0.32, 0.65), 0.03), _at(side * 0.55, 0.02, 0.05), TEAM_DARK])
		parts.append([Cel.cylinder(0.07, 0.07, 0.85, 6), _forward(side * 0.17, -0.02, -0.82), TRIM])
		parts.append([Cel.cylinder(0.1, 0.1, 0.14, 6), _forward(side * 0.17, -0.02, -1.2), TRIM])
	parts.append([Cel.box(Vector3(0.36, 0.07, 0.04)), _at(0.0, 0.18, -0.46), LIGHT_ON])
	return parts


## A square foot, a thin mast with a team coloured collar and struts.
static func _sensor_mast() -> Array:
	var parts := []
	parts.append([Cel.bevel_box(Vector3(0.9, 0.2, 0.9), 0.03), _at(0.0, 0.1, 0.0), TRIM])
	parts.append([Cel.cylinder(0.09, 0.18, 2.0, 6), _at(0.0, 1.2, 0.0), PALE])
	parts.append([Cel.cylinder(0.28, 0.28, 0.2, 8), _at(0.0, 0.6, 0.0), TEAM_PART])
	parts.append([Cel.cylinder(0.14, 0.14, 0.12, 8), _at(0.0, 2.1, 0.0), TRIM])
	for k in 3:
		var angle := TAU * k / 3.0
		var out := Vector3(sin(angle), 0.0, cos(angle))
		var strut := Basis(out.cross(Vector3.UP).normalized(), -0.5)
		parts.append([Cel.box(Vector3(0.05, 0.9, 0.05)), Transform3D(strut, out * 0.22 + Vector3.UP * 0.55), TRIM])
	return parts


## Placed from the top of the mast: a team coloured dish tipped back, with
## a feed out the front and a light on its tip.
static func _sensor_dish() -> Array:
	var parts := []
	var tip := Basis(Vector3.RIGHT, -1.1)
	var face := tip * Vector3.UP
	var dish := Cel.lathe(PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.12, 0.0), Vector2(0.46, 0.09),
		Vector2(0.68, 0.205), Vector2(0.72, 0.235), Vector2(0.68, 0.26),
		Vector2(0.42, 0.14), Vector2(0.0, 0.07),
	]), 10)
	parts.append([dish, Transform3D(tip, Vector3.ZERO), TEAM_PART])
	parts.append([Cel.cylinder(0.025, 0.025, 0.6, 4), Transform3D(tip, face * 0.5), TRIM])
	parts.append([Cel.sphere(0.07, 0.14, 6), Transform3D(tip, face * 0.82), LIGHT_ON])
	parts.append([Cel.box(Vector3(0.12, 0.3, 0.12)), _at(0.0, -0.05, 0.0), TRIM])
	return parts
