extends Node

## The style test scene: a soldier of each armour for each team, a base piece
## with its flag, a slope of ground and a fight (a disc in flight, a blast, a
## jet, chaingun fire and a skier). Takes pictures of it in each palette, a
## close-up of the soldiers, and one from the main scene, then quits. It needs
## a screen:
##   DISPLAY=:0 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/style_shot.tscn
## Saves style-desert.png, style-highland.png, style-soldiers.png and
## style-ingame.png in /srv/downloads/temp/debug/vectorfall.

const FOLDER := "/srv/downloads/temp/debug/vectorfall"

var _root: Node3D
var _camera: Camera3D
var _noise := FastNoiseLite.new()
var _effects: Effects
var _soldiers: Array[Soldier] = []


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_noise.seed = 3
	_noise.frequency = 0.05
	_camera = Camera3D.new()
	_camera.fov = 62.0
	add_child(_camera)
	_camera.make_current()
	for palette: Palette in [Palette.desert(), Palette.highland()]:
		# The scene's ground is lower than the test map's, so move the sand
		# and snow lines to fit it.
		palette.low_height = 0.3
		palette.high_height = 9.0
		await _build(palette)
		_camera.look_at_from_position(Vector3(0.0, 3.2, 9.0), Vector3(1.0, 2.6, -12.0))
		await _save("style-%s.png" % ("desert" if palette.title.contains("desert") else "highland"))
		if palette.title.contains("desert"):
			_camera.look_at_from_position(Vector3(0.0, 1.5, 5.2), Vector3(0.0, 1.1, -1.0))
			await _save("style-soldiers.png")
		_root.queue_free()
		await get_tree().process_frame

	# The main scene, looking down the valley from in front of the base with
	# the bots playing.
	_camera.queue_free()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var map: TestMap = main.map
	var x := map.base_x(0) + 24.0
	main.player.global_position = Vector3(x, map.height_at(x, 0.0) + 0.5, 0.0)
	main.input.source.yaw = -PI * 0.5 + 0.15
	for i in 240:
		await get_tree().physics_frame
	main.input.source.pitch = -0.08
	await _save("style-ingame.png")
	get_tree().quit()


