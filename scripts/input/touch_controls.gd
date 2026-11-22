class_name TouchControls
extends Control

## On-screen controls: a stick that appears where your left thumb lands, drag
## anywhere else on the right half to look, and round buttons for fire, jet,
## jump (hold it to ski) and the weapon in hand (a tap switches to the next),
## small PACK, GREN and MINE buttons, and a small second FIRE just above the
## stick. JUMP, JET and the right FIRE sit close together on the right, with
## the small ones in the gaps round them.
## A touch that starts on JUMP or JET holds that button until it lifts, and
## also holds whichever of the three it's sliding over, so one thumb can jet
## and fire or ski and jet. A touch that starts on a FIRE button also looks
## when dragged, and doesn't slide onto other buttons. ORDERS, at the top
## right, opens the order menu, and while it's open a tap on it picks; the
## menu sits clear of the stick's half and the buttons. A small square pause
## button sits in the top left corner.
## Sizes are design pixels on a 390 pixel high screen (InkUi), scaled by the
## shorter side of the screen times Settings.touch_size, then held to the
## caps below so the middle of the view stays clear on any screen shape.

signal pause_pressed

## Left thumb movement for a full push, in design pixels.
const STICK_REACH := 39.0
## The stick's ring when no thumb is on it: centre from the bottom left
## corner and radius, and the thumb's radius, in design pixels.
const STICK_HOME := Vector2(89.0, 81.0)
const STICK_RING := 55.0
const STICK_THUMB := 20.0
## Name, command bit, distance of the centre from the bottom corner, radius,
## whether the corner is the left one, label size, fill and label colour.
## Distances and sizes in design pixels. ORDERS is a box at the top right
## instead, see orders_rect().
const BUTTONS := [
	["FIRE", PlayerCommand.FIRE, Vector2(66.0, 162.0), 42.0, false, 20, InkUi.PINK, InkUi.CREAM],
	["JET", PlayerCommand.JET, Vector2(64.0, 64.0), 40.0, false, 19, InkUi.ORANGE, InkUi.INK],
	["JUMP", PlayerCommand.JUMP, Vector2(151.0, 65.0), 35.0, false, 17, InkUi.CREAM, InkUi.INK],
	["FIRE", PlayerCommand.FIRE, Vector2(118.0, 186.0), 32.0, true, 16, InkUi.CREAM, InkUi.INK],
	["SWAP", PlayerCommand.NEXT_WEAPON, Vector2(150.0, 134.0), 24.0, false, 13, InkUi.CREAM, InkUi.INK],
	["ORDERS", 0, Vector2.ZERO, 0.0, false, 16, InkUi.INK, InkUi.CREAM],
	["PACK", PlayerCommand.USE, Vector2(108.0, 114.0), 15.0, false, 10, InkUi.CREAM, InkUi.INK],
	["GREN", PlayerCommand.GRENADE, Vector2(84.0, 222.0), 15.0, false, 10, InkUi.CREAM, InkUi.INK],
	["MINE", PlayerCommand.MINE, Vector2(48.0, 222.0), 15.0, false, 10, InkUi.CREAM, InkUi.INK],
	["BOARD", PlayerCommand.BOARD, Vector2(145.0, 197.0), 24.0, false, 12, InkUi.CREAM, InkUi.INK],
]
## How opaque the round buttons are when not held.
const BUTTON_ALPHA := 0.55
const LEFT_FIRE_ALPHA := 0.3
## Indexes in BUTTONS of the weapon button, which shows the weapon in hand,
## and of ORDERS, PACK, GREN and MINE.
const WEAPON_BUTTON := 4
const ORDERS_BUTTON := 5
const PACK_BUTTON := 6
const GRENADE_BUTTON := 7
const MINE_BUTTON := 8
const BOARD_BUTTON := 9
## BUTTONS indexes a touch can slide between, once it started on JET or JUMP.
const SLIDE_GROUP := [0, 1, 2]
## How far past its edge a button still counts: where a touch starts, and for
## the buttons a sliding touch didn't start on.
const START_REACH := 1.2
const SLIDE_REACH := 1.3
## Design pixels the right cluster (FIRE, JET, JUMP and the small ones) takes in from the
## bottom right corner, and the stick and left FIRE from the bottom left.
const RIGHT_SPAN := Vector2(186.0, 238.0)
const LEFT_WIDE := 150.0
## Most of the screen each side may take: the right cluster within the right
## 30% of the width and the lower 60% of the height, the left side within the
## left 25% of the width. Both keep the middle third clear.
const RIGHT_SHARE := Vector2(0.3, 0.6)
const LEFT_SHARE := 0.25
## On a phone or tablet, the most a design pixel can be in millimetres at
## 100%, so a big tablet doesn't get huge buttons. A 20:9 phone of about 400
## dpi stays under it and looks the same as without it.
const MM_PER_DESIGN := 0.22
## With Settings.touch_scheme 1 the stick also jets: a second touch within
## STICK_TAP_SECONDS of the last one lifting, held, or a push past
## STICK_JET_PUSH times the ring's radius.
const STICK_TAP_SECONDS := 0.3
const STICK_JET_PUSH := 1.15
## Buttons sent for one tick per tap.
const PULSES := PlayerCommand.NEXT_WEAPON | PlayerCommand.GRENADE | PlayerCommand.MINE | PlayerCommand.BOARD
## Buttons held while touched and also sent for a tick on the tap, so a
## quick tap between ticks still toggles a pack.
const HELD_AND_TAPPED := PlayerCommand.USE

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
## When the last stick touch lifted, in msec, and whether this one is a double tap.
var _clock := 0.0
var _stick_lifted := -100000.0
var _stick_double := false
## The order menu, opened by ORDERS and picked from by taps.
var menu: OrderMenu
## Size of the controls, times the normal size.
var scale_factor := 1.0
## The soldier they drive, read for the weapon in hand and what's left.
var soldier: Soldier
var movement_only := false
## While true, as when the loadout screen is open, touches are left to the
## screen above.
var blocked := false:
	set(value):
		blocked = value
		if blocked:
			release_all()
