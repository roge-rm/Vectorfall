class_name Weapon
extends RefCounted

## One weapon's numbers, in metres, seconds and health points. Every weapon is
## set up in make_all(), so the numbers are all in one place.

## Slot numbers, also the index into Weapon.all.
const DISC := 0
const CHAINGUN := 1
const GRENADE_LAUNCHER := 2
const MORTAR := 3
const PLASMA := 4
const SNIPER := 5
const BLASTER := 6
## Thrown, not carried: hand grenades and mines have their own counts and
## buttons, and entries here so shots, blasts and the kill feed treat them
## like any other weapon.
const HAND_GRENADE := 7
const MINE := 8
## A base turret's plasma shot, fired by Match for a BaseAsset, never carried.
const TURRET := 9
## Slots below this are guns a loadout can carry.
const GUNS := 7

static var all: Array[Weapon] = make_all()

var slot := 0
var name := ""
## A short name for the kill feed and HUD.
var short_name := ""

## Damage to a soldier the projectile hits head on. That soldier takes no
## splash damage on top. A weapon with splash and no direct damage blows up
## on the soldier it hits, who takes the splash like everyone else.
var damage := 0.0
## For a weapon that scales its damage with energy: the damage with only
## energy_per_shot left, rising to damage at full energy.
var min_damage := 0.0
## Splash damage at the centre of the blast, falling off in a straight line
## to splash_edge_share of it at splash_radius, and none past it.
var splash_damage := 0.0
var splash_radius := 0.0
var splash_edge_share := 0.2
## Push at the centre of the blast in kg·m/s, falling off to nothing at
## splash_radius. On a 90 kg soldier 1400 is a 15.6 m/s kick.
var splash_impulse := 0.0
## Push in kg·m/s on a soldier hit by a projectile with no splash.
var hit_impulse := 0.0
## Share of damage you take from your own shots.
var self_damage_share := 1.0

## Muzzle speed in m/s.
var speed := 0.0
## Downward pull on the projectile in m/s².
var gravity := 0.0
## Share of speed lost per second.
var drag := 0.0
## Share of the shooter's velocity added to the projectile's.
var inherit := 0.0
## Seconds before the projectile is gone if it hits nothing.
var lifetime := 5.0
## Half angle of the random cone shots go out in, in radians.
var spread := 0.0

## Seconds between shots, at full spin for a weapon that spins up.
var fire_interval := 1.0
## Seconds between shots when it has only just spun up enough to fire.
var slow_interval := 0.0
## Seconds to spin up from still to full, 0 for no spin up.
var spin_up := 0.0
## Seconds to spin down from full to still.
var spin_down := 0.0
## Spin share needed before it fires.
var spin_to_fire := 0.0
## Rounds carried, 0 for a weapon that runs on energy.
var ammo := 0
## Energy each shot takes, 0 for a weapon with ammo. It won't fire with less.
var energy_per_shot := 0.0
## Times a shot bounces off the world before the next hit stops it, -1 for
## any number of times.
var bounces := 0
## Share of speed a shot keeps on each bounce.
var bounce_keep := 1.0
## Seconds after firing that a shot blows up by itself, 0 for never. A shot
## with a fuse blows up at the end of its lifetime.
var fuse := 0.0
## Armours that can carry it, as SoldierBody.Armour values.
var armours: Array[int] = [SoldierBody.Armour.LIGHT, SoldierBody.Armour.MEDIUM, SoldierBody.Armour.HEAVY]


