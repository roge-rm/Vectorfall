class_name ResultsBoard
extends Control

signal closed

var game: Match
var viewer: Soldier
var rows: VBoxContainer
var back: Button
var scroll: ScrollContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	theme = MenuKit.theme()
	var column := MenuKit.screen(self, "Match results")
	column.size_flags_horizontal = SIZE_EXPAND_FILL
	rows = MenuKit.rows(column)
	scroll = rows.get_parent().get_parent()
	scroll.focus_mode = FOCUS_ALL
	scroll.gui_input.connect(_scroll_input)
	var footer := MenuKit.button_row(column)
	back = MenuKit.button("Back", closed.emit, 22, true)
	footer.add_child(back)
	hide()


func open() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for team in 2:
		var heading := MenuKit.heading("%s · %d" % [Soldier.TEAM_NAMES[team], game.scores[team]], 26)
		rows.add_child(heading)
		_add_row("Player", MatchResults.HEADINGS, true)
		for who: Soldier in game.entities.values():
			if who.team == team:
				var label := "You" if who == viewer else who.display_name
				_add_row(label, game.results.counts.get(who.entity_id, MatchResults.empty_row()))
		for entry in game.results.former:
			if entry.team == team:
				_add_row("%s (previous)" % entry.name, entry.counts)
	MenuKit.scroll_to_top(rows)
	show()
	scroll.grab_focus()


func _scroll_input(event: InputEvent) -> void:
	var direction := int(event.is_action_pressed("ui_down", true)) - int(event.is_action_pressed("ui_up", true))
	if direction != 0:
		scroll.scroll_vertical += direction * MenuKit.pxi(25)
		scroll.accept_event()


func _add_row(label: String, cells: Array, header := false) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MenuKit.pxi(4))
	rows.add_child(row)
	var name_cell := _cell(label, header)
	name_cell.size_flags_stretch_ratio = 2.75
	name_cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(name_cell)
	for value in cells:
		row.add_child(_cell(str(value), header))


func _cell(words: String, header: bool) -> Label:
	var cell := MenuKit.ink_label(words, 15, InkUi.Face.BLACK if header else InkUi.Face.SERIF)
	cell.size_flags_horizontal = SIZE_EXPAND_FILL
	cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return cell
