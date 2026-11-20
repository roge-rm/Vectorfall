class_name BotLines
extends RefCounted

## What bots say to their team: answers to orders and reports. Each line has
## an id for its voice later and text, with %s for a subject such as a lane.

enum Line { ESCORT_YES, DEFENCE_YES, ATTACK_YES, COVER_YES, TAKE_YES, REPAIR_YES, ROLE_YES, AUTO_YES, CANT_CARRYING, FLAG_TAKEN, CARRIER_LANE, FLAG_RETURNED, WE_HAVE_FLAG, BEHIND_YOU, GENERATOR_DOWN, GENERATOR_BACK, RAID }
const TEXT: Array[String] = [
	"I'll escort you",
	"On defence",
	"Going for their base",
	"Covering you",
	"Going for their flag",
	"Heading home to repair",
	"On %s",
	"Back to the plan",
	"Can't, I'm carrying",
	"Our flag's taken",
	"Enemy carrier heading for the %s",
	"Our flag's back",
	"We have their flag",
	"Behind you",
	"Our generator's down",
	"Our generator's back up",
	"Attacking their %s",
]


static func text(line: int, subject := "") -> String:
	var words := TEXT[line]
	return words % subject if words.contains("%s") else words
