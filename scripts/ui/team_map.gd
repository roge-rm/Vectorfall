class_name TeamMap
extends Control

signal closed
signal waypoint_requested(recipient: int, point: Vector2)

var game: Match
var viewer: Soldier
var chart: Chart
var recipients: OptionButton
var send: Button
var orders: RichTextLabel
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
	chart = Chart.new()
	chart.game = game
	chart.viewer = viewer
	chart.bounds = game.arena.tactical_bounds()
	chart.size_flags_horizontal = SIZE_EXPAND_FILL
	chart.focus_mode = FOCUS_ALL
	chart.clip_contents = true
	chart.picked.connect(_sync_send)
	body.add_child(chart)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = MenuKit.px(206)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	body.add_child(scroll)
	var sidebar := VBoxContainer.new()
	sidebar.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(sidebar)
	sidebar.add_child(MenuKit.heading("Waypoint", 22))
	recipients = OptionButton.new()
	_style_recipient_picker()
	recipients.tooltip_text = "Waypoint recipient"
	recipients.fit_to_longest_item = false
	recipients.add_item("Choose teammate", 0)
	recipients.item_selected.connect(func(_index: int) -> void: _sync_send())
	sidebar.add_child(recipients)
	send = MenuKit.button("Send waypoint", _send, 20, false, true)
	sidebar.add_child(send)
	if not game.hold_points.is_empty():
		sidebar.add_child(MenuKit.heading("Control points", 22))
		objective_status = MenuKit.ink_label("", 14)
		sidebar.add_child(objective_status)
	sidebar.add_child(MenuKit.heading("Active orders", 22))
	orders = RichTextLabel.new()
	orders.fit_content = true
	orders.scroll_active = false
	orders.mouse_filter = MOUSE_FILTER_IGNORE
	orders.add_theme_color_override("default_color", InkUi.INK)
	sidebar.add_child(orders)

	var objective := "◆  Flag" if game.hold_points.is_empty() else "A–C  Control points"
	var legend := MenuKit.ink_label("●  Teammate     ○  Sensor contact     " + objective, 18)
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(legend)
	var footer := MenuKit.button_row(column)
	back = MenuKit.button("Back", closed.emit, 22, true)
	footer.add_child(back)
	hide()


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
	var lines: PackedStringArray = []
	for mate: Soldier in game.entities.values():
		if mate.team != viewer.team:
			continue
		var id := mate.entity_id
		if mate != viewer and not mate.dead and game.carried_flag(id) == null:
			available[id] = mate.display_name
		if game.waypoints.has(id):
			lines.append("%s · Waypoint" % mate.display_name)
		elif active.has(id):
			var order: Dictionary = active[id]
			if order.until < 0 or order.until > game.tick:
				lines.append("%s · %s" % [mate.display_name, Orders.NAMES[order.order]])
	if roster != available:
		var selected := recipients.get_selected_id()
		recipients.clear()
		recipients.add_item("Choose teammate", 0)
		for id: int in available:
			recipients.add_item(available[id], id)
		recipients.select(maxi(0, recipients.get_item_index(selected)))
		roster = available
	var current := "\n".join(lines) if not lines.is_empty() else "No active orders"
	if objective_status != null:
		var statuses: PackedStringArray = []
		for point in game.hold_points:
			statuses.append("%s · %s" % [point.letter, point.status()])
		objective_status.text = "\n".join(statuses)
	if orders.text != current:
		orders.text = current
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
		var image := Image.create_empty(GRID, GRID, false, Image.FORMAT_RGB8)
		var cell := bounds.size / float(GRID)
		for y in GRID:
			for x in GRID:
				var at := bounds.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell
				var height := game.arena.height_at(at.x, at.y)
				var slope := game.arena.height_at(at.x + cell.x, at.y + cell.y) - height
				var tone := clampf(0.43 + height / 360.0 - slope / 80.0, 0.12, 0.92)
				var fill := Color("#3c3743").lerp(Color("#d6b39b"), tone)
				if posmod(floori(height), 24) < 3:
					fill = fill.darkened(0.14)
				image.set_pixel(x, y, fill)
		relief = ImageTexture.create_from_image(image)


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
			var at := _at(game.neutral_station.position, rect)
			InkUi.centred(self, at + Vector2(0, 14), "Ammo", InkUi.Face.BOLD, 15, HoldPoint.NEUTRAL, 3)
		if has_pick or has_focus():
			var at := rect.position + cursor * rect.size
			draw_line(at - Vector2(10, 0), at + Vector2(10, 0), InkUi.CREAM, 2.0)
			draw_line(at - Vector2(0, 10), at + Vector2(0, 10), InkUi.CREAM, 2.0)


	func _mark(at: Vector2, colour: Color) -> void:
		var points := PackedVector2Array([at + Vector2(0, -8), at + Vector2(8, 0), at + Vector2(0, 8), at + Vector2(-8, 0)])
		draw_colored_polygon(points, colour)
		points.append(points[0])
		draw_polyline(points, InkUi.INK, 2.0, true)
