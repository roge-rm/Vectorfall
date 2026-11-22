extends SceneTree

## Runs the main scene for five seconds and checks the bots but defence have set off,
## the player is standing on its base, the touch controls show only after a
## touch, and the touch stick and buttons, holding JUMP to ski, FIRE and SWAP too, end
## up in the player's commands, the left FIRE fires with the order menu open,
## GREN, MINE and PACK throw and switch the pack, and the outline setting
## turns outlines on and off. You start in your saved loadout, each base has
## two stations, stepping onto yours opens the loadout screen and a pick there
## is worn at once, and the LOADOUT button while dead sets what you respawn
## in. The base power notices, power marks and generator marker show, and an
## unpowered station offers no loadouts.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/main_scene_test.gd

var checks := TestWorld.Checks.new()


func _initialize() -> void:
	_run.call_deferred()


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	# Defaults, not your settings.
	Settings.path = "user://no-settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await ticks(300)
	var player: Soldier = main.player
	var camera: FirstPersonCamera = main.camera
	var enemy: Soldier = main.enemy
	checks.check((camera.cull_mask & player.blob.layers) == 0 and (camera.cull_mask & enemy.blob.layers) != 0,
		"the first-person camera hides your shadow and shows other soldiers' shadows")
	checks.check(player.grounded, "the player is standing after five seconds")
	var from_flag := Vector2(player.global_position.x - main.map.base_x(0), player.global_position.z).length()
	checks.check(from_flag > 190.0 and from_flag < 215.0, "the player starts 190 to 215 m beside their flag (%.1f m)" % from_flag)
	checks.check(main.game.entities.size() == 1 + main.setup.own_bots + main.setup.enemy_bots, "the match has you and the bots")
	checks.check(main.enemy.team != player.team and not main.enemy.dead, "the enemy bots are on the other team")
	checks.check(player.loadout.equals(Settings.loadout(0)) and player.weapons.size() == 3, "you start in the first saved loadout")
	var per_team := [0, 0]
	for id: int in main.game.stations:
		per_team[main.game.stations[id].team] += 1
	checks.check(per_team == [2, 2], "each base has two stations (%s)" % [per_team])
	var moving := 0
	var leaving := 0
	for brain: BotBrain in main.bots.brains:
		if brain.role == BotBrain.Role.DEFENCE:
			continue
		leaving += 1
		if brain.soldier.global_position.distance_to(brain.soldier.game.spawns[brain.soldier.team][0].origin) > 15.0:
			moving += 1
	checks.check(leaving > 0 and moving == leaving, "every bot but defence has set off from its base (%d of %d)" % [moving, leaving])
	checks.check(not main.overlay.visible, "the bot overlay starts hidden")
	var outlined := Cel.material(Color(0.5, 0.5, 0.5))
	Settings.outlines = false
	Cel.set_outlines(false)
	var off := outlined.next_pass == null and Cel.material(Color(0.4, 0.5, 0.5)).next_pass == null
	Cel.set_outlines(true)
	checks.check(off and outlined.next_pass != null, "the outline setting takes outlines off and puts them back")
	checks.check(not main.touch.visible, "no touch controls on a computer to start with")

	var touch: TouchControls = main.touch
	# Events come in window pixels, which the stretch turns into the controls'.
	var to_window := root.get_final_transform() * touch.get_global_transform_with_canvas()
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = to_window * touch.stick_home()
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

	# Holding JUMP skis, and letting go stops.
	var hold := InputEventScreenTouch.new()
	hold.index = 2
	hold.pressed = true
	hold.position = to_window * touch.button_centre(2)
	Input.parse_input_event(hold)
	await ticks(3)
	checks.check(player.ski_held, "holding JUMP skis")
	hold = hold.duplicate()
	hold.pressed = false
	Input.parse_input_event(hold)
	await ticks(3)
	checks.check(not player.ski_held, "letting go of JUMP stops skiing")

	# Dragging from the left FIRE fires and looks.
	var fire := InputEventScreenTouch.new()
	fire.index = 4
	fire.pressed = true
	fire.position = to_window * touch.button_centre(3)
	Input.parse_input_event(fire)
	var fire_drag := InputEventScreenDrag.new()
	fire_drag.index = 4
	fire_drag.position = fire.position
	fire_drag.relative = to_window.basis_xform(Vector2(40.0, 0.0))
	Input.parse_input_event(fire_drag)
	await ticks(2)
	checks.check(touch.buttons & PlayerCommand.FIRE != 0 and touch.buttons & PlayerCommand.JET != 0, "the left FIRE and JET are held at once")
	checks.check(touch.stick.y > 0.99, "the stick still works with FIRE and JET held")
	var turned := touch.take_look()
	checks.check(turned.x > 0.0 or absf(main.input.source.yaw) > 0.0, "a drag from FIRE looks")
	fire = fire.duplicate()
	fire.pressed = false
	Input.parse_input_event(fire)
	await ticks(2)
	checks.check(touch.buttons & PlayerCommand.FIRE == 0 and touch.buttons & PlayerCommand.JET != 0, "letting go of FIRE leaves JET held")

	# With the order menu open, the left FIRE still fires and picks no order,
	# and the stick still moves.
	main.menu.open()
	var fire_open := InputEventScreenTouch.new()
	fire_open.index = 5
	fire_open.pressed = true
	fire_open.position = to_window * touch.button_centre(3)
	Input.parse_input_event(fire_open)
	await ticks(2)
	var no_order: bool = main.input._order == 0 and not main.bots.commander(0).decisions.any(func(d: Dictionary) -> bool: return d.text.contains("orders"))
	checks.check(touch.buttons & PlayerCommand.FIRE != 0 and no_order and main.menu.visible, "with the order menu open, the left FIRE fires and sends no order")
	checks.check(not main.menu.covers(touch.button_centre(3)) and not main.menu.covers(Vector2(touch.size.x * 0.44, touch.size.y * 0.5)), "the menu keeps clear of the left FIRE and the stick's half")
	fire_open = fire_open.duplicate()
	fire_open.pressed = false
	Input.parse_input_event(fire_open)
	main.menu.close()
	await ticks(2)

	# One thumb slides between JET, JUMP and the right FIRE.
	var lift := jet.duplicate()
	lift.pressed = false
	Input.parse_input_event(lift)
	await ticks(2)
	checks.check(touch.buttons == 0, "everything is let go before the slide checks")
	var slide := InputEventScreenTouch.new()
	slide.index = 6
	slide.pressed = true
	slide.position = to_window * touch.button_centre(1)
	Input.parse_input_event(slide)
	await ticks(2)
	checks.check(touch.buttons == PlayerCommand.JET, "a touch on JET holds JET")
	var moved := InputEventScreenDrag.new()
	moved.index = 6
	moved.position = to_window * touch.button_centre(0)
	Input.parse_input_event(moved)
	await ticks(2)
	checks.check(touch.buttons == PlayerCommand.JET | PlayerCommand.FIRE, "sliding from JET onto FIRE holds both")
	moved = moved.duplicate()
	moved.position = to_window * touch.button_centre(1)
	Input.parse_input_event(moved)
	await ticks(2)
	checks.check(touch.buttons == PlayerCommand.JET, "sliding off FIRE lets go of fire and keeps jet")
	slide = slide.duplicate()
	slide.pressed = false
	Input.parse_input_event(slide)
	await ticks(2)
	checks.check(touch.buttons == 0, "lifting the sliding touch lets go of everything")

	slide = slide.duplicate()
	slide.pressed = true
	slide.position = to_window * touch.button_centre(2)
	Input.parse_input_event(slide)
	await ticks(3)
	var skied := player.ski_held
	moved = moved.duplicate()
	moved.position = to_window * touch.button_centre(1)
	Input.parse_input_event(moved)
	await ticks(3)
	checks.check(touch.buttons == PlayerCommand.JUMP | PlayerCommand.JET and skied and player.ski_held, "sliding from JUMP onto JET skis and jets")
	moved = moved.duplicate()
	moved.position = to_window * touch.button_centre(2)
	Input.parse_input_event(moved)
	await ticks(3)
	checks.check(touch.buttons == PlayerCommand.JUMP and player.ski_held, "sliding back onto JUMP keeps skiing")
	slide = slide.duplicate()
	slide.pressed = false
	Input.parse_input_event(slide)
	await ticks(2)

	# A touch that starts on the right FIRE looks and doesn't slide.
	var aim := InputEventScreenTouch.new()
	aim.index = 7
	aim.pressed = true
	aim.position = to_window * touch.button_centre(0)
	Input.parse_input_event(aim)
	var aim_drag := InputEventScreenDrag.new()
	aim_drag.index = 7
	aim_drag.position = to_window * touch.button_centre(1)
	aim_drag.relative = to_window.basis_xform(Vector2(30.0, 0.0))
	touch.take_look()
	Input.parse_input_event(aim_drag)
	await ticks(2)
	checks.check(touch.buttons == PlayerCommand.FIRE, "a touch that starts on FIRE doesn't slide onto JET")
	checks.check(touch.take_look().x > 0.0 or absf(main.input.source.yaw) > 0.0, "a drag from the right FIRE looks")
	aim = aim.duplicate()
	aim.pressed = false
	Input.parse_input_event(aim)
	await ticks(2)

	# SWAP switches to the next weapon once per tap.
	var swap := InputEventScreenTouch.new()
	swap.index = 5
	swap.pressed = true
	swap.position = to_window * touch.button_centre(4)
	Input.parse_input_event(swap)
	swap = swap.duplicate()
	swap.pressed = false
	Input.parse_input_event(swap)
	await ticks(3)
	checks.check(player.weapon == Weapon.CHAINGUN, "a tap on SWAP switches to the chaingun")

	# GREN and MINE throw once a tap, PACK switches the shield on and off.
	var grenades := player.grenades
	await _tap(touch, to_window, TouchControls.GRENADE_BUTTON)
	checks.check(player.grenades == grenades - 1, "a tap on GREN throws a hand grenade")
	await ticks(40)
	var mines := player.mines
	await _tap(touch, to_window, TouchControls.MINE_BUTTON)
	checks.check(player.mines == mines - 1, "a tap on MINE places a mine")
	await _tap(touch, to_window, TouchControls.PACK_BUTTON)
	var shield_on := player.pack_on
	await _tap(touch, to_window, TouchControls.PACK_BUTTON)
	checks.check(shield_on and not player.pack_on, "taps on PACK switch the shield on and off")

	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	await ticks(2)
	checks.check(not touch.visible and touch.buttons == 0, "a key press hides the touch controls and lets go of their buttons")
	key.pressed = false
	Input.parse_input_event(key)
	await ticks(2)

	# Onto your own station: the loadout screen opens, you stand still, and a
	# pick is worn at once.
	var station: InventoryStation
	for id: int in main.game.stations:
		if main.game.stations[id].team == player.team:
			station = main.game.stations[id]
	player.global_position = station.global_position + Vector3.UP * 0.3
	player.velocity = Vector3.ZERO
	await ticks(10)
	var screen: LoadoutScreen = main.loadout_screen
	checks.check(screen.visible and main.input.held_off, "stepping onto your station opens the loadout screen")
	screen.pick_slot(1)
	await ticks(3)
	checks.check(player.loadout.equals(Settings.loadout(1)) and player.loadout.armour == SoldierBody.Armour.LIGHT, "a loadout picked on the station is worn at once")
	checks.check(Settings.loadout_slot == 1, "and is the last one used")
	screen.close()
	await ticks(2)
	checks.check(not screen.visible and not main.input.held_off, "closing the screen gives you back control")

	# Dead: the LOADOUT button opens it, and the pick is for the respawn.
	player.global_position = station.global_position + Vector3(6.0, 0.3, 0.0)
	await ticks(5)
	main.game.damage(player, 1000.0, main.enemy.entity_id, Weapon.DISC, main.enemy.global_position)
	await process_frame
	await process_frame
	checks.check(main.hud.loadout_button.visible, "the LOADOUT button shows while you're dead")
	main.hud.loadout_button.pressed.emit()
	await process_frame
	checks.check(screen.visible, "it opens the loadout screen")
	screen.pick_slot(2)
	await ticks(3)
	checks.check(player.next_loadout.equals(Settings.loadout(2)) and player.loadout.armour == SoldierBody.Armour.LIGHT, "a pick while dead is for the respawn")
	await ticks(ceili(player.respawn_in * 60.0) + 5)
	checks.check(not player.dead and player.loadout.armour == SoldierBody.Armour.HEAVY, "you respawn in it")
	checks.check(not screen.visible and not main.hud.loadout_button.visible, "the screen and button go once you're back")

	# Power: with your generator down you get the notice, its power mark goes
	# off, your generator gets a marker and your station stops offering
	# loadouts. Repaired, it comes back. Then the same for the enemy's.
	var game: Match = main.game
	var own: BaseAsset = game.generator(player.team)
	var theirs: BaseAsset = game.generator(1 - player.team)
	checks.check(main.hud.power_mark_on(0) and main.hud.power_mark_on(1) and main.hud.generator_marker() == "", "both power marks start on, with no generator marker")
	game.damage_asset(own, 10.0, main.enemy.entity_id, 1 - player.team, Vector3.ZERO)
	await process_frame
	checks.check(main.hud.generator_marker().begins_with("GENERATOR HIT"), "a hit on your generator puts a marker on it (%s)" % main.hud.generator_marker())
	game.damage_asset(own, 1000.0, main.enemy.entity_id, 1 - player.team, Vector3.ZERO)
	await process_frame
	checks.check(main.hud.notice() == "Our generator is down", "your generator down gives a notice (%s)" % main.hud.notice())
	checks.check(not main.hud.power_mark_on(player.team) and main.hud.power_mark_on(1 - player.team), "and turns your power mark off")
	checks.check(main.hud.generator_marker().begins_with("GENERATOR DOWN"), "and marks it down")
	player.global_position = station.global_position + Vector3.UP * 0.3
	player.velocity = Vector3.ZERO
	await ticks(10)
	checks.check(game.station_under(player) == null and not screen.visible and not main.hud.loadout_button.visible, "an unpowered station doesn't open the loadout screen or show LOADOUT")
	var ring := station.get_node("Ring") as MeshInstance3D
	checks.check(not ring.material_override is StandardMaterial3D, "its ring goes out")
	player.global_position = station.global_position + Vector3(6.0, 0.3, 0.0)
	await ticks(3)
	game.repair_asset(own, 1000.0, player.entity_id)
	await process_frame
	checks.check(main.hud.notice() == "Our power is back" and main.hud.power_mark_on(player.team), "repaired, the notice says so and the mark is on")
	game.damage_asset(theirs, 1000.0, player.entity_id, player.team, Vector3.ZERO)
	await process_frame
	checks.check(main.hud.notice() == "Enemy generator destroyed" and not main.hud.power_mark_on(1 - player.team), "the enemy generator down gives its notice")
	game.repair_asset(theirs, 1000.0, main.enemy.entity_id)
	await process_frame
	checks.check(main.hud.notice() == "Enemy power is back", "and its repair too")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	checks.finish(self)


## A quick tap on a touch button, down and up in the same frame.
func _tap(touch: TouchControls, to_window: Transform2D, k: int) -> void:
	var tap := InputEventScreenTouch.new()
	tap.index = 6
	tap.pressed = true
	tap.position = to_window * touch.button_centre(k)
	Input.parse_input_event(tap)
	tap = tap.duplicate()
	tap.pressed = false
	Input.parse_input_event(tap)
	await ticks(3)
