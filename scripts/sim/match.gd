class_name Match
extends Node3D

## Owns the match state. Entities live under it with stable integer ids and
## only change in step(), once per physics tick, from their commands. The HUD
## and camera only read it, and hear about hits and kills from its signals.

## Physics layers. The world is on 1, living soldiers on 2. Dead soldiers
## leave layer 2, so shots and other soldiers pass through them.
const WORLD_LAYER := 1
const SOLDIER_LAYER := 2
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
signal killed(victim_id: int, killer_id: int, weapon: int)
## A projectile hit something or blew up. normal is the surface's.
signal impacted(weapon: int, position: Vector3, normal: Vector3)
signal respawned(soldier_id: int)
## A thrown mine stuck where it landed, and later armed.
signal mine_placed(mine_id: int, at: Vector3)
signal mine_armed(mine_id: int, at: Vector3)
## A soldier's pack went on or off: a shield or jammer switched, or a repair
## pack starting or stopping.
signal pack_switched(soldier_id: int, on: bool)
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
	if bots != null:
		bots.run_bots(delta)
	for id: int in ids:
		var source: CommandSource = sources.get(id)
		var command := source.make_command(delta) if source != null else PlayerCommand.new()
		if command.order != 0:
			ordered.emit(id, command.order, command.order_arg)
		entities[id].simulate(command, delta)
	_step_stations(delta, ids)
	_step_projectiles(delta)
	_step_mines(delta)
	_step_flags(delta)


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
	if bots != null:
		bots.run_bots(delta)
	Prof.add("bots", Time.get_ticks_usec() - t)
	for id: int in ids:
		var source: CommandSource = sources.get(id)
		t = Time.get_ticks_usec()
		var command := source.make_command(delta) if source != null else PlayerCommand.new()
		Prof.add("bots" if source is BotBrain else "other_sources", Time.get_ticks_usec() - t)
		if command.order != 0:
			ordered.emit(id, command.order, command.order_arg)
		t = Time.get_ticks_usec()
		entities[id].simulate(command, delta)
		Prof.add("soldier_sim", Time.get_ticks_usec() - t)
	_step_stations(delta, ids)
	t = Time.get_ticks_usec()
	_step_projectiles(delta)
	Prof.add("projectiles", Time.get_ticks_usec() - t)
	Prof.count("projectiles_live", projectiles.size())
	_step_mines(delta)
	t = Time.get_ticks_usec()
	_step_flags(delta)
	Prof.add("flags", Time.get_ticks_usec() - t)
	Prof.add("tick", Time.get_ticks_usec() - t0)


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
func add_station(team: int, at: Vector3) -> InventoryStation:
	var station := InventoryStation.new()
	station.entity_id = next_id
	next_id += 1
	station.team = team
	station.position = at
	add_child(station)
	stations[station.entity_id] = station
	return station


## The station a soldier is standing on, or null.
func station_under(who: Soldier) -> InventoryStation:
	for id: int in stations:
		if stations[id].holds(who):
			return stations[id]
	return null


## Each station counts down its cooldowns, then puts the wanted loadout on
## each soldier that just stepped on (once its cooldown is over) and on each
## one on the pad whose wanted loadout differs from what it wears.
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
		var now: Array[int] = []
		for id: int in ids:
			var who := soldier(id)
			if who != null and station.holds(who):
				now.append(id)
		for id in now:
			var who := soldier(id)
			var entered := not station.on.has(id)
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
func start_clock() -> void:
	time_left = settings.time_limit


func carried_flag(soldier_id: int) -> Flag:
	for team in flags:
		var flag := flags[team]
		if flag.mode == Flag.Mode.CARRIED and flag.carrier_id == soldier_id:
			return flag
	return null


func _touching(who: Soldier, point: Vector3, reach: float) -> bool:
	return not who.dead and who.distance_to_body(point) <= reach


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
		for id: int in ids:
			var who := soldier(id)
			if who == null or not _touching(who, flag.global_position, settings.flag_touch_range):
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
		if _touching(carrier, stands[carrier.team], settings.stand_touch_range):
			_capture(flag, carrier)
			if over:
				return
	if not over:
		time_left = maxf(time_left - delta, 0.0)
		if time_left <= 0.0:
			_end(-1 if scores[0] == scores[1] else (0 if scores[0] > scores[1] else 1))


func _take_flag(flag: Flag, who: Soldier) -> void:
	flag.mode = Flag.Mode.CARRIED
	flag.carrier_id = who.entity_id
	flag.return_in = 0.0
	flag.hold_on(who)
	flag_taken.emit(flag.team, who.entity_id)