func _save(file: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(FOLDER)
	get_viewport().get_texture().get_image().save_png(FOLDER + "/" + file)
	print("Saved ", FOLDER + "/" + file)


func _height(x: float, z: float) -> float:
	return maxf(0.0, x - 6.0) * 0.42 + maxf(0.0, -z - 30.0) * 0.3 + _noise.get_noise_2d(x, z) * 0.8


func _build(palette: Palette) -> void:
	_soldiers.clear()
	_root = Node3D.new()
	add_child(_root)
	_root.add_child(Atmosphere.new(palette))
	_build_ground()
	_build_base(palette)
	_build_fight()
	# Let the poses settle and lay the shadows.
	for i in 40:
		await get_tree().physics_frame
	for soldier in _soldiers:
		soldier.blob.follow(soldier)
		if not soldier.grounded:
			soldier.blob.visible = false


func _build_ground() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cell := 1.5
	var n := 100
	var start := Vector2(-70.0, -130.0)
	for j in n:
		for i in n:
			for c: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				var p := start + (Vector2(i, j) + c) * cell
				var normal := Vector3(_height(p.x - 0.5, p.y) - _height(p.x + 0.5, p.y), 1.0, _height(p.x, p.y - 0.5) - _height(p.x, p.y + 0.5)).normalized()
				var patch := _noise.get_noise_2d(p.x * 2.0 + 300.0, p.y * 2.0)
				tool.set_color(Color(normal.y, patch * 0.5 + 0.5, 0.0))
				tool.set_normal(normal)
				tool.add_vertex(Vector3(p.x, _height(p.x, p.y), p.y))
	var mesh := tool.commit()
	var ground := StaticBody3D.new()
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = Cel.ground_material()
	ground.add_child(view)
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	ground.add_child(shape)
	_root.add_child(ground)


func _box(size: Vector3, at: Vector3, material: Material, turn := 0.0) -> void:
	var view := MeshInstance3D.new()
	view.mesh = Cel.box(size)
	view.material_override = material
	view.position = at
	view.rotation.y = turn
	_root.add_child(view)


## A corner of the orange base: deck, ramp, tower and roof in the dark team
## colour, the flag on its pad, and rocks.
func _build_base(palette: Palette) -> void:
	var orange := Soldier.TEAM_COLOURS[0]
	var deck := Cel.material(palette.structure)
	var wall := Cel.team_material(orange.lerp(palette.structure, 0.35).darkened(0.3))
	_box(Vector3(16.0, 2.0, 14.0), Vector3(-18.0, 1.0, -22.0), deck)
	_box(Vector3(3.5, 12.0, 3.5), Vector3(-22.0, 8.0, -26.0), wall)
	_box(Vector3(8.0, 0.8, 8.0), Vector3(-22.0, 14.4, -26.0), deck)
	_box(Vector3(2.5, 3.5, 2.5), Vector3(-23.0, 3.75, -17.0), wall)
	var pad := MeshInstance3D.new()
	pad.mesh = Cel.cylinder(2.0, 2.4, 0.5, 12)
	pad.material_override = Cel.team_material(orange.darkened(0.2))
	pad.position = Vector3(-16.0, 2.25, -20.0)
	_root.add_child(pad)
	var flag := Flag.new()
	flag.team = 0
	_root.add_child(flag)
	flag.position = Vector3(-16.0, 2.5 + Flag.POLE * 0.5, -20.0)
	flag.rotation.y = 0.35
	var rock := Cel.material(palette.boulder)
	for at: Vector3 in [Vector3(26.0, 0.0, -18.0), Vector3(18.0, 0.0, -36.0), Vector3(-34.0, 0.0, -50.0)]:
		var view := MeshInstance3D.new()
		view.mesh = Cel.box(Vector3(2.6, 2.2, 3.0))
		view.material_override = rock
		view.position = Vector3(at.x, _height(at.x, at.z) + 0.6, at.z)
		view.rotation = Vector3(0.3, at.x, 0.2)
		_root.add_child(view)


func _soldier(team: int, armour: SoldierBody.Armour, at: Vector3, yaw: float) -> Soldier:
	var soldier := Soldier.new()
	soldier.team = team
	_root.add_child(soldier)
	soldier.body.set_look(team, armour)
	soldier.position = Vector3(at.x, _height(at.x, at.z) if at.y == 0.0 else at.y, at.z)
	soldier.yaw = yaw
	soldier.rotation.y = yaw
	soldier.grounded = true
	_soldiers.append(soldier)
	return soldier


func _build_fight() -> void:
	# The line-up facing the camera: orange light, medium and heavy on the
	# left, blue on the right, turned a little towards each other.
	var armours := [SoldierBody.Armour.LIGHT, SoldierBody.Armour.MEDIUM, SoldierBody.Armour.HEAVY]
	for k in 3:
		_soldier(0, armours[k], Vector3(-3.6 + k * 1.15, 0.0, -1.0 - k * 0.2), PI + 0.35)
		var blue := _soldier(1, armours[k], Vector3(1.4 + k * 1.15, 0.0, -1.0 - k * 0.2), PI - 0.35)
		blue.weapon = Weapon.CHAINGUN

	# Behind them: orange running in with a disc launcher, one jetting over
	# the deck, blue skiing down the slope and one firing the chaingun.
	var runner := _soldier(0, SoldierBody.Armour.MEDIUM, Vector3(-5.0, 0.0, -11.0), -PI * 0.5 + 0.35)
	runner.velocity = Vector3(5.0, 0.0, -2.0)
	var jetter := _soldier(0, SoldierBody.Armour.LIGHT, Vector3(-8.0, 5.5, -18.0), -PI * 0.5 + 0.6)
	jetter.grounded = false
	jetter.jetting = true
	jetter.pitch = -0.25
	var skier := _soldier(1, SoldierBody.Armour.LIGHT, Vector3(12.0, 0.0, -15.0), PI * 0.5 - 0.2)
	skier.skiing = true
	skier.velocity = Vector3(-24.0, 0.0, 0.0)
	var gunner := _soldier(1, SoldierBody.Armour.HEAVY, Vector3(7.0, 0.0, -9.0), PI * 0.5 + 0.3)
	gunner.weapon = Weapon.CHAINGUN
	gunner.spin = 1.0
	gunner.pitch = 0.12

	# A disc from the runner with its trail, drawn the way ProjectileView does.
	var from := runner.position + Vector3(0.3, 1.3, -0.3)
	var to := Vector3(1.5, 1.7, -11.5)
	var along := (to - from).normalized()
	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 0.2
	disc_mesh.bottom_radius = 0.2
	disc_mesh.height = 0.06
	disc_mesh.radial_segments = 12
	disc_mesh.rings = 1
	disc.mesh = disc_mesh
	disc.material_override = Cel.glow(WeaponModels.DISC_GLOW)
	disc.position = to
	disc.rotation = Vector3(0.1, 0.0, 0.15)
	_root.add_child(disc)
	var trail := MeshInstance3D.new()
	trail.mesh = Cel.cylinder(0.0, 0.12, 1.0, 6)
	trail.material_override = Cel.glow(Color(0.9, 1.0, 1.0))
	trail.basis = Basis(Quaternion(Vector3.UP, along)).scaled_local(Vector3(1.0, 4.0, 1.0))
	trail.position = to - along * 2.1
	_root.add_child(trail)

	# Chaingun rounds from the gunner towards the jetter, and a hit.
	var aim := (jetter.position + Vector3(0.0, 1.2, 0.0) - gunner.position - Vector3(-0.5, 1.4, -0.3)).normalized()
	for k in 3:
		var round_view := MeshInstance3D.new()
		var tracer := BoxMesh.new()
		tracer.size = Vector3(0.07, 0.07, 3.0)
		round_view.mesh = tracer
		round_view.material_override = Cel.glow(Color(1.0, 0.9, 0.45))
		round_view.position = gunner.position + Vector3(-0.5, 1.4, -0.3) + aim * (2.5 + k * 4.5)
		round_view.basis = Basis.looking_at(aim, Vector3.UP)
		_root.add_child(round_view)

	_effects = Effects.new()
	_root.add_child(_effects)
	var at := Vector3(17.0, _height(17.0, -27.0), -27.0)
	_effects.blast(at, Vector3.UP, Weapon.all[Weapon.DISC].splash_radius)
	_effects.set_process(false)
	_effects.pose_blast(_effects._blasts[0], 0.3)
	_effects._on_impacted(Weapon.CHAINGUN, jetter.position + Vector3(0.8, 0.4, 1.4), Vector3.UP)
	_effects._sparks[0].ball.scale = Vector3.ONE * 0.35