var _orders_rect := Rect2()
var _orders_for_size := Vector2(-1.0, -1.0)
var _orders_for_scale := 0.0


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


## Pixels per design pixel for the buttons and stick: the short side times
## the size setting, held to the screen share caps and on a phone or tablet
## to MM_PER_DESIGN.
func design_unit() -> float:
	var s := _short_side() * scale_factor / InkUi.DESIGN_HEIGHT
	s = minf(s, physical_cap())
	s = minf(s, size.x * RIGHT_SHARE.x / RIGHT_SPAN.x)
	s = minf(s, size.y * RIGHT_SHARE.y / RIGHT_SPAN.y)
	return minf(s, size.x * LEFT_SHARE / LEFT_WIDE)


## The most pixels per design pixel the screen's size in millimetres allows
## at this size setting, or INF off a phone or tablet.
func physical_cap() -> float:
	if not OS.has_feature("mobile") or not is_inside_tree():
		return INF
	var dpi := float(DisplayServer.screen_get_dpi())
	var window := Vector2(DisplayServer.window_get_size())
	var view := get_viewport_rect().size
	if dpi <= 0.0 or window.y <= 0.0 or view.y <= 0.0:
		return INF
	# Screen pixels per pixel here, as the canvas is stretched to the window.
	var stretch := window.y / view.y
	return MM_PER_DESIGN / 25.4 * dpi * scale_factor / stretch


func button_centre(k: int) -> Vector2:
	if k == ORDERS_BUTTON:
		return orders_rect().get_center()
	var s := design_unit()
	var from_corner: Vector2 = BUTTONS[k][2]
	var x := from_corner.x * s if BUTTONS[k][4] else size.x - from_corner.x * s
	return Vector2(x, size.y - from_corner.y * s)


## For ORDERS, half its width.
func button_radius(k: int) -> float:
	if k == ORDERS_BUTTON:
		return orders_rect().size.x * 0.5
	return BUTTONS[k][3] * design_unit()


## The ORDERS box: 12 from the right, 48 from the top, 44 high. Kept until
## the size or the size setting changes.
func orders_rect() -> Rect2:
	if size == _orders_for_size and scale_factor == _orders_for_scale:
		return _orders_rect
	var s := design_unit()
	var wide := InkUi.width("ORDERS", InkUi.Face.BLACK, roundi(16.0 * s)) + 28.0 * s
	_orders_rect = Rect2(size.x - 12.0 * s - wide, 48.0 * s, wide, 44.0 * s)
	_orders_for_size = size
	_orders_for_scale = scale_factor
	return _orders_rect


## The stick's ring when no thumb is on it, and its radius.
func stick_home() -> Vector2:
	var s := design_unit()
	return Vector2(STICK_HOME.x * s, size.y - STICK_HOME.y * s)


func stick_radius() -> float:
	return STICK_RING * design_unit()


## The pause button, a 34 design pixel square at the top left. It doesn't
## grow with the touch size setting.
func pause_rect() -> Rect2:
	var s := _short_side() / InkUi.DESIGN_HEIGHT
	return Rect2(Vector2(12.0, 8.0) * s, Vector2(34.0, 34.0) * s)


