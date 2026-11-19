class_name BotCombat
extends RefCounted

## A bot's fighting: picks a target from what it knows, picks one of the
## weapons it carries by range, the target and its energy, leads its shots
## from the projectile's speed, the speed it inherits and its drop, aims discs
## at the feet of anyone on the ground, lobs mortar and grenade shells onto
## them, and fires once its aim is close enough. It throws hand grenades at
## close targets and at the carrier of our flag. It only turns the look and
## adds the buttons and weapon to the steering's command, so the bot keeps
## moving while it fights. Skill sets how far the aim wanders, how well it
## leads and how fast it turns.

## Closer than this a disc hurts the shooter too, in metres.
const DISC_MIN := 10.0
## Discs out to this range at someone on the ground, and this in the air.
const DISC_RANGE := 90.0
const DISC_AIR_RANGE := 35.0
## The chaingun is fired out to this range, where its spread still hits.
const CHAIN_RANGE := 40.0
## Plasma, the blaster and the grenade launcher are fired out to these
## ranges, in metres.
const PLASMA_RANGE := 60.0
const BLASTER_RANGE := 30.0
const GRENADE_RANGE := 38.0
## The mortar lobs from MORTAR_MIN, clear of its own blast, to MORTAR_RANGE,
## about its reach in its fuse.
const MORTAR_MIN := 22.0
const MORTAR_RANGE := 65.0
## The sniper rifle is for targets past SNIPER_MIN out to SNIPER_RANGE moving
## slower than SNIPER_SLOW m/s, fired with at least SNIPER_ENERGY, where its
## damage is near its most.
const SNIPER_MIN := 60.0
const SNIPER_RANGE := 220.0
const SNIPER_SLOW := 12.0
const SNIPER_ENERGY := 95.0
## Energy kept for the jets when using an energy weapon, more while climbing,
## in the air or carrying a flag.
const JET_RESERVE := 25.0
const JET_RESERVE_MOVING := 50.0
## Hand grenades go at targets on the ground from GRENADE_THROW_MIN to
## GRENADE_THROW_MAX metres, or a carrier of our flag in that reach, at most
## one every GRENADE_GAP seconds, with up to GRENADE_AIM_TICKS to aim.
const GRENADE_THROW_MIN := 6.0
const GRENADE_THROW_MAX := 18.0
const GRENADE_GAP := 4.0
const GRENADE_AIM_TICKS := 40
## Discs go at the feet when they're at least this far below the look, in
## radians, about 6°. Flatter than that a small error lands them far off.
const FEET_ANGLE := 0.1
## Seconds a target that went out of sight is still aimed at, and for an
## aggressive bot, which chases longer.
const KEEP_AIM := 1.0
const KEEP_AIM_AGGRESSIVE := 2.5
## A sniper takes disc shots this much further out.
const SNIPER_REACH := 1.35
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
## Ticks left to aim a hand grenade, and the first tick it may throw another.
var throw_ticks := 0
var next_grenade_tick := 0


func reset() -> void:
	target_id = 0
	aiming = false
	aim_error = Vector2.ZERO
	dodge_ticks = 0
	throw_ticks = 0


## True if hit within the last few seconds.
func hurt_recently(tick: int) -> bool:
	return (tick - hurt_tick) / 60.0 < HURT_MEMORY


## True while it has a target or was just hit.
func fighting(brain: BotBrain) -> bool:
	return target_id != 0 or hurt_recently(brain.game.tick)


## Energy to keep for the jets before using an energy weapon or pack.
static func jet_reserve(brain: BotBrain) -> float:
	var s := brain.soldier
	if not s.grounded or brain.steering.climbing or brain.steering.resting or brain.game.carried_flag(s.entity_id) != null:
		return JET_RESERVE_MOVING
	return JET_RESERVE


## How far out it picks targets, by the furthest reaching weapon it carries.
static func reach(brain: BotBrain) -> float:
	var out := disc_range(brain)
	if brain.soldier.weapons.has(Weapon.SNIPER):
		out = maxf(out, SNIPER_RANGE)
	return out


