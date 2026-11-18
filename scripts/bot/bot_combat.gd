class_name BotCombat
extends RefCounted

## A bot's fighting: picks a target from what it knows, picks the disc or the
## chaingun by range, leads its shots from the projectile's speed and the
## speed it inherits, aims discs at the feet of anyone on the ground, and
## fires once its aim is close enough. It only turns the look and adds the
## fire button and weapon to the steering's command, so the bot keeps moving
## while it fights. Skill sets how far the aim wanders, how well it leads
## and how fast it turns.

## Closer than this a disc hurts the shooter too, in metres.
const DISC_MIN := 10.0
## Discs out to this range at someone on the ground, and this in the air.
const DISC_RANGE := 90.0
const DISC_AIR_RANGE := 35.0
## The chaingun is fired out to this range, where its spread still hits.
const CHAIN_RANGE := 40.0
## Discs go at the feet when they're at least this far below the look, in
## radians, about 6°. Flatter than that a small error lands them far off.
const FEET_ANGLE := 0.1
## Seconds a target that went out of sight is still aimed at.
const KEEP_AIM := 1.0
## Health below which the bot backs off.
const LOW_HEALTH := 35.0
## Seconds a hit tells the bot who's shooting at it.
const HURT_MEMORY := 3.0

## The soldier being fought, or 0 for none.
var target_id := 0
## Aim error as (yaw, pitch) in radians, wandering each think.
var aim_error := Vector2.ZERO
## How much of the lead the bot takes, 1 for exact, picked per target.
var lead_share := 1.0
## Where the bot is looking while it fights.
var aim_yaw := 0.0
var aim_pitch := 0.0
var aiming := false
## The weapon slot it wants.
var weapon := Weapon.DISC
## Who last hurt it, and when.
var hurt_by := 0
var hurt_tick := -1000
## Ticks left of a side step while fighting, and which way.
var dodge_ticks := 0
var dodge_side := 1.0


func reset() -> void:
	target_id = 0
	aiming = false
	aim_error = Vector2.ZERO
	dodge_ticks = 0


## Aim error at this skill, in radians: about 4° for a beginner and half a
## degree for an expert. Up and down it's half that.
static func error_for(skill: float) -> float:
	return lerpf(0.07, 0.008, skill)


## How fast the bot can turn its look, in radians a second.
static func turn_rate_for(skill: float) -> float:
	return lerpf(3.0, 10.0, skill)


