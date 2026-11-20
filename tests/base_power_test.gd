extends SceneTree

## Base assets and power: direct hits and splash damage an enemy generator but
## not your own, it's destroyed at 0 and the team loses power, stations do
## nothing without power, a repair pack brings a destroyed generator back
## (teammates first) and power returns, assets round-trip through the match
## state, and a replay from a saved state ends the same. A turret hits a
## still enemy and leaves its teammates alone, stops without power, can't
## see through a wall and with guard points only shoots enemies near them, and a sensor sees enemies in range but not a jammer.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/base_power_test.gd

const Armour := SoldierBody.Armour
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 0.0)

var checks := TestWorld.Checks.new()
var game: Match
var input := TestWorld.Scripted.new()
var a: Soldier
var b: Soldier
var mate: Soldier
var theirs: BaseAsset
var ours: BaseAsset
var turret: BaseAsset
var station: InventoryStation
var used := 0
var lost: Array[int] = []
var back: Array[int] = []
var destroyed: Array[int] = []
var repaired: Array[int] = []
## [victim, amount] for each hit by the turret, and its shots fired.
var turret_hits: Array = []
var turret_shots := 0


func _initialize() -> void:
	TestWorld.flat_ground(root)
	game = Match.new(5)
	root.add_child(game)
	theirs = game.add_asset(1, BaseAsset.Kind.GENERATOR, Vector3(0.0, 0.0, -15.0))
	ours = game.add_asset(0, BaseAsset.Kind.GENERATOR, Vector3(0.0, 0.0, 15.0))
	# Out of everyone's range until its own checks.
	turret = game.add_asset(1, BaseAsset.Kind.TURRET, Vector3(200.0, 0.0, -15.0), PI * 0.5)
	station = game.add_station(0, Vector3(-8.0, 0.0, 0.0))
	a = game.add_soldier(0, Transform3D(Basis.IDENTITY, START), input)
	b = game.add_soldier(1, Transform3D(Basis.IDENTITY, Vector3(60.0, 0.05, 60.0)))
	mate = game.add_soldier(0, Transform3D(Basis.IDENTITY, Vector3(-60.0, 0.05, 60.0)))
	game.station_used.connect(func(_station: int, _id: int) -> void: used += 1)
	game.power_lost.connect(func(team: int) -> void: lost.append(team))
	game.power_back.connect(func(team: int) -> void: back.append(team))
	game.asset_destroyed.connect(func(id: int, _by: int) -> void: destroyed.append(id))
	game.asset_repaired.connect(func(id: int, _by: int) -> void: repaired.append(id))
	game.damaged.connect(func(victim: int, attacker: int, amount: float, _from: Vector3) -> void:
		if attacker == turret.entity_id:
			turret_hits.append([victim, amount]))
	game.turret_fired.connect(func(id: int) -> void:
		if id == turret.entity_id:
			turret_shots += 1)
	_run.call_deferred()


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


## Puts a soldier standing still at a point.
func place(who: Soldier, at: Vector3) -> void:
	var state := who.get_state()
	state.position = at
	state.velocity = Vector3.ZERO
	state.grounded = true
	state.floor_normal = Vector3.UP
	state.energy = who.tuning.energy_max
	state.cooldown = 0.0
	who.set_state(state)


## Yaw and pitch from a's eye to a point, set on its command.
func aim_at(at: Vector3) -> void:
	var eye := a.eye_transform().origin
	var to := at - eye
	input.command.yaw = atan2(-to.x, -to.z)
	input.command.pitch = atan2(to.y, Vector2(to.x, to.z).length())


func full(machine: BaseAsset) -> void:
	machine.health = machine.max_health()
	machine.destroyed = false


