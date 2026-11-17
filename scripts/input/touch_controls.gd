class_name TouchControls
extends Control

## On-screen controls: a stick that appears where your left thumb lands, drag
## anywhere else on the right half to look, and round buttons for fire, jet and
## jump, and a SKI button that turns skiing on and off. Sizes follow the
## shorter side of the screen.

## Left thumb movement in pixels for a full push, as a share of the short side.
const STICK_REACH := 0.1
const BUTTONS := [
	["FIRE", PlayerCommand.FIRE, Vector2(0.15, 0.4), 0.1],
	["JET", PlayerCommand.JET, Vector2(0.36, 0.15), 0.095],
	["JUMP", PlayerCommand.JUMP, Vector2(0.13, 0.14), 0.075],
	["SKI", PlayerCommand.SKI, Vector2(0.36, 0.36), 0.065],
]
## Buttons that a tap turns on and off rather than being held.
const TOGGLES := PlayerCommand.SKI

## x is right and y is forward, like PlayerCommand.move.
var stick := Vector2.ZERO
var buttons := 0
var _look := Vector2.ZERO
## Touch index to what it's doing: "stick", "look" or a button's bit.
var _touches: Dictionary[int, Variant] = {}
var _stick_origin := Vector2.ZERO
var _stick_at := Vector2.ZERO


func _init() -> void:
	name = "TouchControls"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Look movement in pixels since the last call.
func take_look() -> Vector2:
	var look := _look
	_look = Vector2.ZERO
	return look


func _short_side() -> float:
	return minf(size.x, size.y)


func button_centre(k: int) -> Vector2:
	var s := _short_side()
	var from_corner: Vector2 = BUTTONS[k][2]
	return Vector2(size.x - from_corner.x * s, size.y - from_corner.y * s)


func button_radius(k: int) -> float:
	return BUTTONS[k][3] * _short_side()


# Touches are tracked even while hidden, since the first touch is what shows
# the controls.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index)
		queue_redraw()
	elif event is InputEventScreenDrag and _touches.has(event.index):
		var role: Variant = _touches[event.index]
		if role is String and role == "stick":
			_stick_at = event.position
			var reach := STICK_REACH * _short_side()
			var offset: Vector2 = (_stick_at - _stick_origin).limit_length(reach) / reach
			stick = Vector2(offset.x, -offset.y)
			queue_redraw()
		elif role is String and role == "look":
			_look += event.relative


func _press(index: int, at: Vector2) -> void:
	for k in BUTTONS.size():
		if at.distance_to(button_centre(k)) < button_radius(k) * 1.2:
			var bit: int = BUTTONS[k][1]
			if bit & TOGGLES:
				_touches[index] = "toggle"
				buttons ^= bit
			else:
				_touches[index] = bit
				buttons |= bit
			return
	if at.x < size.x * 0.45:
		_touches[index] = "stick"
		_stick_origin = at
		_stick_at = at
		stick = Vector2.ZERO
	else:
		_touches[index] = "look"


func _release(index: int) -> void:
	if not _touches.has(index):
		return
	var role: Variant = _touches[index]
	_touches.erase(index)
	if role is int:
		buttons &= ~role
	elif role == "stick":
		stick = Vector2.ZERO


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		_touches.clear()
		stick = Vector2.ZERO
		buttons = 0


func _draw() -> void:
	var s := _short_side()
	var font := get_theme_default_font()
	var font_size := int(s * 0.035)
	for k in BUTTONS.size():
		var centre := button_centre(k)
		var radius := button_radius(k)
		var held: bool = buttons & BUTTONS[k][1] != 0
		draw_circle(centre, radius, Color(1, 1, 1, 0.3 if held else 0.14))
		draw_arc(centre, radius, 0.0, TAU, 40, Color(1, 1, 1, 0.55), maxf(2.0, s * 0.004), true)
		var label: String = BUTTONS[k][0]
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, centre + Vector2(-width * 0.5, font_size * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.8))
	var reach := STICK_REACH * s
	var origin := _stick_origin
	var knob := _stick_at
	if not _touches.values().has("stick"):
		origin = Vector2(0.2 * s, size.y - 0.22 * s)
		knob = origin
	draw_circle(origin, reach, Color(1, 1, 1, 0.1))
	draw_arc(origin, reach, 0.0, TAU, 40, Color(1, 1, 1, 0.4), maxf(2.0, s * 0.004), true)
	draw_circle(origin + (knob - origin).limit_length(reach), reach * 0.4, Color(1, 1, 1, 0.35))
