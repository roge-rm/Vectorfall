extends Node

## Renders one small scene in four comic ink styles for Dan to pick from, and
## quits. It needs a screen:
##   DISPLAY=:0 ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/mockup_shot.tscn
## Saves mockup-a.png to mockup-d.png in /srv/downloads/temp/debug/vectorfall.
## Each style is only a set of shader and colour settings on the same scene.

const FOLDER := "/srv/downloads/temp/debug/vectorfall"
const INK := preload("res://shaders/ink.gdshader")
const INK_OUTLINE := preload("res://shaders/ink_outline.gdshader")
const INK_SKY := preload("res://shaders/ink_sky.gdshader")
const BLAST := preload("res://shaders/explosion.gdshader")

## A: gritty graphic novel. B: clean line. C: pulp halftone. D: brush and
## spot black.
const STYLES := {
	"a": {
		"ink": Color(0.07, 0.05, 0.04), "shadow_style": 1, "hatch_spacing": 6.0, "hatch_width": 0.32,
		"deep_edge": -0.15, "mid_ink": 1.0, "saturation": 0.3, "grit": 0.16, "paper": Color(0.98, 0.93, 0.84),
		"shade_mid": 0.5, "shade_dark": 0.18, "ambient": Color(0.62, 0.56, 0.5), "ambient_energy": 0.5,
		"sun_colour": Color(1.0, 0.9, 0.74),
		"width": 0.0055, "shadow_weight": 0.9, "brush": 0.15,
		"zenith": Color(0.5, 0.47, 0.42), "horizon": Color(0.86, 0.77, 0.6), "bands": 0.0, "dots": 0.0,
		"fog": 0.006,
		"grass": Color(0.66, 0.58, 0.4), "grass_dark": Color(0.6, 0.52, 0.36), "dirt": Color(0.62, 0.48, 0.34),
		"rock": Color(0.48, 0.44, 0.4), "concrete": Color(0.66, 0.63, 0.58),
		"flame": Color(1.0, 0.7, 0.25), "blast_core": Color(1.0, 0.95, 0.75), "blast_edge": Color(0.95, 0.45, 0.12),
	},
	"b": {
		"ink": Color(0.08, 0.09, 0.14), "shadow_style": 0, "hatch_spacing": 6.0, "hatch_width": 0.35,
		"deep_edge": -0.3, "saturation": 1.15, "grit": 0.0, "paper": Color(1.0, 1.0, 1.0),
		"shade_mid": 0.62, "shade_dark": 0.3, "ambient": Color(0.6, 0.68, 0.85), "ambient_energy": 0.55,
		"sun_colour": Color(1.0, 0.98, 0.92),
		"width": 0.003, "shadow_weight": 0.0, "brush": 0.0,
		"zenith": Color(0.22, 0.52, 0.92), "horizon": Color(0.78, 0.92, 1.0), "bands": 0.0, "dots": 0.0,
		"fog": 0.002,
		"grass": Color(0.5, 0.78, 0.32), "grass_dark": Color(0.42, 0.7, 0.3), "dirt": Color(0.86, 0.74, 0.5),
		"rock": Color(0.68, 0.66, 0.64), "concrete": Color(0.92, 0.9, 0.84),
		"flame": Color(1.0, 0.82, 0.3), "blast_core": Color(1.0, 1.0, 0.85), "blast_edge": Color(1.0, 0.62, 0.15),
	},
	"c": {
		"ink": Color(0.12, 0.05, 0.14), "shadow_style": 2, "hatch_spacing": 6.0, "hatch_width": 0.35,
		"deep_edge": -0.3, "saturation": 1.45, "grit": 0.06, "paper": Color(1.0, 0.95, 0.84),
		"mid_ink": 0.32,
		"shade_mid": 0.6, "shade_dark": 0.3, "ambient": Color(0.62, 0.6, 0.75), "ambient_energy": 0.55,
		"sun_colour": Color(1.0, 0.95, 0.85),
		"width": 0.0045, "shadow_weight": 0.3, "brush": 0.0,
		"zenith": Color(0.0, 0.28, 0.95), "horizon": Color(1.0, 0.86, 0.32), "bands": 3.0, "dots": 0.75,
		"dot_colour": Color(1.0, 0.42, 0.25),
		"fog": 0.0025,
		"grass": Color(0.35, 0.72, 0.25), "grass_dark": Color(0.28, 0.62, 0.22), "dirt": Color(0.95, 0.75, 0.2),
		"rock": Color(0.78, 0.25, 0.2), "concrete": Color(0.9, 0.88, 0.8),
		"flame": Color(1.0, 0.85, 0.1), "blast_core": Color(1.0, 0.95, 0.3), "blast_edge": Color(0.95, 0.15, 0.1),
	},
	"d": {
		"ink": Color(0.03, 0.03, 0.04), "shadow_style": 3, "sun": Vector3(0.75, 0.6, 0.25), "hatch_spacing": 6.0, "hatch_width": 0.35,
		"deep_edge": 0.3, "saturation": 0.12, "grit": 0.05, "paper": Color(1.0, 0.97, 0.9),
		"shade_mid": 0.7, "shade_dark": 0.0, "ambient": Color(0.75, 0.72, 0.68), "ambient_energy": 0.45,
		"sun_colour": Color(1.0, 0.97, 0.9),
		"width": 0.0055, "shadow_weight": 1.6, "brush": 0.4,
		"zenith": Color(0.82, 0.8, 0.74), "horizon": Color(0.96, 0.93, 0.85), "bands": 2.0, "dots": 0.0,
		"fog": 0.003,
		"grass": Color(0.82, 0.8, 0.74), "grass_dark": Color(0.76, 0.74, 0.68), "dirt": Color(0.7, 0.68, 0.62),
		"rock": Color(0.55, 0.54, 0.52), "concrete": Color(0.9, 0.88, 0.82),
		"flame": Color(1.0, 0.92, 0.6), "blast_core": Color(1.0, 0.98, 0.9), "blast_edge": Color(0.98, 0.78, 0.25),
	},
}

