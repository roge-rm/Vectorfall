class_name Loadout
extends RefCounted

## What a soldier carries: an armour, weapons in carry order, a pack and how
## many hand grenades and mines. fixed() trims one to what its armour allows.

const Armour := SoldierBody.Armour
## No pack.
const NO_PACK := -1
## Weapons each armour can carry.
const SLOTS: Dictionary[int, int] = { Armour.LIGHT: 2, Armour.MEDIUM: 3, Armour.HEAVY: 4 }
## Most hand grenades and mines each armour can carry.
const GRENADES: Dictionary[int, int] = { Armour.LIGHT: 3, Armour.MEDIUM: 4, Armour.HEAVY: 5 }
const MINES: Dictionary[int, int] = { Armour.LIGHT: 2, Armour.MEDIUM: 3, Armour.HEAVY: 4 }

var armour: int = Armour.MEDIUM
## Weapon slots (indexes into Weapon.all), in the order they're carried.
var weapons: Array[int] = []
var pack := NO_PACK
var grenades := 0
var mines := 0


## Medium armour with the disc launcher and chaingun, and full grenades and
## mines.
static func standard() -> Loadout:
	return make(Armour.MEDIUM, [Weapon.DISC, Weapon.CHAINGUN])


## A loadout with full grenades and mines for its armour, trimmed to fit.
static func make(with_armour: int, with_weapons: Array[int], with_pack := NO_PACK) -> Loadout:
	var loadout := Loadout.new()
	loadout.armour = with_armour
	loadout.weapons = with_weapons.duplicate()
	loadout.pack = with_pack
	loadout.grenades = GRENADES.get(with_armour, 0)
	loadout.mines = MINES.get(with_armour, 0)
	return loadout.fixed()


## True if an armour may carry a weapon.
static func allows(on_armour: int, slot: int) -> bool:
	return slot >= 0 and slot < Weapon.all.size() and Weapon.all[slot].armours.has(on_armour)


## True if this loadout is already within what its armour allows.
func valid() -> bool:
	return equals(fixed())


## A copy trimmed to what the armour allows: an unknown armour becomes medium,
## weapons it can't carry and repeats are dropped, extra weapons past its slots
## are cut from the end, an unknown pack is dropped and counts are held to
## its limits. With no weapon left it gets the disc launcher.
func fixed() -> Loadout:
	var out := Loadout.new()
	out.armour = armour if SLOTS.has(armour) else Armour.MEDIUM
	for slot in weapons:
		if out.weapons.size() < SLOTS[out.armour] and allows(out.armour, slot) and not out.weapons.has(slot):
			out.weapons.append(slot)
	if out.weapons.is_empty():
		out.weapons.append(Weapon.DISC)
	out.pack = pack if Pack.get_pack(pack) != null else NO_PACK
	out.grenades = clampi(grenades, 0, GRENADES[out.armour])
	out.mines = clampi(mines, 0, MINES[out.armour])
	return out


func duplicate() -> Loadout:
	return Loadout.from_dict(to_dict())


func equals(other: Loadout) -> bool:
	return other != null and to_dict() == other.to_dict()


func to_dict() -> Dictionary:
	return { "armour": armour, "weapons": weapons.duplicate(), "pack": pack, "grenades": grenades, "mines": mines }


static func from_dict(data: Dictionary) -> Loadout:
	var loadout := Loadout.new()
	var armour: Variant = data.get("armour")
	if armour is int:
		loadout.armour = armour
	var weapons: Variant = data.get("weapons")
	if weapons is Array:
		for slot: Variant in weapons:
			if slot is int:
				loadout.weapons.append(slot)
	var pack: Variant = data.get("pack")
	if pack is int:
		loadout.pack = pack
	var grenades: Variant = data.get("grenades")
	if grenades is int:
		loadout.grenades = grenades
	var mines: Variant = data.get("mines")
	if mines is int:
		loadout.mines = mines
	return loadout
