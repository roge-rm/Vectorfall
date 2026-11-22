class_name RemoteCommands
extends CommandSource

# Keep a few ticks to absorb jitter, and stop held input if its sender stalls.
var pending: Array[PlayerCommand] = []
var sequences: Array[int] = []
var applied := 0
var received := 0
var last := PlayerCommand.new()
var stale := 0


func offer(sequence: int, value: PlayerCommand) -> void:
	if sequence <= received:
		return
	received = sequence
	pending.append(value)
	sequences.append(sequence)
	if pending.size() > MatchProtocol.COMMANDS_MAX:
		pending.pop_front()
		sequences.pop_front()


func make_command(_delta: float) -> PlayerCommand:
	if not pending.is_empty():
		last = pending.pop_front()
		applied = sequences.pop_front()
		stale = 0
		return last
	stale += 1
	var held := PlayerCommand.new()
	held.yaw = last.yaw
	held.pitch = last.pitch
	if stale <= 8:
		held.move = last.move
		held.buttons = last.buttons & (MatchProtocol.MOVEMENT | PlayerCommand.FIRE | PlayerCommand.USE)
	return held
