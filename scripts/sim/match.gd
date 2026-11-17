class_name Match
extends Node3D

## Owns the match state. Entities live under it with stable integer ids and
## only change in step(), once per physics tick, from their commands. The HUD
## and camera only read it.

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


func add_soldier(team: int, spawn: Transform3D, source: CommandSource = null) -> Soldier:
	var soldier := Soldier.new()
	soldier.entity_id = next_id
	next_id += 1
	soldier.team = team
	soldier.name = "Soldier%d" % soldier.entity_id
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


func get_state() -> Dictionary:
	var states := {}
	for id: int in entities:
		states[id] = entities[id].get_state()
	return {
		"tick": tick,
		"seed": seed_value,
		"rng_state": rng.state,
		"next_id": next_id,
		"entities": states,
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
			var soldier := Soldier.new()
			soldier.name = "Soldier%d" % id
			soldier.team = entity_state.team
			add_child(soldier)
			entities[id] = soldier
			sources[id] = CommandSource.new()
		entities[id].set_state(entity_state)
