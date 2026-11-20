extends SceneTree

## Checks pack data: their data and a loadout dropping an unknown one,
## the ammo pack's bigger loads at set_loadout and respawn, the energy pack's
## quicker refill, the shield toggling with each press, draining, taking
## damage from energy and going off at no energy, the jammer toggling and
## draining, repair on yourself and on a hurt teammate in front of you within
## reach and not one behind or too far, its energy use, pack state through
## get_state and set_state, and a replay that ends the same.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/pack_test.gd

const TICK := 1.0 / 60.0
const Armour := SoldierBody.Armour

var checks := TestWorld.Checks.new()
var game: Match
var input_a := TestWorld.Scripted.new()
var input_b := TestWorld.Scripted.new()
var input_c := TestWorld.Scripted.new()
## Pack wearer on team 0, an enemy on team 1 and a teammate of the wearer.
var a: Soldier
var b: Soldier
var c: Soldier
var shield_hits: Array[float] = []
var switches: Array[bool] = []


func _initialize() -> void:
	TestWorld.flat_ground(root)
	game = Match.new(9)
	game.spawns[0] = [Transform3D(Basis.IDENTITY, Vector3(-200.0, 0.5, 0.0))]
	game.spawns[1] = [Transform3D(Basis.IDENTITY, Vector3(200.0, 0.5, 0.0))]
	root.add_child(game)
	game.running = false
	a = game.add_soldier(0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, 0.0)), input_a)
	b = game.add_soldier(1, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, -100.0)), input_b)
	c = game.add_soldier(0, Transform3D(Basis.IDENTITY, Vector3(100.0, 0.2, 0.0)), input_c)
	game.shield_hit.connect(func(_victim: int, amount: float, _from: Vector3) -> void: shield_hits.append(amount))
	game.pack_switched.connect(func(id: int, on: bool) -> void:
		if id == a.entity_id:
			switches.append(on))
	_run.call_deferred()


func steps(n: int) -> void:
	for i in n:
		game.step(TICK)


## Puts a soldier standing still at a point facing yaw, with this health and
## energy, and the refill delay just started so energy doesn't refill for a
## while.
func place(who: Soldier, at: Vector3, health: float, energy: float, yaw := 0.0) -> void:
	var state := who.get_state()
	state.position = at
	state.velocity = Vector3.ZERO
	state.yaw = yaw
	state.pitch = 0.0
	state.grounded = true
	state.floor_normal = Vector3.UP
	state.health = health
	state.energy = energy
	state.since_jet = 0.0
	who.set_state(state)
	var source := input_a if who == a else input_b if who == b else input_c
	source.command.yaw = yaw
	source.command.pitch = 0.0


## Presses use for one tick and lets go for one.
func press_use() -> void:
	input_a.command.buttons |= PlayerCommand.USE
	steps(1)
	input_a.command.buttons &= ~PlayerCommand.USE
	steps(1)


func wear(pack: int) -> void:
	a.set_loadout(Loadout.make(Armour.MEDIUM, [Weapon.DISC, Weapon.CHAINGUN], pack))


