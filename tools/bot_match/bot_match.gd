extends Node

## Plays a headless capture the flag match of bots only on a map, as
## fast as it can, and writes a report on how they moved, fought and played
## to build/bot-reports/. Run it with tools/bot-match.sh, which passes these
## after --:
##   --bots N      bots per team, 8 at most (8)
##   --seed N      the match seed (1)
##   --minutes N   simulated minutes (5)
##   --map NAME    ochre_fold or test (ochre_fold)
##   --skill0 N    team 0's skill level, 0 beginner to 4 expert (2, normal)
##   --skill1 N    team 1's (2)
##   --plain       every bot the default personality
##   --check       print a CHECK line for tools/bot-check.sh, and exit with an
##                 error if the bots stopped moving: 60 s or more stuck
## The capture limit is off, so the match runs the whole time. The report has
## each team's roles every 10 s and its commander's decisions.

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
## Every flag event, in order.
var flag_events: Array[Dictionary] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	check = args.has("--check")
	plain = args.has("--plain")
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
	add_child(map)
	print("Map %s built in %.2f s, its route graph in %.2f s (%d points, %d links)" % [map.title, map.build_seconds, map.graph_seconds, map.route_graph.points.size(), map.route_graph.links.size()])
	game = Match.new(seed_value)
	game.terrain = map.terrain
	for team in 2:
		game.spawns[team] = map.spawn_points(team)
	for team in 2:
		game.add_flag(team, map.stand_point(team), map.flag_rest(team))
	game.settings.capture_limit = 1000000
	game.settings.time_limit = minutes * 60.0 + 10.0
	game.start_clock()
	add_child(game)
	director = BotDirector.new(game, map.route_graph)
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
		"speed": snappedf(s.velocity.length(), 0.1) if s != null else 0.0,
		"near": _near_counts(s) if s != null else [0, 0],
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
	if check:
		var totals: Dictionary = report.totals
		var ok: bool = totals.time_stuck < 60.0
		print("CHECK %s seed %d: %d captures, %d grabs, %d returns, %.1f s stuck" % ["ok" if ok else "FAIL", seed_value, totals.captures, totals.grabs, totals.returns, totals.time_stuck])
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
		totals.distance += s.distance
		totals.time_stuck += s.time_stuck
		totals.stuck_spots += s.stuck_spots.size()
		totals.routes += s.routes
		totals.top_speed = maxf(totals.top_speed, s.top_speed)
		totals.avg_speed += avg_speed / director.brains.size()
	# Hits are enemies hurt, so a disc's splash on two counts twice.
	totals["disc_hit_rate"] = float(totals.disc_hits) / maxf(totals.disc_shots, 1.0)
	totals["chaingun_hit_rate"] = float(totals.chaingun_hits) / maxf(totals.chaingun_shots, 1.0)
	# How long each grab lasted, to the drop or the capture.
	var lives := []
	var taken := {}
	for event: Dictionary in flag_events:
		if event.event == "taken":
			taken[event.flag_team] = event.seconds
		elif (event.event == "dropped" or event.event == "captured") and taken.has(event.flag_team):
			lives.append(snappedf(event.seconds - taken[event.flag_team], 0.1))
			taken.erase(event.flag_team)
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
	for team: int in director.commanders:
		var boss: TeamCommander = director.commanders[team]
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
	return {
		"map": GameMap.chosen_name(),
		"seed": seed_value,
		"bots_per_team": bots,
		"simulated_seconds": seconds,
		"ticks": ticks,
		"wall_seconds": snappedf(wall, 0.01),
		"speed_up": snappedf(seconds / maxf(wall, 0.001), 0.01),
		"scores": game.scores.duplicate(),
		"flag_events": flag_events,
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
	for team: int in report.commanders:
		var boss: Dictionary = report.commanders[team]
		print("Team %d commander: %d decisions, lanes %s, attacks by lane %s, enemy carriers home by lane %s, our carriers by lane %s" % [team, boss.decisions.size(), str(boss.lane_names), str(boss.attack_lanes), str(boss.escape_lanes), str(boss.carry_lanes)])
		for sample: Dictionary in boss.roles_over_time:
			if int(sample.seconds) % 60 == 0:
				print("  %4.0f s  %s" % [sample.seconds, sample.plan])
	print("Disc %d shots, %d hits (%.0f%%), chaingun %d shots, %d hits (%.0f%%)" % [totals.disc_shots, totals.disc_hits, totals.disc_hit_rate * 100.0, totals.chaingun_shots, totals.chaingun_hits, totals.chaingun_hit_rate * 100.0])
	for bot: Dictionary in report.bots:
		print("  bot %d team %d %s %s: %.0f m, avg %.1f m/s, stuck %.1f s, %d spots, %d kills, %d deaths, %d caps, %d grabs, %d returns" % [bot.id, bot.team, bot.personality, bot.role, bot.distance, bot.avg_speed, bot.time_stuck, bot.stuck_spots.size(), bot.kills, bot.deaths, bot.captures, bot.grabs, bot.returns])
	print("Report: ", path)
