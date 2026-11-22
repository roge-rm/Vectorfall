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
	var callsigns := {}
	for brain: BotBrain in main.bots.brains:
		callsigns[brain.soldier.display_name] = true
	checks.check(callsigns.size() == main.bots.brains.size()
		and callsigns.keys().all(func(value: String) -> bool: return value in BotDirector.CALLSIGNS),
		"offline bots have distinct callsigns from the pool")
	var orders := main.menu as OrderMenu
	orders.page = OrderMenu.Page.BOTS
	checks.check(orders.entries()[1].begins_with(mate.display_name + " (")
		and main.hud._name(mate) == mate.display_name, "orders and the HUD use the same callsign")
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
	var bounds: Rect2 = main.team_map.chart.bounds
	var seen: Array = DuoPanel.map_snapshot(game, viewer, bounds).markers
	checks.check(seen.any(func(mark: Dictionary) -> bool: return mark.kind == "contact")
		and seen.any(func(mark: Dictionary) -> bool: return mark.kind == "ally" and mark.label == mate.display_name),
		"the Duo map includes sensor contacts and friendly callsigns")
	var jammer := foe.loadout.duplicate()
	jammer.pack = Pack.JAMMER
	foe.set_loadout(jammer)
	foe.pack_on = true
	var own_flag: Flag = game.flags[viewer.team]
	own_flag.mode = Flag.Mode.CARRIED
	own_flag.carrier_id = foe.entity_id
	checks.check(not game.tactical_soldier_visible(viewer, foe) and not game.tactical_flag_visible(viewer, own_flag),
		"a jammer hides a stale sensor contact and the flag they carry")
	own_flag._update_beam()
	checks.check(not own_flag._beam.visible, "the jammed flag beam is hidden from the opposing player")
	var hidden: Array = DuoPanel.map_snapshot(game, viewer, bounds).markers
	checks.check(not hidden.any(func(mark: Dictionary) -> bool:
		return mark.kind == "contact" or (mark.kind == "flag" and mark.team == viewer.team)),
		"the Duo map hides the same jamming enemy and carried flag")
	own_flag.send_home()
	own_flag._update_beam()
	checks.check(own_flag._beam.visible, "the beam comes back when the flag returns")
	foe.pack_on = false
	main.team_map.chart.cursor = Vector2(0.6, 0.5)
	main.team_map.chart.has_pick = true
	var recipients := main.team_map.recipients as OptionButton
	var mate_item := recipients.get_item_index(mate.entity_id)
	checks.check(mate_item >= 0 and recipients.get_item_text(mate_item) == mate.display_name,
		"the map uses the same callsign for the waypoint recipient")
	recipients.select(mate_item)
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
	await _check_team_calls(main, mate, foe)
	await _check_full_team_map(main)

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
	await process_frame
	main.results_board.open()
	checks.check(main.results_board.visible and main.results_board.rows.get_child_count() == game.entities.size() + 4,
		"the results screen lists both teams and their totals")
	var results_names: Array[String] = []
	for row: Node in main.results_board.rows.get_children():
		if row is HBoxContainer:
			results_names.append((row.get_child(0) as Label).text)
	checks.check(mate.display_name in results_names, "the results list the same callsign")
	var duo_rows: Array = DuoPanel.results_snapshot(game, viewer).rows
	checks.check(duo_rows.any(func(row: Dictionary) -> bool: return row.name == mate.display_name and row.counts == mate_row),
		"the Duo results use the same authoritative totals")
	game.change_occupant(mate)
	checks.check(not game.results.counts.has(mate.entity_id) and game.results.former[0].counts == mate_row
		and game.results.former[0].name == mate.display_name,
		"a slot change preserves contributions under the previous player")
	await _check_pad_scroll(main.results_board)
	main.queue_free()
	await process_frame
	checks.finish(self)