func pause_centre() -> Vector2:
	return pause_rect().get_center()


func pause_radius() -> float:
	return pause_rect().size.x * 0.5


# Touches are tracked even while hidden, since the first touch is what shows
# the controls.
func _input(event: InputEvent) -> void:
	if blocked:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event)
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
			var reach := STICK_REACH * design_unit()
			var offset: Vector2 = (_stick_at - _stick_origin).limit_length(reach) / reach
			stick = Vector2(offset.x, -offset.y)
			_update_buttons()
			queue_redraw()
		elif role is String and role == "look":
			_look += event.relative


func button_shown(k: int) -> bool:
	if movement_only:
		return k == 1 or k == 2
	if soldier == null or soldier.game == null:
		return k != BOARD_BUTTON
	if k == ORDERS_BUTTON and not soldier.game.hold_points.is_empty():
		return false
	var hull: Vehicle = soldier.game.fleet.hulls.get(soldier.vehicle_id)
	if hull == null:
		return k != BOARD_BUTTON or soldier.game.fleet.nearby(soldier) != null
	match k:
		PACK_BUTTON, GRENADE_BUTTON, MINE_BUTTON:
			return false
		WEAPON_BUTTON:
			return hull.uses_personal_weapon(soldier.vehicle_seat)
		1, 2:
			return hull.flies() and soldier.vehicle_seat == 0
		0, 3:
			return hull.uses_personal_weapon(soldier.vehicle_seat) or (Vehicle.WEAPONS[hull.kind] >= 0 and soldier.vehicle_seat == hull.weapon_seat())
	return true


## The button under a point, or -1. Where circles overlap the nearest centre wins.
func _button_at(at: Vector2, reach: float, only: Array = []) -> int:
	var best := -1
	var best_score := reach
	for k in BUTTONS.size():
		if not button_shown(k):
			continue
		if not only.is_empty() and not only.has(k):
			continue
		var score := at.distance_to(button_centre(k)) / button_radius(k)
		if k == ORDERS_BUTTON:
			# Distance out from the box as a share of its half size.
			var rect := orders_rect()
			var off := (at - rect.get_center()).abs() / (rect.size * 0.5)
			score = maxf(off.x, off.y)
		if score < best_score:
			best_score = score
			best = k
	return best


## Bits held by a touch that started on the button with bit `start`.
func _slide_bits(start: int, at: Vector2) -> int:
	var k := _button_at(at, SLIDE_REACH, SLIDE_GROUP)
	return start if k < 0 else start | int(BUTTONS[k][1])


func _press(index: int, at: Vector2) -> void:
	# Buttons come first, then the open menu, so a tap meant for a button
	# never picks an order.
	if pause_rect().grow(pause_radius() * (START_REACH - 1.0)).has_point(at):
		_touches[index] = "pause"
		get_viewport().set_input_as_handled()
		return
	var k := _button_at(at, START_REACH)
	if k < 0 and menu != null and menu.covers(at):
		_touches[index] = "menu"
		menu.pick(menu.item_at(at))
		return
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
			if bit & HELD_AND_TAPPED:
				_pulses |= bit
		_update_buttons()
		return
	if at.x < size.x * 0.45:
		_touches[index] = "stick"
		_stick_origin = at
		_stick_at = at
		stick = Vector2.ZERO
		_stick_double = _clock - _stick_lifted <= STICK_TAP_SECONDS
		_update_buttons()
	else:
		_touches[index] = "look"


func _release(event: InputEventScreenTouch) -> void:
	var index := event.index
	if not _touches.has(index):
		return
	var role: Variant = _touches[index]
	_touches.erase(index)
	if role is String:
		match role:
			"stick":
				stick = Vector2.ZERO
				_stick_lifted = _clock
				_stick_double = false
			"pause":
				# Open after this tap so its emulated click can't reach the menu.
				get_viewport().set_input_as_handled()
				if not event.canceled and pause_rect().has_point(event.position):
					pause_pressed.emit.call_deferred()
	_update_buttons()


## Frame time for the double tap, so it matches in tests and on a device.
func _process(delta: float) -> void:
	_clock += delta


## Buttons held are the ones any touch holds.
func _update_buttons() -> void:
	buttons = 0
	for role: Variant in _touches.values():
		if role is int:
			buttons |= role
		elif role is Array:
			buttons |= role[1]
	if stick_jets():
		buttons |= PlayerCommand.JET


