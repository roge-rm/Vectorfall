class_name TeamMap
extends Control

signal closed
signal waypoint_requested(recipient: int, point: Vector2)

const SIDEBAR_WIDTH := 228.0

var game: Match
var viewer: Soldier
var chart: Chart
var recipients: OptionButton
var send: Button
var calls_text: Label
var overview: VBoxContainer
var order_page: VBoxContainer
var order_slots: Array[VBoxContainer] = []
var no_orders: Label
var overview_tab: Button
var orders_tab: Button
var objective_status: Label
var back: Button
var roster := {}
var refresh_in := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	theme = MenuKit.theme()
	var column := MenuKit.screen(self, "Team map")
	column.size_flags_horizontal = SIZE_EXPAND_FILL
	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", MenuKit.pxi(14))
	column.add_child(body)
	var map_column := VBoxContainer.new()
	map_column.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_child(map_column)
	chart = Chart.new()
	chart.game = game
	chart.viewer = viewer
	chart.bounds = game.arena.tactical_bounds()
	chart.size_flags_vertical = SIZE_EXPAND_FILL
	chart.focus_mode = FOCUS_ALL
	chart.clip_contents = true
	chart.picked.connect(_sync_send)
	map_column.add_child(chart)
	var objective := "Flag diamonds" if game.hold_points.is_empty() else "Control points A–C"
	map_column.add_child(MenuKit.ink_label("Teammate dots · Contact rings · " + objective, 13))

	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = MenuKit.px(SIDEBAR_WIDTH)
	sidebar.add_theme_constant_override("separation", MenuKit.pxi(6))
	body.add_child(sidebar)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", MenuKit.pxi(5))
	sidebar.add_child(tabs)
	var tab_group := ButtonGroup.new()
	overview_tab = _tab("Overview", false, tab_group)
	orders_tab = _tab("Orders", true, tab_group)
	tabs.add_child(overview_tab)
	tabs.add_child(orders_tab)
	_build_overview(sidebar)
	_build_orders(sidebar)
	_show_orders(false)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", MenuKit.pxi(8))
	column.add_child(footer)
	recipients = OptionButton.new()
	_style_recipient_picker()
	recipients.tooltip_text = "Waypoint recipient"
	recipients.fit_to_longest_item = false
	recipients.add_item("Waypoint to…", 0)
	recipients.custom_minimum_size.x = MenuKit.px(192)
	recipients.item_selected.connect(func(_index: int) -> void: _sync_send())
	footer.add_child(recipients)
	send = MenuKit.button("Send waypoint", _send, 22, false, true)
	footer.add_child(send)
	var space := Control.new()
	space.size_flags_horizontal = SIZE_EXPAND_FILL
	footer.add_child(space)
	back = MenuKit.button("Back", closed.emit, 22, true)
	footer.add_child(back)
	chart.focus_neighbor_right = chart.get_path_to(overview_tab)
	chart.focus_neighbor_bottom = chart.get_path_to(recipients)
	overview_tab.focus_neighbor_left = overview_tab.get_path_to(chart)
	overview_tab.focus_neighbor_bottom = overview_tab.get_path_to(recipients)
	orders_tab.focus_neighbor_bottom = orders_tab.get_path_to(back)
	recipients.focus_neighbor_top = recipients.get_path_to(chart)
	send.focus_neighbor_top = send.get_path_to(chart)
	back.focus_neighbor_top = back.get_path_to(orders_tab)
	hide()


func _tab(label: String, show_orders: bool, group: ButtonGroup) -> Button:
	var tab := MenuKit.button(label, _show_orders.bind(show_orders), 17)
	tab.custom_minimum_size.x = 0
	tab.size_flags_horizontal = SIZE_EXPAND_FILL
	tab.toggle_mode = true
	tab.button_group = group
	return tab


func _build_overview(sidebar: VBoxContainer) -> void:
	overview = VBoxContainer.new()
	overview.add_theme_constant_override("separation", MenuKit.pxi(6))
	sidebar.add_child(overview)
	if not game.hold_points.is_empty():
		overview.add_child(_section("Control points"))
		objective_status = MenuKit.ink_label("", 14)
		overview.add_child(objective_status)
	overview.add_child(_section("Team calls"))
	calls_text = MenuKit.ink_label("", 14)
	calls_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	calls_text.max_lines_visible = 6
	calls_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	overview.add_child(calls_text)


func _build_orders(sidebar: VBoxContainer) -> void:
	order_page = VBoxContainer.new()
	sidebar.add_child(order_page)
	no_orders = MenuKit.ink_label("No active orders", 14)
	order_page.add_child(no_orders)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", MenuKit.pxi(6))
	grid.add_theme_constant_override("v_separation", 1)
	order_page.add_child(grid)
	for index in MatchProtocol.MAX_TEAM_SIZE:
		var slot := VBoxContainer.new()
		slot.size_flags_horizontal = SIZE_EXPAND_FILL
		slot.add_theme_constant_override("separation", -2)
		var name := MenuKit.ink_label("", 11, InkUi.Face.BOLD)
		var order := MenuKit.ink_label("", 10)
		for label in [name, order]:
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			slot.add_child(label)
		grid.add_child(slot)
		order_slots.append(slot)
		slot.hide()