func _run() -> void:
	# Data.
	checks.check(Pack.all.size() == 8 and Pack.all[Pack.JAMMER].slot == Pack.JAMMER and Pack.all[Pack.STATION].slot == Pack.STATION and Pack.get_pack(Loadout.NO_PACK) == null, "eight packs, by slot, and none for NO_PACK")
	var odd := Loadout.make(Armour.LIGHT, [Weapon.DISC], 9)
	var kept := Loadout.make(Armour.LIGHT, [Weapon.DISC], Pack.SHIELD)
	checks.check(odd.pack == Loadout.NO_PACK and kept.pack == Pack.SHIELD, "a loadout drops an unknown pack and keeps a real one")

	# Ammo pack: half as much again of everything.
	wear(Pack.AMMO)
	checks.check(a.ammo == [23, 450] and a.grenades == 6 and a.mines == 5, "the ammo pack gives 23 discs, 450 rounds, 6 grenades and 5 mines (%s, %d, %d)" % [a.ammo, a.grenades, a.mines])
	a.ammo[0] = 1
	a.grenades = 0
	a.die()
	a.revive(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, 0.0)))
	checks.check(a.ammo == [23, 450] and a.grenades == 6 and a.mines == 5 and a.max_ammo(0) == 23, "and the same again on respawn")
	wear(Loadout.NO_PACK)
	checks.check(a.ammo == [15, 300] and a.grenades == 4 and a.mines == 3, "without it, the usual 15, 300, 4 and 3")

	# Energy pack: refill delay halved and 40% quicker.
	wear(Pack.ENERGY)
	checks.check(is_equal_approx(a.refill_delay(), 0.4) and is_equal_approx(a.refill_rate(), 35.0), "the energy pack halves the refill delay and refills 40% quicker")
	place(a, Vector3(0.0, 0.0, 0.0), 100.0, 0.0)
	place(c, Vector3(10.0, 0.0, 0.0), 100.0, 0.0)
	steps(60)
	checks.check(absf(a.energy - 21.0) < 1.0 and absf(c.energy - 5.0) < 1.0, "after a second from empty: %.1f energy with it, %.1f without" % [a.energy, c.energy])

	# Shield: on and off with each press, held or not.
	wear(Pack.SHIELD)
	place(a, Vector3(0.0, 0.0, 0.0), 100.0, 100.0)
	switches.clear()
	input_a.command.buttons |= PlayerCommand.USE
	steps(20)
	var on_held := a.shielded()
	input_a.command.buttons &= ~PlayerCommand.USE
	steps(1)
	press_use()
	var off_after := not a.shielded()
	press_use()
	checks.check(on_held and off_after and a.shielded() and switches == [true, false, true], "the shield goes on with a press, stays on while held, and toggles each press")
	place(a, Vector3(0.0, 0.0, 0.0), 100.0, 50.0)
	steps(30)
	checks.check(absf(a.energy - 48.0) < 0.05, "it drains 4 energy a second (%.2f left of 50 after 0.5 s)" % a.energy)
	place(a, Vector3(0.0, 0.0, 0.0), 100.0, 50.0)
	game.damage(a, 10.0, b.entity_id, Weapon.DISC, b.global_position)
	checks.check(is_equal_approx(a.health, 100.0) and is_equal_approx(a.energy, 30.0) and shield_hits == [10.0], "10 damage takes 20 energy and no health")
	game.damage(a, 25.0, b.entity_id, Weapon.DISC, b.global_position)
	checks.check(is_equal_approx(a.health, 90.0) and a.energy == 0.0 and not a.shielded() and shield_hits.size() == 2 and is_equal_approx(shield_hits[1], 15.0), "25 more with 30 energy: 15 stopped, 10 to health, and the shield goes off (%.1f health)" % a.health)
	game.damage(a, 10.0, b.entity_id, Weapon.DISC, b.global_position)
	checks.check(is_equal_approx(a.health, 80.0), "off, damage takes health")
	place(a, Vector3(0.0, 0.0, 0.0), 100.0, 100.0)
	press_use()
	place(a, Vector3(0.0, 0.0, 0.0), 100.0, 0.05)
	steps(1)
	checks.check(not a.shielded(), "it goes off by itself at no energy")
	press_use()
	checks.check(not a.shielded(), "and won't go on with none")

	# Jammer: toggled, drains 5 a second, off at no energy.
	wear(Pack.JAMMER)
	place(a, Vector3(0.0, 0.0, 0.0), 100.0, 50.0)
	press_use()
	place(a, Vector3(0.0, 0.0, 0.0), 100.0, 50.0)
	steps(30)
	var drained := 50.0 - a.energy
	var jammed := a.jamming() and not a.shielded()
	place(a, Vector3(0.0, 0.0, 0.0), 100.0, 0.05)
	steps(1)
	checks.check(jammed and absf(drained - 2.5) < 0.05 and not a.jamming(), "the jammer goes on with a press, drains 5 a second (%.2f in 0.5 s) and goes off at no energy" % drained)

	# Energy and ammo packs have nothing to switch.
	wear(Pack.ENERGY)
	press_use()
	checks.check(not a.pack_on, "use does nothing with an always-on pack")

	# Repair: yourself at 10 a second for 10 energy a second.
	wear(Pack.REPAIR)
	place(a, Vector3(0.0, 0.0, 0.0), 50.0, 100.0)
	place(c, Vector3(30.0, 0.0, 0.0), 100.0, 100.0)
	input_a.command.buttons |= PlayerCommand.USE
	steps(30)
	checks.check(absf(a.health - 55.0) < 0.05 and absf(a.energy - 95.0) < 0.05 and a.repair_target == a.entity_id, "holding use repairs yourself 10 a second for 10 energy (%.2f health, %.2f energy)" % [a.health, a.energy])
	input_a.command.buttons &= ~PlayerCommand.USE
	steps(1)
	checks.check(a.repair_target == 0 and not a.pack_on, "and stops when you let go")
	place(a, Vector3(0.0, 0.0, 0.0), 100.0, 100.0)
	input_a.command.buttons |= PlayerCommand.USE
	steps(10)
	checks.check(a.repair_target == 0 and is_equal_approx(a.energy, 100.0), "at full health with no one hurt it takes no energy")
	# A hurt teammate 2.5 m in front, the way you face (yaw 0 looks along -z).
	place(a, Vector3(0.0, 0.0, 0.0), 60.0, 100.0)
	place(c, Vector3(0.0, 0.0, -2.5), 50.0, 100.0)
	steps(30)
	checks.check(absf(c.health - 57.5) < 0.05 and is_equal_approx(a.health, 60.0) and a.repair_target == c.entity_id, "a hurt teammate in front is repaired first, 15 a second (%.2f)" % c.health)
	place(c, Vector3(0.0, 0.0, -2.5), c.tuning.health_max - 0.1, 100.0)
	steps(5)
	checks.check(is_equal_approx(c.health, c.tuning.health_max) and a.repair_target == a.entity_id, "up to full health, then yourself")
	place(a, Vector3(0.0, 0.0, 0.0), 100.0, 100.0)
	place(c, Vector3(0.0, 0.0, 2.5), 50.0, 100.0)
	steps(10)
	var behind := is_equal_approx(c.health, 50.0)
	place(c, Vector3(0.0, 0.0, -6.0), 50.0, 100.0)
	steps(10)
	var far := is_equal_approx(c.health, 50.0)
	place(b, Vector3(0.0, 0.0, -2.5), 50.0, 100.0)
	steps(10)
	var enemy := is_equal_approx(b.health, 50.0)
	checks.check(behind and far and enemy and a.repair_target == 0, "not a teammate behind, one 6 m away or an enemy in front")
	place(a, Vector3(0.0, 0.0, 0.0), 50.0, 0.0)
	steps(10)
	checks.check(is_equal_approx(a.health, 50.0) and a.repair_target == 0, "and nothing with no energy")
	place(b, Vector3(0.0, 0.0, -100.0), 100.0, 100.0)

	# Pack state round trip, with a teammate being repaired.
	place(a, Vector3(0.0, 0.0, 0.0), 100.0, 100.0)
	place(c, Vector3(0.0, 0.0, -2.5), 40.0, 100.0)
	steps(3)
	var saved := game.get_state()
	var mine: Dictionary = saved.entities[a.entity_id]
	game.set_state(saved)
	checks.check(mine.pack_on and mine.use_held and mine.repair_target == c.entity_id and game.get_state() == saved, "pack state goes through get_state and set_state")

	# Replay: a shield wearer fighting a repair, from a saved state.
	var shielded := Loadout.make(Armour.HEAVY, [Weapon.DISC, Weapon.CHAINGUN], Pack.SHIELD)
	b.set_loadout(shielded)
	place(b, Vector3(0.0, 0.0, -30.0), 100.0, 100.0, PI)
	input_b.command.buttons = PlayerCommand.USE
	steps(1)
	input_b.command.buttons = PlayerCommand.FIRE
	saved = game.get_state()
	var play := func() -> Dictionary:
		for i in 240:
			game.step(TICK)
		return game.get_state()
	var first: Dictionary = play.call()
	game.set_state(saved)
	var second: Dictionary = play.call()
	var x: Dictionary = first.entities[c.entity_id]
	var y: Dictionary = second.entities[c.entity_id]
	var ax: Dictionary = first.entities[a.entity_id]
	var ay: Dictionary = second.entities[a.entity_id]
	checks.check(is_equal_approx(x.health, y.health) and is_equal_approx(ax.energy, ay.energy) and ax.repair_target == ay.repair_target and first.entities[b.entity_id].pack_on == second.entities[b.entity_id].pack_on, "replaying from it ends the same (teammate %.1f and %.1f health)" % [x.health, y.health])
	checks.finish(self)