## Towards the sun, unless a style has its own: from behind the camera and to
## the right, so faces towards the camera are in the middle band and the left
## sides in shadow.
const SUN := Vector3(0.4, 0.75, 0.5)

## Parameters every cel material gets from the style.
const CEL_KEYS := ["ink", "shadow_style", "hatch_spacing", "hatch_width", "deep_edge", "saturation", "grit", "paper", "mid_ink", "shade_mid", "shade_dark", "ambient", "ambient_energy", "sun_colour"]

var _noise := FastNoiseLite.new()
var _ground: ShaderMaterial
var _concrete: ShaderMaterial
var _rock: ShaderMaterial
var _sky: ShaderMaterial
var _environment: Environment
var _blast_material: ShaderMaterial
var _effect_outline: ShaderMaterial
var _flame: StandardMaterial3D
var _sun_direction := Vector3.ZERO
var _sun: DirectionalLight3D
var _soldiers: Array[Soldier] = []


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_noise.seed = 3
	_noise.frequency = 0.05
	_build_world()
	_build_fight()
	var camera := Camera3D.new()
	camera.fov = 62.0
	add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 2.4, 0.5), Vector3(1.0, 2.6, -14.0))
	camera.make_current()
	# Let the poses settle, and lay the shadows.
	for i in 40:
		await get_tree().physics_frame
	for soldier in _soldiers:
		soldier.blob.follow(soldier)
		if not soldier.grounded:
			soldier.blob.visible = false
	for key: String in ["a", "b", "c", "d"]:
		_apply(STYLES[key])
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(FOLDER)
		var path := "%s/mockup-%s.png" % [FOLDER, key]
		get_viewport().get_texture().get_image().save_png(path)
		print("Saved ", path)
	get_tree().quit()


func _height(x: float, z: float) -> float:
	return maxf(0.0, x - 4.0) * 0.42 + maxf(0.0, -z - 34.0) * 0.3 + _noise.get_noise_2d(x, z) * 0.8


