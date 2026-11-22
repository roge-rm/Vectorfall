extends SceneTree

var checks := TestWorld.Checks.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Settings.path = "user://tactical-test.cfg"
	MatchSetup.current.map = "test"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var game: Match = main.game
	game.running = false
	var viewer: Soldier = main.player
	var mate: Soldier
	for who: Soldier in game.entities.values():
		if who != viewer and who.team == viewer.team:
			mate = who
			break
	var foe: Soldier = main.enemy
	main.input.set_device(LocalInput.Device.TOUCH)
	await process_frame
	await process_frame
	var map_button: Button = main.hud._map_button
	var touch: TouchControls = main.touch
	var pause_zone := touch.pause_rect().grow(touch.pause_radius() * (TouchControls.START_REACH - 1.0))
	checks.check(map_button.visible and not map_button.get_rect().intersects(pause_zone),
		"the Map button clears the touch pause hitbox")
	var tap := InputEventScreenTouch.new()
	tap.position = root.get_final_transform() * map_button.get_global_rect().get_center()
	tap.pressed = true
	Input.parse_input_event(tap)
	tap = tap.duplicate()
	tap.pressed = false
	Input.parse_input_event(tap)
	await process_frame
	checks.check(main.team_map.visible and main.input.held_off and not paused, "the team map holds input while the match runs")
	checks.check(main.team_map.chart.relief != null, "the team map builds a terrain chart")
	checks.check(not game.tactical_soldier_visible(viewer, foe), "an unseen enemy is left off the map")
	game.sensed[viewer.team].append(foe.entity_id)
	checks.check(game.tactical_soldier_visible(viewer, foe), "an enemy sensor contact appears")
	var jammer := foe.loadout.duplicate()
	jammer.pack = Pack.JAMMER
	foe.set_loadout(jammer)
	foe.pack_on = true
	var own_flag: Flag = game.flags[viewer.team]
	own_flag.mode = Flag.Mode.CARRIED
	own_flag.carrier_id = foe.entity_id
	checks.check(not game.tactical_soldier_visible(viewer, foe) and not game.tactical_flag_visible(viewer, own_flag),
		"a jammer hides a stale sensor contact and the flag they carry")
	own_flag.send_home()
	foe.pack_on = false
	main.team_map.chart.cursor = Vector2(0.6, 0.5)
	main.team_map.chart.has_pick = true
	main.team_map.recipients.select(main.team_map.recipients.get_item_index(mate.entity_id))
	main.team_map._sync_send()
	main.team_map._send()
	var submitted: PlayerCommand = main.input.make_command(OnlineClient.STEP)
	var cmd := MatchProtocol.command(submitted.to_dict())
	if cmd == null:
		checks.check(false, "the client issues a valid waypoint command")
		checks.finish(self)
		return
	game._apply_order(viewer.entity_id, cmd)
	checks.check(not main.team_map.visible and not main.input.held_off and game.waypoints.has(mate.entity_id),
		"sending from the chart assigns the waypoint and gives control back")
	if not game.waypoints.has(mate.entity_id):
		checks.finish(self)
		return
	var ordered: BotBrain = main.bots.brain_of(mate.entity_id)
	ordered.think()
	checks.check(ordered.goal == BotBrain.Goal.WAYPOINT and ordered.goal_target == game.waypoints[mate.entity_id].at,
		"the assigned bot routes to the waypoint")
	cmd.order_arg = foe.entity_id
	game._apply_order(viewer.entity_id, cmd)
	checks.check(not game.waypoints.has(foe.entity_id), "the other team cannot be given waypoints")
	cmd.order_arg = mate.entity_id
	cmd.order_point = Vector2(INF, 0)
	checks.check(MatchProtocol.command(cmd.to_dict()) == null, "the command decoder rejects non-finite waypoints")
	cmd.order_point = Vector2(10000, 10000)
	var previous: Vector3 = game.waypoints[mate.entity_id].at
	game._apply_order(viewer.entity_id, cmd)
	checks.check(game.waypoints[mate.entity_id].at == previous, "a waypoint must be inside the arena")
	mate.global_position = previous
	game._step_waypoints()
	checks.check(not game.waypoints.has(mate.entity_id), "arrival clears a waypoint")

	var held: Flag = game.flags[viewer.team]
	game._take_flag(held, foe)
	game.damage(foe, 10.0, mate.entity_id, Weapon.DISC, Vector3.ZERO)
	game.damage(foe, 200.0, viewer.entity_id, Weapon.DISC, Vector3.ZERO)
	game._return_flag(held, viewer.entity_id)
	var generator := game.generator(viewer.team)
	generator.destroyed = true
	generator.health = 0.0
	game.repair_asset(generator, generator.max_health(), viewer.entity_id)
	var theirs: Flag = game.flags[foe.team]
	game._take_flag(theirs, viewer)
	mate.global_position = viewer.global_position + Vector3(4, 0, 0)
	game.settings.capture_limit = 1
	game._capture(theirs, viewer)
	var viewer_row: Array = game.results.counts[viewer.entity_id]
	var mate_row: Array = game.results.counts[mate.entity_id]
	checks.check(viewer_row == [1, 0, 1, 1, 1, 1, 1, 0], "results count kills, flags, carrier stops and restoring equipment")
	checks.check(mate_row == [0, 1, 0, 0, 0, 0, 0, 1], "results count recent damage and an escort at capture")
	var state := game.get_state(false)
	game.set_state(state)
	checks.check(game.results.counts[viewer.entity_id] == viewer_row, "the authoritative totals survive a snapshot")
	main.results_board.open()
	checks.check(main.results_board.visible and main.results_board.rows.get_child_count() == game.entities.size() + 4,
		"the results screen lists both teams and their totals")
	game.change_occupant(mate)
	checks.check(not game.results.counts.has(mate.entity_id) and game.results.former[0].counts == mate_row,
		"a slot change preserves contributions under the previous player")
	main.queue_free()
	await process_frame
	checks.finish(self)
