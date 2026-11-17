class_name LocalInput
extends Node

## Turns keyboard and mouse, gamepad and touch into PlayerCommands for the
## local soldier, and keeps track of which kind of device was used last so the
## touch controls show only when you're using touch.

enum Device { KEYBOARD, GAMEPAD, TOUCH }

signal device_changed(device: Device)

## Radians per mouse pixel.
@export var mouse_sensitivity := 0.0025
## Radians per second at full right stick.
@export var stick_look_speed := 3.2
## Radians per pixel of touch drag.
@export var touch_sensitivity := 0.006

var device := Device.KEYBOARD
var source := Source.new()
var touch: TouchControls
var _mouse_look := Vector2.ZERO


## The CommandSource the match asks each tick.
class Source:
	extends CommandSource
	var input: LocalInput

	func make_command(delta: float) -> PlayerCommand:
		return input.make_command(delta)


func _init() -> void:
	name = "LocalInput"
	source.input = self
	if DisplayServer.is_touchscreen_available() and OS.has_feature("mobile"):
		device = Device.TOUCH


func _input(event: InputEvent) -> void:
	var used := -1
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		used = Device.TOUCH
	elif event is InputEventKey or event is InputEventMouseButton:
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			used = Device.KEYBOARD
	elif event is InputEventMouseMotion:
		if event.device != InputEvent.DEVICE_ID_EMULATION and event.relative.length() > 2.0:
			used = Device.KEYBOARD
	elif event is InputEventJoypadButton:
		used = Device.GAMEPAD
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.4:
		used = Device.GAMEPAD
	if used != -1 and used != device:
		set_device(used)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not DisplayServer.get_name() == "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_look += event.screen_relative


func set_device(value: Device) -> void:
	device = value
	if device == Device.TOUCH and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	device_changed.emit(device)


func make_command(delta: float) -> PlayerCommand:
	var command := PlayerCommand.new()
	var look := -_mouse_look * mouse_sensitivity
	_mouse_look = Vector2.ZERO
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	# Squared response, finer near the middle of the stick.
	look -= stick * stick.abs() * stick_look_speed * delta
	if touch != null:
		look -= touch.take_look() * touch_sensitivity
	source.yaw = wrapf(source.yaw + look.x, -PI, PI)
	source.pitch = clampf(source.pitch + look.y, -Soldier.PITCH_LIMIT, Soldier.PITCH_LIMIT)
	command.yaw = source.yaw
	command.pitch = source.pitch

	if device == Device.TOUCH:
		# Touches also make pretend mouse clicks, which mustn't fire.
		if touch != null:
			command.move = touch.stick
			command.buttons = touch.buttons
		return command
	command.move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	for pair: Array in [["fire", PlayerCommand.FIRE], ["jump", PlayerCommand.JUMP], ["jet", PlayerCommand.JET], ["use", PlayerCommand.USE], ["deploy", PlayerCommand.DEPLOY], ["ski", PlayerCommand.SKI]]:
		if Input.is_action_pressed(pair[0]):
			command.buttons |= pair[1]
	return command
