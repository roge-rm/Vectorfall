class_name OnlineClient
extends Node

signal failed(reason: String)
signal ready_to_play

const STEP := 1.0 / 60.0
const HISTORY := 120

static var active: OnlineClient
static var last_error := ""

var link := MatchTransport.new()
var round_id := 0
var initial: Dictionary = {}
var map_name := ""
var minutes := 20
var captures := 5
var player_id := 0
var latest: Dictionary = {}
var latest_ack := 0
var messages: Array = []
var sequence := 0
var commands: Array = []
var deadline := 0
var started := false
var last_packet := 0


func start(address: String, port: int, websocket: bool) -> Error:
	link.received.connect(_receive)
	link.joined.connect(func(_id: int) -> void:
		link.send(1, MatchProtocol.encode({"kind": "join", "team": -1}), 0, true))
	link.left.connect(func(_id: int) -> void: _fail("Disconnected from the server."))
	deadline = Time.get_ticks_msec() + MatchTransport.TIMEOUT_MS
	return link.connect_to(address, port, websocket)


func _process(_delta: float) -> void:
	link.poll()
	var now := Time.get_ticks_msec()
	if not started and now > deadline:
		_fail("The server did not answer.")
	elif started and now - last_packet > MatchTransport.TIMEOUT_MS:
		_fail("The connection timed out.")


func _receive(_id: int, packet: PackedByteArray) -> void:
	var message := MatchProtocol.decode(packet, MatchProtocol.SNAPSHOT_MAX)
	if message.is_empty():
		return
	last_packet = Time.get_ticks_msec()
	if message.get("kind") == "reject":
		_fail(str(message.get("reason", "Could not join.")))
		return
	var number: Variant = message.get("round")
	if not number is int or number < round_id:
		return
	match message.get("kind"):
		"welcome":
			if number <= round_id or message.get("map") not in GameMap.NAMES:
				return
			var state := _unpack(message)
			var id: Variant = message.get("player")
			if state.is_empty() or not id is int or not state.entities.has(id):
				return
			round_id = number
			player_id = id
			map_name = message.map
			minutes = int(message.get("minutes", 20))
			captures = int(message.get("captures", 5))
			initial = state
			latest.clear()
			commands.clear()
			messages.clear()
			sequence = 0
			latest_ack = 0
			started = true
			ready_to_play.emit()
		"state":
			if not started or number != round_id:
				return
			var state := _unpack(message)
			if state.is_empty() or state.tick <= maxi(initial.tick, latest.get("tick", 0)):
				return
			latest = state
			latest_ack = clampi(int(message.get("ack", 0)), latest_ack, sequence)
		"events":
			if number == round_id and message.get("events") is Array:
				if messages.size() < 32 and message.get("tick") is int:
					messages.append(message)


func _unpack(message: Dictionary) -> Dictionary:
	var compressed: Variant = message.get("state")
	if not compressed is PackedByteArray:
		return {}
	var raw: PackedByteArray = compressed.decompress_dynamic(512 * 1024, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() < 8:
		return {}
	var value: Variant = bytes_to_var(raw)
	if value is Dictionary and value.get("tick") is int and value.get("entities") is Dictionary:
		return value
	return {}


func arena_ready() -> void:
	last_packet = Time.get_ticks_msec()
	link.send(1, MatchProtocol.encode({"kind": "ready", "round": round_id}), 0, true)


func submit(command: PlayerCommand) -> void:
	sequence += 1
	commands.append([sequence, command.to_dict()])
	if commands.size() > HISTORY:
		commands.pop_front()
	# Repeat recent inputs so a lost UDP packet does not lose a button press.
	link.send(1, MatchProtocol.encode({"kind": "input", "round": round_id,
		"commands": commands.slice(maxi(0, commands.size() - 3))}), 2)


func pending() -> Array:
	while not commands.is_empty() and commands.front()[0] <= latest_ack:
		commands.pop_front()
	return commands


func _fail(reason: String) -> void:
	if is_queued_for_deletion():
		return
	var in_match := started
	stop()
	if in_match:
		last_error = reason
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
	else:
		failed.emit(reason)


func stop() -> void:
	if active == self:
		active = null
	link.close()
	queue_free()


func _exit_tree() -> void:
	if active == self:
		active = null
	link.close()
