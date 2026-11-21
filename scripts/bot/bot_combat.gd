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
## On a raid, enemy base assets within this many metres are shot at, and an
## enemy soldier closer than RAID_SELF_DEFENCE comes first.
const RAID_REACH := 90.0
## Under this many metres above a generator's foot and within ROOM_REACH
## of it a bot is in its room and shoots it straight, else at the room's
## floor through an opening, from no further than LOB_REACH.
const IN_ROOM := 2.5
const ROOM_REACH := 10.0
const LOB_REACH := 12.0
## How far off the floor point, in metres, a shot through an opening may go.
const LOB_SPOT := 0.5
const RAID_SELF_DEFENCE := 25.0

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
## The enemy base asset being shot at when there's no soldier to fight, or
## 0, and the asset the last look had a clear line to, or 0.
var asset_id := 0
var asset_seen := 0


func reset() -> void:
	target_id = 0
	asset_id = 0
	asset_seen = 0
	aiming = false
	aim_error = Vector2.ZERO
	dodge_ticks = 0
	throw_ticks = 0


## True if hit within the last few seconds.
func hurt_recently(tick: int) -> bool:
	return (tick - hurt_tick) / 60.0 < HURT_MEMORY


## True while it has a target or was just hit.
func fighting(brain: BotBrain) -> bool:
	return target_id != 0 or asset_id != 0 or hurt_recently(brain.game.tick)


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
	var machine := _pick_asset(brain)
	if machine != 0 and best != 0 and (brain.role != BotBrain.Role.GENERATOR or s.at().distance_to(perception.guess_position(best, game.tick)) < RAID_SELF_DEFENCE):
		machine = 0
	if machine != 0:
		best = 0
	asset_id = machine
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
	elif asset_id != 0:
		var info := brain.director.asset_info(asset_id)
		var eye := s.eye_transform().origin
		weapon = pick_asset_weapon(brain, eye.distance_to(asset_aim(eye, info)), lobbing(eye, info))


## The enemy base asset to shoot at, or 0. On a raid: a turret aiming at
## the bot, then the raid's target, then the nearest working one, within
## RAID_REACH. Otherwise only a turret that's shooting at it, when where the
## bot is going is inside that turret's reach, so going round won't lose it.
## Only one some carried weapon can hit from here.
func _pick_asset(brain: BotBrain) -> int:
	var s := brain.soldier
	var me := s.entity_id
	var pos := s.at()
	var raid := brain.role == BotBrain.Role.GENERATOR or (brain.role == BotBrain.Role.OFFENCE and brain.goal == BotBrain.Goal.RAID)
	var best := 0
	var best_score := INF
	var ids := brain.director.base_assets.keys()
	for id: int in ids:
		var info: Dictionary = brain.director.base_assets[id]
		if info.team == s.team or info.destroyed:
			continue
		var lob := lobbing(pos, info)
		var distance := pos.distance_to(asset_aim(pos, info))
		var shooting_me: bool = info.kind == BaseAsset.Kind.TURRET and info.target == me and info.powered
		var score := distance
		if raid:
			if distance > RAID_REACH:
				continue
			if shooting_me:
				score -= 100.0
			elif id == brain.role_target:
				score -= 50.0
		else:
			if not shooting_me or hurt_by != id or not hurt_recently(brain.game.tick) or distance > BaseAsset.TURRET_RANGE:
				continue
			if brain.goal_target.distance_to(info.centre) > BaseAsset.TURRET_RANGE and not brain.holding():
				continue
		if id == asset_id:
			score -= 10.0
		if pick_asset_weapon(brain, distance, lob) < 0:
			continue
		if score < best_score:
			best_score = score
			best = id
	return best


## True for shooting a generator through an opening from above: it has
## floor points to shoot at and the point is above its room.
static func lobbing(from: Vector3, info: Dictionary) -> bool:
	return not info.get("lobs", []).is_empty() and not in_room(from, info)


## True for a point in an asset's room: under IN_ROOM above its foot and
## within ROOM_REACH of it across the ground.
static func in_room(from: Vector3, info: Dictionary) -> bool:
	var foot: Vector3 = info.foot
	return from.y < foot.y + IN_ROOM and Vector2(from.x - foot.x, from.z - foot.z).length() < ROOM_REACH


## Where to shoot an asset from a point: the nearest floor point under an
## opening when lobbing, else its middle.
static func asset_aim(from: Vector3, info: Dictionary) -> Vector3:
	if not lobbing(from, info):
		return info.centre
	var lobs: Array = info.lobs
	var best: Vector3 = lobs[0]
	for at: Vector3 in lobs:
		if at.distance_to(from) < best.distance_to(from):
			best = at
	return best


## The carried weapon best for shooting a base asset this far from the eye,
## or -1 if none can. lob is for shooting a generator's room floor.
static func pick_asset_weapon(brain: BotBrain, distance: float, lob := false) -> int:
	var s := brain.soldier
	var best := -1
	var best_score := 0.0
	for slot in s.weapons:
		var score := asset_weapon_score(brain, slot, distance, lob)
		if score > best_score:
			best_score = score
			best = slot
	return best


