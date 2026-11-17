class_name PlayerCommand
extends RefCounted

## What a soldier wants to do for one physics tick. Input devices, bots and
## later the network only make these; soldiers only move from them.

const FIRE := 1
const JUMP := 2
const JET := 4
const USE := 8
const DEPLOY := 16

## x is right and y is forward, length at most 1.
var move := Vector2.ZERO
## Absolute look angles in radians. Yaw turns left as it grows, like Godot's
## rotation.y, and pitch looks up as it grows.
var yaw := 0.0
var pitch := 0.0
var buttons := 0


func has(button: int) -> bool:
	return buttons & button != 0


func duplicate() -> PlayerCommand:
	return PlayerCommand.from_dict(to_dict())


func to_dict() -> Dictionary:
	return { "move": move, "yaw": yaw, "pitch": pitch, "buttons": buttons }


static func from_dict(data: Dictionary) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.move = data.get("move", Vector2.ZERO)
	command.yaw = data.get("yaw", 0.0)
	command.pitch = data.get("pitch", 0.0)
	command.buttons = data.get("buttons", 0)
	return command
