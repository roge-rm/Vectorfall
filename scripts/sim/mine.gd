class_name Mine
extends RefCounted

## A mine stuck to the world, kept in Match.mines and changed only by
## Match.step(). Plain data like Projectile.

var id := 0
## Entity id of the soldier who placed it. It stays when they die.
var owner_id := 0
var team := 0
var position := Vector3.ZERO
## The surface's normal where it landed.
var normal := Vector3.UP
## Seconds until it's armed and enemies can set it off.
var arm_in := 0.0
## Seconds since it landed, for the blink.
var age := 0.0


func armed() -> bool:
	return arm_in <= 0.0


func get_state() -> Dictionary:
	return {
		"id": id,
		"owner": owner_id,
		"team": team,
		"position": position,
		"normal": normal,
		"arm_in": arm_in,
		"age": age,
	}


static func from_state(state: Dictionary) -> Mine:
	var mine := Mine.new()
	mine.id = state.id
	mine.owner_id = state.owner
	mine.team = state.team
	mine.position = state.position
	mine.normal = state.normal
	mine.arm_in = state.arm_in
	mine.age = state.age
	return mine
