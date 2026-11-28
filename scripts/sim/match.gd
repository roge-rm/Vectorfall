class_name Match
extends Node3D

## Owns the match state. Entities live under it with stable integer ids and
## only change in step(), once per physics tick, from their commands. The HUD
## and camera only read it, and hear about hits and kills from its signals.

## Physics layers. The world is on 1, living soldiers on 2 and base assets
## on 3 (bit 4). Dead soldiers leave layer 2, so shots and other soldiers pass
## through them. Sight lines only check the world, so assets don't block them.
## Team 0's force fields are on layer 4 (bit 8) and team 1's on 5 (bit 16), see
## field_layer(): soldiers and dropped flags collide with the other team's.
## Shots, blasts, mines and line checks pass through every field.
const WORLD_LAYER := 1
const SOLDIER_LAYER := 2
const ASSET_LAYER := 4
const FIELD_LAYER := 8
# Shots can hit a deployed station pad. Soldiers can walk through its rim.
const PAD_LAYER := 32
const DEPLOY_DISTANCE := 3.0
const DEPLOY_SPACING := 3.5
const DEPLOY_SPEED := 8.0

## Seconds from death to respawning.
const RESPAWN_DELAY := 4.0
## Mines: most out per soldier, seconds to arm, how close an enemy sets one
## off and how close a blast sets one off, in metres.
const MINE_LIMIT := 3
const MINE_ARM_TIME := 2.0
const MINE_TRIGGER := 2.5
const MINE_SPLASH_TRIGGER := 2.0
## Half angle in radians around where you look that a repair pack reaches.
const REPAIR_CONE := 0.9

signal fired(soldier_id: int, weapon: int)
## A soldier took damage. from is where it came from: the blast or the shooter.
signal damaged(victim_id: int, attacker_id: int, amount: float, from: Vector3)
## A soldier's weapon hurt an enemy, for stats.
signal hit(attacker_id: int, victim_id: int, weapon: int)
## A slow projectile struck an enemy who was already airborne.
signal air_hit(attacker_id: int, victim_id: int)
signal killed(victim_id: int, killer_id: int, weapon: int)
## An enemy killed a carrier and made them drop the flag.
signal carrier_stopped(carrier_id: int, killer_id: int)
## A projectile hit something or blew up. normal is the surface's.
signal impacted(weapon: int, position: Vector3, normal: Vector3)
signal respawned(soldier_id: int)
## A thrown mine stuck where it landed, and later armed.
signal mine_placed(mine_id: int, at: Vector3)
signal mine_armed(mine_id: int, at: Vector3)
## A soldier's pack went on or off: a shield or jammer switched, or a repair
## pack starting or stopping.
signal pack_switched(soldier_id: int, on: bool)
signal deploy_result(soldier_id: int, text: String)
## A shield pack stopped some damage, taken from energy instead.
signal shield_hit(victim_id: int, amount: float, from: Vector3)
## Flag events. team is the flag's team, and soldier_id who took, dropped or
## returned it, or 0 when it went home by itself.
signal flag_taken(team: int, soldier_id: int)
signal flag_dropped(team: int, soldier_id: int)
signal flag_returned(team: int, soldier_id: int)
## team is the team that scored, soldier_id the carrier.
signal flag_captured(team: int, soldier_id: int)
## winner is a team, or -1 for a draw.
signal match_over(winner: int)
## A soldier stepped onto one of its team's inventory stations, and a station
## put a loadout on a soldier or restocked it.
signal station_entered(station_id: int, soldier_id: int)
signal station_used(station_id: int, soldier_id: int)
signal resupplied(soldier_id: int)
## A base asset took damage, was destroyed, or came back after a repair.
## attacker_id is 0 if it isn't known.
signal asset_damaged(asset_id: int, attacker_id: int, amount: float, from: Vector3)
signal asset_destroyed(asset_id: int, attacker_id: int)
signal asset_repaired(asset_id: int, soldier_id: int)
## A team's generator went down or came back.
signal power_lost(team: int)
## A turret fired a shot, added to projectiles before this.
signal turret_fired(asset_id: int)
signal power_back(team: int)
## A soldier gave its team's bots an order (Orders.Kind) in its command this
## tick, sent before it moves.
signal ordered(soldier_id: int, order: int, arg: int)

var rng := RandomNumberGenerator.new()
var seed_value := 0
var tick := 0
var running := true
## Entity id to node. Each entity has entity_id, simulate(), get_state() and
## set_state().
var entities: Dictionary[int, Node] = {}
## Entity id to the CommandSource that drives it.
var sources: Dictionary[int, CommandSource] = {}
var next_id := 1
## Shots in flight, oldest first.
var projectiles: Array[Projectile] = []
## Mines stuck to the world, oldest first.
var mines: Array[Mine] = []
## Team to the places its soldiers respawn. Set from the map.
var spawns: Dictionary[int, Array] = {}
var settings := MatchSettings.new()
## Team to its flag, and to the spot on its stand a carrier touches to score.
var flags: Dictionary[int, Flag] = {}
var stands: Dictionary[int, Vector3] = {}
## Inventory stations by id.
var stations: Dictionary[int, InventoryStation] = {}
## Base assets (generators, turrets and sensors) by id.
var assets: Dictionary[int, BaseAsset] = {}
## Each team's generator (the lowest id if it has more than one), by team.
var generators: Dictionary[int, BaseAsset] = {}
## Force fields over the ways into the generator rooms, by id.
var fields: Dictionary[int, ForceField] = {}
## Per team, the ids of living enemy soldiers its working sensors see, in id
## order, made at the end of each tick from where everyone is.
var sensed: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var scores: Array[int] = [0, 0]
var time_left := 0.0
var over := false
## The winning team, or -1 for a draw, once the match is over.
var winner := -1
## The map's chunked ground, if it has one. Its collision is kept under the
## soldiers and flags each tick, and shots and sight lines are checked
## against its heights everywhere.
var terrain: Terrain
## The match's bots, if it has any. They work out their commands for the tick
## before anything moves.
var bots: BotDirector
var fleet := VehicleFleet.new(self)


const WAYPOINT_TICKS := 30 * 60
const WAYPOINT_RANGE := 12.0

var arena: GameMap
var hold_points: Array[HoldPoint] = []
var neutral_station: InventoryStation
var neutral_supply_at := Vector3.INF
var results := MatchResults.new()
var waypoints := {}
var remote_orders := {}
var team_calls := TeamCalls.new()


func _init(match_seed := 1) -> void:
	seed_value = match_seed
	rng.seed = match_seed
	time_left = settings.time_limit
	name = "Match"


func _physics_process(delta: float) -> void:
	if running:
		step(delta)


func step(delta: float) -> void:
	if Prof.on:
		_profiled_step(delta)
		return
	tick += 1
	var ids := entities.keys()
	ids.sort()
	if terrain != null:
		_keep_terrain_collision(ids)
	_step_waypoints()
	if bots != null:
		bots.run_bots(delta)
	for id: int in ids:
		var source: CommandSource = sources.get(id)
		var command := source.make_command(delta) if source != null else PlayerCommand.new()
		_apply_order(id, command)
		_move_soldier(entities[id], command, delta)
	_step_fleet(delta)
	_step_stations(delta, ids)
	_step_turrets(delta)
	_step_projectiles(delta)
	_step_mines(delta)
	_step_objectives(delta)
	_step_fields()
	_step_sensors()


