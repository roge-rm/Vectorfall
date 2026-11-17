class_name Effects
extends Node3D

## Blasts and sparks where shots hit, from the match's impacted signal. The
## nodes are made once and reused. Only for looks.

const SHADER := preload("res://shaders/explosion.gdshader")
const BLAST_TIME := 0.55
const SPARK_TIME := 0.09
const POOL := 12

var _blasts: Array[Blast] = []
var _sparks: Array[Blast] = []
var _next_blast := 0
var _next_spark := 0


class Blast:
	var root: Node3D
	var ball: MeshInstance3D
	var ring: MeshInstance3D
	var radius := 1.0
	var time := -1.0


func _init() -> void:
	name = "Effects"
	var material := ShaderMaterial.new()
	material.shader = SHADER
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = 1.0
	ball_mesh.height = 2.0
	ball_mesh.radial_segments = 16
	ball_mesh.rings = 8
	ball_mesh.material = material
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.82
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 4
	ring_mesh.material = material
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.5
	spark_mesh.height = 1.0
	spark_mesh.radial_segments = 6
	spark_mesh.rings = 3
	spark_mesh.material = Cel.glow(Color(1.0, 0.92, 0.5))
	for k in POOL:
		_blasts.append(_make(ball_mesh, ring_mesh))
		_sparks.append(_make(spark_mesh, null))


func _make(ball_mesh: Mesh, ring_mesh: Mesh) -> Blast:
	var blast := Blast.new()
	blast.root = Node3D.new()
	blast.root.visible = false
	add_child(blast.root)
	blast.ball = MeshInstance3D.new()
	blast.ball.mesh = ball_mesh
	blast.ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blast.root.add_child(blast.ball)
	if ring_mesh != null:
		blast.ring = MeshInstance3D.new()
		blast.ring.mesh = ring_mesh
		blast.ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		blast.root.add_child(blast.ring)
	return blast


func watch(game: Match) -> void:
	game.impacted.connect(_on_impacted)


func _on_impacted(weapon_slot: int, at: Vector3, normal: Vector3) -> void:
	var weapon := Weapon.all[weapon_slot]
	if weapon.splash_radius > 0.0:
		blast(at, normal, weapon.splash_radius)
	else:
		var spark := _sparks[_next_spark]
		_next_spark = (_next_spark + 1) % POOL
		_start(spark, at, normal, 0.35)


## A blast of a given radius on a surface with this normal.
func blast(at: Vector3, normal: Vector3, radius: float) -> void:
	var made := _blasts[_next_blast]
	_next_blast = (_next_blast + 1) % POOL
	_start(made, at, normal, radius)


func _start(made: Blast, at: Vector3, normal: Vector3, radius: float) -> void:
	var up := normal if normal.length() > 0.5 else Vector3.UP
	made.root.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, up.normalized())), at)
	made.radius = radius
	made.time = 0.0
	made.root.visible = true
	# Sparks have no ring and are sized in _process().
	if made.ring != null:
		_pose(made, 0.0)


func _process(delta: float) -> void:
	for made in _blasts:
		if made.time >= 0.0:
			made.time += delta
			_pose(made, made.time / BLAST_TIME)
	for made in _sparks:
		if made.time >= 0.0:
			made.time += delta
			var life := made.time / SPARK_TIME
			made.root.visible = life < 1.0
			made.ball.scale = Vector3.ONE * made.radius * (1.0 - life * 0.5)
			if life >= 1.0:
				made.time = -1.0


## Grows fast then slows: the ball to most of the blast radius, the ring
## flat along the surface past it.
func _pose(made: Blast, life: float) -> void:
	if life >= 1.0:
		made.root.visible = false
		made.time = -1.0
		return
	var grow := 1.0 - pow(1.0 - minf(life * 1.6, 1.0), 3.0)
	made.ball.scale = Vector3.ONE * made.radius * lerpf(0.15, 0.6, grow)
	made.ring.scale = Vector3.ONE * made.radius * lerpf(0.2, 1.1, 1.0 - pow(1.0 - life, 2.0))
	made.ball.set_instance_shader_parameter("life", life)
	made.ring.set_instance_shader_parameter("life", life)
