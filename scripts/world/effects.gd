class_name Effects
extends Node3D

## Blasts and sparks where shots hit, from the match's impacted signal, in
## flat ink style: a lumpy outlined ball with a ring and a few chunks thrown
## out for a blast, a small burst for a hit. The nodes are made once and
## reused. Only for looks.

const SHADER := preload("res://shaders/explosion.gdshader")
const BLAST_TIME := 0.6
const SPARK_TIME := 0.1
const POOL := 12
const CHUNKS := 4
const GRAVITY := 20.0

var _blasts: Array[Blast] = []
var _sparks: Array[Blast] = []
var _next_blast := 0
var _next_spark := 0


class Blast:
	var root: Node3D
	var ball: MeshInstance3D
	var ring: MeshInstance3D
	var chunks: Array[MeshInstance3D] = []
	var throws: Array[Vector3] = []
	var radius := 1.0
	var time := -1.0


func _init() -> void:
	name = "Effects"
	var material := ShaderMaterial.new()
	material.shader = SHADER
	if Cel.outlines_on():
		material.next_pass = Cel.effect_outline()
	var ball_mesh := lumpy_ball(14, 7, 0.5, 3)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.86
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 20
	ring_mesh.ring_segments = 4
	var spark_mesh := lumpy_ball(8, 4, 0.9, 5)
	var chunk_mesh := Cel.box(Vector3(0.3, 0.26, 0.34))
	var chunk_material := Cel.glow(Color(0.12, 0.09, 0.07))
	var spark_material := Cel.glow(Color(1.0, 0.92, 0.5))
	for k in POOL:
		var blast := _make(ball_mesh, material)
		blast.ring = MeshInstance3D.new()
		blast.ring.mesh = ring_mesh
		blast.ring.material_override = material
		blast.ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		blast.root.add_child(blast.ring)
		for c in CHUNKS:
			var chunk := MeshInstance3D.new()
			chunk.mesh = chunk_mesh
			chunk.material_override = chunk_material
			chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			blast.root.add_child(chunk)
			blast.chunks.append(chunk)
			# Thrown up and out, the same way each time.
			var angle := c * TAU / CHUNKS + k * 0.7
			blast.throws.append(Vector3(cos(angle) * 0.9, 1.5 + 0.35 * (c % 2), sin(angle) * 0.9))
		_blasts.append(blast)
		_sparks.append(_make(spark_mesh, spark_material))


func _make(mesh: Mesh, material: Material) -> Blast:
	var blast := Blast.new()
	blast.root = Node3D.new()
	blast.root.visible = false
	add_child(blast.root)
	blast.ball = MeshInstance3D.new()
	blast.ball.mesh = mesh
	blast.ball.material_override = material
	blast.ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blast.root.add_child(blast.ball)
	return blast


## A ball with lumps pushed out of it, radius 1 before the lumps, with
## outline normals. spikes over 1 makes a sharper burst.
static func lumpy_ball(sides: int, rings: int, lumps: float, spikes: float) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = sides
	sphere.rings = rings
	var arrays := sphere.get_mesh_arrays()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		var p := points[index]
		var key := Vector3i((p * 100.0).round())
		var bump := fposmod(sin(key.x * 12.99 + key.y * 78.23 + key.z * 37.72) * 437.58, 1.0)
		tool.add_vertex(p * (1.0 + lumps * pow(bump, spikes)))
	tool.generate_normals()
	return Cel.hull_mesh(tool.commit())


func watch(game: Match) -> void:
	game.impacted.connect(_on_impacted)


func _on_impacted(weapon_slot: int, at: Vector3, normal: Vector3) -> void:
	var weapon := Weapon.all[weapon_slot]
	if weapon.splash_radius > 0.0:
		blast(at, normal, weapon.splash_radius)
	else:
		var spark := _sparks[_next_spark]
		_next_spark = (_next_spark + 1) % POOL
		_start(spark, at, normal, 0.22)


## A blast of a given radius on a surface with this normal.
func blast(at: Vector3, normal: Vector3, radius: float) -> void:
	var made := _blasts[_next_blast]
	_next_blast = (_next_blast + 1) % POOL
	_start(made, at, normal, radius)


func _start(made: Blast, at: Vector3, normal: Vector3, radius: float) -> void:
	var up := normal if normal.length() > 0.5 else Vector3.UP
	made.root.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, up.normalized())), at)
	made.root.rotate_object_local(Vector3.UP, randf() * TAU)
	made.radius = radius
	made.time = 0.0
	made.root.visible = true
	if made.ring != null:
		pose_blast(made, 0.0)


func _process(delta: float) -> void:
	for made in _blasts:
		if made.time >= 0.0:
			made.time += delta
			pose_blast(made, made.time / BLAST_TIME)
	for made in _sparks:
		if made.time >= 0.0:
			made.time += delta
			var life := made.time / SPARK_TIME
			made.root.visible = life < 1.0
			made.ball.scale = Vector3.ONE * made.radius * (0.6 + life * 0.6)
			if life >= 1.0:
				made.time = -1.0


## Grows fast then slows and shrinks away at the end: the ball to about half
## the blast radius and up off the ground, the ring flat along the surface
## past it, the chunks flying out and falling.
func pose_blast(made: Blast, life: float) -> void:
	if life >= 1.0:
		made.root.visible = false
		made.time = -1.0
		return
	var grow := 1.0 - pow(1.0 - minf(life * 1.8, 1.0), 3.0)
	var shrink := 1.0 - smoothstep(0.7, 1.0, life)
	made.ball.scale = Vector3.ONE * made.radius * lerpf(0.12, 0.42, grow) * shrink
	made.ball.position.y = made.radius * 0.2 * grow
	made.ring.scale = Vector3(1.0, 0.25, 1.0) * made.radius * lerpf(0.2, 1.05, 1.0 - pow(1.0 - life, 2.0)) * (1.0 - smoothstep(0.5, 1.0, life))
	made.ball.set_instance_shader_parameter("life", life)
	made.ring.set_instance_shader_parameter("life", minf(life * 1.5, 1.0))
	var t := life * BLAST_TIME
	for c in made.chunks.size():
		var throw := made.throws[c] * made.radius * 1.4
		made.chunks[c].position = Vector3(throw.x * t, throw.y * t - 0.5 * GRAVITY * t * t, throw.z * t)
		made.chunks[c].rotation = Vector3(t * 9.0, t * 7.0 + c, 0.0)
		made.chunks[c].visible = life < 0.85
