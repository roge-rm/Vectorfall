extends SceneTree

## Inventory stations: a command's loadout sets the wanted loadout, stepping
## onto your team's station puts it on with full ammo and health kept as a
## share, standing on it doesn't loop, stepping on again only restocks after
## the cooldown, a new wanted loadout on the pad goes on at once, enemies get
## nothing, a dead soldier's pick is what it respawns in, and stations
## round-trip through the match state.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/station_test.gd

const Armour := SoldierBody.Armour
const OFF_PAD := Vector3(6.0, 0.05, 0.0)

var checks := TestWorld.Checks.new()
var game: Match
var input := TestWorld.Scripted.new()
var soldier: Soldier
var enemy: Soldier
var station: InventoryStation
var used := 0
var entered := 0


func _initialize() -> void:
	TestWorld.flat_ground(root)
	game = Match.new(7)
	root.add_child(game)
	station = game.add_station(0, Vector3.ZERO)
	soldier = game.add_soldier(0, Transform3D(Basis.IDENTITY, OFF_PAD), input)
	enemy = game.add_soldier(1, Transform3D(Basis.IDENTITY, Vector3(-6.0, 0.05, 0.0)))
	game.station_used.connect(func(_station: int, id: int) -> void:
		if id == soldier.entity_id:
			used += 1)
	game.station_entered.connect(func(_station: int, id: int) -> void:
		if id == soldier.entity_id:
			entered += 1)
	_run.call_deferred()


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


func move_to(at: Vector3) -> void:
	soldier.global_position = at
	soldier.velocity = Vector3.ZERO


