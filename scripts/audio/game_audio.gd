class_name GameAudio
extends Node3D

## A match's sounds. It hears the match's signals and reads the soldiers, and
## never changes either. World sounds (shots, blasts) are placed in 3D on a
## pool of VOICES players: when they're all busy a new sound takes the one
## that started longest ago, or is dropped if it matters less. Your own jet,
## skis, footsteps and landings, repair hum, pack switches, hit markers and
## flag and base power jingles play flat. The
## jets of the JET_VOICES nearest other soldiers loop in 3D, and so does each
## working generator's hum, heard only close by.

const VOICES := 10
const JET_VOICES := 3
const FLAT_VOICES := 4
## How far world sounds carry, in metres.
const REACH := 260.0
const STEP_TIME := 0.33
## Each weapon's firing sound and its hit or blast sound, by slot. The
## chaingun's hits make no sound.
const FIRE_SOUNDS: Array[String] = ["disc_fire", "chaingun", "grenade_fire", "mortar_fire", "plasma_fire", "sniper_fire", "blaster_fire", "throw", "throw", "turret_fire"]
const HIT_SOUNDS: Array[String] = ["disc_blast", "", "grenade_blast", "mortar_blast", "plasma_hit", "blaster_hit", "blaster_hit", "hand_grenade_blast", "mine_blast", "plasma_hit"]
## Seconds between one soldier's chaingun sounds, so a burst doesn't take
## every voice.
const CHAINGUN_GAP := 0.06

var game: Match
var soldier: Soldier
var _pool: Array[AudioStreamPlayer3D] = []
## Milliseconds of play: it stops while the game is paused, like the players.
var _clock := 0
## When each pool voice started and finishes, on _clock, and how much it matters.
var _started: Array[int] = []
var _ends: Array[int] = []
var _priority: Array[int] = []
var _flat: Array[AudioStreamPlayer] = []
var _next_flat := 0
var _jet: AudioStreamPlayer
var _ski: AudioStreamPlayer
var _repair: AudioStreamPlayer
var _jets: Array[AudioStreamPlayer3D] = []
## Each generator's hum, by its asset.
var _hums: Dictionary[Object, AudioStreamPlayer3D] = {}
var _step_left := 0.0
var _was_grounded := true
var _fall_speed := 0.0
var _last_chaingun: Dictionary[int, int] = {}
## Sounds dropped because every voice was busy with something that mattered more.
var dropped := 0


func _init() -> void:
	name = "GameAudio"
	SoundBank.build()
	Sound.make_buses()
	for k in VOICES:
		var player := AudioStreamPlayer3D.new()
		player.bus = Sound.EFFECTS_BUS
		player.max_distance = REACH
		player.unit_size = 12.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(player)
		_pool.append(player)
		_started.append(0)
		_ends.append(0)
		_priority.append(0)
	for k in FLAT_VOICES:
		var flat := AudioStreamPlayer.new()
		flat.bus = Sound.EFFECTS_BUS
		add_child(flat)
		_flat.append(flat)
	_jet = _loop_player("jet")
	_ski = _loop_player("ski")
	_repair = _loop_player("repair")
	for k in JET_VOICES:
		var jet := AudioStreamPlayer3D.new()
		jet.bus = Sound.EFFECTS_BUS
		jet.stream = SoundBank.get_stream("jet")
		jet.max_distance = 120.0
		jet.unit_size = 6.0
		jet.volume_db = -10.0
		add_child(jet)
		_jets.append(jet)