func _build_world() -> void:
	var atmosphere := Atmosphere.new()
	add_child(atmosphere)
	_environment = atmosphere.environment
	_sun = atmosphere.sun
	_sky = ShaderMaterial.new()
	_sky.shader = INK_SKY
	_environment.sky.sky_material = _sky

	# The ground: flat in front, a slope rising to the right and behind.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cell := 1.5
	var n := 90
	var start := Vector2(-60.0, -110.0)
	for j in n:
		for i in n:
			var corners: Array[Vector2] = []
			for c: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				corners.append(start + (Vector2(i, j) + c) * cell)
			for p in corners:
				var normal := Vector3(_height(p.x - 0.5, p.y) - _height(p.x + 0.5, p.y), 1.0, _height(p.x, p.y - 0.5) - _height(p.x, p.y + 0.5)).normalized()
				var patch := _noise.get_noise_2d(p.x * 2.0 + 300.0, p.y * 2.0)
				tool.set_color(Color(normal.y, patch * 0.5 + 0.5, 0.0))
				tool.set_normal(normal)
				tool.add_vertex(Vector3(p.x, _height(p.x, p.y), p.y))
	var mesh := tool.commit()
	_ground = ShaderMaterial.new()
	_ground.shader = INK
	_ground.set_shader_parameter("ground", true)
	_ground.set_shader_parameter("rim_amount", 0.0)
	var ground := StaticBody3D.new()
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = _ground
	ground.add_child(view)
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	ground.add_child(shape)
	add_child(ground)

	# A piece of the orange base: a deck, a tower with a roof and a pillar,
	# and the flag on its stand.
	_concrete = Cel.material(Color(0.7, 0.7, 0.69))
	_rock = Cel.material(Color(0.5, 0.48, 0.46))
	var orange := Palette.team(0)
	_box(Vector3(16.0, 2.0, 14.0), Vector3(-16.0, 1.0, -24.0), _concrete)
	_box(Vector3(3.5, 12.0, 3.5), Vector3(-20.0, 8.0, -28.0), Cel.material(orange))
	_box(Vector3(8.0, 0.8, 8.0), Vector3(-20.0, 14.4, -28.0), _concrete)
	_box(Vector3(2.5, 3.5, 2.5), Vector3(-9.5, 3.75, -18.5), Cel.material(orange))
	var pad := MeshInstance3D.new()
	pad.mesh = Cel.cylinder(2.0, 2.4, 0.5, 12)
	pad.material_override = Cel.material(orange.darkened(0.2))
	pad.position = Vector3(-14.0, 2.25, -22.0)
	add_child(pad)
	var flag := Flag.new()
	flag.team = 0
	add_child(flag)
	flag.position = Vector3(-14.0, 2.5 + Flag.POLE * 0.5, -22.0)
	# Cloth to the left, clear of the pillar.
	flag.rotation.y = PI - 0.2
	# Rocks on the slope.
	for at: Vector3 in [Vector3(26.0, 0.0, -18.0), Vector3(22.0, 0.0, -8.0), Vector3(-30.0, 0.0, -50.0)]:
		var rock := MeshInstance3D.new()
		rock.mesh = Cel.box(Vector3(2.6, 2.2, 3.0))
		rock.material_override = _rock
		rock.position = Vector3(at.x, _height(at.x, at.z) + 0.6, at.z)
		rock.rotation = Vector3(0.3, at.x, 0.2)
		add_child(rock)


func _box(size: Vector3, at: Vector3, material: Material) -> void:
	var view := MeshInstance3D.new()
	view.mesh = Cel.box(size)
	view.material_override = material
	view.position = at
	add_child(view)


func _soldier(team: int, at: Vector3, yaw: float) -> Soldier:
	var soldier := Soldier.new()
	soldier.team = team
	add_child(soldier)
	soldier.position = at
	soldier.yaw = yaw
	soldier.rotation.y = yaw
	soldier.grounded = true
	_soldiers.append(soldier)
	return soldier


