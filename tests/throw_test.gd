extends SceneTree

## Checks hand grenades and mines: the command bits, counts per armour, one
## throw per press with a cooldown, a grenade's speed with the thrower's
## velocity, bounce, fuse and kill feed, mines sticking where they land,
## arming, going off on an enemy and not a teammate, the most out per
## soldier, staying when the owner dies, going off from a blast close by,
## and a match with both in it saving and replaying the same.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/throw_test.gd

const TICK := 1.0 / 60.0
const Armour := SoldierBody.Armour

var checks := TestWorld.Checks.new()
var game: Match
var input_a := TestWorld.Scripted.new()
var input_b := TestWorld.Scripted.new()
var input_c := TestWorld.Scripted.new()
## Thrower on team 0, an enemy on team 1 and a teammate of the thrower.
var a: Soldier
var b: Soldier
var c: Soldier
var blasts: Array[int] = []
var kills: Array[Array] = []


func _initialize() -> void:
	TestWorld.flat_ground(root)
	game = Match.new(5)
	game.spawns[0] = [Transform3D(Basis.IDENTITY, Vector3(-200.0, 0.5, 0.0))]
	game.spawns[1] = [Transform3D(Basis.IDENTITY, Vector3(200.0, 0.5, 0.0))]
	root.add_child(game)
	a = game.add_soldier(0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, 0.0)), input_a)
	b = game.add_soldier(1, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, -100.0)), input_b)
	c = game.add_soldier(0, Transform3D(Basis.IDENTITY, Vector3(100.0, 0.2, 0.0)), input_c)
	game.impacted.connect(func(w: int, _at: Vector3, _n: Vector3) -> void: blasts.append(w))
	game.killed.connect(func(victim: int, killer: int, w: int) -> void: kills.append([victim, killer, w]))
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
	state.throw_cooldown = 0.0
	who.set_state(state)


## Presses a button for one tick.
func press(source: TestWorld.Scripted, button: int) -> void:
	source.command.buttons |= button
	await ticks(1)
	source.command.buttons &= ~button


func last_shot(from: Soldier) -> Projectile:
	for k in range(game.projectiles.size() - 1, -1, -1):
		if game.projectiles[k].shooter == from.entity_id:
			return game.projectiles[k]
	return null


func mine_ids(owner_id: int) -> Array[int]:
	var ids: Array[int] = []
	for mine in game.mines:
		if mine.owner_id == owner_id:
			ids.append(mine.id)
	return ids


## Throws a mine at a's feet and waits for it to land. Returns its id.
func lay_mine() -> int:
	input_a.command.pitch = -1.3
	await press(input_a, PlayerCommand.MINE)
	var shot := last_shot(a)
	for i in 60:
		if not game.projectiles.has(shot):
			break
		await ticks(1)
	await ticks(int(Soldier.THROW_TIME * 60.0) + 1)
	return shot.id


