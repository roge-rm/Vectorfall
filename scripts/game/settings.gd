class_name Settings
extends RefCounted

## Player settings, kept in user://settings.cfg.

const PATH := "user://settings.cfg"

static var outlines := true
static var hatching := true
## How far you can see, in metres: the camera's far plane, where the fog is
## nearly solid, and how far chunked ground is drawn.
static var view_distance := 1200.0
## Bot skill level per team, beginner (0) to expert (4), BotDirector.SKILLS.
static var bot_skill: Array[int] = [BotDirector.NORMAL, BotDirector.NORMAL]
## Lets you hand out your bots' roles from the order menu.
static var commander_mode := false


static func load_file() -> void:
	var file := ConfigFile.new()
	if file.load(PATH) == OK:
		outlines = file.get_value("graphics", "outlines", outlines)
		hatching = file.get_value("graphics", "hatching", hatching)
		view_distance = clampf(file.get_value("graphics", "view_distance", view_distance), 300.0, 3000.0)
		for team in 2:
			bot_skill[team] = clampi(file.get_value("bots", "skill%d" % team, bot_skill[team]), 0, BotDirector.SKILLS.size() - 1)
		commander_mode = file.get_value("bots", "commander", commander_mode)
	Cel.set_outlines(outlines)
	Cel.set_hatching(hatching)


static func save_file() -> void:
	var file := ConfigFile.new()
	file.load(PATH)
	file.set_value("graphics", "outlines", outlines)
	file.set_value("graphics", "hatching", hatching)
	file.set_value("graphics", "view_distance", view_distance)
	for team in 2:
		file.set_value("bots", "skill%d" % team, bot_skill[team])
	file.set_value("bots", "commander", commander_mode)
	file.save(PATH)


static func set_outlines(on: bool) -> void:
	outlines = on
	Cel.set_outlines(on)
	save_file()


static func set_hatching(on: bool) -> void:
	hatching = on
	Cel.set_hatching(on)
	save_file()
