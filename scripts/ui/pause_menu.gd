class_name PauseMenu
extends Control

## The pause menu: Resume, Settings, How to play, Restart and Quit to menu.
## It runs while the tree is paused; the owner pauses and unpauses the tree
## on `opened` and `resumed`, so the match itself holds no pause state.

signal resumed
signal restart_pressed
signal quit_pressed

var home: Control
var settings: SettingsScreen
var how_to: HowToPlay
## Last input used, a LocalInput.Device, for the how to play tab.
var device := 0


func _init(restart_title := "Restart") -> void:
	name = "PauseMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = MenuKit.theme()
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(InkUi.INK, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	home = Control.new()
	home.set_anchors_preset(Control.PRESET_FULL_RECT)
	home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(home)
	var box := MenuKit.card(home, "Paused")
	box.add_child(MenuKit.button("Resume", resume, 22, false, true))
	box.add_child(MenuKit.button("Settings", _show_settings, 22))
	box.add_child(MenuKit.button("How to play", _show_how_to, 22))
	box.add_child(MenuKit.button(restart_title, restart_pressed.emit, 22))
	box.add_child(MenuKit.button("Quit to menu", quit_pressed.emit, 22, true))
	settings = SettingsScreen.new()
	settings.visible = false
	settings.closed.connect(_show_home)
	add_child(settings)
	how_to = HowToPlay.new()
	how_to.visible = false
	how_to.closed.connect(_show_home)
	add_child(how_to)


func open() -> void:
	visible = true
	_show_home()


func resume() -> void:
	visible = false
	resumed.emit()


func _show_home() -> void:
	settings.visible = false
	how_to.visible = false
	home.visible = true
	MenuKit.focus_first(home)


func _show_settings() -> void:
	home.visible = false
	settings.open()


func _show_how_to() -> void:
	home.visible = false
	how_to.open(device)


func _unhandled_input(event: InputEvent) -> void:
	if visible and home.visible and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		Sound.click(true)
		resume()
