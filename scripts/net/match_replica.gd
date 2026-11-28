class_name MatchReplica
extends RefCounted

const SNAP_SECONDS := 4.0 / 60.0
const MAX_PREDICTION := 12
const SMOOTH_DISTANCE := 12.0
const SIGNALS := ["fired", "impacted", "damaged", "killed", "air_hit", "hit", "shield_hit",
	"flag_taken", "flag_dropped", "flag_captured", "flag_returned", "carrier_stopped",
	"power_lost", "power_back", "station_entered", "resupplied", "turret_fired", "asset_destroyed", "asset_damaged",
	"mine_placed", "mine_armed", "pack_switched", "landed", "vehicle_crashed"]

var client: OnlineClient
var game: Match
var player: Soldier
var last_tick := 0
var round_id := 0
var remote_poses := {}
var hull_poses := {}
var flag_poses := {}
var shot_origins := {}
var elapsed := 0.0


func start(connection: OnlineClient, match_node: Match) -> void:
	client = connection
	round_id = client.round_id
	game = match_node
	game.running = false
	game.set_state(client.initial)
	player = game.soldier(client.player_id)
	last_tick = game.tick
	_names(client.initial)
	_freeze_flags()
	game.prepare_terrain()


func advance(command: PlayerCommand) -> void:
	if client.round_id != round_id:
		return
	if not client.latest.is_empty() and client.latest.tick > last_tick:
		_apply(client.latest)
	if game.over:
		return
	client.submit(command)
	_predict(command)


func _apply(state: Dictionary) -> void:
	var was_over := game.over
	var local_position := player.global_position
	var old_vehicle := player.vehicle_id
	var old_dead := player.dead
	var soldiers := {}
	var hulls := {}
	var flags := {}
	var shots := {}
	for id: int in game.entities:
		var who := game.soldier(id)
		if who != player:
			soldiers[id] = who.global_transform
	for id: int in game.fleet.hulls:
		hulls[id] = game.fleet.hulls[id].global_transform
	for team: int in game.flags:
		var flag := game.flags[team]
		if flag.mode == Flag.Mode.DROPPED:
			flags[team] = flag.global_transform
	for shot in game.projectiles:
		shots[shot.id] = projectile_position(shot)
	game.set_state(state)
	_names(state)
	_freeze_flags()
	game.prepare_terrain()
	last_tick = game.tick
	elapsed = 0.0
	remote_poses.clear()
	hull_poses.clear()
	flag_poses.clear()
	shot_origins = shots
	for id: int in soldiers:
		var who := game.soldier(id)
		if soldiers[id].origin.distance_to(who.global_position) < SMOOTH_DISTANCE:
			remote_poses[id] = [soldiers[id], who.global_transform]
	for id: int in hulls:
		if game.fleet.hulls.has(id):
			var hull := game.fleet.hulls[id]
			if hulls[id].origin.distance_to(hull.global_position) < SMOOTH_DISTANCE:
				hull_poses[id] = [hulls[id], hull.global_transform]
	for team: int in flags:
		var flag := game.flags[team]
		if flag.mode == Flag.Mode.DROPPED and flags[team].origin.distance_to(flag.global_position) < SMOOTH_DISTANCE:
			flag_poses[team] = [flags[team], flag.global_transform]
	var history := client.pending()
	if not game.over:
		for entry in history.slice(maxi(0, history.size() - MAX_PREDICTION)):
			_predict(PlayerCommand.from_dict(entry[1]))
		if old_vehicle == 0 and player.vehicle_id == 0 and old_dead == player.dead:
			if local_position.distance_to(player.global_position) < 1.0:
				player.global_position = player.global_position.lerp(local_position, 0.35)
	render(0.0)
	if game.over and not was_over:
		game.match_over.emit(game.winner)


func render(delta: float) -> void:
	elapsed += delta
	var weight := clampf(elapsed / SNAP_SECONDS, 0.0, 1.0)
	for id: int in remote_poses:
		var pose: Array = remote_poses[id]
		game.entities[id].global_transform = pose[0].interpolate_with(pose[1], weight)
	for id: int in hull_poses:
		var pose: Array = hull_poses[id]
		game.fleet.hulls[id].global_transform = pose[0].interpolate_with(pose[1], weight)

	for team: int in game.flags:
		var flag := game.flags[team]
		if flag.mode == Flag.Mode.CARRIED:
			var carrier := game.soldier(flag.carrier_id)
			if carrier != null:
				flag.hold_on(carrier)
		elif flag_poses.has(team):
			var pose: Array = flag_poses[team]
			flag.global_transform = pose[0].interpolate_with(pose[1], weight)


func projectile_position(shot: Projectile) -> Vector3:
	var target := shot.visual_position()
	var start: Vector3 = shot_origins.get(shot.id, target - shot.velocity * minf(SNAP_SECONDS, shot.age))
	return start.lerp(target, clampf(elapsed / SNAP_SECONDS, 0.0, 1.0))


func events(voice: Callable) -> void:
	if client.round_id != round_id:
		return
	while not client.messages.is_empty() and client.messages.front().tick <= last_tick:
		var batch: Dictionary = client.messages.pop_front()
		for event in batch.events:
			if not event is Array or event.is_empty():
				continue
			if event[0] == "chat" and event.size() == 5:
				voice.callv(event.slice(1))
			elif event[0] in SIGNALS:
				game.callv(&"emit_signal", event)


func _predict(command: PlayerCommand) -> void:
	if player.dead:
		return
	if player.vehicle_id == 0:
		player.simulate(command, OnlineClient.STEP, true)
	else:
		player.yaw = command.yaw
		player.pitch = command.pitch


func _names(state: Dictionary) -> void:
	var humans: Dictionary = state.get("humans", {})
	var bot_names: Dictionary = client.initial.get("bot_names", {})
	for id: int in game.entities:
		var who := game.soldier(id)
		who.display_name = "You" if who == player else humans.get(id, bot_names.get(id, "Bot %d" % id))


func _freeze_flags() -> void:
	for flag: Flag in game.flags.values():
		flag.freeze = true
