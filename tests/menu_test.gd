extends SceneTree

## The menus: settings save, load, reset and apply, a settings row changes
## and saves its setting, match setup choices are remembered and reach the
## match (team, bots, skill, time and captures, map), the main menu opens its
## screens, pausing stops the sim ticking and resuming starts it, settings
## changed from the pause menu reach the match, and auto ski skis when fast.
## The home screen's footnote follows the chosen match. Saved loadouts round
## trip through the settings file. Gyro aim turns only when on, and aim
## assist slows look near an enemy, pulls toward its lead and leaves the
## mouse alone.
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
	Settings.touch_scheme = 1
	Settings.gyro = 1.5
	Settings.invert_gyro = true
	Settings.aim_assist = 2
	var sniper := Loadout.make(SoldierBody.Armour.LIGHT, [Weapon.SNIPER, Weapon.GRENADE_LAUNCHER], Pack.JAMMER)
	Settings.save_loadout(2, sniper)
	Settings.save_file()
	Settings.reset()
	checks.check(Settings.look_mouse == 1.0 and not Settings.invert_look and Settings.outlines and Settings.gyro == 0.0 and Settings.aim_assist == 1, "reset puts the settings back, gyro off and aim assist low")
	Settings.load_file()
	var loaded := Settings.look_mouse == 1.5 and Settings.invert_look and Settings.render_scale == 0.67 and Settings.view_distance == 900.0 and not Settings.outlines and Settings.auto_ski and Settings.commander_mode and Settings.touch_size == 1.3 and Settings.touch_scheme == 1
	loaded = loaded and Settings.gyro == 1.5 and Settings.invert_gyro and Settings.aim_assist == 2
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
	row = _row(screen, "Aim assist")
	row.get_meta("step").call(1)
	checks.check(Settings.aim_assist == 2, "the Aim assist row steps up to High")
	_pad_layout(screen)
	screen._reset()
	checks.check(not Settings.invert_look and Settings.view_distance == 1200.0 and root.scaling_3d_scale == 1.0, "Defaults puts everything back and applies it")
	checks.check(Settings.pad_layout == Settings.PadLayout.XBOX and _face_bindings(JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y),
		"Defaults restores the Xbox face buttons")
	screen.free()


func _pad_layout(screen: SettingsScreen) -> void:
	var file := ConfigFile.new()
	file.load(TEST_FILE)
	file.erase_section_key("controls", "pad_layout")
	file.save(TEST_FILE)
	Settings.load_file()
	checks.check(Settings.pad_layout == Settings.PadLayout.XBOX and _face_bindings(JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y),
		"settings saved before gamepad layouts still use the Xbox face buttons")
	_row(screen, "Gamepad layout").get_meta("step").call(1)
	file.load(TEST_FILE)
	checks.check(file.get_value("controls", "pad_layout") == Settings.PadLayout.NINTENDO and _face_bindings(JOY_BUTTON_B, JOY_BUTTON_A, JOY_BUTTON_Y, JOY_BUTTON_X),
		"the Gamepad layout row saves and applies Nintendo face buttons to menus and play")
	var south := InputEventJoypadButton.new()
	south.button_index = JOY_BUTTON_A
	south.pressed = true
	var east := south.duplicate() as InputEventJoypadButton
	east.button_index = JOY_BUTTON_B
	checks.check(east.is_action_pressed("ui_accept") and not east.is_action_pressed("ui_cancel")
		and south.is_action_pressed("ui_cancel") and not south.is_action_pressed("ui_accept"),
		"Nintendo A accepts on the right and B cancels at the bottom")
	var bumper := south.duplicate() as InputEventJoypadButton
	bumper.button_index = JOY_BUTTON_LEFT_SHOULDER
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_LEFT
	trigger.axis_value = 1.0
	checks.check(bumper.is_action_pressed("ski") and not bumper.is_action_pressed("jet")
		and bumper.is_action_pressed("jump") and trigger.is_action_pressed("jet")
		and east.is_action_pressed("jump") and east.is_action_pressed("ski")
		and not south.is_action_pressed("ski"),
		"left bumper and Nintendo A both jump and ski, and left trigger jets")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	var reset_key := InputEventKey.new()
	reset_key.physical_keycode = KEY_R
	reset_key.pressed = true
	var shoulder := south.duplicate() as InputEventJoypadButton
	shoulder.button_index = JOY_BUTTON_RIGHT_SHOULDER
	checks.check(enter.is_action_pressed("ui_accept") and reset_key.is_action_pressed("practice_reset") and shoulder.is_action_pressed("next_weapon"),
		"changing gamepad layout leaves keyboard and shoulder bindings in place")
	Settings.reset()
	Settings.load_file()
	Settings.apply()
	checks.check(Settings.pad_layout == Settings.PadLayout.NINTENDO and _face_bindings(JOY_BUTTON_B, JOY_BUTTON_A, JOY_BUTTON_Y, JOY_BUTTON_X),
		"loading reapplies the saved layout without duplicating bindings")


