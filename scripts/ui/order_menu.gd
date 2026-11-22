class_name OrderMenu
extends Control

## A short numbered list of bot orders and team calls, on a
## cream card under the compass, right of middle. V, the D-pad up or the
## ORDERS button opens it. Pick
## with the number keys, the D-pad (up and down, right to pick, left to go
## back) or a tap. With commander mode on, its last entry hands out roles:
## pick a bot, then a role. It only makes the order; LocalInput sends it in the
## next command.

signal chosen(order: int, arg: int)

enum Page { ORDERS, BOTS, ROLES, CALLS }
const ROLE_TITLES: Array[String] = ["Offence", "Defence", "Light defence", "Midfield", "Escort me", "Back to the plan"]

var page := Page.ORDERS
var selected := 0
var game: Match
## For the bots page: the bots on your team.
var director: BotDirector
var soldier: Soldier
var commander_mode := false
## The touch controls, which the card keeps clear of while they show.
var touch: TouchControls
## The bot picked on the bots page, or 0 for the nearest.
var _bot_pick := 0


func _init() -> void:
	name = "OrderMenu"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func open() -> void:
	page = Page.CALLS if _hold_match() else Page.ORDERS
	selected = 0
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Your team's bots, by id.
func team_bots() -> Array[BotBrain]:
	var found: Array[BotBrain] = []
	if director == null or soldier == null:
		return found
	for brain in director.brains:
		if brain.soldier.team == soldier.team:
			found.append(brain)
	return found


func title() -> String:
	match page:
		Page.BOTS:
			return "Which bot"
		Page.ROLES:
			return "Role"
		Page.CALLS:
			return "Team calls"
	return "Orders"


func entries() -> Array[String]:
	var list: Array[String] = []
	match page:
		Page.ORDERS:
			for kind in Orders.MENU:
				list.append(Orders.NAMES[kind])
			if game != null:
				list.append("Team calls")
			if commander_mode:
				list.append("Give roles")
		Page.BOTS:
			list.append("Nearest bot")
			# Room for 8 entries on the number keys.
			for brain in team_bots().slice(0, 7):
				list.append("%s (%s)" % [brain.soldier.display_name, BotBrain.ROLE_NAMES[brain.role]])
		Page.ROLES:
			list.assign(ROLE_TITLES)
		Page.CALLS:
			for kind in _calls():
				list.append(Orders.CALL_NAMES[kind])
	if page in [Page.ORDERS, Page.CALLS]:
		var call := _acknowledgeable()
		if not call.is_empty():
			list.append("Acknowledge %s" % String(Orders.CALL_MARKERS[call.kind]).to_lower())
	return list


func pick(index: int) -> void:
	if not visible or index < 0 or index >= entries().size():
		return
	match page:
		Page.ORDERS:
			if index < Orders.MENU.size():
				chosen.emit(Orders.MENU[index], 0)
				close()
			elif game != null and index == Orders.MENU.size():
				page = Page.CALLS
				selected = 0
			elif commander_mode and index == Orders.MENU.size() + int(game != null):
				page = Page.BOTS
				selected = 0
			else:
				_acknowledge()
		Page.BOTS:
			_bot_pick = 0 if index == 0 else team_bots()[index - 1].soldier.entity_id
			page = Page.ROLES
			selected = 0
		Page.ROLES:
			chosen.emit(Orders.Kind.SET_ROLE, Orders.role_arg(_bot_pick, Orders.ROLES[index]))
			close()
		Page.CALLS:
			var calls := _calls()
			if index < calls.size():
				chosen.emit(calls[index], 0)
				close()
			else:
				_acknowledge()
	queue_redraw()


func pick_selected() -> void:
	pick(selected)


## Back a page, or closed from the first.
func back() -> void:
	match page:
		Page.ORDERS:
			close()
		Page.BOTS:
			page = Page.ORDERS
		Page.ROLES:
			page = Page.BOTS
		Page.CALLS:
			if _hold_match():
				close()
			else:
				page = Page.ORDERS
	selected = 0
	queue_redraw()


func move(step: int) -> void:
	var count := entries().size()
	if count > 0:
		selected = posmod(selected + step, count)
	queue_redraw()


func _hold_match() -> bool:
	return game != null and not game.hold_points.is_empty()


func _calls() -> Array[int]:
	var calls: Array[int] = []
	if game != null and soldier != null and not soldier.dead:
		for kind in Orders.TEAM_CALLS:
			if game.team_calls.can_send(game, soldier, kind):
				calls.append(kind)
	return calls


func _acknowledgeable() -> Dictionary:
	if game != null and soldier != null and not soldier.dead and not game.over:
		return game.team_calls.latest(soldier, true)
	return {}


