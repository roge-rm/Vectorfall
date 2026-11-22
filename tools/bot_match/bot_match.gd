extends Node

## Plays a headless capture the flag match of bots only on a map, as
## fast as it can, and writes a report on how they moved, fought and played
## to build/bot-reports/. Run it with tools/bot-match.sh, which passes these
## after --:
##   --bots N      bots per team, 8 at most (8)
##   --seed N      the match seed (1)
##   --minutes N   simulated minutes (5)
##   --map NAME    any match map (ochre_fold)
##   --skill0 N    team 0's skill level, 0 beginner to 4 expert (2, normal)
##   --skill1 N    team 1's (2)
##   --plain       every bot the default personality
##   --no-base     no generators, turrets, sensors or force fields, for
##                 comparing
##   --no-raids    the commanders send no raids on the enemy base
##   --serial-bots bots work one after another on the main thread instead of
##                 on worker threads, for comparing; the match is the same
##   --profile     time each part of every tick and the map build, and print
##                 a table of them at the end
##   --check       print a CHECK line for tools/bot-check.sh, and exit with an
##                 error if the bots stopped moving: 60 s or more stuck
##   --track       report every bot's position and goal every 5 s
##   --vehicle-report   report reservations, trips and crew exits
## The capture limit is off, so the match runs the whole time. The report has
## each team's roles every 10 s and its commander's decisions.

const VehicleReport := preload("res://tools/bot_match/vehicle_report.gd")
const REPORTS := "res://build/bot-reports"

var map: GameMap
var game: Match
var director: BotDirector
var bots := 8
var seed_value := 1
var minutes := 5.0
var check := false
var skills: Array[int] = [BotDirector.NORMAL, BotDirector.NORMAL]
var plain := false
var no_base := false
var profile := false
var track := false
## Map build parts timed with --profile, name to microseconds, and counts.
var build_parts := {}
var build_counts := {}
## Every flag event, in order.
var flag_events: Array[Dictionary] = []
## Base assets destroyed and repaired back to working, by kind name, and
## every such event in order.
var destroyed := { "generator": 0, "turret": 0, "sensor": 0 }
var repaired := { "generator": 0, "turret": 0, "sensor": 0 }
var asset_events: Array[Dictionary] = []
var generator_hits: Array[Dictionary] = []
var runner_near_stand_seconds := [0, 0]
var runner_with_support_seconds := [0, 0]
var vehicle_boardings: Array[Dictionary] = []
var vehicle_ticks := {}
var _vehicle_report: VehicleReport
var tracked_positions: Array[Dictionary] = []
var _ridden_hulls := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	check = args.has("--check")
	plain = args.has("--plain")
	no_base = args.has("--no-base")
	TeamCommander.raids = not args.has("--no-raids")
	profile = args.has("--profile")
	track = args.has("--track")
	Prof.on = profile
	BotDirector.threads = not args.has("--serial-bots")
	for k in args.size() - 1:
		match args[k]:
			"--bots":
				bots = clampi(int(args[k + 1]), 1, 8)
			"--seed":
				seed_value = int(args[k + 1])
			"--minutes":
				minutes = float(args[k + 1])
			"--skill0":
				skills[0] = clampi(int(args[k + 1]), 0, BotDirector.SKILLS.size() - 1)
			"--skill1":
				skills[1] = clampi(int(args[k + 1]), 0, BotDirector.SKILLS.size() - 1)
	map = GameMap.make(GameMap.chosen_name())
	if profile:
		build_parts = Prof._now.duplicate()
		build_counts = Prof._counts.duplicate()
		Prof._now.clear()
		Prof._counts.clear()
	add_child(map)
	print("Map %s built in %.2f s, its route graph in %.2f s (%d points, %d links)" % [map.title, map.build_seconds, map.graph_seconds, map.route_graph.points.size(), map.route_graph.links.size()])
	game = Match.new(seed_value)
	game.terrain = map.terrain
	for team in 2:
		game.spawns[team] = map.spawn_points(team)
	for team in 2:
		game.add_flag(team, map.stand_point(team), map.flag_rest(team))
	for team in 2:
		for at in map.station_points(team):
			game.add_station(team, at)
		if not no_base:
			map.add_base_power(game, team)
			map.add_vehicle_pads(game, team)
	game.settings.capture_limit = 1000000
	game.settings.time_limit = minutes * 60.0 + 10.0
	game.start_clock()
	add_child(game)
	director = BotDirector.new(game, map.route_graph)
	if args.has("--vehicle-report"):
		_vehicle_report = VehicleReport.new(game, director)
	director.skill_levels.assign(skills)
	director.personalities = not plain
	for team in 2:
		for k in bots:
			var brain := director.add_bot(team, map.spawn_point(team, k))
			# Nothing's drawn, so the bodies needn't move their legs.
			brain.soldier.body.process_mode = Node.PROCESS_MODE_DISABLED
	game.killed.connect(_on_killed)
	for event in ["taken", "dropped", "returned", "captured"]:
		game.connect("flag_" + event, _on_flag_event.bind(event))
	game.asset_destroyed.connect(_on_asset_event.bind("destroyed"))
	game.asset_repaired.connect(_on_asset_event.bind("repaired"))
	game.asset_damaged.connect(_on_asset_damaged)
	var prepared := Time.get_ticks_usec()
	game.prepare_terrain()
	print("Terrain collision made for the start in %.0f ms" % ((Time.get_ticks_usec() - prepared) / 1000.0))
	Prof._now.clear()
	Prof._counts.clear()
	_run.call_deferred()


