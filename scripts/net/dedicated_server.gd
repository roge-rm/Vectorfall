extends Node

const STEP := 1.0 / 60.0
const SNAPSHOT_TICKS := 4
const BETWEEN_ROUNDS := 12.0
const HUMAN_NAME := "Player"
const EVENT_LIMIT := 64
const LOAD_TIMEOUT_MS := 60000

var link := MatchTransport.new()
var discovery := PacketPeerUDP.new()
var map: GameMap
var game: Match
var director: BotDirector
var assignments: Dictionary[int, BotBrain] = {}
var inputs: Dictionary[int, RemoteCommands] = {}
var active_players: Dictionary[int, bool] = {}
var loading_players: Dictionary[int, int] = {}
var waiting: Dictionary[int, int] = {}
var events: Array = []
var epoch := 0
var rounds_wait := 0.0
var server_name := "Vectorfall"
var map_name := GameMap.DEFAULT
var teams := 8
var minutes := 20
var captures := 5
var hold := false
var resupply := false
var game_port := MatchProtocol.GAME_PORT
var discovery_port := MatchProtocol.DISCOVERY_PORT
var web_port := MatchProtocol.WEB_PORT
var status_dir := ""
var status_ticks := 0
var pending_map := ""


func _ready() -> void:
	server_name = OS.get_environment("VECTORFALL_NAME").strip_edges().left(48)
	if server_name.is_empty():
		server_name = "Vectorfall"
	var wanted := OS.get_environment("VECTORFALL_MAP")
	if GameMap.NAMES.has(wanted):
		map_name = wanted
	hold = OS.get_environment("VECTORFALL_MODE") == "hold"
	resupply = OS.get_environment("VECTORFALL_MIDFIELD_RESUPPLY") == "1"
	teams = _setting("TEAM_SIZE", 8, 1, MatchProtocol.MAX_TEAM_SIZE)
	minutes = _setting("MINUTES", 20, 1, 60)
	captures = _setting("CAPTURES", 5, 1, 20)
	game_port = _setting("GAME_PORT", MatchProtocol.GAME_PORT, 1, 65535)
	discovery_port = _setting("DISCOVERY_PORT", MatchProtocol.DISCOVERY_PORT, 1, 65535)
	web_port = _setting("WS_PORT", MatchProtocol.WEB_PORT, 1, 65535)
	status_dir = OS.get_environment("VECTORFALL_STATUS_DIR")
	var result := link.listen(game_port, web_port)
	if result != OK:
		push_error("Could not open game ports: " + error_string(result))
		get_tree().quit(1)
		return
	if OS.get_environment("VECTORFALL_DISCOVERY") != "0":
		result = discovery.bind(discovery_port)
		if result != OK:
			push_error("Could not open LAN discovery: " + error_string(result))
			get_tree().quit(1)
			return
	link.joined.connect(func(id: int) -> void: waiting[id] = Time.get_ticks_msec())
	link.left.connect(_release)
	link.received.connect(_receive)
	_new_round()
	print("%s ready on UDP %d and WebSocket %d" % [server_name, game_port, web_port])


func _setting(name: String, fallback: int, low: int, high: int) -> int:
	var value := OS.get_environment("VECTORFALL_" + name)
	return clampi(value.to_int(), low, high) if value.is_valid_int() else fallback


func _new_round() -> void:
	var roster := {}
	for id: int in assignments:
		roster[id] = assignments[id].soldier.team
	assignments.clear()
	inputs.clear()
	active_players.clear()
	loading_players.clear()
	if game != null:
		remove_child(game)
		game.queue_free()
		remove_child(map)
		map.queue_free()
	epoch += 1
	events.clear()
	rounds_wait = 0.0
	if not pending_map.is_empty():
		map_name = pending_map
		pending_map = ""
	map = GameMap.make(map_name)
	add_child(map)
	game = ArenaMatch.make(self, map, minutes, captures, epoch, maxi(8, teams), hold, resupply)
	game.running = false
	director = BotDirector.new(game, map.route_graph)
	for team in 2:
		for index in teams:
			var brain := director.add_bot(team, map.spawn_point(team, index))
			brain.soldier.body.process_mode = Node.PROCESS_MODE_DISABLED
	game.prepare_terrain()
	_watch_events()
	for id: int in roster:
		_assign(id, roster[id])
	_write_status()


