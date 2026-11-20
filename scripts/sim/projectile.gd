class_name Projectile
extends RefCounted

## A shot in flight, moved by Match.step() each tick. Plain data, so a match
## can hold hundreds without a node each.

var id := 0
var weapon := 0
## Entity id of the soldier or turret that fired it.
var shooter := 0
var team := 0
var position := Vector3.ZERO
var velocity := Vector3.ZERO
## Seconds since it was fired. A weapon with a fuse blows up when it
## reaches the fuse.
var age := 0.0
## Damage on a direct hit, set when fired.
var damage := 0.0
## Bounces off the world left, -1 for any number.
var bounces_left := 0
## From the shooter's eye, where the shot really starts, to the gun's muzzle.
## The visual starts at the muzzle and closes onto the real path.
var muzzle_offset := Vector3.ZERO

const OFFSET_FADE := 0.12


## Where to draw it: the real position plus a muzzle offset that fades out.
func visual_position() -> Vector3:
	return position + muzzle_offset * maxf(1.0 - age / OFFSET_FADE, 0.0)


func get_state() -> Dictionary:
	return {
		"id": id,
		"weapon": weapon,
		"shooter": shooter,
		"team": team,
		"position": position,
		"velocity": velocity,
		"age": age,
		"damage": damage,
		"bounces_left": bounces_left,
		"muzzle_offset": muzzle_offset,
	}


static func from_state(state: Dictionary) -> Projectile:
	var shot := Projectile.new()
	shot.id = state.id
	shot.weapon = state.weapon
	shot.shooter = state.shooter
	shot.team = state.team
	shot.position = state.position
	shot.velocity = state.velocity
	shot.age = state.age
	shot.damage = state.get("damage", 0.0)
	shot.bounces_left = state.get("bounces_left", 0)
	shot.muzzle_offset = state.muzzle_offset
	return shot
