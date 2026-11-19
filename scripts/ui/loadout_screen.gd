class_name LoadoutScreen
extends Control

## The loadout screen: a cream card over the game dimmed, with the three
## saved loadouts as tabs, the armour and pack on the left, one weapon per
## slot from what the armour allows on the right, and the hand grenades and
## mines it carries. Every change is saved in Settings and sent out through
## `chosen` at once, so on a station it's worn straight away and while dead
## it's what you respawn in. The match keeps running while it's open. Up and
## down move between rows, left and right change one.

signal chosen(loadout: Loadout)
signal closed

const ARMOUR_NAMES: Array[String] = ["Light", "Medium", "Heavy"]

## The saved loadout shown, and what it holds.
var slot := 0
var loadout := Loadout.standard()
var _tabs: Array[MenuKit.CoverButton] = []
var _left: VBoxContainer
var _right: VBoxContainer
var _done: MenuKit.CoverButton
## The value buttons up and down the screen, for focus.
var _order: Array[Control] = []


func _init() -> void:
	name = "LoadoutScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = MenuKit.theme()
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(InkUi.INK, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box := MenuKit.card(self, "Loadout", 660.0)
	var tabs := MenuKit.button_row(box)
	tabs.add_theme_constant_override("separation", MenuKit.pxi(10))
	for k in Settings.LOADOUT_SLOTS:
		var tab := MenuKit.button(ARMOUR_NAMES[1], pick_slot.bind(k), 20, false, false, k + 1)
		tab.toggle_mode = true
		tab.custom_minimum_size.x = MenuKit.px(150)
		tabs.add_child(tab)
		_tabs.append(tab)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", MenuKit.pxi(16))
	box.add_child(columns)
	_left = VBoxContainer.new()
	_right = VBoxContainer.new()
	for column in [_left, _right]:
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", MenuKit.pxi(8))
		columns.add_child(column)
	_done = MenuKit.button("Done", close, 22, false, true)
	MenuKit.button_row(box).add_child(_done)


## Shows the last saved loadout used, focused on its tab.
func open() -> void:
	slot = Settings.loadout_slot
	loadout = Settings.current_loadout()
	visible = true
	_rebuild()
	_tabs[slot].grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## Shows a saved loadout and sends it.
func pick_slot(k: int) -> void:
	slot = clampi(k, 0, Settings.LOADOUT_SLOTS - 1)
	loadout = Settings.loadout(slot)
	_changed(_tabs[slot])


func set_armour(armour: int) -> void:
	loadout.armour = armour
	# Keep the weapons it can still carry, then fill its slots in the usual
	# order of the weapons.
	var kept: Array[int] = []
	for weapon in loadout.weapons:
		if Loadout.allows(armour, weapon) and kept.size() < Loadout.SLOTS[armour]:
			kept.append(weapon)
	for weapon in Weapon.GUNS:
		if kept.size() < Loadout.SLOTS[armour] and Loadout.allows(armour, weapon) and not kept.has(weapon):
			kept.append(weapon)
	loadout.weapons = kept
	loadout.grenades = Loadout.GRENADES[armour]
	loadout.mines = Loadout.MINES[armour]
	_changed(_row_value(_left, 0))


## Puts a weapon in a slot. One already carried in another slot swaps over.
func set_weapon(k: int, weapon: int) -> void:
	var had := loadout.weapons.find(weapon)
	if had >= 0 and had != k:
		loadout.weapons[had] = loadout.weapons[k]
	loadout.weapons[k] = weapon
	_changed(_row_value(_right, k))


func set_pack(pack: int) -> void:
	loadout.pack = pack
	_changed(_row_value(_left, 1))


func _changed(focus: Control) -> void:
	loadout = loadout.fixed()
	Settings.save_loadout(slot, loadout)
	chosen.emit(loadout.duplicate())
	# Made again after the press that got here is over, since it can free the
	# button that was pressed.
	_refresh.call_deferred(0 if _tabs.has(focus) else _order.find(focus))


func _refresh(focus_index: int) -> void:
	_rebuild()
	if visible and focus_index >= 0 and focus_index < _order.size():
		_order[focus_index].grab_focus()


func _row_value(column: Control, k: int) -> Control:
	if k >= column.get_child_count():
		return null
	return column.get_child(k).get_meta("value", null)


## Makes the rows again for the loadout shown.
func _rebuild() -> void:
	for k in _tabs.size():
		_tabs[k].set_pressed_no_signal(k == slot)
		_tabs[k].words = ARMOUR_NAMES[Settings.loadout(k).armour].to_upper()
		_tabs[k].queue_redraw()
	for column in [_left, _right]:
		for child in column.get_children():
			column.remove_child(child)
			child.queue_free()
	_left.add_child(_row("Armour", ARMOUR_NAMES, loadout.armour, set_armour))
	var packs: Array[String] = ["None"]
	for pack in Pack.all:
		packs.append(pack.name)
	_left.add_child(_row("Pack", packs, loadout.pack + 1, func(k: int) -> void: set_pack(k - 1)))
	var counts := "%d hand grenades · %d mines" % [Pack.scaled(loadout.grenades, loadout.pack), Pack.scaled(loadout.mines, loadout.pack)]
	var label := MenuKit.ink_label(counts, 14, InkUi.Face.ITALIC, InkUi.RUST)
	label.name = "Counts"
	_left.add_child(label)
	var allowed: Array[int] = []
	var names: Array[String] = []
	for weapon in Weapon.GUNS:
		if Loadout.allows(loadout.armour, weapon):
			allowed.append(weapon)
			names.append(Weapon.all[weapon].name)
	for k in loadout.weapons.size():
		var pick := func(i: int, at: int) -> void: set_weapon(at, allowed[i])
		_right.add_child(_row("Weapon %d" % (k + 1), names, allowed.find(loadout.weapons[k]), pick.bind(k)))
	_order.clear()
	_order.append(_tabs[slot])
	_order.append(_row_value(_left, 0))
	_order.append(_row_value(_left, 1))
	for k in loadout.weapons.size():
		_order.append(_row_value(_right, k))
	_order.append(_done)
	# Up and down go through the rows in order, from either column.
	for k in _order.size():
		var below := _order[mini(k + 1, _order.size() - 1)]
		var above := _order[maxi(k - 1, 0)]
		_order[k].focus_neighbor_bottom = _order[k].get_path_to(below)
		_order[k].focus_neighbor_top = _order[k].get_path_to(above)
		_order[k].focus_next = _order[k].get_path_to(below)
		_order[k].focus_previous = _order[k].get_path_to(above)
	for tab in _tabs:
		tab.focus_neighbor_bottom = tab.get_path_to(_order[1])
	_order[1].focus_neighbor_top = _order[1].get_path_to(_tabs[slot])


func _row(words: String, choices: Array[String], index: int, on_change: Callable) -> HBoxContainer:
	var row := MenuKit.stepper(words, choices, index, on_change)
	var value: MenuKit.CoverButton = row.get_meta("value")
	value.custom_minimum_size.x = MenuKit.px(150)
	value.font_size = MenuKit.pxi(17)
	var label := row.get_child(0) as Label
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return row


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") or event.is_action_pressed("loadout"):
		get_viewport().set_input_as_handled()
		Sound.click(true)
		close()
