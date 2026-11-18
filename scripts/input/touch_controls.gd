class_name TouchControls
extends Control

## On-screen controls: a stick that appears where your left thumb lands, drag
## anywhere else on the right half to look, and round buttons for fire, jet,
## jump (hold it to ski) and SWAP for the next weapon, and a small second FIRE
## on the left. JUMP, JET and the right FIRE sit close together on the right.
## A touch that starts on JUMP or JET holds that button until it lifts, and
## also holds whichever of the three it's sliding over, so one thumb can jet
## and fire or ski and jet. A touch that starts on a FIRE button also looks
## when dragged, and doesn't slide onto other buttons. ORDERS, above the
## right FIRE, opens the order menu, and while it's open a tap on it picks.
## Sizes follow the shorter side of the screen.

## Left thumb movement in pixels for a full push, as a share of the short side.
const STICK_REACH := 0.1
## Name, command bit, distance of the centre from the bottom corner as a share
## of the short side, radius, and whether the corner is the left one.
const BUTTONS := [
	["FIRE", PlayerCommand.FIRE, Vector2(0.13, 0.33), 0.1, false],
	["JET", PlayerCommand.JET, Vector2(0.13, 0.115), 0.095, false],
	["JUMP", PlayerCommand.JUMP, Vector2(0.32, 0.115), 0.075, false],
	["FIRE", PlayerCommand.FIRE, Vector2(0.4, 0.4), 0.065, true],
	["SWAP", PlayerCommand.NEXT_WEAPON, Vector2(0.48, 0.1), 0.06, false],
	["ORDERS", 0, Vector2(0.1, 0.6), 0.07, false],
]
## The ORDERS button's index in BUTTONS.
const ORDERS_BUTTON := 5
## BUTTONS indexes a touch can slide between, once it started on JET or JUMP.
const SLIDE_GROUP := [0, 1, 2]
## How far past its edge a button still counts: where a touch starts, and for
## the buttons a sliding touch didn't start on.
const START_REACH := 1.2
const SLIDE_REACH := 1.3
## Buttons sent for one tick per tap.
const PULSES := PlayerCommand.NEXT_WEAPON

## x is right and y is forward, like PlayerCommand.move.
var stick := Vector2.ZERO
var buttons := 0
var _look := Vector2.ZERO
## Taps on PULSES buttons not yet sent.
var _pulses := 0
## Touch index to what it's doing: "stick", "look", "pulse", a button's bit (a
## FIRE touch) or a [start bit, bits held now] pair for a sliding touch.
var _touches: Dictionary[int, Variant] = {}
var _stick_origin := Vector2.ZERO
var _stick_at := Vector2.ZERO
## The order menu, opened by ORDERS and picked from by taps.
var menu: OrderMenu


func _init() -> void:
	name = "TouchControls"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Taps on one-shot buttons since the last call.
func take_pulses() -> int:
	var taken := _pulses
	_pulses = 0
	return taken


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
	var x := from_corner.x * s if BUTTONS[k][4] else size.x - from_corner.x * s
	return Vector2(x, size.y - from_corner.y * s)


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
		if role is Array:
			role[1] = _slide_bits(role[0], event.position)
			_update_buttons()
			queue_redraw()
		elif role is int and role == PlayerCommand.FIRE:
			_look += event.relative
		elif role is String and role == "stick":
			_stick_at = event.position
			var reach := STICK_REACH * _short_side()
			var offset: Vector2 = (_stick_at - _stick_origin).limit_length(reach) / reach
			stick = Vector2(offset.x, -offset.y)
			queue_redraw()
		elif role is String and role == "look":
			_look += event.relative


## The button under a point, or -1. Where circles overlap the nearest centre wins.
func _button_at(at: Vector2, reach: float, only: Array = []) -> int:
	var best := -1
	var best_score := reach
	for k in BUTTONS.size():
		if not only.is_empty() and not only.has(k):
			continue
		var score := at.distance_to(button_centre(k)) / button_radius(k)
		if score < best_score:
			best_score = score
			best = k
	return best


## Bits held by a touch that started on the button with bit `start`.
func _slide_bits(start: int, at: Vector2) -> int:
	var k := _button_at(at, SLIDE_REACH, SLIDE_GROUP)
	return start if k < 0 else start | int(BUTTONS[k][1])


func _press(index: int, at: Vector2) -> void:
	if menu != null and menu.covers(at):
		_touches[index] = "menu"
		menu.pick(menu.item_at(at))
		return
	var k := _button_at(at, START_REACH)
	if k == ORDERS_BUTTON:
		_touches[index] = "menu"
		if menu != null:
			menu.toggle()
		return
	if k >= 0:
		var bit: int = BUTTONS[k][1]
		if bit & PULSES:
			_touches[index] = "pulse"
			_pulses |= bit
		elif k == 1 or k == 2:
			_touches[index] = [bit, _slide_bits(bit, at)]
		else:
			_touches[index] = bit
		_update_buttons()
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
	if role is String and role == "stick":
		stick = Vector2.ZERO
	_update_buttons()


## Buttons held are the ones any touch holds.
func _update_buttons() -> void:
	buttons = 0
	for role: Variant in _touches.values():
		if role is int:
			buttons |= role
		elif role is Array:
			buttons |= role[1]


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		_touches.clear()
		stick = Vector2.ZERO
		buttons = 0


func _draw() -> void:
	var s := _short_side()
	var font := InkUi.font()
	var font_size := int(s * 0.035)
	var line := maxf(2.0, s * 0.005)
	for k in BUTTONS.size():
		var centre := button_centre(k)
		var radius := button_radius(k)
		var held: bool = buttons & BUTTONS[k][1] != 0 or (k == ORDERS_BUTTON and menu != null and menu.visible)
		# Ink rings round a pale fill, solid ink while held.
		draw_circle(centre + Vector2(line, line), radius + line, Color(InkUi.INK, 0.35))
		draw_circle(centre, radius, Color(InkUi.INK, 0.55) if held else Color(InkUi.PAPER, 0.18))
		draw_arc(centre, radius, 0.0, TAU, 40, Color(InkUi.INK, 0.8), line * 2.0, true)
		draw_arc(centre, radius - line * 1.5, 0.0, TAU, 40, Color(InkUi.PAPER, 0.6), line * 0.6, true)
		var label: String = BUTTONS[k][0]
		var label_size := font_size
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
		if width > radius * 1.7:
			# Long labels shrink to fit inside the ring.
			label_size = int(label_size * radius * 1.7 / width)
			width = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
		var at := centre + Vector2(-width * 0.5, label_size * 0.35)
		draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, maxi(4, label_size / 4), Color(InkUi.INK, 0.85))
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, Color(InkUi.PAPER, 0.9))
	var reach := STICK_REACH * s
	var origin := _stick_origin
	var knob := _stick_at
	if not _touches.values().has("stick"):
		origin = Vector2(0.2 * s, size.y - 0.22 * s)
		knob = origin
	draw_circle(origin, reach, Color(InkUi.PAPER, 0.1))
	draw_arc(origin, reach, 0.0, TAU, 40, Color(InkUi.INK, 0.6), line * 2.0, true)
	draw_arc(origin, reach - line * 1.5, 0.0, TAU, 40, Color(InkUi.PAPER, 0.45), line * 0.6, true)
	var knob_at := origin + (knob - origin).limit_length(reach)
	draw_circle(knob_at, reach * 0.4 + line, Color(InkUi.INK, 0.7))
	draw_circle(knob_at, reach * 0.4, Color(InkUi.PAPER, 0.45))