func _face_bindings(a: JoyButton, b: JoyButton, x: JoyButton, y: JoyButton) -> bool:
	return (
		_only_face_button(a, [&"ui_accept", &"jump", &"ski"])
		and _only_face_button(b, [&"ui_cancel", &"board"])
		and _only_face_button(x, [&"use"])
		and _only_face_button(y, [&"next_weapon", &"practice_reset"])
	)


func _only_face_button(button: JoyButton, actions: Array[StringName]) -> bool:
	for action in actions:
		var found: Array[JoyButton] = []
		for event in InputMap.action_get_events(action):
			var pad := event as InputEventJoypadButton
			if pad != null and pad.button_index in Settings.NINTENDO_BUTTONS:
				found.append(pad.button_index)
		if found != [button]:
			return false
	return true


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
	var mode := _row(menu.setup_screen, "Mode")
	var captures := _row(menu.setup_screen, "Captures to win")
	mode.get_meta("step").call(1)
	checks.check(mode.visible and setup.hold and not captures.visible, "Test map can select Capture and Hold")
	var hold_setup := setup.duplicate()
	hold_setup.save()
	checks.check(MatchSetup.load_saved().hold, "the selected mode reloads on Test map")
	mode.get_meta("step").call(-1)
	checks.check(not setup.hold and captures.visible, "switching back to Capture the Flag shows the capture limit")
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
	var play := menu.home.buttons[0]
	var ladder := menu.home.buttons[1]
	var down := InputEventJoypadButton.new()
	down.button_index = JOY_BUTTON_DPAD_DOWN
	down.pressed = true
	root.push_input(down)
	down.pressed = false
	root.push_input(down)
	checks.check(ladder.has_focus() and not play.has_focus() and not play.filled and not play.highlight_hover,
		"moving down with the controller moves the highlight off Play")
	var accept := InputEventJoypadButton.new()
	accept.button_index = JOY_BUTTON_A
	accept.pressed = true
	root.push_input(accept)
	accept.pressed = false
	root.push_input(accept)
	checks.check(menu.ladder.visible and not menu.home.visible, "controller confirm opens Bot ladder")
	var back := InputEventJoypadButton.new()
	back.button_index = JOY_BUTTON_B
	back.pressed = true
	root.push_input(back)
	back.pressed = false
	root.push_input(back)
	checks.check(menu.home.visible and ladder.has_focus(), "controller Back restores focus to Bot ladder")
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
	checks.check(main.game.fleet.hulls.size() == 10, "the Test map spawns all five vehicles for each team")
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
	var pause_at := touch.pause_rect().get_center()
	await _touch_at(touch, 2, pause_at, true)
	var waited_for_release := not paused
	await _touch_at(touch, 2, pause_at, false)
	await process_frame
	checks.check(waited_for_release and paused and main.pause_menu.visible,
		"a touch opens the pause menu after release")
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
	var pause_menu: PauseMenu = main.pause_menu
	var resume_button := root.gui_get_focus_owner()
	var settings_button := resume_button.find_next_valid_focus() as MenuKit.CoverButton
	settings_button.grab_focus()
	settings_button.pressed.emit()
	pause_menu.settings.close()
	checks.check(pause_menu.home.visible and settings_button.has_focus() and settings_button.words == "SETTINGS",
		"closing pause settings restores focus to Settings")
	Settings.view_distance = 600.0
	Settings.touch_size = 0.8
	main.pause_menu.settings.changed.emit()
	checks.check(main.camera.far == 600.0 and main.touch.scale_factor == 0.8, "settings changed while paused reach the match")
	main.pause_menu.resume()
	await ticks(10)
	checks.check(not paused and game.tick > tick, "resume starts the sim again")

	await _check_stick_jet(main)
	_check_gyro(main)
	_check_aim_assist(main)
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


