class_name Settings
extends RefCounted

## Player settings, kept in user://settings.cfg.

const PATH := "user://settings.cfg"

static var outlines := true
static var hatching := true


static func load_file() -> void:
	var file := ConfigFile.new()
	if file.load(PATH) == OK:
		outlines = file.get_value("graphics", "outlines", outlines)
		hatching = file.get_value("graphics", "hatching", hatching)
	Cel.set_outlines(outlines)
	Cel.set_hatching(hatching)


static func save_file() -> void:
	var file := ConfigFile.new()
	file.load(PATH)
	file.set_value("graphics", "outlines", outlines)
	file.set_value("graphics", "hatching", hatching)
	file.save(PATH)


static func set_outlines(on: bool) -> void:
	outlines = on
	Cel.set_outlines(on)
	save_file()


static func set_hatching(on: bool) -> void:
	hatching = on
	Cel.set_hatching(on)
	save_file()