func _on_killed(victim_id: int, killer_id: int, weapon: int) -> void:
	if flag_events.is_empty():
		return
	var drop := flag_events[-1]
	if drop.event != "dropped" or drop.soldier != victim_id or drop.tick != game.tick:
		return
	var killer := game.soldier(killer_id)
	var role := ""
	var brain := director.brain_of(killer_id)
	if brain != null:
		role = BotBrain.ROLE_NAMES[brain.role] + " " + BotBrain.GOAL_NAMES[brain.goal]
	var distance := killer.global_position.distance_to(game.soldier(victim_id).global_position) if killer != null else 0.0
	drop["killed_by"] = [killer_id, role, Weapon.all[weapon].short_name, snappedf(distance, 0.1)]


func _on_flag_event(team: int, soldier_id: int, event: String) -> void:
	var at := Vector3.ZERO
	var s := game.soldier(soldier_id)
	if s != null:
		at = s.global_position
	flag_events.append({
		"tick": game.tick,
		"seconds": snappedf(game.tick / 60.0, 0.1),
		"event": event,
		"flag_team": team,
		"carried_flag_team": 1 - team if event == "captured" else team,
		"soldier": soldier_id,
		"health": snappedf(s.health, 1.0) if s != null else 0.0,
		"position": [snappedf(at.x, 0.1), snappedf(at.y, 0.1), snappedf(at.z, 0.1)],
		"speed": snappedf(s.velocity.length(), 0.1) if s != null else 0.0,
		"near": _near_counts(s) if s != null else [0, 0],
	})


func _on_asset_damaged(asset_id: int, attacker_id: int, amount: float, _from: Vector3) -> void:
	var machine := game.asset(asset_id)
	if machine.kind == BaseAsset.Kind.GENERATOR:
		generator_hits.append({"tick": game.tick, "team": machine.team, "attacker": attacker_id, "damage": amount})


func _observe_runner_support() -> void:
	for brain: BotBrain in director.brains:
		var who := brain.soldier
		var stand: Vector3 = game.stands[1 - who.team]
		if not brain.is_flag_runner() or who.dead or who.vehicle_id != 0 or who.at().distance_squared_to(stand) > 60.0 * 60.0:
			continue
		runner_near_stand_seconds[who.team] += 1
		for other: BotBrain in director.brains:
			var mate := other.soldier
			if mate != who and mate.team == who.team and not mate.dead and mate.vehicle_id == 0 and mate.at().distance_squared_to(who.at()) <= 60.0 * 60.0:
				runner_with_support_seconds[who.team] += 1
				break


