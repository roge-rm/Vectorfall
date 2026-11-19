extends SceneTree

## Checks weapons, health and respawning: direct hits and splash damage with
## falloff, splash knockback and disc jumps, less damage from your own shots
## and none from a teammate's, velocity inheritance, shots that never pass
## through a wall or the ground at full speed, weapon switching and spin up,
## death and respawn at the right base, and match state with shots in flight
## round-tripping through get_state() and set_state(). The five newer
## weapons: each fires only from the armours it's allowed on, grenades
## bounce and go off at their fuse or on a soldier, the mortar's splash and
## push, the sniper rifle's damage scaling with energy and taking it, the
## blaster taking energy and bouncing once, and energy weapons stopping
## without energy.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/weapon_test.gd

const TICK := 1.0 / 60.0
const Armour := SoldierBody.Armour

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

	await _new_weapons()

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


## Gives a soldier a loadout and puts it standing still at a point.
func arm(who: Soldier, armour: int, slots: Array[int], at: Vector3) -> void:
	who.set_loadout(Loadout.make(armour, slots))
	place(who, at)


func set_energy(who: Soldier, value: float) -> void:
	var state := who.get_state()
	state.energy = value
	state.cooldown = 0.0
	who.set_state(state)


## The newest shot from a soldier, or null.
func last_shot(from: Soldier) -> Projectile:
	for k in range(game.projectiles.size() - 1, -1, -1):
		if game.projectiles[k].shooter == from.entity_id:
			return game.projectiles[k]
	return null


## Pitch from a soldier's eye to a point.
func pitch_to(who: Soldier, at: Vector3) -> float:
	var eye := who.eye_transform().origin
	return atan2(at.y - eye.y, Vector2(at.x - eye.x, at.z - eye.z).length())