func _assign(id: int, preference: int) -> void:
	var open: Array[int] = [0, 0]
	for brain in director.brains:
		open[brain.soldier.team] += 1
	var team := preference if preference in [0, 1] and open[preference] > 0 else int(open[1] > open[0])
	for brain in director.brains:
		var who := brain.soldier
		if who.team != team:
			continue
		assignments[id] = brain
		director.brains.erase(brain)
		var source := RemoteCommands.new()
		source.last.yaw = who.yaw
		source.last.pitch = who.pitch
		inputs[id] = source
		game.sources[who.entity_id] = source
		game.change_occupant(who)
		who.display_name = "%s %d" % [HUMAN_NAME, id]
		waiting.erase(id)
		director.assign_roles()
		loading_players[id] = Time.get_ticks_msec()
		_welcome(id)
		return
	_send(id, {"kind": "reject", "reason": "The match is full."}, 0, true)
	waiting[id] = Time.get_ticks_msec() - MatchTransport.TIMEOUT_MS + 1000


func _release(id: int) -> void:
	waiting.erase(id)
	if not assignments.has(id):
		return
	var brain := assignments[id]
	var who := brain.soldier
	game.change_occupant(who)
	who.display_name = director.callsigns[who.entity_id]
	game.sources[who.entity_id] = brain
	brain.reset()
	director.brains.append(brain)
	director.assign_roles()
	assignments.erase(id)
	inputs.erase(id)
	active_players.erase(id)
	loading_players.erase(id)


func _receive(id: int, packet: PackedByteArray) -> void:
	var message := MatchProtocol.decode(packet, MatchProtocol.INPUT_MAX)
	if message.get("kind") == "join" and waiting.has(id):
		if hold and message.get("hold") != true:
			_send(id, {"kind": "reject", "reason": "This match needs a client with Capture and hold."}, 0, true)
			waiting[id] = Time.get_ticks_msec() - MatchTransport.TIMEOUT_MS + 1000
			return
		var team: Variant = message.get("team", -1)
		_assign(id, team if team is int else -1)
		return
	if not inputs.has(id) or message.get("round") != epoch:
		return
	if message.get("kind") == "ready":
		active_players[id] = true
		loading_players.erase(id)
		return
	if not active_players.has(id) or message.get("kind") != "input":
		return
	var commands: Variant = message.get("commands")
	if not commands is Array or commands.size() > 3:
		return
	for entry in commands:
		if not entry is Array or entry.size() != 2 or not entry[0] is int:
			continue
		var command := MatchProtocol.command(entry[1])
		if command != null:
			inputs[id].offer(entry[0], command)


func _physics_process(delta: float) -> void:
	if game == null:
		return
	link.poll()
	if discovery.is_bound():
		_discover()
	for id: int in waiting.keys():
		if Time.get_ticks_msec() - waiting[id] > MatchTransport.TIMEOUT_MS:
			link.disconnect_peer(id)
			waiting.erase(id)
	for id: int in loading_players.keys():
		if Time.get_ticks_msec() - loading_players[id] > LOAD_TIMEOUT_MS:
			link.disconnect_peer(id)
			_release(id)
	if game.over:
		rounds_wait += delta
	game.step(delta)
	if game.tick % SNAPSHOT_TICKS == 0:
		_snapshot()
	if rounds_wait >= BETWEEN_ROUNDS:
		_new_round()
	status_ticks += 1
	if status_ticks >= 60:
		status_ticks = 0
		_read_control()
		_write_status()


func _snapshot() -> void:
	if active_players.is_empty():
		events.clear()
		return
	var state := _state()
	var packed := {}
	for id: int in active_players:
		var team := assignments[id].soldier.team
		if not packed.has(team):
			packed[team] = _team_snapshot(state, team)
		_send(id, {"kind": "state", "round": epoch, "ack": inputs[id].applied, "state": packed[team]}, 1)
	if not events.is_empty():
		var report := MatchProtocol.encode({"kind": "events", "round": epoch, "tick": game.tick, "events": events})
		for id: int in active_players:
			link.send(id, report, 0, true)
		events.clear()


func _state() -> Dictionary:
	var state := game.get_state(false)
	var humans := {}
	for id: int in assignments:
		var who := assignments[id].soldier
		humans[who.entity_id] = who.display_name
	state["humans"] = humans
	return state


func _team_snapshot(state: Dictionary, team: int) -> PackedByteArray:
	var view := state.duplicate()
	var contacts := [PackedInt32Array(), PackedInt32Array()]
	contacts[team] = game.sensed[team]
	view["sensed"] = contacts
	view["tactical_orders"] = {team: game.tactical_orders(team)}
	var markers := {}
	for recipient: int in game.waypoints:
		if game.soldier(recipient).team == team:
			markers[recipient] = game.waypoints[recipient]
	view["waypoints"] = markers
	return var_to_bytes(view).compress(FileAccess.COMPRESSION_DEFLATE)


func _welcome(id: int) -> void:
	var state := _state()
	state["bot_names"] = director.callsigns
	_send(id, {"kind": "welcome", "round": epoch, "map": map_name, "minutes": minutes,
		"captures": captures, "player": assignments[id].soldier.entity_id, "name": server_name,
		"state": _team_snapshot(state, assignments[id].soldier.team)}, 0, true)


