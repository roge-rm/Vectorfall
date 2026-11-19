extends SceneTree

## Checks armour and loadouts: each armour's health, run speed, jet climb and
## push from a blast, loadouts trimmed to their armour, picking a carried
## weapon by index, a loadout kept through get_state() and set_state(), and
## next_loadout put on at respawn.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/armour_test.gd

const Armour := SoldierBody.Armour
const NAMES: Array[String] = ["light", "medium", "heavy"]

var checks := TestWorld.Checks.new()
var game: Match
var inputs: Array[TestWorld.Scripted] = []
## One soldier per armour, light, medium and heavy, 40 m apart.
var soldiers: Array[Soldier] = []
var standard: Soldier


func _initialize() -> void:
	TestWorld.flat_ground(root)
	game = Match.new(3)
	game.spawns[0] = [Transform3D(Basis.IDENTITY, Vector3(-200.0, 0.5, 0.0))]
	root.add_child(game)
	for armour in 3:
		var input := TestWorld.Scripted.new()
		inputs.append(input)
		var loadout := Loadout.make(armour, [Weapon.DISC, Weapon.CHAINGUN])
		soldiers.append(game.add_soldier(0, Transform3D(Basis.IDENTITY, Vector3(armour * 40.0, 0.2, 0.0)), input, loadout))
	standard = game.add_soldier(1, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, 100.0)))
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
	who.set_state(state)


func _run() -> void:
	await ticks(20)
	_check_loadouts()

	var medium := MovementTuning.new()
	var plain := standard.tuning
	checks.check(standard.loadout.armour == Armour.MEDIUM and standard.weapons == [Weapon.DISC, Weapon.CHAINGUN], "a soldier added with no loadout is medium with the disc launcher and chaingun")
	checks.check(plain.mass == medium.mass and plain.run_speed == medium.run_speed and plain.jet_up_accel == medium.jet_up_accel and plain.energy_max == medium.energy_max, "medium keeps the usual movement numbers")

	var healths := [75.0, 100.0, 160.0]
	var masses := [70.0, 90.0, 130.0]
	for k in 3:
		var s := soldiers[k]
		checks.check(s.tuning.health_max == healths[k] and s.health == healths[k], "%s has %.0f health" % [NAMES[k], healths[k]])
		checks.check(s.tuning.mass == masses[k] and s.body.armour == k, "%s weighs %.0f kg and looks %s" % [NAMES[k], masses[k], NAMES[k]])

	# Running flat out for three seconds.
	for input in inputs:
		input.command.move = Vector2(0.0, 1.0)
	await ticks(180)
	for k in 3:
		var s := soldiers[k]
		checks.check(absf(s.horizontal_speed() - s.tuning.run_speed) < 0.05, "%s runs at %.1f m/s (%.2f)" % [NAMES[k], s.tuning.run_speed, s.horizontal_speed()])
	var speeds := soldiers.map(func(s: Soldier) -> float: return s.horizontal_speed())
	checks.check(speeds[0] > speeds[1] and speeds[1] > speeds[2], "light runs fastest and heavy slowest")

	# Jetting straight up for half a second from standing.
	for k in 3:
		inputs[k].command.move = Vector2.ZERO
		place(soldiers[k], Vector3(k * 40.0, 0.0, 0.0))
	await ticks(10)
	for input in inputs:
		input.command.buttons = PlayerCommand.JET
	await ticks(30)
	var heights: Array[float] = []
	for k in 3:
		var s := soldiers[k]
		var t := s.tuning
		var climb := t.jet_up_accel - t.gravity
		heights.append(s.global_position.y)
		checks.check(absf(s.velocity.y - minf(climb * 0.5, t.jet_max_rise)) < 0.5, "%s climbs at %.0f m/s² (%.2f m/s after half a second)" % [NAMES[k], climb, s.velocity.y])
	checks.check(heights[0] > heights[1] and heights[1] > heights[2], "light climbs highest and heavy lowest (%.2f, %.2f, %.2f m)" % heights)
	for input in inputs:
		input.command.buttons = 0
	await ticks(120)

	# The same blast 3 m from each one's feet.
	var disc := Weapon.all[Weapon.DISC]
	for k in 3:
		place(soldiers[k], Vector3(k * 40.0, 0.0, 0.0))
	await ticks(2)
	var kicks: Array[float] = []
	for k in 3:
		var s := soldiers[k]
		var before := s.velocity
		var at := s.global_position + Vector3(3.0, 0.3, 0.0)
		var expected := disc.splash_impulse_at(s.distance_to_body(at)) / s.tuning.mass
		game.explode(at, Weapon.DISC, standard.entity_id)
		var kick := (s.velocity - before).length()
		kicks.append(kick)
		checks.check(absf(kick - expected) < 0.01, "%s is pushed %.1f m/s by a blast" % [NAMES[k], kick])
	checks.check(kicks[0] > kicks[1] and kicks[1] > kicks[2], "light is pushed most and heavy least")
	await ticks(120)

	# A command picks by index in the carried list.
	var light := soldiers[0]
	light.set_loadout(Loadout.make(Armour.LIGHT, [Weapon.CHAINGUN, Weapon.DISC]))
	checks.check(light.weapons == [Weapon.CHAINGUN, Weapon.DISC] and light.ammo == [Weapon.all[Weapon.CHAINGUN].ammo, disc.ammo], "a new loadout carries its weapons with full ammo")
	inputs[0].command.weapon = 1
	await ticks(1)
	inputs[0].command.weapon = -1
	checks.check(light.weapon == 1 and light.weapon_slot() == Weapon.DISC, "weapon 1 is the second carried weapon, the disc launcher")
	await ticks(30)
	inputs[0].command.buttons = PlayerCommand.FIRE
	await ticks(1)
	inputs[0].command.buttons = 0
	checks.check(light.ammo_for(Weapon.DISC) == disc.ammo - 1 and light.ammo[1] == disc.ammo - 1, "firing uses the carried disc launcher's ammo")
	inputs[0].command.buttons = PlayerCommand.NEXT_WEAPON
	await ticks(1)
	inputs[0].command.buttons = 0
	checks.check(light.weapon == 0 and light.weapon_slot() == Weapon.CHAINGUN, "next weapon goes round the two carried")

	# State with a loadout and a different next one.
	var heavy := Loadout.make(Armour.HEAVY, [Weapon.DISC])
	light.next_loadout = heavy.duplicate()
	game.running = false
	var saved := light.get_state()
	light.set_loadout(Loadout.standard())
	light.set_state(saved)
	game.running = true
	checks.check(light.loadout.armour == Armour.LIGHT and light.weapons == [Weapon.CHAINGUN, Weapon.DISC] and light.tuning.mass == 70.0 and light.body.armour == Armour.LIGHT, "set_state puts back the loadout, its tuning and look")
	checks.check(light.next_loadout.equals(heavy) and light.get_state() == saved, "and the next loadout, giving the same state back")

	# Respawn puts on the next loadout.
	game.damage(light, 500.0, standard.entity_id, Weapon.DISC, standard.global_position)
	checks.check(light.dead and light.loadout.armour == Armour.LIGHT, "dead, still in light armour")
	await ticks(roundi(Match.RESPAWN_DELAY * 60.0) + 3)
	checks.check(not light.dead and light.loadout.equals(heavy) and light.weapons == [Weapon.DISC], "respawns in the next loadout")
	checks.check(light.tuning.mass == 130.0 and light.health == 160.0 and light.energy == light.tuning.energy_max and light.body.armour == Armour.HEAVY, "with heavy tuning, full heavy health and energy and the heavy look")
	checks.check(light.weapon == 0 and light.ammo == [disc.ammo], "holding its one weapon with full ammo")
	checks.finish(self)


