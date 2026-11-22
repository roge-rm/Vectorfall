extends SceneTree

var checks := TestWorld.Checks.new()
var native: OnlineClient
var web: OnlineClient


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var remote := RemoteCommands.new()
	var held := PlayerCommand.new()
	held.move = Vector2.UP
	remote.offer(1, held)
	remote.make_command(OnlineClient.STEP)
	for index in 12:
		remote.make_command(OnlineClient.STEP)
	checks.check(remote.make_command(OnlineClient.STEP).move == Vector2.ZERO,
		"the server clears held movement when input stops")
	remote.offer(181, held)
	checks.check(remote.make_command(OnlineClient.STEP).move == Vector2.UP and remote.applied == 181,
		"input resumes after a long packet gap")
	var game_port := int(OS.get_environment("VECTORFALL_GAME_PORT"))
	var web_port := int(OS.get_environment("VECTORFALL_WS_PORT"))
	var discovery_port := int(OS.get_environment("VECTORFALL_DISCOVERY_PORT"))
	Settings.path = "user://online-match-test.cfg"
	var probe := PacketPeerUDP.new()
	probe.bind(0)
	probe.set_dest_address("127.0.0.1", discovery_port)
	probe.put_packet(MatchProtocol.DISCOVERY_QUERY.to_ascii_buffer())
	for index in 180:
		if probe.get_available_packet_count() > 0:
			break
		await physics_frame
	var response: Variant = JSON.parse_string(probe.get_packet().get_string_from_utf8()) if probe.get_available_packet_count() else null
	checks.check(response is Dictionary and int(response.port) == game_port and int(response.slots) == 32,
		"LAN discovery reports the server's UDP port and 32 slots")
	probe.close()

	change_scene_to_file("res://scenes/menu.tscn")
	await scene_changed
	var menu := current_scene as MainMenu
	menu.show_online()
	menu.online.address.text = "127.0.0.1"
	menu.online.port.value = game_port
	menu.online._join()
	native = menu.online.connection
	web = OnlineClient.new()
	root.add_child(web)
	web.ready_to_play.connect(web.arena_ready)
	var connected := web.start("ws://127.0.0.1:%d" % web_port, 0, true)
	checks.check(connected == OK and native != null, "both client transports open")
	for index in 600:
		if current_scene != null and current_scene.scene_file_path == "res://scenes/main.tscn" and web.started:
			break
		await physics_frame
	if not is_instance_valid(native) or not native.started or not web.started or current_scene == null or current_scene.scene_file_path != "res://scenes/main.tscn":
		checks.check(false, "both clients receive a playable server snapshot")
		_finish()
		return
	var main := current_scene
	var team_counts := [0, 0]
	for soldier: Dictionary in native.initial.entities.values():
		team_counts[soldier.team] += 1
	checks.check(native.player_id != web.player_id and team_counts == [16, 16],
		"native and WebSocket clients fill distinct slots in the same 16v16 match")
	checks.check(main.bots == null and not main.game.running and main.player.entity_id == native.player_id,
		"the normal scene uses the server snapshot without simulating a second match")

	var before: Vector3 = main.player.position
	Input.action_press("move_forward")
	for index in 110:
		await physics_frame
	Input.action_release("move_forward")
	var server_view: Dictionary = web.latest.get("entities", {}).get(native.player_id, {})
	checks.check(native.latest_ack > 0 and main.player.position.distance_to(before) > 3.0,
		"movement is predicted and acknowledged")
	checks.check(not server_view.is_empty() and server_view.position.distance_to(before) > 3.0,
		"the other client receives the authoritative movement")
	var old_tick: int = main.game.tick
	main.pause()
	for index in 30:
		await physics_frame
	checks.check(not paused and main.game.tick > old_tick, "opening the pause menu keeps online snapshots moving")
	main.pause_menu.resume()
	var first_round := native.round_id
	var scene_id := main.get_instance_id()
	var request := FileAccess.open(OS.get_environment("VECTORFALL_STATUS_DIR").path_join("round.json"), FileAccess.WRITE)
	request.store_string(JSON.stringify({"map": native.map_name}))
	request.close()
	for index in 420:
		if native.round_id > first_round and web.round_id == native.round_id and is_instance_valid(current_scene) and current_scene.get_instance_id() != scene_id:
			break
		await physics_frame
	checks.check(native.round_id > first_round and web.round_id == native.round_id and current_scene.get_instance_id() != scene_id,
		"a new round reloads the match and keeps both connections")
	var dropped_id := web.player_id
	web.stop()
	web = null
	for index in 150:
		if not native.latest.is_empty() and not native.latest.humans.has(dropped_id):
			break
		await physics_frame
	checks.check(not native.latest.humans.has(dropped_id) and native.latest.entities.has(dropped_id),
		"leaving hands the same soldier back to a bot")
	await _check_capacity(game_port, web_port)
	_finish()


func _check_capacity(game_port: int, web_port: int) -> void:
	var clients: Array[OnlineClient] = []
	var opened := true
	for index in 31:
		var client := OnlineClient.new()
		root.add_child(client)
		clients.append(client)
		client.ready_to_play.connect(client.arena_ready)
		var result := client.start("127.0.0.1", game_port, false)
		opened = opened and result == OK
	var received_full_match := func(client: OnlineClient) -> bool:
		return is_instance_valid(client) and client.latest.get("humans", {}).size() == 32
	for index in 360:
		if received_full_match.call(native) and clients.all(received_full_match):
			break
		await physics_frame
	var everyone_received: bool = opened and received_full_match.call(native) and clients.all(received_full_match)
	checks.check(everyone_received, "32 native clients can connect and receive match snapshots")

	if everyone_received:
		var extra := OnlineClient.new()
		root.add_child(extra)
		var rejection := [""]
		extra.failed.connect(func(reason: String) -> void: rejection[0] = reason)
		extra.start("ws://127.0.0.1:%d" % web_port, 0, true)
		for index in 150:
			if not is_instance_valid(extra) or extra.started:
				break
			await physics_frame
		checks.check(rejection[0] == "The match is full.", "the 33rd player is rejected across transports")
		if is_instance_valid(extra):
			extra.stop()
	for client in clients:
		if is_instance_valid(client):
			client.stop()


func _finish() -> void:
	if is_instance_valid(native):
		native.stop()
	if is_instance_valid(web):
		web.stop()
	checks.finish(self)