## A touch down or up on the touch controls at a point in their own space.
func _touch_at(touch: TouchControls, index: int, at: Vector2, pressed: bool) -> void:
	var to_window := root.get_final_transform() * touch.get_global_transform_with_canvas()
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = to_window * at
	Input.parse_input_event(event)
	await process_frame


func _check_stick_jet(main: Node) -> void:
	var touch: TouchControls = main.touch
	var home := touch.stick_home()
	var jet := PlayerCommand.JET
	Settings.touch_scheme = 0
	await _touch_at(touch, 0, home, true)
	await _touch_at(touch, 0, home, false)
	await _touch_at(touch, 0, home, true)
	checks.check(touch.buttons & jet == 0, "double-tap and hold does nothing with the jet scheme off")
	await _touch_at(touch, 0, home, false)
	Settings.touch_scheme = 1
	touch.release_all()
	await create_timer(0.4).timeout
	await _touch_at(touch, 0, home, true)
	checks.check(touch.buttons & jet == 0, "a single stick touch doesn't jet")
	await _touch_at(touch, 0, home, false)
	await _touch_at(touch, 0, home, true)
	checks.check(touch.buttons & jet != 0, "double-tap and hold on the stick jets")
	await _touch_at(touch, 0, home, false)
	checks.check(touch.buttons & jet == 0, "and stops when the touch lifts")
	await create_timer(0.4).timeout
	await _touch_at(touch, 0, home, true)
	checks.check(touch.buttons & jet == 0, "a second touch after 0.3 s is a new single touch")
	var to_window := root.get_final_transform() * touch.get_global_transform_with_canvas()
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = to_window * (home + Vector2(0.0, -touch.stick_radius() * 1.3))
	Input.parse_input_event(drag)
	await process_frame
	checks.check(touch.buttons & jet != 0 and touch.stick.y > 0.9, "pushing past the ring jets and still steers")
	Settings.touch_scheme = 0
	Input.parse_input_event(drag.duplicate())
	touch._update_buttons()
	checks.check(touch.buttons & jet == 0, "past the ring does nothing with the scheme off")
	await _touch_at(touch, 0, home, false)
	touch.release_all()
	Settings.touch_scheme = 0


## Gyro aim adds the fake turn rate to yaw while on, and nothing while off.
func _check_gyro(main: Node) -> void:
	var input: LocalInput = main.input
	input.set_device(LocalInput.Device.TOUCH)
	Settings.aim_assist = 0
	input.read_gyro = func() -> Vector3: return Vector3(0.0, 1.0, 0.0)
	input.read_gravity = func() -> Vector3: return Vector3(0.0, -9.8, 0.0)
	input.source.yaw = 0.0
	Settings.gyro = 0.0
	input.make_command(1.0 / 60.0)
	checks.check(input.source.yaw == 0.0, "gyro off doesn't turn")
	Settings.gyro = 1.0
	input.make_command(1.0 / 60.0)
	var want := (1.0 - LocalInput.GYRO_DEAD_ZONE) / 60.0
	checks.check(is_equal_approx(input.source.yaw, want), "gyro on turns left at the phone's rate (%.4f, want %.4f)" % [input.source.yaw, want])
	input.read_gravity = func() -> Vector3: return Vector3(0.0, 9.8, 0.0)
	input.make_command(1.0 / 60.0)
	checks.check(is_zero_approx(input.source.yaw), "the other landscape way up turns the other way (%.4f)" % input.source.yaw)
	input.read_gyro = func() -> Vector3: return Vector3(0.0, 0.03, 0.0)
	input.make_command(1.0 / 60.0)
	checks.check(is_zero_approx(input.source.yaw), "drift under the dead zone doesn't turn")
	input.read_gyro = Input.get_gyroscope
	input.read_gravity = Input.get_gravity
	Settings.gyro = 0.0
	Settings.aim_assist = 1


