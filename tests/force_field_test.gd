extends SceneTree

## The generator room and its force fields on the test map: an enemy soldier
## lands on the field and a teammate drops through it, a dropped enemy flag
## stays on it and the team's own falls through, an enemy disc, its blast
## and a thrown mine pass through it, with power off the enemy falls through, the
## fields round-trip through the match state, the map's surface and ground
## match the room, and on both maps routes reach each generator from the
## flag stands, with the enemy's way in shut while the field is on.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/force_field_test.gd

var checks := TestWorld.Checks.new()
var map: TestMap
var game: Match
## Team 0, the enemy at team 1's base, and team 1's own soldier.
var enemy: Soldier
var mate: Soldier
var generator: BaseAsset
var fields: Array[ForceField] = []


func _initialize() -> void:
	map = TestMap.new()
	root.add_child(map)
	game = Match.new(3)
	root.add_child(game)
	generator = game.add_asset(1, BaseAsset.Kind.GENERATOR, map.generator_point(1), map.asset_facing(1))
	for at in map.field_points(1):
		fields.append(game.add_field(1, at, GameMap.FIELD_SIZE))
	enemy = game.add_soldier(0, Transform3D(Basis.IDENTITY, Vector3(0.0, 40.0, 60.0)))
	mate = game.add_soldier(1, Transform3D(Basis.IDENTITY, Vector3(0.0, 40.0, -60.0)))
	_run.call_deferred()


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


## Puts a soldier at a point, still and in the air.
func place(who: Soldier, at: Vector3) -> void:
	var state := who.get_state()
	state.position = at
	state.velocity = Vector3.ZERO
	state.grounded = false
	state.energy = who.tuning.energy_max
	state.cooldown = 0.0
	who.set_state(state)