func _run() -> void:
	await ticks(10)
	checks.check(used == 0 and entered == 0, "nothing happens off the pad")
	var heavy := Loadout.make(Armour.HEAVY, [Weapon.DISC, Weapon.MORTAR, Weapon.CHAINGUN, Weapon.PLASMA], Pack.SHIELD)
	input.command.loadout = heavy.to_dict()
	await ticks(2)
	input.command.loadout = {}
	checks.check(soldier.next_loadout.equals(heavy) and soldier.loadout.armour == Armour.MEDIUM, "a command's loadout is wanted, not worn, off a station")

	soldier.health = soldier.tuning.health_max * 0.5
	soldier.ammo[0] = 1
	move_to(Vector3(0.3, 0.05, 0.2))
	await ticks(2)
	checks.check(entered == 1 and used == 1, "stepping on enters and uses the station once (%d, %d)" % [entered, used])
	checks.check(soldier.loadout.equals(heavy) and soldier.weapons.size() == 4, "the station puts the wanted loadout on")
	checks.check(soldier.ammo[0] == soldier.max_ammo(0) and soldier.grenades == Pack.scaled(heavy.grenades, heavy.pack), "with full ammo and grenades")
	checks.check(absf(soldier.health / soldier.tuning.health_max - 0.5) < 0.01, "health is kept as a share (%.2f)" % (soldier.health / soldier.tuning.health_max))
	checks.check(station.on == [soldier.entity_id], "the station knows who's on it")
	await ticks(90)
	checks.check(used == 1 and entered == 1, "standing on it doesn't use it again")

	soldier.grenades = 0
	move_to(OFF_PAD)
	await ticks(5)
	move_to(Vector3(0.0, 0.05, 0.0))
	await ticks(2)
	checks.check(entered == 2 and used == 1 and soldier.grenades == 0, "stepping straight back on doesn't restock")
	var light := Loadout.make(Armour.LIGHT, [Weapon.SNIPER, Weapon.DISC], Pack.JAMMER)
	input.command.loadout = light.to_dict()
	await ticks(2)
	input.command.loadout = {}
	checks.check(used == 2 and soldier.loadout.equals(light) and soldier.tuning.health_max == MovementTuning.for_armour(Armour.LIGHT).health_max, "a new loadout on the pad goes on at once")
	await ticks(30)
	checks.check(used == 2, "and only once")

	soldier.grenades = 0
	move_to(OFF_PAD)
	await ticks(int(InventoryStation.COOLDOWN * 60.0) + 5)
	move_to(Vector3(0.0, 0.05, -0.3))
	await ticks(2)
	checks.check(used == 3 and soldier.grenades == Pack.scaled(light.grenades, light.pack), "after the cooldown stepping on restocks")

	var enemy_loadout := enemy.loadout.duplicate()
	enemy.global_position = Vector3(0.2, 0.05, 0.0)
	enemy.next_loadout = heavy.duplicate()
	await ticks(3)
	checks.check(enemy.loadout.equals(enemy_loadout) and not station.on.has(enemy.entity_id), "an enemy on the pad gets nothing")
	enemy.global_position = Vector3(-6.0, 0.05, 0.0)

	# State: a fresh match takes the station whole.
	game.running = false
	var view := SubViewport.new()
	view.own_world_3d = true
	root.add_child(view)
	TestWorld.flat_ground(view)
	var other := Match.new(1)
	other.running = false
	view.add_child(other)
	var state := game.get_state()
	other.set_state(state)
	checks.check(other.stations.size() == 1 and other.get_state().stations == state.stations, "stations round-trip through the match state")
	game.running = true

	# Dead: the pick is what you respawn in.
	move_to(OFF_PAD)
	await ticks(2)
	game.damage(soldier, 1000.0, enemy.entity_id, Weapon.DISC, enemy.global_position)
	var medium := Loadout.make(Armour.MEDIUM, [Weapon.PLASMA, Weapon.DISC, Weapon.GRENADE_LAUNCHER], Pack.REPAIR)
	input.command.loadout = medium.to_dict()
	await ticks(2)
	input.command.loadout = {}
	checks.check(soldier.dead and soldier.loadout.equals(light), "a dead soldier keeps its loadout until it respawns")
	await ticks(int(Match.RESPAWN_DELAY * 60.0) + 5)
	checks.check(not soldier.dead and soldier.loadout.equals(medium), "and respawns in the one picked while dead")

	# Swapping loadouts on the pad during the cooldown carries ammo, grenades
	# and mines over, so swapping back and forth can't refill.
	move_to(OFF_PAD)
	await ticks(int(InventoryStation.COOLDOWN * 60.0) + 5)
	move_to(Vector3(0.0, 0.05, 0.0))
	await ticks(2)
	soldier.ammo[1] = 3
	soldier.grenades = 1
	soldier.mines = 0
	input.command.loadout = heavy.to_dict()
	await ticks(2)
	input.command.loadout = {}
	checks.check(soldier.loadout.equals(heavy) and soldier.ammo[0] == 3 and soldier.ammo[1] == 0 and soldier.grenades == 1 and soldier.mines == 0, "a swap during the cooldown carries ammo over and a new weapon starts empty (%s, %d, %d)" % [soldier.ammo, soldier.grenades, soldier.mines])
	input.command.loadout = medium.to_dict()
	await ticks(2)
	input.command.loadout = {}
	checks.check(soldier.loadout.equals(medium) and soldier.ammo[1] == 3 and soldier.grenades == 1 and soldier.mines == 0, "and swapping back doesn't refill (%s)" % [soldier.ammo])

	# Bad saved or sent values are dropped before fixed() trims the rest.
	var bad := Loadout.from_dict({ "armour": "heavy", "weapons": [Weapon.DISC, "x", 2.5, null], "pack": [1], "grenades": "9", "mines": 1.5 })
	var odd := Loadout.from_dict({ "weapons": "disc", "armour": 99 }).fixed()
	checks.check(bad.armour == Armour.MEDIUM and bad.weapons.size() == 1 and bad.weapons[0] == Weapon.DISC and bad.pack == Loadout.NO_PACK and bad.grenades == 0 and bad.mines == 0, "from_dict drops values of the wrong type")
	checks.check(odd.armour == Armour.MEDIUM and odd.weapons.size() == 1 and odd.weapons[0] == Weapon.DISC, "and fixed() makes the rest sane")
	checks.finish(self)
