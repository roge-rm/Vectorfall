class_name DrillsScreen
extends Control

signal closed
signal drill_pressed(index: int)

const TITLES: Array[String] = ["Air shots", "Flag run", "Restore power"]
const GOALS: Array[String] = [
	"Lead a flying target with the disc launcher.",
	"Grab the flag at speed and ski through the exit.",
	"Use cover and a repair pack to bring a generator back online.",
]

var buttons: Array[MenuKit.CoverButton] = []


func _init() -> void:
	name = "DrillsScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = MenuKit.theme()
	var column := MenuKit.screen(self, "Drills")
	var rows := MenuKit.rows(column, 5)
	for index in TITLES.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", MenuKit.pxi(12))
		rows.add_child(row)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = SIZE_EXPAND_FILL
		text.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(text)
		var title := MenuKit.heading(TITLES[index], 24)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		text.add_child(title)
		text.add_child(MenuKit.ink_label(GOALS[index], 14))
		var button := MenuKit.button("Play", drill_pressed.emit.bind(index))
		row.add_child(button)
		buttons.append(button)
	var bottom := MenuKit.button_row(column)
	bottom.add_child(MenuKit.button("Back", close, MenuKit.BUTTON_SIZE, true))
	hide()


func open(index: int) -> void:
	show()
	buttons[clampi(index, 0, buttons.size() - 1)].grab_focus()


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
