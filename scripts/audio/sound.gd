class_name Sound
extends RefCounted

## Effects, Voices and Music, and the players shared by menus and matches.
## The match owns its own GameAudio for world sounds.

const EFFECTS_BUS := &"Effects"
const VOICES_BUS := &"Voices"
const MUSIC_BUS := &"Music"

static var _ui: AudioStreamPlayer
static var _voice: AudioStreamPlayer
static var _music: MusicRotation


## Adds the buses under Master if they aren't there yet.
static func make_buses() -> void:
	for bus: StringName in [EFFECTS_BUS, VOICES_BUS, MUSIC_BUS]:
		if AudioServer.get_bus_index(bus) == -1:
			var at := AudioServer.bus_count
			AudioServer.add_bus(at)
			AudioServer.set_bus_name(at, bus)
			AudioServer.set_bus_send(at, &"Master")


## Volumes from 0 to 1.
static func set_volumes(effects: float, voices: float, music: float) -> void:
	make_buses()
	for pair: Array in [[EFFECTS_BUS, effects], [VOICES_BUS, voices], [MUSIC_BUS, music]]:
		var index := AudioServer.get_bus_index(pair[0])
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(pair[1], 0.0001)))
		AudioServer.set_bus_mute(index, pair[1] <= 0.001)

	if not is_instance_valid(_music) and music > 0.001 and DisplayServer.get_name() != "headless":
		var root := (Engine.get_main_loop() as SceneTree).root
		_music = MusicRotation.new()
		_music.name = "Music"
		_music.bus = MUSIC_BUS
		_music.volume_db = -6.0
		_music.process_mode = Node.PROCESS_MODE_ALWAYS
		root.add_child.call_deferred(_music)
	if is_instance_valid(_music):
		_music.set_audible(music > 0.001)


static func _player(bus: StringName, polyphony: int) -> AudioStreamPlayer:
	make_buses()
	var player := AudioStreamPlayer.new()
	player.bus = bus
	player.max_polyphony = polyphony
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	return player


## A UI click, or the lower one for going back.
static func click(back := false) -> void:
	if not is_instance_valid(_ui):
		_ui = _player(EFFECTS_BUS, 2)
	_ui.stream = SoundBank.get_stream("back" if back else "click")
	_ui.volume_db = -6.0
	_ui.play()


## A bot's line over the team radio, pitched a little per speaker.
static func say(line: int, team: int, speaker_id: int) -> void:
	if not is_instance_valid(_voice):
		_voice = _player(VOICES_BUS, 1)
		_voice.process_mode = Node.PROCESS_MODE_PAUSABLE
	_voice.stream = SoundBank.voice(line, team)
	_voice.pitch_scale = 0.9 + 0.05 * (speaker_id % 5)
	_voice.volume_db = -8.0
	_voice.play()


## The voice player, for tests.
static func voice_player() -> AudioStreamPlayer:
	return _voice