func _new_weapons() -> void:
	input_a.command = PlayerCommand.new()
	input_b.command = PlayerCommand.new()
	place(b, Vector3(0.0, 0.0, -100.0))

	# Each fires only from the armours it's allowed on: a loadout drops it
	# anywhere else and the shot is a disc.
	var allowed := {
		Weapon.GRENADE_LAUNCHER: [Armour.LIGHT, Armour.MEDIUM, Armour.HEAVY],
		Weapon.MORTAR: [Armour.HEAVY],
		Weapon.PLASMA: [Armour.MEDIUM, Armour.HEAVY],
		Weapon.SNIPER: [Armour.LIGHT],
		Weapon.BLASTER: [Armour.LIGHT, Armour.MEDIUM, Armour.HEAVY],
	}
	var right := true
	var wrong: Array[String] = []
	for slot: int in allowed:
		for armour in 3:
			arm(a, armour, [slot], Vector3(0.0, 0.0, 0.0))
			input_a.command.pitch = 0.8
			game.projectiles.clear()
			await fire_once(input_a)
			var shot := last_shot(a)
			var fired_slot := shot.weapon if shot != null else -1
			var expect: int = slot if allowed[slot].has(armour) else Weapon.DISC
			if fired_slot != expect or Loadout.allows(armour, slot) != allowed[slot].has(armour):
				right = false
				wrong.append("%s on %d fired %d" % [Weapon.all[slot].short_name, armour, fired_slot])
	game.projectiles.clear()
	checks.check(right, "each new weapon fires from its armours only, a disc anywhere else %s" % [wrong])

	# A grenade lobbed at the ground bounces and goes off at its fuse.
	var grenades := Weapon.all[Weapon.GRENADE_LAUNCHER]
	arm(a, Armour.MEDIUM, [Weapon.GRENADE_LAUNCHER], Vector3(0.0, 0.0, 0.0))
	input_a.command.pitch = -0.3
	impacts.clear()
	await fire_once(input_a)
	var grenade := last_shot(a)
	var bounced := 0
	var falling := true
	var went_off := -1
	for i in 150:
		await ticks(1)
		if not game.projectiles.has(grenade):
			went_off = i + 1
			break
		if falling and grenade.velocity.y > 0.0:
			bounced += 1
		falling = grenade.velocity.y <= 0.0
	var fuse_ticks := roundi(grenades.fuse * 60.0)
	checks.check(bounced >= 1 and grenade.position.y < 1.0, "a grenade bounces off the ground (%d bounces)" % bounced)
	checks.check(absi(went_off + 1 - fuse_ticks) <= 2 and impacts.size() == 1, "and goes off at its %.0f s fuse (after %d ticks, %d blasts)" % [grenades.fuse, went_off + 1, impacts.size()])

	# A grenade straight at a soldier goes off on it, for the full splash.
	place(b, Vector3(0.0, 0.0, -10.0))
	await ticks(2)
	place(a, Vector3(0.0, 0.0, 0.0))
	input_a.command.pitch = pitch_to(a, b.centre() + Vector3.UP * 0.6)
	await fire_once(input_a)
	await ticks(30)
	var loss := b.tuning.health_max - b.health
	checks.check(absf(loss - grenades.splash_damage) < 1.5, "a grenade that hits a soldier goes off on it for %.1f damage" % loss)

	# The mortar: more splash and push than the disc, out to 12 m.
	var mortar := Weapon.all[Weapon.MORTAR]
	place(b, Vector3(0.0, 0.0, -20.0))
	await ticks(2)
	game.explode(Vector3(6.0 + b.tuning.radius, b.tuning.radius, -20.0), Weapon.MORTAR, a.entity_id)
	var mortar_loss := b.tuning.health_max - b.health
	var thrown := b.velocity.length()
	var expected_push := mortar.splash_impulse_at(6.0) / b.tuning.mass
	checks.check(absf(mortar_loss - mortar.splash_damage_at(6.0)) < 0.6 and absf(thrown - expected_push) < 0.5, "a mortar 6 m away does %.1f damage and throws at %.1f m/s" % [mortar_loss, thrown])
	place(b, Vector3(0.0, 0.0, -20.0))
	await ticks(2)
	game.explode(Vector3(11.0 + b.tuning.radius, b.tuning.radius, -20.0), Weapon.MORTAR, a.entity_id)
	checks.check(b.health < b.tuning.health_max, "and still hurts 11 m away, past the disc's 7 m (%.1f)" % (b.tuning.health_max - b.health))

	# The sniper rifle: damage with the energy you have, taking 60 a shot.
	var sniper := Weapon.all[Weapon.SNIPER]
	arm(a, Armour.LIGHT, [Weapon.SNIPER, Weapon.DISC], Vector3(0.0, 0.0, 0.0))
	place(b, Vector3(0.0, 0.0, -40.0))
	await ticks(2)
	input_a.command.pitch = pitch_to(a, b.centre())
	var losses: Array[float] = []
	var energy_after: Array[float] = []
	for energy: float in [a.tuning.energy_max, 85.0]:
		place(b, Vector3(0.0, 0.0, -40.0))
		place(a, Vector3(0.0, 0.0, 0.0))
		set_energy(a, energy)
		await fire_once(input_a)
		energy_after.append(a.energy)
		await ticks(10)
		losses.append(b.tuning.health_max - b.health)
	var half := lerpf(sniper.min_damage, sniper.damage, inverse_lerp(sniper.energy_per_shot, a.tuning.energy_max, 85.0))
	checks.check(absf(losses[0] - sniper.damage) < 0.1 and absf(losses[1] - half) < 1.0, "the sniper rifle does %.0f at full energy and %.1f at 85 (%s)" % [sniper.damage, half, losses])
	checks.check(absf(energy_after[0] - (a.tuning.energy_max - sniper.energy_per_shot)) < 1.0 and absf(energy_after[1] - (85.0 - sniper.energy_per_shot)) < 1.0, "and takes %.0f energy a shot (%s left)" % [sniper.energy_per_shot, energy_after])
	place(a, Vector3(0.0, 0.0, 0.0))
	set_energy(a, sniper.energy_per_shot - 1.0)
	var shots := a.shots
	await fire_once(input_a)
	checks.check(a.shots == shots, "it won't fire under %.0f energy" % sniper.energy_per_shot)

	# The blaster takes a little energy a shot, and none at all stops it.
	var blaster := Weapon.all[Weapon.BLASTER]
	arm(a, Armour.MEDIUM, [Weapon.BLASTER], Vector3(0.0, 0.0, 0.0))
	input_a.command.pitch = 0.6
	set_energy(a, 50.0)
	await fire_once(input_a)
	var bolt := last_shot(a)
	checks.check(bolt != null and bolt.weapon == Weapon.BLASTER and absf(a.energy - (50.0 - blaster.energy_per_shot)) < 0.6 and a.ammo == [0], "the blaster takes %.0f energy a shot and no ammo (%.1f left)" % [blaster.energy_per_shot, a.energy])
	set_energy(a, 0.0)
	shots = a.shots
	await fire_once(input_a)
	checks.check(a.shots == shots, "and won't fire with no energy")
	game.projectiles.clear()

	# A bolt aimed down glances off the ground once, then stops at the wall.
	impacts.clear()
	var glance := Projectile.new()
	glance.id = 9300
	glance.weapon = Weapon.BLASTER
	glance.damage = blaster.damage
	glance.bounces_left = blaster.bounces
	glance.position = Vector3(295.0, 3.0, -10.0)
	glance.velocity = Vector3(0.0, -30.0, -147.0).normalized() * blaster.speed
	game.projectiles.append(glance)
	await ticks(15)
	var at_wall := impacts.size() == 1 and impacts[0].z > -30.0 and impacts[0].z < -29.5 and impacts[0].y > 0.3
	checks.check(at_wall and glance.bounces_left == 0 and game.projectiles.is_empty(), "a blaster bolt bounces off the ground once and stops at the next wall (%s)" % [impacts])

	# Back to the usual loadout for the rest.
	a.set_loadout(Loadout.standard())
	input_a.command = PlayerCommand.new()
	await ticks(30)


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