func _section(title: String) -> Label:
	var section := MenuKit.heading(title, 19)
	section.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return section


func _show_orders(enabled: bool) -> void:
	overview.visible = not enabled
	order_page.visible = enabled
	overview_tab.set_pressed_no_signal(not enabled)
	orders_tab.set_pressed_no_signal(enabled)


func _style_recipient_picker() -> void:
	var edge := StyleBoxFlat.new()
	edge.bg_color = InkUi.CREAM
	edge.border_color = InkUi.INK
	edge.set_border_width_all(MenuKit.pxi(2))
	edge.content_margin_left = MenuKit.px(8)
	edge.content_margin_top = MenuKit.px(4)
	edge.content_margin_bottom = MenuKit.px(4)
	for state in ["normal", "hover", "pressed"]:
		recipients.add_theme_stylebox_override(state, edge)
	var focus := edge.duplicate() as StyleBoxFlat
	focus.draw_center = false
	focus.border_color = InkUi.PINK
	recipients.add_theme_stylebox_override("focus", focus)
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		recipients.add_theme_color_override(state, InkUi.INK)
	recipients.add_theme_constant_override("modulate_arrow", 1)


func open() -> void:
	if chart.relief == null:
		chart.build_relief()
	chart.has_pick = false
	chart.cursor = chart.world_ratio(viewer.at()).clamp(Vector2.ZERO, Vector2.ONE * 0.999)
	_show_orders(false)
	show()
	_refresh()
	chart.grab_focus()


func _process(delta: float) -> void:
	if not visible:
		return
	chart.queue_redraw()
	refresh_in -= delta
	if refresh_in <= 0.0:
		_refresh()


func _refresh() -> void:
	refresh_in = 0.2
	var active := game.tactical_orders(viewer.team)
	var available := {}
	var lines: Array[Vector2i] = []
	for mate: Soldier in game.entities.values():
		if mate.team != viewer.team:
			continue
		var id := mate.entity_id
		if mate != viewer and not mate.dead and game.carried_flag(id) == null:
			available[id] = mate.display_name
		if game.waypoints.has(id):
			lines.append(Vector2i(id, Orders.Kind.WAYPOINT))
		elif active.has(id):
			var order: Dictionary = active[id]
			if order.until < 0 or order.until > game.tick:
				lines.append(Vector2i(id, order.order))
	if roster != available:
		var selected := recipients.get_selected_id()
		recipients.clear()
		recipients.add_item("Waypoint to…", 0)
		for id: int in available:
			recipients.add_item(available[id], id)
		recipients.select(maxi(0, recipients.get_item_index(selected)))
		roster = available
	if objective_status != null:
		var statuses: PackedStringArray = []
		for point in game.hold_points:
			statuses.append("%s · %s" % [point.letter, point.status()])
		objective_status.text = "\n".join(statuses)
	no_orders.visible = lines.is_empty()
	for index in order_slots.size():
		var slot := order_slots[index]
		slot.visible = index < lines.size()
		if slot.visible:
			var line := lines[index]
			slot.get_child(0).text = game.soldier(line.x).display_name
			slot.get_child(1).text = Orders.NAMES[line.y]
	var calls: PackedStringArray = []
	for call: Dictionary in game.team_calls.active(viewer.team).values():
		var caller := game.soldier(call.by)
		if caller != null:
			var name := "You" if caller == viewer else caller.display_name
			var line := "%s · %s: %s" % [Orders.CALL_ICONS[call.kind], name, Orders.CALL_MARKERS[call.kind]]
			if not call.acks.is_empty():
				line += " (%d ack)" % call.acks.size()
			calls.append(line)
	calls_text.text = "\n".join(calls) if not calls.is_empty() else "No team calls"
	_sync_send()


func _sync_send() -> void:
	send.disabled = viewer.dead or not chart.has_pick or recipients.get_selected_id() <= 0


func _send() -> void:
	if send.disabled:
		return
	waypoint_requested.emit(recipients.get_selected_id(), chart.bounds.position + chart.cursor * chart.bounds.size)
	chart.has_pick = false
	_sync_send()


