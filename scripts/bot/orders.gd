class_name Orders
extends RefCounted

## The orders a person can give their team's bots. An order goes into the
## match as part of a PlayerCommand (order and order_arg, for one tick), so it
## reaches the team's commander on a tick and replays with the commands.

enum Kind { NONE, DEFEND_FLAG, ESCORT_ME, ATTACK_GENERATOR, COVER_ME, TAKE_FLAG, REPAIR_BASE, SET_ROLE, WAYPOINT }
const NAMES: Array[String] = ["", "Defend the flag", "Escort me", "Attack the generator", "Cover me", "Take the flag", "Repair the base", "Set a role", "Waypoint"]
## The orders on the menu, in order.
const MENU: Array[int] = [Kind.DEFEND_FLAG, Kind.ESCORT_ME, Kind.ATTACK_GENERATOR, Kind.COVER_ME, Kind.TAKE_FLAG, Kind.REPAIR_BASE]
## Roles a person in commander mode can hand out, and AUTO to give a bot
## back to the commander.
const AUTO := 15
const ROLES: Array[int] = [BotBrain.Role.OFFENCE, BotBrain.Role.DEFENCE, BotBrain.Role.LIGHT_DEFENCE, BotBrain.Role.MIDFIELD, BotBrain.Role.ESCORT, AUTO]


## SET_ROLE's argument: the bot's id, or 0 for the nearest bot, and the role.
static func role_arg(bot_id: int, role: int) -> int:
	return bot_id * 16 + role


static func arg_bot(arg: int) -> int:
	return arg / 16


static func arg_role(arg: int) -> int:
	return arg % 16


static func role_name(role: int) -> String:
	return "auto" if role == AUTO else BotBrain.ROLE_NAMES[role]