func _check_team_calls(main: Node, mate: Soldier, foe: Soldier) -> void:
	var game: Match = main.game
	var viewer: Soldier = main.player
	var menu: OrderMenu = main.menu
	_press_key(KEY_V)
	_press_key(KEY_7)
	await process_frame
	checks.check(menu.title() == "Team calls" and "I'll run the flag" in menu.entries(),
		"the keyboard opens team calls from the normal Orders menu")
	_press_key(KEY_1)
	await process_frame
	var cmd: PlayerCommand = main.input.make_command(OnlineClient.STEP)
	game._apply_order(viewer.entity_id, cmd)
	var calls := game.team_calls.active(viewer.team)
	var run_call: Dictionary = calls.get(Orders.Kind.FLAG_RUN, {})
	checks.check(cmd.order == Orders.Kind.FLAG_RUN and run_call.get("at") == game.stands[foe.team]
		and game.team_calls.active(foe.team).is_empty(), "a flag run marks the other stand for teammates only")

	cmd.order = Orders.Kind.REPAIR_GENERATOR
	game._apply_order(viewer.entity_id, cmd)
	game._apply_order(mate.entity_id, cmd)
	checks.check(calls.size() == 1, "a caller has a cooldown and bots cannot send team calls")
	var bot_source: CommandSource = game.sources[mate.entity_id]
	game.sources[mate.entity_id] = CommandSource.new()
	game._apply_order(mate.entity_id, cmd)
	var repair_call: Dictionary = calls.get(Orders.Kind.REPAIR_GENERATOR, {})
	checks.check(repair_call.get("at") == game.generator(viewer.team).centre(), "a repair call marks the team's generator")
	if repair_call.is_empty():
		game.sources[mate.entity_id] = bot_source
		return
	cmd.order = Orders.Kind.ACK_CALL
	cmd.order_arg = repair_call.id
	game._apply_order(mate.entity_id, cmd)
	var foe_source: CommandSource = game.sources[foe.entity_id]
	game.sources[foe.entity_id] = CommandSource.new()
	game._apply_order(foe.entity_id, cmd)
	game.sources[foe.entity_id] = foe_source
	checks.check(repair_call.acks.is_empty(), "callers and opponents cannot acknowledge a call")
	_press_key(KEY_V)
	await process_frame
	checks.check(menu.entries().back() == "Acknowledge repair generator", "an incoming call adds a shortcut to Orders")
	_press_key(KEY_1 + menu.entries().size() - 1)
	await process_frame
	cmd = MatchProtocol.command(main.input.make_command(OnlineClient.STEP).to_dict())
	if cmd != null:
		game._apply_order(viewer.entity_id, cmd)
		game._apply_order(viewer.entity_id, cmd)
	checks.check(repair_call.acks == PackedInt32Array([viewer.entity_id]), "the same teammate can acknowledge a specific call once")
	game.sources[mate.entity_id] = bot_source
	await process_frame
	checks.check(main.hud.feed_text().any(func(line: String) -> bool: return line.ends_with("Generator needs repair")),
		"the match HUD shows the teammate's call")
	main._open_team_map()
	checks.check(main.team_map.calls_text.text.contains("Repair generator (1 ack)"), "the chart shows the call and acknowledgement")
	var bottom: Dictionary = DuoPanel.map_snapshot(game, viewer, main.team_map.chart.bounds)
	checks.check(bottom.markers.any(func(marker: Dictionary) -> bool: return marker.kind == "call" and marker.label == "G"),
		"the Duo chart includes calls for the viewer's team")
	main._close_team_map()
	game.team_calls.expire(game.tick + TeamCalls.LIFETIME, false)
	checks.check(game.team_calls.active(viewer.team).is_empty(), "calls expire after a short window")


func _check_full_team_map(main: Node) -> void:
	var game: Match = main.game
	var viewer: Soldier = main.player
	var team_map: TeamMap = main.team_map
	var roster := game.bots.commander(viewer.team).members()
	var added: Array[Soldier] = []
	for index in range(roster.size(), MatchProtocol.MAX_TEAM_SIZE):
		var who := game.add_soldier(viewer.team, main.map.spawn_point(viewer.team, index))
		who.display_name = "Player %d" % (index + 1)
		added.append(who)
		roster.append(who)
	var active := game.tactical_orders(viewer.team)
	var prior := active.duplicate()
	for who in roster:
		active[who.entity_id] = {"order": Orders.Kind.ATTACK_GENERATOR, "until": -1}
	var previous_aspect := root.content_scale_aspect
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	main._open_team_map()
	team_map.orders_tab.pressed.emit()
	await process_frame
	await process_frame
	var body := team_map.order_page.get_global_rect()
	var last := team_map.order_slots.back() as Control
	var footer := team_map.back.get_global_rect()
	checks.check(team_map.recipients.item_count == MatchProtocol.MAX_TEAM_SIZE and team_map.order_slots.all(
		func(slot: Control) -> bool: return slot.is_visible_in_tree()),
		"the full 16-player team fits the recipient picker and orders view")
	checks.check(last.get_global_rect().end.y <= footer.position.y and body.end.y <= footer.position.y
		and team_map.get_global_rect().encloses(footer),
		"every order and the footer fit without scrolling (last %s, footer %s, page %s)" % [
			last.get_global_rect(), footer, team_map.get_global_rect()])
	team_map.overview_tab.pressed.emit()
	checks.check(team_map.overview.visible and not team_map.order_page.visible
		and team_map.chart.is_visible_in_tree() and team_map.recipients.is_visible_in_tree(),
		"switching panels keeps the map and waypoint controls visible")
	main._close_team_map()
	root.content_scale_aspect = previous_aspect
	active.clear()
	active.merge(prior)
	for who in added:
		game.entities.erase(who.entity_id)
		game.sources.erase(who.entity_id)
		who.queue_free()


func _press_key(code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)


func _check_pad_scroll(board: ResultsBoard) -> void:
	# Previous players make the results scroll even in a tall viewport.
	for index in 16:
		board.game.results.former.append({"name": "Player %d" % index, "team": index % 2, "counts": MatchResults.empty_row()})
	board.open()
	await process_frame
	await process_frame
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_DPAD_DOWN
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var first_step := board.scroll.scroll_vertical
	checks.check(first_step == MenuKit.pxi(ResultsBoard.SCROLL_STEP), "D-pad Down scrolls the results one step on press")
	await create_timer(0.45).timeout
	var held_position := board.scroll.scroll_vertical
	checks.check(held_position > first_step, "holding D-pad Down keeps scrolling the results")
	var release := press.duplicate() as InputEventJoypadButton
	release.pressed = false
	Input.parse_input_event(release)
	await create_timer(0.2).timeout
	checks.check(board.scroll.scroll_vertical == held_position, "releasing the D-pad stops the results from scrolling")

	press.button_index = JOY_BUTTON_DPAD_UP
	Input.parse_input_event(press)
	await process_frame
	board.back.grab_focus()
	var unfocused_position := board.scroll.scroll_vertical
	await create_timer(0.45).timeout
	checks.check(unfocused_position < held_position and board.scroll.scroll_vertical == unfocused_position,
		"the results stop scrolling when focus leaves the list")
	release.button_index = JOY_BUTTON_DPAD_UP
	Input.parse_input_event(release)
