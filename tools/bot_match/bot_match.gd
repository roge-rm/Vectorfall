extends Node

## Plays a headless capture the flag match of bots only on the test map, as
## fast as it can, and writes a report on how they moved, fought and played
## to build/bot-reports/. Run it with tools/bot-match.sh, which passes these
## after --:
##   --bots N      bots per team, 8 at most (8)
##   --seed N      the match seed (1)
##   --minutes N   simulated minutes (5)
## The capture limit is off, so the match runs the whole time.

const REPORTS := "res://build/bot-reports"

var map: TestMap
var game: Match
var director: BotDirector
var bots := 8
var seed_value := 1
var minutes := 5.0
## Every flag event, in order.
var flag_events: Array[Dictionary] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for k in args.size() - 1:
		match args[k]:
			"--bots":
				bots = clampi(int(args[k + 1]), 1, 8)
			"--seed":
				seed_value = int(args[k + 1])
			"--minutes":
				minutes = float(args[k + 1])
	map = TestMap.new()
	add_child(map)
	game = Match.new(seed_value)
	for team in 2:
		game.spawns[team] = map.spawn_points(team)
	for team in 2:
		game.add_flag(team, map.stand_point(team), map.flag_rest(team))
	game.settings.capture_limit = 1000000
	game.settings.time_limit = minutes * 60.0 + 10.0
	game.start_clock()
	add_child(game)
	director = BotDirector.new(game, map.route_graph)
	for team in 2:
		for k in bots:
			var brain := director.add_bot(team, map.spawn_point(team, k))
			# Nothing's drawn, so the bodies needn't move their legs.
			brain.soldier.body.process_mode = Node.PROCESS_MODE_DISABLED
	game.killed.connect(_on_killed)
	for event in ["taken", "dropped", "returned", "captured"]:
		game.connect("flag_" + event, _on_flag_event.bind(event))
	_run.call_deferred()


func _on_killed(victim_id: int, killer_id: int, weapon: int) -> void:
	if not flag_events.is_empty() and flag_events[-1].event == "dropped" and flag_events[-1].soldier == victim_id:
		var killer := game.soldier(killer_id)
		var role := ""
		var brain := director.brain_of(killer_id)
		if brain != null:
			role = BotBrain.ROLE_NAMES[brain.role] + " " + BotBrain.GOAL_NAMES[brain.goal]
		flag_events[-1]["killed_by"] = [killer_id, role, Weapon.all[weapon].short_name, snappedf(killer.global_position.distance_to(game.soldier(victim_id).global_position), 0.1) if killer != null else 0.0]


func _on_flag_event(team: int, soldier_id: int, event: String) -> void:
	var at := Vector3.ZERO
	var s := game.soldier(soldier_id)
	if s != null:
		at = s.global_position
	flag_events.append({
		"seconds": snappedf(game.tick / 60.0, 0.1),
		"event": event,
		"flag_team": team,
		"soldier": soldier_id,
		"health": snappedf(s.health, 1.0) if s != null else 0.0,
		"position": [snappedf(at.x, 0.1), snappedf(at.y, 0.1), snappedf(at.z, 0.1)],
	})


func _run() -> void:
	var ticks := int(minutes * 60.0 * 60.0)
	var started := Time.get_ticks_usec()
	while game.tick < ticks:
		await get_tree().physics_frame
	var wall := (Time.get_ticks_usec() - started) / 1000000.0
	var report := _report(ticks, wall)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORTS))
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := ProjectSettings.globalize_path("%s/bots-%d-seed-%d-%s.json" % [REPORTS, bots, seed_value, stamp])
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	_print_summary(report, path)
	get_tree().quit()


func _report(ticks: int, wall: float) -> Dictionary:
	var seconds := ticks / 60.0
	var per_bot := []
	var totals := {
		"distance": 0.0, "time_stuck": 0.0, "stuck_spots": 0, "routes": 0, "top_speed": 0.0, "avg_speed": 0.0,
		"kills": 0, "deaths": 0, "captures": 0, "returns": 0, "grabs": 0,
		"disc_shots": 0, "disc_hits": 0, "chaingun_shots": 0, "chaingun_hits": 0,
	}
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
		totals.distance += s.distance
		totals.time_stuck += s.time_stuck
		totals.stuck_spots += s.stuck_spots.size()
		totals.routes += s.routes
		totals.top_speed = maxf(totals.top_speed, s.top_speed)
		totals.avg_speed += avg_speed / director.brains.size()
	# Hits are enemies hurt, so a disc's splash on two counts twice.
	totals["disc_hit_rate"] = float(totals.disc_hits) / maxf(totals.disc_shots, 1.0)
	totals["chaingun_hit_rate"] = float(totals.chaingun_hits) / maxf(totals.chaingun_shots, 1.0)
	for key in totals:
		if totals[key] is float:
			totals[key] = snappedf(totals[key], 0.01)
	return {
		"map": "test",
		"seed": seed_value,
		"bots_per_team": bots,
		"simulated_seconds": seconds,
		"ticks": ticks,
		"wall_seconds": snappedf(wall, 0.01),
		"speed_up": snappedf(seconds / maxf(wall, 0.001), 0.01),
		"scores": game.scores.duplicate(),
		"flag_events": flag_events,
		"totals": totals,
		"bots": per_bot,
	}


func _print_summary(report: Dictionary, path: String) -> void:
	var totals: Dictionary = report.totals
	print("Bot match: %d bots a team, seed %d, %.0f s simulated in %.1f s (%.1fx real time)" % [report.bots_per_team, report.seed, report.simulated_seconds, report.wall_seconds, report.speed_up])
	print("Routes completed %d, distance %.0f m, average speed %.1f m/s, top %.1f m/s" % [totals.routes, totals.distance, totals.avg_speed, totals.top_speed])
	print("Time stuck %.1f s over %d stuck spots" % [totals.time_stuck, totals.stuck_spots])
	print("Score %d to %d: %d captures, %d grabs, %d returns, %d kills, %d deaths" % [report.scores[0], report.scores[1], totals.captures, totals.grabs, totals.returns, totals.kills, totals.deaths])
	print("Disc %d shots, %d hits (%.0f%%), chaingun %d shots, %d hits (%.0f%%)" % [totals.disc_shots, totals.disc_hits, totals.disc_hit_rate * 100.0, totals.chaingun_shots, totals.chaingun_hits, totals.chaingun_hit_rate * 100.0])
	for bot: Dictionary in report.bots:
		print("  bot %d team %d %s: %.0f m, avg %.1f m/s, stuck %.1f s, %d spots, %d kills, %d deaths, %d caps, %d grabs, %d returns" % [bot.id, bot.team, bot.role, bot.distance, bot.avg_speed, bot.time_stuck, bot.stuck_spots.size(), bot.kills, bot.deaths, bot.captures, bot.grabs, bot.returns])
	print("Report: ", path)