class Chart extends Control:
	signal picked

	const GRID := 96
	var game: Match
	var viewer: Soldier
	var bounds: Rect2
	var relief: ImageTexture
	var cursor := Vector2(0.5, 0.5)
	var has_pick := false


	func build_relief() -> void:
		relief = ImageTexture.create_from_image(relief_image(game.arena, bounds))


	static func relief_image(arena: GameMap, area: Rect2) -> Image:
		var image := Image.create_empty(GRID, GRID, false, Image.FORMAT_RGB8)
		var cell := area.size / float(GRID)
		for y in GRID:
			for x in GRID:
				var at := area.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell
				var height := arena.height_at(at.x, at.y)
				var slope := arena.height_at(at.x + cell.x, at.y + cell.y) - height
				var tone := clampf(0.43 + height / 360.0 - slope / 80.0, 0.12, 0.92)
				var fill := Color("#3c3743").lerp(Color("#d6b39b"), tone)
				if posmod(floori(height), 24) < 3:
					fill = fill.darkened(0.14)
				image.set_pixel(x, y, fill)
		return image


	func world_ratio(at: Vector3) -> Vector2:
		return (Vector2(at.x, at.z) - bounds.position) / bounds.size


	func _rect() -> Rect2:
		var scale := minf(size.x / bounds.size.x, size.y / bounds.size.y)
		var span := bounds.size * scale
		return Rect2((size - span) * 0.5, span)


	func _at(world: Vector3, rect: Rect2) -> Vector2:
		return rect.position + world_ratio(world).clamp(Vector2.ZERO, Vector2.ONE) * rect.size


	func _gui_input(event: InputEvent) -> void:
		var rect := _rect()
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if rect.has_point(event.position):
				cursor = (event.position - rect.position) / rect.size
				has_pick = true
				picked.emit()
				grab_focus()
			accept_event()
		elif event.is_action_pressed("ui_accept"):
			has_pick = true
			picked.emit()
			accept_event()


	func _process(delta: float) -> void:
		if not is_visible_in_tree() or not has_focus():
			return
		var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if move != Vector2.ZERO:
			cursor = (cursor + move * delta * 0.5).clamp(Vector2.ZERO, Vector2.ONE * 0.999)
			has_pick = true
			picked.emit()


	func _draw() -> void:
		if relief == null:
			return
		var rect := _rect()
		draw_rect(Rect2(Vector2.ZERO, size), InkUi.INK)
		draw_texture_rect(relief, rect, false)
		for step: float in [0.25, 0.5, 0.75]:
			var x := rect.position.x + rect.size.x * step
			var y := rect.position.y + rect.size.y * step
			draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(InkUi.CREAM, 0.2))
			draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(InkUi.CREAM, 0.2))

		for team: int in game.stands:
			var base := _at(game.stands[team], rect)
			var power := "Power on" if game.powered(team) else "Power off"
			var label_x := clampf(base.x, rect.position.x + 44.0, rect.end.x - 44.0)
			InkUi.centred(self, Vector2(label_x, base.y + 21.0), "%s · %s" % [Soldier.TEAM_NAMES[team], power],
				InkUi.Face.BOLD, 15, Palette.team(team), 3)
		for who: Soldier in game.entities.values():
			if game.tactical_soldier_visible(viewer, who):
				var at := _at(who.global_position, rect)
				var radius := 6.0 if who == viewer else 4.0
				draw_circle(at, radius + 2.0, InkUi.INK, true, -1, true)
				var friendly := who.team == viewer.team
				draw_circle(at, radius, Palette.team(who.team), friendly, -1.0 if friendly else 2.0, true)
				if who == viewer:
					InkUi.centred(self, at + Vector2(0, -15), "You", InkUi.Face.BOLD, 15, InkUi.CREAM, 3)
				var order: Dictionary = game.waypoints.get(who.entity_id, {})
				if who.team == viewer.team and not order.is_empty():
					var finish := _at(order.at, rect)
					draw_dashed_line(at, finish, InkUi.CREAM, 2.0, 6.0)
					_mark(finish, InkUi.CREAM)
		for flag: Flag in game.flags.values():
			if game.tactical_flag_visible(viewer, flag):
				_mark(_at(flag.global_position, rect), Palette.team(flag.team))
		for point in game.hold_points:
			var at := _at(point.position, rect)
			_mark(at, point.colour())
			InkUi.centred(self, at, point.letter, InkUi.Face.BLACK, 13, InkUi.INK)
		if game.neutral_station != null:
			var supply := game.neutral_station
			var at := _at(supply.position, rect)
			var owner := game.station_team(supply)
			var tint := HoldPoint.NEUTRAL if owner < 0 else Palette.team(owner)
			var label := "Ammo"
			if supply.control_index >= 0 and supply.control_index < game.hold_points.size():
				label = "%s ammo" % game.hold_points[supply.control_index].letter
			InkUi.centred(self, at + Vector2(0, 14), label, InkUi.Face.BOLD, 15, tint, 3)
		for call: Dictionary in game.team_calls.active(viewer.team).values():
			var at := _at(call.at, rect) + Vector2(0, -13)
			draw_circle(at, 9.0, InkUi.INK, true, -1.0, true)
			draw_circle(at, 7.0, InkUi.AMBER, true, -1.0, true)
			InkUi.centred(self, at, Orders.CALL_ICONS[call.kind], InkUi.Face.BLACK, 12, InkUi.INK)
		if has_pick or has_focus():
			var at := rect.position + cursor * rect.size
			draw_line(at - Vector2(10, 0), at + Vector2(10, 0), InkUi.CREAM, 2.0)
			draw_line(at - Vector2(0, 10), at + Vector2(0, 10), InkUi.CREAM, 2.0)


	func _mark(at: Vector2, colour: Color) -> void:
		var points := PackedVector2Array([at + Vector2(0, -8), at + Vector2(8, 0), at + Vector2(0, 8), at + Vector2(-8, 0)])
		draw_colored_polygon(points, colour)
		points.append(points[0])
		draw_polyline(points, InkUi.INK, 2.0, true)
