class_name LadderScreen
extends Control

signal closed
signal round_pressed(round_index: int)

const TITLES: Array[String] = ["Ski practice", "Capture the flag", "Capture and hold"]
const GOALS: Array[String] = [
	"Jet over the crest and grab the flag.",
	"Saltwake Flats · 4v4 · Easy bots · First capture wins",
	"Gannet Reach · 6v6 · Hard bots · Win the 4-minute round",
]

var buttons: Array[MenuKit.CoverButton] = []


func _init() -> void:
	name = "LadderScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = MenuKit.theme()
	var column := MenuKit.screen(self, "Bot ladder")
	var rows := MenuKit.rows(column, 5)
	for round_index in TITLES.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", MenuKit.pxi(12))
		rows.add_child(row)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = SIZE_EXPAND_FILL
		text.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(text)
		var title := MenuKit.heading(TITLES[round_index], 24)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		text.add_child(title)
		text.add_child(MenuKit.ink_label(GOALS[round_index], 14))
		var button := MenuKit.button("Replay", round_pressed.emit.bind(round_index))
		buttons.append(button)
		row.add_child(button)
	var bottom := MenuKit.button_row(column)
	bottom.add_child(MenuKit.button("Back", close, MenuKit.BUTTON_SIZE, true))
	hide()


func open() -> void:
	var cleared := BotLadder.completed()
	var next := mini(cleared + 1, BotLadder.Round.HOLD)
	for round_index in buttons.size():
		var button := buttons[round_index]
		button.disabled = not BotLadder.unlocked(round_index, cleared)
		button.focus_mode = FOCUS_NONE if button.disabled else FOCUS_ALL
		button.filled = round_index == cleared + 1
		button.words = "LOCKED" if button.disabled else ("REPLAY" if round_index <= cleared else "PLAY")
		button.queue_redraw()
	show()
	buttons[next].grab_focus()


func close() -> void:
	hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		Sound.click(true)
		close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		close()
