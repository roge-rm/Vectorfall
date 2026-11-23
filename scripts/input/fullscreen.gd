extends Node

var _windowed_mode := Window.MODE_WINDOWED


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(OS.has_feature("pc") and DisplayServer.get_name() != "headless")


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or event.keycode != KEY_F11 or not event.pressed or event.echo:
		return
	var window := get_window()
	if window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
		window.mode = _windowed_mode
	else:
		_windowed_mode = window.mode
		window.mode = Window.MODE_FULLSCREEN
	get_viewport().set_input_as_handled()