## Whether the stick is jetting: on the second touch of a double tap, or
## pushed past its ring.
func stick_jets() -> bool:
	if Settings.touch_scheme != 1 or not _touches.values().has("stick"):
		return false
	return _stick_double or (_stick_at - _stick_origin).length() > STICK_JET_PUSH * stick_radius()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		release_all()


## Lets go of every touch, for when releases can't be seen, like while
## paused.
func release_all() -> void:
	_touches.clear()
	stick = Vector2.ZERO
	_stick_double = false
	buttons = 0
	_look = Vector2.ZERO
	_pulses = 0
	queue_redraw()


func _draw() -> void:
	if size.y <= 0.0:
		return
	var s := design_unit()
	var line := maxf(2.0, 2.0 * s)
	for k in BUTTONS.size():
		if not button_shown(k):
			continue
		var held: bool = buttons & BUTTONS[k][1] != 0 or (k == ORDERS_BUTTON and menu != null and menu.visible)
		var fill: Color = BUTTONS[k][6]
		var ink: Color = BUTTONS[k][7]
		var label: String = BUTTONS[k][0]
		var label_size := roundi(float(BUTTONS[k][5]) * s)
		# Faded while there's nothing for it to do.
		var spent := false
		if soldier != null:
			if soldier.vehicle_id != 0:
				match k:
					1: label = "UP"
					2: label = "DOWN"
					BOARD_BUTTON: label = "EXIT"
			match k:
				WEAPON_BUTTON:
					label = Weapon.all[soldier.weapon_slot()].short_name
				PACK_BUTTON:
					spent = soldier.pack() == null
					if soldier.pack() != null and soldier.pack().use == Pack.Use.DEPLOY:
						label = "PLACE"
						spent = not soldier.deploy_ready
					if soldier.pack_on:
						fill = InkUi.ORANGE
				GRENADE_BUTTON:
					spent = soldier.grenades <= 0
				MINE_BUTTON:
					spent = soldier.mines <= 0
		if k == ORDERS_BUTTON:
			var rect := orders_rect()
			draw_rect(rect, InkUi.PINK if held else fill)
			InkUi.centred(self, rect.get_center(), label, InkUi.Face.BLACK, label_size, InkUi.INK if held else ink)
			continue
		var centre := button_centre(k)
		var radius := button_radius(k)
		# See-through so the view shows behind, the left FIRE most of all.
		# Held buttons go solid ink with cream words.
		var a := 1.0 if held else (LEFT_FIRE_ALPHA if BUTTONS[k][4] or spent else BUTTON_ALPHA)
		var words_a := minf(1.0, a + 0.3)
		# Long weapon names shrink to fit inside the circle.
		var fit := InkUi.width(label, InkUi.Face.BLACK, label_size)
		if fit > radius * 1.7:
			label_size = maxi(1, floori(label_size * radius * 1.7 / fit))
		draw_circle(centre, radius, Color(InkUi.INK, a))
		draw_circle(centre, radius - line, InkUi.INK if held else Color(fill, a))
		InkUi.centred(self, centre, label, InkUi.Face.BLACK, label_size, InkUi.CREAM if held else Color(ink, words_a))
	var origin := _stick_origin
	var knob := _stick_at
	if not _touches.values().has("stick"):
		origin = stick_home()
		knob = origin
	var ring := stick_radius()
	draw_circle(origin, ring, Color(InkUi.INK, 0.25))
	draw_arc(origin, ring - line * 0.5, 0.0, TAU, 48, InkUi.CREAM, line, true)
	# The thumb travels to the ring's edge at a full push.
	var thumb := STICK_THUMB * s
	var reach := STICK_REACH * s
	var push := (knob - origin).limit_length(reach) / reach
	var knob_at := origin + push * (ring - thumb)
	var jetting := stick_jets()
	draw_circle(knob_at, thumb, InkUi.INK)
	draw_circle(knob_at, thumb - line, InkUi.ORANGE if jetting else InkUi.CREAM)
	if jetting:
		draw_arc(origin, ring - line * 0.5, 0.0, TAU, 48, Color(InkUi.ORANGE, 0.8), line * 1.5, true)
	# The pause button: two ink bars in a cream square.
	var pause := pause_rect()
	var p := pause.size.x
	InkUi.box(self, pause, InkUi.CREAM, maxf(2.0, p / 17.0))
	for side: float in [-1.0, 1.0]:
		var bar := Rect2(pause.get_center() + Vector2(side * p * 0.14 - p * 0.06, -p * 0.22), Vector2(p * 0.12, p * 0.44))
		draw_rect(bar, InkUi.INK)
