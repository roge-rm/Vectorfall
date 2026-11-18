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
	audio.free()
	checks.finish(self)
