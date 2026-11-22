extends SceneTree

## Sound: every effect and every bot line in both team voices is made at
## load, the loops loop, the two teams sound different, it's quick to make,
## the world sound voices are capped and a sound that matters less is dropped
## when they're full, and BotVoice plays a line.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/sound_test.gd

var checks := TestWorld.Checks.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	SoundBank.build()
	print("  sounds made in %.0f ms" % SoundBank.build_ms)
	var made := 0
	var seconds := 0.0
	for sound_name in SoundBank.NAMES:
		var stream := SoundBank.get_stream(sound_name)
		if stream != null and stream.data.size() > 100:
			made += 1
			seconds += stream.get_length()
	checks.check(made == SoundBank.NAMES.size(), "every effect is made (%d of %d, %.1f s)" % [made, SoundBank.NAMES.size(), seconds])
	checks.check(SoundBank.get_stream("jet").loop_mode == AudioStreamWAV.LOOP_FORWARD and SoundBank.get_stream("ski").loop_mode == AudioStreamWAV.LOOP_FORWARD, "the jet and ski sounds loop")
	var engines := {}
	for engine in SoundBank.ENGINE_NAMES:
		var stream := SoundBank.get_stream(engine)
		if stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD:
			engines[hash(stream.data)] = true
	checks.check(engines.size() == Vehicle.NAMES.size(), "each vehicle has its own looping engine")
	for material in ["rock", "metal", "salt"]:
		var ski := SoundBank.get_stream("ski_" + material)
		var step := SoundBank.get_stream("step_" + material)
		var land := SoundBank.get_stream("land_" + material)
		checks.check(ski.loop_mode == AudioStreamWAV.LOOP_FORWARD and step.data != land.data, "%s has a ski loop and distinct contact sounds" % material)
	var voices := 0
	var differ := true
	for line in BotLines.TEXT.size():
		var a := SoundBank.voice(line, 0)
		var b := SoundBank.voice(line, 1)
		if a != null and b != null and a.get_length() > 0.15 and a.get_length() < 1.5:
			voices += 1
		if a != null and b != null and a.data == b.data:
			differ = false
	checks.check(voices == BotLines.TEXT.size(), "every bot line has a voice for each team, 0.15 to 1.5 s long")
	checks.check(differ, "the two teams' voices differ")
	checks.check(SoundBank.build_ms < 2000.0, "everything is made in under 2 s here (%.0f ms)" % SoundBank.build_ms)

	var audio := GameAudio.new()
	root.add_child(audio)
	var played := 0
	for k in 40:
		if audio.play_at("disc_blast", Vector3(k, 0.0, 0.0), 0.0, 3):
			played += 1
	checks.check(audio.voices_in_use() == GameAudio.VOICES, "40 blasts at once use only %d voices (%d busy)" % [GameAudio.VOICES, audio.voices_in_use()])
	var busy := 0
	for player in audio.find_children("*", "AudioStreamPlayer3D", true, false):
		if (player as AudioStreamPlayer3D).playing:
			busy += 1
	checks.check(busy <= GameAudio.VOICES + GameAudio.JET_VOICES, "no more 3D players play than the cap (%d)" % busy)
	checks.check(not audio.play_at("chaingun", Vector3.ZERO, 0.0, 0) and audio.dropped == 1, "a chaingun shot is dropped while blasts fill every voice")
	checks.check(audio.play_at("disc_blast", Vector3.ZERO, 0.0, 3), "another blast takes the oldest voice")

	BotVoice.play(BotLines.Line.FLAG_TAKEN, 3, 1)
	var voice := Sound.voice_player()
	checks.check(voice != null and voice.stream == SoundBank.voice(BotLines.Line.FLAG_TAKEN, 1) and voice.bus == Sound.VOICES_BUS, "BotVoice plays the line in the team's voice on the Voices bus")
	voice.stop()
	voice.stream = null
	audio.queue_free()
	await _check_music()
	checks.finish(self)


func _check_music() -> void:
	var tracks := 0
	for k in MusicRotation.TRACKS.size():
		var stream := load(MusicRotation.track_path(k)) as AudioStreamOggVorbis
		if stream != null and not stream.loop and stream.get_length() > 60.0:
			tracks += 1
	checks.check(tracks == 10, "ten complete songs load with track looping off")
	var rotation := MusicRotation.new()
	var previous := -1
	var cycles_are_unique := true
	for cycle in 3:
		var songs := {}
		for k in MusicRotation.TRACKS.size():
			var track := rotation.next_index()
			if track == previous:
				cycles_are_unique = false
			songs[track] = true
			previous = track
		cycles_are_unique = cycles_are_unique and songs.size() == MusicRotation.TRACKS.size()
	checks.check(cycles_are_unique, "three cycles play every song once and avoid immediate repeats")
	root.add_child(rotation)
	rotation.set_audible(true)
	var first := rotation.stream
	rotation.stop()
	rotation.finished.emit()
	checks.check(first != null and rotation.stream != null and first != rotation.stream, "when a track finishes, the rotation loads the next song")
	rotation.set_audible(false)
	checks.check(rotation.stream_paused, "muting pauses the current song")
	root.remove_child(rotation)
	checks.check(rotation.stream == null and not rotation.has_stream_playback(),
		"leaving the tree releases the paused music playback")
	rotation.free()
	# The audio server drops stopped playbacks after its next mix.
	OS.delay_msec(70)
	await process_frame
	await process_frame
	var original := Settings.path
	Settings.path = "user://sound-test-settings.cfg"
	Settings.set_value("music_volume", 0.0)
	Settings.save_file()
	Settings.set_value("music_volume", 1.0)
	Settings.load_file()
	var music := AudioServer.get_bus_index(Sound.MUSIC_BUS)
	var effects := AudioServer.get_bus_index(Sound.EFFECTS_BUS)
	checks.check(Settings.music_volume == 0.0 and AudioServer.is_bus_mute(music) and not AudioServer.is_bus_mute(effects), "music volume persists and mutes just the Music bus")
	Settings.path = original
	DirAccess.remove_absolute("user://sound-test-settings.cfg")
