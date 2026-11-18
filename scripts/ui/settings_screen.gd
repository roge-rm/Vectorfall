class_name SettingsScreen
extends Control

## The settings: look speed for touch, mouse and gamepad, invert look, touch
## control size, auto ski, view distance, outlines, render scale, commander
## mode and the two volumes, with Defaults to put them all back. Each change
## is saved and applied at once; `changed` tells a running match to pick up
## the ones that are its own.

signal changed
signal closed

var _rows: VBoxContainer


func _init() -> void:
	name = "SettingsScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = MenuKit.theme()
	var box := MenuKit.panel(self, "Settings", 0.72)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	scroll.add_child(_rows)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 24)
	box.add_child(bottom)
	bottom.add_child(MenuKit.button("Defaults", _reset))
	bottom.add_child(MenuKit.button("Back", close, MenuKit.BUTTON_SIZE, true))
	_build()


func open() -> void:
	visible = true
	MenuKit.focus_first(_rows)


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		Sound.click(true)
		close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		close()


func _reset() -> void:
	Settings.reset()
	_saved()
	_build()
	MenuKit.focus_first(_rows)


func _saved() -> void:
	Settings.apply()
	Settings.save_file()
	changed.emit()


func _section(words: String) -> void:
	var label := MenuKit.ink_label(words, 22)
	label.modulate = Color(1, 1, 1, 0.6)
	_rows.add_child(label)


## A row that sets a setting from a list of values.
func _choice(words: String, setting: String, values: Array, labels: Array[String]) -> void:
	var at := MenuKit.nearest(values, float(Settings.value(setting)))
	_rows.add_child(MenuKit.stepper(words, labels, at, func(k: int) -> void:
		Settings.set_value(setting, values[k])
		_saved()))


func _toggle(words: String, setting: String) -> void:
	_rows.add_child(MenuKit.stepper(words, MenuKit.on_off(), 1 if Settings.value(setting) else 0, func(k: int) -> void:
		Settings.set_value(setting, k == 1)
		_saved()))


func _build() -> void:
	for child in _rows.get_children():
		child.free()
	var looks := MenuKit.percents(Settings.LOOK_SPEEDS)
	_section("Controls")
	_choice("Look speed, touch", "look_touch", Settings.LOOK_SPEEDS, looks)
	_choice("Look speed, mouse", "look_mouse", Settings.LOOK_SPEEDS, looks)
	_choice("Look speed, gamepad", "look_pad", Settings.LOOK_SPEEDS, looks)
	_toggle("Invert look", "invert_look")
	_choice("Touch controls size", "touch_size", Settings.TOUCH_SIZES, MenuKit.percents(Settings.TOUCH_SIZES))
	_toggle("Auto ski", "auto_ski")
	_toggle("Commander mode", "commander_mode")
	_section("Graphics")
	var distances: Array[String] = []
	for metres in Settings.VIEW_DISTANCES:
		distances.append("%d m" % metres)
	_choice("View distance", "view_distance", Settings.VIEW_DISTANCES, distances)
	_toggle("Outlines", "outlines")
	_choice("Render scale", "render_scale", Settings.RENDER_SCALES, MenuKit.percents(Settings.RENDER_SCALES))
	_section("Sound")
	var volumes := MenuKit.volume_steps()
	_choice("Sound volume", "sound_volume", volumes, MenuKit.percents(volumes))
	_choice("Voice volume", "voice_volume", volumes, MenuKit.percents(volumes))
