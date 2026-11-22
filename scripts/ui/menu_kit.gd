class_name MenuKit
extends RefCounted

## Building blocks for the menus in the paperback cover look: cream screens
## under an ink title band and the three colour stripe, filled and outlined
## buttons with an italic number, and rows that step through a list of
## choices with < and > (or left and right on a gamepad or keyboard).
## Sizes are design pixels (a 390 pixel high screen) times U, as the menus
## lay out on the 1280 x 720 canvas.

const U := 720.0 / InkUi.DESIGN_HEIGHT
const TITLE_SIZE := 48
const BUTTON_SIZE := 26
const ROW_SIZE := 20
## Design width of the column of rows on setup and settings.
const COLUMN_WIDTH := 600.0

static var _theme: Theme


## Design pixels to canvas pixels.
static func px(design: float) -> float:
	return design * U


static func pxi(design: float) -> int:
	return roundi(design * U)


## Serif ink text, no boxes or focus rings from the theme (the buttons draw
## their own), and paper scroll bars.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = InkUi.theme().duplicate() as Theme
	_theme.default_font = InkUi.face(InkUi.Face.SERIF)
	_theme.default_font_size = pxi(14)
	var empty := StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		_theme.set_stylebox(state, "Button", empty)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = InkUi.INK
	grabber.set_content_margin_all(px(3))
	var track := StyleBoxFlat.new()
	track.bg_color = InkUi.CREAM
	track.border_color = InkUi.INK
	track.set_border_width_all(roundi(px(1)))
	track.set_content_margin_all(px(3))
	_theme.set_stylebox("grabber", "VScrollBar", grabber)
	_theme.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	_theme.set_stylebox("grabber_pressed", "VScrollBar", grabber)
	_theme.set_stylebox("scroll", "VScrollBar", track)
	_theme.set_stylebox("panel", "ScrollContainer", empty)
	return _theme


## A full screen cream page with a title band, its rows in a centred column.
## Returns the column, which the rest goes in.
static func screen(parent: Control, title: String) -> VBoxContainer:
	var holder := Control.new()
	holder.name = title.replace(" ", "")
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(holder)
	var back := ColorRect.new()
	back.color = InkUi.CREAM
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(back)
	var page := VBoxContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 0)
	holder.add_child(page)
	page.add_child(Band.make(title, 56.0, TITLE_SIZE))
	var margins := MarginContainer.new()
	margins.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margins.add_theme_constant_override("margin_left", pxi(28))
	margins.add_theme_constant_override("margin_right", pxi(28))
	margins.add_theme_constant_override("margin_top", pxi(14))
	margins.add_theme_constant_override("margin_bottom", pxi(12))
	page.add_child(margins)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.custom_minimum_size.x = px(COLUMN_WIDTH)
	column.add_theme_constant_override("separation", pxi(10))
	margins.add_child(column)
	return column


## A cream card with an ink edge and a title band, centred on the screen.
## Returns the box its buttons go in.
static func card(parent: Control, title: String, width := 300.0) -> VBoxContainer:
	var centre := CenterContainer.new()
	centre.name = title.replace(" ", "")
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(centre)
	var outer := PanelContainer.new()
	outer.custom_minimum_size.x = px(width)
	var edge := StyleBoxFlat.new()
	edge.bg_color = InkUi.CREAM
	edge.border_color = InkUi.INK
	edge.set_border_width_all(pxi(2))
	edge.set_content_margin_all(px(2))
	outer.add_theme_stylebox_override("panel", edge)
	centre.add_child(outer)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 0)
	outer.add_child(inner)
	inner.add_child(Band.make(title, 48.0, 34))
	var margins := MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margins.add_theme_constant_override(side, pxi(16))
	inner.add_child(margins)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", pxi(8))
	margins.add_child(box)
	return box


## The kept name for a card, for screens that want one.
static func panel(parent: Control, title: String, _width := 0.6, _fill := true) -> VBoxContainer:
	return card(parent, title)


## Big Shoulders words in ink, upper case.
static func heading(words: String, font_size := TITLE_SIZE) -> Label:
	var label := Label.new()
	label.text = words.to_upper()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", InkUi.face(InkUi.Face.BLACK))
	label.add_theme_font_size_override("font_size", pxi(font_size))
	label.add_theme_color_override("font_color", InkUi.INK)
	return label


## Serif text in ink, or another face and colour. font_size is in design
## pixels.
static func ink_label(words: String, font_size := 15, face := InkUi.Face.SERIF, colour := InkUi.INK) -> Label:
	var label := Label.new()
	label.text = words
	label.add_theme_font_override("font", InkUi.face(face))
	label.add_theme_font_size_override("font_size", pxi(font_size))
	label.add_theme_color_override("font_color", colour)
	return label