func _loop_player(sound_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = Sound.EFFECTS_BUS
	player.stream = SoundBank.get_stream(sound_name)
	add_child(player)
	return player


## Listens to a match, with you as `who`.
func watch(match_node: Match, who: Soldier) -> void:
	game = match_node
	soldier = who
	game.fired.connect(_on_fired)
	game.impacted.connect(_on_impacted)
	game.hit.connect(_on_hit)
	game.mine_placed.connect(_on_mine.bind("mine_place", -4.0))
	game.mine_armed.connect(_on_mine.bind("mine_arm", -8.0))
	game.pack_switched.connect(_on_pack_switched)
	game.shield_hit.connect(_on_shield_hit)
	game.flag_taken.connect(_on_flag.bind("taken"))
	game.flag_dropped.connect(_on_flag.bind("dropped"))
	game.flag_returned.connect(_on_flag.bind("returned"))
	game.flag_captured.connect(_on_flag.bind("captured"))
	game.power_lost.connect(_on_power.bind("power_down"))
	game.power_back.connect(_on_power.bind("power_up"))
	game.turret_fired.connect(_on_turret_fired)
	game.asset_destroyed.connect(_on_asset_destroyed)
	for id: int in game.assets:
		var made := game.assets[id]
		if made.kind != BaseAsset.Kind.GENERATOR:
			continue
		var hum := AudioStreamPlayer3D.new()
		hum.bus = Sound.EFFECTS_BUS
		hum.stream = SoundBank.get_stream("generator_hum")
		hum.max_distance = 22.0
		hum.unit_size = 3.0
		hum.volume_db = -14.0
		add_child(hum)
		hum.global_position = made.centre()
		_hums[made] = hum


func _on_power(_team: int, sound_name: String) -> void:
	if soldier != null:
		play_flat(sound_name, -4.0)


func _on_turret_fired(asset_id: int) -> void:
	var turret := game.asset(asset_id)
	if turret != null:
		play_at("turret_fire", turret.pivot(), -4.0, 1)


func _on_asset_destroyed(asset_id: int, _attacker_id: int) -> void:
	var made := game.asset(asset_id)
	if made != null:
		play_at("asset_destroyed", made.centre(), 0.0, 3)


func _on_mine(_mine_id: int, at: Vector3, sound_name: String, volume_db: float) -> void:
	play_at(sound_name, at, volume_db, 1)


## Plays a sound at a point on a free voice, or the oldest one if they're all
## busy and it matters as much. False if it was dropped.
func play_at(sound_name: String, at: Vector3, volume_db := 0.0, priority := 1, pitch := 1.0) -> bool:
	var now := _clock
	var pick := -1
	var oldest := now + 1
	for k in VOICES:
		if _ends[k] <= now:
			pick = k
			break
		if _priority[k] <= priority and _started[k] < oldest:
			oldest = _started[k]
			pick = k
	if pick == -1:
		dropped += 1
		return false
	var stream := SoundBank.get_stream(sound_name)
	var player := _pool[pick]
	player.stream = stream
	player.global_position = at
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()
	_started[pick] = now
	_ends[pick] = now + int(stream.get_length() * 1000.0 / pitch) + 1
	_priority[pick] = priority
	return true


## Voices busy now.
func voices_in_use() -> int:
	var now := _clock
	var busy := 0
	for k in VOICES:
		if _ends[k] > now:
			busy += 1
	return busy


## A sound with no place, for your own things and the flag jingles.
func play_flat(sound_name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var player := _flat[_next_flat]
	_next_flat = (_next_flat + 1) % FLAT_VOICES
	player.stream = SoundBank.get_stream(sound_name)
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func _on_fired(soldier_id: int, weapon: int) -> void:
	var who := game.soldier(soldier_id)
	if who == null:
		return
	var at := who.eye_transform().origin
	if weapon == Weapon.CHAINGUN:
		var now := _clock
		if now - _last_chaingun.get(soldier_id, -1000) < int(CHAINGUN_GAP * 1000.0):
			return
		_last_chaingun[soldier_id] = now
		play_at("chaingun", at, -4.0 if who == soldier else -6.0, 0, 0.95 + 0.1 * randf())
	elif weapon == Weapon.BLASTER or weapon == Weapon.HAND_GRENADE or weapon == Weapon.MINE:
		play_at(FIRE_SOUNDS[weapon], at, -6.0, 1 if who == soldier else 0)
	else:
		play_at(FIRE_SOUNDS[weapon], at, -2.0, 2 if who == soldier else 1)


## A click up or down for a shield or jammer going on or off. The repair
## pack has its hum instead.
func _on_pack_switched(soldier_id: int, on: bool) -> void:
	var who := game.soldier(soldier_id)
	if who == null or who.loadout.pack == Pack.REPAIR:
		return
	var sound_name := "pack_on" if on else "pack_off"
	if who == soldier:
		play_flat(sound_name, -8.0)
	else:
		play_at(sound_name, who.centre(), -10.0, 0)


func _on_shield_hit(victim_id: int, _amount: float, _from: Vector3) -> void:
	var who := game.soldier(victim_id)
	if who == null:
		return
	if who == soldier:
		play_flat("shield_hit", -6.0, 0.95 + 0.1 * randf())
	else:
		play_at("shield_hit", who.centre(), -4.0, 1, 0.95 + 0.1 * randf())


func _on_impacted(weapon: int, at: Vector3, _normal: Vector3) -> void:
	var sound := HIT_SOUNDS[weapon]
	if sound.is_empty():
		return
	# Blasts matter most; small hits only take a free voice.
	var priority := 3 if Weapon.all[weapon].splash_radius > 0.0 else 0
	play_at(sound, at, 0.0 if priority == 3 else -6.0, priority)


func _on_hit(attacker_id: int, victim_id: int, _weapon: int) -> void:
	if soldier == null or attacker_id != soldier.entity_id or victim_id == attacker_id:
		return
	# The hit comes before the death, so a kill shows as no health left.
	var victim := game.soldier(victim_id)
	play_flat("kill" if victim != null and victim.health <= 0.0 else "hit", -6.0)


func _on_flag(team: int, _soldier_id: int, what: String) -> void:
	if soldier == null:
		return
	var ours := team == soldier.team
	match what:
		"taken":
			play_flat("flag_alarm" if ours else "flag_grab", -4.0)
		"dropped":
			play_flat("flag_dropped", -4.0)
		"returned":
			play_flat("flag_returned" if ours else "flag_dropped", -4.0)
		"captured":
			# team is the scorer's.
			play_flat("flag_captured" if ours else "flag_lost", -2.0)


func _process(delta: float) -> void:
	_clock += roundi(delta * 1000.0)
	if soldier == null or game == null:
		return
	_own_sounds(delta)
	_other_jets()
	_generator_hums()


func _own_sounds(delta: float) -> void:
	var alive := not soldier.dead
	var speed := Vector2(soldier.velocity.x, soldier.velocity.z).length()
	_set_loop(_jet, alive and soldier.jetting, -8.0, 1.0)
	_set_loop(_repair, alive and soldier.repair_target != 0, -12.0, 1.0 if soldier.repair_target == soldier.entity_id else 1.15)
	var skiing := alive and soldier.skiing and speed > 3.0
	# The hiss rises with speed.
	_set_loop(_ski, skiing, linear_to_db(clampf(speed / 40.0, 0.15, 1.0)) - 10.0, 0.8 + clampf(speed / 60.0, 0.0, 0.6))
	if not alive:
		_was_grounded = true
		return
	if soldier.grounded and not _was_grounded and _fall_speed > 6.0:
		play_flat("land", linear_to_db(clampf(_fall_speed / 25.0, 0.3, 1.0)) - 6.0)
		_step_left = STEP_TIME
	elif soldier.grounded and not soldier.skiing and speed > 2.0:
		_step_left -= delta
		if _step_left <= 0.0:
			_step_left = STEP_TIME
			play_flat("step", -14.0, 0.9 + 0.2 * randf())
	_was_grounded = soldier.grounded
	_fall_speed = maxf(-soldier.velocity.y, 0.0)


func _set_loop(player: AudioStreamPlayer, on: bool, volume_db: float, pitch: float) -> void:
	if on:
		player.volume_db = volume_db
		player.pitch_scale = pitch
		if not player.playing:
			player.play()
	elif player.playing:
		player.stop()


## The nearest other soldiers jetting get the 3D jet loops.
func _other_jets() -> void:
	var listener := soldier.global_position
	var jetting: Array[Soldier] = []
	for id: int in game.entities:
		var other := game.entities[id] as Soldier
		if other != null and other != soldier and other.jetting and not other.dead and other.global_position.distance_to(listener) < 120.0:
			jetting.append(other)
	jetting.sort_custom(func(a: Soldier, b: Soldier) -> bool: return a.global_position.distance_squared_to(listener) < b.global_position.distance_squared_to(listener))
	for k in JET_VOICES:
		var jet := _jets[k]
		if k < jetting.size():
			jet.global_position = jetting[k].global_position
			if not jet.playing:
				jet.play()
		elif jet.playing:
			jet.stop()


## Each generator hums while it's working and you're near enough to hear it.
func _generator_hums() -> void:
	for made: Variant in _hums:
		var hum: AudioStreamPlayer3D = _hums[made]
		var on := is_instance_valid(made) and not (made as BaseAsset).destroyed and (made as BaseAsset).global_position.distance_to(soldier.global_position) < hum.max_distance
		if on and not hum.playing:
			hum.play()
		elif not on and hum.playing:
			hum.stop()