## Aim error at this skill, in radians: about 4° for a beginner and half a
## degree for an expert. Up and down it's half that.
static func error_for(skill: float) -> float:
	return lerpf(0.07, 0.008, skill)


## How fast the bot can turn its look, in radians a second.
static func turn_rate_for(skill: float) -> float:
	return lerpf(3.0, 10.0, skill)


## How far out the bot fires discs at someone on the ground: further for a
## sniper.
static func disc_range(brain: BotBrain) -> float:
	return DISC_RANGE * (SNIPER_REACH if brain.personality == BotBrain.Personality.SNIPER else 1.0)


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
	var far := reach(brain)
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
		var keep := KEEP_AIM_AGGRESSIVE if brain.personality == BotBrain.Personality.AGGRESSIVE else KEEP_AIM
		if not seen and last_seen > keep:
			continue
		var distance := s.at().distance_to(perception.guess_position(id, game.tick))
		if distance > far:
			continue
		# Closer is more of a threat, a carrier of our flag matters most, and
		# whoever is shooting at us comes next.
		var score := distance
		if game.carried_flag(id) != null:
			score -= 120.0
		# Going for a flag, whoever guards it comes first.
		if (brain.goal == BotBrain.Goal.TAKE_FLAG or brain.goal == BotBrain.Goal.CAPTURE) and other.at().distance_to(brain.goal_target) < 30.0:
			score -= 60.0
		if ours != null and other.at().distance_to(ours.at()) < 50.0:
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
		lead_share = 1.0 + clampf(brain.rng.randfn(0.0, spread), -0.6, 0.6)
	var sigma := error_for(brain.skill)
	if target_id != 0:
		# A target crossing fast is harder to keep on.
		var other := game.soldier(target_id)
		var to := other.at() - s.at()
		var across := (other.vel() - s.vel()).slide(to.normalized()).length()
		sigma += across / maxf(to.length(), 5.0) * lerpf(0.12, 0.04, brain.skill)
	aim_error = aim_error * 0.5 + Vector2(brain.rng.randfn(0.0, sigma), brain.rng.randfn(0.0, sigma * 0.5))
	if target_id != 0:
		var other := game.soldier(target_id)
		var distance := s.at().distance_to(other.at())
		weapon = pick_weapon(brain, other, distance)
		var carrier := game.carried_flag(target_id) != null
		if throw_ticks <= 0 and s.grenades > 0 and game.tick >= next_grenade_tick and perception.can_see(target_id) and distance > GRENADE_THROW_MIN and distance < GRENADE_THROW_MAX and (other.grounded or carrier):
			throw_ticks = GRENADE_AIM_TICKS
		if dodge_ticks <= 0 and brain.rng.randf() < 0.3:
			dodge_ticks = brain.rng.randi_range(20, 50)
			dodge_side = -dodge_side


## The carried weapon best for a target at this distance, by how well each
## suits it; the weapon in hand when none can fire.
func pick_weapon(brain: BotBrain, other: Soldier, distance: float) -> int:
	var s := brain.soldier
	var best := weapon if s.weapons.has(weapon) else s.weapon_slot()
	var best_score := 0.0
	for slot in s.weapons:
		var score := weapon_score(brain, slot, other, distance)
		if score > best_score:
			best_score = score
			best = slot
	return best


