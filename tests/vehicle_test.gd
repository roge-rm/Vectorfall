extends SceneTree

const TICK := 1.0 / 60.0

var checks := TestWorld.Checks.new()
var game: Match
var pilot: Soldier
var rider: Soldier
var enemy: Soldier
var pilot_input := TestWorld.Scripted.new()
var rider_input := TestWorld.Scripted.new()
var pads: Array[VehiclePad] = []


func _initialize() -> void:
	TestWorld.flat_ground(root)
	game = Match.new(12)
	root.add_child(game)
	for kind in Vehicle.NAMES.size():
		pads.append(game.fleet.add_pad(0, kind as Vehicle.Kind, Vector3(kind * 14, 0, 0), 0.0))
	pilot = game.add_soldier(0, Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 4)), pilot_input)
	rider = game.add_soldier(0, Transform3D(Basis.IDENTITY, Vector3(95, 0.05, 10)), rider_input)
	enemy = game.add_soldier(1, Transform3D(Basis.IDENTITY, Vector3(125, 0.05, 10)))
	_run.call_deferred()


func ticks(count: int) -> void:
	for i in count:
		await physics_frame


func hull(kind: int) -> Vehicle:
	return game.fleet.hulls.get(pads[kind].hull_id)


func put(who: Soldier, at: Vector3) -> void:
	who.position = at
	who.velocity = Vector3.ZERO


func tap(input: TestWorld.Scripted, button: int) -> void:
	input.command.buttons |= button
	await ticks(2)
	input.command.buttons &= ~button
	await ticks(2)


func board(craft: Vehicle, who: Soldier, input: TestWorld.Scripted) -> void:
	put(who, craft.position + Vector3(Vehicle.SIZE[craft.kind].x * 0.5 + 1.2, -craft.position.y + 0.05, 1.0))
	await ticks(4)
	input.command.board_id = craft.entity_id
	await tap(input, PlayerCommand.BOARD)
	input.command.board_id = 0