static func line_edit(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.custom_minimum_size.y = px(40)
	var frame := StyleBoxFlat.new()
	frame.bg_color = InkUi.CREAM
	frame.border_color = InkUi.INK
	frame.set_border_width_all(pxi(2))
	frame.set_content_margin_all(px(6))
	edit.add_theme_stylebox_override("normal", frame)
	edit.add_theme_color_override("font_color", InkUi.INK)
	edit.add_theme_color_override("font_placeholder_color", InkUi.BROWN_GREY)
	edit.add_theme_color_override("caret_color", InkUi.INK)
	edit.max_length = 256
	edit.placeholder_text = placeholder
	return edit


## A menu button that clicks and calls back when pressed. filled is the ink
## primary look, otherwise it's outlined. number shows as "No. n" before the
## words when above 0. font_size is in design pixels.
static func button(words: String, pressed: Callable, font_size := BUTTON_SIZE, back := false, filled := false, number := 0) -> CoverButton:
	var made := CoverButton.new()
	made.words = words.to_upper()
	made.filled = filled
	made.number = "No. %d" % number if number > 0 else ""
	made.font_size = pxi(font_size)
	made.centre_words = number <= 0
	var wide := InkUi.width(made.words, InkUi.Face.BLACK, made.font_size) + px(32)
	if number > 0:
		wide += InkUi.width(made.number, InkUi.Face.ITALIC, made.number_size()) + px(12)
	made.custom_minimum_size = Vector2(maxf(wide, px(120)), px(font_size * 1.55))
	made.pressed.connect(func() -> void:
		Sound.click(back)
		pressed.call())
	return made


## A row with a name on the left and a value stepped through choices on the
## right. on_change gets the new index. kind is "" for a plain list, "toggle"
## for Off and On, "meter" to show how far along the list the value is.
## Returns the row; its value button is row.get_meta("value").
static func stepper(words: String, choices: Array[String], index: int, on_change: Callable, kind := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", pxi(6))
	var label := ink_label(words, 15)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var state := {"index": clampi(index, 0, choices.size() - 1)}
	var value := CoverButton.new()
	value.centre_words = true
	value.font_size = pxi(ROW_SIZE)
	value.custom_minimum_size = Vector2(px(170), px(34))
	var show := func(k: int) -> void:
		value.words = choices[k].to_upper()
		value.lit = kind == "toggle" and k == 1
		value.meter = float(k) / maxf(choices.size() - 1, 1.0) if kind == "meter" else -1.0
		value.queue_redraw()
	show.call(state.index)
	var step := func(by: int) -> void:
		var next: int = clampi(state.index + by, 0, choices.size() - 1)
		if by > 0 and state.index == choices.size() - 1:
			next = 0
		if next == state.index:
			return
		state.index = next
		show.call(next)
		Sound.click(by < 0)
		on_change.call(next)
	var less := _arrow(-1, step.bind(-1))
	var more := _arrow(1, step.bind(1))
	value.pressed.connect(step.bind(1))
	value.gui_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed("ui_left"):
			step.call(-1)
			value.accept_event()
		elif event.is_action_pressed("ui_right"):
			step.call(1)
			value.accept_event())
	row.add_child(less)
	row.add_child(value)
	row.add_child(more)
	row.set_meta("value", value)
	row.set_meta("step", step)
	return row


static func _arrow(direction: int, pressed: Callable) -> CoverButton:
	var arrow := CoverButton.new()
	arrow.arrow = direction
	arrow.focus_mode = Control.FOCUS_NONE
	arrow.custom_minimum_size = Vector2(px(34), px(34))
	arrow.pressed.connect(pressed)
	return arrow


## A row of buttons along the bottom of a screen, centred.
static func button_row(parent: Control) -> HBoxContainer:
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", pxi(14))
	parent.add_child(bottom)
	return bottom


## A scrolling list for rows, filling the space left on a screen.
static func rows(parent: Control, vertical_margin := 0) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	parent.add_child(scroll)
	# Room on the right for the scroll bar.
	var room := MarginContainer.new()
	room.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room.add_theme_constant_override("margin_right", pxi(14))
	room.add_theme_constant_override("margin_top", pxi(vertical_margin))
	room.add_theme_constant_override("margin_bottom", pxi(vertical_margin))
	scroll.add_child(room)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", pxi(6))
	room.add_child(list)
	return list


## Scrolls a list from rows() back to its top.
static func scroll_to_top(list: Control) -> void:
	var scroll := list.get_parent().get_parent() as ScrollContainer
	if scroll != null:
		scroll.set_deferred("scroll_vertical", 0)


## Off and On for steppers.
static func on_off() -> Array[String]:
	return ["Off", "On"]


## The index of the choice nearest to value.
static func nearest(values: Array, value: float) -> int:
	var best := 0
	for k in values.size():
		if absf(float(values[k]) - value) < absf(float(values[best]) - value):
			best = k
	return best


## Percent labels for a list of shares.
static func percents(values: Array) -> Array[String]:
	var words: Array[String] = []
	for v: float in values:
		words.append("%d%%" % roundi(v * 100.0))
	return words


## Volume steps from 0 to 1 in tenths.
static func volume_steps() -> Array[float]:
	var steps: Array[float] = []
	for k in 11:
		steps.append(k / 10.0)
	return steps


## Focuses the first focusable control under node, for gamepad and keyboard.
static func focus_first(node: Node) -> void:
	for child in node.get_children():
		var control := child as Control
		if control != null and control.focus_mode == Control.FOCUS_ALL and control.is_visible_in_tree():
			control.grab_focus()
			return
		focus_first(child)
		var viewport := node.get_viewport()
		if viewport != null and viewport.gui_get_focus_owner() != null:
			return


## The ink title band over the three colour stripe, at the top of a screen
## or card. Heights and title size are design pixels.
class Band:
	extends Control

	var title := ""
	var band := 56.0
	var title_size := 48

	static func make(words: String, band_height: float, font_size: int) -> Band:
		var made := Band.new()
		made.title = words.to_upper()
		made.band = band_height
		made.title_size = font_size
		made.custom_minimum_size.y = MenuKit.px(band_height + 18.0)
		made.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return made

	func _draw() -> void:
		var h := MenuKit.px(band)
		draw_rect(Rect2(0.0, 0.0, size.x, h), InkUi.INK)
		InkUi.stripes(self, Rect2(0.0, h, size.x, MenuKit.px(18.0)))
		var font_size := MenuKit.pxi(title_size)
		var f := InkUi.face(InkUi.Face.BLACK)
		var baseline := h - MenuKit.px(8.0) - f.get_descent(font_size) * 0.6
		InkUi.words(self, Vector2(MenuKit.px(24.0), baseline), title, InkUi.Face.BLACK, font_size, InkUi.CREAM)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()


## A button drawn in the cover look. Filled: ink with cream words. Outlined:
## a 2 px ink edge and ink words, filled in ink while focused or hovered.
## A focused filled button gets a pink ring 2 px outside it. Pressed moves it
## 2 px down, disabled is at 40%. lit fills it orange (a toggle that's on),
## meter draws a bar along its bottom, arrow draws a < or > instead of words.
class CoverButton:
	extends Button

	var words := ""
	var number := ""
	var filled := false
	var highlight_hover := true
	var lit := false
	var meter := -1.0
	var arrow := 0
	var font_size := 40
	var centre_words := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		button_down.connect(queue_redraw)
		button_up.connect(queue_redraw)
		toggled.connect(func(_on: bool) -> void: queue_redraw())

	func number_size() -> int:
		return roundi(font_size * 14.0 / 36.0)

	func _draw() -> void:
		var mode := get_draw_mode()
		var line := MenuKit.px(2.0)
		var on := filled or (toggle_mode and button_pressed)
		var down := not toggle_mode and (mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED)
		var hovered := mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED
		var inverted := on or has_focus() or (highlight_hover and hovered)
		var alpha := 0.4 if disabled else 1.0
		var rect := Rect2(Vector2(0.0, line if down else 0.0), size)
		if inverted:
			draw_rect(rect, Color(InkUi.INK, alpha))
		else:
			if lit:
				draw_rect(rect, Color(InkUi.ORANGE, alpha))
			draw_rect(rect.grow(-line * 0.5), Color(InkUi.INK, alpha), false, line)
		if on and has_focus():
			draw_rect(rect.grow(line * 1.5), Color(InkUi.PINK, alpha), false, line)
		var ink := InkUi.CREAM if inverted else InkUi.INK
		if meter >= 0.0:
			var bar := Rect2(rect.position + Vector2(line * 2.0, rect.size.y - line * 3.5), Vector2((rect.size.x - line * 4.0) * meter, line * 1.5))
			draw_rect(bar, Color(InkUi.ORANGE if inverted else InkUi.PINK, alpha))
		if arrow != 0:
			var c := rect.get_center()
			var r := rect.size.y * 0.2
			var tip := c + Vector2(r * arrow, 0.0)
			draw_colored_polygon(PackedVector2Array([tip, c + Vector2(-r * arrow * 0.8, -r), c + Vector2(-r * arrow * 0.8, r)]), Color(ink, alpha))
			return
		var f := InkUi.face(InkUi.Face.BLACK)
		var baseline := rect.position.y + (rect.size.y + f.get_ascent(font_size) - f.get_descent(font_size)) * 0.5
		var x := rect.position.x + MenuKit.px(16.0)
		var word_width := InkUi.width(words, InkUi.Face.BLACK, font_size)
		if centre_words:
			x = rect.position.x + (rect.size.x - word_width) * 0.5
		if number != "":
			var number_colour := InkUi.AMBER if inverted else InkUi.RUST
			x += InkUi.words(self, Vector2(x, baseline), number, InkUi.Face.ITALIC, number_size(), Color(number_colour, alpha)) + MenuKit.px(12.0)
		InkUi.words(self, Vector2(x, baseline), words, InkUi.Face.BLACK, font_size, Color(ink, alpha))