func _track_bots() -> void:
	var sample := track and game.tick % 300 == 0
	var positions: Array[Dictionary] = []
	for brain in director.brains:
		var who := brain.soldier
		var hull: Vehicle = game.fleet.hulls.get(who.vehicle_id)
		if hull != null:
			var kind := Vehicle.NAMES[hull.kind]
			vehicle_ticks[kind] = int(vehicle_ticks.get(kind, 0)) + 1
			if _ridden_hulls.get(who.entity_id, 0) != hull.entity_id:
				vehicle_boardings.append({
					"seconds": snappedf(game.tick / 60.0, 0.1), "soldier": who.entity_id,
					"team": who.team, "vehicle": kind, "seat": who.vehicle_seat,
				})
		_ridden_hulls[who.entity_id] = who.vehicle_id
		if sample:
			var at := who.position.snapped(Vector3(0.1, 0.1, 0.1))
			positions.append({
				"soldier": who.entity_id, "team": who.team, "alive": not who.dead,
				"position": [at.x, at.y, at.z], "role": BotBrain.ROLE_NAMES[brain.role],
				"goal": BotBrain.GOAL_NAMES[brain.goal],
			})
	if sample:
		tracked_positions.append({ "seconds": game.tick / 60.0, "bots": positions })


func _on_asset_event(asset_id: int, soldier_id: int, event: String) -> void:
	var machine := game.asset(asset_id)
	var kind := BaseAsset.NAMES[machine.kind].to_lower()
	(destroyed if event == "destroyed" else repaired)[kind] += 1
	var brain := director.brain_of(soldier_id)
	asset_events.append({
		"seconds": snappedf(game.tick / 60.0, 0.1),
		"event": event,
		"asset": kind,
		"team": machine.team,
		"by": soldier_id,
		"by_role": BotBrain.ROLE_NAMES[brain.role] if brain != null else "",
	})


## Living soldiers within 60 m of s, as [its team, the other team], s left out.
func _near_counts(s: Soldier) -> Array:
	var counts := [0, 0]
	for id: int in game.entities:
		var other := game.soldier(id)
		if other != null and other != s and not other.dead and other.global_position.distance_to(s.global_position) < 60.0:
			counts[0 if other.team == s.team else 1] += 1
	return counts


func _run() -> void:
	var ticks := int(minutes * 60.0 * 60.0)
	var started := Time.get_ticks_usec()
	var last := -1
	_track_bots()
	while game.tick < ticks:
		await get_tree().physics_frame
		if game.tick > 0:
			_track_bots()
			if game.tick % 60 == 0:
				_observe_runner_support()
			if _vehicle_report != null:
				_vehicle_report.observe()
		if profile:
			# physics_frame comes before the nodes' physics ticks and the physics
			# step, so the time since the last one is a whole frame.
			var now := Time.get_ticks_usec()
			if last >= 0 and game.tick > 0:
				Prof.add("frame", now - last)
				Prof.add("physics_process_monitor", int(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000000.0))
				Prof.end_tick()
			last = now
	var wall := (Time.get_ticks_usec() - started) / 1000000.0
	var report := _report(ticks, wall)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORTS))
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := ProjectSettings.globalize_path("%s/bots-%d-seed-%d-%s.json" % [REPORTS, bots, seed_value, stamp])
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	_print_summary(report, path)
	if profile:
		_print_profile()
	if check:
		var totals: Dictionary = report.totals
		var ok: bool = totals.time_stuck < 60.0
		print("CHECK %s seed %d: %d captures, %d grabs, %d returns, %.1f s stuck, %d generators destroyed, %d repaired, %d turrets destroyed, %d repaired" % ["ok" if ok else "FAIL", seed_value, totals.captures, totals.grabs, totals.returns, totals.time_stuck, destroyed.generator, repaired.generator, destroyed.turret, repaired.turret])
		get_tree().quit(0 if ok else 1)
		return
	get_tree().quit()