## The carrier lets go where it is, with its velocity.
func _drop_flag(flag: Flag, carrier: Soldier) -> void:
	var by := flag.carrier_id
	var spin := Vector3(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
	flag.drop(carrier.velocity if carrier != null else Vector3.ZERO, spin, settings.flag_return_time)
	flag_dropped.emit(flag.team, by)


func _return_flag(flag: Flag, by: int) -> void:
	flag.send_home()
	flag_returned.emit(flag.team, by)


func _capture(flag: Flag, carrier: Soldier) -> void:
	flag.send_home()
	scores[carrier.team] += 1
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
		if Prof.on:
			Prof.count("ray_by_projectile")
		# A thrown mine passes through soldiers and sticks to the world.
		var is_mine := shot.weapon == Weapon.MINE
		var hit := world_ray(shot.position, to, WORLD_LAYER if is_mine else WORLD_LAYER | SOLDIER_LAYER, exclude)
		shot.age += delta
		if is_mine:
			if not hit.is_empty():
				_place_mine(shot, hit.position, hit.normal)
			elif shot.age < weapon.lifetime:
				shot.position = to
				kept.append(shot)
		elif not hit.is_empty():
			var victim := hit.collider as Soldier
			var normal: Vector3 = hit.normal
			if victim == null and shot.bounces_left != 0:
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
				_impact(shot, hit.position + normal * 0.05, normal, victim)
		elif weapon.fuse > 0.0 and shot.age >= weapon.fuse:
			_impact(shot, to, Vector3.UP, null)
		elif shot.age >= weapon.lifetime:
			pass
		else:
			shot.position = to
			kept.append(shot)
	projectiles = kept


func _impact(shot: Projectile, at: Vector3, normal: Vector3, victim: Soldier) -> void:
	var weapon := Weapon.all[shot.weapon]
	shot.position = at
	impacted.emit(weapon.slot, at, normal)
	# A shot with no direct damage, like a grenade, just blows up on the
	# soldier it hits.
	var direct := victim if victim != null and shot.damage > 0.0 else null
	if direct != null:
		var push := shot.velocity.normalized() * weapon.hit_impulse
		if weapon.splash_radius > 0.0:
			push = (direct.centre() - at).normalized() * weapon.splash_impulse
		direct.push(push)
		var from := at
		var attacker := soldier(shot.shooter)
		if attacker != null:
			from = attacker.global_position
		damage(direct, shot.damage, shot.shooter, weapon.slot, from)
	if weapon.splash_radius > 0.0:
		explode(at, weapon.slot, shot.shooter, direct)


## A blast from a weapon at a point: splash damage and a push on every living
## soldier in range that the blast can see, less for those further away.
func explode(at: Vector3, weapon_slot: int, attacker_id: int, skip: Soldier = null, attacker_team := -1) -> void:
	var weapon := Weapon.all[weapon_slot]
	# With the attacker gone, its team still takes no damage, as in damage().
	var orphan_team := attacker_team if soldier(attacker_id) == null else -1
	var ids := entities.keys()
	ids.sort()
	for id: int in ids:
		var target := soldier(id)
		if target == null or target == skip or target.dead:
			continue
		var distance := target.distance_to_body(at)
		if distance > weapon.splash_radius:
			continue
		# Walls and ground between the blast and the soldier block it.
		if Prof.on:
			Prof.count("ray_by_blast")
		if not line_clear(at, target.centre()):
			continue
		var away := target.centre() - at
		away = away.normalized() if away.length() > 0.01 else Vector3.UP
		target.push(away * weapon.splash_impulse_at(distance))
		if target.team == orphan_team:
			continue
		damage(target, weapon.splash_damage_at(distance), attacker_id, weapon_slot, at)
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
	elif attacker != null and attacker.team == victim.team:
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
	damaged.emit(victim.entity_id, attacker_id, amount, from)
	if victim.health <= 0.0:
		victim.die()
		var held := carried_flag(victim.entity_id)
		if held != null:
			_drop_flag(held, victim)
		killed.emit(victim.entity_id, attacker_id, weapon_slot)


## The nearest hurt living teammate a soldier is looking towards, within
## reach metres of its eye and not behind a wall, or null.
func repair_target(healer: Soldier, reach: float) -> Soldier:
	var eye := healer.eye_transform()
	var ahead := -eye.basis.z
	var best: Soldier = null
	var best_distance := reach
	var ids := entities.keys()
	ids.sort()
	for id: int in ids:
		var other := soldier(id)
		if other == null or other == healer or other.dead or other.team != healer.team or other.health >= other.tuning.health_max:
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
	return best


## Puts a dead soldier back at one of its team's spawn points, picked with the
## match's random numbers.
func respawn(target: Soldier) -> void:
	var points: Array = spawns.get(target.team, [])
	var where := Transform3D(Basis.IDENTITY, target.global_position)
	if not points.is_empty():
		where = points[rng.randi_range(0, points.size() - 1)]
	target.revive(where)
	var source: CommandSource = sources.get(target.entity_id)
	if source != null:
		source.yaw = target.yaw
		source.pitch = 0.0
	respawned.emit(target.entity_id)


func get_state() -> Dictionary:
	var states := {}
	for id: int in entities:
		states[id] = entities[id].get_state()
	var shots := []
	for shot in projectiles:
		shots.append(shot.get_state())
	var source_states := {}
	for id: int in sources:
		var source_state := sources[id].get_state()
		if not source_state.is_empty():
			source_states[id] = source_state
	var flag_states := {}
	for team in flags:
		flag_states[team] = flags[team].get_state()
	var station_states := {}
	for id: int in stations:
		station_states[id] = stations[id].get_state()
	return {
		"scores": scores.duplicate(),
		"time_left": time_left,
		"over": over,
		"winner": winner,
		"stands": stands.duplicate(),
		"flags": flag_states,
		"stations": station_states,
		"tick": tick,
		"seed": seed_value,
		"rng_state": rng.state,
		"next_id": next_id,
		"entities": states,
		"projectiles": shots,
		"mines": mines.map(func(mine: Mine) -> Dictionary: return mine.get_state()),
		"sources": source_states,
	}


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
	var station_states: Dictionary = state.get("stations", {})
	for id: int in station_states:
		if not stations.has(id):
			var made := InventoryStation.new()
			made.entity_id = id
			made.team = station_states[id].team
			made.position = station_states[id].position
			add_child(made)
			stations[id] = made
		stations[id].set_state(station_states[id])
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