## How well a weapon suits a base asset at this distance, higher is better
## and 0 for one it can't or shouldn't fire. Assets stand still, so the
## splash weapons do best.
static func asset_weapon_score(brain: BotBrain, slot: int, distance: float, lob := false) -> float:
	var s := brain.soldier
	if not s.loaded(slot):
		return 0.0
	if lob:
		# Down through an opening to the floor, where only the blast reaches
		# the generator.
		if distance > LOB_REACH:
			return 0.0
		match slot:
			Weapon.MORTAR:
				return 90.0
			Weapon.GRENADE_LAUNCHER:
				return 80.0
			Weapon.DISC:
				return 70.0
		return 0.0
	match slot:
		Weapon.MORTAR:
			return 90.0 if distance > MORTAR_MIN and distance < MORTAR_RANGE else 0.0
		Weapon.DISC:
			return 70.0 if distance > DISC_MIN and distance < disc_range(brain) else 0.0
		Weapon.GRENADE_LAUNCHER:
			return 65.0 if distance > 10.0 and distance < GRENADE_RANGE else 0.0
		Weapon.PLASMA:
			return 55.0 if distance > 6.0 and distance < PLASMA_RANGE else 0.0
		Weapon.CHAINGUN:
			return (75.0 if distance < DISC_MIN else 50.0) if distance < CHAIN_RANGE else 0.0
		Weapon.BLASTER:
			if s.energy < Weapon.all[slot].energy_per_shot + jet_reserve(brain):
				return 0.0
			return 40.0 if distance < BLASTER_RANGE else 0.0
		Weapon.SNIPER:
			return 30.0 if distance > 30.0 and distance < SNIPER_RANGE and s.energy >= SNIPER_ENERGY else 0.0
	return 0.0


## Main thread, before work(), on the ticks the bot looks: checks with a ray
## from the eye that nothing but the asset is in the way, the world and the
## asset team's force fields. Keeps the last answer when the tick's rays are
## used up.
func look_at_asset(brain: BotBrain) -> void:
	if asset_id == 0:
		asset_seen = 0
		return
	var machine := brain.game.asset(asset_id)
	if machine == null or machine.destroyed:
		asset_seen = 0
		return
	if not brain.director.take_ray():
		return
	var blocks := Match.WORLD_LAYER
	var eye := brain.soldier.eye_transform().origin
	var info := brain.director.asset_info(asset_id)
	var aim := asset_aim(eye, info) if not info.is_empty() else machine.centre()
	asset_seen = asset_id if brain.game.world_ray(eye, aim, blocks).is_empty() else 0


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
		var info := brain.director.asset_info(asset_id) if asset_id != 0 else {}
		if info.is_empty() or info.destroyed:
			asset_id = 0
			aiming = false
			return
		_apply_asset(brain, command, delta, info)
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
	_turn(brain, command, delta, want_yaw, want_pitch)

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


## Turns the look towards a yaw and pitch at the bot's turn rate, and turns
## the steering's command with it. The push stays the same in the world.
func _turn(brain: BotBrain, command: PlayerCommand, delta: float, want_yaw: float, want_pitch: float) -> void:
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
	command.weapon = brain.soldier.carried(weapon)


## Aims at a base asset's middle and fires once the aim is on it, it's in
## range and the last look had a clear line to it. It stands still, so there's
## no lead.
func _apply_asset(brain: BotBrain, command: PlayerCommand, delta: float, info: Dictionary) -> void:
	var s := brain.soldier
	if not aiming:
		aim_yaw = s.yaw
		aim_pitch = s.pitch
		aiming = true
	var eye := s.eye_transform().origin
	var w := Weapon.all[weapon]
	var lob := lobbing(eye, info)
	var to: Vector3 = asset_aim(eye, info) - eye
	var want_yaw := atan2(-to.x, -to.z) + aim_error.x
	var want_pitch := aim_error.y + (lob_pitch(to, w) if w.gravity > 0.0 else atan2(to.y, Vector2(to.x, to.z).length()))
	_turn(brain, command, delta, want_yaw, want_pitch)
	if asset_seen != asset_id or s.weapon_slot() != weapon:
		return
	var distance := to.length()
	var off := absf(wrapf(want_yaw - aim_yaw, -PI, PI)) + absf(want_pitch - aim_pitch)
	var tolerance := maxf(atan2(LOB_SPOT if lob else info.radius, distance), 0.02)
	if off > tolerance or asset_weapon_score(brain, weapon, distance, lob) <= 0.0:
		return
	if w.uses_energy() and s.energy < w.energy_per_shot + jet_reserve(brain) and weapon != Weapon.SNIPER:
		return
	# Through an opening the floor's edge shields the shooter from the blast.
	var keep := 0.0 if lob else self_blast_range(weapon) * (1.0 if s.health > LOW_HEALTH else 1.5)
	if lob and s.cooldown > 0.0:
		return
	if keep > 0.0:
		if s.cooldown > 0.0 or distance < keep:
			return
		var forward := -Basis.from_euler(Vector3(aim_pitch, aim_yaw, 0.0)).z
		brain.check_disc(eye, eye + forward * minf(DISC_MIN, distance - info.radius - 0.5))
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
static func lead(eye: Vector3, shooter_velocity: Vector3, at: Vector3, velocity: Vector3, fall: float, w: Weapon, inherit_override := -1.0) -> Vector3:
	var inherit := w.inherit if inherit_override < 0.0 else inherit_override
	var relative := velocity - shooter_velocity * inherit
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
		"asset_id": asset_id,
		"asset_seen": asset_seen,
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
	asset_id = state.get("asset_id", 0)
	asset_seen = state.get("asset_seen", 0)
