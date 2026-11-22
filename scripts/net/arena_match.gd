class_name ArenaMatch
extends RefCounted


static func make(parent: Node, map: GameMap, minutes: float, captures: int, seed := 1, spawn_count := 8, hold := false, resupply := false) -> Match:
	var game := Match.new(seed)
	game.settings.time_limit = minutes * 60.0
	game.settings.capture_limit = captures
	game.start_clock()
	game.terrain = map.terrain
	game.arena = map
	var sites: Array[Vector2] = []
	if hold:
		sites = map.control_sites()
	if sites.is_empty():
		game.settings.respawn_wave_ticks = MatchSettings.CTF_RESPAWN_WAVE_TICKS
	for team in 2:
		game.spawns[team] = map.ctf_respawn_points(team, spawn_count) if sites.is_empty() else map.spawn_points(team, spawn_count)
		if not sites.is_empty():
			game.stands[team] = map.stand_point(team)
		else:
			game.add_flag(team, map.stand_point(team), map.flag_rest(team))
	# Keep flag, station and pad IDs in the same order on both ends.
	for team in 2:
		for at in map.station_points(team):
			game.add_station(team, at)
		map.add_base_power(game, team)
		map.add_vehicle_pads(game, team)
	for site in sites:
		game.add_hold_point(Vector3(site.x, map.surface_at(site.x, site.y), site.y))
	var supply := map.midfield_supply()
	if resupply and supply.is_finite():
		var control := map.controlled_supply_site() if not sites.is_empty() else -1
		if control >= 0:
			supply = sites[control] + Vector2(0.0, 9.0)
		game.add_station(InventoryStation.NEUTRAL, Vector3(supply.x, map.surface_at(supply.x, supply.y), supply.y), 0, control)
	parent.add_child(game)
	return game