## step() with each part timed for Prof. Does the same in the same order.
func _profiled_step(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	tick += 1
	var ids := entities.keys()
	ids.sort()
	var t := Time.get_ticks_usec()
	if terrain != null:
		_keep_terrain_collision(ids)
	Prof.add("terrain_collision", Time.get_ticks_usec() - t)
	t = Time.get_ticks_usec()
	_step_waypoints()
	if bots != null:
		bots.run_bots(delta)
	Prof.add("bots", Time.get_ticks_usec() - t)
	for id: int in ids:
		var source: CommandSource = sources.get(id)
		t = Time.get_ticks_usec()
		var command := source.make_command(delta) if source != null else PlayerCommand.new()
		Prof.add("bots" if source is BotBrain else "other_sources", Time.get_ticks_usec() - t)
		_apply_order(id, command)
		t = Time.get_ticks_usec()
		_move_soldier(entities[id], command, delta)
		Prof.add("soldier_sim", Time.get_ticks_usec() - t)
	t = Time.get_ticks_usec()
	_step_fleet(delta)
	Prof.add("vehicles", Time.get_ticks_usec() - t)
	_step_stations(delta, ids)
	t = Time.get_ticks_usec()
	_step_turrets(delta)
	Prof.add("turrets", Time.get_ticks_usec() - t)
	t = Time.get_ticks_usec()
	_step_projectiles(delta)
	Prof.add("projectiles", Time.get_ticks_usec() - t)
	Prof.count("projectiles_live", projectiles.size())
	_step_mines(delta)
	t = Time.get_ticks_usec()
	_step_objectives(delta)
	Prof.add("flags", Time.get_ticks_usec() - t)
	_step_fields()
	_step_sensors()
	Prof.add("tick", Time.get_ticks_usec() - t0)


func _apply_order(id: int, command: PlayerCommand) -> void:
	if command.order == Orders.Kind.NONE:
		return
	if command.order in Orders.TEAM_CALLS or command.order == Orders.Kind.ACK_CALL:
		team_calls.apply(self, soldier(id), command)
		return
	if command.order != Orders.Kind.WAYPOINT:
		ordered.emit(id, command.order, command.order_arg)
		return
	var sender := soldier(id)
	var recipient := soldier(command.order_arg)
	var point := command.order_point
	if over or arena == null or sender == null or sender.dead or recipient == null or recipient.dead:
		return
	if recipient == sender or recipient.team != sender.team or not point.is_finite() or not arena.tactical_bounds().has_point(point):
		return
	if carried_flag(recipient.entity_id) != null:
		return
	var target := Vector3(point.x, arena.surface_at(point.x, point.y), point.y)
	waypoints[recipient.entity_id] = {"by": id, "at": target, "until": tick + WAYPOINT_TICKS}


func _step_waypoints() -> void:
	if not team_calls.by_team.is_empty():
		team_calls.expire(tick, over)
	for id: int in waypoints.keys():
		var order: Dictionary = waypoints[id]
		var who := soldier(id)
		if over or who == null or who.dead or tick >= order.until or who.at().distance_to(order.at) <= WAYPOINT_RANGE or carried_flag(id) != null:
			waypoints.erase(id)


func tactical_orders(team: int) -> Dictionary:
	if bots == null:
		return remote_orders.get(team, {})
	var commander := bots.commander(team)
	return commander.order_locks if commander != null else {}


func tactical_soldier_visible(viewer: Soldier, who: Soldier) -> bool:
	return not who.dead and (who.team == viewer.team or (who.entity_id in sensed[viewer.team] and not who.jamming()))


func tactical_flag_visible(viewer: Soldier, flag: Flag) -> bool:
	if flag.mode != Flag.Mode.CARRIED:
		return true
	var carrier := soldier(flag.carrier_id)
	return carrier != null and (carrier.team == viewer.team or not carrier.jamming())


func change_occupant(who: Soldier) -> void:
	results.change_occupant(who)
	team_calls.change_occupant(who)
	waypoints.erase(who.entity_id)
	for id: int in waypoints.keys():
		if waypoints[id].by == who.entity_id:
			waypoints.erase(id)


func _move_soldier(who: Soldier, command: PlayerCommand, delta: float) -> void:
	if fleet.pads.is_empty():
		who.simulate(command, delta)
	else:
		fleet.command(who, command, delta)


func _step_fleet(delta: float) -> void:
	if not fleet.pads.is_empty():
		fleet.step(delta)


## Makes the terrain collision under everything now, before the first tick,
## so the match doesn't start with a hitch.
func prepare_terrain() -> void:
	if terrain != null:
		var ids := entities.keys()
		ids.sort()
		_keep_terrain_collision(ids, false)


## Collision under every soldier, living or dead, and every flag.
func _keep_terrain_collision(ids: Array, next_tick := true) -> void:
	var points := PackedVector3Array()
	var speeds := PackedFloat32Array()
	for id: int in ids:
		var body := entities[id] as Node3D
		if body is Soldier:
			points.append(body.global_position)
			speeds.append((body as Soldier).velocity.length())
	for team: int in flags:
		points.append(flags[team].global_position)
		# A frozen flag reports the jump it was moved by as a speed.
		speeds.append(0.0 if flags[team].freeze else flags[team].linear_velocity.length())
	for hull: Vehicle in fleet.hulls.values():
		if not hull.empty() or hull.velocity.length_squared() > 0.1:
			points.append(hull.position)
			speeds.append(hull.velocity.length())
	terrain.keep_collision_near(points, speeds, next_tick)


## The first thing in the world on the segment from a to b, from the physics
## world and the terrain's heights, as intersect_ray() gives it. The terrain
## has no collider.
func world_ray(a: Vector3, b: Vector3, mask: int, exclude: Array[RID] = []) -> Dictionary:
	var t := Time.get_ticks_usec() if Prof.on else 0
	var query := PhysicsRayQueryParameters3D.create(a, b, mask, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if Prof.on:
		Prof.count("intersect_ray")
		Prof.add("ray_physics", Time.get_ticks_usec() - t)
		t = Time.get_ticks_usec()
	if terrain != null and mask & WORLD_LAYER:
		var ground := terrain.raycast(a, b)
		if Prof.on:
			Prof.count("terrain_raycast")
			Prof.add("ray_terrain", Time.get_ticks_usec() - t)
		if not ground.is_empty() and (hit.is_empty() or a.distance_squared_to(ground.position) < a.distance_squared_to(hit.position)):
			ground["collider"] = null
			return ground
	return hit


## True if nothing in the world is between a and b.
func line_clear(a: Vector3, b: Vector3) -> bool:
	return world_ray(a, b, WORLD_LAYER).is_empty()


## Puts a team's flag on its stand. stand is the spot a capturing carrier has to
## touch, and the flag rests above it.
func add_flag(team: int, stand: Vector3, rest: Vector3) -> Flag:
	var flag := Flag.new()
	flag.entity_id = next_id
	next_id += 1
	flag.team = team
	flag.home = rest
	flag.position = rest
	add_child(flag)
	flags[team] = flag
	stands[team] = stand
	return flag


## Puts an inventory station for a team with its pad's foot at a point.
func add_station(team: int, at: Vector3, asset_id := 0, control_index := -1) -> InventoryStation:
	var station := InventoryStation.new()
	station.entity_id = next_id
	next_id += 1
	station.team = team
	station.asset_id = asset_id
	station.control_index = control_index
	station.position = at
	add_child(station)
	stations[station.entity_id] = station
	if team == InventoryStation.NEUTRAL:
		neutral_station = station
		neutral_supply_at = at
	return station


## The working station a soldier is standing on, or null. Stations are off
## while their team has no power.
func station_under(who: Soldier) -> InventoryStation:
	for id: int in stations:
		if stations[id].team == who.team and stations[id].holds(who) and station_working(stations[id]):
			return stations[id]
	return null


## Puts a base asset of a kind (BaseAsset.Kind) for a team with its foot at a
## point, facing a yaw in radians.
func add_asset(team: int, kind: BaseAsset.Kind, at: Vector3, facing := 0.0, deployed := false) -> BaseAsset:
	var made := BaseAsset.make(kind, team)
	made.entity_id = next_id
	next_id += 1
	made.position = at
	made.facing = facing
	if deployed:
		made.aim_yaw = facing
	made.deployed = deployed
	add_child(made)
	assets[made.entity_id] = made
	if kind == BaseAsset.Kind.GENERATOR and not generators.has(team):
		generators[team] = made
	return made


func asset_powered(machine: BaseAsset) -> bool:
	return machine.deployed or powered(machine.team)


func station_working(station: InventoryStation) -> bool:
	if station.team == InventoryStation.NEUTRAL:
		return station.control_index < 0 or station_team(station) >= 0
	if station.asset_id == 0:
		return powered(station.team)
	var machine := asset(station.asset_id)
	return machine != null and not machine.destroyed


func station_team(station: InventoryStation) -> int:
	if station.control_index < 0:
		return station.team
	if station.control_index >= hold_points.size():
		return InventoryStation.NEUTRAL
	var point := hold_points[station.control_index]
	return InventoryStation.NEUTRAL if point.contested else point.owning_team


func deploy_count(team: int, kind: BaseAsset.Kind) -> int:
	var count := 0
	for machine: BaseAsset in assets.values():
		if machine.deployed and machine.team == team and machine.kind == kind:
			count += 1
	return count


func deploy_clear(at: Vector3) -> bool:
	for stand: Vector3 in stands.values():
		if stand.distance_to(at) < DEPLOY_SPACING:
			return false
	for machine: BaseAsset in assets.values():
		if machine.position.distance_to(at) < DEPLOY_SPACING:
			return false
	for station: InventoryStation in stations.values():
		if station.asset_id == 0 and station.position.distance_to(at) < DEPLOY_SPACING:
			return false
	return true


func deploy(who: Soldier, pack: Pack) -> void:
	if not who.deploy_ready:
		deploy_result.emit(who.entity_id, "Pack empty")
		return
	if deploy_count(who.team, pack.deploy_kind) >= pack.team_limit:
		deploy_result.emit(who.entity_id, "Team limit reached")
		return
	var at := _deploy_ground(who, pack.deploy_kind)
	if at == Vector3.INF:
		deploy_result.emit(who.entity_id, "Stand on clear, level ground to deploy")
		return
	var machine := add_asset(who.team, pack.deploy_kind, at, who.yaw, true)
	if machine.kind == BaseAsset.Kind.STATION:
		add_station(who.team, at, machine.entity_id)
	who.deploy_ready = false
	deploy_result.emit(who.entity_id, "%s deployed" % BaseAsset.NAMES[machine.kind])


func _deploy_ground(who: Soldier, kind: BaseAsset.Kind) -> Vector3:
	if not who.grounded or who.horizontal_speed() > DEPLOY_SPEED:
		return Vector3.INF
	var ahead := BaseAsset.direction(who.yaw, 0.0)
	var at := who.position + ahead * DEPLOY_DISTANCE
	var ground := world_ray(at + Vector3.UP * 1.4, at + Vector3.DOWN * 1.4, WORLD_LAYER)
	if ground.is_empty() or ground.normal.y < 0.94:
		return Vector3.INF
	at = ground.position
	if not deploy_clear(at) or not line_clear(who.eye_transform().origin, at + Vector3.UP * 0.25):
		return Vector3.INF
	var radius := BaseAsset.RADIUS[kind]
	for direction in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var rim: Vector3 = at + direction * radius
		var support := world_ray(rim + Vector3.UP * 0.45, rim + Vector3.DOWN * 0.45, WORLD_LAYER)
		if support.is_empty() or support.normal.y < 0.94:
			return Vector3.INF
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = maxf(BaseAsset.HEIGHT[kind], 0.9)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = at + Vector3.UP * (0.45 + shape.height * 0.5)
	query.collision_mask = WORLD_LAYER | SOLDIER_LAYER | ASSET_LAYER | enemy_fields(who.team) | field_layer(who.team)
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return Vector3.INF
	return at


## The physics layer bit a team's force fields are on.
static func field_layer(team: int) -> int:
	return FIELD_LAYER << team


## The layers that block a team's soldiers and shots besides the world: the
## other team's force fields. None for -1, a team not known.
static func enemy_fields(team: int) -> int:
	return field_layer(1 - team) if team == 0 or team == 1 else 0


## Puts a force field for a team with its box's middle at a point, on while
## the team has power.
func add_field(team: int, at: Vector3, size: Vector3) -> ForceField:
	var made := ForceField.new()
	made.entity_id = next_id
	next_id += 1
	made.team = team
	made.position = at
	made.size = size
	made.on = powered(team)
	add_child(made)
	fields[made.entity_id] = made
	return made


## Each force field on while its team has power and off without. A change
## takes effect in the next tick's physics.
func _step_fields() -> void:
	for id: int in fields:
		var field := fields[id]
		var want := powered(field.team)
		if field.on != want:
			field.set_on(want)
			if not want:
				_wake_flags_on(field)



## Wakes dropped flags resting on a field that just went off so they fall.
func _wake_flags_on(field: ForceField) -> void:
	for team: int in flags:
		var each := flags[team]
		if each.mode == Flag.Mode.DROPPED and field.touches(each.global_position, 3.0):
			each.sleeping = false


func asset(id: int) -> BaseAsset:
	return assets.get(id)


## The team's generator, or null if it has none.
func generator(team: int) -> BaseAsset:
	return generators.get(team)


## True while the team's generator isn't destroyed, or if it has none.
func powered(team: int) -> bool:
	var made := generator(team)
	return made == null or not made.destroyed


## Takes health off an asset, none from its own team, and destroys it at 0.
## team is the attacker's team, used when the attacker is gone.
func damage_asset(target: BaseAsset, amount: float, attacker_id: int, team: int, from: Vector3) -> void:
	if target.destroyed or amount <= 0.0:
		return
	var attacker := soldier(attacker_id)
	if attacker != null:
		team = attacker.team
	if team == target.team:
		return
	target.health = maxf(target.health - amount, 0.0)
	asset_damaged.emit(target.entity_id, attacker_id, amount, from)
	if target.health <= 0.0:
		target.destroyed = true
		asset_destroyed.emit(target.entity_id, attacker_id)
		if target.kind == BaseAsset.Kind.GENERATOR:
			power_lost.emit(target.team)


## The team of a soldier or asset by its entity id, or -1.
func team_of(id: int) -> int:
	var who := soldier(id)
	if who != null:
		return who.team
	var machine := asset(id)
	return machine.team if machine != null else -1


## Each working turret with power turns towards the nearest enemy it can see
## within range, leading it, and fires once its aim is close. It looks round
## every LOOK_TICKS ticks, each turret on its own tick, with up to LOOK_RAYS
## rays, and keeps its target between looks while it's alive and in range.
func _step_turrets(delta: float) -> void:
	if assets.is_empty():
		return
	var w := Weapon.all[Weapon.TURRET]
	var ids := assets.keys()
	ids.sort()
	for id: int in ids:
		var turret := assets[id]
		if turret.kind != BaseAsset.Kind.TURRET:
			continue
		if turret.destroyed or not asset_powered(turret):
			turret.target_id = 0
			continue
		turret.cooldown = maxf(turret.cooldown - delta, 0.0)
		var pivot := turret.pivot()
		if (tick + id) % BaseAsset.LOOK_TICKS == 0:
			turret.target_id = _turret_target(turret, pivot)
		var target := soldier(turret.target_id)
		if target != null and (target.dead or target.centre().distance_to(pivot) > BaseAsset.TURRET_RANGE or not turret.guards(target.centre())):
			target = null
		if target == null:
			turret.target_id = 0
			turret.turn_towards(turret.facing, 0.0, BaseAsset.TURN_RATE * delta)
			continue
		var fall := target.tuning.gravity if not target.grounded and not target.jetting else 0.0
		var to := BotCombat.lead(pivot, Vector3.ZERO, target.centre(), target.velocity, fall, w) - pivot
		var want_yaw := atan2(-to.x, -to.z)
		var want_pitch := clampf(atan2(to.y, Vector2(to.x, to.z).length()), BaseAsset.PITCH_MIN, BaseAsset.PITCH_MAX)
		turret.turn_towards(want_yaw, want_pitch, BaseAsset.TURN_RATE * delta)
		var error := BaseAsset.direction(turret.aim_yaw, turret.aim_pitch).angle_to(BaseAsset.direction(want_yaw, want_pitch))
		if turret.cooldown <= 0.0 and error < BaseAsset.FIRE_CONE:
			_turret_fire(turret, pivot, w)


## The nearest living enemy it guards (BaseAsset.guards()) within a turret's range with a clear line from its
## swivel point, trying the nearest LOOK_RAYS, or 0. Walls and ground block
## the line.
func _turret_target(turret: BaseAsset, pivot: Vector3) -> int:
	var near: Array = []
	var ids := entities.keys()
	ids.sort()
	for id: int in ids:
		var other := soldier(id)
		if other == null or other.dead or other.team == turret.team or not turret.guards(other.centre()):
			continue
		var distance := other.centre().distance_to(pivot)
		if distance <= BaseAsset.TURRET_RANGE:
			near.append([distance, id])
	near.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	var blocks := WORLD_LAYER
	for k in mini(near.size(), BaseAsset.LOOK_RAYS):
		var id: int = near[k][1]
		if Prof.on:
			Prof.count("ray_by_turret")
		if world_ray(pivot, soldier(id).centre(), blocks).is_empty():
			return id
	return 0


## A turret's shot along its aim from its swivel point, with the turret's id
## as the shooter and its team.
func _turret_fire(turret: BaseAsset, pivot: Vector3, w: Weapon) -> void:
	var dir := BaseAsset.direction(turret.aim_yaw, turret.aim_pitch)
	var shot := Projectile.new()
	shot.id = next_id
	next_id += 1
	shot.weapon = w.slot
	shot.shooter = turret.entity_id
	shot.team = turret.team
	shot.position = pivot
	shot.velocity = dir * w.speed
	shot.damage = w.damage
	shot.muzzle_offset = dir * BaseAsset.BARREL
	projectiles.append(shot)
	turret.cooldown = w.fire_interval
	turret_fired.emit(turret.entity_id)


## Fills sensed: each team's working sensors with power see living enemies
## within SENSOR_RANGE of their top, except ones with a jammer on.
func _step_sensors() -> void:
	sensed[0] = PackedInt32Array()
	sensed[1] = PackedInt32Array()
	if assets.is_empty():
		return
	var tops: Array = [[], []]
	var asset_ids := assets.keys()
	asset_ids.sort()
	for id: int in asset_ids:
		var sensor := assets[id]
		if sensor.kind == BaseAsset.Kind.SENSOR and not sensor.destroyed and (sensor.team == 0 or sensor.team == 1) and asset_powered(sensor):
			tops[sensor.team].append(sensor.global_position + Vector3.UP * sensor.height())
	if tops[0].is_empty() and tops[1].is_empty():
		return
	var ids := entities.keys()
	ids.sort()
	for id: int in ids:
		var other := soldier(id)
		if other == null or other.dead or other.jamming() or (other.team != 0 and other.team != 1):
			continue
		var team := 1 - other.team
		for top: Vector3 in tops[team]:
			if top.distance_to(other.centre()) <= BaseAsset.SENSOR_RANGE:
				sensed[team].append(id)
				break


## Puts health back on an asset. A destroyed one works again once it's full.
func repair_asset(target: BaseAsset, amount: float, by: int) -> void:
	target.health = minf(target.health + amount, target.max_health())
	if target.destroyed and target.health >= target.max_health():
		target.destroyed = false
		results.add(self, by, MatchResults.Stat.REPAIRS)
		asset_repaired.emit(target.entity_id, by)
		if target.kind == BaseAsset.Kind.GENERATOR:
			power_back.emit(target.team)


## Each station counts down its cooldowns, then puts the wanted loadout on
## each soldier that just stepped on (once its cooldown is over) and on each
## one on the pad whose wanted loadout differs from what it wears. A station
## without power does nothing and forgets who's on it, so stepping on counts
## again once power is back.
func _step_stations(delta: float, ids: Array) -> void:
	if stations.is_empty():
		return
	var station_ids := stations.keys()
	station_ids.sort()
	for station_id: int in station_ids:
		var station := stations[station_id]
		var waiting := station.cooldowns.keys()
		waiting.sort()
		for id: int in waiting:
			station.cooldowns[id] -= delta
			if station.cooldowns[id] <= 0.0:
				station.cooldowns.erase(id)
		if not station_working(station):
			station.on.clear()
			continue
		var allowed_team := station_team(station)
		var now: Array[int] = []
		for id: int in ids:
			var who := soldier(id)
			if who != null and (allowed_team == InventoryStation.NEUTRAL or allowed_team == who.team) and station.holds(who):
				now.append(id)
		for id in now:
			var who := soldier(id)
			var entered := not station.on.has(id)
			if station.team == InventoryStation.NEUTRAL:
				if entered and not station.cooldowns.has(id):
					_refill_ammo(station, who)
				continue
			if entered:
				station_entered.emit(station_id, id)
			var changed := not who.next_loadout.equals(who.loadout)
			if changed or (entered and not station.cooldowns.has(id)):
				if changed:
					# During the cooldown a change keeps what was left, so
					# swapping loadouts can't refill.
					who.set_loadout(who.next_loadout, station.cooldowns.has(id))
				else:
					who.restock()
				station.cooldowns[id] = InventoryStation.COOLDOWN
				station_used.emit(station_id, id)
		station.on = now


## Starts the match clock again with the time limit in the settings.
func _refill_ammo(station: InventoryStation, who: Soldier) -> void:
	var refilled := false
	for slot in who.weapons.size():
		var full := who.max_ammo(slot)
		if who.ammo[slot] < full:
			who.ammo[slot] = full
			refilled = true
	if refilled:
		station.cooldowns[who.entity_id] = InventoryStation.AMMO_COOLDOWN
		resupplied.emit(who.entity_id)
		station_used.emit(station.entity_id, who.entity_id)


func start_clock() -> void:
	time_left = settings.time_limit


func carried_flag(soldier_id: int) -> Flag:
	for team in flags:
		var flag := flags[team]
		if flag.mode == Flag.Mode.CARRIED and flag.carrier_id == soldier_id:
			return flag
	return null


func _touching(who: Soldier, point: Vector3, reach: float) -> bool:
	return not who.dead and who.vehicle_id == 0 and who.distance_to_body(point) <= reach


func _at_capture_stand(who: Soldier) -> bool:
	return stands.has(who.team) and _touching(who, stands[who.team], settings.stand_touch_range)


## A carrier at its stand is waiting for its own flag before it can score.
func awaiting_flag_return(who: Soldier) -> bool:
	var own: Flag = flags.get(who.team)
	return not over and own != null and own.mode != Flag.Mode.HOME and _at_capture_stand(who) and carried_flag(who.entity_id) != null


func add_hold_point(at: Vector3) -> void:
	var point := HoldPoint.new()
	point.arena = arena
	point.letter = String.chr(65 + hold_points.size())
	point.position = at
	point.spot = at
	add_child(point)
	hold_points.append(point)


func _step_objectives(delta: float) -> void:
	if hold_points.is_empty():
		_step_flags(delta)
		return
	if over:
		return
	for point in hold_points:
		var sides := 0
		for who: Soldier in entities.values():
			if who.dead or who.vehicle_id != 0:
				continue
			if HoldPoint.contains(who.at(), point.spot):
				sides |= 1 << who.team
				if sides == 3:
					break
		var scored := point.advance(delta, sides)
		if scored >= 0:
			scores[scored] += 1
	_step_clock(delta)


func _step_flags(delta: float) -> void:
	if over or flags.is_empty():
		return
	var ids := entities.keys()
	ids.sort()
	var teams := flags.keys()
	teams.sort()
	for team: int in teams:
		var flag := flags[team]
		match flag.mode:
			Flag.Mode.CARRIED:
				var carrier := soldier(flag.carrier_id)
				if carrier == null or carrier.dead:
					_drop_flag(flag, carrier)
				else:
					flag.hold_on(carrier)
			Flag.Mode.DROPPED:
				flag.return_in -= delta
				if flag.return_in <= 0.0 or flag.global_position.y < -200.0:
					_return_flag(flag, 0)
		if flag.mode == Flag.Mode.CARRIED:
			continue
		# Touching it: enemies take it, its own team sends it home if it's lying
		# about.
		var reach := settings.flag_home_touch_range if flag.mode == Flag.Mode.HOME else settings.flag_touch_range
		for id: int in ids:
			var who := soldier(id)
			if who == null or not _touching(who, flag.global_position, reach):
				continue
			if who.team != flag.team:
				_take_flag(flag, who)
				break
			elif flag.mode == Flag.Mode.DROPPED:
				_return_flag(flag, who.entity_id)
				break
	# A carrier touching its own stand scores if its own flag is home.
	for team: int in teams:
		var flag := flags[team]
		if flag.mode != Flag.Mode.CARRIED:
			continue
		var carrier := soldier(flag.carrier_id)
		var own: Flag = flags.get(carrier.team)
		if own == null or own.mode != Flag.Mode.HOME:
			continue
		if _at_capture_stand(carrier):
			_capture(flag, carrier)
			if over:
				return
	_step_clock(delta)


func _step_clock(delta: float) -> void:
	time_left = maxf(time_left - delta, 0.0)
	if time_left <= 0.0:
		_end(-1 if scores[0] == scores[1] else (0 if scores[0] > scores[1] else 1))


func _take_flag(flag: Flag, who: Soldier) -> void:
	flag.mode = Flag.Mode.CARRIED
	flag.carrier_id = who.entity_id
	flag.return_in = 0.0
	flag.hold_on(who)
	results.add(self, who.entity_id, MatchResults.Stat.GRABS)
	flag_taken.emit(flag.team, who.entity_id)


## The carrier lets go where it is, with its velocity.
func _drop_flag(flag: Flag, carrier: Soldier) -> void:
	var by := flag.carrier_id
	var spin := Vector3(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
	flag.drop(carrier.velocity if carrier != null else Vector3.ZERO, spin, settings.flag_return_time)
	flag_dropped.emit(flag.team, by)


func _return_flag(flag: Flag, by: int) -> void:
	flag.send_home()
	results.add(self, by, MatchResults.Stat.RETURNS)
	flag_returned.emit(flag.team, by)


func _capture(flag: Flag, carrier: Soldier) -> void:
	flag.send_home()
	scores[carrier.team] += 1
	results.capture(self, carrier)
	flag_captured.emit(carrier.team, carrier.entity_id)
	if scores[carrier.team] >= settings.capture_limit:
		_end(carrier.team)


func _end(team: int) -> void:
	over = true
	winner = team
	match_over.emit(team)


## Adds a soldier in a loadout, by default medium with the disc launcher and
## chaingun.
func add_soldier(team: int, spawn: Transform3D, source: CommandSource = null, loadout: Loadout = null) -> Soldier:
	var soldier := Soldier.new()
	if loadout != null:
		soldier.set_loadout(loadout)
	soldier.entity_id = next_id
	next_id += 1
	soldier.team = team
	soldier.game = self
	soldier.name = "Soldier%d" % soldier.entity_id
	soldier.display_name = "Soldier %d" % soldier.entity_id
	# The match sits at the world origin, so its space is the world's.
	soldier.position = spawn.origin
	soldier.yaw = spawn.basis.get_euler().y
	soldier.rotation.y = soldier.yaw
	add_child(soldier)
	entities[soldier.entity_id] = soldier
	if source == null:
		source = CommandSource.new()
	source.yaw = soldier.yaw
	sources[soldier.entity_id] = source
	return soldier


func soldier(id: int) -> Soldier:
	return entities.get(id) as Soldier


## Fires one shot of the soldier's current weapon from its eye, with spread
## from the match's random numbers and some of its velocity.
func fire(shooter: Soldier) -> void:
	var weapon := Weapon.all[shooter.weapon_slot()]
	var eye := shooter.eye_transform()
	var dir := -eye.basis.z
	if weapon.spread > 0.0:
		# An even spread over the cone's disc.
		var angle := rng.randf() * TAU
		var off := sqrt(rng.randf()) * tan(weapon.spread)
		dir = (dir + (eye.basis.x * cos(angle) + eye.basis.y * sin(angle)) * off).normalized()
	_launch(shooter, weapon, dir, eye.basis * Soldier.MUZZLE)


## Throws a hand grenade or a mine (Weapon.HAND_GRENADE or Weapon.MINE) from
## the soldier's eye where it's looking, from the left hand.
func throw(shooter: Soldier, slot: int) -> void:
	var eye := shooter.eye_transform()
	_launch(shooter, Weapon.all[slot], -eye.basis.z, eye.basis * Soldier.THROW_HAND)


func _launch(shooter: Soldier, weapon: Weapon, dir: Vector3, muzzle_offset: Vector3) -> void:
	var eye := shooter.eye_transform()
	var shot := Projectile.new()
	shot.id = next_id
	next_id += 1
	shot.weapon = weapon.slot
	shot.shooter = shooter.entity_id
	shot.vehicle_id = shooter.vehicle_id
	shot.team = shooter.team
	shot.position = eye.origin
	shot.velocity = dir * weapon.speed + shooter.velocity * weapon.inherit
	shot.damage = weapon.damage_with(shooter.energy, shooter.tuning.energy_max)
	shot.bounces_left = weapon.bounces
	shot.muzzle_offset = muzzle_offset
	projectiles.append(shot)
	fired.emit(shooter.entity_id, weapon.slot)


## Moves every shot along its path for one tick, with a ray cast over the
## whole step so even the fastest can't pass through anything. A shot with
## bounces left glances off the world, and one with a fuse blows up where it
## is when the fuse runs out.
func _step_projectiles(delta: float) -> void:
	if projectiles.is_empty():
		return
	var kept: Array[Projectile] = []
	for shot in projectiles:
		var weapon := Weapon.all[shot.weapon]
		shot.velocity += Vector3.DOWN * weapon.gravity * delta
		if weapon.drag > 0.0:
			shot.velocity *= maxf(1.0 - weapon.drag * delta, 0.0)
		var to := shot.position + shot.velocity * delta
		var exclude: Array[RID] = []
		var owner_body := soldier(shot.shooter)
		if owner_body != null:
			exclude.append(owner_body.get_rid())
		elif assets.has(shot.shooter):
			exclude.append(assets[shot.shooter].get_rid())
		if Prof.on:
			Prof.count("ray_by_projectile")
		# A thrown mine passes through soldiers and sticks to the world or
		# an asset.
		var is_mine := shot.weapon == Weapon.MINE
		var own_hull: Vehicle = fleet.hulls.get(shot.vehicle_id)
		if own_hull != null:
			exclude.append(own_hull.get_rid())
		var mask := WORLD_LAYER | ASSET_LAYER | PAD_LAYER | Vehicle.HULL_LAYER
		var hit := world_ray(shot.position, to, mask if is_mine else mask | SOLDIER_LAYER, exclude)
		shot.age += delta
		if is_mine:
			if not hit.is_empty():
				_place_mine(shot, hit.position, hit.normal)
			elif shot.age < weapon.lifetime:
				shot.position = to
				kept.append(shot)
		elif not hit.is_empty():
			var victim := hit.collider as Soldier
			var machine := hit.collider as BaseAsset
			var hull := hit.collider as Vehicle
			var normal: Vector3 = hit.normal
			# Grenades bounce off the world and go off on a soldier or asset.
			if victim == null and machine == null and hull == null and shot.bounces_left != 0:
				# The rest of the tick's move is dropped, which is under 2 cm at
				# grenade speeds after a bounce.
				shot.position = hit.position + normal * 0.05
				shot.velocity = shot.velocity.bounce(normal) * weapon.bounce_keep
				if shot.bounces_left > 0:
					shot.bounces_left -= 1
				if weapon.fuse > 0.0 and shot.age >= weapon.fuse:
					_impact(shot, shot.position, normal, null)
				else:
					kept.append(shot)
			else:
				_impact(shot, hit.position + normal * 0.05, normal, victim, machine, hull)
		elif weapon.fuse > 0.0 and shot.age >= weapon.fuse:
			_impact(shot, to, Vector3.UP, null)
		elif shot.age >= weapon.lifetime:
			pass
		else:
			shot.position = to
			kept.append(shot)
	projectiles = kept


func _impact(shot: Projectile, at: Vector3, normal: Vector3, victim: Soldier, machine: BaseAsset = null, hull: Vehicle = null) -> void:
	var weapon := Weapon.all[shot.weapon]
	shot.position = at
	impacted.emit(weapon.slot, at, normal)
	# A shot with no direct damage, like a grenade, just blows up on the
	# soldier it hits.
	var direct := victim if victim != null and shot.damage > 0.0 else null
	if direct != null:
		var attacker := soldier(shot.shooter)
		# Read the stance before the hit can lift the target off the ground.
		var slow_shot := weapon.slot == Weapon.DISC or weapon.slot == Weapon.PLASMA or weapon.slot == Weapon.BLASTER
		var airborne := slow_shot and attacker != null and attacker.team != direct.team and not direct.dead and not direct.grounded and direct.vehicle_id == 0
		var push := shot.velocity.normalized() * weapon.hit_impulse
		if weapon.splash_radius > 0.0:
			push = (direct.centre() - at).normalized() * weapon.splash_impulse
		direct.push(push)
		var from := at
		if attacker != null:
			from = attacker.global_position
		elif assets.has(shot.shooter):
			from = assets[shot.shooter].pivot()
		damage(direct, shot.damage, shot.shooter, weapon.slot, from)
		if airborne:
			air_hit.emit(shot.shooter, direct.entity_id)
	var direct_asset := machine if machine != null and shot.damage > 0.0 else null
	if direct_asset != null:
		damage_asset(direct_asset, shot.damage, shot.shooter, shot.team, at)
	var direct_hull := hull if hull != null and shot.damage > 0.0 else null
	if direct_hull != null:
		direct_hull.push(shot.velocity.normalized() * maxf(weapon.hit_impulse, weapon.splash_impulse))
		fleet.damage(direct_hull, shot.damage, shot.shooter, shot.team, weapon.slot)
	if weapon.splash_radius > 0.0:
		explode(at, weapon.slot, shot.shooter, direct, -1, direct_asset, shot.team, direct_hull)


## A blast from a weapon at a point: splash damage and a push on every living
## soldier in range that the blast can see, less for those further away, and
## splash damage on every enemy asset in range it can see. asset_team is the
## attacker's team for assets when the attacker is gone, if attacker_team
## isn't given.
func explode(at: Vector3, weapon_slot: int, attacker_id: int, skip: Soldier = null, attacker_team := -1, skip_asset: BaseAsset = null, asset_team := -1, skip_hull: Vehicle = null) -> void:
	var weapon := Weapon.all[weapon_slot]
	# With the attacker gone, its team still takes no damage, as in damage().
	var orphan_team := attacker_team if soldier(attacker_id) == null else -1
	# Walls and ground block it. Force fields don't.
	var blocks := WORLD_LAYER
	var ids := entities.keys()
	ids.sort()
	for id: int in ids:
		var target := soldier(id)
		if target == null or target == skip or target.dead or target.vehicle_id != 0:
			continue
		var distance := target.distance_to_body(at)
		if distance > weapon.splash_radius:
			continue
		# Walls and ground between the blast and the soldier block it.
		if Prof.on:
			Prof.count("ray_by_blast")
		if not world_ray(at, target.centre(), blocks).is_empty():
			continue
		var away := target.centre() - at
		away = away.normalized() if away.length() > 0.01 else Vector3.UP
		target.push(away * weapon.splash_impulse_at(distance))
		if target.team == orphan_team:
			continue
		damage(target, weapon.splash_damage_at(distance), attacker_id, weapon_slot, at)
	if not assets.is_empty():
		var team := asset_team if attacker_team < 0 else attacker_team
		var asset_ids := assets.keys()
		asset_ids.sort()
		for id: int in asset_ids:
			var target := assets[id]
			if target == skip_asset or target.destroyed:
				continue
			var distance := target.distance_to_body(at)
			if distance > weapon.splash_radius or not world_ray(at, target.centre(), blocks).is_empty():
				continue
			damage_asset(target, weapon.splash_damage_at(distance), attacker_id, team, at)
	var vehicle_team := team_of(attacker_id)
	if vehicle_team < 0:
		vehicle_team = asset_team if attacker_team < 0 else attacker_team
	var hull_ids := fleet.hulls.keys()
	hull_ids.sort()
	for id: int in hull_ids:
		var hull: Vehicle = fleet.hulls.get(id)
		if hull == null or hull == skip_hull:
			continue
		var distance := hull.distance_to_body(at)
		if distance > weapon.splash_radius or not line_clear(at, hull.position):
			continue
		hull.push((hull.position - at).normalized() * weapon.splash_impulse_at(distance))
		fleet.damage(hull, weapon.splash_damage_at(distance), attacker_id, vehicle_team, weapon_slot)
	_set_off_mines_near(at)


## A thrown mine sticks where it landed. A soldier's oldest mine goes off if
## this one is past MINE_LIMIT.
func _place_mine(shot: Projectile, at: Vector3, normal: Vector3) -> void:
	var own: Array[Mine] = []
	for other in mines:
		if other.owner_id == shot.shooter:
			own.append(other)
	var mine := Mine.new()
	mine.id = shot.id
	mine.owner_id = shot.shooter
	mine.team = shot.team
	mine.normal = normal
	mine.position = at + normal * 0.05
	mine.arm_in = MINE_ARM_TIME
	mines.append(mine)
	mine_placed.emit(mine.id, mine.position)
	for k in own.size() - MINE_LIMIT + 1:
		if mines.has(own[k]):
			_blow_mine(own[k])


## Arms mines, and sets off armed ones with a living enemy close by.
func _step_mines(delta: float) -> void:
	if mines.is_empty():
		return
	var ids := entities.keys()
	ids.sort()
	for mine in mines.duplicate():
		if not mines.has(mine):
			continue
		mine.age += delta
		if not mine.armed():
			mine.arm_in = maxf(mine.arm_in - delta, 0.0)
			if mine.armed():
				mine_armed.emit(mine.id, mine.position)
			continue
		for id: int in ids:
			var who := soldier(id)
			if who != null and not who.dead and who.team != mine.team and who.distance_to_body(mine.position) <= MINE_TRIGGER:
				_blow_mine(mine)
				break


## Every mine close to a blast goes off too, armed or not.
func _set_off_mines_near(at: Vector3) -> void:
	for mine in mines.duplicate():
		if mines.has(mine) and mine.position.distance_to(at) <= MINE_SPLASH_TRIGGER:
			_blow_mine(mine)


## Takes a mine out and blows it up, which can set off others near it.
func _blow_mine(mine: Mine) -> void:
	mines.erase(mine)
	var at := mine.position + mine.normal * 0.1
	impacted.emit(Weapon.MINE, at, mine.normal)
	explode(at, Weapon.MINE, mine.owner_id, null, mine.team)


## Takes health off a soldier, less for your own shots and none from your
## teammates', and kills it at zero. A shield takes what it can from energy
## first and goes off when energy runs out.
func damage(victim: Soldier, amount: float, attacker_id: int, weapon_slot: int, from: Vector3) -> void:
	if victim.dead or amount <= 0.0:
		return
	var attacker := soldier(attacker_id)
	if attacker_id == victim.entity_id:
		amount *= Weapon.all[weapon_slot].self_damage_share
	elif team_of(attacker_id) == victim.team:
		return
	if victim.shielded():
		var per_point := victim.pack().energy_per_point
		var stopped := minf(amount, victim.energy / per_point)
		victim.energy = maxf(victim.energy - stopped * per_point, 0.0)
		amount -= stopped
		if stopped > 0.0:
			shield_hit.emit(victim.entity_id, stopped, from)
		if victim.energy <= 0.0:
			victim.switch_pack(false)
	victim.health = maxf(victim.health - amount, 0.0)
	if attacker != null and attacker.team != victim.team:
		hit.emit(attacker_id, victim.entity_id, weapon_slot)
	results.damage(self, victim, attacker_id, amount)
	damaged.emit(victim.entity_id, attacker_id, amount, from)
	if victim.health <= 0.0:
		var hull: Vehicle = fleet.hulls.get(victim.vehicle_id)
		if hull != null and not fleet.eject(hull, victim, true):
			victim.mount(0, -1)
		victim.die()
		var held := carried_flag(victim.entity_id)
		if held != null:
			_drop_flag(held, victim)
		results.kill(self, victim.entity_id, attacker_id)
		killed.emit(victim.entity_id, attacker_id, weapon_slot)
		if held != null and team_of(attacker_id) == held.team:
			results.add(self, attacker_id, MatchResults.Stat.STOPS)
			carrier_stopped.emit(victim.entity_id, attacker_id)


## The nearest hurt living teammate a soldier is looking towards, within
## reach metres of its eye and not behind a wall, else the nearest damaged or
## destroyed asset of its team like that, or null.
func repair_target(healer: Soldier, reach: float) -> Node3D:
	var eye := healer.eye_transform()
	var ahead := -eye.basis.z
	var best: Soldier = null
	var best_distance := reach
	var ids := entities.keys()
	ids.sort()
	for id: int in ids:
		var other := soldier(id)
		if other == null or other == healer or other.dead or other.vehicle_id != 0 or other.team != healer.team or other.health >= other.tuning.health_max:
			continue
		var distance := other.distance_to_body(eye.origin)
		if distance > best_distance:
			continue
		var to := other.centre() - eye.origin
		# In front: within about 50° of where you look, or touching.
		if distance > 0.3 and ahead.angle_to(to) > REPAIR_CONE:
			continue
		if not line_clear(eye.origin, other.centre()):
			continue
		best = other
		best_distance = distance
	if best != null:
		return best
	var best_asset: BaseAsset = null
	best_distance = reach
	var asset_ids := assets.keys()
	asset_ids.sort()
	for id: int in asset_ids:
		var machine := assets[id]
		if machine.team != healer.team or machine.health >= machine.max_health():
			continue
		var distance := machine.distance_to_body(eye.origin)
		if distance > best_distance:
			continue
		if distance > 0.3 and ahead.angle_to(machine.centre() - eye.origin) > REPAIR_CONE:
			continue
		if not line_clear(eye.origin, machine.centre()):
			continue
		best_asset = machine
		best_distance = distance
	return best_asset


func respawn_delay() -> float:
	var wave := settings.respawn_wave_ticks
	if wave <= 0:
		return RESPAWN_DELAY
	var earliest := tick + roundi(RESPAWN_DELAY * 60.0)
	return RESPAWN_DELAY + posmod(-earliest, wave) / 60.0


func ready_to_respawn(seconds_left: float, delta: float) -> bool:
	var wave := settings.respawn_wave_ticks
	if wave <= 0:
		return seconds_left <= 0.0
	return tick % wave == 0 and seconds_left < delta * 0.5


## Puts a dead soldier back at one of its team's spawn points, picked with the
## match's random numbers.
func respawn(target: Soldier) -> void:
	var points: Array = spawns.get(target.team, [])
	var where := Transform3D(Basis.IDENTITY, target.global_position)
	if not points.is_empty():
		var first := rng.randi_range(0, points.size() - 1)
		where = points[first]
		if settings.respawn_wave_ticks > 0:
			where = _pick_ctf_spawn(points, first, target.team)
	target.revive(where)
	var source: CommandSource = sources.get(target.entity_id)
	if source != null:
		source.yaw = target.yaw
		source.pitch = 0.0
	results.hits.erase(target.entity_id)
	respawned.emit(target.entity_id)


## Start at a random point. If both flanks are under fire, take the farthest.
func _pick_ctf_spawn(points: Array, first: int, team: int) -> Transform3D:
	var best: Transform3D = points[first]
	var safest := -1.0
	for slot in points.size():
		var point: Transform3D = points[(first + slot) % points.size()]
		var closest := INF
		var occupied := false
		for who: Soldier in entities.values():
			if who.dead:
				continue
			var distance := who.at().distance_squared_to(point.origin)
			if who.team == team:
				occupied = occupied or distance < 3.0 * 3.0
			else:
				closest = minf(closest, distance)
		if occupied:
			continue
		if closest >= 38.0 * 38.0:
			return point
		if closest > safest:
			best = point
			safest = closest
	return best


func get_state(include_sources := true) -> Dictionary:
	var states := {}
	for id: int in entities:
		states[id] = entities[id].get_state()
	var shots := []
	for shot in projectiles:
		shots.append(shot.get_state())
	var source_states := {}
	if include_sources:
		for id: int in sources:
			# The director saves its brains along with the shared bot state.
			if bots != null and sources[id] is BotBrain:
				continue
			var source_state := sources[id].get_state()
			if not source_state.is_empty():
				source_states[id] = source_state
	var flag_states := {}
	for team in flags:
		flag_states[team] = flags[team].get_state()
	var station_states := {}
	for id: int in stations:
		station_states[id] = stations[id].get_state()
	var asset_states := {}
	for id: int in assets:
		asset_states[id] = assets[id].get_state()
	var field_states := {}
	for id: int in fields:
		field_states[id] = fields[id].get_state()
	var state := {
		"scores": scores.duplicate(),
		"hold_points": hold_points.map(func(point: HoldPoint) -> Dictionary: return point.get_state()),
		"results": results.get_state(include_sources),
		"waypoints": waypoints.duplicate(true),
		"team_calls": team_calls.get_state() if include_sources else {},
		"sensed": sensed.duplicate(),
		"time_left": time_left,
		"over": over,
		"winner": winner,
		"stands": stands.duplicate(),
		"flags": flag_states,
		"stations": station_states,
		"assets": asset_states,
		"fields": field_states,
		"fleet": fleet.get_state(),
		"tick": tick,
		"seed": seed_value,
		"rng_state": rng.state,
		"next_id": next_id,
		"entities": states,
		"projectiles": shots,
		"mines": mines.map(func(mine: Mine) -> Dictionary: return mine.get_state()),
		"sources": source_states,
	}
	if include_sources:
		if terrain != null:
			state["terrain_collision"] = terrain.collision_state()
		if bots != null:
			state["bots"] = bots.get_state()
	return state


## Puts the match back to a state from get_state(), making any soldiers it's
## missing. Entities not in the state are left alone.
func set_state(state: Dictionary) -> void:
	tick = state.tick
	seed_value = state.seed
	rng.seed = seed_value
	rng.state = state.rng_state
	next_id = state.next_id
	for id: int in state.entities:
		var entity_state: Dictionary = state.entities[id]
		if not entities.has(id) and entity_state.kind == "soldier":
			var made := Soldier.new()
			made.name = "Soldier%d" % id
			made.display_name = "Soldier %d" % id
			made.team = entity_state.team
			made.game = self
			add_child(made)
			entities[id] = made
			sources[id] = CommandSource.new()
		entities[id].set_state(entity_state)
	results.set_state(state.get("results", {}))
	waypoints = state.get("waypoints", {}).duplicate(true)
	team_calls.set_state(state.get("team_calls", {}))
	remote_orders = state.get("tactical_orders", {})
	sensed.assign(state.get("sensed", [PackedInt32Array(), PackedInt32Array()]))
	scores.assign(state.scores)
	time_left = state.time_left
	over = state.over
	winner = state.winner
	for team: int in state.stands:
		stands[team] = state.stands[team]
	for team: int in state.flags:
		var flag_state: Dictionary = state.flags[team]
		if not flags.has(team):
			add_flag(team, stands[team], flag_state.home)
			flags[team].entity_id = flag_state.id
		flags[team].set_state(flag_state)
	var point_states: Array = state.get("hold_points", [])
	while hold_points.size() > point_states.size():
		var removed: HoldPoint = hold_points.pop_back()
		remove_child(removed)
		removed.queue_free()
	for index in point_states.size():
		if index == hold_points.size():
			add_hold_point(point_states[index].position)
		hold_points[index].set_state(point_states[index])
	neutral_station = null
	neutral_supply_at = Vector3.INF
	var station_states: Dictionary = state.get("stations", {})
	for id: int in stations.keys():
		var station := stations[id]
		var saved: Dictionary = station_states.get(id, {})
		if (station.asset_id != 0 or station.team == InventoryStation.NEUTRAL) and (saved.is_empty() or station.team != saved.team):
			remove_child(station)
			station.queue_free()
			stations.erase(id)
	for id: int in station_states:
		if not stations.has(id):
			var made := InventoryStation.new()
			made.entity_id = id
			made.team = station_states[id].team
			made.position = station_states[id].position
			add_child(made)
			stations[id] = made
		stations[id].set_state(station_states[id])
		if stations[id].team == InventoryStation.NEUTRAL:
			neutral_station = stations[id]
			neutral_supply_at = station_states[id].position
	var asset_states: Dictionary = state.get("assets", {})
	for id: int in assets.keys():
		var machine := assets[id]
		var saved: Dictionary = asset_states.get(id, {})
		if machine.deployed and (saved.is_empty() or machine.kind != saved.asset or machine.team != saved.team):
			remove_child(machine)
			machine.queue_free()
			assets.erase(id)
	for id: int in asset_states:
		if not assets.has(id):
			var made := BaseAsset.make(asset_states[id].asset, asset_states[id].team)
			made.entity_id = id
			made.position = asset_states[id].position
			made.facing = asset_states[id].facing
			made.deployed = asset_states[id].get("deployed", false)
			add_child(made)
			assets[id] = made
		assets[id].set_state(asset_states[id])
	generators.clear()
	var generator_ids := assets.keys()
	generator_ids.sort()
	for id: int in generator_ids:
		if assets[id].kind == BaseAsset.Kind.GENERATOR and not generators.has(assets[id].team):
			generators[assets[id].team] = assets[id]
	var field_states: Dictionary = state.get("fields", {})
	for id: int in field_states:
		if not fields.has(id):
			var made := ForceField.new()
			made.entity_id = id
			made.team = field_states[id].team
			made.position = field_states[id].position
			made.size = field_states[id].size
			made.on = field_states[id].on
			add_child(made)
			fields[id] = made
		fields[id].set_state(field_states[id])
	var source_states: Dictionary = state.get("sources", {})
	for id: int in source_states:
		if sources.has(id):
			sources[id].set_state(source_states[id])
	projectiles.clear()
	for shot_state: Dictionary in state.get("projectiles", []):
		projectiles.append(Projectile.from_state(shot_state))
	mines.clear()
	for mine_state: Dictionary in state.get("mines", []):
		mines.append(Mine.from_state(mine_state))
	fleet.set_state(state.get("fleet", {}))
	if terrain != null and state.has("terrain_collision"):
		terrain.set_collision_state(state.terrain_collision)
	if bots != null and state.has("bots"):
		bots.set_state(state.bots)
	next_id = state.next_id
	if is_inside_tree():
		_step_sensors()
