class_name CommandSource
extends RefCounted

## Makes one PlayerCommand per physics tick for a soldier. This one stands
## still and keeps looking where it was told; input devices and bots extend it.

var yaw := 0.0
var pitch := 0.0


func make_command(_delta: float) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.yaw = yaw
	command.pitch = pitch
	return command


## What it needs to carry on the same after a match's set_state(), for those
## that keep any. Bots keep their goal, route and memory here.
func get_state() -> Dictionary:
	return {}


func set_state(_state: Dictionary) -> void:
	pass
