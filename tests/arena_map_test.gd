extends SceneTree

const MAPS: Array[String] = [
	"saltwake_flats", "nightline_foundry", "copper_steps",
	"caldera_relay", "gannet_reach", "white_signal", "glass_ravine", "greenfall_terraces", "beacon_wreck",
]
var checks := TestWorld.Checks.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Settings.path = "user://arena-map-test.cfg"
	for selected in MAPS:
		MatchSetup.current = MatchSetup.new()
		MatchSetup.current.map = selected
		MatchSetup.current.own_bots = 1
		MatchSetup.current.enemy_bots = 1
		MatchSetup.current.save()
		MatchSetup.current = MatchSetup.load_saved()
		var match_scene: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(match_scene)
		var map := match_scene.map as ArenaMap
		var game: Match = match_scene.game
		for i in 16:
			await physics_frame
		var map_index := GameMap.NAMES.find(selected)
		var correct_map := map != null and map_index >= 0 and map_index < SetupScreen.MAP_TITLES.size() and SetupScreen.MAP_TITLES[map_index] == map.title
		checks.check(MatchSetup.current.map == selected and correct_map, "%s loads from saved match setup" % selected)
		if map == null:
			match_scene.free()
			continue
		checks.check(game.flags.size() == 2 and game.fleet.hulls.size() == 10 and game.generators.size() == 2, "%s has both flags, power and all ten vehicles (%d vehicles)" % [map.title, game.fleet.hulls.size()])
		var grounded: bool = match_scene.bots.brains.size() == 2 and match_scene.player.grounded
		for brain: BotBrain in match_scene.bots.brains:
			grounded = grounded and brain.soldier.grounded
		checks.check(grounded, "%s starts the player and bots on the ground" % map.title)
		_check_routes(map)
		if map is WhiteSignal:
			_check_centre_lane(map)
			_check_snow_routes(map)
		if map is GlassRavine:
			_check_bridge_routes(map)
			_check_service_span(map)
		if map is BeaconWreck:
			_check_wreck_routes(map)
		if map is GreenfallTerraces:
			_check_spillway_routes(map)
		if map is CalderaRelay:
			_check_crater_routes(map)
		if map is SaltwakeFlats:
			_check_salt_routes(map)
		if map is NightlineFoundry:
			_check_foundry_routes(map)
		if map is GannetReach:
			_check_coastal_routes(map)
		if map is CopperSteps:
			_check_ferry_pads(map, game)
		if map is CopperSteps or map is NightlineFoundry:
			_check_reworked_base(map, game)
			var defender: BotBrain = match_scene.bots.brains[0]
			defender.role = BotBrain.Role.DEFENCE
			defender.role_slot = 0
			var flag_post: Vector3 = defender._role_goal()[1]
			defender.role_slot = 1
			var reactor_post: Vector3 = defender._role_goal()[1]
			checks.check(flag_post.distance_to(reactor_post) > 20.0 and reactor_post.distance_to(game.generator(defender.soldier.team).position) <= 5.0,
				"%s gives the second defender a separate reactor post" % map.title)
		var player: Soldier = match_scene.player
		player.global_position = game.stands[1 - player.team]
		player.velocity = Vector3.ZERO
		for i in 3:
			await physics_frame
		var grabbed := game.carried_flag(player.entity_id) != null
		player.global_position = game.stands[player.team]
		player.velocity = Vector3.ZERO
		for i in 3:
			await physics_frame
		checks.check(grabbed and game.scores[player.team] == 1, "%s awards a capture when the flag is brought home" % map.title)
		match_scene.free()
		await process_frame
	checks.finish(self)