func _send(id: int, message: Dictionary, channel: int, reliable := false) -> void:
	var data := MatchProtocol.encode(message)
	if data.size() <= MatchProtocol.SNAPSHOT_MAX:
		link.send(id, data, channel, reliable)


func _watch_events() -> void:
	game.mine_placed.connect(func(a: int, b: Vector3) -> void: _event(["mine_placed", a, b]))
	game.mine_armed.connect(func(a: int, b: Vector3) -> void: _event(["mine_armed", a, b]))
	game.pack_switched.connect(func(a: int, b: bool) -> void: _event(["pack_switched", a, b]))
	game.fired.connect(func(a: int, b: int) -> void: _event(["fired", a, b]))
	game.impacted.connect(func(a: int, b: Vector3, c: Vector3) -> void: _event(["impacted", a, b, c]))
	game.damaged.connect(func(a: int, b: int, c: float, d: Vector3) -> void: _event(["damaged", a, b, c, d]))
	game.killed.connect(func(a: int, b: int, c: int) -> void: _event(["killed", a, b, c]))
	game.air_hit.connect(func(a: int, b: int) -> void: _event(["air_hit", a, b]))
	game.hit.connect(func(a: int, b: int, c: int) -> void: _event(["hit", a, b, c]))
	game.shield_hit.connect(func(a: int, b: float, c: Vector3) -> void: _event(["shield_hit", a, b, c]))
	game.flag_taken.connect(func(a: int, b: int) -> void: _event(["flag_taken", a, b]))
	game.flag_dropped.connect(func(a: int, b: int) -> void: _event(["flag_dropped", a, b]))
	game.flag_captured.connect(func(a: int, b: int) -> void: _event(["flag_captured", a, b]))
	game.flag_returned.connect(func(a: int, b: int) -> void: _event(["flag_returned", a, b]))
	game.carrier_stopped.connect(func(a: int, b: int) -> void: _event(["carrier_stopped", a, b]))
	game.power_lost.connect(func(a: int) -> void: _event(["power_lost", a]))
	game.power_back.connect(func(a: int) -> void: _event(["power_back", a]))
	game.resupplied.connect(func(id: int) -> void: _event(["resupplied", id]))
	game.station_entered.connect(func(a: int, b: int) -> void: _event(["station_entered", a, b]))
	game.turret_fired.connect(func(a: int) -> void: _event(["turret_fired", a]))
	game.asset_destroyed.connect(func(a: int, b: int) -> void: _event(["asset_destroyed", a, b]))
	game.asset_damaged.connect(func(a: int, b: int, c: float, d: Vector3) -> void: _event(["asset_damaged", a, b, c, d]))
	for team in director.commanders:
		director.commanders[team].said.connect(func(a: int, b: int, c: int, d: String) -> void: _event(["chat", a, b, c, d]))


func _event(value: Array) -> void:
	if not assignments.is_empty() and events.size() < EVENT_LIMIT:
		events.append(value)


func _discover() -> void:
	for index in 16:
		if discovery.get_available_packet_count() == 0:
			break
		var packet := discovery.get_packet()
		if packet.get_string_from_ascii() != MatchProtocol.DISCOVERY_QUERY:
			continue
		discovery.set_dest_address(discovery.get_packet_ip(), discovery.get_packet_port())
		discovery.put_packet(JSON.stringify({"name": server_name, "port": game_port,
			"map": map.title, "players": assignments.size(), "slots": teams * 2}).to_utf8_buffer())


func _write_status() -> void:
	if status_dir.is_empty():
		return
	var temporary := status_dir.path_join("status.tmp")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return
	var names: Array[String] = []
	for brain in assignments.values():
		names.append(brain.soldier.display_name)
	file.store_string(JSON.stringify({"name": server_name, "map": map_name, "title": map.title,
		"game_port": game_port, "ws_port": web_port, "players": names, "bots": director.brains.size(),
		"slots": teams * 2, "score": game.scores, "seconds": int(ceil(game.time_left)), "round": epoch,
		"over": game.over, "mode": "hold" if hold else "ctf",
		"maps": GameMap.NAMES}))
	file.close()
	DirAccess.rename_absolute(temporary, status_dir.path_join("status.json"))


func _read_control() -> void:
	if status_dir.is_empty():
		return
	var path := status_dir.path_join("round.json")
	var claimed := status_dir.path_join("round.processing")
	if not FileAccess.file_exists(path) or DirAccess.rename_absolute(path, claimed) != OK:
		return
	var request: Variant = JSON.parse_string(FileAccess.get_file_as_string(claimed))
	DirAccess.remove_absolute(claimed)
	if request is Dictionary and request.get("map") in GameMap.NAMES:
		pending_map = request.map
		_new_round()


func _exit_tree() -> void:
	link.close()
	discovery.close()
