class_name LocalInput
extends Node

## Turns keyboard and mouse, gamepad and touch into PlayerCommands for the
## local soldier, and keeps track of which kind of device was used last so the
## touch controls show only when you're using touch. Look speeds, invert
## look, gyro, aim assist and auto ski come from Settings each tick, so
## changes apply at once. Gyro aim and aim assist only change the yaw and
## pitch sent.

enum Device { KEYBOARD, GAMEPAD, TOUCH }

signal device_changed(device: Device)
## Esc, the gamepad's Start or the touch pause button, with the order menu shut.
signal pause_requested
## I, B or the gamepad's Back, for the loadout screen.
signal loadout_requested

## Radians per mouse pixel.
@export var mouse_sensitivity := 0.0025
## Radians per second at full right stick.
@export var stick_look_speed := 3.2
## Radians per pixel of touch drag.
@export var touch_sensitivity := 0.006
## Gyro turn rates below this, in radians per second, are drift and ignored.
const GYRO_DEAD_ZONE := 0.04
## Gravity across the screen past this, in m/s², says which way up the phone is.
const GYRO_UPRIGHT := 3.0

var device := Device.KEYBOARD
var source := Source.new()
var touch: TouchControls
## The soldier these commands drive, read for auto ski.
var soldier: Soldier
## The order menu, which the number keys and D-pad drive while it's open.
var menu: OrderMenu
var _mouse_look := Vector2.ZERO
## Weapon switches pressed since the last command, sent one tick each.
var _next_presses := 0
var _prev_presses := 0
var _slot_wanted := -1
## A grenade throw or mine pressed since the last command, sent for one tick.
## Taken from events rather than held state, so the D-pad picking from the
## open order menu doesn't also throw.
var _grenade_pending := false
var _mine_pending := false
## An order picked from the menu, sent in the next command.
var _order := 0
var _order_arg := 0
## A loadout picked on the loadout screen, sent in the next command.
var _loadout: Dictionary = {}
## While true, as when the loadout screen is open, commands only keep looking
## where they were and carry orders and loadouts.
var held_off := false
## Read each tick for gyro aim: the turn rate in radians per second and the
## gravity, both in the screen's frame. Tests swap in their own.
var read_gyro: Callable = Input.get_gyroscope
var read_gravity: Callable = Input.get_gravity
## True while the phone's screen frame reads upside down, see gyro_look().
var _gyro_flipped := false
var assist := AimAssist.new()


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


## Sends an order to your team's bots with the next command.
func queue_order(order: int, arg: int) -> void:
	_order = order
	_order_arg = arg


## Sends the loadout you want with the next command: worn at once on a
## station, otherwise at your next respawn.
func want_loadout(loadout: Loadout) -> void:
	_loadout = loadout.to_dict()