func _run() -> void:
	await ticks(4)
	checks.check(game.fleet.hulls.size() == 5, "all five kinds spawn on powered pads")
	if game.fleet.hulls.size() != 5:
		checks.finish(self)
		return
	var bike := hull(Vehicle.Kind.BIKE)
	var at := bike.position
	await board(bike, pilot, pilot_input)
	checks.check(pilot.vehicle_id == bike.entity_id and pilot.vehicle_seat == 0 and pilot.collision_layer == 0, "board moves a soldier to the driver seat")
	pilot_input.command.move = Vector2.UP * -1.0
	await ticks(72)
	pilot_input.command.move = Vector2.ZERO
	checks.check(bike.position.z < at.z - 10.0 and pilot.position.z < at.z - 10.0, "driving moves the grav bike and its rider together")
	await tap(pilot_input, PlayerCommand.BOARD)
	checks.check(pilot.vehicle_id == 0 and pilot.collision_layer == Match.SOLDIER_LAYER, "exit restores the soldier's collision and controls")

	var ferry := hull(Vehicle.Kind.TRANSPORT)
	await board(ferry, pilot, pilot_input)
	await board(ferry, rider, rider_input)
	checks.check(pilot.vehicle_seat == 0 and rider.vehicle_seat == 1 and rider.vehicle_id == ferry.entity_id, "transport has a pilot and separate passenger seats")
	var a_shot := game.next_id
	rider_input.command.yaw = 1.57
	await tap(rider_input, PlayerCommand.FIRE)
	var rounds := game.projectiles.filter(func(shot: Projectile) -> bool: return shot.id == a_shot and shot.vehicle_id == ferry.entity_id and shot.shooter == rider.entity_id)
	checks.check(rounds.size() == 1, "a passenger can fire a carried gun from the hull")
	var start_y := ferry.position.y
	pilot_input.command.buttons = PlayerCommand.JET
	await ticks(95)
	pilot_input.command.buttons = 0
	checks.check(ferry.position.y > start_y + 10.0, "holding climb lifts the transport")
	var flying := game.get_state()
	var id := ferry.entity_id
	await tap(rider_input, PlayerCommand.BOARD)
	checks.check(rider.vehicle_id == 0 and rider.velocity.y > 4.0, "a passenger can eject in the air")
	game.set_state(flying)
	checks.check(rider.vehicle_id == id and ferry.crew[1] == rider.entity_id and game.get_state() == flying, "snapshot restores flight, crew and their command state")
	pilot_input.command.buttons = PlayerCommand.JUMP
	await ticks(175)
	pilot_input.command.buttons = 0
	checks.check(ferry.position.y < start_y + 1.0, "holding descend brings the transport back to ground level")
	await tap(pilot_input, PlayerCommand.BOARD)
	await tap(rider_input, PlayerCommand.BOARD)

	var wing := hull(Vehicle.Kind.GUNSHIP)
	await board(wing, pilot, pilot_input)
	await board(wing, rider, rider_input)
	pilot_input.command.buttons = PlayerCommand.FIRE
	var no_shot := game.next_id
	await ticks(3)
	pilot_input.command.buttons = 0
	checks.check(game.next_id == no_shot, "the gunner takes the gun from the gunship pilot")
	var before_fire := game.next_id
	await tap(rider_input, PlayerCommand.FIRE)
	checks.check(game.next_id == before_fire + 1 and game.projectiles.any(func(shot: Projectile) -> bool: return shot.id == before_fire and shot.weapon == Weapon.TURRET and shot.shooter == rider.entity_id), "the gunner fires the swivel gun")

	var friendly := wing.health
	game.fleet.damage(wing, 50.0, pilot.entity_id, pilot.team, Weapon.DISC)
	checks.check(wing.health == friendly, "friendly weapons do not damage the hull")
	var struck := Projectile.new()
	struck.weapon = Weapon.DISC
	struck.shooter = enemy.entity_id
	struck.team = enemy.team
	struck.position = wing.position + Vector3(0, 0, -3.3)
	struck.velocity = Vector3.BACK * 120
	struck.damage = 55.0
	game.projectiles.append(struck)
	await ticks(3)
	checks.check(wing.health == friendly - 55.0 and pilot.health == pilot.tuning.health_max, "a direct hit damages the hull while shielding its crew")
	var wing_id := wing.entity_id
	var generator := game.add_asset(0, BaseAsset.Kind.GENERATOR, Vector3(-20, 0, 0))
	game.damage_asset(generator, 500.0, enemy.entity_id, enemy.team, enemy.position)
	var before_destroy := game.get_state()
	game.fleet.damage(wing, 1000, enemy.entity_id, enemy.team, Weapon.DISC)
	checks.check(not game.fleet.hulls.has(wing_id) and pilot.vehicle_id == 0 and rider.vehicle_id == 0, "destroying a hull ejects its crew")
	var wing_pad := pads[Vehicle.Kind.GUNSHIP]
	await ticks(6)
	checks.check(wing_pad.hull_id == 0 and wing_pad.remaining == VehiclePad.RESPAWN, "generator power is required for the replacement timer")
	wing_pad.remaining = TICK
	game.repair_asset(generator, generator.max_health(), pilot.entity_id)
	await ticks(4)
	checks.check(wing_pad.hull_id != 0 and wing_pad.hull_id != wing_id, "a powered pad replaces its hull with a fresh id")
	game.set_state(before_destroy)
	wing = game.fleet.hulls.get(wing_id)
	checks.check(wing != null and wing.crew[0] == pilot.entity_id and not game.powered(0), "snapshot recreates the old hull in place of its replacement")

	await tap(pilot_input, PlayerCommand.BOARD)
	await tap(rider_input, PlayerCommand.BOARD)
	var bomber := hull(Vehicle.Kind.BOMBER)
	await board(bomber, pilot, pilot_input)
	pilot_input.command.buttons = PlayerCommand.JET
	await ticks(100)
	pilot_input.command.buttons = 0
	var bomb_id := game.next_id
	await tap(pilot_input, PlayerCommand.FIRE)
	checks.check(game.projectiles.any(func(shot: Projectile) -> bool: return shot.id == bomb_id and shot.velocity.y < 0.0 and shot.weapon == Weapon.MORTAR), "the bomber drops a shell beneath the hull")
	await tap(pilot_input, PlayerCommand.BOARD)

	var tank := hull(Vehicle.Kind.TANK)
	await board(tank, pilot, pilot_input)
	var tank_origin := tank.position
	pilot_input.command.move = Vector2(0, 1)
	pilot_input.command.buttons = PlayerCommand.JET
	await ticks(55)
	pilot_input.command.move = Vector2.ZERO
	pilot_input.command.buttons = 0
	checks.check(tank.position.z < tank_origin.z - 4.0 and absf(tank.position.y - tank_origin.y) < 0.3, "the tank drives along the ground")
	var cannon_id := game.next_id
	await tap(pilot_input, PlayerCommand.FIRE)
	checks.check(game.projectiles.any(func(shot: Projectile) -> bool: return shot.id == cannon_id and shot.weapon == Weapon.DISC), "the tank fires its cannon")
	await ticks(65)
	game.add_field(1, tank.position + Vector3(2.24, 0.7, 0), Vector3(0.12, 3.3, 6.0))
	await ticks(3)
	await tap(pilot_input, PlayerCommand.BOARD)
	checks.check(pilot.vehicle_id == 0 and pilot.position.x < tank.position.x, "exit tries the other side when a field blocks the way")
	await _impacts()
	checks.finish(self)


