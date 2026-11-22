class_name ServerDirectory
extends RefCounted

const LIMIT := 32
const BODY_LIMIT := 32768


static func url(value: String) -> String:
	value = value.strip_edges().left(256)
	if value.begins_with("https://") or value.begins_with("http://127.0.0.1:") or value.begins_with("http://localhost:"):
		return value
	return ""


static func status(value: Dictionary) -> Dictionary:
	var result := {}
	for field in ["name", "map", "mode"]:
		if not value.get(field) is String:
			return {}
		result[field] = String(value[field]).replace("\n", " ").replace("\r", " ").strip_edges().left(48)
	if result.name.is_empty() or result.map.is_empty() or result.mode not in ["ctf", "hold"]:
		return {}
	for field in ["port", "players", "slots"]:
		if typeof(value.get(field)) not in [TYPE_INT, TYPE_FLOAT]:
			return {}
		result[field] = int(value[field])
	if result.port < 1 or result.port > 65535 or result.slots < 2 or result.slots > 32 \
			or result.players < 0 or result.players > result.slots:
		return {}
	return result


static func entries(bytes: PackedByteArray, web: bool) -> Array[Dictionary]:
	var payload: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	var servers: Array[Dictionary] = []
	if not payload is Dictionary or not payload.get("servers") is Array:
		return servers
	var secure: bool = web and not JavaScriptBridge.eval("location.protocol === 'http:'")
	for value in payload.servers.slice(0, LIMIT):
		if not value is Dictionary or value.get("v") != MatchProtocol.VERSION:
			continue
		var entry := status(value)
		if entry.is_empty():
			continue
		var host := str(value.get("host", "")).strip_edges().left(128)
		var ws := str(value.get("ws", "")).strip_edges().left(256)
		if not (ws.begins_with("wss://") or ws.begins_with("ws://")):
			ws = ""
		if secure and not ws.begins_with("wss://"):
			continue
		if (host.is_empty() or web) and ws.is_empty():
			continue
		entry["host"] = host
		entry["ws"] = ws
		servers.append(entry)
	return servers
