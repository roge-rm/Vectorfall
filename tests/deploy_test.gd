extends SceneTree

const START := Vector3(0.0, 0.05, 0.0)

var checks := TestWorld.Checks.new()
var game: Match
var input := TestWorld.Scripted.new()
var player: Soldier
var result := ""


func _initialize() -> void:
	TestWorld.flat_ground(root)
	game = Match.new(21)
	root.add_child(game)
	player = game.add_soldier(0, Transform3D(Basis.IDENTITY, START), input)
	game.deploy_result.connect(func(id: int, text: String) -> void:
		if id == player.entity_id:
			result = text)
	_run.call_deferred()


func ticks(count: int) -> void:
	for i in count:
		await physics_frame


func place(at: Vector3, slot: int) -> void:
	player.revive(Transform3D(Basis.IDENTITY, at))
	var kit := player.loadout.duplicate()
	kit.pack = slot
	player.set_loadout(kit)
	await ticks(8)


func press(button: int) -> void:
	input.command.buttons = button
	await ticks(2)
	input.command.buttons = 0
	await ticks(2)


func _run() -> void:
	var generator := game.add_asset(0, BaseAsset.Kind.GENERATOR, Vector3(20, 0, 0))
	var fixed_pad := game.add_station(0, Vector3(0, 0, -3))
	await place(START, Pack.TURRET)
	await press(PlayerCommand.USE)
	checks.check(player.deploy_ready and game.assets.size() == 1, "blocked placement keeps the pack")
	await place(START + Vector3(10, 6, 0), Pack.TURRET)
	await press(PlayerCommand.USE)
	checks.check(player.deploy_ready and game.assets.size() == 1, "can't place while airborne")

	await place(START + Vector3(10, 0, 0), Pack.TURRET)
	var before := game.get_state()
	await press(PlayerCommand.USE)
	var turret_id: int = before.next_id
	var turret := game.asset(turret_id)
	checks.check(turret != null and turret.deployed and not player.deploy_ready, "pack command places a turret and consumes stock")
	if turret == null:
		checks.finish(self)
		return
	var placed := game.get_state()
	game.set_state(before)
	checks.check(game.asset(turret_id) == null and player.deploy_ready, "restore removes the turret and restores stock")
	await place(START + Vector3(10, 0, 0), Pack.SENSOR)
	await press(PlayerCommand.USE)
	var alternate := game.asset(turret_id)
	checks.check(alternate != null and alternate.kind == BaseAsset.Kind.SENSOR, "another timeline can use the same id for a sensor")
	game.set_state(placed)
	turret = game.asset(turret_id)
	checks.check(turret != alternate and turret.kind == BaseAsset.Kind.TURRET and turret.head != null, "restore rebuilds equipment when the id was reused")
	checks.check(turret != null and turret.deployed and not player.deploy_ready and placed.next_id == game.next_id, "restore recreates the turret and stock")
	await place(START + Vector3(15, 0, 0), Pack.TURRET)
	await press(PlayerCommand.DEPLOY)
	checks.check(game.deploy_count(0, BaseAsset.Kind.TURRET) == 2, "deploy command places a second turret")
	game.damage_asset(turret, 1000.0, 0, 1, START)
	await place(START + Vector3(25, 0, 0), Pack.TURRET)
	await press(PlayerCommand.USE)
	checks.check(result == "Team limit reached" and player.deploy_ready, "a repairable wreck counts towards the team limit")

	await place(START + Vector3(30, 0, 0), Pack.SENSOR)
	await press(PlayerCommand.USE)
	var enemy := game.add_soldier(1, Transform3D(Basis.IDENTITY, Vector3(35, 0.05, -25)))
	game.damage_asset(generator, 1000.0, 0, 1, START)
	await ticks(10)
	checks.check(not game.powered(0) and game.sensed[0].has(enemy.entity_id), "field sensor has its own power")
	checks.check(not game.station_working(fixed_pad) and game.asset_powered(turret), "base pad depends on the generator, field turret has its own power")

	await place(START + Vector3(35, 0, 0), Pack.STATION)
	var before_pad := game.get_state()
	await press(PlayerCommand.USE)
	var pad_id: int = before_pad.next_id + 1
	var pad: InventoryStation = game.stations.get(pad_id)
	checks.check(pad != null and game.station_working(pad), "field station has its own power")
	if pad == null:
		checks.finish(self)
		return
	var with_pad := game.get_state()
	game.set_state(before_pad)
	checks.check(not game.stations.has(pad_id) and not game.assets.has(pad.asset_id), "restore removes both parts of a placed station")
	game.set_state(with_pad)
	pad = game.stations[pad_id]
	var machine := game.asset(pad.asset_id)
	var ray := game.world_ray(machine.centre() + Vector3.UP, machine.centre(), Match.PAD_LAYER)
	checks.check(ray.get("collider") == machine, "shots can hit the station")
	player.global_position = pad.global_position + Vector3.UP * 0.05
	await ticks(4)
	checks.check(game.station_under(player) == pad and player.deploy_ready, "friendly station restocks the pack")
	game.damage_asset(machine, 1000.0, 0, 1, START)
	await ticks(2)
	checks.check(game.station_under(player) == null, "destroyed station stops serving soldiers")
	await place(pad.position + Vector3(0, 0.05, 2.8), Pack.REPAIR)
	input.command.pitch = -0.5
	checks.check(game.repair_target(player, 4.0) == machine, "repair pack can target the wreck")
	input.command.buttons = PlayerCommand.USE
	await ticks(950)
	input.command.buttons = 0
	checks.check(game.station_working(pad), "repair pack brings the deployed station back")

	await _bot_deploys()
	checks.finish(self)


func _bot_deploys() -> void:
	var bot_game := Match.new(22)
	root.add_child(bot_game)
	bot_game.add_flag(0, Vector3(0, 0.5, 12), Vector3(0, 0.5, 12))
	bot_game.add_flag(1, Vector3(0, 0.5, -200), Vector3(0, 0.5, -200))
	var graph := RouteGraph.new()
	var site := Vector3(10, 0, 12)
	var spawn := Vector3(10, 0.05, 24)
	var a := graph.add_point(spawn)
	var b := graph.add_point(site)
	graph.add_link(a, b, RouteGraph.Kind.RUN)
	graph.add_link(b, a, RouteGraph.Kind.RUN)
	graph.add_interest(RouteGraph.DEPLOY, 0, b)
	var director := BotDirector.new(bot_game, graph)
	var brain := director.add_bot(0, Transform3D(Basis.IDENTITY, graph.points[a]))
	bot_game.add_soldier(0, Transform3D(Basis.IDENTITY, Vector3(-100, 0.05, 12)))
	director.commander(0)._lock(brain, BotBrain.Role.DEFENCE, 0, -1, Orders.Kind.SET_ROLE, 0)
	brain.dress()
	await ticks(360)
	var near_site := false
	for asset: BaseAsset in bot_game.assets.values():
		near_site = near_site or (asset.deployed and asset.position.distance_to(site) < 1.0)
	checks.check(near_site, "a defence bot places a turret at a marked spot")