## Picks a target and a weapon, and lets the aim error wander. Called when
## the bot thinks.
func think(brain: BotBrain) -> void:
	var s := brain.soldier
	var game := brain.game
	var perception := brain.perception
	var best := 0
	var best_score := INF
	# Our own carrier, whose chasers come first.
	var ours: Soldier = null
	var theirs: Flag = game.flags.get(1 - s.team)
	if theirs != null and theirs.mode == Flag.Mode.CARRIED and theirs.carrier_id != s.entity_id:
		ours = game.soldier(theirs.carrier_id)
	# Or the runner it escorts, or the person it covers.
	if ours == null and brain.role == BotBrain.Role.ESCORT and brain.role_target != 0:
		ours = game.soldier(brain.role_target)
	var boss := brain.director.commander(s.team)
	if ours == null and boss != null and boss.covers.has(s.entity_id):
		ours = game.soldier(boss.covers[s.entity_id])
	var ids := perception.contacts.keys()
	ids.sort()
	for id: int in ids:
		if not perception.knows(id):
			continue
		var other := game.soldier(id)
		if other == null or other.dead:
			continue
		var seen := perception.can_see(id)
		var last_seen: float = (game.tick - perception.contacts[id].tick) / 60.0
		if not seen and last_seen > KEEP_AIM:
			continue
		var distance := s.global_position.distance_to(perception.guess_position(id, game.tick))
		if distance > DISC_RANGE:
			continue
		# Closer is more of a threat, a carrier of our flag matters most, and
		# whoever is shooting at us comes next.
		var score := distance
		if game.carried_flag(id) != null:
			score -= 120.0
		# Going for a flag, whoever guards it comes first.
		if (brain.goal == BotBrain.Goal.TAKE_FLAG or brain.goal == BotBrain.Goal.CAPTURE) and other.global_position.distance_to(brain.goal_target) < 30.0:
			score -= 60.0
		if ours != null and other.global_position.distance_to(ours.global_position) < 50.0:
			score -= 80.0
		if id == hurt_by and (game.tick - hurt_tick) / 60.0 < HURT_MEMORY:
			score -= 40.0
		if id == target_id:
			score -= 15.0
		if not seen:
			score += 40.0
		if score < best_score:
			best_score = score
			best = id
	if best != target_id:
		target_id = best
		var spread := lerpf(0.35, 0.06, brain.skill)
		lead_share = 1.0 + clampf(game.rng.randfn(0.0, spread), -0.6, 0.6)
	var sigma := error_for(brain.skill)
	if target_id != 0:
		# A target crossing fast is harder to keep on.
		var other := game.soldier(target_id)
		var to := other.global_position - s.global_position
		var across := (other.velocity - s.velocity).slide(to.normalized()).length()
		sigma += across / maxf(to.length(), 5.0) * lerpf(0.12, 0.04, brain.skill)
	aim_error = aim_error * 0.5 + Vector2(game.rng.randfn(0.0, sigma), game.rng.randfn(0.0, sigma * 0.5))
	if target_id != 0:
		var other := game.soldier(target_id)
		var distance := s.global_position.distance_to(other.global_position)
		var disc_reach := DISC_RANGE if other.grounded else DISC_AIR_RANGE
		var has_disc := s.ammo[Weapon.DISC] > 0
		var has_chain := s.ammo[Weapon.CHAINGUN] > 0
		if has_disc and distance > DISC_MIN and distance < disc_reach:
			weapon = Weapon.DISC
		elif has_chain:
			weapon = Weapon.CHAINGUN
		elif has_disc:
			weapon = Weapon.DISC
		if dodge_ticks <= 0 and game.rng.randf() < 0.3:
			dodge_ticks = game.rng.randi_range(20, 50)
			dodge_side = -dodge_side


