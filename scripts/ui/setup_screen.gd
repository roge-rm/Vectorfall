class_name SetupScreen
extends Control

## Match setup: map, your team, bots and their skill on each side, time limit
## and captures to win. Starts with the last choices and saves them on Start.

signal start_pressed(setup: MatchSetup)
signal closed

const MAP_TITLES: Array[String] = [
	"Ochre Fold", "Test map", "Saltwake Flats", "Nightline Foundry", "Copper Steps",
	"Caldera Relay", "Gannet Reach", "White Signal", "Glass Ravine", "Greenfall Terraces", "Beacon Wreck",
]

var setup: MatchSetup
var _rows: VBoxContainer
var _supply_row: Control
var _captures_row: Control


func _init() -> void:
	name = "SetupScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = MenuKit.theme()
	var box := MenuKit.screen(self, "Match setup")
	_rows = MenuKit.rows(box)
	var bottom := MenuKit.button_row(box)
	bottom.add_child(MenuKit.button("Back", close, MenuKit.BUTTON_SIZE, true))
	bottom.add_child(MenuKit.button("Start", start, MenuKit.BUTTON_SIZE, false, true))


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
	if setup.map not in GameMap.RESUPPLY_ARENAS:
		setup.resupply = false
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


func _row(words: String, choices: Array[String], index: int, key: String, values: Array) -> Control:
	var row := MenuKit.stepper(words, choices, index, func(k: int) -> void:
		setup.set(key, values[k])
		if key == "map" or key == "hold":
			_update_mode_rows())
	_rows.add_child(row)
	return row


func _update_mode_rows() -> void:
	_supply_row.visible = setup.map in GameMap.RESUPPLY_ARENAS
	_captures_row.visible = not setup.hold


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
	_row("Mode", ["Capture the flag", "Capture and hold"], int(setup.hold), "hold", [false, true])
	_supply_row = _row("Midfield ammo", ["Off", "On"], int(setup.resupply), "resupply", [false, true])
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
	_captures_row = _row("Captures to win", captures, MenuKit.nearest(MatchSetup.CAPTURE_LIMITS, setup.capture_limit), "capture_limit", MatchSetup.CAPTURE_LIMITS)
	_update_mode_rows()
