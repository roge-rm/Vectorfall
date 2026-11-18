class_name BotPerception
extends RefCounted

## What one bot knows about the enemy soldiers: those it has seen in its view
## cone with nothing in the way, heard firing or jetting nearby, or seen
## before. Each contact keeps a last known position and velocity, and fades
## from memory when it's neither seen nor heard for a while. A soldier coming
## into view is only noticed after the bot's reaction time. Line of sight
## takes ray casts from the director's budget, shared by every bot each tick.

const VIEW_RANGE := 300.0
## Half the view cone's angle, 65°.
const VIEW_HALF_ANGLE := 1.134
## Closer than this a soldier is seen whichever way the bot faces, if
## nothing's in the way.
const NEAR_SENSE := 6.0
## Seconds a contact is remembered after it was last seen or heard.
const SEEN_MEMORY := 10.0
const HEARD_MEMORY := 5.0
## Jets are heard this far away.
const JET_RANGE := 40.0
## Seconds ahead a remembered velocity is used to guess where a contact is.
const PREDICT_LIMIT := 2.0

## Seconds from a soldier coming into view to the bot noticing it.
var reaction_time := 0.4
## How far the bot sees, in metres, from its skill.
var view_range := VIEW_RANGE
## Soldier id to { position, velocity, tick, visible, since, noticed, heard }.
## tick is when it was last seen or heard, since when it came into view, or -1
## while it's out of view.
var contacts: Dictionary = {}
## Where to start checking line of sight next think, so a budget that runs
## out part way gets to everyone in turn.
var cursor := 0
## The director's count of sounds when they were last read.
var heard_up_to := 0
## The last blast heard, and when, with tick -1 for none.
var danger_at := Vector3.ZERO
var danger_tick := -1


## Looks and listens. Called when the bot thinks.
func update(me: Soldier, game: Match, director: BotDirector) -> void:
	var now := game.tick
	var eye := me.eye_transform()
	var forward := -eye.basis.z
	var enemies: Array[Soldier] = []
	var ids := game.entities.keys()
	ids.sort()
	for id: int in ids:
		var other := game.soldier(id)
		if other != null and other.team != me.team and not other.dead:
			enemies.append(other)
	var count := enemies.size()
	var checked := 0
	for k in count:
		var other := enemies[(cursor + k) % count]
		var to := other.global_position + Vector3.UP * 1.2 - eye.origin
		var distance := to.length()
		var in_view := distance < NEAR_SENSE or (distance < view_range and forward.angle_to(to) < VIEW_HALF_ANGLE)
		if in_view:
			if not director.take_ray():
				break
			in_view = game.line_clear(eye.origin, eye.origin + to)
		checked += 1
		if in_view:
			_see(other, now)
		elif contacts.has(other.entity_id):
			contacts[other.entity_id].visible = false
			contacts[other.entity_id].since = -1
	if count > 0:
		cursor = (cursor + checked) % count
	# Jets nearby.
	for other in enemies:
		if other.jetting and other.global_position.distance_to(me.global_position) < JET_RANGE:
			_hear(other.entity_id, other.global_position, other.velocity, now)
	# Shots and blasts since the last think.
	for sound: Dictionary in director.sounds:
		if sound.seq <= heard_up_to or me.global_position.distance_to(sound.position) > sound.range:
			continue
		var source := game.soldier(sound.source)
		if source != null and source.team != me.team:
			_hear(source.entity_id, sound.position, Vector3.ZERO, sound.tick)
		elif source == null:
			danger_at = sound.position
			danger_tick = sound.tick
	heard_up_to = director.sound_count
	# Gone dead or out of memory.
	for id: int in contacts.keys():
		var contact: Dictionary = contacts[id]
		var other := game.soldier(id)
		var memory := SEEN_MEMORY if not contact.heard or contact.since >= 0 else HEARD_MEMORY
		if other == null or other.dead or (now - contact.tick) / 60.0 > memory:
			contacts.erase(id)


func _see(other: Soldier, now: int) -> void:
	var contact: Dictionary = contacts.get(other.entity_id, {})
	if contact.is_empty():
		contact = { "noticed": false, "since": -1 }
		contacts[other.entity_id] = contact
	if contact.since < 0:
		contact.since = now
	contact.position = other.global_position
	contact.velocity = other.velocity
	contact.tick = now
	contact.visible = true
	contact.heard = false
	if (now - contact.since) / 60.0 >= reaction_time:
		contact.noticed = true


## How far a bot sees at a skill from 0 to 1: three quarters of VIEW_RANGE
## for a beginner, all of it at normal (0.5) and a quarter more for an expert.
static func view_range_for(skill: float) -> float:
	return VIEW_RANGE * (0.75 + 0.5 * skill)


## Reaction time at a skill from 0 for a beginner to 1 for an expert, in
## seconds.
static func reaction_for(skill: float) -> float:
	return lerpf(0.7, 0.15, skill)


## Learns where a soldier is from a sound or a hit.
func hear(id: int, at: Vector3, velocity: Vector3, tick: int) -> void:
	_hear(id, at, velocity, tick)


func _hear(id: int, at: Vector3, velocity: Vector3, tick: int) -> void:
	var contact: Dictionary = contacts.get(id, {})
	if not contact.is_empty() and contact.visible:
		return
	if contact.is_empty():
		contact = { "since": -1, "visible": false }
		contacts[id] = contact
	contact.position = at
	contact.velocity = velocity
	contact.tick = tick
	contact.noticed = true
	contact.heard = true


## True if the bot knows about this soldier: noticed, and not yet forgotten.
func knows(id: int) -> bool:
	return contacts.has(id) and contacts[id].noticed


func can_see(id: int) -> bool:
	return knows(id) and contacts[id].visible


## How sure the bot is of where this soldier is, from 1 just seen to 0
## forgotten.
func confidence(id: int, now: int) -> float:
	if not contacts.has(id):
		return 0.0
	var contact: Dictionary = contacts[id]
	var memory := HEARD_MEMORY if contact.heard else SEEN_MEMORY
	return clampf(1.0 - (now - contact.tick) / 60.0 / memory, 0.0, 1.0)


## Where the bot thinks this soldier is now, from where it was last seen or
## heard and how it was moving.
func guess_position(id: int, now: int) -> Vector3:
	var contact: Dictionary = contacts[id]
	var age := minf((now - contact.tick) / 60.0, PREDICT_LIMIT)
	return contact.position + contact.velocity * age


func known_count() -> int:
	var n := 0
	for id: int in contacts:
		if contacts[id].noticed:
			n += 1
	return n


func get_state() -> Dictionary:
	return {
		"contacts": contacts.duplicate(true),
		"cursor": cursor,
		"heard_up_to": heard_up_to,
		"danger_at": danger_at,
		"danger_tick": danger_tick,
		"reaction_time": reaction_time,
		"view_range": view_range,
	}


func set_state(state: Dictionary) -> void:
	contacts = state.contacts.duplicate(true)
	cursor = state.cursor
	heard_up_to = state.heard_up_to
	danger_at = state.danger_at
	danger_tick = state.danger_tick
	reaction_time = state.reaction_time
	view_range = state.get("view_range", VIEW_RANGE)
