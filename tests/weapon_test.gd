extends SceneTree

## Checks weapons, health and respawning: direct hits and splash damage with
## falloff, splash knockback and disc jumps, less damage from your own shots
## and none from a teammate's, velocity inheritance, shots that never pass
## through a wall or the ground at full speed, weapon switching and spin up,
## death and respawn at the right base, and match state with shots in flight
## round-tripping through get_state() and set_state().
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/weapon_test.gd

const TICK := 1.0 / 60.0

var checks := TestWorld.Checks.new()
var game: Match
var input_a := TestWorld.Scripted.new()
var input_b := TestWorld.Scripted.new()
var input_c := TestWorld.Scripted.new()
## Shooter on team 0, target on team 1 and a teammate of the shooter.
var a: Soldier
var b: Soldier
var c: Soldier
var impacts: Array[Vector3] = []
var kills: Array[Array] = []


func _initialize() -> void:
	TestWorld.flat_ground(root)
	# A thin wall far off to the side, and mesh ground raised 20 m.
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 20.0, 0.2)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	wall.position = Vector3(300.0, 10.0, -30.0)
	root.add_child(wall)
	var mesh := TestWorld.mesh_ground(root, 100.0)
	mesh.position = Vector3(-300.0, 20.0, 0.0)
	game = Match.new(11)
	game.spawns[0] = [Transform3D(Basis.IDENTITY, Vector3(-100.0, 0.5, 0.0))]
	game.spawns[1] = [Transform3D(Basis.IDENTITY, Vector3(100.0, 0.5, 0.0)), Transform3D(Basis.IDENTITY, Vector3(100.0, 0.5, 10.0))]
	root.add_child(game)
	a = game.add_soldier(0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, 0.0)), input_a)
	b = game.add_soldier(1, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, -20.0)), input_b)
	c = game.add_soldier(0, Transform3D(Basis.IDENTITY, Vector3(30.0, 0.2, 0.0)), input_c)
	game.impacted.connect(func(_w: int, at: Vector3, _n: Vector3) -> void: impacts.append(at))
	game.killed.connect(func(victim: int, killer: int, _w: int) -> void: kills.append([victim, killer]))
	_run.call_deferred()


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


## Puts a soldier standing still at a point, at full health.
func place(who: Soldier, at: Vector3) -> void:
	var state := who.get_state()
	state.position = at
	state.velocity = Vector3.ZERO
	state.grounded = true
	state.floor_normal = Vector3.UP
	state.health = who.tuning.health_max
	state.energy = who.tuning.energy_max
	state.cooldown = 0.0
	who.set_state(state)


func fire_once(source: TestWorld.Scripted) -> void:
	source.command.buttons |= PlayerCommand.FIRE
	await ticks(1)
	source.command.buttons &= ~PlayerCommand.FIRE


