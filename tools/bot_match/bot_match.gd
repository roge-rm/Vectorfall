extends Node

## Plays a headless match of bots only on the test map, as fast as it can,
## and writes a report on how they moved to build/bot-reports/. Run it with
## tools/bot-match.sh, which passes these after --:
##   --bots N      bots per team, 8 at most (8)
##   --seed N      the match seed (1)
##   --minutes N   simulated minutes (5)
## The bots run their goal loop between the flag stands. The match has no
## flags yet, so they can't take one.

const REPORTS := "res://build/bot-reports"

var map: TestMap
var game: Match
var director: BotDirector
var bots := 8
var seed_value := 1
var minutes := 5.0


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
	add_child(game)
	director = BotDirector.new(game, map.route_graph)
	for team in 2:
		for k in bots:
			var brain := director.add_bot(team, map.spawn_point(team, k))
			# Nothing's drawn, so the bodies needn't move their legs.
			brain.soldier.body.process_mode = Node.PROCESS_MODE_DISABLED
	_run.call_deferred()


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
	var totals := { "distance": 0.0, "time_stuck": 0.0, "stuck_spots": 0, "routes": 0, "top_speed": 0.0, "avg_speed": 0.0 }
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
		})
		totals.distance += s.distance
		totals.time_stuck += s.time_stuck
		totals.stuck_spots += s.stuck_spots.size()
		totals.routes += s.routes
		totals.top_speed = maxf(totals.top_speed, s.top_speed)
		totals.avg_speed += avg_speed / director.brains.size()
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
		"totals": totals,
		"bots": per_bot,
	}


func _print_summary(report: Dictionary, path: String) -> void:
	var totals: Dictionary = report.totals
	print("Bot match: %d bots a team, seed %d, %.0f s simulated in %.1f s (%.1fx real time)" % [report.bots_per_team, report.seed, report.simulated_seconds, report.wall_seconds, report.speed_up])
	print("Routes completed %d, distance %.0f m, average speed %.1f m/s, top %.1f m/s" % [totals.routes, totals.distance, totals.avg_speed, totals.top_speed])
	print("Time stuck %.1f s over %d stuck spots" % [totals.time_stuck, totals.stuck_spots])
	for bot: Dictionary in report.bots:
		print("  bot %d team %d: %d routes (%.1f s each), %.0f m, avg %.1f m/s, top %.1f m/s, stuck %.1f s, %d spots" % [bot.id, bot.team, bot.routes_completed, bot.avg_route_seconds, bot.distance, bot.avg_speed, bot.top_speed, bot.time_stuck, bot.stuck_spots.size()])
	print("Report: ", path)
