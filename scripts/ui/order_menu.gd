class_name OrderMenu
extends Control

## The order menu: a short numbered list of orders for your team's bots, at
## the top of the screen right of middle. V, the D-pad up or the ORDERS button opens it. Pick
## with the number keys, the D-pad (up and down, right to pick, left to go
## back) or a tap. With commander mode on, its last entry hands out roles:
## pick a bot, then a role. It only makes the order; LocalInput sends it in the
## next command.

signal chosen(order: int, arg: int)

enum Page { ORDERS, BOTS, ROLES }
const ROLE_TITLES: Array[String] = ["Offence", "Defence", "Light defence", "Midfield", "Escort me", "Back to the plan"]

var page := Page.ORDERS
var selected := 0
## For the bots page: the bots on your team.
var director: BotDirector
var soldier: Soldier
var commander_mode := false
## The bot picked on the bots page, or 0 for the nearest.
var _bot_pick := 0


func _init() -> void:
	name = "OrderMenu"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func open() -> void:
	page = Page.ORDERS
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
	return "Orders"


func entries() -> Array[String]:
	var list: Array[String] = []
	match page:
		Page.ORDERS:
			for kind in Orders.MENU:
				list.append(Orders.NAMES[kind])
			if commander_mode:
				list.append("Give roles")
		Page.BOTS:
			list.append("Nearest bot")
			# Room for 8 entries on the number keys.
			for brain in team_bots().slice(0, 7):
				list.append("%s (%s)" % [brain.soldier.display_name, BotBrain.ROLE_NAMES[brain.role]])
		Page.ROLES:
			list.assign(ROLE_TITLES)
	return list


func pick(index: int) -> void:
	if not visible or index < 0 or index >= entries().size():
		return
	match page:
		Page.ORDERS:
			if index < Orders.MENU.size():
				chosen.emit(Orders.MENU[index], 0)
				close()
			else:
				page = Page.BOTS
				selected = 0
		Page.BOTS:
			_bot_pick = 0 if index == 0 else team_bots()[index - 1].soldier.entity_id
			page = Page.ROLES
			selected = 0
		Page.ROLES:
			chosen.emit(Orders.Kind.SET_ROLE, Orders.role_arg(_bot_pick, Orders.ROLES[index]))
			close()
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
	selected = 0
	queue_redraw()


func move(step: int) -> void:
	var count := entries().size()
	if count > 0:
		selected = posmod(selected + step, count)
	queue_redraw()


## Where the panel goes: right of the touch stick's half (the left 45% of
## the screen) and clear of the right hand buttons, below the score. Returns
## [panel, row height, font size, entry boxes].
func layout() -> Array:
	var short := minf(size.x, size.y)
	var count := entries().size()
	var left := size.x * 0.45 + short * 0.03
	var width := minf(short * 0.62, size.x - short * 0.25 - left)
	var scale := clampf(width / (short * 0.62), 0.6, 1.0)
	var row := short * 0.065 * scale
	var top := Vector2(left, short * 0.12)
	var panel := Rect2(top, Vector2(width, row * (count + 1) + short * 0.02))
	var boxes: Array[Rect2] = []
	for k in count:
		boxes.append(Rect2(top + Vector2(0.0, row * (k + 1)), Vector2(width, row)))
	return [panel, row, roundi(short * 0.04 * scale), boxes]


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
	InkUi.panel(self, panel, Color(InkUi.INK, 0.72), short)
	InkUi.text(self, panel.position + Vector2(short * 0.02, row * 0.7), title(), font_size, Color(0.95, 0.72, 0.3), HORIZONTAL_ALIGNMENT_LEFT)
	for k in boxes.size():
		var box := boxes[k]
		if k == selected:
			draw_rect(box.grow(-short * 0.006), Color(InkUi.PAPER, 0.22))
		InkUi.text(self, box.position + Vector2(short * 0.02, row * 0.68), "%d  %s" % [k + 1, list[k]], font_size, InkUi.PAPER, HORIZONTAL_ALIGNMENT_LEFT)