static func make_all() -> Array[Weapon]:
	var list: Array[Weapon] = []

	var disc := Weapon.new()
	disc.slot = DISC
	disc.name = "Disc launcher"
	disc.short_name = "DISC"
	disc.damage = 55.0
	disc.splash_damage = 45.0
	disc.splash_radius = 7.0
	disc.splash_edge_share = 0.2
	disc.splash_impulse = 1400.0
	disc.self_damage_share = 0.35
	disc.speed = 65.0
	disc.gravity = 0.0
	disc.drag = 0.0
	disc.inherit = 0.85
	disc.lifetime = 6.0
	disc.fire_interval = 1.1
	disc.ammo = 15
	list.append(disc)

	var chaingun := Weapon.new()
	chaingun.slot = CHAINGUN
	chaingun.name = "Chaingun"
	chaingun.short_name = "CHAIN"
	chaingun.damage = 6.0
	chaingun.hit_impulse = 25.0
	chaingun.speed = 400.0
	chaingun.gravity = 4.0
	chaingun.drag = 0.0
	chaingun.inherit = 0.25
	chaingun.lifetime = 1.5
	chaingun.spread = 0.03
	chaingun.fire_interval = 0.075
	chaingun.slow_interval = 0.2
	chaingun.spin_up = 0.5
	chaingun.spin_down = 1.0
	chaingun.spin_to_fire = 0.3
	chaingun.ammo = 300
	list.append(chaingun)

	var grenades := Weapon.new()
	grenades.slot = GRENADE_LAUNCHER
	grenades.name = "Grenade launcher"
	grenades.short_name = "GREN"
	grenades.splash_damage = 40.0
	grenades.splash_radius = 6.0
	grenades.splash_edge_share = 0.2
	grenades.splash_impulse = 900.0
	grenades.self_damage_share = 0.5
	grenades.speed = 40.0
	grenades.gravity = 20.0
	grenades.inherit = 0.5
	grenades.bounces = -1
	grenades.bounce_keep = 0.5
	grenades.fuse = 2.0
	grenades.lifetime = 2.0
	grenades.fire_interval = 0.8
	grenades.ammo = 20
	list.append(grenades)

	var mortar := Weapon.new()
	mortar.slot = MORTAR
	mortar.name = "Mortar"
	mortar.short_name = "MORTAR"
	mortar.splash_damage = 100.0
	mortar.splash_radius = 12.0
	mortar.splash_edge_share = 0.2
	mortar.splash_impulse = 2500.0
	mortar.self_damage_share = 0.5
	mortar.speed = 35.0
	mortar.gravity = 18.0
	mortar.inherit = 0.5
	mortar.bounces = -1
	mortar.bounce_keep = 0.5
	mortar.fuse = 3.0
	mortar.lifetime = 3.0
	mortar.fire_interval = 1.8
	mortar.ammo = 10
	mortar.armours = [SoldierBody.Armour.HEAVY]
	list.append(mortar)

	var plasma := Weapon.new()
	plasma.slot = PLASMA
	plasma.name = "Plasma gun"
	plasma.short_name = "PLASMA"
	plasma.damage = 35.0
	plasma.splash_damage = 20.0
	plasma.splash_radius = 3.0
	plasma.splash_edge_share = 0.3
	plasma.splash_impulse = 300.0
	plasma.self_damage_share = 0.5
	plasma.speed = 55.0
	plasma.inherit = 0.5
	plasma.lifetime = 4.0
	plasma.fire_interval = 0.5
	plasma.ammo = 30
	plasma.armours = [SoldierBody.Armour.MEDIUM, SoldierBody.Armour.HEAVY]
	list.append(plasma)

	var sniper := Weapon.new()
	sniper.slot = SNIPER
	sniper.name = "Sniper rifle"
	sniper.short_name = "SNIPER"
	sniper.damage = 75.0
	sniper.min_damage = 20.0
	sniper.hit_impulse = 150.0
	sniper.speed = 1000.0
	sniper.lifetime = 0.4
	sniper.fire_interval = 1.5
	sniper.energy_per_shot = 60.0
	sniper.armours = [SoldierBody.Armour.LIGHT]
	list.append(sniper)

	var blaster := Weapon.new()
	blaster.slot = BLASTER
	blaster.name = "Blaster"
	blaster.short_name = "BLASTER"
	blaster.damage = 12.0
	blaster.hit_impulse = 40.0
	blaster.speed = 150.0
	blaster.inherit = 0.25
	blaster.lifetime = 1.5
	blaster.bounces = 1
	blaster.fire_interval = 0.3
	blaster.energy_per_shot = 4.0
	list.append(blaster)

	var hand_grenade := Weapon.new()
	hand_grenade.slot = HAND_GRENADE
	hand_grenade.name = "Hand grenade"
	hand_grenade.short_name = "HAND GREN"
	hand_grenade.splash_damage = 50.0
	hand_grenade.splash_radius = 7.0
	hand_grenade.splash_edge_share = 0.2
	hand_grenade.splash_impulse = 1500.0
	hand_grenade.self_damage_share = 0.5
	hand_grenade.speed = 20.0
	hand_grenade.gravity = 20.0
	hand_grenade.inherit = 0.5
	hand_grenade.bounces = -1
	hand_grenade.bounce_keep = 0.5
	hand_grenade.fuse = 2.5
	hand_grenade.lifetime = 2.5
	hand_grenade.armours = []
	list.append(hand_grenade)

	# In flight it passes through soldiers and sticks to the world where it
	# lands, then lives in Match.mines.
	var mine := Weapon.new()
	mine.slot = MINE
	mine.name = "Mine"
	mine.short_name = "MINE"
	mine.splash_damage = 70.0
	mine.splash_radius = 6.0
	mine.splash_edge_share = 0.2
	mine.splash_impulse = 1500.0
	mine.self_damage_share = 0.5
	mine.speed = 8.0
	mine.gravity = 20.0
	mine.inherit = 0.5
	mine.lifetime = 10.0
	mine.armours = []
	list.append(mine)

	# Plasma's look and sound with the turret's own numbers. Its short name
	# reads in the kill feed as "Turret plasma Flint".
	var turret := Weapon.new()
	turret.slot = TURRET
	turret.name = "Turret"
	turret.short_name = "PLASMA"
	turret.damage = 25.0
	turret.splash_damage = 10.0
	turret.splash_radius = 2.5
	turret.splash_edge_share = 0.3
	turret.splash_impulse = 250.0
	turret.self_damage_share = 0.0
	turret.speed = 55.0
	turret.lifetime = 1.6
	turret.fire_interval = 0.8
	turret.armours = []
	list.append(turret)
	return list


## True for a weapon that takes energy instead of ammo.
func uses_energy() -> bool:
	return energy_per_shot > 0.0


## Direct hit damage of a shot fired with this much energy out of most. Only
## a weapon with min_damage scales it.
func damage_with(energy: float, energy_max: float) -> float:
	if min_damage <= 0.0 or energy_max <= energy_per_shot:
		return damage
	return lerpf(min_damage, damage, clampf(inverse_lerp(energy_per_shot, energy_max, energy), 0.0, 1.0))


## Splash damage at a distance from the blast.
func splash_damage_at(distance: float) -> float:
	if splash_radius <= 0.0 or distance > splash_radius:
		return 0.0
	return splash_damage * lerpf(1.0, splash_edge_share, distance / splash_radius)


## Splash push in kg·m/s at a distance from the blast.
func splash_impulse_at(distance: float) -> float:
	if splash_radius <= 0.0 or distance > splash_radius:
		return 0.0
	return splash_impulse * (1.0 - distance / splash_radius)


## Seconds to the next shot at this spin.
func interval_at(spin: float) -> float:
	if spin_up <= 0.0:
		return fire_interval
	var share := inverse_lerp(spin_to_fire, 1.0, spin)
	return lerpf(slow_interval, fire_interval, clampf(share, 0.0, 1.0))
