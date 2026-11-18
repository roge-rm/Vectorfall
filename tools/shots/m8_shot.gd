extends Node

## Pictures of the menus and a match, and the sounds as WAV files, and quits.
## It needs a screen:
##   DISPLAY=:0 ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/m8_shot.tscn
## Saves in /srv/downloads/temp/debug/vectorfall: m8-menu.png, m8-setup.png,
## m8-settings.png, m8-howto.png, m8-match.png, m8-pause.png and
## m8-touch.png (the touch controls with the pause button), and every sound
## in sounds/. Uses its own settings file.

const FOLDER := "/srv/downloads/temp/debug/vectorfall"


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	Settings.path = "user://shot-settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	DirAccess.make_dir_recursive_absolute(FOLDER + "/sounds")
	_save_sounds()

	var menu: MainMenu = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	while menu.map == null:
		await get_tree().process_frame
	while menu._cover.visible:
		await get_tree().process_frame
	var started := Time.get_ticks_usec()
	for i in 60:
		await get_tree().process_frame
	print("menu frames: %.1f ms each" % ((Time.get_ticks_usec() - started) / 60000.0))
	await _save("m8-menu.png")
	menu.show_setup()
	await _save("m8-setup.png")
	menu.show_settings()
	await _save("m8-settings.png")
	menu.show_how_to()
	await _save("m8-howto.png")
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
	await _save("m8-match.png")
	main.input.set_device(LocalInput.Device.TOUCH)
	await _save("m8-touch.png")
	main.input.set_device(LocalInput.Device.KEYBOARD)
	main.pause()
	var tick := game.tick
	await _save("m8-pause.png")
	print("ticks while paused: ", game.tick - tick)
	main.pause_menu.resume()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	get_tree().quit()


func _save_sounds() -> void:
	SoundBank.build()
	for sound_name in SoundBank.NAMES:
		SoundBank.get_stream(sound_name).save_to_wav(FOLDER + "/sounds/" + sound_name + ".wav")
	for line in BotLines.TEXT.size():
		for team in 2:
			SoundBank.voice(line, team).save_to_wav(FOLDER + "/sounds/voice-%d-%s.wav" % [team, BotLines.Line.keys()[line].to_lower()])
	print("Sounds made in %.0f ms" % SoundBank.build_ms)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _save(file: String) -> void:
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := FOLDER + "/" + file
	get_viewport().get_texture().get_image().save_png(path)
	print("Saved ", path)
