class_name Weapon
extends RefCounted

## One weapon's numbers, in metres, seconds and health points. Every weapon is
## set up in make_all(), so the numbers are all in one place.

## Slot numbers, also the index into Weapon.all.
const DISC := 0
const CHAINGUN := 1

static var all: Array[Weapon] = make_all()

var slot := 0
var name := ""
## A short name for the kill feed and HUD.
var short_name := ""

## Damage to a soldier the projectile hits head on. That soldier takes no
## splash damage on top.
var damage := 0.0
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
var ammo := 0


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
	return list


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