## How well a weapon suits a target at this distance, higher is better and 0
## for one it can't or shouldn't fire.
static func weapon_score(brain: BotBrain, slot: int, other: Soldier, distance: float) -> float:
	var s := brain.soldier
	if not s.loaded(slot):
		return 0.0
	var air := not other.grounded
	var slow := other.vel().length() < SNIPER_SLOW
	var reserve := jet_reserve(brain)
	match slot:
		Weapon.DISC:
			if distance > DISC_MIN and distance < (DISC_AIR_RANGE if air else disc_range(brain)):
				return 50.0 if air else 60.0
			return 5.0 if distance > DISC_MIN else 1.0
		Weapon.CHAINGUN:
			if distance < DISC_MIN:
				return 70.0
			if distance < CHAIN_RANGE:
				return 65.0 if air else 30.0
			return 3.0
		Weapon.PLASMA:
			if distance > 6.0 and distance < PLASMA_RANGE:
				return 55.0 if air else 40.0
			return 4.0 if distance > 6.0 else 0.0
		Weapon.GRENADE_LAUNCHER:
			if air or distance < 10.0:
				return 0.0
			if distance < GRENADE_RANGE:
				# Better than the disc at someone well below, round a lip.
				return 62.0 if other.at().y < s.at().y - 5.0 else 45.0
			return 2.0
		Weapon.MORTAR:
			if air or distance < MORTAR_MIN or distance > MORTAR_RANGE:
				return 0.0
			return 75.0 if other.vel().length() < 15.0 else 45.0
		Weapon.SNIPER:
			if distance < 30.0:
				return 0.0
			if s.energy < SNIPER_ENERGY:
				# Past the disc's reach it waits for the energy with it in hand.
				return 6.0 if distance > disc_range(brain) else 0.0
			return 80.0 if distance > SNIPER_MIN and slow else 35.0
		Weapon.BLASTER:
			if s.energy < Weapon.all[slot].energy_per_shot + reserve:
				return 0.0
			if distance < BLASTER_RANGE:
				return 55.0 if air else 50.0
			return 8.0
	return 1.0


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
	var at := other.at() if seen else brain.perception.guess_position(target_id, game.tick)
	var velocity := other.vel() if seen else Vector3.ZERO
	var throwing := throw_ticks > 0 and s.grenades > 0
	if throw_ticks > 0:
		throw_ticks -= 1
	var w := Weapon.all[Weapon.HAND_GRENADE if throwing else weapon]
	if w.slot == Weapon.CHAINGUN:
		# Tracking lags behind a target that moves across, more for a beginner.
		at -= velocity * lerpf(0.25, 0.06, brain.skill)
	var fall := s.tuning.gravity if seen and not other.grounded and not other.jetting else 0.0
	var aim_at := lead(eye, s.vel(), at, velocity, fall, w)
	aim_at = at + (aim_at - at) * lead_share if lead_share != 1.0 else aim_at
	var below := atan2(eye.y - aim_at.y, Vector2(aim_at.x - eye.x, aim_at.z - eye.z).length())
	if w.slot == Weapon.DISC and other.grounded and below > FEET_ANGLE:
		# The ground at the feet, for the splash.
		aim_at.y -= 0.1
	elif w.slot == Weapon.DISC and other.grounded:
		# Too flat an angle to hit the ground where it should, so low on the
		# body: a miss above still hits it and one below lands close.
		aim_at.y += 0.5
	elif w.gravity > 1.0 and other.grounded:
		# Lobs land low on the body, or just short, and bounce on into it.
		aim_at.y += 0.4
	else:
		aim_at.y += s.tuning.height * 0.5
	var to := aim_at - eye
	var want_yaw := atan2(-to.x, -to.z) + aim_error.x
	var want_pitch := aim_error.y + (lob_pitch(to, w) if w.gravity > 0.0 else atan2(to.y, Vector2(to.x, to.z).length()))
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
	command.weapon = s.carried(weapon)

	var off := absf(wrapf(want_yaw - aim_yaw, -PI, PI)) + absf(want_pitch - aim_pitch)
	var distance := to.length()
	if throwing:
		if seen and off < maxf(atan2(2.0, distance), 0.03) and not s.grenade_held and s.throw_cooldown <= 0.0:
			command.buttons |= PlayerCommand.GRENADE
			throw_ticks = 0
			next_grenade_tick = game.tick + int(GRENADE_GAP * 60.0)
		return
	if not seen or s.weapon_slot() != weapon:
		return
	var tolerance := maxf(atan2(1.5, distance), 0.02)
	match weapon:
		Weapon.CHAINGUN:
			tolerance *= 2.0
		Weapon.MORTAR:
			tolerance = maxf(atan2(3.0, distance), 0.02)
		Weapon.SNIPER:
			tolerance = maxf(atan2(0.4, distance), 0.003)
	if off > tolerance or distance > fire_range(brain, weapon, other):
		return
	if w.uses_energy() and s.energy < w.energy_per_shot + jet_reserve(brain) and weapon != Weapon.SNIPER:
		return
	if weapon == Weapon.SNIPER and (s.energy < SNIPER_ENERGY or s.cooldown > 0.0):
		return
	var keep := self_blast_range(weapon) * (1.0 if s.health > LOW_HEALTH else 1.5)
	if keep > 0.0:
		# The blast mustn't reach the bot itself, with more room when hurt.
		if s.cooldown > 0.0 or distance < keep:
			return
		# Not into a wall or the ground right in front, which the bot checks
		# with a ray after the bot phase's work, taking the fire back if not.
		var forward := -Basis.from_euler(Vector3(aim_pitch, aim_yaw, 0.0)).z
		brain.check_disc(eye, eye + forward * DISC_MIN)
	command.buttons |= PlayerCommand.FIRE


