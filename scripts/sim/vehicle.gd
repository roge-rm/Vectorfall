class_name Vehicle
extends CharacterBody3D

enum Kind { BIKE, GUNSHIP, BOMBER, TRANSPORT, TANK }

const NAMES: Array[String] = ["Tern Sled", "Needlewing", "Cinder Kite", "Morrow Ferry", "Basalt Crawler"]
const MAX_HEALTH: Array[float] = [135.0, 280.0, 325.0, 420.0, 550.0]
const SEATS: Array[int] = [1, 2, 1, 4, 2]
const SIZE: Array[Vector3] = [
	Vector3(1.8, 0.95, 3.5), Vector3(4.1, 1.5, 4.8), Vector3(5.4, 1.55, 5.3),
	Vector3(4.8, 2.1, 6.4), Vector3(3.8, 1.7, 4.9),
]
const SPEED: Array[float] = [52.0, 62.0, 52.0, 44.0, 29.0]
const ACCEL: Array[float] = [22.0, 30.0, 22.0, 19.0, 14.0]
const TURN: Array[float] = [3.0, 2.2, 1.55, 1.6, 2.0]
const MASS: Array[float] = [190.0, 550.0, 770.0, 1000.0, 1300.0]
const WEAPONS: Array[int] = [-1, Weapon.TURRET, Weapon.MORTAR, -1, Weapon.DISC]
const MUZZLE: Array[Vector3] = [
	Vector3.ZERO, Vector3(0, 0.8, -1.1), Vector3(0, -0.65, -0.3),
	Vector3.ZERO, Vector3(0, 1.1, -0.55),
]
const ALTITUDE_LIMIT := 115.0
const CLIMB_SPEED := 15.0
const SINK_SPEED := 11.0
const BOARD_SPEED := 5.5
const HULL_LAYER := 64

var entity_id := 0
var team := 0
var kind := Kind.BIKE
var pad_id := 0
## Driver is seat zero. The gunship's second seat takes over the gun.
var crew: Array[int] = []
var health := 0.0
var yaw := 0.0
var gun_yaw := 0.0
var gun_pitch := 0.0
var cooldown := 0.0
var unattended := 0.0
var kick := Vector3.ZERO
var gun_mount: Node3D


func _ready() -> void:
	name = "Vehicle%d" % entity_id
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = HULL_LAYER
	collision_mask = Match.WORLD_LAYER | Match.ASSET_LAYER | HULL_LAYER | Match.enemy_fields(team)
	var collider := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = SIZE[kind]
	collider.shape = hull
	add_child(collider)
	gun_mount = VehicleLook.build(self)
	_pose()


static func ride_height(of_kind: int) -> float:
	return SIZE[of_kind].y * 0.5 + (0.75 if of_kind == Kind.BIKE else 0.12)


func flies() -> bool:
	return kind in [Kind.GUNSHIP, Kind.BOMBER, Kind.TRANSPORT]


func weapon_seat() -> int:
	return 1 if kind == Kind.GUNSHIP and crew[1] != 0 else 0


func uses_personal_weapon(seat: int) -> bool:
	return seat > 0 and (kind != Kind.GUNSHIP or seat != weapon_seat())


func open_seat() -> int:
	return crew.find(0)


func empty() -> bool:
	return crew.count(0) == crew.size()


func seat_eye(seat: int) -> Vector3:
	var offset := Vector3(0.0, SIZE[kind].y * 0.52, -SIZE[kind].z * 0.2)
	if seat > 0:
		offset.x = 0.0 if kind == Kind.GUNSHIP else (1.0 if seat % 2 else -1.0) * SIZE[kind].x * 0.43
		offset.z = SIZE[kind].z * (0.2 if seat < 3 else 0.38)
	return global_transform * offset


func distance_to_body(at: Vector3) -> float:
	var outside := (to_local(at).abs() - SIZE[kind] * 0.5).max(Vector3.ZERO)
	return outside.length()


func push(impulse: Vector3) -> void:
	kick = (kick + impulse / MASS[kind]).limit_length(15.0)


func drive(command: PlayerCommand, floor_y: float, delta: float) -> void:
	var goal := Vector3.ZERO
	if command != null:
		yaw = rotate_toward(yaw, command.yaw, TURN[kind] * delta)
		var normal := command.move.limit_length()
		var across := 0.7 if flies() else (0.35 if kind == Kind.BIKE else 0.0)
		goal = Basis(Vector3.UP, yaw) * Vector3(normal.x * across, 0.0, -normal.y)
		goal *= SPEED[kind] * (0.4 if normal.y < 0.0 else 1.0)
	rotation.y = yaw
	var ground_band := ride_height(kind)
	var lift := clampf((floor_y + ground_band - position.y) * 9.0, -12.0, 20.0)
	if flies() and command != null:
		lift = maxf(0.0, lift)
		if command.has(PlayerCommand.JUMP):
			lift = maxf(-SINK_SPEED, (floor_y + ground_band - position.y) * 9.0)
		elif command.has(PlayerCommand.JET):
			lift = clampf((floor_y + ALTITUDE_LIMIT - position.y) * 2.0, 0.0, CLIMB_SPEED)
	var flat := Vector3(velocity.x, 0, velocity.z).move_toward(goal, ACCEL[kind] * delta)
	velocity = flat + Vector3.UP * move_toward(velocity.y, lift, 36.0 * delta)
	velocity += kick * delta * 4.0
	kick = kick.move_toward(Vector3.ZERO, delta * 7.0)
	if velocity.length_squared() > 0.0004:
		move_and_slide()
	cooldown = maxf(0.0, cooldown - delta)


func aim(command: PlayerCommand, delta: float) -> void:
	var aim_yaw := yaw if kind == Kind.GUNSHIP and weapon_seat() == 0 else command.yaw
	gun_yaw = rotate_toward(gun_yaw, aim_yaw, 3.5 * delta)
	gun_pitch = move_toward(gun_pitch, clampf(command.pitch, -0.9, 0.85), 3.5 * delta)
	_pose()


func _pose() -> void:
	rotation.y = yaw
	if gun_mount != null:
		gun_mount.rotation = Vector3(gun_pitch, gun_yaw - yaw, 0.0)


func get_state() -> Dictionary:
	return {
		"id": entity_id, "pad": pad_id, "team": team, "kind": kind, "position": position,
		"velocity": velocity, "yaw": yaw, "crew": crew.duplicate(), "health": health,
		"gun_yaw": gun_yaw, "gun_pitch": gun_pitch, "cooldown": cooldown,
		"unattended": unattended, "kick": kick,
	}


func set_state(state: Dictionary) -> void:
	position = state.position
	velocity = state.velocity
	yaw = state.yaw
	crew.assign(state.crew)
	health = state.health
	gun_yaw = state.gun_yaw
	gun_pitch = state.gun_pitch
	cooldown = state.cooldown
	unattended = state.unattended
	kick = state.kick
	_pose()
