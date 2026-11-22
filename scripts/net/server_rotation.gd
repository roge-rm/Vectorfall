class_name ServerRotation
extends RefCounted

var entries: Array[Dictionary] = []
var index := 0


func _init(setting: String, initial: String, hold: bool) -> void:
	if setting.strip_edges().to_lower() == "off":
		return
	if setting.strip_edges().is_empty():
		entries.append({"map": initial, "hold": hold})
		for map_name in GameMap.NAMES:
			if map_name != initial and map_name != "test":
				entries.append({"map": map_name, "hold": hold})
		return
	for item in setting.split(",", false):
		var parts := item.strip_edges().split(":")
		if parts.size() > 2 or parts[0] not in GameMap.NAMES:
			continue
		var mode := parts[1] if parts.size() == 2 else ("hold" if hold else "ctf")
		var entry := {"map": parts[0], "hold": mode == "hold"}
		if mode in ["ctf", "hold"] and entry not in entries:
			entries.append(entry)


func current() -> Dictionary:
	return entries[index] if not entries.is_empty() else {}


func advance() -> Dictionary:
	if not entries.is_empty():
		index = (index + 1) % entries.size()
	return current()


func align(map_name: String, hold: bool) -> void:
	var found := entries.find({"map": map_name, "hold": hold})
	if found != -1:
		index = found
