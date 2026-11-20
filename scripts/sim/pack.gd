class_name Pack
extends RefCounted

## One pack's numbers, in metres, seconds, health and energy points. Every
## pack is set up in make_all(), so the numbers are all in one place. A
## loadout carries one, used with PlayerCommand.USE.

## Slot numbers, also the index into Pack.all.
const REPAIR := 0
const SHIELD := 1
const ENERGY := 2
const AMMO := 3
const JAMMER := 4
const TURRET := 5
const SENSOR := 6
const STATION := 7

## A pack can be held, toggled, passive or placed with one press.
enum Use { HOLD, TOGGLE, ALWAYS, DEPLOY }

static var all: Array[Pack] = make_all()

var slot := 0
var name := ""
## A short name for the HUD and loadout screen.
var short_name := ""
var use := Use.ALWAYS
## Energy a second taken while it's on.
var drain := 0.0
## Equipment and team limit for placement packs.
var deploy_kind := BaseAsset.Kind.GENERATOR
var team_limit := 0

## Repair: health a second on yourself, and on a teammate in front of you
## within reach metres.
var self_repair := 0.0
var other_repair := 0.0
var reach := 0.0
## Shield: energy taken for each point of damage it stops.
var energy_per_point := 0.0
## Energy pack: the refill rate times this, the refill delay times
## delay_scale.
var refill_scale := 1.0
var delay_scale := 1.0
## Ammo pack: rounds, hand grenades and mines times this.
var ammo_scale := 1.0
## Jammer: enemy bots don't see you past this many metres.
var jam_sight := 0.0


static func make_all() -> Array[Pack]:
	var list: Array[Pack] = []

	var repair := Pack.new()
	repair.slot = REPAIR
	repair.name = "Repair pack"
	repair.short_name = "REPAIR"
	repair.use = Use.HOLD
	repair.drain = 10.0
	repair.self_repair = 10.0
	repair.other_repair = 15.0
	repair.reach = 4.0
	list.append(repair)

	var shield := Pack.new()
	shield.slot = SHIELD
	shield.name = "Shield pack"
	shield.short_name = "SHIELD"
	shield.use = Use.TOGGLE
	shield.drain = 4.0
	shield.energy_per_point = 2.0
	list.append(shield)

	var energy := Pack.new()
	energy.slot = ENERGY
	energy.name = "Energy pack"
	energy.short_name = "ENERGY"
	energy.refill_scale = 1.4
	energy.delay_scale = 0.5
	list.append(energy)

	var ammo := Pack.new()
	ammo.slot = AMMO
	ammo.name = "Ammo pack"
	ammo.short_name = "AMMO"
	ammo.ammo_scale = 1.5
	list.append(ammo)

	var jammer := Pack.new()
	jammer.slot = JAMMER
	jammer.name = "Sensor jammer"
	jammer.short_name = "JAMMER"
	jammer.use = Use.TOGGLE
	jammer.drain = 5.0
	jammer.jam_sight = 20.0
	list.append(jammer)
	for spec in [
		[TURRET, "Turret pack", "TURRET", BaseAsset.Kind.TURRET, 2],
		[SENSOR, "Sensor pack", "SENSOR", BaseAsset.Kind.SENSOR, 2],
		[STATION, "Station pack", "STATION", BaseAsset.Kind.STATION, 1],
	]:
		var deploy := Pack.new()
		deploy.slot = spec[0]
		deploy.name = spec[1]
		deploy.short_name = spec[2]
		deploy.use = Use.DEPLOY
		deploy.deploy_kind = spec[3]
		deploy.team_limit = spec[4]
		list.append(deploy)
	return list


## The pack in a slot, or null for Loadout.NO_PACK or an unknown slot.
static func get_pack(slot: int) -> Pack:
	return all[slot] if slot >= 0 and slot < all.size() else null


## A count times a pack's ammo scale, for a slot that may be no pack.
static func scaled(count: int, slot: int) -> int:
	var pack := get_pack(slot)
	return roundi(count * pack.ammo_scale) if pack != null else count