func _build_fight() -> void:
	# Orange: one running in and firing a disc, one jetting over the deck.
	var runner := _soldier(0, Vector3(-3.5, _height(-3.5, -9.0), -9.0), -PI * 0.5 + 0.35)
	runner.velocity = Vector3(5.0, 0.0, -2.0)
	runner.pitch = 0.05
	var jetter := _soldier(0, Vector3(-6.5, 5.5, -17.0), -PI * 0.5 + 0.6)
	jetter.grounded = false
	jetter.jetting = true
	jetter.weapon = Weapon.CHAINGUN
	jetter.pitch = -0.25
	# Blue: one skiing down the slope, one holding with the chaingun.
	var skier := _soldier(1, Vector3(8.0, _height(8.0, -13.0), -13.0), PI * 0.5 - 0.2)
	skier.skiing = true
	skier.velocity = Vector3(-14.0, 0.0, 0.0)
	var gunner := _soldier(1, Vector3(4.5, _height(4.5, -6.5), -6.5), PI * 0.5 + 0.3)
	gunner.weapon = Weapon.CHAINGUN
	gunner.spin = 1.0
	gunner.pitch = 0.12
	for soldier in _soldiers:
		soldier.body.set_process(true)

	_flame = Cel.glow(SoldierBody.FLAME)
	# Effects get an ink line of their own.
	_effect_outline = ShaderMaterial.new()
	_effect_outline.shader = INK_OUTLINE
	_effect_outline.set_shader_parameter("min_distance", 0.5)

	# A disc between them with a tapered trail back to the runner.
	var disc_glow := Cel.glow(WeaponModels.DISC_GLOW)
	var from := runner.position + Vector3(0.3, 1.3, -0.3)
	var to := Vector3(2.4, 1.5, -10.5)
	var disc := MeshInstance3D.new()
	disc.mesh = Cel.cylinder(0.22, 0.22, 0.07, 14)
	disc.material_override = disc_glow
	disc.position = to
	disc.rotation = Vector3(0.15, 0.0, 0.2)
	add_child(disc)
	var trail := MeshInstance3D.new()
	trail.mesh = Cel.cylinder(0.0, 0.16, 1.0, 6)
	trail.material_override = disc_glow
	var along := (to - from).normalized()
	trail.basis = Basis(Quaternion(Vector3.UP, along)).scaled_local(Vector3(0.8, 3.0, 0.8))
	trail.position = to - along * 1.7
	add_child(trail)

	# Chaingun rounds from the blue gunner towards the jetter.
	var tracer := Cel.glow(Color(1.0, 0.9, 0.45))
	for k in 3:
		var start := gunner.position + Vector3(-0.5, 1.4, -0.3)
		var aim := (jetter.position + Vector3(0.0, 1.2, 0.0) - start).normalized()
		var round_view := MeshInstance3D.new()
		round_view.mesh = Cel.box(Vector3(0.06, 0.06, 1.6))
		round_view.material_override = tracer
		round_view.position = start + aim * (1.8 + k * 3.2) + Vector3(0.0, k * 0.1 - 0.1, 0.0)
		round_view.basis = Basis.looking_at(aim, Vector3.UP)
		add_child(round_view)

	# A disc blast on the slope behind the skier.
	_blast_material = ShaderMaterial.new()
	_blast_material.shader = BLAST
	_blast_material.next_pass = _effect_outline
	var at := Vector3(17.0, _height(17.0, -27.0), -27.0)
	var ball := MeshInstance3D.new()
	ball.mesh = _lumpy_ball()
	ball.material_override = _blast_material
	ball.position = at + Vector3(0.0, 1.6, 0.0)
	ball.scale = Vector3.ONE * 2.6
	ball.set_instance_shader_parameter("life", 0.2)
	add_child(ball)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.82
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 4
	ring.mesh = torus
	ring.material_override = _blast_material
	ring.position = at + Vector3(0.0, 0.2, 0.0)
	ring.scale = Vector3(4.0, 1.0, 4.0)
	ring.set_instance_shader_parameter("life", 0.2)
	add_child(ring)
	# Chunks thrown out of it.
	for k in 4:
		var chunk := MeshInstance3D.new()
		chunk.mesh = Cel.box(Vector3(0.35, 0.3, 0.4))
		chunk.material_override = _rock
		chunk.position = at + Vector3(cos(k * 1.7) * 2.5, 2.5 + k * 0.6, sin(k * 1.7) * 2.0)
		chunk.rotation = Vector3(k, k * 2.0, 0.0)
		add_child(chunk)
	# Smoke puffs under the jetter.
	for k in 3:
		var puff := MeshInstance3D.new()
		puff.mesh = Cel.sphere(0.2 + k * 0.12, 0.4 + k * 0.24, 10)
		puff.material_override = Cel.material(Color(0.85, 0.85, 0.85))
		puff.position = jetter.position + Vector3(0.9 + k * 0.9, -0.5 - k * 1.1, 0.3)
		add_child(puff)


