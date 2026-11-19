extends SceneTree

## The menus: settings save, load, reset and apply, a settings row changes
## and saves its setting, match setup choices are remembered and reach the
## match (team, bots, skill, time and captures, map), the main menu opens its
## screens, pausing stops the sim ticking and resuming starts it, settings
## changed from the pause menu reach the match, and auto ski skis when fast.
## The home screen's footnote follows the chosen match. Saved loadouts round
## trip through the settings file.
## Uses its own settings file, not yours.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/menu_test.gd

const TEST_FILE := "user://test-settings.cfg"

var checks := TestWorld.Checks.new()


func _initialize() -> void:
	_run.call_deferred()


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	Settings.path = TEST_FILE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_FILE))
	_settings()
	_settings_row()
	await _menu()
	await _match()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_FILE))
	checks.finish(self)


func _settings() -> void:
	Settings.reset()
	Settings.look_mouse = 1.5
	Settings.invert_look = true
	Settings.render_scale = 0.67
	Settings.view_distance = 900.0
	Settings.outlines = false
	Settings.voice_volume = 0.3
	Settings.auto_ski = true
	Settings.commander_mode = true
	Settings.touch_size = 1.3
	var sniper := Loadout.make(SoldierBody.Armour.LIGHT, [Weapon.SNIPER, Weapon.GRENADE_LAUNCHER], Pack.JAMMER)
	Settings.save_loadout(2, sniper)
	Settings.save_file()
	Settings.reset()
	checks.check(Settings.look_mouse == 1.0 and not Settings.invert_look and Settings.outlines, "reset puts the settings back")
	Settings.load_file()
	var loaded := Settings.look_mouse == 1.5 and Settings.invert_look and Settings.render_scale == 0.67 and Settings.view_distance == 900.0 and not Settings.outlines and Settings.auto_ski and Settings.commander_mode and Settings.touch_size == 1.3
	checks.check(loaded and is_equal_approx(Settings.voice_volume, 0.3), "settings save and load")
	checks.check(Settings.loadout_slot == 2 and Settings.current_loadout().equals(sniper) and Settings.loadout(0).equals(Loadout.from_dict(Settings.default_loadouts()[0])), "saved loadouts and the last one used save and load")
	var voices := AudioServer.get_bus_index(Sound.VOICES_BUS)
	checks.check(voices != -1 and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(voices)), 0.3), "loading applies the voice volume to its bus")
	checks.check(is_equal_approx(root.scaling_3d_scale, 0.67), "loading applies the render scale")
	checks.check(not Cel.outlines_on(), "loading applies outlines off")
	Settings.reset()
	Settings.apply()
	Settings.save_file()
	checks.check(Cel.outlines_on() and root.scaling_3d_scale == 1.0, "defaults apply outlines and full scale")


## Stepping a row on the settings screen changes, applies and saves it.
func _settings_row() -> void:
	var screen := SettingsScreen.new()
	root.add_child(screen)
	var changed := [0]
	screen.changed.connect(func() -> void: changed[0] += 1)
	var row := _row(screen, "Invert look")
	row.get_meta("step").call(1)
	var file := ConfigFile.new()
	file.load(TEST_FILE)
	checks.check(Settings.invert_look and file.get_value("controls", "invert_look", false) and changed[0] == 1, "the Invert look row turns it on, saves it and says so")
	row = _row(screen, "View distance")
	row.get_meta("step").call(-1)
	checks.check(Settings.view_distance == 900.0, "the View distance row steps down to 900 m (%.0f)" % Settings.view_distance)
	row = _row(screen, "Render scale")
	row.get_meta("step").call(-1)
	checks.check(is_equal_approx(root.scaling_3d_scale, 0.8), "the Render scale row applies at once")
	screen._reset()
	checks.check(not Settings.invert_look and Settings.view_distance == 1200.0 and root.scaling_3d_scale == 1.0, "Defaults puts everything back and applies it")
	screen.free()


func _row(screen: Node, words: String) -> HBoxContainer:
	for row in screen.find_children("*", "HBoxContainer", true, false):
		if row.has_meta("step") and (row.get_child(0) as Label).text == words:
			return row
	return null