func _report(ticks: int, wall: float) -> Dictionary:
	var seconds := ticks / 60.0
	var per_bot := []
	var totals := {
		"distance": 0.0, "time_stuck": 0.0, "stuck_spots": 0, "routes": 0, "top_speed": 0.0, "avg_speed": 0.0,
		"kills": 0, "deaths": 0, "captures": 0, "returns": 0, "grabs": 0,
		"disc_shots": 0, "disc_hits": 0, "chaingun_shots": 0, "chaingun_hits": 0,
	}
	# Weapon short name to [shots, hits] over all bots.
	var weapon_shots := {}
	for brain in director.brains:
		var s := brain.stats
		var avg_speed: float = s.speed_sum / maxf(s.ticks, 1)
		var routes: Array = s.route_seconds
		var route_avg := 0.0
		for r: float in routes:
			route_avg += r / routes.size()
		per_bot.append({
			"id": brain.soldier.entity_id,
			"team": brain.soldier.team,
			"distance": snappedf(s.distance, 0.1),
			"avg_speed": snappedf(avg_speed, 0.01),
			"top_speed": snappedf(s.top_speed, 0.01),
			"time_stuck": snappedf(s.time_stuck, 0.01),
			"stuck_spots": s.stuck_spots,
			"routes_completed": s.routes,
			"avg_route_seconds": snappedf(route_avg, 0.1),
			"role": BotBrain.ROLE_NAMES[brain.role],
			"wears": BotLoadouts.describe(brain.soldier.loadout, false),
			"skill": BotDirector.SKILL_NAMES[BotDirector.skill_level(brain.skill)],
			"personality": BotBrain.PERSONALITY_NAMES[brain.personality],
			"kills": s.kills,
			"deaths": s.deaths,
			"captures": s.captures,
			"returns": s.returns,
			"grabs": s.grabs,
			"disc_shots": s.shots[Weapon.DISC],
			"disc_hits": s.hits[Weapon.DISC],
			"chaingun_shots": s.shots[Weapon.CHAINGUN],
			"chaingun_hits": s.hits[Weapon.CHAINGUN],
		})
		for key in ["kills", "deaths", "captures", "returns", "grabs"]:
			totals[key] += s[key]
		totals.disc_shots += s.shots[Weapon.DISC]
		totals.disc_hits += s.hits[Weapon.DISC]
		totals.chaingun_shots += s.shots[Weapon.CHAINGUN]
		totals.chaingun_hits += s.hits[Weapon.CHAINGUN]
		for k in Weapon.all.size():
			var key := Weapon.all[k].short_name
			if not weapon_shots.has(key):
				weapon_shots[key] = [0, 0]
			weapon_shots[key][0] += s.shots[k]
			weapon_shots[key][1] += s.hits[k]
		totals.distance += s.distance
		totals.time_stuck += s.time_stuck
		totals.stuck_spots += s.stuck_spots.size()
		totals.routes += s.routes
		totals.top_speed = maxf(totals.top_speed, s.top_speed)
		totals.avg_speed += avg_speed / director.brains.size()
	# Hits are enemies hurt, so a disc's splash on two counts twice.
	totals["weapons"] = weapon_shots
	totals["disc_hit_rate"] = float(totals.disc_hits) / maxf(totals.disc_shots, 1.0)
	totals["chaingun_hit_rate"] = float(totals.chaingun_hits) / maxf(totals.chaingun_shots, 1.0)
	# How long each grab lasted, to the drop or the capture.
	var lives := []
	var taken := {}
	var first_grab: Variant = null
	var carrier_deaths: Array[Dictionary] = []
	for event: Dictionary in flag_events:
		var flag_team: int = event.carried_flag_team
		if event.event == "taken":
			if first_grab == null:
				first_grab = event.seconds
			taken[flag_team] = event.seconds
		elif (event.event == "dropped" or event.event == "captured") and taken.has(flag_team):
			lives.append(snappedf(event.seconds - taken[flag_team], 0.1))
			taken.erase(flag_team)
		if event.event == "dropped" and event.has("killed_by"):
			carrier_deaths.append(event)
	var life_sum := 0.0
	for life: float in lives:
		life_sum += life
	totals["carrier_life_avg"] = life_sum / maxf(lives.size(), 1.0)
	totals["carrier_life_max"] = lives.max() if not lives.is_empty() else 0.0
	for key in totals:
		if totals[key] is float:
			totals[key] = snappedf(totals[key], 0.01)
	var teams := [{}, {}]
	for team in 2:
		teams[team] = { "skill": BotDirector.SKILL_NAMES[skills[team]], "kills": 0, "deaths": 0, "captures": 0, "grabs": 0, "returns": 0, "disc_shots": 0, "disc_hits": 0 }
	for bot: Dictionary in per_bot:
		var t: Dictionary = teams[bot.team]
		for key in ["kills", "deaths", "captures", "grabs", "returns", "disc_shots", "disc_hits"]:
			t[key] += bot[key]
	var commanders := {}
	var generator_raids: Array[Dictionary] = []
	for team: int in director.commanders:
		var boss: TeamCommander = director.commanders[team]
		for decision: Dictionary in boss.decisions:
			if decision.text == "raid on their generator":
				generator_raids.append({ "team": team, "seconds": decision.seconds })
		var lines := {}
		for said: Dictionary in boss.chat:
			lines[said.text] = int(lines.get(said.text, 0)) + 1
		commanders[team] = {
			"recent_lines": lines,
			"roles_over_time": boss.history,
			"decisions": boss.decisions,
			"attack_lanes": boss.attack_lanes.map(func(w: float) -> float: return snappedf(w, 0.01)),
			"escape_lanes": boss.escape_lanes.map(func(w: float) -> float: return snappedf(w, 0.01)),
			"carry_lanes": boss.carry_lanes,
			"lane_names": boss.lanes.names if boss.lanes != null else [],
		}
	var vehicle_seconds := {}
	for kind: String in vehicle_ticks:
		vehicle_seconds[kind] = snappedf(vehicle_ticks[kind] / 60.0, 0.1)
	return {
		"map": GameMap.chosen_name(),
		"seed": seed_value,
		"bots_per_team": bots,
		"simulated_seconds": seconds,
		"ticks": ticks,
		"wall_seconds": snappedf(wall, 0.01),
		"speed_up": snappedf(seconds / maxf(wall, 0.001), 0.01),
		"scores": game.scores.duplicate(),
		"first_grab_seconds": first_grab,
		"flag_events": flag_events,
		"carrier_deaths": carrier_deaths,
		"generator_raids": generator_raids,
		"generator_hits": generator_hits,
		"runner_near_stand_seconds": runner_near_stand_seconds,
		"runner_with_support_seconds": runner_with_support_seconds,
		"vehicle_boardings": vehicle_boardings,
		"vehicle_report": _vehicle_report.report() if _vehicle_report != null else {},
		"vehicle_rider_seconds": vehicle_seconds,
		"tracked_positions": tracked_positions,
		"assets_destroyed": destroyed,
		"assets_repaired": repaired,
		"asset_events": asset_events,
		"carrier_lives": lives,
		"commanders": commanders,
		"totals": totals,
		"teams": teams,
		"bots": per_bot,
	}


