extends SceneTree

const TEST_SETTINGS := "user://ski-practice-test.cfg"

var checks := TestWorld.Checks.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Settings.path = TEST_SETTINGS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	var setup := MatchSetup.new()
	setup.map = "gannet_reach"
	setup.save()
	var practice := await _open_course()
	if practice == null:
		_finish()
		return
	for i in 12:
		await physics_frame
	checks.check(practice.player.grounded and practice.stage == SkiPractice.Stage.SKI, "the run starts on the downhill gate")
	checks.check(practice.best_ticks == 0 and practice.elapsed_ticks == 0, "waiting at the start does not start the clock")
	var player := practice.player

	Input.action_press("move_forward")
	Input.action_press("jump")
	Input.action_press("ski")
	for i in 500:
		await physics_frame
		if practice.stage != SkiPractice.Stage.SKI or player.position.x > -43.0:
			break
	checks.check(practice.stage == SkiPractice.Stage.CREST and player.velocity.x >= 12.0,
		"skiing in the lane opens the jet leg (x %.1f, speed %.1f)" % [player.position.x, player.velocity.x])

	for i in 90:
		if player.position.x >= -47.0:
			break
		await physics_frame
	Input.action_press("jet")
	for i in 200:
		await physics_frame
		if practice.stage == SkiPractice.Stage.FLAG or player.position.x > 54.0:
			break
	checks.check(practice.stage == SkiPractice.Stage.FLAG and practice.game.flags.has(1),
		"jetting opens the flag leg (x %.1f, height %.1f)" % [player.position.x, player.position.y])
	Input.action_release("jet")
	Input.action_release("jump")
	Input.action_release("ski")
	var furthest := player.position.x
	for i in 600:
		await physics_frame
		furthest = maxf(furthest, player.position.x)
		if practice.stage != SkiPractice.Stage.FLAG:
			break
		if player.position.x > PracticeMap.FLAG_X + 3.0 and not Input.is_action_pressed("move_back"):
			Input.action_release("move_forward")
			Input.action_press("move_back")
		elif player.position.x < PracticeMap.FLAG_X - 4.0 and Input.is_action_pressed("move_back"):
			Input.action_release("move_back")
			Input.action_press("move_forward")
	Input.action_release("move_forward")
	Input.action_release("move_back")
	var flag: Flag = practice.game.flags.get(1)
	checks.check(practice.stage == SkiPractice.Stage.FINISHED and flag != null and flag.carrier_id == player.entity_id,
		"touching the flag ends the real run (x %.1f, height %.1f, furthest %.1f)" % [player.position.x, player.position.y, furthest])
	var best := practice.best_ticks
	checks.check(best > 0 and best == practice.elapsed_ticks and practice._result.visible, "the finish card shows the first personal best")
	var reset := _button(practice, "RUN AGAIN")
	reset.pressed.emit()
	await physics_frame
	checks.check(practice.stage == SkiPractice.Stage.SKI and practice.game.running and practice.elapsed_ticks == 0 and not practice.game.flags.has(1),
		"Run again resets the gates, flag and clock inside the course")
	checks.check(practice.best_ticks == best and is_equal_approx(player.position.x, PracticeMap.START_X), "reset keeps the best time and moves the player to the starting gate")
	practice._quit()
	await scene_changed
	var menu := current_scene as MainMenu
	checks.check(menu != null and MatchSetup.load_saved().map == "gannet_reach", "leaving practice keeps the saved match")
	practice = await _start_from_menu(menu)
	checks.check(practice != null and practice.best_ticks == best and best > 0, "the best time reloads from disk")
	if practice != null:
		Settings.set_value("pad_layout", Settings.PadLayout.NINTENDO)
		Settings.apply()
		practice.stage = SkiPractice.Stage.CREST
		var reset_pad := InputEventJoypadButton.new()
		reset_pad.button_index = JOY_BUTTON_X
		reset_pad.pressed = true
		Input.parse_input_event(reset_pad)
		await process_frame
		reset_pad.pressed = false
		Input.parse_input_event(reset_pad)
		checks.check(practice.stage == SkiPractice.Stage.SKI, "the left face button resets practice in the Nintendo layout")
	_finish()


func _open_course() -> SkiPractice:
	change_scene_to_file("res://scenes/menu.tscn")
	await scene_changed
	return await _start_from_menu(current_scene as MainMenu)


func _start_from_menu(menu: MainMenu) -> SkiPractice:
	if menu == null:
		return null
	menu.show_how_to()
	var launch := _button(menu.how_to, "SKI PRACTICE")
	checks.check(launch != null and launch.is_visible_in_tree(), "How to Play offers a playable ski course")
	if launch == null:
		return null
	launch.pressed.emit()
	await scene_changed
	var practice := current_scene as SkiPractice
	checks.check(practice != null, "the menu button loads the practice scene")
	return practice


func _button(parent: Node, words: String) -> MenuKit.CoverButton:
	for button in parent.find_children("*", "Button", true, false):
		if button is MenuKit.CoverButton and button.words == words:
			return button
	return null


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	checks.finish(self)