## How far out a weapon is fired at a target.
static func fire_range(brain: BotBrain, slot: int, other: Soldier) -> float:
	match slot:
		Weapon.DISC:
			return disc_range(brain) if other.grounded else DISC_AIR_RANGE
		Weapon.CHAINGUN:
			return CHAIN_RANGE
		Weapon.PLASMA:
			return PLASMA_RANGE
		Weapon.GRENADE_LAUNCHER:
			return GRENADE_RANGE
		Weapon.MORTAR:
			return MORTAR_RANGE
		Weapon.SNIPER:
			return SNIPER_RANGE
		Weapon.BLASTER:
			return BLASTER_RANGE
	return DISC_RANGE


## Closer than this a weapon's own blast reaches the shooter, or 0 for one
## with no splash to speak of.
static func self_blast_range(slot: int) -> float:
	match slot:
		Weapon.DISC:
			return DISC_MIN
		Weapon.GRENADE_LAUNCHER:
			return 9.0
		Weapon.MORTAR:
			return MORTAR_MIN * 0.75
		Weapon.PLASMA:
			return 5.0
	return 0.0


## Look pitch for a lob to land at "to" from the eye: the low arc, or 45°
## for a target out of reach.
static func lob_pitch(to: Vector3, w: Weapon) -> float:
	var x := Vector2(to.x, to.z).length()
	var v2 := w.speed * w.speed
	var g := w.gravity
	var root := v2 * v2 - g * (g * x * x + 2.0 * to.y * v2)
	if root < 0.0 or x < 0.1:
		return PI * 0.25 if x >= 0.1 else atan2(to.y, 0.1)
	return atan2(v2 - sqrt(root), g * x)


## Seconds a shot takes to get to "to" from the eye, along the lob for a
## weapon that drops.
static func flight_time(to: Vector3, w: Weapon) -> float:
	if w.gravity <= 0.0:
		return to.length() / w.speed
	var x := Vector2(to.x, to.z).length()
	return x / maxf(w.speed * cos(lob_pitch(to, w)), 1.0)


## Where to aim so a shot from eye meets a target at "at" moving with
## velocity: the shot inherits part of the shooter's velocity, and a target
## in the air falls at fall m/s².
static func lead(eye: Vector3, shooter_velocity: Vector3, at: Vector3, velocity: Vector3, fall: float, w: Weapon) -> Vector3:
	var relative := velocity - shooter_velocity * w.inherit
	var t := flight_time(at - eye, w)
	var aim := at
	for k in 4:
		aim = at + relative * t + Vector3.DOWN * 0.5 * fall * t * t
		t = flight_time(aim - eye, w)
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
		"throw_ticks": throw_ticks,
		"next_grenade_tick": next_grenade_tick,
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
	throw_ticks = state.get("throw_ticks", 0)
	next_grenade_tick = state.get("next_grenade_tick", 0)