func _check_routes(map: ArenaMap) -> void:
	var graph := map.route_graph
	var stands: Array[int] = []
	for team in 2:
		stands.append(graph.interest_points(RouteGraph.FLAG_STAND, team)[0])
	for team in 2:
		var own := stands[team]
		var enemy := stands[1 - team]
		var path_ok := graph.connected(own, enemy)
		for kind in [RouteGraph.SPAWN, RouteGraph.FLAG_APPROACH, RouteGraph.VEHICLE_PAD, RouteGraph.GENERATOR, RouteGraph.DEPLOY]:
			var points := graph.interest_points(kind, team)
			path_ok = path_ok and not points.is_empty()
			for point in points:
				path_ok = path_ok and graph.connected(point, own) and graph.connected(own, point)
		checks.check(path_ok, "%s team %d can reach both flags and every local objective" % [map.title, team])


func _check_centre_lane(map: ArenaMap) -> void:
	var graph := map.route_graph
	var previous := -1
	var clear := true
	for step in range(-4, 5):
		var x := step * ArenaMap.ROUTE_STEP
		var floor_point := Vector3(x, map.ground_height(x, 0.0), 0.0)
		var point := graph.nearest(floor_point)
		clear = clear and point >= 0 and graph.points[point].is_equal_approx(floor_point)
		if step > -4 and clear:
			clear = graph.link_between(previous, point) != null and graph.link_between(point, previous) != null
		previous = point
	checks.check(clear, "%s has an unbroken bot route through its sheltered middle" % map.title)


func _check_reworked_base(map: ArenaMap, game: Match) -> void:
	var graph := map.route_graph
	var clear := true
	var exits := true
	var mirrored := true
	var clear_spawns := true
	for team in 2:
		var gen := game.generator(team)
		var centre := gen.centre()
		for end: float in [-1.0, 1.0]:
			var from := centre + Vector3.RIGHT * end * 18.0
			clear = clear and game.world_ray(from, centre, Match.WORLD_LAYER).is_empty()
		var stand := map.stand_point(team)
		var deck := stand - Vector3.UP * (GameMap.STAND_HEIGHT + 0.5)
		var roof := game.world_ray(deck + Vector3.UP * 14.0, deck + Vector3.UP * 3.0, Match.WORLD_LAYER)
		clear = clear and roof.is_empty() == (map is CopperSteps)
		var start := graph.interest_points(RouteGraph.FLAG_STAND, team)[0]
		exits = exits and graph.interest_points(RouteGraph.FLAG_EXIT, team).size() == 2
		for side: float in [-1.0, 1.0]:
			var inner := 14.0 if map is CopperSteps else 12.0
			var outer := 35.0 if map is CopperSteps else 19.0
			var a := graph.nearest(Vector3(deck.x, deck.y, side * inner))
			var b := graph.nearest(Vector3(deck.x, map.surface_at(deck.x, side * outer), side * outer))
			exits = exits and graph.link_between(start, a) != null and graph.link_between(a, b) != null
			var z := side * 27.0
			var y := map.surface_at(deck.x, z)
			var surface := game.world_ray(Vector3(deck.x, y + 1, z), Vector3(deck.x, y - 1, z), Match.WORLD_LAYER)
			exits = exits and not surface.is_empty() and absf(surface.position.y - y) < 0.08
	var lime_reinforcements := map.ctf_respawn_points(0, 16)
	var blue_reinforcements := map.ctf_respawn_points(1, 16)
	for row in 16:
		var lime := map.spawn_point(0, row).origin
		var blue := map.spawn_point(1, row).origin
		mirrored = mirrored and is_equal_approx(lime.x, -blue.x) and is_equal_approx(lime.z, blue.z)
		var left := lime_reinforcements[row].origin
		var right := blue_reinforcements[row].origin
		mirrored = mirrored and is_equal_approx(left.x, -right.x) and is_equal_approx(left.z, right.z)
		for at: Vector3 in [left, right]:
			clear_spawns = clear_spawns and not map.blocked_at(at.x, at.z) and map.terrain.normal_at(at.x, at.z).y > 0.7
	checks.check(clear_spawns, "%s has 16 open respawn spots on each side" % map.title)
	checks.check(mirrored, "%s mirrors all 16 starts across the map" % map.title)
	checks.check(clear and game.fields.is_empty(), "%s separates the reactor with two firing angles and the intended flag cover" % map.title)
	checks.check(exits, "%s has two connected flag exits with walkable surfaces" % map.title)
	var brain: BotBrain = game.bots.brains[0]
	var runner := brain.soldier
	var old_at := runner.global_position
	var stolen: Flag = game.flags[1 - runner.team]
	runner.global_position = game.stands[stolen.team]
	game._take_flag(stolen, runner)
	brain.goal = BotBrain.Goal.TAKE_FLAG
	var breakout := brain._role_goal()
	checks.check(breakout[0] == BotBrain.Goal.BREAKOUT and graph.interest_points(RouteGraph.FLAG_EXIT, stolen.team).any(
		func(id: int) -> bool: return graph.points[id] == breakout[1]), "%s's runner heads to a mapped exit after grabbing" % map.title)
	brain.goal = BotBrain.Goal.BREAKOUT
	brain.goal_target = breakout[1]
	brain.goal_started = game.tick
	runner.global_position = breakout[1]
	checks.check(brain._role_goal()[0] == BotBrain.Goal.CAPTURE, "%s's runner turns for home after reaching the exit" % map.title)
	stolen.send_home()
	runner.global_position = old_at