func _run() -> void:
	await ticks(20)
	var disc := Weapon.all[Weapon.DISC]
	checks.check(game.assets.size() == 3 and theirs.health == 400.0 and turret.health == 250.0, "assets start at full health (400 and 250)")
	checks.check(game.powered(0) and game.powered(1), "both teams start with power")

	# A disc straight into the enemy generator: direct damage, no splash on top.
	input.command.weapon = Weapon.DISC
	await ticks(30)
	aim_at(theirs.centre())
	await ticks(2)
	input.command.buttons = PlayerCommand.FIRE
	await ticks(1)
	input.command.buttons = 0
	await ticks(40)
	checks.check(is_equal_approx(theirs.health, 400.0 - disc.damage), "a direct disc hit does %.0f to the enemy generator (health %.1f)" % [disc.damage, theirs.health])

	# The same at our own generator does nothing.
	place(a, START)
	aim_at(ours.centre())
	await ticks(30)
	input.command.buttons = PlayerCommand.FIRE
	await ticks(1)
	input.command.buttons = 0
	await ticks(40)
	checks.check(ours.health == 400.0, "a direct hit on our own generator does nothing (health %.1f)" % ours.health)

	# Splash 2 m from the generator's side.
	full(theirs)
	game.explode(Vector3(0.0, 0.5, -15.0 + theirs.radius() + 2.0), Weapon.DISC, a.entity_id)
	var expected := disc.splash_damage_at(2.0)
	checks.check(is_equal_approx(theirs.health, 400.0 - expected), "splash 2 m away does %.1f to the enemy generator (health %.1f)" % [expected, theirs.health])
	game.explode(Vector3(0.0, 0.5, 15.0 - ours.radius() - 1.0), Weapon.DISC, a.entity_id)
	checks.check(ours.health == 400.0, "splash by our own generator does nothing")
	game.explode(Vector3(0.0, 0.5, 15.0 - ours.radius() - 1.0), Weapon.MINE, 999, null, 1)
	checks.check(ours.health < 400.0, "an enemy mine whose owner is gone still hurts it")
	full(ours)

	# Destroyed at 0, and the team's power goes.
	game.damage_asset(theirs, 1000.0, a.entity_id, 0, Vector3.ZERO)
	checks.check(theirs.destroyed and theirs.health == 0.0 and destroyed == [theirs.entity_id], "the enemy generator is destroyed at 0")
	checks.check(not game.powered(1) and game.powered(0) and lost == [1], "team 1 loses power, team 0 keeps it")
	game.damage_asset(theirs, 10.0, a.entity_id, 0, Vector3.ZERO)
	checks.check(destroyed.size() == 1 and lost.size() == 1, "hitting a destroyed generator does nothing more")

	# Our generator down: our station does nothing.
	game.damage_asset(ours, 1000.0, b.entity_id, 1, Vector3.ZERO)
	checks.check(not game.powered(0) and lost == [1, 0], "our generator down takes our power")
	var heavy := Loadout.make(Armour.HEAVY, [Weapon.DISC, Weapon.MORTAR, Weapon.CHAINGUN, Weapon.PLASMA], Pack.SHIELD)
	input.command.loadout = heavy.to_dict()
	place(a, Vector3(-8.0, 0.05, 0.0))
	await ticks(3)
	input.command.loadout = {}
	checks.check(used == 0 and a.loadout.armour == Armour.MEDIUM and station.on.is_empty(), "a station without power does nothing (used %d)" % used)

	# Repair: a hurt teammate first, then our generator.
	a.set_loadout(Loadout.make(Armour.MEDIUM, [Weapon.DISC, Weapon.CHAINGUN], Pack.REPAIR))
	a.next_loadout = heavy
	place(a, Vector3(0.0, 0.05, 11.5))
	ours.health = ours.max_health() - 20.0
	place(mate, Vector3(1.0, 0.05, 13.2))
	mate.health = mate.tuning.health_max * 0.5
	aim_at(ours.centre())
	await ticks(3)
	checks.check(game.repair_target(a, 4.0) == mate, "a hurt teammate comes before the generator")
	place(mate, Vector3(-60.0, 0.05, 60.0))
	await ticks(2)
	checks.check(game.repair_target(a, 4.0) == ours, "with no teammate the pack picks our generator")
	checks.check(game.repair_target(b, 400.0) != ours, "an enemy can't repair it")
	input.command.buttons = PlayerCommand.USE
	await ticks(30)
	var gained := ours.health - (ours.max_health() - 20.0)
	checks.check(a.repair_target == ours.entity_id and gained > 6.5 and gained < 8.5, "the pack repairs it at 15 a second (%.2f in 0.5 s)" % gained)
	checks.check(ours.destroyed and not game.powered(0), "still down until it's full")
	await ticks(60)
	input.command.buttons = 0
	checks.check(not ours.destroyed and ours.health == ours.max_health() and repaired == [ours.entity_id], "full again, it's repaired")
	checks.check(game.powered(0) and back == [0], "and our power is back")
	place(a, Vector3(-8.0, 0.05, 0.0))
	await ticks(3)
	checks.check(used == 1 and a.loadout.equals(heavy), "the station works again with power back")

	# State: save, change, put back.
	full(theirs)
	await ticks(2)
	game.running = false
	var saved := game.get_state()
	checks.check(saved.assets.size() == 3 and saved.assets[theirs.entity_id].health == 400.0, "assets are in the match state")
	theirs.health = 12.0
	theirs.destroyed = true
	game.set_state(saved)
	checks.check(game.get_state() == saved and theirs.health == 400.0 and not theirs.destroyed, "set_state then get_state gives back the same match")

	# A match made from the state gets the assets too.
	var copy := Match.new(5)
	root.add_child(copy)
	copy.set_state(saved)
	var copied := copy.asset(turret.entity_id)
	checks.check(copied != null and copied.kind == BaseAsset.Kind.TURRET and copied.team == 1 and is_equal_approx(copied.facing, PI * 0.5), "set_state makes missing assets")
	copy.free()

	# Replay: chaingun fire at the enemy generator from a saved state, twice.
	place(a, START)
	input.command.weapon = Weapon.CHAINGUN
	for i in 30:
		game.step(TICK)
	aim_at(theirs.centre())
	input.command.buttons = PlayerCommand.FIRE
	for i in 5:
		game.step(TICK)
	var replay := game.get_state()
	var play := func() -> Dictionary:
		for i in 60:
			game.step(TICK)
		return game.get_state()
	var first: Dictionary = play.call()
	game.set_state(replay)
	var second: Dictionary = play.call()
	var h1: float = first.assets[theirs.entity_id].health
	var h2: float = second.assets[theirs.entity_id].health
	checks.check(h1 < 400.0 and is_equal_approx(h1, h2) and first.rng_state == second.rng_state, "a replay from the same state ends the same (health %.1f and %.1f)" % [h1, h2])
	await _turret_checks()
	await _sensor_checks()
	checks.finish(self)