func _run() -> void:
	await ticks(20)
	var disc := Weapon.all[Weapon.DISC]
	var chaingun := Weapon.all[Weapon.CHAINGUN]

	# A disc straight into the target's chest.
	input_a.command.pitch = atan2(b.centre().y - a.eye_transform().origin.y, 20.0)
	await fire_once(input_a)
	await ticks(40)
	checks.check(is_equal_approx(b.health, b.tuning.health_max - disc.damage), "a direct disc hit does %.0f damage and no splash on top (health %.1f)" % [disc.damage, b.health])
	checks.check(game.projectiles.is_empty(), "the disc is gone after hitting")
	checks.check(a.ammo[Weapon.DISC] == disc.ammo - 1, "firing uses a disc")

	# Splash at set distances from the target's body.
	var losses: Array[float] = []
	for distance: float in [0.0, 2.0, 4.0, 6.0, 8.0]:
		place(b, Vector3(0.0, 0.0, -20.0))
		await ticks(2)
		# Level with the bottom of the capsule's middle, so the gap is exact.
		game.explode(Vector3(distance + b.tuning.radius, b.tuning.radius, -20.0), Weapon.DISC, a.entity_id)
		losses.append(b.tuning.health_max - b.health)
	var expected := [disc.splash_damage_at(0.0), disc.splash_damage_at(2.0), disc.splash_damage_at(4.0), disc.splash_damage_at(6.0), 0.0]
	var close := true
	for k in losses.size():
		close = close and absf(losses[k] - expected[k]) < 0.6
	checks.check(close, "splash damage falls off with distance (%s)" % [losses])
	checks.check(losses[0] > losses[1] and losses[1] > losses[2] and losses[2] > losses[3] and losses[4] == 0.0, "less damage further out and none past %.0f m" % disc.splash_radius)

	# A blast at the feet throws the soldier up.
	place(b, Vector3(0.0, 0.0, -20.0))
	await ticks(2)
	game.explode(Vector3(0.0, 0.05, -20.0), Weapon.DISC, a.entity_id)
	var kick := b.velocity.y
	var top := 0.0
	for i in 90:
		await ticks(1)
		top = maxf(top, b.global_position.y)
	checks.check(absf(kick - disc.splash_impulse / b.tuning.mass) < 0.5, "a blast at the feet kicks %.1f m/s upwards" % kick)
	checks.check(top > 4.0, "and throws the soldier %.1f m up" % top)

	# A teammate's blast pushes but doesn't hurt.
	place(c, Vector3(30.0, 0.0, 0.0))
	await ticks(2)
	game.explode(Vector3(30.0 + c.tuning.radius + 1.0, 0.05, 0.0), Weapon.DISC, a.entity_id)
	checks.check(c.health == c.tuning.health_max and c.velocity.length() > 5.0, "a teammate's blast pushes (%.1f m/s) but does no damage" % c.velocity.length())

	# Disc jump: jet up a little, then fire at your feet, against the same
	# jet without the disc.
	var heights: Array[float] = []
	var self_loss := 0.0
	for with_disc: bool in [false, true]:
		place(a, Vector3(0.0, 0.0, 0.0))
		input_a.command.pitch = -Soldier.PITCH_LIMIT
		await ticks(5)
		input_a.command.buttons = PlayerCommand.JET
		await ticks(12)
		if with_disc:
			await fire_once(input_a)
		await ticks(6)
		input_a.command.buttons = 0
		top = 0.0
		for i in 150:
			await ticks(1)
			top = maxf(top, a.global_position.y)
		heights.append(top)
		self_loss = a.tuning.health_max - a.health
	checks.check(heights[1] > heights[0] + 4.0, "a disc at your feet while jetting launches you higher (%.1f m against %.1f m)" % [heights[1], heights[0]])
	checks.check(self_loss > 0.0 and self_loss <= disc.splash_damage * disc.self_damage_share + 0.01, "your own disc does reduced damage (%.1f)" % self_loss)
	input_a.command.pitch = 0.0

	# Velocity inheritance while skiing fast across the way you fire, with
	# the chaingun's spread off so only the inherited part is sideways.
	var spread := chaingun.spread
	chaingun.spread = 0.0
	for weapon: Weapon in [disc, chaingun]:
		place(a, Vector3(0.0, 0.0, 0.0))
		var state := a.get_state()
		state.velocity = Vector3(30.0, 0.0, 0.0)
		state.weapon = weapon.slot
		state.spin = 1.0
		a.set_state(state)
		input_a.command.buttons = PlayerCommand.SKI | PlayerCommand.FIRE
		input_a.command.weapon = weapon.slot
		input_a.command.yaw = 0.0
		var before := game.projectiles.size()
		await ticks(1)
		input_a.command.buttons = PlayerCommand.SKI
		var shot: Projectile = game.projectiles.back() if game.projectiles.size() > before else null
		var side := shot.velocity.x if shot != null else 0.0
		checks.check(shot != null and absf(side - a.velocity.x * weapon.inherit) < 0.2, "the %s inherits %.0f%% of a 30 m/s sideways ski (%.1f m/s sideways)" % [weapon.name.to_lower(), weapon.inherit * 100.0, side])
		input_a.command.buttons = 0
		await ticks(60)
	input_a.command.weapon = -1
	chaingun.spread = spread

	# Shots at full speed and more never pass through a thin wall or mesh ground.
	impacts.clear()
	game.projectiles.clear()
	var speeds := [chaingun.speed + 80.0 * chaingun.inherit, disc.speed + 80.0 * disc.inherit]
	for k in 2:
		var shot := Projectile.new()
		shot.id = 9000 + k
		shot.weapon = k
		shot.shooter = 0
		shot.position = Vector3(300.0 + k, 5.0, 10.0)
		shot.velocity = Vector3(0.0, 0.0, -speeds[1 - k])
		game.projectiles.append(shot)
		var dive := Projectile.new()
		dive.id = 9100 + k
		dive.weapon = k
		dive.shooter = 0
		dive.position = Vector3(-300.0 + k, 60.0, 0.0)
		dive.velocity = Vector3(10.0, -speeds[1 - k], 0.0)
		game.projectiles.append(dive)
	await ticks(90)
	var wall_hits := impacts.filter(func(at: Vector3) -> bool: return at.x > 250.0)
	var ground_hits := impacts.filter(func(at: Vector3) -> bool: return at.x < -250.0)
	checks.check(wall_hits.size() == 2 and wall_hits.all(func(at: Vector3) -> bool: return at.z > -30.0 and at.z < -29.5), "fast shots stop at a 20 cm wall (%s)" % [wall_hits])
	checks.check(ground_hits.size() == 2 and ground_hits.all(func(at: Vector3) -> bool: return at.y > 19.9), "fast shots stop at mesh ground (%s)" % [ground_hits])
	checks.check(game.projectiles.is_empty(), "and none are left flying")

	# Switching and the chaingun's spin up.
	place(a, Vector3(0.0, 0.0, 0.0))
	input_a.command.pitch = 0.3
	input_a.command.weapon = Weapon.CHAINGUN
	await ticks(1)
	input_a.command.weapon = -1
	checks.check(a.weapon == Weapon.CHAINGUN, "a command picks the chaingun")
	await ticks(30)
	var shots := a.shots
	var rounds := a.ammo[Weapon.CHAINGUN]
	input_a.command.buttons = PlayerCommand.FIRE
	var spin_ticks := ceili(chaingun.spin_up * chaingun.spin_to_fire * 60.0)
	await ticks(spin_ticks - 1)
	checks.check(a.shots == shots, "the chaingun doesn't fire before it spins up")
	await ticks(60)
	var fired := a.shots - shots
	checks.check(fired >= 9 and fired <= 15, "then fires faster as it spins (%d in a second)" % fired)
	checks.check(a.ammo[Weapon.CHAINGUN] == rounds - fired, "using a round a shot")
	input_a.command.buttons = PlayerCommand.NEXT_WEAPON
	await ticks(1)
	input_a.command.buttons = 0
	checks.check(a.weapon == Weapon.DISC and a.spin == 0.0, "next weapon goes back round to the disc launcher")
	await ticks(60)

	# Death and respawn at the team's base after the delay.
	kills.clear()
	place(b, Vector3(0.0, 0.0, -20.0))
	await ticks(2)
	game.damage(b, 500.0, a.entity_id, Weapon.DISC, a.global_position)
	checks.check(b.dead and b.health == 0.0 and b.collision_layer == 0, "enough damage kills, and the body stops blocking")
	checks.check(kills.size() == 1 and kills[0] == [b.entity_id, a.entity_id], "the kill goes to the shooter")
	await ticks(roundi(Match.RESPAWN_DELAY * 60.0) - 3)
	checks.check(b.dead, "still dead just before the respawn delay")
	await ticks(5)
	var at_spawn := false
	for spawn: Transform3D in game.spawns[1]:
		at_spawn = at_spawn or Vector2(b.global_position.x, b.global_position.z).distance_to(Vector2(spawn.origin.x, spawn.origin.z)) < 0.5
	checks.check(not b.dead and b.health == b.tuning.health_max and at_spawn, "respawns at full health on a team 1 spawn point (%s)" % b.global_position)
	checks.check(b.ammo[Weapon.DISC] == disc.ammo and b.collision_layer == Match.SOLDIER_LAYER, "with full ammo and a body again")

	# Match state with shots in flight and a hurt soldier: save, play on, put
	# it back and play on again. Both runs must end the same.
	place(a, Vector3(0.0, 0.0, 0.0))
	place(b, Vector3(0.0, 0.0, -100.0))
	game.damage(b, 30.0, a.entity_id, Weapon.DISC, a.global_position)
	input_a.command.weapon = Weapon.CHAINGUN
	input_a.command.pitch = atan2(b.centre().y - a.eye_transform().origin.y, 100.0)
	input_a.command.buttons = PlayerCommand.FIRE
	await ticks(45)
	game.running = false
	var saved := game.get_state()
	checks.check(not saved.projectiles.is_empty() and b.health < b.tuning.health_max, "the saved state has %d shots in flight and a hurt soldier" % saved.projectiles.size())
	var play := func() -> Dictionary:
		for i in 40:
			game.step(TICK)
		return game.get_state()
	var first: Dictionary = play.call()
	game.set_state(saved)
	checks.check(game.get_state() == saved, "set_state then get_state gives back the same match")
	var second: Dictionary = play.call()
	checks.check(_same(first, second), "replaying from it ends the same (health %.1f and %.1f, %d and %d shots)" % [first.entities[b.entity_id].health, second.entities[b.entity_id].health, first.projectiles.size(), second.projectiles.size()])
	checks.finish(self)


## Two match states agree on every soldier's place and health and every shot.
func _same(one: Dictionary, two: Dictionary) -> bool:
	if one.projectiles.size() != two.projectiles.size() or one.rng_state != two.rng_state:
		return false
	for id: int in one.entities:
		var x: Dictionary = one.entities[id]
		var y: Dictionary = two.entities[id]
		if x.position.distance_to(y.position) > 1e-4 or not is_equal_approx(x.health, y.health) or x.ammo != y.ammo:
			return false
	for k in one.projectiles.size():
		if one.projectiles[k].position.distance_to(two.projectiles[k].position) > 1e-4:
			return false
	return true