func _check_bridge_routes(map: ArenaMap) -> void:
	var graph := map.route_graph
	var correct := true
	for z: float in [-112, -84, 0, 84, 112]:
		var from := graph.nearest(Vector3(56.0, map.ground_height(56.0, z), z))
		var to := graph.nearest(Vector3(112.0, map.ground_height(112.0, z), z))
		var across := graph.link_between(from, to) != null
		correct = correct and across == (absf(z) != 84.0)
	checks.check(correct, "Glass Ravine routes bots around bridge rails while keeping the ledges and floor open")


func _ground_point(map: ArenaMap, at: Vector2) -> int:
	var floor_point := Vector3(at.x, map.ground_height(at.x, at.y), at.y)
	var graph := map.route_graph
	var point := graph.nearest(floor_point)
	return point if point >= 0 and graph.points[point].is_equal_approx(floor_point) else -1


func _ground_link(map: ArenaMap, a: Vector2, b: Vector2) -> bool:
	var from := _ground_point(map, a)
	var to := _ground_point(map, b)
	var graph := map.route_graph
	if from < 0 or to < 0:
		return false
	var there := graph.link_between(from, to)
	var back := graph.link_between(to, from)
	return there != null and back != null and there.kind != RouteGraph.Kind.JET and back.kind != RouteGraph.Kind.JET


func _check_wreck_routes(map: ArenaMap) -> void:
	var graph := map.route_graph
	var west := _ground_point(map, Vector2(-28, 0))
	var east := _ground_point(map, Vector2(28, 0))
	var severed := west >= 0 and east >= 0 and graph.link_between(west, east) == null and graph.link_between(east, west) == null
	var exits := _ground_link(map, Vector2(-84, 0), Vector2(-84, 28))
	exits = exits and _ground_link(map, Vector2(84, 0), Vector2(84, 28))
	var outside := _ground_link(map, Vector2(-28, 56), Vector2(28, 56))
	checks.check(severed and exits and outside, "Beacon Wreck breaks the cargo spine and keeps side exits and a dune bypass")


func _check_spillway_routes(map: ArenaMap) -> void:
	var bends: Array[Vector2] = [Vector2(0, 56), Vector2(28, 56), Vector2(56, 28), Vector2(56, 0), Vector2(84, -28), Vector2(112, -56), Vector2(140, -56)]
	var clear := true
	for step in range(1, bends.size()):
		var a := bends[step - 1]
		var b := bends[step]
		clear = clear and map.ground_height(b.x, b.y) < 13.0
		clear = clear and _ground_link(map, a, b) and _ground_link(map, Vector2(-a.x, a.y), Vector2(-b.x, b.y))
	checks.check(clear, "Greenfall has a continuous low route that switches banks")