func _run() -> void:
	await ticks(5)
	var deck := map.deck_height()
	var floor_y := map.room_floor()
	var over := [fields[0].position, fields[1].position]
	checks.check(fields[0].on and fields[1].on and fields[0].collision_layer == Match.field_layer(1), "team 1's fields start on, on its field layer")
	checks.check(enemy.collision_mask & Match.field_layer(1) != 0 and enemy.collision_mask & Match.field_layer(0) == 0, "a team 0 soldier collides with team 1's fields and not its own")
	checks.check(mate.collision_mask & Match.field_layer(1) == 0, "a team 1 soldier passes its own fields")

	# The map: the opening is the room's floor, the deck round it the deck,
	# and there's no ground in the room.
	var hole: Vector3 = over[1]
	checks.check(is_equal_approx(map.surface_at(hole.x, hole.z), floor_y) and is_equal_approx(map.surface_at(hole.x, hole.z + 2.5), deck), "surface_at gives the room floor in an opening and the deck beside it")
	var inside := map.generator_point(1) + Vector3(2.0, 1.5, 0.0)
	var down := game.world_ray(inside, inside + Vector3.DOWN * 5.0, Match.WORLD_LAYER)
	checks.check(not down.is_empty() and absf(down.position.y - floor_y) < 0.05, "in the room the ground below is the room's floor (%.2f, floor %.2f)" % [down.get("position", Vector3.ZERO).y, floor_y])

	# Flags: a dropped team 0 flag lands on team 1's field and a team 1 flag
	# falls through it. Then they're taken out.
	var their_flag := game.add_flag(0, Vector3(0.0, 80.0, 100.0), Vector3(0.0, 80.0, 100.0))
	var own_flag := game.add_flag(1, Vector3(0.0, 80.0, -100.0), Vector3(0.0, 80.0, -100.0))
	checks.check(their_flag.collision_mask & Match.field_layer(1) != 0 and own_flag.collision_mask & Match.field_layer(1) == 0, "a flag collides with the other team's fields and not its own")
	their_flag.global_position = hole + Vector3.UP * 3.0
	their_flag.drop(Vector3.ZERO, Vector3(0.5, 0.0, 0.3), 60.0)
	own_flag.global_position = over[0] + Vector3.UP * 3.0
	own_flag.drop(Vector3.ZERO, Vector3(0.5, 0.0, 0.3), 60.0)
	await ticks(120)
	checks.check(their_flag.global_position.y > deck - 0.3, "an enemy flag dropped on the field stays on it (y %.2f, deck %.2f)" % [their_flag.global_position.y, deck])
	checks.check(own_flag.global_position.y < deck - 1.0, "the field's own team's flag falls through (y %.2f)" % own_flag.global_position.y)
	for team in 2:
		game.flags[team].free()
		game.flags.erase(team)
		game.stands.erase(team)

	# Drops: the enemy lands on the field, the teammate goes through.
	place(enemy, hole + Vector3.UP * 1.5)
	place(mate, over[0] + Vector3.UP * 1.5)
	await ticks(90)
	checks.check(absf(enemy.global_position.y - deck) < 0.2, "an enemy stands on the field (y %.2f, deck %.2f)" % [enemy.global_position.y, deck])
	checks.check(absf(mate.global_position.y - floor_y) < 0.2, "a teammate drops through to the room's floor (y %.2f, floor %.2f)" % [mate.global_position.y, floor_y])

	# Shots: a real disc from the enemy on the field straight down at the
	# teammate under it goes through, and so does a blast on top of it.
	place(mate, Vector3(hole.x + 0.5, floor_y + 0.05, hole.z))
	place(enemy, hole + Vector3(0.0, 0.6, 0.0))
	await ticks(30)
	var health := mate.health
	enemy.pitch = -PI * 0.5
	enemy.weapon = enemy.weapons.find(Weapon.DISC) if enemy.weapons.has(Weapon.DISC) else 0
	game.fire(enemy)
	await ticks(40)
	checks.check(mate.health < health, "an enemy disc goes through the field to the teammate below (health %.1f to %.1f)" % [health, mate.health])
	mate.health = health
	game.explode(hole + Vector3.UP * 1.1, Weapon.DISC, enemy.entity_id)
	checks.check(mate.health < health, "and so does a blast on top of it (health %.1f)" % mate.health)
	mate.health = health
	# A mine thrown straight down from the field lands on the room's floor.
	place(mate, Vector3(hole.x + 6.0, floor_y + 0.05, hole.z))
	place(enemy, hole + Vector3(0.0, 0.6, 0.0))
	await ticks(30)
	enemy.pitch = -PI * 0.5
	var before := game.mines.size()
	game.throw(enemy, Weapon.MINE)
	await ticks(90)
	var landed: Mine = game.mines[game.mines.size() - 1] if game.mines.size() > before else null
	checks.check(landed != null and absf(landed.position.y - floor_y) < 0.3, "a mine thrown down goes through the field to the floor (y %.2f, floor %.2f, thrower y %.2f)" % [landed.position.y if landed != null else 0.0, floor_y, enemy.global_position.y])
	game.mines.clear()
	mate.health = health

	# State: saved with the fields on, then put back after turning one off.
	game.running = false
	var saved := game.get_state()
	checks.check(saved.fields.size() == 2 and saved.fields[fields[0].entity_id].on, "the fields are in the match state")
	fields[0].set_on(false)
	game.set_state(saved)
	checks.check(fields[0].on and fields[0].collision_layer == Match.field_layer(1) and game.get_state() == saved, "set_state puts a field back on")
	var copy := Match.new(3)
	root.add_child(copy)
	copy.set_state(saved)
	var copied: ForceField = copy.fields.get(fields[1].entity_id)
	checks.check(copied != null and copied.team == 1 and copied.on and copied.position.is_equal_approx(fields[1].position), "set_state makes missing fields")
	copy.free()
	game.running = true

	# Power off: the fields go off and the enemy falls into the room.
	place(enemy, hole + Vector3.UP * 1.5)
	await ticks(60)
	checks.check(absf(enemy.global_position.y - deck) < 0.2, "the enemy is on the field again")
	game.damage_asset(generator, 1000.0, enemy.entity_id, 0, Vector3.ZERO)
	await ticks(90)
	checks.check(not fields[0].on and not fields[1].on and fields[1].collision_layer == 0, "with the generator down the fields are off")
	checks.check(absf(enemy.global_position.y - floor_y) < 0.2, "and the enemy drops into the room (y %.2f)" % enemy.global_position.y)
	game.repair_asset(generator, 1000.0, mate.entity_id)
	await ticks(2)
	checks.check(fields[0].on and fields[1].on, "repaired, the fields are on again")

	# A dropped enemy flag asleep on a field falls when the power goes off.
	place(enemy, Vector3(0.0, 60.0, 80.0))
	var sleeper := game.add_flag(0, Vector3(0.0, 80.0, 100.0), Vector3(0.0, 80.0, 100.0))
	sleeper.global_position = hole + Vector3.UP * 1.0
	sleeper.drop(Vector3.ZERO, Vector3.ZERO, 600.0)
	await ticks(300)
	checks.check(sleeper.sleeping and sleeper.global_position.y > deck - 0.3, "a dropped flag sleeps on the field (sleeping %s, y %.2f)" % [sleeper.sleeping, sleeper.global_position.y])
	game.damage_asset(generator, 1000.0, enemy.entity_id, 0, Vector3.ZERO)
	await ticks(60)
	checks.check(sleeper.global_position.y < deck - 1.0, "and falls through when the field goes off (y %.2f)" % sleeper.global_position.y)

	_check_routes(map, "the test map")
	game.free()
	map.free()
	var fold := OchreFold.new()
	root.add_child(fold)
	_check_routes(fold, "Ochre Fold")
	var under := fold.generator_point(0) + Vector3(2.0, 0.0, 3.0)
	checks.check(fold.terrain.height_at(under.x, under.z) < fold.room_floor() - 1.0 and fold.terrain.height_at(fold.base_x(0), 20.0) == OchreFold.BASE_GROUND, "Ochre Fold's ground is under the room's floor in the room and as it was beside the base")
	fold.free()
	checks.finish(self)


