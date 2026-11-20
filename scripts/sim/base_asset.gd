class_name BaseAsset
extends StaticBody3D

## A machine in a team's base: its generator, a turret or its sensor. Shots and
## blasts from the other team wear its health down, and at 0 it's destroyed.
## A repair pack brings its health back up, and a destroyed one works again
## once it's full. It's a solid upright cylinder on Match.ASSET_LAYER, so
## shots hit it and soldiers can't walk through it. Its origin is its foot.
## The match changes it only on physics ticks, and its look is made in
## _ready().

enum Kind { GENERATOR, TURRET, SENSOR }

## Per kind: most health, and the body's radius and height in metres.
const MAX_HEALTH: Array[float] = [400.0, 250.0, 150.0]
const RADIUS: Array[float] = [1.3, 0.7, 0.45]
const HEIGHT: Array[float] = [2.2, 1.8, 2.6]
const NAMES: Array[String] = ["Generator", "Turret", "Sensor"]
## A turret aims at the nearest enemy it can see within TURRET_RANGE metres,
## looking round every LOOK_TICKS ticks with up to LOOK_RAYS line of sight
## rays. It turns at TURN_RATE radians a second, 90°, and fires when its aim
## is within FIRE_CONE radians of where it wants to be, about 3°.
const TURRET_RANGE := 70.0
const LOOK_TICKS := 15
const LOOK_RAYS := 3
const TURN_RATE := PI * 0.5
const FIRE_CONE := 0.05
const PITCH_MIN := -1.0
const PITCH_MAX := 1.3
## Height share of a turret's swivel point, where its shots start, and its
## barrel's length past that in metres, for the shot's look.
const PIVOT_SHARE := 0.78
const BARREL := 1.2
## A sensor sees enemies within this many metres while it works and has power.
const SENSOR_RANGE := 90.0
## How far under a guard point, in metres, a turret still guards.
const GUARD_BELOW := 2.0

var entity_id := 0
var team := 0
var kind := Kind.GENERATOR
## Yaw in radians it faces, for a turret's resting aim and the look.
var facing := 0.0
var health := 0.0
var destroyed := false
## A turret's aim, as a yaw and pitch in radians like a soldier's look.
var aim_yaw := 0.0
var aim_pitch := 0.0
## A turret with guard points only aims at enemies within guard_radius
## metres of one of them across the ground and no more than GUARD_BELOW
## under it. With none it aims at any enemy in range.
var guard_points: Array[Vector3] = []
var guard_radius := 0.0
## Entity id of the soldier a turret aims at, 0 for none.
var target_id := 0
## Seconds until a turret can fire again.
var cooldown := 0.0
## The part of a turret's look that swivels with its aim, or null.
var head: Node3D


## A new asset of a kind at full health.
static func make(of_kind: Kind, of_team: int) -> BaseAsset:
	var made := BaseAsset.new()
	made.kind = of_kind
	made.team = of_team
	made.health = MAX_HEALTH[of_kind]
	return made


func _ready() -> void:
	name = "%s%d" % [NAMES[kind], entity_id]
	collision_layer = Match.ASSET_LAYER
	collision_mask = 0
	rotation.y = facing
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius()
	cylinder.height = height()
	shape.shape = cylinder
	shape.position = Vector3.UP * height() * 0.5
	add_child(shape)
	head = AssetLook.build(self, kind, team)
	_pose_head()


## True for a point a turret guards: anywhere with no guard points, else
## within guard_radius of one across the ground and above or just under it.
func guards(point: Vector3) -> bool:
	if guard_points.is_empty():
		return true
	for at in guard_points:
		var flat := Vector2(point.x - at.x, point.z - at.z)
		if flat.length() <= guard_radius and point.y >= at.y - GUARD_BELOW:
			return true
	return false


func max_health() -> float:
	return MAX_HEALTH[kind]


func radius() -> float:
	return RADIUS[kind]


func height() -> float:
	return HEIGHT[kind]


func centre() -> Vector3:
	return global_position + Vector3.UP * height() * 0.5


## A turret's swivel point, where its shots start.
func pivot() -> Vector3:
	return global_position + Vector3.UP * height() * PIVOT_SHARE


## The way a yaw and pitch look, like a soldier's.
static func direction(yaw: float, pitch: float) -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


## Turns a turret's aim towards a yaw and pitch by up to step radians on each.
func turn_towards(yaw: float, pitch: float, step: float) -> void:
	aim_yaw = wrapf(aim_yaw + clampf(wrapf(yaw - aim_yaw, -PI, PI), -step, step), -PI, PI)
	aim_pitch = aim_pitch + clampf(pitch - aim_pitch, -step, step)
	_pose_head()


func _pose_head() -> void:
	if head != null:
		head.rotation = Vector3(aim_pitch, aim_yaw - facing, 0.0)


## True while it works: not destroyed. Power is the match's to check.
func working() -> bool:
	return not destroyed


## Distance from a point to the body's cylinder, 0 inside it.
func distance_to_body(point: Vector3) -> float:
	var d := point - global_position
	var side := maxf(Vector2(d.x, d.z).length() - radius(), 0.0)
	var up := maxf(maxf(-d.y, d.y - height()), 0.0)
	return Vector2(side, up).length()


func get_state() -> Dictionary:
	return {
		"kind": "asset",
		"id": entity_id,
		"team": team,
		"asset": kind,
		"position": position,
		"facing": facing,
		"health": health,
		"destroyed": destroyed,
		"aim_yaw": aim_yaw,
		"aim_pitch": aim_pitch,
		"target_id": target_id,
		"cooldown": cooldown,
		"guard_points": guard_points.duplicate(),
		"guard_radius": guard_radius,
	}


func set_state(state: Dictionary) -> void:
	entity_id = state.id
	team = state.team
	kind = int(state.asset) as Kind
	position = state.position
	facing = state.facing
	rotation.y = facing
	health = state.health
	destroyed = state.destroyed
	aim_yaw = state.get("aim_yaw", facing)
	aim_pitch = state.get("aim_pitch", 0.0)
	target_id = state.get("target_id", 0)
	cooldown = state.get("cooldown", 0.0)
	guard_points.assign(state.get("guard_points", []))
	guard_radius = state.get("guard_radius", 0.0)
	_pose_head()
