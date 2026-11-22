class_name PlayerCommand
extends RefCounted

## What a soldier wants to do for one physics tick. Input devices, bots and
## later the network only make these; soldiers only move from them.

const FIRE := 1
const JUMP := 2
const JET := 4
const USE := 8
const DEPLOY := 16
## Held to ski: next to no friction on the ground, so slopes speed you up.
const SKI := 32
## Switch to the next or previous weapon. Input sources send each of these for
## one tick per press, and a soldier switches once for every tick it's set.
const NEXT_WEAPON := 64
const PREV_WEAPON := 128
## Held to throw a hand grenade or place a mine. One throw per press.
const GRENADE := 256
const MINE := 512
const BOARD := 1024

## x is right and y is forward, length at most 1.
var move := Vector2.ZERO
## Absolute look angles in radians. Yaw turns left as it grows, like Godot's
## rotation.y, and pitch looks up as it grows.
var yaw := 0.0
var pitch := 0.0
var buttons := 0
## An optional specific hull to board. Zero boards the nearest one.
var board_id := 0
## Index in the soldier's carried weapons to switch to, or -1 to keep the
## current one.
var weapon := -1
## An order to the team's bots (Orders.Kind), sent for one tick, and what it's
## about, such as the bot and role for Orders.Kind.SET_ROLE.
var order := 0
var order_arg := 0
var order_point := Vector2.ZERO
## A loadout the soldier wants (Loadout.to_dict()), sent for one tick when it
## changes, or empty. It's worn at the next respawn, or at once on a station.
var loadout: Dictionary = {}


func has(button: int) -> bool:
	return buttons & button != 0


func duplicate() -> PlayerCommand:
	return PlayerCommand.from_dict(to_dict())


func to_dict() -> Dictionary:
	var data := { "move": move, "yaw": yaw, "pitch": pitch, "buttons": buttons, "board_id": board_id, "weapon": weapon, "order": order, "order_arg": order_arg, "loadout": loadout.duplicate(true) }
	if order == Orders.Kind.WAYPOINT:
		data["order_point"] = order_point
	return data


static func from_dict(data: Dictionary) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.move = data.get("move", Vector2.ZERO)
	command.yaw = data.get("yaw", 0.0)
	command.pitch = data.get("pitch", 0.0)
	command.buttons = data.get("buttons", 0)
	command.board_id = data.get("board_id", 0)
	command.weapon = data.get("weapon", -1)
	command.order = data.get("order", 0)
	command.order_arg = data.get("order_arg", 0)
	command.order_point = data.get("order_point", Vector2.ZERO)
	command.loadout = data.get("loadout", {}).duplicate(true)
	return command
