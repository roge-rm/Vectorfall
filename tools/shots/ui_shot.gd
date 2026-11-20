extends Node

## Pictures of the paperback cover UI at one window size, and quits. It needs
## a screen:
##   DISPLAY=:0 ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --resolution 2400x1080 --path . res://tools/shots/ui_shot.tscn
## Saves in /srv/downloads/temp/debug/vectorfall/ui as <size>-menu.png,
## -setup, -settings, -howto, -match (keyboard), -touch (touch controls, the
## feed and a held SKI), -orders (the order menu open on touch), -pause and
## -end (the match over card), -station (one of your inventory stations from
## beside it), -loadout (the loadout screen it opens) and -dead (the respawn
## count with the LOADOUT button). "-- touch=1.3" sets the touch controls'
## size for the touch and later pictures, and "-- out=/some/folder/ui-" saves
## as /some/folder/ui-<size>-<what>.png instead. "-- release" saves the menu,
## a touch flag chase and the ski course in the milestone 13 release folder.
## Uses its own settings file.

const FOLDER := "/srv/downloads/temp/debug/vectorfall/ui"
const RELEASE_FOLDER := "/srv/downloads/temp/debug/vectorfall/m13/release"

var _tag := "1280x720"
var _out := FOLDER + "/"


func _ready() -> void:
	# The window can be smaller than asked for on a small screen, so the
	# picture is the size the window really is.
	for i in 3:
		await get_tree().process_frame
	var window_size := get_window().size
	_tag = "%dx%d" % [window_size.x, window_size.y]
	Settings.path = "user://shot-settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	var args := OS.get_cmdline_user_args()
	var release := args.has("release")
	if release:
		_out = RELEASE_FOLDER + "/"
	for arg in args:
		if arg.begins_with("out="):
			_out = arg.substr(4)
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())

	var menu: MainMenu = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	await _save("menu")
	if release:
		menu.queue_free()
		await get_tree().process_frame
		await _release_chase()
		await _release_practice()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
		get_tree().quit()
		return
	menu.show_setup()
	await _save("setup")
	menu.show_settings()
	await _save("settings")
	menu.show_how_to()
	await _save("howto")
	menu.queue_free()
	await get_tree().process_frame

	MatchSetup.current = MatchSetup.new()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(4.0)
	var player: Soldier = main.player
	var game: Match = main.game
	# Face the middle of the map from the base.
	main.input.source.yaw = -PI * 0.5 if player.team == 0 else PI * 0.5
	main.input.source.pitch = -0.08
	await _wait(1.0)
	var mates: Array[Soldier] = []
	for brain: BotBrain in main.bots.brains:
		if brain.soldier.team == player.team:
			mates.append(brain.soldier)
	main.hud.add_chat(mates[0], "Going for their flag")
	main.hud.add_chat(mates[1], "Our flag's taken")
	main.hud._on_killed(mates[2].entity_id, main.bots.brains[-1].soldier.entity_id, 0)
	main.hud.add_chat(mates[3], "Defending our flag")
	# Hurt, so the health arc shows, with the shield on and a grenade thrown.
	player.health = player.tuning.health_max * 0.6
	player.pack_on = true
	player.grenades -= 1
	await _wait(0.5)
	await _save("match")
	# "-- touch=1.3" draws the touch controls at that size.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("touch="):
			main.touch.scale_factor = float(arg.substr(6))
			_tag += "-touch%d" % roundi(main.touch.scale_factor * 100.0)
	main.input.set_device(LocalInput.Device.TOUCH)
	player.ski_held = true
	await _save("touch")
	main.menu.open()
	await _save("orders")
	main.menu.close()
	main.input.set_device(LocalInput.Device.KEYBOARD)
	player.pack_on = false
	# Beside one of your stations, looking at it.
	var station: InventoryStation
	for id: int in game.stations:
		if game.stations[id].team == player.team:
			station = game.stations[id]
	var side := signf(station.global_position.z)
	var stand := station.global_position + Vector3(main.map.front(player.team) * 5.0, 0.3, side * 3.5)
	player.global_position = stand
	player.velocity = Vector3.ZERO
	var to := station.global_position - stand
	main.input.source.yaw = atan2(-to.x, -to.z)
	main.input.source.pitch = -0.3
	await _wait(0.5)
	await _save("station")
	player.global_position = station.global_position + Vector3.UP * 0.3
	player.velocity = Vector3.ZERO
	await _wait(0.5)
	await _save("loadout")
	main.loadout_screen.close()
	game.damage(player, 1000.0, main.enemy.entity_id, Weapon.DISC, main.enemy.global_position)
	await _wait(0.5)
	await _save("dead")
	await _wait(Match.RESPAWN_DELAY)
	main.pause()
	await _save("pause")
	main.pause_menu.resume()
	game.match_over.emit(player.team)
	await _save("end")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	get_tree().quit()


func _release_chase() -> void:
	MatchSetup.current = MatchSetup.new()
	MatchSetup.current.map = "white_signal"
	MatchSetup.current.own_bots = 0
	MatchSetup.current.enemy_bots = 1
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var game: Match = main.game
	var player: Soldier = main.player
	var carrier: Soldier = main.enemy
	var map: GameMap = main.map
	var pose := CommandSource.new()
	pose.yaw = -PI * 0.5
	game.sources[carrier.entity_id] = pose
	carrier.position = game.stands[0]
	for i in 3:
		await get_tree().physics_frame

	# Bring the chase into view of the tunnel while keeping the live flag HUD.
	player.position = Vector3(-128, map.ground_height(-128, 0) + 0.25, 0)
	player.velocity = Vector3.ZERO
	main.input.source.yaw = -PI * 0.5
	main.input.source.pitch = 0.025
	main.input.set_device(LocalInput.Device.TOUCH)
	carrier.position = Vector3(-112, map.ground_height(-112, 4) + 3.2, 4)
	carrier.velocity = Vector3(4, 0, 0)
	game.prepare_terrain()
	for i in 8:
		await get_tree().physics_frame
	var impact := Vector3(-109, map.ground_height(-109, -5) + 0.05, -5)
	main.effects.blast(impact, Vector3.UP, Weapon.all[Weapon.DISC].splash_radius)
	await _save("flag-chase", 4)
	main.queue_free()
	await get_tree().process_frame


func _release_practice() -> void:
	var practice: SkiPractice = load("res://scenes/ski_practice.tscn").instantiate()
	add_child(practice)
	practice.input.set_device(LocalInput.Device.TOUCH)
	await _save("ski-practice")


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _save(what: String, frames := 12) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "%s%s-%s.png" % [_out, _tag, what]
	var saved := get_viewport().get_texture().get_image().save_png(path)
	if saved != OK:
		push_error("Could not save " + path)
		get_tree().quit(1)
		return
	print("Saved ", path)
