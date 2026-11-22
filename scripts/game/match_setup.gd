class_name MatchSetup
extends RefCounted

## The choices for the next match from the setup screen: map, your team, bots
## and their skill on each side, time limit and captures to win. Kept in the
## [match] section of the settings file so the screen starts with the last
## choices.

const TIME_LIMITS: Array[float] = [300.0, 600.0, 900.0, 1200.0, 1800.0]
const CAPTURE_LIMITS: Array[int] = [1, 3, 5, 7, 10]
const MAX_OWN_BOTS := 7
const MAX_ENEMY_BOTS := 8

## The match the main scene starts. The menu sets it; tests and tools that
## load the main scene directly get the defaults.
static var current := MatchSetup.new()

## GameMap.NAMES entry.
var map := GameMap.DEFAULT
## The team you play on, 0 or 1.
var team := 0
var own_bots := MAX_OWN_BOTS
var enemy_bots := MAX_ENEMY_BOTS
## BotDirector.SKILLS levels for your team's bots and theirs.
var own_skill := BotDirector.NORMAL
var enemy_skill := BotDirector.NORMAL
var time_limit := 1200.0
var capture_limit := 5
var hold := false
var resupply := false


## The last choices saved, or the defaults.
static func load_saved() -> MatchSetup:
	var made := MatchSetup.new()
	var file := ConfigFile.new()
	if file.load(Settings.path) != OK:
		return made
	var map_name: String = file.get_value("match", "map", made.map)
	made.map = map_name if GameMap.NAMES.has(map_name) else GameMap.DEFAULT
	made.team = clampi(file.get_value("match", "team", made.team), 0, 1)
	made.own_bots = clampi(file.get_value("match", "own_bots", made.own_bots), 0, MAX_OWN_BOTS)
	made.enemy_bots = clampi(file.get_value("match", "enemy_bots", made.enemy_bots), 0, MAX_ENEMY_BOTS)
	var top := BotDirector.SKILLS.size() - 1
	made.own_skill = clampi(file.get_value("match", "own_skill", made.own_skill), 0, top)
	made.enemy_skill = clampi(file.get_value("match", "enemy_skill", made.enemy_skill), 0, top)
	made.time_limit = clampf(file.get_value("match", "time_limit", made.time_limit), 60.0, 3600.0)
	made.capture_limit = clampi(file.get_value("match", "capture_limit", made.capture_limit), 1, 20)
	made.hold = file.get_value("match", "hold", false) == true
	if made.map in GameMap.RESUPPLY_ARENAS:
		made.resupply = file.get_value("match", "resupply", false) == true
	return made


func save() -> void:
	var file := ConfigFile.new()
	file.load(Settings.path)
	file.set_value("match", "map", map)
	file.set_value("match", "team", team)
	file.set_value("match", "own_bots", own_bots)
	file.set_value("match", "enemy_bots", enemy_bots)
	file.set_value("match", "own_skill", own_skill)
	file.set_value("match", "enemy_skill", enemy_skill)
	file.set_value("match", "time_limit", time_limit)
	file.set_value("match", "capture_limit", capture_limit)
	file.set_value("match", "hold", hold)
	file.set_value("match", "resupply", resupply)
	file.save(Settings.path)


## Skill level per team index, as BotDirector.skill_levels takes it.
func skill_levels() -> Array[int]:
	var levels: Array[int] = [own_skill, enemy_skill]
	if team == 1:
		levels.reverse()
	return levels


func duplicate() -> MatchSetup:
	var made := MatchSetup.new()
	for key: String in ["map", "team", "own_bots", "enemy_bots", "own_skill", "enemy_skill", "time_limit", "capture_limit", "hold", "resupply"]:
		made.set(key, get(key))
	return made
