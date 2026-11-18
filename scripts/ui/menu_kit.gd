class_name MenuKit
extends RefCounted

## Building blocks for the menus in the HUD's paperback look: comic panels,
## big ink buttons that click, and rows that step through a list of choices
## with < and > (or left and right on a gamepad or keyboard).

const TITLE_SIZE := 44
const BUTTON_SIZE := 30
const ROW_SIZE := 26
## Orange for hover and focus, from the HUD's button theme.
const HIGHLIGHT := Color(0.95, 0.72, 0.3)

static var _theme: Theme


## InkUi's theme with a clear focus ring, paper scroll bars and paper labels
## on panels in ink.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = InkUi.theme().duplicate() as Theme
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = HIGHLIGHT
	focus.set_border_width_all(5)
	focus.set_expand_margin_all(4)
	_theme.set_stylebox("focus", "Button", focus)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = InkUi.INK
	grabber.set_content_margin_all(6)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(InkUi.INK, 0.15)
	track.set_content_margin_all(6)
	_theme.set_stylebox("grabber", "VScrollBar", grabber)
	_theme.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	_theme.set_stylebox("grabber_pressed", "VScrollBar", grabber)
	_theme.set_stylebox("scroll", "VScrollBar", track)
	# Slimmer buttons for setting rows.
	_theme.set_type_variation("RowButton", "Button")
	for state: String in ["normal", "hover", "pressed"]:
		var slim := (_theme.get_stylebox(state, "Button") as StyleBoxFlat).duplicate() as StyleBoxFlat
		slim.content_margin_top = 2
		slim.content_margin_bottom = 2
		slim.shadow_offset = Vector2(3, 3)
		_theme.set_stylebox(state, "RowButton", slim)
	return _theme


## A full screen holder with margins, its panel centred in it, and the box
## the rest goes in. width is a share of the screen's width.
## fill false lets the panel shrink to what's in it, centred.
static func panel(parent: Control, title: String, width := 0.6, fill := true) -> VBoxContainer:
	var holder := MarginContainer.new()
	holder.name = title.replace(" ", "")
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.anchor_left = 0.5 - width * 0.5
	holder.anchor_right = 0.5 + width * 0.5
	for side: String in ["margin_top", "margin_bottom"]:
		holder.add_theme_constant_override(side, 28)
	parent.add_child(holder)
	var box_panel := PanelContainer.new()
	if not fill:
		box_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.add_child(box_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box_panel.add_child(box)
	box.add_child(heading(title))
	return box


static func heading(words: String, font_size := TITLE_SIZE) -> Label:
	var label := Label.new()
	label.text = words
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	return label


## Ink text on the paper panel.
static func ink_label(words: String, font_size := ROW_SIZE) -> Label:
	var label := Label.new()
	label.text = words
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", InkUi.INK)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	return label


## A button that clicks and calls back when pressed.
static func button(words: String, pressed: Callable, font_size := BUTTON_SIZE, back := false) -> Button:
	var made := Button.new()
	made.text = words
	made.add_theme_font_size_override("font_size", font_size)
	made.custom_minimum_size = Vector2(font_size * 6.5, font_size * 1.9)
	made.pressed.connect(func() -> void:
		Sound.click(back)
		pressed.call())
	return made


## A row with a name on the left and a value stepped through choices on the
## right. on_change gets the new index. Returns the row; its value button is
## row.get_meta("value").
static func stepper(words: String, choices: Array[String], index: int, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := ink_label(words)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var state := {"index": clampi(index, 0, choices.size() - 1)}
	var value := Button.new()
	value.theme_type_variation = &"RowButton"
	value.add_theme_font_size_override("font_size", ROW_SIZE)
	value.custom_minimum_size = Vector2(230.0, ROW_SIZE * 1.55)
	value.text = choices[state.index]
	var step := func(by: int) -> void:
		var next: int = clampi(state.index + by, 0, choices.size() - 1)
		if by > 0 and state.index == choices.size() - 1:
			next = 0
		if next == state.index:
			return
		state.index = next
		value.text = choices[next]
		Sound.click(by < 0)
		on_change.call(next)
	var less := _arrow("<", step.bind(-1))
	var more := _arrow(">", step.bind(1))
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


static func _arrow(words: String, pressed: Callable) -> Button:
	var arrow := Button.new()
	arrow.text = words
	arrow.focus_mode = Control.FOCUS_NONE
	arrow.theme_type_variation = &"RowButton"
	arrow.add_theme_font_size_override("font_size", ROW_SIZE)
	arrow.custom_minimum_size = Vector2(ROW_SIZE * 1.8, ROW_SIZE * 1.55)
	arrow.pressed.connect(pressed)
	return arrow


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