## V and the D-pad up open the menu; while it's open the number keys pick from
## it and the D-pad moves through it. True if the event was the menu's.
func _menu_input(event: InputEvent) -> bool:
	if menu == null:
		return false
	var pad := event as InputEventJoypadButton
	if pad != null and pad.pressed:
		if not menu.visible:
			if pad.button_index == JOY_BUTTON_DPAD_UP:
				menu.open()
				return true
			return false
		match pad.button_index:
			JOY_BUTTON_DPAD_UP:
				menu.move(-1)
			JOY_BUTTON_DPAD_DOWN:
				menu.move(1)
			JOY_BUTTON_DPAD_RIGHT:
				menu.pick_selected()
			JOY_BUTTON_DPAD_LEFT:
				menu.back()
			_:
				return false
		return true
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	if key.physical_keycode == KEY_V:
		menu.toggle()
		return true
	if not menu.visible:
		return false
	if key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_9:
		menu.pick(key.physical_keycode - KEY_1)
		return true
	if key.physical_keycode == KEY_ESCAPE or key.physical_keycode == KEY_BACKSPACE:
		menu.back()
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not held_off and _menu_input(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("next_weapon"):
		_next_presses += 1
	elif event.is_action_pressed("prev_weapon"):
		_prev_presses += 1
	elif event.is_action_pressed("weapon_1"):
		_slot_wanted = 0
	elif event.is_action_pressed("weapon_2"):
		_slot_wanted = 1
	elif event.is_action_pressed("weapon_3"):
		_slot_wanted = 2
	elif event.is_action_pressed("weapon_4"):
		_slot_wanted = 3
	elif event.is_action_pressed("loadout"):
		loadout_requested.emit()
	elif event.is_action_pressed("grenade"):
		_grenade_pending = true
	elif event.is_action_pressed("mine"):
		_mine_pending = true
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		pause_requested.emit()
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
	var mouse := -_mouse_look * mouse_sensitivity * Settings.look_mouse
	_mouse_look = Vector2.ZERO
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	# Squared response, finer near the middle of the stick.
	var look := -stick * stick.abs() * stick_look_speed * Settings.look_pad * delta
	if touch != null:
		look -= touch.take_look() * touch_sensitivity * Settings.look_touch
	if Settings.invert_look:
		mouse.y = -mouse.y
		look.y = -look.y
	var gyro := Vector2.ZERO
	var aim: AimAssist.Aim = null
	if held_off:
		mouse = Vector2.ZERO
		look = Vector2.ZERO
	else:
		if device == Device.TOUCH and Settings.gyro > 0.0 and (menu == null or not menu.visible):
			gyro = gyro_look(read_gyro.call(), read_gravity.call(), delta)
		if device != Device.KEYBOARD and Settings.aim_assist > 0 and (soldier == null or soldier.vehicle_id == 0):
			aim = assist.find(soldier, source.yaw, source.pitch)
			look *= AimAssist.slowdown(aim, Settings.aim_assist)
	var turn := mouse + look + gyro
	source.yaw = wrapf(source.yaw + turn.x, -PI, PI)
	source.pitch = clampf(source.pitch + turn.y, -Soldier.PITCH_LIMIT, Soldier.PITCH_LIMIT)
	# The pull only works while you move or look, so it never aims for you.
	if aim != null and (turn != Vector2.ZERO or _moving()):
		var pulled := AimAssist.pull(source.yaw, source.pitch, aim, AimAssist.PULL[Settings.aim_assist] * delta)
		source.yaw = wrapf(pulled.x, -PI, PI)
		source.pitch = clampf(pulled.y, -Soldier.PITCH_LIMIT, Soldier.PITCH_LIMIT)
	command.yaw = source.yaw
	command.pitch = source.pitch
	command.order = _order
	command.order_arg = _order_arg
	_order = 0
	_order_arg = 0
	command.loadout = _loadout
	_loadout = {}
	if held_off:
		_next_presses = 0
		_prev_presses = 0
		_slot_wanted = -1
		_grenade_pending = false
		_mine_pending = false
		if touch != null:
			touch.take_pulses()
		return command

	if device == Device.TOUCH:
		# Touches also make pretend mouse clicks, which mustn't fire.
		if touch != null:
			command.move = touch.stick
			command.buttons = touch.buttons | touch.take_pulses()
			# Holding jump skis, like space and the gamepad A button.
			if command.buttons & PlayerCommand.JUMP:
				command.buttons |= PlayerCommand.SKI
		_auto_ski(command)
		return command
	command.weapon = _slot_wanted
	_slot_wanted = -1
	if _next_presses > 0:
		command.buttons |= PlayerCommand.NEXT_WEAPON
		_next_presses -= 1
	elif _prev_presses > 0:
		command.buttons |= PlayerCommand.PREV_WEAPON
		_prev_presses -= 1
	if _grenade_pending:
		command.buttons |= PlayerCommand.GRENADE
		_grenade_pending = false
	if _mine_pending:
		command.buttons |= PlayerCommand.MINE
		_mine_pending = false
	command.move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	for pair: Array in [["fire", PlayerCommand.FIRE], ["jump", PlayerCommand.JUMP], ["jet", PlayerCommand.JET], ["use", PlayerCommand.USE], ["deploy", PlayerCommand.DEPLOY], ["board", PlayerCommand.BOARD], ["ski", PlayerCommand.SKI]]:
		if Input.is_action_pressed(pair[0]):
			command.buttons |= pair[1]
	_auto_ski(command)
	return command


## Yaw and pitch to add for a gyro turn rate over delta seconds. With the
## screen's x right, y up and z out of it, turning about y is yaw and about x
## is pitch. Godot turns the sensor into the screen's frame but can miss a
## flip from one landscape to the other, so gravity pointing up the screen
## means the frame is upside down and both turns change sign.
func gyro_look(rate: Vector3, gravity: Vector3, delta: float) -> Vector2:
	if absf(gravity.y) > GYRO_UPRIGHT:
		_gyro_flipped = gravity.y > 0.0
	var turn := Vector2(rate.y, rate.x)
	# A soft dead zone, so turns just past it start from nothing.
	var size := turn.length()
	if size <= GYRO_DEAD_ZONE:
		return Vector2.ZERO
	turn *= (size - GYRO_DEAD_ZONE) / size
	if _gyro_flipped:
		turn = -turn
	if Settings.invert_gyro:
		turn.y = -turn.y
	return turn * Settings.gyro * delta


## Whether the move stick or keys are pushed, for the aim assist pull.
func _moving() -> bool:
	if device == Device.TOUCH:
		return touch != null and touch.stick.length() > 0.1
	return Input.get_vector("move_left", "move_right", "move_back", "move_forward").length() > 0.1


## With auto ski on, skis whenever you're faster than a run or in the air,
## unless you're pulling back to brake.
func _auto_ski(command: PlayerCommand) -> void:
	if not Settings.auto_ski or soldier == null or command.move.y < -0.3:
		return
	var speed := Vector2(soldier.velocity.x, soldier.velocity.z).length()
	if not soldier.grounded or speed > soldier.tuning.run_speed + 1.0:
		command.buttons |= PlayerCommand.SKI
