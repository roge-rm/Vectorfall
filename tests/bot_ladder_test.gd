extends SceneTree

const TEST_SETTINGS := "user://test-bot-ladder.cfg"
const MENU_SCENE := "res://scenes/menu.tscn"

var checks := TestWorld.Checks.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Settings.path = TEST_SETTINGS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	var saved := MatchSetup.new()
	saved.map = "test"
	saved.team = 1
	saved.save()
	MatchSetup.current = saved
	var old_save := ConfigFile.new()
	old_save.load(TEST_SETTINGS)
	old_save.set_value("practice", "best_ticks", 300)
	old_save.save(TEST_SETTINGS)

	change_scene_to_file(MENU_SCENE)
	await scene_changed
	var menu := current_scene as MainMenu
	var entry: MenuKit.CoverButton
	for button in menu.home.buttons:
		if button.words == "BOT LADDER":
			entry = button
	checks.check(entry != null, "the home cover opens Bot ladder")
	if entry == null:
		_finish()
		return
	entry.pressed.emit()
	checks.check(menu.ladder.visible and not menu.ladder.buttons[0].disabled and menu.ladder.buttons[1].disabled and menu.ladder.buttons[2].disabled,
		"only Ski Practice is available at the start, even with a saved best time")
	await process_frame
	await process_frame
	var play := menu.ladder.buttons[0]
	var scroll := menu.ladder.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
	checks.check(play.has_focus() and scroll.get_global_rect().encloses(play.get_global_rect().grow(MenuKit.px(4))),
		"the first Play button and its focus ring fit inside the ladder scroll area")
	checks.check(not BotLadder.record_clear(BotLadder.Round.HOLD), "a locked round cannot advance progress")
	menu.ladder.buttons[0].pressed.emit()
	await scene_changed
	var practice := current_scene as SkiPractice
	checks.check(practice != null and practice._ladder_run, "Ski Practice loads in ladder mode")
	practice.stage = SkiPractice.Stage.FLAG
	practice._on_flag_taken(1, practice.player.entity_id)
	checks.check(BotLadder.completed() == BotLadder.Round.SKI and practice._ladder_status.visible,
		"finishing Ski Practice saves the clear and shows the next unlock")
	practice._ladder_button.pressed.emit()
	await scene_changed
	menu = current_scene as MainMenu
	checks.check(menu.ladder.visible and menu.ladder.buttons[0].words == "REPLAY" and menu.ladder.buttons[1].words == "PLAY" and menu.ladder.buttons[2].disabled,
		"returning to the ladder shows the new unlock and allows replay")
	checks.check(root.gui_get_focus_owner() == menu.ladder.buttons[1], "focus moves to the newly unlocked round")

	menu.ladder.buttons[1].pressed.emit()
	await scene_changed
	var battle := current_scene
	var game: Match = battle.game
	checks.check(battle.map is SaltwakeFlats and game.flags.size() == 2 and game.settings.capture_limit == 1 and game.entities.size() == 8,
		"the second round is Saltwake Flats CTF with eight soldiers and one capture to win")
	checks.check(battle.bots.skill_levels == [BotDirector.NORMAL, BotDirector.NORMAL - 1], "the CTF opponents are Easy")
	game._end(1 - battle.player.team)
	checks.check(BotLadder.completed() == BotLadder.Round.SKI, "a CTF loss keeps the last round locked")
	battle.hud._restart_button.pressed.emit()
	await scene_changed
	battle = current_scene
	game = battle.game
	checks.check(battle.ladder_round == BotLadder.Round.FLAG and not game.over, "Restart gives a fresh attempt at the same round")
	game._capture(game.flags[1], battle.player)
	checks.check(game.over and battle.hud._ladder_status.visible and BotLadder.completed() == BotLadder.Round.FLAG,
		"a CTF win unlocks Capture and Hold")
	battle.hud._results_button.pressed.emit()
	checks.check(battle.results_board.visible, "match results still open from the ladder result card")
	battle.results_board.back.pressed.emit()
	battle.hud._end_menu_button.pressed.emit()
	await scene_changed

	menu = current_scene as MainMenu
	menu.ladder.buttons[2].pressed.emit()
	await scene_changed
	battle = current_scene
	game = battle.game
	checks.check(battle.map is GannetReach and game.hold_points.size() == 3 and game.entities.size() == 12 and game.settings.time_limit == 240.0,
		"the last round is a four-minute 6v6 Capture and Hold on Gannet Reach")
	checks.check(battle.bots.skill_levels == [BotDirector.NORMAL, BotDirector.NORMAL + 1], "the Hold opponents are Hard")
	game.scores[battle.player.team] = 1
	game.time_left = 0.0
	game._step_clock(0.0)
	checks.check(game.over and BotLadder.completed() == BotLadder.Round.HOLD and battle.hud._ladder_status.text == "Ladder complete",
		"the final round clears the ladder when your team wins")
	var back := InputEventJoypadButton.new()
	back.button_index = JOY_BUTTON_B
	back.pressed = true
	Input.parse_input_event(back)
	await scene_changed
	var released := back.duplicate() as InputEventJoypadButton
	released.pressed = false
	Input.parse_input_event(released)

	menu = current_scene as MainMenu
	checks.check(menu.ladder.visible, "gamepad Back returns to the ladder from the final result")
	menu.ladder.buttons[0].pressed.emit()
	await scene_changed
	practice = current_scene as SkiPractice
	checks.check(practice != null and practice.stage == SkiPractice.Stage.SKI and BotLadder.completed() == BotLadder.Round.HOLD,
		"an earlier round remains replayable without losing progress")
	practice._pause()
	practice.pause_menu.quit_pressed.emit()
	await scene_changed
	menu = current_scene as MainMenu
	checks.check(menu.ladder.visible and not paused and menu.ladder.buttons[2].words == "REPLAY",
		"quitting a paused run returns to the ladder")
	menu.ladder.close()
	menu.show_setup()
	checks.check(menu.setup_screen.setup.map == saved.map and menu.setup_screen.setup.team == saved.team and MatchSetup.current == saved,
		"the ladder keeps the saved and in-memory free-play setup")
	Settings.save_file()
	checks.check(BotLadder.completed() == BotLadder.Round.HOLD, "saving settings keeps completed ladder progress")
	_finish()


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	checks.finish(self)