func _menu() -> void:
	var menu: MainMenu = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	checks.check(menu.home.visible and not menu.setup_screen.visible, "the main menu starts on its home screen")
	menu.show_setup()
	checks.check(menu.setup_screen.visible and not menu.home.visible, "Play opens match setup")
	var setup := menu.setup_screen.setup
	checks.check(setup.own_bots == MatchSetup.MAX_OWN_BOTS and setup.enemy_bots == MatchSetup.MAX_ENEMY_BOTS, "setup starts 7 and 8 bots with no saved choices")
	_row(menu.setup_screen, "Bots on their team").get_meta("step").call(-1)
	_row(menu.setup_screen, "Your team").get_meta("step").call(1)
	_row(menu.setup_screen, "Map").get_meta("step").call(1)
	var started: Array[MatchSetup] = []
	menu.setup_screen.start_pressed.connect(func(chosen: MatchSetup) -> void: started.append(chosen))
	menu.setup_screen.start()
	checks.check(started.size() == 1 and started[0].enemy_bots == 7 and started[0].team == 1 and started[0].map == "test", "Start sends the choices")
	var again := MatchSetup.load_saved()
	checks.check(again.enemy_bots == 7 and again.team == 1 and again.map == "test", "the choices are remembered")
	menu.setup_screen.close()
	checks.check(menu.home.visible, "Back goes home")
	menu.show_settings()
	checks.check(menu.settings_screen.visible, "Settings opens")
	menu.settings_screen.close()
	menu.show_how_to()
	checks.check(menu.how_to.visible and menu.how_to.scheme == HowToPlay.Scheme.KEYBOARD, "How to play opens on the keyboard scheme on a computer")
	menu.how_to.show_scheme(HowToPlay.Scheme.TOUCH)
	checks.check(menu.how_to._controls.text.contains("JUMP"), "the touch tab shows the touch controls")
	menu.show_home()
	checks.check(menu.home.footnote == "Test map · 8 against 7 · bots", "the cover's footnote shows the chosen map and teams (%s)" % menu.home.footnote)
	checks.check(menu.get_viewport().gui_get_focus_owner() == menu.home.buttons[0], "Play has the focus on the home screen")
	menu.free()


func _match() -> void:
	var chosen := MatchSetup.new()
	chosen.map = "test"
	chosen.team = 1
	chosen.own_bots = 2
	chosen.enemy_bots = 5
	chosen.own_skill = 4
	chosen.enemy_skill = 0
	chosen.time_limit = 300.0
	chosen.capture_limit = 3
	MatchSetup.current = chosen
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await ticks(60)
	var game: Match = main.game
	checks.check(main.map is TestMap, "the chosen map loads")
	checks.check(main.player.team == 1 and game.entities.size() == 8, "you're on the chosen team with 2 and 5 bots (%d soldiers)" % game.entities.size())
	var own := 0
	for brain: BotBrain in main.bots.brains:
		if brain.soldier.team == 1:
			own += 1
	checks.check(own == 2, "2 bots on your team")
	checks.check(main.bots.skill_levels == [0, 4], "skills go to the right teams (%s)" % [main.bots.skill_levels])
	checks.check(game.settings.capture_limit == 3 and game.time_left <= 300.0 and game.time_left > 290.0, "time limit and captures reach the match")

	# Hold the stick and FIRE, pause, let go while paused, and resume.
	var touch: TouchControls = main.touch
	main.input.set_device(LocalInput.Device.TOUCH)
	await process_frame
	var to_window := root.get_final_transform() * touch.get_global_transform_with_canvas()
	var held: Array[InputEventScreenTouch] = []
	for at: Vector2 in [touch.stick_home(), touch.button_centre(0)]:
		var press := InputEventScreenTouch.new()
		press.index = held.size()
		press.pressed = true
		press.position = to_window * at
		Input.parse_input_event(press)
		held.append(press)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = held[0].position + to_window.basis_xform(Vector2(0.0, -300.0))
	Input.parse_input_event(drag)
	await process_frame
	var was_held := touch.buttons & PlayerCommand.FIRE != 0 and touch.stick.length() > 0.5
	main.pause()
	for press in held:
		var lift := press.duplicate() as InputEventScreenTouch
		lift.pressed = false
		Input.parse_input_event(lift)
	await process_frame
	main.pause_menu.resume()
	await process_frame
	checks.check(was_held and touch.buttons == 0 and touch.stick == Vector2.ZERO, "touches held through a pause are let go")
	var marker := main.hud._clear_of_touch(touch.button_centre(TouchControls.ORDERS_BUTTON), 10.0) as Vector2
	checks.check(marker.distance_to(touch.button_centre(TouchControls.ORDERS_BUTTON)) >= touch.button_radius(TouchControls.ORDERS_BUTTON) + 9.9, "edge markers keep clear of the touch buttons")
	main.input.set_device(LocalInput.Device.KEYBOARD)
	await process_frame

	main.pause()
	var audio_clock: int = main.audio._clock
	var tick: int = game.tick
	await process_frame
	await process_frame
	await process_frame
	checks.check(paused and main.pause_menu.visible, "pause opens the pause menu and pauses the tree")
	checks.check(game.tick == tick, "the sim doesn't tick while paused (%d to %d)" % [tick, game.tick])
	checks.check(main.audio._clock == audio_clock, "the sound clock stops while paused")
	Settings.view_distance = 600.0
	Settings.touch_size = 0.8
	main.pause_menu.settings.changed.emit()
	checks.check(main.camera.far == 600.0 and main.touch.scale_factor == 0.8, "settings changed while paused reach the match")
	main.pause_menu.resume()
	await ticks(10)
	checks.check(not paused and game.tick > tick, "resume starts the sim again")

	Settings.auto_ski = true
	var player: Soldier = main.player
	player.velocity = Vector3(20.0, 0.0, 0.0)
	var command: PlayerCommand = main.input.make_command(1.0 / 60.0)
	checks.check(command.buttons & PlayerCommand.SKI != 0, "auto ski skis when you're faster than a run")
	Settings.auto_ski = false
	command = main.input.make_command(1.0 / 60.0)
	checks.check(command.buttons & PlayerCommand.SKI == 0, "and doesn't with it off")
	main.free()
	MatchSetup.current = MatchSetup.new()
