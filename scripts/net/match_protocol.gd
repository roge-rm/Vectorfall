class_name MatchProtocol
extends RefCounted

const VERSION := 2
const MAX_TEAM_SIZE := 16
const GAME_PORT := 27300
const DISCOVERY_PORT := 27301
const WEB_PORT := 27302
const DISCOVERY_QUERY := "skifrei/2"
const INPUT_MAX := 2048
const SNAPSHOT_MAX := 96 * 1024
const COMMANDS_MAX := 12
const MOVEMENT := PlayerCommand.JUMP | PlayerCommand.SKI | PlayerCommand.JET


static func command(data: Variant) -> PlayerCommand:
	if not data is Dictionary:
		return null
	var move: Variant = data.get("move")
	if not move is Vector2 or not move.is_finite():
		return null
	for key in ["yaw", "pitch"]:
		var angle: Variant = data.get(key)
		if typeof(angle) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(angle)):
			return null
	for key in ["buttons", "board_id", "weapon", "order", "order_arg"]:
		if not data.get(key) is int:
			return null
	var kit: Variant = data.get("loadout")
	if not kit is Dictionary:
		return null
	if not kit.is_empty():
		for key in ["armour", "pack", "grenades", "mines"]:
			if not kit.get(key) is int:
				return null
		if not kit.get("weapons") is Array or kit.weapons.size() > 4:
			return null
		for slot in kit.weapons:
			if not slot is int:
				return null
	var point: Variant = data.get("order_point", Vector2.ZERO)
	if not point is Vector2 or not point.is_finite() or (data.order == Orders.Kind.WAYPOINT and not data.has("order_point")):
		return null
	var result := PlayerCommand.from_dict(data)
	result.move = result.move.limit_length()
	result.yaw = wrapf(result.yaw, -PI, PI)
	result.pitch = clampf(result.pitch, -PI * 0.5 + 0.01, PI * 0.5 - 0.01)
	result.buttons &= 2047
	result.board_id = maxi(0, result.board_id)
	result.weapon = clampi(result.weapon, -1, 3)
	if result.order not in [Orders.Kind.WAYPOINT, Orders.Kind.ACK_CALL]:
		if result.order not in Orders.MENU and result.order not in Orders.TEAM_CALLS:
			result.order = 0
		result.order_arg = 0
	if not result.loadout.is_empty():
		result.loadout = Loadout.from_dict(result.loadout).to_dict()
	return result


static func decode(packet: PackedByteArray, limit: int) -> Dictionary:
	if packet.size() < 8 or packet.size() > limit:
		return {}
	var value: Variant = bytes_to_var(packet)
	if value is Dictionary and value.get("v") == VERSION:
		return value
	return {}


static func encode(message: Dictionary) -> PackedByteArray:
	message["v"] = VERSION
	return var_to_bytes(message)
