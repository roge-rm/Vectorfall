class_name SetupScreen
extends Control

## Match setup: map, your team, bots and their skill on each side, time limit
## and captures to win. Starts with the last choices and saves them on Start.

signal start_pressed(setup: MatchSetup)
signal closed

const MAP_TITLES: Array[String] = ["Ochre Fold", "Test map"]

var setup: MatchSetup
var _rows: VBoxContainer


func _init() -> void:
	name = "SetupScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = MenuKit.theme()
	var box := MenuKit.panel(self, "Match setup", 0.72)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	scroll.add_child(_rows)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 24)
	box.add_child(bottom)
	bottom.add_child(MenuKit.button("Back", close, MenuKit.BUTTON_SIZE, true))
	bottom.add_child(MenuKit.button("Start", start))


## Shows the screen with the last choices.
func open() -> void:
	setup = MatchSetup.load_saved()
	_build()
	visible = true
	MenuKit.focus_first(_rows)


func close() -> void:
	visible = false
	closed.emit()


func start() -> void:
	setup.save()
	start_pressed.emit(setup)


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		Sound.click(true)
		close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		close()


func _row(words: String, choices: Array[String], index: int, key: String, values: Array) -> void:
	_rows.add_child(MenuKit.stepper(words, choices, index, func(k: int) -> void:
		setup.set(key, values[k])))


static func _numbers(top: int) -> Array[String]:
	var words: Array[String] = []
	for n in top + 1:
		words.append(str(n))
	return words


static func _range(top: int) -> Array:
	return range(top + 1)


func _build() -> void:
	for child in _rows.get_children():
		child.free()
	_row("Map", MAP_TITLES, maxi(GameMap.NAMES.find(setup.map), 0), "map", GameMap.NAMES)
	var teams: Array[String] = []
	for name_of: String in Soldier.TEAM_NAMES:
		teams.append(name_of)
	_row("Your team", teams, setup.team, "team", [0, 1])
	_row("Bots on your team", _numbers(MatchSetup.MAX_OWN_BOTS), setup.own_bots, "own_bots", _range(MatchSetup.MAX_OWN_BOTS))
	_row("Bots on their team", _numbers(MatchSetup.MAX_ENEMY_BOTS), setup.enemy_bots, "enemy_bots", _range(MatchSetup.MAX_ENEMY_BOTS))
	var skills: Array[String] = []
	for skill: String in BotDirector.SKILL_NAMES:
		skills.append(skill.capitalize())
	var levels := _range(BotDirector.SKILLS.size() - 1)
	_row("Your bots' skill", skills, setup.own_skill, "own_skill", levels)
	_row("Their bots' skill", skills, setup.enemy_skill, "enemy_skill", levels)
	var times: Array[String] = []
	for seconds in MatchSetup.TIME_LIMITS:
		times.append("%d min" % roundi(seconds / 60.0))
	_row("Time limit", times, MenuKit.nearest(MatchSetup.TIME_LIMITS, setup.time_limit), "time_limit", MatchSetup.TIME_LIMITS)
	var captures: Array[String] = []
	for n in MatchSetup.CAPTURE_LIMITS:
		captures.append(str(n))
	_row("Captures to win", captures, MenuKit.nearest(MatchSetup.CAPTURE_LIMITS, setup.capture_limit), "capture_limit", MatchSetup.CAPTURE_LIMITS)