## Aim assist with an enemy hung in the air in front of you.
func _check_aim_assist(main: Node) -> void:
	var input: LocalInput = main.input
	var player: Soldier = main.player
	var enemy: Soldier = main.enemy
	var touch: TouchControls = main.touch
	input.set_device(LocalInput.Device.TOUCH)
	Settings.aim_assist = 1
	var up := player.global_position + Vector3.UP * 40.0
	player.global_position = up
	player.velocity = Vector3.ZERO
	player.weapon = player.weapons.find(Weapon.DISC)
	enemy.global_position = up + Vector3(0.0, 0.0, -25.0)
	enemy.velocity = Vector3.ZERO
	var aim := input.assist.find(player, 0.0, 0.0)
	checks.check(aim != null and aim.target_id == enemy.entity_id, "aim assist finds the enemy in front")
	if aim == null:
		return
	# A drag right, on the aim point and with the enemy behind you.
	var turned := func(yaw: float, pitch: float) -> float:
		input.source.yaw = yaw
		input.source.pitch = pitch
		touch._look = Vector2(10.0, 0.0)
		input.make_command(1.0 / 60.0)
		return absf(wrapf(input.source.yaw - yaw, -PI, PI))
	var full := 10.0 * input.touch_sensitivity * Settings.look_touch
	var near: float = turned.call(aim.yaw, aim.pitch)
	var away: float = turned.call(PI, 0.0)
	checks.check(near < full * 0.7 and near > full * 0.5, "aim assist slows look on an enemy (%.4f of %.4f)" % [near, full])
	checks.check(is_equal_approx(away, full), "and not looking away from one (%.4f)" % away)

	# The enemy runs right: the pull turns you right toward its lead while
	# you move, and not while you're idle.
	enemy.velocity = Vector3(10.0, 0.0, 0.0)
	var at_body := enemy.global_position + Vector3.UP * enemy.tuning.height * 0.5 - player.eye_transform().origin
	var body_yaw := atan2(-at_body.x, -at_body.z)
	input.source.yaw = body_yaw
	input.source.pitch = 0.0
	input.make_command(1.0 / 60.0)
	checks.check(input.source.yaw == body_yaw, "no pull while idle")
	touch.stick = Vector2(0.0, 1.0)
	input.make_command(1.0 / 60.0)
	var pulled := wrapf(input.source.yaw - body_yaw, -PI, PI)
	var step := AimAssist.PULL[1] / 60.0
	checks.check(pulled < 0.0 and absf(pulled) <= step * 1.01, "moving pulls toward the lead ahead of a running enemy (%.5f, step %.5f)" % [pulled, step])
	touch.stick = Vector2.ZERO

	# A mouse gets no slowdown and no pull.
	input.set_device(LocalInput.Device.KEYBOARD)
	input.source.yaw = aim.yaw
	input.source.pitch = aim.pitch
	enemy.velocity = Vector3.ZERO
	input._mouse_look = Vector2(-10.0, 0.0)
	input.make_command(1.0 / 60.0)
	var mouse_full := 10.0 * input.mouse_sensitivity * Settings.look_mouse
	checks.check(is_equal_approx(wrapf(input.source.yaw - aim.yaw, -PI, PI), mouse_full), "aim assist leaves the mouse alone")
	Settings.aim_assist = 1
