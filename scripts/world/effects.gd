class_name Effects
extends Node3D

## Blasts and sparks where shots hit, from the match's impacted signal, in
## flat ink style: a lumpy outlined ball with a ring and a few chunks thrown
## out for a blast, a small burst for a hit. The nodes are made once and
## reused. Sniper shots draw a beam from the muzzle to where the shot is,
## which thins away once it's gone. Only for looks.

const SHADER := preload("res://shaders/explosion.gdshader")
const BLAST_TIME := 0.6
const SPARK_TIME := 0.1
const POOL := 12
const CHUNKS := 4
const GRAVITY := 20.0
const BEAMS := 6
const BEAM_TIME := 0.35
const BEAM_WIDTH := 0.09
const BEAM_COLOUR := WeaponModels.SNIPER_GLOW

var _blasts: Array[Blast] = []
var _sparks: Array[Blast] = []
var _next_blast := 0
var _next_spark := 0
var _beams: Array[Beam] = []
var _next_beam := 0
var _game: Match


class Blast:
	var root: Node3D
	var ball: MeshInstance3D
	var ring: MeshInstance3D
	var chunks: Array[MeshInstance3D] = []
	var throws: Array[Vector3] = []
	var radius := 1.0
	var time := -1.0


class Beam:
	var view: MeshInstance3D
	var start := Vector3.ZERO
	var end := Vector3.ZERO
	## The shot it follows, while it flies.
	var shot: Projectile
	## Seconds since the shot was gone, -1 while it flies or unused.
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
	# A box 1 m long along -z from its origin, stretched to each beam.
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(1.0, 1.0, 1.0)
	var beam_material := Cel.glow(BEAM_COLOUR)
	for k in BEAMS:
		var beam := Beam.new()
		beam.view = MeshInstance3D.new()
		beam.view.mesh = beam_mesh
		beam.view.material_override = beam_material
		beam.view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.view.visible = false
		add_child(beam.view)
		_beams.append(beam)


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
	_game = game
	game.impacted.connect(_on_impacted)
	game.fired.connect(_on_fired)
	game.shield_hit.connect(_on_shield_hit)


func _on_shield_hit(victim_id: int, _amount: float, _from: Vector3) -> void:
	var victim := _game.soldier(victim_id)
	if victim != null:
		victim.body.flash_shield()


func _on_fired(_soldier_id: int, weapon_slot: int) -> void:
	if weapon_slot != Weapon.SNIPER or _game.projectiles.is_empty():
		return
	# The match adds the shot before it says it fired.
	var shot: Projectile = _game.projectiles.back()
	var beam := _beams[_next_beam]
	_next_beam = (_next_beam + 1) % BEAMS
	beam.shot = shot
	beam.start = shot.position + shot.muzzle_offset
	beam.end = shot.position
	beam.time = -1.0
	_pose_beam(beam, 0.0)


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
	for beam in _beams:
		if beam.shot != null or beam.time >= 0.0:
			_pose_beam(beam, delta)
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


## Follows the shot while it flies, then thins away along its whole length.
func _pose_beam(beam: Beam, delta: float) -> void:
	if beam.shot != null:
		beam.end = beam.shot.position
		if _game == null or not _game.projectiles.has(beam.shot):
			beam.shot = null
			beam.time = 0.0
	else:
		beam.time += delta
	var life := maxf(beam.time, 0.0) / BEAM_TIME
	var length := beam.start.distance_to(beam.end)
	if life >= 1.0:
		beam.time = -1.0
	beam.view.visible = life < 1.0 and length >= 0.05
	if not beam.view.visible:
		return
	var dir := (beam.end - beam.start) / length
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var width := BEAM_WIDTH * (1.0 - life)
	var basis := Basis.looking_at(dir, up).scaled_local(Vector3(width, width, length))
	beam.view.global_transform = Transform3D(basis, (beam.start + beam.end) * 0.5)
