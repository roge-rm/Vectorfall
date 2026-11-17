class_name ProjectileView
extends Node3D

## Draws every shot in flight with one MultiMesh per weapon, so hundreds of
## chaingun rounds cost a draw call. It only reads the match.

const MAX_SHOTS := 512
## Length of a chaingun tracer in metres.
const TRACER_LENGTH := 3.5

var game: Match
var _views: Array[MultiMeshInstance3D] = []


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
	tracer.size = Vector3(0.06, 0.06, 1.0)
	tracer.material = Cel.glow(Color(1.0, 0.9, 0.45))
	for mesh: Mesh in [disc, tracer]:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = MAX_SHOTS
		multi.visible_instance_count = 0
		var view := MultiMeshInstance3D.new()
		view.multimesh = multi
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Shots fly across the whole map, so don't let culling hide them.
		view.custom_aabb = AABB(Vector3(-5000, -5000, -5000), Vector3(10000, 10000, 10000))
		add_child(view)
		_views.append(view)


func _process(_delta: float) -> void:
	if game == null:
		return
	var counts := [0, 0]
	for shot in game.projectiles:
		var kind := 0 if shot.weapon == Weapon.DISC else 1
		var k: int = counts[kind]
		if k >= MAX_SHOTS:
			continue
		counts[kind] = k + 1
		var at := shot.visual_position()
		var dir := shot.velocity.normalized() if shot.velocity.length() > 0.01 else Vector3.FORWARD
		var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
		var basis := Basis.looking_at(dir, up)
		if kind == 0:
			# Lies flat along its path, spinning.
			basis = basis * Basis(Vector3.UP, shot.age * 25.0)
		else:
			var length := minf(TRACER_LENGTH, shot.age * shot.velocity.length())
			basis = basis.scaled_local(Vector3(1.0, 1.0, maxf(length, 0.2)))
			at -= dir * length * 0.5
		_views[kind].multimesh.set_instance_transform(k, Transform3D(basis, at))
	for kind in 2:
		_views[kind].multimesh.visible_instance_count = counts[kind]
