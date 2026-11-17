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

signal fired(soldier_id: int, weapon: int)
## A soldier took damage. from is where it came from: the blast or the shooter.
signal damaged(victim_id: int, attacker_id: int, amount: float, from: Vector3)
signal killed(victim_id: int, killer_id: int, weapon: int)
## A projectile hit something or blew up. normal is the surface's.
signal impacted(weapon: int, position: Vector3, normal: Vector3)
signal respawned(soldier_id: int)

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
## Team to the places its soldiers respawn. Set from the map.
var spawns: Dictionary[int, Array] = {}


func _init(match_seed := 1) -> void:
	seed_value = match_seed
	rng.seed = match_seed
	name = "Match"


func _physics_process(delta: float) -> void:
	if running:
		step(delta)


func step(delta: float) -> void:
	tick += 1
	var ids := entities.keys()
	ids.sort()
	for id: int in ids:
		var source: CommandSource = sources.get(id)
		var command := source.make_command(delta) if source != null else PlayerCommand.new()
		entities[id].simulate(command, delta)
	_step_projectiles(delta)


func add_soldier(team: int, spawn: Transform3D, source: CommandSource = null) -> Soldier:
	var soldier := Soldier.new()
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
	var weapon := Weapon.all[shooter.weapon]
	var eye := shooter.eye_transform()
	var dir := -eye.basis.z
	if weapon.spread > 0.0:
		# An even spread over the cone's disc.
		var angle := rng.randf() * TAU
		var off := sqrt(rng.randf()) * tan(weapon.spread)
		dir = (dir + (eye.basis.x * cos(angle) + eye.basis.y * sin(angle)) * off).normalized()
	var shot := Projectile.new()
	shot.id = next_id
	next_id += 1
	shot.weapon = weapon.slot
	shot.shooter = shooter.entity_id
	shot.team = shooter.team
	shot.position = eye.origin
	shot.velocity = dir * weapon.speed + shooter.velocity * weapon.inherit
	shot.muzzle_offset = eye.basis * Soldier.MUZZLE
	projectiles.append(shot)
	fired.emit(shooter.entity_id, weapon.slot)


## Moves every shot along its path for one tick, with a ray cast over the
## whole step so even the fastest can't pass through anything.
func _step_projectiles(delta: float) -> void:
	if projectiles.is_empty():
		return
	var space := get_world_3d().direct_space_state
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
		var query := PhysicsRayQueryParameters3D.create(shot.position, to, WORLD_LAYER | SOLDIER_LAYER, exclude)
		var hit := space.intersect_ray(query)
		shot.age += delta
		if not hit.is_empty():
			var victim := hit.collider as Soldier
			var normal: Vector3 = hit.normal
			_impact(shot, hit.position + normal * 0.05, normal, victim)
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
	if victim != null:
		var push := shot.velocity.normalized() * weapon.hit_impulse
		if weapon.splash_radius > 0.0:
			push = (victim.centre() - at).normalized() * weapon.splash_impulse
		victim.push(push)
		var from := at
		var attacker := soldier(shot.shooter)
		if attacker != null:
			from = attacker.global_position
		damage(victim, weapon.damage, shot.shooter, weapon.slot, from)
	if weapon.splash_radius > 0.0:
		explode(at, weapon.slot, shot.shooter, victim)


## A blast from a weapon at a point: splash damage and a push on every living
## soldier in range that the blast can see, less for those further away.
func explode(at: Vector3, weapon_slot: int, attacker_id: int, skip: Soldier = null) -> void:
	var weapon := Weapon.all[weapon_slot]
	var space := get_world_3d().direct_space_state
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
		var query := PhysicsRayQueryParameters3D.create(at, target.centre(), WORLD_LAYER)
		if not space.intersect_ray(query).is_empty():
			continue
		var away := target.centre() - at
		away = away.normalized() if away.length() > 0.01 else Vector3.UP
		target.push(away * weapon.splash_impulse_at(distance))
		damage(target, weapon.splash_damage_at(distance), attacker_id, weapon_slot, at)


## Takes health off a soldier, less for your own shots and none from your
## teammates', and kills it at zero.
func damage(victim: Soldier, amount: float, attacker_id: int, weapon_slot: int, from: Vector3) -> void:
	if victim.dead or amount <= 0.0:
		return
	var attacker := soldier(attacker_id)
	if attacker_id == victim.entity_id:
		amount *= Weapon.all[weapon_slot].self_damage_share
	elif attacker != null and attacker.team == victim.team:
		return
	victim.health = maxf(victim.health - amount, 0.0)
	damaged.emit(victim.entity_id, attacker_id, amount, from)
	if victim.health <= 0.0:
		victim.die()
		killed.emit(victim.entity_id, attacker_id, weapon_slot)


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
	return {
		"tick": tick,
		"seed": seed_value,
		"rng_state": rng.state,
		"next_id": next_id,
		"entities": states,
		"projectiles": shots,
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
	projectiles.clear()
	for shot_state: Dictionary in state.get("projectiles", []):
		projectiles.append(Projectile.from_state(shot_state))