## Turns the steering's command to look at the target and fire. The push
## stays the same in the world, so it's turned to the new look.
func apply(brain: BotBrain, command: PlayerCommand, delta: float) -> void:
	var s := brain.soldier
	var game := brain.game
	var other := game.soldier(target_id) if target_id != 0 else null
	if other == null or other.dead or not brain.perception.knows(target_id):
		target_id = 0
		aiming = false
		return
	if not aiming:
		aim_yaw = s.yaw
		aim_pitch = s.pitch
		aiming = true
	var eye := s.eye_transform().origin
	var seen := brain.perception.can_see(target_id)
	# What a player sees: where the target is now if it's in view, or where
	# it was going if not.
	var at := other.global_position if seen else brain.perception.guess_position(target_id, game.tick)
	var velocity := other.velocity if seen else Vector3.ZERO
	var w := Weapon.all[weapon]
	if weapon == Weapon.CHAINGUN:
		# Tracking lags behind a target that moves across, more for a beginner.
		at -= velocity * lerpf(0.25, 0.06, brain.skill)
	var fall := s.tuning.gravity if seen and not other.grounded and not other.jetting else 0.0
	var aim_at := lead(eye, s.velocity, at, velocity, fall, w)
	aim_at = at + (aim_at - at) * lead_share if lead_share != 1.0 else aim_at
	var below := atan2(eye.y - aim_at.y, Vector2(aim_at.x - eye.x, aim_at.z - eye.z).length())
	if weapon == Weapon.DISC and other.grounded and below > FEET_ANGLE:
		# The ground at the feet, for the splash.
		aim_at.y -= 0.1
	elif weapon == Weapon.DISC and other.grounded:
		# Too flat an angle to hit the ground where it should, so low on the
		# body: a miss above still hits it and one below lands close.
		aim_at.y += 0.5
	else:
		aim_at.y += s.tuning.height * 0.5
	var to := aim_at - eye
	var want_yaw := atan2(-to.x, -to.z) + aim_error.x
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length()) + aim_error.y
	if w.gravity > 0.0:
		# Lift for the drop on the way.
		var flight := to.length() / w.speed
		want_pitch += atan2(0.5 * w.gravity * flight * flight, to.length())
	var turn := turn_rate_for(brain.skill) * delta
	var dyaw := wrapf(want_yaw - aim_yaw, -PI, PI)
	aim_yaw = wrapf(aim_yaw + clampf(dyaw, -turn, turn), -PI, PI)
	aim_pitch = clampf(aim_pitch + clampf(want_pitch - aim_pitch, -turn, turn), -1.4, 1.4)

	# The steering's push, kept the same way in the world.
	var world := Basis(Vector3.UP, command.yaw) * Vector3(command.move.x, 0.0, -command.move.y)
	if dodge_ticks > 0:
		dodge_ticks -= 1
		if brain.holding():
			world = Basis(Vector3.UP, aim_yaw) * Vector3(dodge_side, 0.0, 0.0)
	command.yaw = aim_yaw
	command.pitch = aim_pitch
	var local := Basis(Vector3.UP, aim_yaw).inverse() * world
	command.move = Vector2(local.x, -local.z).limit_length(1.0)
	command.weapon = weapon

	if not seen or s.weapon != weapon:
		return
	var off := absf(wrapf(want_yaw - aim_yaw, -PI, PI)) + absf(want_pitch - aim_pitch)
	var distance := to.length()
	var tolerance := maxf(atan2(1.5, distance), 0.02)
	if weapon == Weapon.CHAINGUN:
		tolerance *= 2.0
	if off > tolerance or (weapon == Weapon.CHAINGUN and distance > CHAIN_RANGE):
		return
	if weapon == Weapon.DISC:
		# The blast mustn't reach the bot itself, with more room when hurt.
		var keep := DISC_MIN if s.health > LOW_HEALTH else DISC_MIN * 1.5
		if s.cooldown > 0.0 or distance < keep:
			return
		# Not into a wall or the ground right in front.
		if not brain.director.take_ray():
			return
		var forward := -Basis.from_euler(Vector3(aim_pitch, aim_yaw, 0.0)).z
		if not s.game.line_clear(eye, eye + forward * DISC_MIN):
			return
	command.buttons |= PlayerCommand.FIRE


## Where to aim so a shot from eye meets a target at "at" moving with
## velocity: the shot inherits part of the shooter's velocity, and a target
## in the air falls at fall m/s².
static func lead(eye: Vector3, shooter_velocity: Vector3, at: Vector3, velocity: Vector3, fall: float, w: Weapon) -> Vector3:
	var relative := velocity - shooter_velocity * w.inherit
	var t := eye.distance_to(at) / w.speed
	var aim := at
	for k in 4:
		aim = at + relative * t + Vector3.DOWN * 0.5 * fall * t * t
		t = eye.distance_to(aim) / w.speed
	return aim


## Called when the bot is hurt, so it knows who's shooting at it.
func hurt(attacker_id: int, tick: int) -> void:
	hurt_by = attacker_id
	hurt_tick = tick


func get_state() -> Dictionary:
	return {
		"target_id": target_id,
		"aim_error": aim_error,
		"lead_share": lead_share,
		"aim_yaw": aim_yaw,
		"aim_pitch": aim_pitch,
		"aiming": aiming,
		"weapon": weapon,
		"hurt_by": hurt_by,
		"hurt_tick": hurt_tick,
		"dodge_ticks": dodge_ticks,
		"dodge_side": dodge_side,
	}


func set_state(state: Dictionary) -> void:
	target_id = state.target_id
	aim_error = state.aim_error
	lead_share = state.lead_share
	aim_yaw = state.aim_yaw
	aim_pitch = state.aim_pitch
	aiming = state.aiming
	weapon = state.weapon
	hurt_by = state.hurt_by
	hurt_tick = state.hurt_tick
	dodge_ticks = state.dodge_ticks
	dodge_side = state.dodge_side
