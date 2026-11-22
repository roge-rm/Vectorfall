class_name BotLadder
extends RefCounted

enum Round { NONE = -1, SKI, FLAG, HOLD }

## Set when a round starts and cleared when the menu opens again.
static var active: int = Round.NONE


static func completed() -> int:
	var file := ConfigFile.new()
	if file.load(Settings.path) != OK:
		return Round.NONE
	return _completed_in(file)


static func _completed_in(file: ConfigFile) -> int:
	var saved: Variant = file.get_value("ladder", "completed_round", Round.NONE)
	return clampi(saved, Round.NONE, Round.HOLD) if saved is int else Round.NONE


static func unlocked(round_index: int, cleared: int) -> bool:
	return round_index >= Round.SKI and round_index <= Round.HOLD and round_index <= cleared + 1


## Returns true when this is the first clear of the round.
static func record_clear(round_index: int) -> bool:
	var file := ConfigFile.new()
	var error := file.load(Settings.path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning("Couldn't load the bot ladder save.")
		return false
	var cleared := _completed_in(file)
	if round_index != cleared + 1 or not unlocked(round_index, cleared):
		return false
	file.set_value("ladder", "completed_round", round_index)
	if file.save(Settings.path) != OK:
		push_warning("Couldn't save bot ladder progress.")
		return false
	return true


static func match_setup(round_index: int) -> MatchSetup:
	var setup := MatchSetup.new()
	setup.hold = round_index == Round.HOLD
	setup.map = "gannet_reach" if setup.hold else "saltwake_flats"
	setup.own_bots = 5 if setup.hold else 3
	setup.enemy_bots = setup.own_bots + 1
	setup.enemy_skill = BotDirector.NORMAL + 1 if setup.hold else BotDirector.NORMAL - 1
	setup.time_limit = 240.0 if setup.hold else 300.0
	setup.capture_limit = 1
	return setup
