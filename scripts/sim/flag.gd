class_name Flag
extends RigidBody3D

## A team's flag. At home it sits on its stand, carried it follows the soldier
## holding it, and dropped it's a physics body that keeps the carrier's
## velocity and tumbles to rest. The match decides which state it's in, only on
## physics ticks, and moves it while it's home or carried.

enum Mode { HOME, CARRIED, DROPPED }

const POLE := 4.0
const CLOTH := Vector2(2.0, 1.2)

var entity_id := 0
var team := 0
var mode := Mode.HOME
var carrier_id := 0
## Seconds until a dropped flag goes home.
var return_in := 0.0
## Where its stand holds it.
var home := Vector3.ZERO

var _beam: MeshInstance3D
var _beam_material: StandardMaterial3D


func _init() -> void:
	collision_layer = 0
	collision_mask = Match.WORLD_LAYER
	mass = 2.0
	continuous_cd = true
	linear_damp = 0.15
	angular_damp = 2.5
	var surface := PhysicsMaterial.new()
	surface.friction = 0.8
	surface.bounce = 0.25
	physics_material_override = surface
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.2
	capsule.height = POLE
	shape.shape = capsule
	add_child(shape)


func _ready() -> void:
	name = "Flag%d" % entity_id
	var colour := Soldier.TEAM_COLOURS[team % Soldier.TEAM_COLOURS.size()]
	# Pole, cloth in the full team colour with a pale band across it, and a
	# ball on top, as one mesh. The band keeps it clear of its own base.
	var cloth_at := Vector3(CLOTH.x * 0.5 + 0.05, POLE * 0.5 - CLOTH.y * 0.5 - 0.1, 0.0)
	var pale := Color(0.96, 0.94, 0.88, 0.0)
	var team_part := Color(1.0, 1.0, 1.0, 1.0)
	var view := MeshInstance3D.new()
	view.name = "Look"
	view.mesh = _look_mesh(cloth_at, pale, team_part)
	view.material_override = Cel.material(Color.WHITE, 1.0, true, true)
	add_child(view)
	Cel.set_team(view, colour)
	# An upright beam of light that stays vertical however the flag lies.
	_beam_material = StandardMaterial3D.new()
	_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_material.disable_fog = true
	_beam_material.albedo_color = Color(colour.r, colour.g, colour.b, 0.2)
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 1.0
	cylinder.radial_segments = 12
	cylinder.rings = 1
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	_beam = MeshInstance3D.new()
	_beam.mesh = cylinder
	_beam.material_override = _beam_material
	_beam.top_level = true
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	_update_beam()


func _process(_delta: float) -> void:
	_update_beam()


static var _look_meshes: Dictionary[String, ArrayMesh] = {}


static func _look_mesh(cloth_at: Vector3, pale: Color, team_part: Color) -> ArrayMesh:
	if not _look_meshes.has("flag"):
		_look_meshes["flag"] = Cel.merged([
			[Cel.cylinder(0.07, 0.1, POLE), Transform3D.IDENTITY, pale],
			[Cel.box(Vector3(CLOTH.x, CLOTH.y, 0.06)), Transform3D(Basis.IDENTITY, cloth_at), team_part],
			[Cel.box(Vector3(CLOTH.x * 0.98, CLOTH.y * 0.22, 0.08)), Transform3D(Basis.IDENTITY, cloth_at), pale],
			[Cel.sphere(0.2, 0.4), Transform3D(Basis.IDENTITY, Vector3(0.0, POLE * 0.5 + 0.1, 0.0)), team_part],
		])
	return _look_meshes["flag"]


## A thin faint beam while it's home, a wide bright one when it's away, so it
## can be found from across the map.
func _update_beam() -> void:
	var away := mode != Mode.HOME
	var radius := 0.9 if away else 0.35
	var height := 400.0 if away else 70.0
	_beam_material.albedo_color.a = 0.4 if away else 0.3
	var base := global_position
	_beam.global_transform = Transform3D(Basis.from_scale(Vector3(radius, height, radius)), base + Vector3.UP * (height * 0.5 - 1.0))


## Where the match holds it to the soldier carrying it: on their back.
func hold_on(who: Soldier) -> void:
	var basis := Basis(Vector3.UP, who.yaw)
	global_transform = Transform3D(basis, who.global_position + Vector3.UP * (POLE * 0.5 - 0.3) + basis * Vector3(0.0, 0.0, 0.45))


func send_home() -> void:
	mode = Mode.HOME
	carrier_id = 0
	return_in = 0.0
	_freeze_at(Transform3D(Basis.IDENTITY, home))


func _freeze_at(where: Transform3D) -> void:
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = where


## Lets go of the flag at the carrier's speed with a bit of random spin from
## the match's numbers.
func drop(velocity: Vector3, spin: Vector3, time: float) -> void:
	mode = Mode.DROPPED
	carrier_id = 0
	return_in = time
	freeze = false
	linear_velocity = velocity
	angular_velocity = spin


func get_state() -> Dictionary:
	return {
		"kind": "flag",
		"id": entity_id,
		"team": team,
		"mode": mode,
		"carrier": carrier_id,
		"return_in": return_in,
		"home": home,
		"position": global_position,
		"rotation": global_transform.basis.get_rotation_quaternion(),
		"velocity": linear_velocity,
		"spin": angular_velocity,
		"sleeping": sleeping,
	}


func set_state(state: Dictionary) -> void:
	entity_id = state.id
	team = state.team
	mode = state.mode
	carrier_id = state.carrier
	return_in = state.return_in
	home = state.home
	var where := Transform3D(Basis(state.rotation as Quaternion), state.position)
	if mode == Mode.DROPPED:
		freeze = false
		global_transform = where
		linear_velocity = state.velocity
		angular_velocity = state.spin
		sleeping = state.sleeping
	else:
		_freeze_at(where)