func _acknowledge() -> void:
	var call := _acknowledgeable()
	if not call.is_empty():
		chosen.emit(Orders.Kind.ACK_CALL, call.id)
		close()


## Where the panel goes: right of the touch stick's half (the left 45% of
## the screen) and below the score and compass, clear of the touch buttons
## on the right while they show. Returns [panel, row height, font size,
## entry boxes].
func layout() -> Array:
	var short := minf(size.x, size.y)
	var count := entries().size()
	var left := size.x * 0.45 + short * 0.03
	var top := short * 0.17
	var longest := 0.0
	var probe := 100
	for entry in entries() + [title()]:
		longest = maxf(longest, InkUi.width(entry.to_upper(), InkUi.Face.BLACK, probe))
	# Rows get shorter, and the words with them, until the card is clear of
	# the touch buttons on the right and its longest entry fits.
	var scale := 1.0
	var width := 0.0
	var start := left
	while true:
		left = start
		var row := short * 0.07 * scale
		var font := short * 0.045 * scale
		var tall := row * (count + 1) + short * 0.01
		var right := size.x - short * 0.03
		if touch != null and touch.visible:
			for k in TouchControls.BUTTONS.size():
				var centre := touch.button_centre(k)
				var reach := touch.button_radius(k)
				var span_top := centre.y - reach
				var span_bottom := centre.y + reach
				if k == TouchControls.ORDERS_BUTTON:
					var box := touch.orders_rect()
					span_top = box.position.y
					span_bottom = box.end.y
				if span_bottom > top and span_top < top + tall:
					if centre.x > size.x * 0.5:
						right = minf(right, centre.x - reach - short * 0.02)
					else:
						left = maxf(left, centre.x + reach + short * 0.02)
		var needed := longest * font / probe + font * 0.9 + short * 0.05
		width = minf(maxf(short * 0.62 * scale, needed), right - left)
		if width >= needed or scale <= 0.4:
			break
		scale -= 0.05
	var row_height := short * 0.07 * scale
	var corner := Vector2(left, top)
	var panel := Rect2(corner, Vector2(width, row_height * (count + 1) + short * 0.01))
	var boxes: Array[Rect2] = []
	for k in count:
		boxes.append(Rect2(corner + Vector2(0.0, row_height * (k + 1)), Vector2(width, row_height)))
	return [panel, row_height, roundi(short * 0.045 * scale), boxes]


## The entry under a point on screen, or -1.
func item_at(at: Vector2) -> int:
	if not visible:
		return -1
	var boxes: Array[Rect2] = layout()[3]
	for k in boxes.size():
		if boxes[k].has_point(at):
			return k
	return -1


## True if a point is on the menu's panel.
func covers(at: Vector2) -> bool:
	return visible and (layout()[0] as Rect2).has_point(at)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var short := minf(size.x, size.y)
	var parts := layout()
	var panel: Rect2 = parts[0]
	var row: float = parts[1]
	var font_size: int = parts[2]
	var boxes: Array[Rect2] = parts[3]
	var list := entries()
	var line := maxf(2.0, short / InkUi.DESIGN_HEIGHT * 2.0)
	var pad := short * 0.025
	InkUi.box(self, panel, InkUi.CREAM, line)
	# An ink title band with a thin stripe under it.
	var band := Rect2(panel.position, Vector2(panel.size.x, row))
	draw_rect(band, InkUi.INK)
	InkUi.stripes(self, Rect2(band.position.x, band.end.y - line * 1.5, band.size.x, line * 1.5), true)
	InkUi.centred(self, Vector2(band.position.x + pad + InkUi.width(title().to_upper(), InkUi.Face.BLACK, font_size) * 0.5, band.get_center().y - line * 0.5), title().to_upper(), InkUi.Face.BLACK, font_size, InkUi.CREAM)
	var number_size := roundi(font_size * 0.7)
	var f := InkUi.face(InkUi.Face.BLACK)
	for k in boxes.size():
		var box := boxes[k]
		var chosen := k == selected
		if chosen:
			draw_rect(box.grow_individual(-line, 0.0, -line, 0.0), InkUi.INK)
		var baseline := box.position.y + (box.size.y + f.get_ascent(font_size) - f.get_descent(font_size)) * 0.5
		var x := box.position.x + pad
		InkUi.words(self, Vector2(x, baseline), "%d" % (k + 1), InkUi.Face.ITALIC, number_size, InkUi.AMBER if chosen else InkUi.RUST)
		InkUi.words(self, Vector2(x + font_size * 0.9, baseline), list[k].to_upper(), InkUi.Face.BLACK, font_size, InkUi.CREAM if chosen else InkUi.INK)