func _impacts() -> void:
	game.queue_free()
	await process_frame
	game = Match.new(14)
	root.add_child(game)
	var first := game.fleet.add_pad(0, Vehicle.Kind.BIKE, Vector3(-20, 0, 0), 0.0)
	var second := game.fleet.add_pad(0, Vehicle.Kind.BIKE, Vector3(-30, 0, 0), 0.0)
	pilot = game.add_soldier(0, Transform3D(Basis.IDENTITY, Vector3(-20, 0, 4)), pilot_input)
	rider = game.add_soldier(0, Transform3D(Basis.IDENTITY, Vector3(40, 0, 10)))
	enemy = game.add_soldier(1, Transform3D(Basis.IDENTITY, Vector3(40, 0, 12)))
	await ticks(4)
	var bike: Vehicle = game.fleet.hulls.get(first.hull_id)
	var parked: Vehicle = game.fleet.hulls.get(second.hull_id)
	await board(bike, pilot, pilot_input)
	var ride_y := bike.position.y
	var full := bike.health
	var impacts := []
	game.hit.connect(func(attacker: int, victim: int, slot: int) -> void:
		impacts.append([attacker, victim, slot]))
	bike.position = Vector3(20, ride_y, 0)
	bike.velocity = Vector3.FORWARD * 35.0
	put(enemy, Vector3(20, 0, -2.7))
	put(rider, Vector3(20, 0, -4.0))
	pilot_input.command.move = Vector2(0, 1)
	await ticks(16)
	checks.check(impacts == [[pilot.entity_id, enemy.entity_id, Weapon.VEHICLE_IMPACT]] and enemy.health < enemy.tuning.health_max and not enemy.dead,
		"a fast hull hits the enemy once and credits its driver (%s, health %.1f)" % [str(impacts), enemy.health])
	checks.check(bike.health == full and rider.health == rider.tuning.health_max and bike.position.z < -4.0,
		"soldiers neither block the hull nor damage it, and teammates take no ram damage")

	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(20, 12, 1)
	shape.shape = wall_box
	wall.add_child(shape)
	wall.position = Vector3(20, 6, -20)
	root.add_child(wall)
	put(enemy, Vector3(20, 0, -21.1))
	bike.position = Vector3(20, ride_y, -17.65)
	bike.velocity = Vector3(18, 0, -4)
	await ticks(6)
	checks.check(bike.health == full, "a glancing scrape does no crash damage")

	bike.position = Vector3(20, ride_y, -16)
	bike.velocity = Vector3.FORWARD * 32.0
	await ticks(8)
	var crashed_health := bike.health
	checks.check(crashed_health < full and crashed_health > 0.0 and impacts.size() == 1,
		"a direct crash hurts the hull without ramming a soldier behind the wall")
	await ticks(40)
	checks.check(bike.health == crashed_health, "pushing against a wall does not add crash damage")

	bike.position = Vector3(0, ride_y, 8)
	bike.velocity = Vector3.FORWARD * 42.0
	parked.position = Vector3(0, ride_y, 3)
	await ticks(8)
	checks.check(bike.health < crashed_health and parked.health < full and parked.health > 0.0,
		"a fast crash damages both vehicles even on the same team")
	wall.queue_free()
