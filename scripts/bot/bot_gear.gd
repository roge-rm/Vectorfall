class_name BotGear
extends RefCounted

## A bot's pack and mines. Repair: held on itself when hurt and out of a
## fight, on a hurt teammate close by, person or bot, which it walks up to
## and looks at, or on the base asset a repair bot was sent to. Shield: on in a fight while the energy lasts, off otherwise.
## Jammer: on while carrying a flag, and for a sniper while it isn't
## shooting. Defence lays a few mines towards the flag's approaches while it
## stands guard. Runs in BotBrain.work(), so it reads only snapshotted
## soldiers and plain fields.

## Repairs itself below this share of its health, and stops when full.
const SELF_REPAIR := 0.7
## Goes to repair a teammate below this share of its health within
## MATE_RANGE metres, and stands this close to do it.
const MATE_HURT := 0.6
const MATE_RANGE := 30.0
const MATE_HOLD := 2.5
## A teammate this close is in reach of the repair beam, in metres; the
## pack's own reach is 4 m from the eye.
const MATE_REACH := 3.5
## Energy kept back for the jets on top of what a pack uses, and the energy a
## shield needs to come on.
const PACK_RESERVE := 25.0
const SHIELD_ON := 45.0
## Energy a sniper's jammer needs to come on, and goes off below.
const JAM_ON := 70.0
const JAM_OFF := 35.0
## Mines a bot lays each life, and seconds between them.
const MINES_PER_LIFE := 2
const MINE_GAP := 8.0
## Look pitch for laying a mine, a short lob ahead, in radians.
const MINE_PITCH := 0.2

## The teammate it's going to repair, or 0.
var mate_id := 0
var mines_laid := 0
var next_mine_tick := 0


func reset() -> void:
	mate_id = 0
	mines_laid = 0


## Picks a hurt teammate to repair, if it carries a repair pack and isn't in
## a fight. Called when the bot thinks.
func think(brain: BotBrain) -> void:
	var s := brain.soldier
	mate_id = 0
	if s.loadout.pack != Pack.REPAIR or brain.combat.fighting(brain) or s.energy < PACK_RESERVE + 10.0:
		return
	if brain.game.carried_flag(s.entity_id) != null:
		return
	var best := MATE_RANGE
	for other in brain.director.soldiers():
		if other == s or other.dead or other.team != s.team:
			continue
		if other.health >= other.tuning.health_max * MATE_HURT:
			continue
		var distance := other.at().distance_to(s.at())
		if distance < best:
			best = distance
			mate_id = other.entity_id


## Adds the pack button and mines to this tick's command, after the fight
## has turned the look.
func apply(brain: BotBrain, command: PlayerCommand) -> void:
	var s := brain.soldier
	_use_pack(brain, command)
	if not brain.combat.aiming and s.mines > 0 and not command.has(PlayerCommand.GRENADE):
		_lay_mine(brain, command)


func _use_pack(brain: BotBrain, command: PlayerCommand) -> void:
	var s := brain.soldier
	var p := s.pack()
	if p == null or p.use == Pack.Use.ALWAYS:
		return
	var fighting := brain.combat.fighting(brain)
	var want := false
	match s.loadout.pack:
		Pack.REPAIR:
			want = _repair(brain, command, fighting)
		Pack.SHIELD:
			# Kept on until the energy gets down to what the jets need.
			want = fighting and s.energy > (PACK_RESERVE if s.pack_on else SHIELD_ON)
		Pack.JAMMER:
			if brain.game.carried_flag(s.entity_id) != null:
				want = s.energy > 5.0
			elif s.weapons.has(Weapon.SNIPER):
				want = not fighting and s.energy > (JAM_OFF if s.pack_on else JAM_ON)
	if p.use == Pack.Use.HOLD:
		if want:
			command.buttons |= PlayerCommand.USE
	elif want != s.pack_on and not s.use_held:
		# One press toggles it; the next tick lets go.
		command.buttons |= PlayerCommand.USE


## True to hold the repair button: on a teammate in reach, which it turns to
## when it isn't aiming, or on itself.
func _repair(brain: BotBrain, command: PlayerCommand, fighting: bool) -> bool:
	var s := brain.soldier
	if fighting or s.energy < PACK_RESERVE * (0.6 if s.pack_on else 1.0):
		return false
	if brain.goal == BotBrain.Goal.FIX and not brain.combat.aiming:
		# The base asset it was sent to, once it's in reach.
		var info := brain.director.asset_info(brain.role_target)
		if not info.is_empty() and info.health < info.max:
			var eye := s.eye_transform().origin
			var to: Vector3 = info.centre - eye
			if Vector2(to.x, to.z).length() < info.radius + MATE_REACH:
				command.yaw = atan2(-to.x, -to.z)
				command.pitch = atan2(to.y, Vector2(to.x, to.z).length())
				return true
	var mate := brain.game.soldier(mate_id) if mate_id != 0 else null
	if mate != null and not mate.dead and mate.health < mate.tuning.health_max and not brain.combat.aiming:
		var eye := s.eye_transform().origin
		var to := mate.at() + Vector3.UP * mate.tuning.height * 0.5 - eye
		if to.length() < MATE_REACH + 1.0:
			command.yaw = atan2(-to.x, -to.z)
			command.pitch = atan2(to.y, Vector2(to.x, to.z).length())
			return true
	if s.health < s.tuning.health_max * (1.0 if s.pack_on else SELF_REPAIR):
		return s.grounded or s.energy > 50.0
	return false


## Defence standing guard lays a mine towards one of the flag's approaches,
## a few each life with a gap between.
func _lay_mine(brain: BotBrain, command: PlayerCommand) -> void:
	var s := brain.soldier
	var game := brain.game
	if brain.role != BotBrain.Role.DEFENCE and brain.role != BotBrain.Role.LIGHT_DEFENCE:
		return
	if brain.goal != BotBrain.Goal.DEFEND or not brain.at_goal or not s.grounded:
		return
	if mines_laid >= MINES_PER_LIFE or game.tick < next_mine_tick or s.mine_held or s.throw_cooldown > 0.0:
		return
	var toward := game.stands[1 - s.team]
	var boss := brain.director.commander(s.team)
	if boss != null and boss.lanes != null and boss.lanes.count > 0:
		toward = boss.lanes.approach(s.team, (brain.role_slot + mines_laid) % boss.lanes.count)
	var to := toward - s.at()
	if Vector2(to.x, to.z).length() < 5.0:
		to = game.stands[1 - s.team] - s.at()
	command.yaw = atan2(-to.x, -to.z)
	command.pitch = MINE_PITCH
	command.buttons |= PlayerCommand.MINE
	mines_laid += 1
	next_mine_tick = game.tick + int(MINE_GAP * 60.0)


func get_state() -> Dictionary:
	return { "mate_id": mate_id, "mines_laid": mines_laid, "next_mine_tick": next_mine_tick }


func set_state(state: Dictionary) -> void:
	mate_id = state.get("mate_id", 0)
	mines_laid = state.get("mines_laid", 0)
	next_mine_tick = state.get("next_mine_tick", 0)