## Routes from each flag stand to each generator: our own always, the
## enemy's only with its field off.
func _check_routes(on: GameMap, title: String) -> void:
	var graph := on.route_graph
	var planner := RoutePlanner.new()
	var good := true
	var shut_out := true
	for team in 2:
		var stand: int = graph.interest_points(RouteGraph.FLAG_STAND, team)[0]
		var at: Array[int] = graph.interest_points(RouteGraph.GENERATOR, team)
		good = good and at.size() == 1
		if at.size() != 1:
			continue
		var goal := at[0]
		good = good and graph.points[goal].distance_to(on.generator_point(team)) < 4.0 and graph.room_of(goal) == team
		var enemy_stand: int = graph.interest_points(RouteGraph.FLAG_STAND, 1 - team)[0]
		var own := planner.plan(graph, stand, goal, 0.0, 100.0, {}, Vector2.ZERO, 1 << (1 - team))
		var open := planner.plan(graph, enemy_stand, goal, 0.0, 100.0)
		var shut := planner.plan(graph, enemy_stand, goal, 0.0, 100.0, {}, Vector2.ZERO, 1 << team)
		good = good and own.size() > 1 and own[-1] == goal and open.size() > 1 and open[-1] == goal
		var through_field := false
		for k in open.size() - 1:
			through_field = through_field or graph.link_between(open[k], open[k + 1]).field == team
		good = good and through_field
		shut_out = shut_out and shut.is_empty()
		var back := planner.plan(graph, goal, enemy_stand, 0.0, 100.0, {}, Vector2.ZERO, 1 << (1 - team))
		good = good and back.size() > 1
	checks.check(good, "on %s routes reach each generator from both flag stands through a field link, and back out" % title)
	checks.check(shut_out, "on %s the enemy's route in is shut while the field is on" % title)
