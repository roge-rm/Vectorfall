extends SceneTree

var checks := TestWorld.Checks.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var udp := PacketPeerUDP.new()
	var tcp := TCPServer.new()
	if udp.bind(0, "127.0.0.1") != OK or tcp.listen(0, "127.0.0.1") != OK:
		checks.check(false, "the loopback ports are available")
		checks.finish(self)
		return
	var native_port := udp.get_local_port()
	var web_port := tcp.get_local_port()
	udp.close()
	tcp.stop()
	OS.set_environment("VECTORFALL_GAME_PORT", str(native_port))
	OS.set_environment("VECTORFALL_WS_PORT", str(web_port))
	OS.set_environment("VECTORFALL_DISCOVERY", "0")
	OS.set_environment("VECTORFALL_TEAM_SIZE", "1")
	OS.set_environment("VECTORFALL_MODE", "hold")
	var map_name := "copper_steps" if OS.get_cmdline_user_args().has("new-arena") else "nightline_foundry"
	OS.set_environment("VECTORFALL_MAP", map_name)
	OS.set_environment("VECTORFALL_MIDFIELD_RESUPPLY", "1")
	OS.set_environment("VECTORFALL_STATUS_DIR", "")
	var server: Node = load("res://scenes/server.tscn").instantiate()
	root.add_child(server)
	var native := OnlineClient.new()
	var web := OnlineClient.new()
	for client in [native, web]:
		root.add_child(client)
		client.ready_to_play.connect(client.arena_ready)
	checks.check(native.start("127.0.0.1", native_port, false) == OK
		and web.start("ws://127.0.0.1:%d" % web_port, 0, true) == OK,
		"both transports open for the Capture and Hold server")
	for index in 650:
		if not native.latest.is_empty() and not web.latest.is_empty():
			break
		await physics_frame
	if native.latest.is_empty() or web.latest.is_empty():
		checks.check(false, "both clients receive Capture and Hold snapshots")
		_finish(server, native, web)
		return
	Settings.path = "user://control-online-test.cfg"
	OnlineClient.active = native
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	checks.check(server.map_name == map_name and scene.map.title == server.map.title,
		"the host and client use the requested Capture and Hold arena")
	checks.check(scene.game.hold_points.size() == 3
		and (scene.game.neutral_station != null) == GameMap.RESUPPLY_ARENAS.has(map_name),
		"the normal client scene builds the host objectives and the map’s optional resupply pad")
	var original: Match = server.game
	var point := original.hold_points[1]
	var lime := original.soldier(native.player_id)
	var blue := original.soldier(web.player_id)
	checks.check(native.initial.hold_points.size() == 3 and native.initial.flags.is_empty(),
		"the welcome includes the right objectives")
	lime.position = point.position + Vector3.UP * 0.2
	blue.position = point.position + Vector3(2.0, 0.2, 0.0)
	for index in 90:
		if native.latest.hold_points[1].contested and web.latest.hold_points[1].contested:
			break
		await physics_frame
	checks.check(native.latest.hold_points[1].contested and web.latest.hold_points[1].contested,
		"both clients see the point contested")
	blue.position = server.map.spawn_point(blue.team, 0).origin
	point.progress = HoldPoint.CAPTURE_SECONDS - 0.2
	point.challenger = lime.team
	for index in 90:
		if native.latest.hold_points[1].owning_team == lime.team and web.latest.hold_points[1].owning_team == lime.team:
			break
		await physics_frame
	checks.check(native.latest.hold_points[1].owning_team == lime.team and web.latest.hold_points[1].owning_team == lime.team,
		"both clients see the host capture the point")
	point.held_seconds = HoldPoint.SCORE_SECONDS - 0.2
	original.time_left = 0.5
	for index in 120:
		if native.latest.over and web.latest.over and scene.game.over:
			break
		await physics_frame
	checks.check(native.latest.over and web.latest.over and native.latest.scores == web.latest.scores
		and native.latest.scores[lime.team] == 1 and native.latest.winner == lime.team and web.latest.winner == lime.team,
		"both clients see the same winning score at time up")
	checks.check(scene.game.over and scene.game.winner == lime.team and scene.game.scores == native.latest.scores,
		"the online match scene ends with the host's result")
	scene.queue_free()
	_finish(server, native, web)


func _finish(server: Node, native: OnlineClient, web: OnlineClient) -> void:
	native.stop()
	web.stop()
	server.queue_free()
	await process_frame
	checks.finish(self)
