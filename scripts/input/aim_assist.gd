class_name AimAssist
extends RefCounted

## Aim assist for touch and the gamepad. find() picks the enemy whose aim
## point is closest to the crosshair: where to aim for the weapon in hand to
## hit, leading its velocity. LocalInput slows look near that point and turns
## gently toward it. It only changes the yaw and pitch a command sends, never
## the sim. Main thread, outside the bot phase.

enum Level { OFF, LOW, HIGH }

## Share of look speed kept near an aim point, by level.
const SLOWDOWN: Array[float] = [1.0, 0.6, 0.4]
## Turn toward the aim point in radians per second by level: about 3° and 7°.
const PULL: Array[float] = [0.0, 0.052, 0.122]
## Look slows within this many metres of the aim point, held to an angle
## between SLOW_ANGLE_MIN and SLOW_ANGLE_MAX in radians (about 2° to 8°).
const SLOW_RADIUS := 1.5
const SLOW_ANGLE_MIN := 0.035
const SLOW_ANGLE_MAX := 0.14
## Only aim points within this angle of the crosshair count, about 11°.
const PULL_ANGLE := 0.2
## Useful range in metres for each gun, by Weapon slot.
const RANGES: Array[float] = [90.0, 60.0, 45.0, 80.0, 70.0, 250.0, 40.0]
## Share of the real lead taken for the fast guns (chaingun, sniper, blaster),
## which mostly aim at the body.
const LIGHT_LEAD := 0.5
## Line of sight rays: at most RAYS_PER_TICK a tick, one per target every
## RECHECK_TICKS, and a result older than FORGET_TICKS isn't trusted.
const RAYS_PER_TICK := 2
const RECHECK_TICKS := 6
const FORGET_TICKS := 30


## An enemy's aim point as seen from the crosshair.
class Aim:
	var target_id := 0
	## Where to look to hit, and how far that is from the crosshair, in radians.
	var yaw := 0.0
	var pitch := 0.0
	var error := 0.0
	## Within this angle of the aim point look slows down.
	var slow_angle := 0.0


## Target id to Vector2i(tick checked, 1 if the line was clear).
var _lines: Dictionary[int, Vector2i] = {}
var _ray_tick := -1
var _rays_left := 0


## The closest aim point to where shooter looks with yaw and pitch, or null:
## enemies alive, in front, in range of the weapon in hand, in clear view,
## and not jamming past the jammer's sight.
func find(shooter: Soldier, yaw: float, pitch: float) -> Aim:
	if shooter == null or shooter.dead or shooter.game == null:
		return null
	var game := shooter.game
	var slot := shooter.weapon_slot()
	if slot < 0 or slot >= RANGES.size():
		return null
	var w := Weapon.all[slot]
	var eye := shooter.eye_transform().origin
	var view := direction(yaw, pitch)
	var jam_sight := Pack.all[Pack.JAMMER].jam_sight
	var found: Array[Aim] = []
	for node: Node in game.entities.values():
		var other := node as Soldier
		if other == null or other.dead or other.team == shooter.team:
			continue
		var body := other.at() + Vector3.UP * other.tuning.height * 0.5
		var distance := eye.distance_to(body)
		if distance > RANGES[slot] or distance < 0.5:
			continue
		if other.jamming() and distance > jam_sight:
			continue
		var aim := _aim_at(shooter, other, eye, body, w)
		aim.error = view.angle_to(direction(aim.yaw, aim.pitch))
		if aim.error > PULL_ANGLE:
			continue
		aim.slow_angle = clampf(atan2(SLOW_RADIUS, distance), SLOW_ANGLE_MIN, SLOW_ANGLE_MAX)
		found.append(aim)
	found.sort_custom(func(a: Aim, b: Aim) -> bool: return a.error < b.error)
	for aim in found:
		if _line_clear(game, aim.target_id, eye):
			return aim
	return null


## Where shooter should look to hit other with weapon w.
func _aim_at(shooter: Soldier, other: Soldier, eye: Vector3, body: Vector3, w: Weapon) -> Aim:
	var aim := Aim.new()
	aim.target_id = other.entity_id
	var at := body
	var arced := false
	match w.slot:
		Weapon.CHAINGUN, Weapon.SNIPER, Weapon.BLASTER:
			var relative := other.vel() - shooter.vel() * w.inherit
			at = body + relative * (eye.distance_to(body) / w.speed) * LIGHT_LEAD
		_:
			var fall := other.tuning.gravity if not other.grounded and not other.jetting else 0.0
			at = BotCombat.lead(eye, shooter.vel(), body, other.vel(), fall, w)
			arced = w.gravity > 1.0
	var to := at - eye
	aim.yaw = atan2(-to.x, -to.z)
	aim.pitch = BotCombat.lob_pitch(to, w) if arced else atan2(to.y, Vector2(to.x, to.z).length())
	aim.pitch = clampf(aim.pitch, -Soldier.PITCH_LIMIT, Soldier.PITCH_LIMIT)
	return aim


## Whether the line from eye to a target is clear, from the cache or a new
## ray while this tick has rays left.
func _line_clear(game: Match, id: int, eye: Vector3) -> bool:
	if _ray_tick != game.tick:
		_ray_tick = game.tick
		_rays_left = RAYS_PER_TICK
	var known: Vector2i = _lines.get(id, Vector2i(-100000, 0))
	var age := game.tick - known.x
	if age >= RECHECK_TICKS and _rays_left > 0:
		_rays_left -= 1
		var other := game.soldier(id)
		var clear := game.line_clear(eye, other.at() + Vector3.UP * other.tuning.height * 0.5)
		known = Vector2i(game.tick, 1 if clear else 0)
		_lines[id] = known
		age = 0
	return age <= FORGET_TICKS and known.y == 1


## Turns yaw and pitch toward an aim point by up to step radians.
static func pull(yaw: float, pitch: float, aim: Aim, step: float) -> Vector2:
	var error := direction(yaw, pitch).angle_to(direction(aim.yaw, aim.pitch))
	if error <= 0.0001:
		return Vector2(yaw, pitch)
	var share := minf(step / error, 1.0)
	return Vector2(yaw + wrapf(aim.yaw - yaw, -PI, PI) * share, pitch + (aim.pitch - pitch) * share)


## Look speed share near an aim point: the level's slowdown inside half its
## slow angle, easing back to full speed at the edge.
static func slowdown(aim: Aim, level: int) -> float:
	if aim == null or aim.error >= aim.slow_angle:
		return 1.0
	var inside := clampf(inverse_lerp(aim.slow_angle, aim.slow_angle * 0.5, aim.error), 0.0, 1.0)
	return lerpf(1.0, SLOWDOWN[level], inside)


## The way a soldier looks with this yaw and pitch, as in eye_transform().
static func direction(yaw: float, pitch: float) -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3.FORWARD