func _check_crater_routes(map: ArenaMap) -> void:
	var peak := map.ground_height(0.0, 0.0)
	var split := true
	for z: float in [-84.0, 84.0]:
		split = split and peak - map.ground_height(0.0, z) > 45.0
		split = split and _ground_link(map, Vector2(-28, z), Vector2(28, z))
	checks.check(split, "Caldera's plug divides two usable ski runs across the crater")


func _check_salt_routes(map: ArenaMap) -> void:
	var north := map.ground_height(0, -112)
	var middle := map.ground_height(0, 0)
	var south := map.ground_height(0, 140)
	var lanes := north < middle - 10.0 and south > middle + 6.0
	for z: float in [-112.0, 0.0, 140.0]:
		lanes = lanes and _ground_link(map, Vector2(-28, z), Vector2(28, z))
	checks.check(lanes, "Saltwake has an open pan, a lower drainage cut and a higher berm")


func _check_foundry_routes(map: ArenaMap) -> void:
	var split := map.blocked_at(-28, 0) and map.blocked_at(28, 0)
	var aisle := _ground_link(map, Vector2(0, -28), Vector2(0, 28))
	var roads := _ground_link(map, Vector2(-28, -56), Vector2(28, -56))
	roads = roads and _ground_link(map, Vector2(-28, 56), Vector2(28, 56))
	checks.check(split and aisle and roads, "Foundry has a cross aisle between furnaces and two open service roads")


func _check_coastal_routes(map: ArenaMap) -> void:
	var dry_creek := map.ground_height(56, 140) - map.ground_height(0, 140) > 5.0
	var causeway := _ground_link(map, Vector2(-28, 0), Vector2(28, 0))
	checks.check(dry_creek and causeway, "Gannet has a tidal creek across the flats and a clear causeway")


func _check_snow_routes(map: ArenaMap) -> void:
	var cornice := map.ground_height(0, -112) - map.ground_height(0, 112) > 20.0
	var snowfield := _ground_link(map, Vector2(-28, 112), Vector2(28, 112))
	checks.check(cornice and snowfield, "White Signal has distinct high and low routes outside its tunnel")


func _check_service_span(map: ArenaMap) -> void:
	var graph := map.route_graph
	var north := graph.nearest(Vector3(0, GlassRavine.SPAN_DECK, -GlassRavine.SPAN_BANK))
	var south := graph.nearest(Vector3(0, GlassRavine.SPAN_DECK, GlassRavine.SPAN_BANK))
	var span := graph.nearest(Vector3(0, GlassRavine.SPAN_DECK, 0))
	var crossings := graph.connected(north, span) and graph.connected(span, south)
	var floor_open := _ground_link(map, Vector2(-28, 0), Vector2(28, 0))
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 60, 0), Vector3(0, 50, 0), 1)
	var hit := map.get_world_3d().direct_space_state.intersect_ray(ray)
	checks.check(crossings and floor_open and not hit.is_empty() and is_equal_approx(hit.position.y, GlassRavine.SPAN_DECK), "Glass Ravine has a usable high crossing above the open floor")


func _check_ferry_pads(map: ArenaMap, game: Match) -> void:
	var shelves := 0
	for pad: VehiclePad in game.fleet.pads.values():
		if pad.kind != Vehicle.Kind.TRANSPORT:
			continue
		var at := pad.position
		if is_equal_approx(at.x, -map.front(pad.team) * CopperSteps.PAD_X) and is_equal_approx(at.z, CopperSteps.PAD_Z):
			shelves += 1
	checks.check(shelves == 2, "Copper Steps launches both troop ferries from the forward shelves")