func _check_loadouts() -> void:
	var light := Loadout.make(Armour.LIGHT, [Weapon.DISC, Weapon.DISC, Weapon.CHAINGUN, 99])
	checks.check(light.weapons == [Weapon.DISC, Weapon.CHAINGUN], "repeats and unknown weapons are dropped")
	var too_many := Loadout.new()
	too_many.armour = Armour.LIGHT
	too_many.weapons = [Weapon.CHAINGUN, Weapon.DISC]
	too_many.grenades = 9
	too_many.mines = -1
	checks.check(not too_many.valid(), "a light loadout with 9 grenades isn't valid")
	var fixed := too_many.fixed()
	checks.check(fixed.valid() and fixed.grenades == 3 and fixed.mines == 0 and fixed.weapons == [Weapon.CHAINGUN, Weapon.DISC], "fixed() holds the counts to light's limits and keeps the weapon order")
	# A weapon light armour can't carry is dropped.
	var chaingun := Weapon.all[Weapon.CHAINGUN]
	var kept := chaingun.armours.duplicate()
	chaingun.armours = [Armour.MEDIUM, Armour.HEAVY]
	var trimmed := Loadout.make(Armour.LIGHT, [Weapon.CHAINGUN, Weapon.DISC])
	var heavy := Loadout.make(Armour.HEAVY, [Weapon.CHAINGUN, Weapon.DISC])
	chaingun.armours = kept
	checks.check(trimmed.weapons == [Weapon.DISC] and heavy.weapons == [Weapon.CHAINGUN, Weapon.DISC], "a weapon the armour can't carry is dropped")
	var counts: Array[int] = []
	for armour in 3:
		counts.append(Loadout.SLOTS[armour])
	checks.check(counts == [2, 3, 4], "light carries 2 weapons, medium 3 and heavy 4")
	var odd := Loadout.new()
	odd.armour = 7
	odd.weapons = []
	var odd_fixed := odd.fixed()
	checks.check(odd_fixed.armour == Armour.MEDIUM and odd_fixed.weapons == [Weapon.DISC], "an unknown armour becomes medium and an empty one gets the disc launcher")
	var back := Loadout.from_dict(fixed.to_dict())
	checks.check(back.equals(fixed), "a loadout comes back the same from to_dict and from_dict")