func _apply(style: Dictionary) -> void:
	var ink: Color = style["ink"]
	_sun_direction = (style.get("sun", SUN) as Vector3).normalized()
	_sun.basis = Basis.looking_at(-_sun_direction, Vector3.UP)
	# Every cel material moves to the ink shader with the style's settings.
	var materials: Array = Cel._materials.values()
	materials.append(_ground)
	for made: ShaderMaterial in materials:
		made.shader = INK
		made.set_shader_parameter("sun_direction", _sun_direction)
		for key: String in CEL_KEYS:
			made.set_shader_parameter(key, style.get(key, 0.0))
	for key: String in ["grass", "grass_dark", "dirt", "rock"]:
		_ground.set_shader_parameter(key, style[key])
	_concrete.set_shader_parameter("albedo", style["concrete"])
	_rock.set_shader_parameter("albedo", style["rock"])
	for outline: ShaderMaterial in [Cel.outline(), Cel.near_outline(), Cel.figure_outline(), _effect_outline]:
		outline.shader = INK_OUTLINE
		outline.set_shader_parameter("colour", ink)
		outline.set_shader_parameter("sun_direction", _sun_direction)
		outline.set_shader_parameter("shadow_weight", style["shadow_weight"])
		outline.set_shader_parameter("brush", style["brush"])
	Cel.outline().set_shader_parameter("width", style["width"])
	_effect_outline.set_shader_parameter("width", style["width"] * 0.8)
	# Flames, shots and the visor are flat colour with an ink line.
	for key: String in Cel._glows:
		var glow: StandardMaterial3D = Cel._glows[key]
		glow.next_pass = _effect_outline
	_flame.albedo_color = style["flame"]
	_blast_material.set_shader_parameter("core", style["blast_core"])
	_blast_material.set_shader_parameter("edge", style["blast_edge"])

	_sky.set_shader_parameter("zenith", style["zenith"])
	_sky.set_shader_parameter("horizon", style["horizon"])
	_sky.set_shader_parameter("ground", style["grass_dark"])
	_sky.set_shader_parameter("ink", ink)
	_sky.set_shader_parameter("bands", style["bands"])
	_sky.set_shader_parameter("dots", style["dots"])
	_sky.set_shader_parameter("dot_colour", style.get("dot_colour", Color.WHITE))
	_sky.set_shader_parameter("screen_height", float(get_viewport().get_visible_rect().size.y))
	_environment.fog_light_color = style["horizon"]
	_environment.fog_density = style["fog"]


## A ball with lumps pushed out of it, for a blast that reads as a burst.
func _lumpy_ball() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 14
	sphere.rings = 7
	var arrays := sphere.get_mesh_arrays()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for k in points.size():
		var p := points[k]
		var key := Vector3i((p * 100.0).round())
		var lump := 1.0 + 0.5 * fposmod(sin(key.x * 12.99 + key.y * 78.23 + key.z * 37.72) * 437.58, 1.0)
		points[k] = p * lump
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		tool.add_vertex(points[index])
	tool.generate_normals()
	return Cel.hull_mesh(tool.commit())
