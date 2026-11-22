extends SceneTree

const TEST_SETTINGS := "user://training-drill-test.cfg"
const MENU := "res://scenes/menu.tscn"

var checks := TestWorld.Checks.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Settings.path = TEST_SETTINGS
	var menu := await _open_menu()
	menu.show_how_to()
	var drills_button := menu.how_to.drills_button
	drills_button.pressed.emit()
	checks.check(menu.drills.is_visible_in_tree() and root.gui_get_focus_owner() == menu.drills.buttons[0],
		"How to play opens the drills with controller and keyboard focus")
	menu.drills.close()
	checks.check(menu.how_to.visible and root.gui_get_focus_owner() == drills_button,
		"leaving the drill list returns focus to its button")
	drills_button.pressed.emit()
	var drill := await _start(menu, TrainingDrill.Kind.AIR)
	checks.check(drill != null and drill.kind == TrainingDrill.Kind.AIR, "Air shots opens in the practice arena")
	if drill == null:
		checks.finish(self)
		return
	await _air_shot(drill)
	drill._quit()
	await scene_changed
	menu = current_scene as MainMenu
	checks.check(menu.drills.visible and root.gui_get_focus_owner() == menu.drills.buttons[0],
		"leaving an exercise goes back to the selected drill")

	drill = await _start(menu, TrainingDrill.Kind.FLAG)
	await _flag_run(drill)
	drill._quit()
	await scene_changed
	menu = current_scene as MainMenu
	drill = await _start(menu, TrainingDrill.Kind.REPAIR)
	await _repair(drill)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	checks.finish(self)


func _open_menu() -> MainMenu:
	change_scene_to_file(MENU)
	await scene_changed
	return current_scene as MainMenu


func _start(menu: MainMenu, kind: TrainingDrill.Kind) -> TrainingDrill:
	menu.drills.buttons[kind].pressed.emit()
	await scene_changed
	for i in 15:
		await physics_frame
	return current_scene as TrainingDrill


func _air_shot(drill: TrainingDrill) -> void:
	checks.check(not drill.target.grounded and absf(drill.target.velocity.x) > 10.0,
		"the range target is airborne and crossing fast")
	checks.check(drill.touch.button_shown(0) and not drill.touch.button_shown(TouchControls.PACK_BUTTON),
		"the touch range offers the fire control")
	# Work out where the target will be when the disc arrives, then use Fire.
	var eye := drill.player.eye_transform().origin
	var elapsed := drill._seconds(drill._started)
	var speed := Weapon.all[Weapon.DISC].speed
	var flight_time := eye.distance_to(drill.target.centre()) / speed
	var centre_offset := drill.target.centre() - drill.target.global_position
	var lead := Vector3.ZERO
	for i in 4:
		lead = TrainingDrill.AirTarget.course(elapsed + flight_time) + centre_offset - eye
		flight_time = lead.length() / speed
	drill.input.source.yaw = atan2(-lead.x, -lead.z)
	drill.input.source.pitch = atan2(lead.y, Vector2(lead.x, lead.z).length())
	Input.action_press("fire")
	await physics_frame
	await physics_frame
	Input.action_release("fire")
	var fired := drill.player.ammo_for(0) < drill.player.max_ammo(Weapon.DISC)
	for i in 100:
		if drill.finished:
			break
		await physics_frame
	checks.check(fired and drill.passed and drill._result.visible,
		"a led disc physically hits the airborne soldier and clears the drill")
	drill.reset_run()
	checks.check(not drill.finished and drill.game.projectiles.is_empty() and drill.player.ammo_for(0) == drill.player.max_ammo(Weapon.DISC),
		"restarting the range clears shots and restores ammo")


func _flag_run(drill: TrainingDrill) -> void:
	checks.check(not drill.touch.button_shown(0) and drill.touch.button_shown(2), "flag training uses the normal ski control")
	Input.action_press("move_forward")
	Input.action_press("jump")
	Input.action_press("ski")
	for i in 600:
		if drill.finished:
			break
		await physics_frame
	Input.action_release("move_forward")
	Input.action_release("jump")
	Input.action_release("ski")
	checks.check(drill.grab_speed >= TrainingDrill.FLAG_SPEED,
		"holding downhill ski grabs the enemy flag at speed (%.1f m/s)" % drill.grab_speed)
	checks.check(drill.passed and drill.game.scores[0] == 1,
		"a fast escape across the second gate records a real capture (exit x %.1f)" % drill.player.position.x)
	drill.reset_run()
	drill.player.global_position = Vector3(DrillMap.FLAG_X, 0.3, 0.0)
	for i in 15:
		if drill.finished:
			break
		await physics_frame
	checks.check(drill.finished and not drill.passed and drill._result_words.text.contains("Aim for"),
		"a slow grab ends the attempt with a speed target")


func _repair(drill: TrainingDrill) -> void:
	checks.check(drill.generator.destroyed and not drill.game.powered(0), "the repair drill starts with the base offline")
	checks.check(drill.touch.button_shown(TouchControls.PACK_BUTTON), "the repair pack is available on touch")
	var fired := []
	drill.game.turret_fired.connect(fired.append)
	Input.action_press("move_forward")
	for i in 160:
		if drill.player.position.z < 4.0 or drill.finished:
			break
		await physics_frame
	Input.action_release("move_forward")
	Input.action_press("use")
	for i in 850:
		if drill.finished:
			break
		await physics_frame
	Input.action_release("use")
	checks.check(not fired.is_empty(), "a real enemy turret fires on the approach")
	checks.check(drill.passed and drill.game.powered(0) and drill.player.health > 0.0,
		"holding the repair pack from cover restores power (generator %.1f, hp %.1f, z %.1f)" %
		[drill.generator.health, drill.player.health, drill.player.position.z])
	drill.reset_run()
	checks.check(not drill.finished and not drill.game.powered(0) and not drill.turret.destroyed,
		"retry resets the damage and the live defence")