func _print_summary(report: Dictionary, path: String) -> void:
	var totals: Dictionary = report.totals
	print("Bot match: %d bots a team, seed %d, %.0f s simulated in %.1f s (%.1fx real time)" % [report.bots_per_team, report.seed, report.simulated_seconds, report.wall_seconds, report.speed_up])
	print("Routes completed %d, distance %.0f m, average speed %.1f m/s, top %.1f m/s" % [totals.routes, totals.distance, totals.avg_speed, totals.top_speed])
	print("Time stuck %.1f s over %d stuck spots" % [totals.time_stuck, totals.stuck_spots])
	print("Score %d to %d: %d captures, %d grabs, %d returns, %d kills, %d deaths" % [report.scores[0], report.scores[1], totals.captures, totals.grabs, totals.returns, totals.kills, totals.deaths])
	for team in 2:
		var t: Dictionary = report.teams[team]
		print("Team %d (%s): %d kills, %d deaths, %d captures, %d grabs, %d returns, discs %d of %d hit" % [team, t.skill, t.kills, t.deaths, t.captures, t.grabs, t.returns, t.disc_hits, t.disc_shots])
	print("Carriers held the flag %.1f s on average, %.1f s at most" % [totals.carrier_life_avg, totals.carrier_life_max])
	print("Destroyed %s, repaired %s" % [str(report.assets_destroyed), str(report.assets_repaired)])
	for team: int in report.commanders:
		var boss: Dictionary = report.commanders[team]
		print("Team %d commander: %d decisions, lanes %s, attacks by lane %s, enemy carriers home by lane %s, our carriers by lane %s" % [team, boss.decisions.size(), str(boss.lane_names), str(boss.attack_lanes), str(boss.escape_lanes), str(boss.carry_lanes)])
		for sample: Dictionary in boss.roles_over_time:
			if int(sample.seconds) % 60 == 0:
				print("  %4.0f s  %s" % [sample.seconds, sample.plan])
	print("Disc %d shots, %d hits (%.0f%%), chaingun %d shots, %d hits (%.0f%%)" % [totals.disc_shots, totals.disc_hits, totals.disc_hit_rate * 100.0, totals.chaingun_shots, totals.chaingun_hits, totals.chaingun_hit_rate * 100.0])
	var used: Array[String] = []
	for key: String in totals.weapons:
		if totals.weapons[key][0] > 0:
			used.append("%s %d/%d" % [key, totals.weapons[key][1], totals.weapons[key][0]])
	print("Hits/shots by weapon: %s" % ", ".join(used))
	for bot: Dictionary in report.bots:
		print("  bot %d team %d %s %s (%s): %.0f m, avg %.1f m/s, stuck %.1f s, %d spots, %d kills, %d deaths, %d caps, %d grabs, %d returns" % [bot.id, bot.team, bot.personality, bot.role, bot.wears, bot.distance, bot.avg_speed, bot.time_stuck, bot.stuck_spots.size(), bot.kills, bot.deaths, bot.captures, bot.grabs, bot.returns])
	print("Report: ", path)


