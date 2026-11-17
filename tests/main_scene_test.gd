extends SceneTree

## Runs the main scene for five seconds and checks the player is standing on
## its base, the touch controls show only after a touch, and the touch stick
## and buttons, the SKI toggle too, end up in the player's commands.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/main_scene_test.gd

var checks := TestWorld.Checks.new()


func _initialize() -> void:
	_run.call_deferred()


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await ticks(300)
	var player: Soldier = main.player
	checks.check(player.grounded, "the player is standing after five seconds")
	checks.check(absf(player.global_position.y - (TestMap.BASE_HEIGHT + 2.0)) < 0.1, "on top of the base platform (y %.2f)" % player.global_position.y)
	checks.check(main.game.entities.size() == 2, "the match has both soldiers")
	checks.check(not main.touch.visible, "no touch controls on a computer to start with")

	var touch: TouchControls = main.touch
	# Events come in window pixels, which the stretch turns into the controls'.
	var to_window := root.get_final_transform() * touch.get_global_transform_with_canvas()
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = to_window * Vector2(touch.size.x * 0.2, touch.size.y * 0.7)
	Input.parse_input_event(press)
	await ticks(2)
	checks.check(touch.visible and main.input.device == LocalInput.Device.TOUCH, "a touch shows the touch controls")
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = press.position + to_window.basis_xform(Vector2(0.0, -500.0))
	drag.relative = to_window.basis_xform(Vector2(0.0, -500.0))
	Input.parse_input_event(drag)
	var jet := InputEventScreenTouch.new()
	jet.index = 1
	jet.pressed = true
	jet.position = to_window * touch.button_centre(1)
	Input.parse_input_event(jet)
	var start := player.global_position
	await ticks(30)
	checks.check(touch.stick.y > 0.99 and touch.buttons == PlayerCommand.JET, "the stick and jet button register")
	checks.check(player.global_position.y > start.y + 0.5, "the jet button lifts the player")
	checks.check((player.global_position - start).x > 0.5, "the stick pushes the player forward, towards the other base")

	# SKI is a toggle: one tap turns it on, the next turns it off.
	for on: bool in [true, false]:
		var tap := InputEventScreenTouch.new()
		tap.index = 2
		tap.pressed = true
		tap.position = to_window * touch.button_centre(3)
		Input.parse_input_event(tap)
		tap = tap.duplicate()
		tap.pressed = false
		Input.parse_input_event(tap)
		await ticks(2)
		checks.check(player.ski_held == on, "a tap on SKI turns skiing %s" % ("on" if on else "off"))

	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	await ticks(2)
	checks.check(not touch.visible and touch.buttons == 0, "a key press hides the touch controls and lets go of their buttons")
	key.pressed = false
	Input.parse_input_event(key)
	checks.finish(self)
