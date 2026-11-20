class_name HowToPlay
extends Control

## A short how to play: the controls for one input scheme, picked by tabs and
## starting on the one in use, then the flag rules and skiing.

signal closed
signal practice_pressed

enum Scheme { TOUCH, KEYBOARD, GAMEPAD }

const TABS: Array[String] = ["Touch", "Keyboard", "Gamepad"]
const CONTROLS: Array[String] = [
	"Drag on the left side to move and on the right side to look.\nHold JUMP to ski and JET to fly. With Jet set to Stick and button, double-tap and hold the stick, or push it past its ring, to jet too. One thumb can slide between JUMP, JET and FIRE.\nDrag from FIRE to aim while firing. The button with your weapon's name changes weapon.\nPACK uses your pack. PLACE sets down a turret, sensor or station on level ground. GREN throws a hand grenade and MINE places a mine.\nStep onto a friendly station, or tap LOADOUT while dead, to change your loadout.\nTap BOARD beside a friendly vehicle, or EXIT to leave it. Drag to steer, use the stick to drive and UP or DOWN to fly.\nORDERS gives your bots orders, II pauses.\nTurn on Gyro aim in Settings to aim by turning the phone.\nAim assist slows your aim over an enemy and turns it gently toward them.",
	"WASD to move, the mouse to look, left click to fire.\nHold space to jump and ski, right click or shift to jet.\n1 to 4 pick a weapon, Q or the wheel changes weapon.\nE uses your pack. E or G places turret, sensor and station packs on level ground. F throws a hand grenade, C places a mine.\nI or B changes your loadout on a friendly station or while dead.\nR boards or exits a vehicle. Look to steer, use movement keys to drive, and hold right click or Shift to climb or Space to descend in the air.\nV then a number gives your bots orders, Esc pauses.",
	"Left stick to move, right stick to look.\nRight trigger fires, left trigger or LB jets, hold A to jump and ski.\nY or RB changes weapon.\nX uses your pack or places it on level ground if it carries a turret, sensor or station. D-pad left throws a hand grenade, d-pad right places a mine.\nBack changes your loadout on a friendly station or while dead.\nB boards or exits a vehicle. Look to steer, use the left stick to drive and hold the jet or jump button to climb or descend in the air.\nD-pad up gives your bots orders, Start pauses.\nAim assist slows your aim over an enemy and turns it gently toward them.",
]
const RULES := "Take the other team's flag from their base and bring it to your flag stand. You can only score while your own flag is home.\nTouch your own flag when it's dropped to send it home, or it goes home by itself after 30 s.\nThe first team to the capture limit wins, or the one with most captures when time runs out.\nHold jump going downhill to ski: you slide with no friction and pick up speed. Jet over the next rise to keep it. Jet energy comes back when you stop jetting."

const FONTS := "Big Shoulders Display, copyright 2019 The Big Shoulders Project Authors (https://github.com/xotypeco/big_shoulders).\nIBM Plex Serif, copyright 2017 IBM Corp. with Reserved Font Name \"Plex\".\nBoth are licensed under the SIL Open Font License, Version 1.1:"
const LICENCE_FILE := "res://art/fonts/IBMPlexSerif-OFL.txt"

var scheme := Scheme.KEYBOARD
var _tabs: Array[MenuKit.CoverButton] = []
var _controls: Label


func _init(allow_practice := false) -> void:
	name = "HowToPlay"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = MenuKit.theme()
	var box := MenuKit.screen(self, "How to play")
	var tabs := MenuKit.button_row(box)
	for k in TABS.size():
		var tab := MenuKit.button(TABS[k], show_scheme.bind(k), 22)
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
	text.add_theme_constant_override("separation", MenuKit.pxi(10))
	scroll.add_child(text)
	_controls = _paragraph(text, "")
	_paragraph(text, RULES)
	# The fonts' licence has to travel with them.
	text.add_child(MenuKit.ink_label("Fonts", 14, InkUi.Face.ITALIC, InkUi.RUST))
	_paragraph(text, FONTS)
	var licence := _paragraph(text, _licence_text())
	licence.add_theme_font_size_override("font_size", MenuKit.pxi(10))
	var buttons := MenuKit.button_row(box)
	buttons.add_child(MenuKit.button("Back", close, MenuKit.BUTTON_SIZE, true))
	if allow_practice:
		buttons.add_child(MenuKit.button("Ski practice", practice_pressed.emit, MenuKit.BUTTON_SIZE, false, true))
	show_scheme(scheme)


func _paragraph(parent: Control, words: String) -> Label:
	var label := MenuKit.ink_label(words, 14)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


## The licence from its file, without the copyright line at its top.
static func _licence_text() -> String:
	var whole := FileAccess.get_file_as_string(LICENCE_FILE)
	var start := whole.find("This Font Software")
	return whole.substr(maxi(start, 0)).strip_edges()


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
