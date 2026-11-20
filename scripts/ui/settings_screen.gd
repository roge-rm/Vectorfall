class_name SettingsScreen
extends Control

## The settings: look speed for touch, mouse and gamepad, invert look, touch
## control size, jet scheme, gyro aim on a phone or tablet, aim assist, auto ski, view distance, outlines, render scale, commander
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
	var box := MenuKit.screen(self, "Settings")
	_rows = MenuKit.rows(box)
	var bottom := MenuKit.button_row(box)
	bottom.add_child(MenuKit.button("Defaults", _reset))
	bottom.add_child(MenuKit.button("Back", close, MenuKit.BUTTON_SIZE, true))
	_build()


func open() -> void:
	visible = true
	MenuKit.focus_first(_rows)
	MenuKit.scroll_to_top(_rows)


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
	var label := MenuKit.ink_label(words, 14, InkUi.Face.ITALIC, InkUi.RUST)
	_rows.add_child(label)


## A row that sets a setting from a list of values.
func _choice(words: String, setting: String, values: Array, labels: Array[String]) -> void:
	var at := MenuKit.nearest(values, float(Settings.value(setting)))
	_rows.add_child(MenuKit.stepper(words, labels, at, func(k: int) -> void:
		Settings.set_value(setting, values[k])
		_saved(), "meter"))


func _toggle(words: String, setting: String) -> void:
	_rows.add_child(MenuKit.stepper(words, MenuKit.on_off(), 1 if Settings.value(setting) else 0, func(k: int) -> void:
		Settings.set_value(setting, k == 1)
		_saved(), "toggle"))


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
	_choice("Jet", "touch_scheme", [0, 1], ["Button", "Stick and button"])
	if OS.has_feature("mobile"):
		var gyros: Array[String] = ["Off"]
		gyros.append_array(MenuKit.percents(Settings.GYRO_SPEEDS.slice(1)))
		_choice("Gyro aim", "gyro", Settings.GYRO_SPEEDS, gyros)
		_toggle("Invert gyro", "invert_gyro")
	_choice("Aim assist", "aim_assist", [0, 1, 2], ["Off", "Low", "High"])
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