## The --profile tables: the map build in parts, then each tick's parts and
## counts.
func _print_profile() -> void:
	print("\nMap build (ms):")
	var total := map.build_seconds * 1000.0
	var named := 0.0
	var keys := build_parts.keys()
	keys.sort()
	for key: String in keys:
		var ms: float = build_parts[key] / 1000.0
		print("  %-40s %9.1f" % [key, ms])
		if key.count(".") == 1 or key == "build.graph.auto_link_pairs" or key == "build.graph.points" or key == "build.graph.mirrors" or key == "build.graph.mesas_towers":
			named += ms
	print("  %-40s %9.1f" % ["whole build", total])
	print("  %-40s %9.1f" % ["rest (atmosphere, noise setup, ...)", total - named])
	var counts := build_counts.keys()
	counts.sort()
	for key: String in counts:
		print("  %-40s %9d" % [key, build_counts[key]])
	# Single calls of the graph's ground samplers.
	var n := 200000
	var t := Time.get_ticks_usec()
	for k in n:
		map.surface_at(k * 0.37 - 400.0, (k % 500) * 0.8 - 200.0)
	var surface_us := float(Time.get_ticks_usec() - t) / n
	t = Time.get_ticks_usec()
	for k in n:
		map.blocked_at(k * 0.37 - 400.0, (k % 500) * 0.8 - 200.0)
	var blocked_us := float(Time.get_ticks_usec() - t) / n
	var surf_call := Callable(map, "surface_at")
	t = Time.get_ticks_usec()
	for k in n:
		surf_call.call(k * 0.37 - 400.0, (k % 500) * 0.8 - 200.0)
	var callable_us := float(Time.get_ticks_usec() - t) / n
	print("  surface_at %.2f us a call (%.2f us through a Callable), blocked_at %.2f us" % [surface_us, callable_us, blocked_us])

	var ticks := Prof.ticks
	var tick_mean: float = Prof.stats("t:tick").mean
	print("\nBots on %s" % ("worker threads" if BotDirector.threads else "the main thread (--serial-bots)"))
	print("Per tick over %d ticks (us): mean, p95, max, share of the Match tick, ticks it ran in" % ticks)
	var order := [
		"frame", "physics_process_monitor", "tick",
		"terrain_collision", "chunk_add",
		"bots", "bots.serial_before", "bots.snapshot", "bots.work", "bots.work_sum", "bots.starts", "bots.serial_after", "bot.commander", "commander0", "commander1", "bot.think", "bot.perception", "bot.combat_think",
		"bot.replan", "bot.replan.nearest", "bot.replan.start_point", "bot.replan.astar",
		"bot.check_stuck", "bot.steering", "bot.combat_aim",
		"soldier_sim", "move_and_slide", "blob_shadow_ray",
		"projectiles", "flags", "ray_physics", "ray_terrain",
	]
	for key: String in Prof.series:
		if key.begins_with("t:") and not order.has(key.substr(2)):
			order.append(key.substr(2))
	for part: String in order:
		var s := Prof.stats("t:" + part)
		var ran := 0
		for v: int in Prof.series.get("t:" + part, []):
			if v > 0:
				ran += 1
		print("  %-26s %8.1f %7d %7d %6.1f%% %6d" % [part, s.mean, s.p95, s.max, 100.0 * s.mean / maxf(tick_mean, 0.001), ran])
	var f: Dictionary = Prof.stats("t:frame")
	print("  outside the Match tick (Jolt step, engine): mean %.1f us" % [f.mean - tick_mean])
	print("\nCounts per tick: mean, p95, max, total")
	var names := []
	for key: String in Prof.series:
		if key.begins_with("n:"):
			names.append(key.substr(2))
	names.sort()
	for what: String in names:
		var s := Prof.stats("n:" + what)
		print("  %-26s %8.2f %7d %7d %9d" % [what, s.mean, s.p95, s.max, s.sum])
