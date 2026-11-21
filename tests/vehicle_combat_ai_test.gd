extends SceneTree

var checks := TestWorld.Checks.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var floor := TestWorld.flat_ground(root)
	var game := Match.new(32)
	root.add_child(game)
	game.running = false
	game.add_flag(0, Vector3(-105, 0.5, 0), Vector3(-105, 0.5, 0))
	game.add_flag(1, Vector3(155, 0.5, 0), Vector3(155, 0.5, 0))
	var director := BotDirector.new(game, RouteGraph.new())
	var pilot := director.add_bot(0, Transform3D(Basis.IDENTITY, Vector3(-110, 0.05, 0))).soldier
	var gunner := director.add_bot(0, Transform3D(Basis.IDENTITY, Vector3(-110, 0.05, -4))).soldier
	var boss := director.commander(0)
	var enemy := game.add_soldier(1, Transform3D(Basis.IDENTITY, Vector3(75, 0.05, -6)))
	game._take_flag(game.flags[0], enemy)
	var policy := director.vehicle_orders.combat
	var wing := _hull(game, Vehicle.Kind.GUNSHIP, Vector3(0, 29, 0), [pilot.entity_id, gunner.entity_id])
	var bomber := _hull(game, Vehicle.Kind.BOMBER, Vector3(-95, 30, 0), [pilot.entity_id])
	var tank := _hull(game, Vehicle.Kind.TANK, Vector3(0, 0.98, 0), [pilot.entity_id, 0])
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 2.2, 0.7)
	var collider := CollisionShape3D.new()
	collider.shape = box
	var body := StaticBody3D.new()
	body.position = Vector3(6, 1.1, 2.2)
	body.add_child(collider)
	root.add_child(body)
	await physics_frame
	await physics_frame
	_gunship_check(policy, boss, wing, enemy)
	_bomber_check(policy, boss, bomber)
	_ground_check(policy, boss, tank)
	_completed_support(boss, tank, bomber, enemy)
	body.free()
	game.free()
	floor.free()
	checks.finish(self)


func _hull(game: Match, kind: Vehicle.Kind, at: Vector3, crew: Array) -> Vehicle:
	var hull := Vehicle.new()
	hull.kind = kind
	hull.position = at
	hull.entity_id = game.next_id
	game.next_id += 1
	hull.yaw = -PI * 0.5
	hull.crew.assign(crew)
	game.add_child(hull)
	return hull


func _gunship_check(policy: BotCombatVehicles, boss: TeamCommander, wing: Vehicle, enemy: Soldier) -> void:
	var objective := enemy.position
	var stationary := PlayerCommand.new()
	policy.pilot(wing, stationary, boss, enemy, objective)
	enemy.velocity = Vector3(0, 0, 33)
	var leading := PlayerCommand.new()
	policy.pilot(wing, leading, boss, enemy, objective)
	checks.check(absf(angle_difference(stationary.yaw, leading.yaw)) > 0.2 and leading.move.y > 0.0,
		"gunship pilot leads a moving carrier while the gunner has the weapon")
	var different_aim := PlayerCommand.new()
	policy.pilot(wing, different_aim, boss, null, objective)
	checks.check(is_equal_approx(different_aim.yaw, leading.yaw) and not leading.has(PlayerCommand.FIRE),
		"gunner targeting does not turn a crewed gunship away from the pursuit path")


func _bomber_check(policy: BotCombatVehicles, boss: TeamCommander, bomber: Vehicle) -> void:
	var target := Vector3.ZERO
	var lining_up := PlayerCommand.new()
	policy.pilot(bomber, lining_up, boss, null, target)
	checks.check(policy.bombing[bomber.entity_id].phase == BotCombatVehicles.BombPhase.RUN and not lining_up.has(PlayerCommand.FIRE),
		"bomber lines up and holds fire before the release point")
	bomber.position.x = 0.0
	bomber.velocity = Vector3(34, 0, 0)
	bomber.position.x = -BotCombatVehicles.bomb_landing(bomber, 0.0).x
	var release := PlayerCommand.new()
	policy.pilot(bomber, release, boss, null, target)
	var clear := PlayerCommand.new()
	policy.pilot(bomber, clear, boss, null, target)
	checks.check(release.has(PlayerCommand.FIRE) and not clear.has(PlayerCommand.FIRE) and clear.move.y > 0.0,
		"bomber drops at the predicted release point and flies clear")


func _ground_check(policy: BotCombatVehicles, boss: TeamCommander, tank: Vehicle) -> void:
	boss.game.tick = 2
	var through_centre := boss.game.world_ray(Vector3(0, 1.1, 0), Vector3(9, 1.1, 0), Match.WORLD_LAYER, [tank.get_rid()])
	var full_width := policy._clear_ground(tank, boss, -PI * 0.5, 9.0)
	checks.check(through_centre.is_empty() and full_width == 0, "tank detects an obstacle that misses its centreline")
	policy.ground_progress[tank.entity_id] = Vector2(145, 0)
	boss.game.tick = BotCombatVehicles.GROUND_STALL_TICKS + 8
	var exit := PlayerCommand.new()
	policy.pilot(tank, exit, boss, null, Vector3(150, 0, 0))
	checks.check(exit.has(PlayerCommand.BOARD) and exit.move == Vector2.ZERO, "a stalled ground pilot stops and exits")
	var hold := PlayerCommand.new()
	policy.pilot(tank, hold, boss, null, Vector3(40, 0, 0))
	checks.check(not policy.ground_progress.has(tank.entity_id) and not hold.has(PlayerCommand.BOARD), "a tank holding at stand-off clears its stall timer")


func _completed_support(boss: TeamCommander, tank: Vehicle, bomber: Vehicle, enemy: Soldier) -> void:
	var game := boss.game
	var orders := boss.director.vehicle_orders
	var turret := game.add_asset(1, BaseAsset.Kind.TURRET, Vector3(155, 0, 0))
	for hull: Vehicle in [tank, bomber]:
		var pad := game.fleet.add_pad(0, hull.kind, Vector3(-105, 0, 30), hull.yaw)
		pad.hull_id = hull.entity_id
		hull.pad_id = pad.entity_id
		game.fleet.hulls[hull.entity_id] = hull
	orders.missions[tank.entity_id] = {"kind": "support", "target": enemy.entity_id, "objective": enemy.position}
	orders.missions[bomber.entity_id] = {"kind": "support", "target": turret.entity_id, "objective": turret.pivot()}
	var contact := Vector3(-60, 0, 20)
	boss.known[enemy.entity_id] = {"position": contact, "velocity": Vector3.ZERO, "tick": game.tick}
	orders._assign(game)
	checks.check(orders.mission_objective(tank, boss) == contact, "a tank follows the last known position of a nearby threat")
	boss.known.erase(enemy.entity_id)
	turret.destroyed = true
	orders._assign(game)
	var pilot := boss.director.brain_of(tank.crew[0])
	pilot.soldier.mount(tank.entity_id, 0)
	var tank_exit := orders.rider_command(pilot)
	checks.check(orders.mission_kind(tank).is_empty() and tank_exit.has(PlayerCommand.BOARD), "a tank pilot goes back on foot after the threat is gone")
	pilot.soldier.mount(bomber.entity_id, 0)
	orders.rider_command(pilot)
	checks.check(orders.mission_kind(bomber).is_empty() and orders.ferry.trips[bomber.entity_id].returning, "a bomber returns to land when its target is destroyed")
