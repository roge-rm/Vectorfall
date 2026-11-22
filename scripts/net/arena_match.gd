class_name ArenaMatch
extends RefCounted


static func make(parent: Node, map: GameMap, minutes: float, captures: int, seed := 1, spawn_count := 8) -> Match:
	var game := Match.new(seed)
	game.settings.time_limit = minutes * 60.0
	game.settings.capture_limit = captures
	game.start_clock()
	game.terrain = map.terrain
	for team in 2:
		game.spawns[team] = map.spawn_points(team, spawn_count)
		game.add_flag(team, map.stand_point(team), map.flag_rest(team))
	# Keep flag, station and pad IDs in the same order on both ends.
	for team in 2:
		for at in map.station_points(team):
			game.add_station(team, at)
		map.add_base_power(game, team)
		map.add_vehicle_pads(game, team)
	parent.add_child(game)
	return game
