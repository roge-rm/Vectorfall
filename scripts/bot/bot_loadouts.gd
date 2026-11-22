class_name BotLoadouts
extends RefCounted

## The loadouts bots wear for each role, all in one place. A role has one or
## more kits to choose from, a personality narrows them, and the bot's own
## random numbers pick one the first time it plays that role, which it keeps.

const A := SoldierBody.Armour
const R := BotBrain.Role
const P := BotBrain.Personality

## Kits, as indexes into KITS.
enum Kit { RUNNER_BLASTER, RUNNER_GRENADES, MEDIUM_SHIELD, MEDIUM_AMMO, MEDIUM_REPAIR, HEAVY_SHIELD, HEAVY_REPAIR, LIGHT_CHASER, SNIPER, RUNNER_JAMMER }
const KIT_NAMES: Array[String] = ["runner", "runner grenades", "medium shield", "medium ammo", "medium repair", "heavy shield", "heavy repair", "chaser", "sniper", "runner jammer"]
## Each kit as [armour, weapons in carry order, pack].
const KITS: Array = [
	[A.LIGHT, [Weapon.DISC, Weapon.BLASTER], Pack.ENERGY],
	[A.LIGHT, [Weapon.DISC, Weapon.GRENADE_LAUNCHER], Pack.ENERGY],
	[A.MEDIUM, [Weapon.DISC, Weapon.CHAINGUN, Weapon.PLASMA], Pack.SHIELD],
	[A.MEDIUM, [Weapon.DISC, Weapon.CHAINGUN, Weapon.PLASMA], Pack.AMMO],
	[A.MEDIUM, [Weapon.DISC, Weapon.CHAINGUN, Weapon.PLASMA], Pack.REPAIR],
	[A.HEAVY, [Weapon.DISC, Weapon.CHAINGUN, Weapon.MORTAR, Weapon.GRENADE_LAUNCHER], Pack.SHIELD],
	[A.HEAVY, [Weapon.DISC, Weapon.CHAINGUN, Weapon.MORTAR, Weapon.GRENADE_LAUNCHER], Pack.REPAIR],
	[A.LIGHT, [Weapon.DISC, Weapon.CHAINGUN], Pack.ENERGY],
	[A.LIGHT, [Weapon.DISC, Weapon.SNIPER], Pack.JAMMER],
	[A.LIGHT, [Weapon.DISC, Weapon.CHAINGUN], Pack.JAMMER],
]


## The kits a bot in a role with a personality chooses between.
static func choices(role: int, personality: int, ctf := false) -> Array[int]:
	match role:
		R.OFFENCE:
			# Runners are light for speed; careful ones go medium.
			if personality == P.CAREFUL:
				return [Kit.MEDIUM_SHIELD, Kit.MEDIUM_AMMO]
			if personality == P.AGGRESSIVE:
				return [Kit.RUNNER_BLASTER, Kit.RUNNER_GRENADES]
			if ctf:
				return [Kit.RUNNER_BLASTER, Kit.RUNNER_GRENADES, Kit.RUNNER_JAMMER, Kit.MEDIUM_SHIELD]
			return [Kit.RUNNER_BLASTER, Kit.RUNNER_GRENADES, Kit.MEDIUM_SHIELD]
		R.ESCORT:
			return [Kit.MEDIUM_SHIELD, Kit.MEDIUM_AMMO]
		R.GENERATOR:
			# Heavies, for the mortar and grenades on a still target.
			return [Kit.HEAVY_SHIELD]
		R.MIDFIELD:
			if personality == P.SNIPER:
				return [Kit.SNIPER]
			if personality == P.CAREFUL:
				return [Kit.MEDIUM_REPAIR]
			return [Kit.MEDIUM_SHIELD, Kit.MEDIUM_AMMO]
		R.DEFENCE:
			if personality == P.CAREFUL:
				return [Kit.HEAVY_REPAIR]
			if personality == P.AGGRESSIVE:
				return [Kit.HEAVY_SHIELD]
			return [Kit.HEAVY_SHIELD, Kit.HEAVY_REPAIR]
		R.LIGHT_DEFENCE:
			# A sniper watches the lanes with the rifle.
			if personality == P.SNIPER:
				return [Kit.SNIPER]
			return [Kit.LIGHT_CHASER]
		R.CHASE:
			return [Kit.LIGHT_CHASER]
		R.SNIPER:
			return [Kit.SNIPER]
		R.REPAIR:
			return [Kit.MEDIUM_REPAIR]
	return [Kit.MEDIUM_SHIELD]


## A kit's loadout, with full grenades and mines.
static func loadout(kit: int) -> Loadout:
	var k: Array = KITS[kit]
	var weapons: Array[int] = []
	weapons.assign(k[1])
	return Loadout.make(k[0], weapons, k[2])


## Picks one of the choices with rng.
static func pick(role: int, personality: int, rng: RandomNumberGenerator, ctf := false) -> int:
	var options := choices(role, personality, ctf)
	return options[rng.randi_range(0, options.size() - 1)] if options.size() > 1 else options[0]


## A short line on a loadout for the debug overlay: armour, weapons and pack.
static func describe(worn: Loadout, pack_on: bool) -> String:
	var names: Array[String] = []
	for slot in worn.weapons:
		names.append(Weapon.all[slot].short_name)
	var pack := Pack.get_pack(worn.pack)
	var pack_text := "" if pack == null else ", %s%s" % [pack.short_name, " on" if pack_on else ""]
	return "%s %s%s" % [["light", "medium", "heavy"][worn.armour], " ".join(names), pack_text]