func _turret_checks() -> void:
	game.running = true
	input.command = PlayerCommand.new()
	full(theirs)
	# The turret faces -x and a stands 25 m to its -z, with b, the turret's
	# teammate, 1.5 m beside it inside the splash.
	turret.position = Vector3(40.0, 0.0, 40.0)
	place(a, Vector3(40.0, 0.05, 15.0))
	place(b, Vector3(41.5, 0.05, 15.0))
	a.health = a.tuning.health_max
	b.health = b.tuning.health_max
	await ticks(150)
	var on_a := turret_hits.filter(func(each: Array) -> bool: return each[0] == a.entity_id)
	checks.check(on_a.size() >= 1 and on_a.any(func(each: Array) -> bool: return is_equal_approx(each[1], 25.0)), "the turret turns, fires and hits a still enemy for 25 (%d hits)" % on_a.size())
	checks.check(absf(wrapf(turret.aim_yaw, -PI, PI)) < 0.05 and turret.target_id == a.entity_id, "it aims at the enemy (yaw %.2f)" % turret.aim_yaw)
	checks.check(b.health == b.tuning.health_max and turret_hits.all(func(each: Array) -> bool: return each[0] != b.entity_id), "and leaves its teammate beside it alone")

	# No power, no shots.
	game.damage_asset(theirs, 1000.0, a.entity_id, 0, Vector3.ZERO)
	var shots := turret_shots
	a.health = a.tuning.health_max
	await ticks(120)
	checks.check(turret_shots == shots and turret.target_id == 0, "a turret without power doesn't fire")
	full(theirs)
	await ticks(60)
	checks.check(turret_shots > shots, "and fires again with power back")

	# A wall in the way: once it has looked again it stops.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 5.0, 0.5)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(40.0, 2.5, 28.0)
	root.add_child(wall)
	await ticks(30)
	a.health = a.tuning.health_max
	shots = turret_shots
	await ticks(120)
	checks.check(turret_shots == shots and turret.target_id == 0, "it can't see through a wall")
	wall.queue_free()
	await ticks(2)

	# Guard points: an enemy away from them is left alone, and one by them,
	# or above one, is shot at.
	turret.guard_points.assign([Vector3(10.0, 0.0, 15.0)])
	turret.guard_radius = 6.0
	checks.check(turret.get_state().guard_points == [Vector3(10.0, 0.0, 15.0)] and turret.get_state().guard_radius == 6.0, "a turret's guard points are in its state")
	await ticks(30)
	shots = turret_shots
	await ticks(120)
	checks.check(turret_shots == shots and turret.target_id == 0, "a turret with guard points leaves an enemy 30 m from them alone")
	checks.check(turret.guards(Vector3(14.0, 20.0, 15.0)) and not turret.guards(Vector3(10.0, -3.0, 15.0)), "it guards any height above a guard point and not well under it")
	turret.guard_points.assign([Vector3(36.0, 0.0, 15.0)])
	await ticks(150)
	checks.check(turret_shots > shots and turret.target_id == a.entity_id, "and shoots one within 6 m of one")
	turret.guard_points.clear()
	turret.position = Vector3(200.0, 0.0, -15.0)


func _sensor_checks() -> void:
	var sensor := game.add_asset(1, BaseAsset.Kind.SENSOR, Vector3(-40.0, 0.0, 40.0))
	place(a, Vector3(-40.0, 0.05, -20.0))
	await ticks(2)
	checks.check(game.sensed[1].has(a.entity_id) and not game.sensed[0].has(b.entity_id), "a sensor sees an enemy 60 m away")
	place(a, Vector3(-40.0, 0.05, -60.0))
	await ticks(2)
	checks.check(not game.sensed[1].has(a.entity_id), "but not one 100 m away")
	place(a, Vector3(-40.0, 0.05, -20.0))
	a.set_loadout(Loadout.make(Armour.LIGHT, [Weapon.DISC], Pack.JAMMER))
	a.pack_on = true
	await ticks(2)
	checks.check(not game.sensed[1].has(a.entity_id), "nor a jammer")
	a.pack_on = false
	game.damage_asset(theirs, 1000.0, a.entity_id, 0, Vector3.ZERO)
	await ticks(2)
	checks.check(not game.sensed[1].has(a.entity_id), "and nothing without power")
	full(theirs)
	game.damage_asset(sensor, 1000.0, a.entity_id, 0, Vector3.ZERO)
	await ticks(2)
	checks.check(sensor.destroyed and not game.sensed[1].has(a.entity_id), "or once it's destroyed")
