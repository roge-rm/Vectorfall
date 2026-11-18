class_name HowToPlay
extends Control

## A short how to play: the controls for one input scheme, picked by tabs and
## starting on the one in use, then the flag rules and skiing.

signal closed

enum Scheme { TOUCH, KEYBOARD, GAMEPAD }

const TABS: Array[String] = ["Touch", "Keyboard", "Gamepad"]
const CONTROLS: Array[String] = [
	"Drag on the left side to move and on the right side to look.\nHold JUMP to ski and JET to fly. One thumb can slide between JUMP, JET and FIRE.\nDrag from FIRE to aim while firing. SWAP changes weapon.\nORDERS gives your bots orders, II pauses.",
	"WASD to move, the mouse to look, left click to fire.\nHold space to jump and ski, right click or shift to jet.\n1, 2 or Q change weapon.\nV then a number gives your bots orders, Esc pauses.",
	"Left stick to move, right stick to look.\nRight trigger fires, left trigger or LB jets, hold A to jump and ski.\nRB changes weapon.\nD-pad up gives your bots orders, Start pauses.",
]
const RULES := "Take the other team's flag from their base and bring it to your flag stand. You can only score while your own flag is home.\nTouch your own flag when it's dropped to send it home, or it goes home by itself after 30 s.\nThe first team to the capture limit wins, or the one with most captures when time runs out.\nHold jump going downhill to ski: you slide with no friction and pick up speed. Jet over the next rise to keep it. Jet energy comes back when you stop jetting."

var scheme := Scheme.KEYBOARD
var _tabs: Array[Button] = []
var _controls: Label


func _init() -> void:
	name = "HowToPlay"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = MenuKit.theme()
	var box := MenuKit.panel(self, "How to play", 0.8)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 12)
	box.add_child(tabs)
	for k in TABS.size():
		var tab := MenuKit.button(TABS[k], show_scheme.bind(k), 24)
		tab.toggle_mode = true
		tabs.add_child(tab)
		_tabs.append(tab)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	box.add_child(scroll)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 12)
	scroll.add_child(text)
	_controls = _paragraph(text, "")
	_paragraph(text, RULES)
	var back := MenuKit.button("Back", close, MenuKit.BUTTON_SIZE, true)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(back)
	show_scheme(scheme)


func _paragraph(parent: Control, words: String) -> Label:
	var label := MenuKit.ink_label(words, 22)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func show_scheme(which: int) -> void:
	scheme = which as Scheme
	_controls.text = CONTROLS[which]
	for k in _tabs.size():
		_tabs[k].set_pressed_no_signal(k == which)


## Opens on the scheme for a LocalInput.Device.
func open(device: int) -> void:
	match device:
		LocalInput.Device.TOUCH:
			show_scheme(Scheme.TOUCH)
		LocalInput.Device.GAMEPAD:
			show_scheme(Scheme.GAMEPAD)
		_:
			show_scheme(Scheme.KEYBOARD)
	visible = true
	_tabs[scheme].grab_focus()


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