func _run() -> void:
	# The command bits are new, apart from the others and carried in the dict.
	var command := PlayerCommand.new()
	command.buttons = PlayerCommand.GRENADE | PlayerCommand.MINE
	var copy := PlayerCommand.from_dict(command.to_dict())
	var others := PlayerCommand.FIRE | PlayerCommand.JUMP | PlayerCommand.JET | PlayerCommand.USE | PlayerCommand.DEPLOY | PlayerCommand.SKI | PlayerCommand.NEXT_WEAPON | PlayerCommand.PREV_WEAPON
	checks.check(copy.has(PlayerCommand.GRENADE) and copy.has(PlayerCommand.MINE) and command.buttons & others == 0 and PlayerCommand.GRENADE != PlayerCommand.MINE, "GRENADE and MINE are their own bits and round-trip")

	# Counts by armour, and they're in the soldier's state.
	var counts := []
	for armour: int in [Armour.LIGHT, Armour.MEDIUM, Armour.HEAVY]:
		a.set_loadout(Loadout.make(armour, [Weapon.DISC]))
		counts.append([a.grenades, a.mines])
	checks.check(counts == [[3, 2], [4, 3], [5, 4]], "light, medium and heavy carry %s grenades and mines" % [counts])
	a.set_loadout(Loadout.make(Armour.MEDIUM, [Weapon.DISC]))
	place(a, Vector3.ZERO)
	await ticks(2)

	# Holding the button throws once; pressing again inside the cooldown does
	# nothing; after it, it throws again.
	input_a.command.pitch = 0.3
	input_a.command.buttons = PlayerCommand.GRENADE
	await ticks(40)
	var held_throws := 4 - a.grenades
	input_a.command.buttons = 0
	await ticks(1)
	checks.check(held_throws == 1, "holding the grenade button throws once (%d)" % held_throws)
	place(a, Vector3.ZERO)
	await press(input_a, PlayerCommand.GRENADE)
	await ticks(1)
	await press(input_a, PlayerCommand.GRENADE)
	var quick := 3 - a.grenades
	await ticks(int(Soldier.THROW_TIME * 60.0) + 1)
	checks.check(quick == 1 and a.grenades == 1, "a second press inside the cooldown waits for it, then throws (%d left)" % a.grenades)
	await ticks(200)
	game.projectiles.clear()

	# At none left nothing is thrown, and respawning fills them up.
	place(a, Vector3.ZERO)
	await press(input_a, PlayerCommand.GRENADE)
	await ticks(int(Soldier.THROW_TIME * 60.0) + 1)
	var before := game.projectiles.size()
	await press(input_a, PlayerCommand.GRENADE)
	checks.check(a.grenades == 0 and game.projectiles.size() == before, "with no grenades left nothing is thrown")
	await ticks(200)

	# A grenade then a mine pressed close together: both go, the mine when
	# the cooldown ends, and the waiting press is in the state.
	a.set_loadout(Loadout.make(Armour.MEDIUM, [Weapon.DISC]))
	place(a, Vector3.ZERO)
	await press(input_a, PlayerCommand.GRENADE)
	await press(input_a, PlayerCommand.MINE)
	var waiting: int = a.get_state().throw_pending
	var mines_then := a.mines
	await ticks(int(Soldier.THROW_TIME * 60.0) + 1)
	checks.check(waiting == Weapon.MINE and mines_then == 3 and a.grenades == 3 and a.mines == 2 and a.throw_pending == Soldier.NO_THROW, "a grenade then a mine pressed close together both happen (%d, %d)" % [a.grenades, a.mines])
	await ticks(200)
	game.projectiles.clear()
	game.mines.clear()

	# Thrown at 20 m/s plus half your velocity.
	var hand := Weapon.all[Weapon.HAND_GRENADE]
	a.set_loadout(Loadout.make(Armour.MEDIUM, [Weapon.DISC]))
	place(a, Vector3(0.0, 5.0, 0.0))
	var state := a.get_state()
	state.velocity = Vector3(12.0, 0.0, 0.0)
	state.grounded = false
	a.set_state(state)
	input_a.command.pitch = 0.0
	input_a.command.yaw = 0.0
	await press(input_a, PlayerCommand.GRENADE)
	var thrown := last_shot(a)
	var expect_x := a.velocity.x * hand.inherit
	var forward := -thrown.velocity.z
	checks.check(thrown != null and thrown.weapon == Weapon.HAND_GRENADE and absf(thrown.velocity.x - expect_x) < 0.01 and absf(forward - hand.speed) < 0.5, "a grenade leaves at %.1f m/s ahead plus %.1f of your %.1f m/s sideways" % [forward, thrown.velocity.x, a.velocity.x])
	game.projectiles.clear()
	await ticks(60)

	# It bounces off the ground and goes off at its fuse.
	place(a, Vector3.ZERO)
	await ticks(2)
	input_a.command.pitch = -0.2
	blasts.clear()
	await press(input_a, PlayerCommand.GRENADE)
	var grenade := last_shot(a)
	var bounced := 0
	var falling := true
	var went_off := -1
	for i in 200:
		await ticks(1)
		if not game.projectiles.has(grenade):
			went_off = i + 2
			break
		if falling and grenade.velocity.y > 0.0:
			bounced += 1
		falling = grenade.velocity.y <= 0.0
	var fuse_ticks := roundi(hand.fuse * 60.0)
	checks.check(bounced >= 1, "a hand grenade bounces (%d bounces)" % bounced)
	checks.check(absi(went_off - fuse_ticks) <= 2 and blasts == [Weapon.HAND_GRENADE], "and goes off at its %.1f s fuse (after %d ticks, blasts %s)" % [hand.fuse, went_off, blasts])

	# Its blast hurts an enemy close by, and a kill shows the hand grenade.
	place(a, Vector3.ZERO)
	place(b, Vector3(0.0, 0.0, -100.0))
	await ticks(2)
	a.set_loadout(Loadout.make(Armour.MEDIUM, [Weapon.DISC]))
	input_a.command.pitch = -0.6
	await press(input_a, PlayerCommand.GRENADE)
	grenade = last_shot(a)
	await ticks(20)
	place(a, Vector3(0.0, 0.0, 60.0))
	await ticks(10)
	place(b, grenade.position + Vector3(1.0, -grenade.position.y, 0.0))
	var b_state := b.get_state()
	b_state.health = 20.0
	b.set_state(b_state)
	kills.clear()
	await ticks(150)
	checks.check(kills.size() == 1 and kills[0] == [b.entity_id, a.entity_id, Weapon.HAND_GRENADE], "a hand grenade kill names the hand grenade %s" % [kills])
	await ticks(260)

	# Mines: thrown, they stick where they land and arm after 2 s.
	place(a, Vector3.ZERO)
	place(b, Vector3(0.0, 0.0, -100.0))
	place(c, Vector3(100.0, 0.0, 0.0))
	await ticks(2)
	input_a.command.pitch = -1.3
	await press(input_a, PlayerCommand.MINE)
	var mine_shot := last_shot(a)
	checks.check(mine_shot != null and mine_shot.weapon == Weapon.MINE and absf(mine_shot.velocity.length() - Weapon.all[Weapon.MINE].speed) < 0.6 and a.mines == 2, "a mine is thrown at %.1f m/s" % (mine_shot.velocity.length() if mine_shot != null else 0.0))
	var landed_after := -1
	for i in 60:
		await ticks(1)
		if not game.projectiles.has(mine_shot):
			landed_after = i
			break
	var mine: Mine = game.mines.back() if not game.mines.is_empty() else null
	checks.check(mine != null and mine.id == mine_shot.id and mine.owner_id == a.entity_id and mine.team == 0 and absf(mine.position.y) < 0.1 and not mine.armed(), "it lands on the ground after %d ticks and isn't armed yet" % landed_after)
	var spot := mine.position
	place(a, Vector3(0.0, 0.0, 30.0))
	# An enemy close by before it's armed doesn't set it off.
	place(b, spot + Vector3(1.5, 0.0, 0.0))
	await ticks(60)
	checks.check(game.mines.has(mine) and mine.position == spot, "an enemy 1.5 m away doesn't set it off before it's armed, and it stays put")
	place(b, Vector3(0.0, 0.0, -100.0))
	await ticks(70)
	checks.check(mine.armed(), "it's armed after %.0f s" % Match.MINE_ARM_TIME)
	# A teammate on it doesn't set it off.
	place(c, spot + Vector3(1.0, 0.0, 0.0))
	await ticks(20)
	checks.check(game.mines.has(mine), "a teammate next to it doesn't set it off")
	place(c, Vector3(100.0, 0.0, 0.0))
	# An enemy walking up sets it off within 2.5 m, for its splash.
	blasts.clear()
	place(b, spot + Vector3(6.0, 0.0, 0.0))
	input_b.command.yaw = PI * 0.5
	input_b.command.move = Vector2(0.0, 0.3)
	var gone_at := -1.0
	for i in 120:
		await ticks(1)
		if not game.mines.has(mine):
			gone_at = b.distance_to_body(spot)
			break
	input_b.command.move = Vector2.ZERO
	var mine_weapon := Weapon.all[Weapon.MINE]
	var hurt := b.tuning.health_max - b.health
	checks.check(gone_at >= 0.0 and gone_at <= Match.MINE_TRIGGER and blasts == [Weapon.MINE], "an enemy walking up sets it off at %.2f m" % gone_at)
	checks.check(absf(hurt - mine_weapon.splash_damage_at(gone_at)) < 8.0 and hurt > 40.0, "for %.1f damage" % hurt)
	await ticks(10)

	# At most three out: a fourth sets off the oldest.
	place(a, Vector3.ZERO)
	place(b, Vector3(0.0, 0.0, -100.0))
	a.set_loadout(Loadout.make(Armour.HEAVY, [Weapon.DISC]))
	place(a, Vector3.ZERO)
	var laid: Array[int] = []
	for k in 4:
		place(a, Vector3(k * 10.0, 0.0, 0.0))
		laid.append(await lay_mine())
	var out := mine_ids(a.entity_id)
	checks.check(out == laid.slice(1), "a fourth mine sets off the oldest (%s out of %s)" % [out, laid])

	# They stay when their owner dies and respawns.
	game.damage(a, 1000.0, b.entity_id, Weapon.DISC, b.global_position)
	await ticks(roundi(Match.RESPAWN_DELAY * 60.0) + 10)
	checks.check(not a.dead and mine_ids(a.entity_id) == laid.slice(1), "they stay when their owner dies and respawns")

	# A blast within 2 m sets one off, one further off doesn't.
	var target: Mine = game.mines[0]
	game.explode(target.position + Vector3(0.0, 0.5, 3.0), Weapon.DISC, b.entity_id)
	var after_far := game.mines.has(target)
	game.explode(target.position + Vector3(0.0, 0.5, 1.5), Weapon.DISC, b.entity_id)
	checks.check(after_far and not game.mines.has(target), "a blast 1.6 m away sets a mine off and one 3 m away doesn't")
	game.mines.clear()
	await ticks(2)

	# Mines round-trip through the match state.
	place(a, Vector3.ZERO)
	a.set_loadout(Loadout.make(Armour.MEDIUM, [Weapon.DISC]))
	place(a, Vector3.ZERO)
	await lay_mine()
	game.running = false
	var saved := game.get_state()
	game.set_state(saved)
	checks.check(saved.mines.size() == 1 and game.get_state() == saved, "mines go through get_state and set_state")
	game.running = true

	# A match with a grenade in the air and a mine down: save, play on, put
	# it back and play on again. Both runs end the same.
	place(a, Vector3(0.0, 0.0, 10.0))
	place(b, Vector3(0.0, 0.0, -20.0))
	# b walks onto the mine; the grenade goes the other way.
	input_b.command.yaw = PI
	input_a.command.yaw = PI
	input_a.command.pitch = 0.4
	await press(input_a, PlayerCommand.GRENADE)
	await ticks(10)
	game.running = false
	saved = game.get_state()
	checks.check(saved.projectiles.size() == 1 and saved.mines.size() == 1, "the saved state has a grenade in flight and a mine")
	input_b.command.move = Vector2(0.0, 1.0)
	var play := func() -> Dictionary:
		for i in 240:
			game.step(TICK)
		return game.get_state()
	var first: Dictionary = play.call()
	game.set_state(saved)
	var second: Dictionary = play.call()
	checks.check(first.mines.is_empty() and _same(first, second), "replaying from it ends the same (b health %.1f and %.1f, %d and %d mines)" % [first.entities[b.entity_id].health, second.entities[b.entity_id].health, first.mines.size(), second.mines.size()])
	checks.finish(self)


func _same(one: Dictionary, two: Dictionary) -> bool:
	if one.projectiles.size() != two.projectiles.size() or one.mines != two.mines or one.rng_state != two.rng_state or one.next_id != two.next_id:
		return false
	for id: int in one.entities:
		var x: Dictionary = one.entities[id]
		var y: Dictionary = two.entities[id]
		if x.position.distance_to(y.position) > 1e-4 or not is_equal_approx(x.health, y.health) or x.grenades != y.grenades or x.mines != y.mines:
			return false
	return true
