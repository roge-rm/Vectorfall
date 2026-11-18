class_name BotVoice
extends RefCounted

## Plays the voice for a line a bot says (BotLines.Line): short robot speech
## made by SoundBank, in the team's voice, pitched a little per speaker.


static func play(line: int, speaker_id: int, team := 0) -> void:
	Sound.say(line, team, speaker_id)
