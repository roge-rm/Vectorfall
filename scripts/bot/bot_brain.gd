class_name BotBrain
extends CommandSource

## A bot: it only ever makes PlayerCommands, like a player's input. It thinks
## a few times a second (looks and listens, picks a goal, plans a route over
## the route graph) and steers every WORK_TICKS ticks, with BotCombat turning
## its look to fight on the way every tick. In a match with flags its goal comes from the role its
## team's commander gives it and the flags; with none it loops between the
## flag stands. Everything that changes
## what it does is in get_state(), and its random numbers are its own, seeded
## from the match's seed and its id.
##
## BotDirector.run_bots() runs it each tick in three parts: before_work() and
## after_work() on the main thread in bot order, and work() between them,
## maybe on a worker thread at the same time as other bots. work() writes only
## this bot's own fields and reads soldiers and flags through their snapshot
## (Soldier.at() and the like), never a node, ray or signal.

## POINT is a route graph point given by go_to(), and HOLD standing still
## after reaching it. The rest are capture the flag goals with a position in
## goal_target.
enum Goal { NONE, ENEMY_STAND, HOME_STAND, POINT, HOLD, TAKE_FLAG, CAPTURE, RETURN_FLAG, CHASE, ESCORT, DEFEND, MIDFIELD, RETREAT, RALLY, CUT_OFF, HIDE, STATION, HELP, RAID, FIX, DEPLOY, VEHICLE, WAYPOINT }
const GOAL_NAMES: Array[String] = ["none", "enemy stand", "home stand", "point", "hold", "take flag", "capture", "return flag", "chase", "escort", "defend", "midfield", "back off", "rally", "cut off", "hide", "station", "repair", "raid", "fix base", "deploy", "board", "waypoint"]
## OFFENCE takes out the enemy flag turret (role_target) while it works,
## then goes for the enemy flag and carries it, DEFENCE holds by the flag,
## LIGHT_DEFENCE watches the way enemies come in and chases carriers, ESCORT
## goes with a carrier or a person heading for the flag, CHASE goes after the
## enemy carrier of our flag. GENERATOR raids the enemy base asset in
## role_target, and REPAIR fixes our own one in role_target, both picked by
## the commander. SNIPER is for a later milestone and plays midfield for now.
enum Role { OFFENCE, DEFENCE, MIDFIELD, ESCORT, LIGHT_DEFENCE, CHASE, REPAIR, SNIPER, GENERATOR }
const ROLE_NAMES: Array[String] = ["offence", "defence", "midfield", "escort", "light defence", "chase", "repair", "sniper", "generator"]
## Variety within a team. AGGRESSIVE closes in on enemies and chases them
## longer, CAREFUL backs off sooner and leans to defence, SNIPER holds high
## ground, sniper perches if the map has them, and shoots from further out.
enum Personality { DEFAULT, AGGRESSIVE, CAREFUL, SNIPER }
const PERSONALITY_NAMES: Array[String] = ["default", "aggressive", "careful", "sniper"]
enum Escape { NONE, JET, BACK_OFF, OTHER_WAY }
const ESCAPE_NAMES: Array[String] = ["", "jet out", "back off", "other way"]

## Bots steer, check their goal and route and carry searches on every this
## many ticks, half of them on even ticks and half on odd. In between they
## keep the steering they had, with combat aim and fire still every tick.
const WORK_TICKS := 2
## Seconds with no progress towards the next point before the bot is stuck.
const STUCK_TIME := 2.5
## Metres closer to the next point that count as progress, or a speed
## towards it in m/s.
const PROGRESS := 1.0
const CLOSING_SPEED := 3.0
## Seconds on one leg, at least, before the bot counts as stuck on it.
const LEG_TIME := 20.0
## Ticks an escape move lasts.
const ESCAPE_TICKS := 60
## Seconds a link the bot got stuck on stays avoided.
const AVOID_TIME := 60.0
## Off the route by more than this, in metres, and the bot plans again.
const OFF_ROUTE := 25.0
## Below the route by more than this, in metres, and the bot plans again.
const OFF_ROUTE_BELOW := 10.0
## Close enough to a goal, flat and up or down, in metres.
const ARRIVE_RANGE := 6.0
const ARRIVE_HEIGHT := 4.0
## Closer than this to the goal, flat and up or down, the bot leaves the route
## graph and heads straight for it.
const DIRECT_RANGE := 35.0
const DIRECT_HEIGHT := 12.0
## Seconds between plans for a goal that moves.
const REPLAN_TIME := 0.5
## A friendly carrier this close gets an escort, in metres, or this for
## offence and midfield.
const ESCORT_RANGE := 60.0
const ESCORT_RANGE_FAR := 200.0
## Enemies this close to the home stand get chased by defence, and this close
## by light defence.
const GUARD_RANGE := 45.0
const WATCH_RANGE := 130.0
## A dropped own flag this close is worth going for, whatever the role.
const RETURN_RANGE := 90.0
## Seconds offence waits at the rally point for the others before it goes
## for the flag anyway.
const RALLY_WAIT := 12.0
## A carrier's route keeps this far from the enemy spawn, in metres, unless
## the way round costs more than this many seconds.
const CARRIER_KEEP_OFF := 12.0
const CARRIER_AVOID_COST := 8.0
## Energy an escape jet needs to start; below it the bot stands and refills.
const ESCAPE_ENERGY := 25.0
## An aggressive bot holding the middle goes after an enemy it's fighting
## this close, and one on defence meets enemies this much further out, in
## metres and as a share of GUARD_RANGE.
const PRESS_RANGE := 80.0
const PRESS_GUARD := 1.5
## Health below which a careful bot backs off, and an aggressive one.
const CAREFUL_HEALTH := 55.0
const AGGRESSIVE_HEALTH := 20.0
## A carrier this close to home waits somewhere out of the way while its own
## flag is carried off, in metres.
const HIDE_RANGE := 200.0
## A carrier plans its way home again this often, round the enemies its team
## knows of, in seconds.
const CARRIER_REPLAN := 1.5
## Seconds a carrier's route pays for each point this close to a known enemy,
## in metres.
const ENEMY_COST := 8.0
const ENEMY_REACH := 45.0
## Offence jets in towards their flag at home between these distances from
## it, flat, to take it at speed, in metres.
const JET_IN_FAR := 150.0
const JET_IN_NEAR := 45.0
## Light defence goes out to meet our carrier once it's this close to home, in
## metres.
const MEET_RANGE := 450.0
## A bot whose role wants another loadout goes to one of its team's stations
## this close, in metres, while nothing more urgent is going on. It gives up
## after STATION_TIME seconds and doesn't try again for STATION_WAIT.
const STATION_RANGE := 60.0
const STATION_TIME := 20.0
const STATION_WAIT := 90.0
const DEPLOY_TRY_TICKS := 20 * 60
const DEPLOY_RETRY_TICKS := 30 * 60
const DEPLOY_SITE_RANGE := 220.0
const ROLE_PACKS := {
	Role.DEFENCE: Pack.TURRET,
	Role.LIGHT_DEFENCE: Pack.SENSOR,
	Role.MIDFIELD: Pack.STATION,
}
## Goals a bot may leave for a station or to repair a teammate.
const CALM_GOALS: Array[Goal] = [Goal.DEFEND, Goal.MIDFIELD, Goal.RALLY, Goal.RETREAT]

var director: BotDirector
var game: Match
var soldier: Soldier
## 0 for a beginner to 1 for an expert.
var skill := 0.5
var personality := Personality.DEFAULT
## Which tick of every BotDirector.THINK_TICKS this bot thinks on.
var think_offset := 0
## Which tick of every WORK_TICKS this bot steers on.
var work_parity := 0
var perception := BotPerception.new()
var steering := BotSteering.new()
var combat := BotCombat.new()
var gear := BotGear.new()
var role := Role.OFFENCE
## Which of its role's places it takes, such as a defence spot.
var role_slot := 0
## Who the role is about: the soldier escorted or chased, or 0.
var role_target := 0

var goal := Goal.NONE
## The route graph point the goal is at.
var goal_point := -1
## Where a capture the flag goal is, and where it was when last planned.
var goal_target := Vector3.ZERO
var planned_for := Vector3.ZERO
var planned_tick := -1000
## Heading straight for goal_target, off the route graph.
var direct := false
var direct_start := Vector3.ZERO
## Tick before which the bot keeps to the graph, after a straight line got it
## stuck.
var no_direct_until := 0
## At a goal it holds, standing guard.
var at_goal := false
## Offence that has left the rally point for the enemy flag.
var attacking := false
## When it got to the rally point, or -1.
var rally_tick := -1
## Route graph points to go through, and the one being steered towards.
var path: Array[int] = []
var path_index := 0
## Where the bot was when it planned, the start of the first leg.
var path_start := Vector3.ZERO
## A route search still going, carried on each tick, with the tick it was
## last carried on. The bot keeps to its old route meanwhile.
var _search: RoutePlanner.Search
var _search_tick := -1
## Links got stuck on, as "from:to", to the tick they stop being avoided.
var avoid := {}
## current_link() for the last pair of points asked about.
var _link_from := -1
var _link_to := -1
var _link: RouteGraph.Link
## Closest the bot has been to the point it's steering towards.
var best_distance := INF
## The point the stuck check is timing, and ticks spent heading for it.
var leg_target := -1
var leg_ticks := 0
var no_progress := 0.0
## Escapes tried since the last progress, which picks the next one.
var escapes := 0
var escape := Escape.NONE
var escape_ticks := 0
## Which side an escape move goes, -1 or 1.
var escape_side := 1.0
var stuck := false
## Standing still for energy before an escape jet.
var refilling := false
var was_dead := false
var last_position := Vector3.ZERO
var goal_started := 0
## For the bot match report.
var stats := {}
## The bot's own random numbers, seeded by the director.
var rng := RandomNumberGenerator.new()
## The command work() made for this tick.
var _command: PlayerCommand
## The last steering command, before combat, as PlayerCommand.to_dict(),
## kept for the ticks in between, or empty.
var _steer := {}
## Points of the route search it may take this tick, handed out by the
## director before work().
var _search_allow := 0
## A search began in work() this tick, waiting for allow_start().
var _search_new := false
## Searches work() finished, for run_bots() to keep in the route store.
var found: Array[RoutePlanner.Search] = []
## On a raid, how close to a turret or sensor counts as there, with a clear
## line to it, in metres, and how far up or down.
const RAID_RANGE := 40.0
const RAID_HEIGHT := 20.0
## How close to the spot by an asset counts as there to repair it.
const FIX_RANGE := 1.5
## Metres up or down from a route point into or out of a generator room
## within which it counts as reached.
const ROOM_HEIGHT := 1.5
## Ready to go for the flag, as it was before work() this tick, read by the
## team's other offence bots.
var ready_seen := false
## The disc's way out, from and to, for after_work() to check with a ray
## before the shot.
## Role to the BotLoadouts kit picked for it, kept for the match, and the
## random numbers that pick them, seeded from the bot's own so its aim and
## other choices go on as they would without them.
var kit_picks := {}
var kit_rng := RandomNumberGenerator.new()
## The tick a station detour gives up, and the tick before which it won't
## start another.
var station_until := -1
var no_station_until := 0
var deploy_retry := 0
var _disc_check := false
var _disc_from := Vector3.ZERO
var _disc_to := Vector3.ZERO


## Back to the start of the goal loop, after spawning or respawning.
func reset() -> void:
	goal = Goal.NONE
	goal_point = -1
	path.clear()
	path_index = 0
	_search = null
	escape = Escape.NONE
	escape_ticks = 0
	refilling = false
	stuck = false
	no_progress = 0.0
	best_distance = INF
	escapes = 0
	direct = false
	at_goal = false
	attacking = false
	rally_tick = -1
	_steer = {}
	station_until = -1
	steering.reset()
	combat.reset()
	gear.reset()
	if soldier != null:
		last_position = soldier.at()
		yaw = soldier.yaw
	if stats.is_empty():
		stats = {
			"distance": 0.0,
			"speed_sum": 0.0,
			"ticks": 0,
			"top_speed": 0.0,
			"time_stuck": 0.0,
			"stuck_spots": [],
			"routes": 0,
			"route_seconds": [],
			"kills": 0,
			"deaths": 0,
			"captures": 0,
			"returns": 0,
			"grabs": 0,
			"shots": _zeros(Weapon.all.size()),
			"hits": _zeros(Weapon.all.size()),
		}


## The command work() made for this tick.
func make_command(_delta: float) -> PlayerCommand:
	if _command == null:
		var command := PlayerCommand.new()
		command.yaw = yaw
		command.pitch = pitch
		return command
	return _command


## True on the ticks it steers.
func _works_now() -> bool:
	return (game.tick + work_parity) % WORK_TICKS == 0


## True on the first tick it steers at or after each of its think ticks, one
## every BotDirector.THINK_TICKS.
func _thinks_now() -> bool:
	if not _works_now():
		return false
	for back in WORK_TICKS:
		if posmod(game.tick - back + think_offset, BotDirector.THINK_TICKS) == 0:
			return true
	return false


## True if it thinks or carries a route search on this tick, after
## before_work(): the bots with the most work.
func busy() -> bool:
	return _command == null and soldier != null and not soldier.dead and (_thinks_now() or _search_allow > 0)


## True if it began a route search in work() this tick, which took no points
## yet, for the director to hand points to.
func started_search() -> bool:
	return _search_new and _search != null and not _search.done


## Main thread, in bot order, before work(): looks along its sight lines if it
## thinks this tick.
func before_work() -> void:
	ready_seen = attacking or (goal == Goal.RALLY and at_goal)
	_command = null
	_search_allow = 0
	_search_new = false
	_disc_check = false
	if soldier == null or game == null or soldier.dead:
		return
	if soldier.vehicle_id != 0:
		_command = director.vehicle_orders.rider_command(self)
		yaw = _command.yaw
		pitch = _command.pitch
		_steer.clear()
		return
	if _thinks_now():
		perception.look(soldier, game, director)
		combat.look_at_asset(self)


## True if it carries a search on this tick, after before_work().
func wants_points() -> bool:
	return _command == null and soldier != null and game != null and not soldier.dead and _search != null and not _search.done and not was_dead and _works_now()


## Main thread, before work(): takes points for the search it carries on from
## the pool left. Returns what's left of the pool.
func allow_carry(pool: int) -> int:
	_search_allow = mini(BotDirector.SEARCH_POINTS * WORK_TICKS, pool)
	return pool - _search_allow


## Main thread, after work(): takes points from what's left of the pool for a
## search work() began. Returns what's left of the pool.
func allow_start(pool: int) -> int:
	_search_allow = mini(BotDirector.SEARCH_FIRST, pool)
	return pool - _search_allow


## Runs a search work() began with the points allow_start() gave, and follows
## the route if it's done. May run on a worker thread, like work().
func work_start() -> void:
	if _run_search(_search_allow):
		_take_route()


## Main thread, in bot order, after work(): the ray for a disc shot, which
## holds the shot if the way out is blocked.
func after_work() -> void:
	if not _disc_check:
		return
	_disc_check = false
	if Prof.on:
		Prof.count("ray_by_disc_check")
	if not director.take_ray(true) or not game.line_clear(_disc_from, _disc_to):
		_command.buttons &= ~PlayerCommand.FIRE


## Works out this tick's command. May run on a worker thread: see the class
## notes.
func work(delta: float) -> void:
	if _command != null:
		return
	var command := PlayerCommand.new()
	command.yaw = yaw
	command.pitch = pitch
	_command = command
	if soldier == null or game == null:
		return
	_send_loadout(command)
	if soldier.dead:
		was_dead = true
		return
	if was_dead:
		was_dead = false
		reset()
	_track(delta)
	if _works_now():
		command = _steer_tick(delta)
		_steer = command.to_dict()
	elif not _steer.is_empty():
		command = PlayerCommand.from_dict(_steer)
	if Prof.on:
		var prof_t := Time.get_ticks_usec()
		combat.apply(self, command, delta)
		Prof.add("bot.combat_aim", Time.get_ticks_usec() - prof_t)
	else:
		combat.apply(self, command, delta)
	gear.apply(self, command)
	_aim_deploy(command)
	director.vehicle_orders.request_board(self, command)
	if _command.loadout.size() > 0:
		command.loadout = _command.loadout
	yaw = command.yaw
	pitch = command.pitch
	_command = command


## The loadout its role wants, picking the kit the first time it plays the
## role. Uses the bot's kit random numbers, so only from work() or the main
## thread in bot order.
func wanted_loadout() -> Loadout:
	if not kit_picks.has(role):
		kit_picks[role] = BotLoadouts.pick(role, personality, kit_rng)
	var worn := BotLoadouts.loadout(kit_picks[role])
	if role_slot != 0 or director.deploy_open[soldier.team].is_empty():
		return worn
	var deploy_pack: int = ROLE_PACKS.get(role, Loadout.NO_PACK)
	if deploy_pack in director.deploy_slots[soldier.team]:
		worn.pack = deploy_pack
	return worn


## Once each think period, alive or dead, sends the role's loadout when the
## soldier's next one differs, so it respawns in it, the same way a person's
## loadout screen does.
func _send_loadout(command: PlayerCommand) -> void:
	if posmod(game.tick + think_offset, BotDirector.THINK_TICKS) != 0:
		return
	var want := wanted_loadout()
	if not soldier.next_loadout.equals(want):
		command.loadout = want.to_dict()


## Puts the role's loadout on at once, before the match starts.
func dress() -> void:
	var want := wanted_loadout()
	if not soldier.loadout.equals(want):
		soldier.set_loadout(want)


## Thinks if it's time, carries its route search on and steers, on the ticks
## it works. The steering command, before combat.
func _steer_tick(delta: float) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.yaw = yaw
	command.pitch = pitch
	if _thinks_now():
		if Prof.on:
			var prof_t := Time.get_ticks_usec()
			think()
			Prof.add("bot.think", Time.get_ticks_usec() - prof_t)
			Prof.count("bot_thinks")
		else:
			think()
	if _search != null and _search_tick != game.tick:
		_search_tick = game.tick
		if _run_search(_search_allow):
			_take_route()
	if _ctf():
		_check_goal()
	elif goal_point >= 0 and _near(director.graph.points[goal_point]):
		_arrived()
	if holding():
		command = _hold_command()
	elif path.is_empty() and not direct:
		pass
	else:
		if Prof.on:
			var prof_t := Time.get_ticks_usec()
			_check_stuck(delta)
			Prof.add("bot.check_stuck", Time.get_ticks_usec() - prof_t)
		else:
			_check_stuck(delta)
		if escape_ticks > 0:
			command = _escape_command()
			escape_ticks = maxi(escape_ticks - WORK_TICKS, 0)
			if escape_ticks == 0 and escape == Escape.OTHER_WAY:
				if direct:
					direct = false
					no_direct_until = game.tick + 300
				replan()
		elif Prof.on:
			var prof_t := Time.get_ticks_usec()
			command = steering.steer(self, delta)
			Prof.add("bot.steering", Time.get_ticks_usec() - prof_t)
		else:
			command = steering.steer(self, delta)
	return command


## Carries the search on by up to budget points, noting a route found for the
## route store. True once it's done.
func _run_search(budget: int) -> bool:
	var done := director.run_plan(_search, budget)
	if done and Soldier.use_snapshot and not _search.key.is_empty():
		found.append(_search)
	return done


## The way out of a disc shot, for after_work() to check with a ray.
func check_disc(from: Vector3, to: Vector3) -> void:
	_disc_check = true
	_disc_from = from
	_disc_to = to


## Looks and listens, picks a goal and plans a route to it when it needs one.
func think() -> void:
	if Prof.on:
		var prof_t := Time.get_ticks_usec()
		perception.listen(soldier, game, director)
		Prof.add("bot.perception", Time.get_ticks_usec() - prof_t)
		prof_t = Time.get_ticks_usec()
		combat.think(self)
		gear.think(self)
		Prof.add("bot.combat_think", Time.get_ticks_usec() - prof_t)
	else:
		perception.listen(soldier, game, director)
		combat.think(self)
		gear.think(self)
	if goal == Goal.HOLD or goal == Goal.POINT:
		if goal == Goal.POINT and _needs_route():
			replan()
		return
	if _ctf():
		_think_ctf()
		return
	if goal == Goal.NONE:
		_set_goal(Goal.ENEMY_STAND)
	elif goal == Goal.HOLD:
		return
	elif _needs_route():
		replan()


## True in a match with flags, where the bot plays capture the flag.
func _ctf() -> bool:
	return not game.flags.is_empty()


## One offence bot stays on foot to attempt the flag while the rest can attack the base.
func is_flag_runner() -> bool:
	return role == Role.OFFENCE and role_slot == 0 and _ctf()


## Picks a goal from the role and the flags, and plans to it when it changes
## or moves.
func _think_ctf() -> void:
	var prof_t := Time.get_ticks_usec() if Prof.on else 0
	var next := _choose_goal()
	if Prof.on:
		Prof.add("bot.choose_goal", Time.get_ticks_usec() - prof_t)
	var kind: Goal = next[0]
	var where: Vector3 = next[1]
	var moved := where.distance_to(planned_for) > 12.0 and (game.tick - planned_tick) / 60.0 >= REPLAN_TIME
	if kind != goal:
		goal = kind
		goal_started = game.tick
		at_goal = false
		goal_target = where
		replan()
	else:
		goal_target = where
		# Only with enemies known and while it's getting on, so the stuck check
		# still sees a bad climb.
		var boss := director.commander(soldier.team)
		var carrier_due := goal == Goal.CAPTURE and (game.tick - planned_tick) / 60.0 >= CARRIER_REPLAN and no_progress < 0.5 and escape_ticks == 0 and not steering.resting and not steering.climbing and boss != null and not boss.known.is_empty()
		if (moved or carrier_due) and not direct:
			replan()
	var pos := soldier.at()
	var to := goal_target - pos
	var close := Vector2(to.x, to.z).length() < DIRECT_RANGE and absf(to.y) < DIRECT_HEIGHT
	var route_done := not path.is_empty() and path_index >= path.size() - 1 and _near(director.graph.points[path[path_index]])
	# A goal on a route graph point is reached by the route, which goes round
	# rocks; a straight line might not.
	var on_graph := goal_point >= 0 and director.graph.points[goal_point].distance_to(goal_target) < 3.0
	# A raid keeps to the route, which goes round the asset and through ways in.
	var want_direct := (close or route_done) and not on_graph and game.tick >= no_direct_until and goal != Goal.RAID
	if want_direct and not direct:
		direct = true
		direct_start = pos
		best_distance = INF
		no_progress = 0.0
	elif not want_direct and direct:
		direct = false
		replan()
	elif not direct and _needs_route():
		replan()


## The goal for now, as [Goal, position]: the role's, or when that's a calm
## one, a detour to a station for the role's loadout or to repair a teammate.
func _choose_goal() -> Array:
	var waypoint: Dictionary = game.waypoints.get(soldier.entity_id, {})
	if not waypoint.is_empty() and game.carried_flag(soldier.entity_id) == null:
		return [Goal.WAYPOINT, waypoint.at]
	var next := _role_goal()
	var kind: Goal = next[0]
	var own: Flag = game.flags.get(soldier.team)
	var home_safe := own == null or own.mode == Flag.Mode.HOME
	var safe := combat.target_id == 0 and not combat.hurt_recently(game.tick)
	var id := soldier.entity_id
	var boss := director.commander(soldier.team)
	if boss == null or not boss.order_locks.has(id):
		if kind in [Goal.MIDFIELD, Goal.RALLY, Goal.TAKE_FLAG, Goal.RAID, Goal.ESCORT]:
			var delivery := director.vehicle_orders.foot_support(id)
			if not delivery.is_empty():
				var runner := game.soldier(delivery.target)
				if runner != null and not runner.dead and runner.vehicle_id == 0 and runner.at().distance_squared_to(soldier.at()) < 120.0 * 120.0:
					return [Goal.ESCORT, _escort_spot(runner)]
				if kind in [Goal.MIDFIELD, Goal.RALLY]:
					return [kind, delivery.objective]
		var boarding := director.vehicle_orders.board_target(id)
		if director.vehicle_orders.is_intercept_job(id) and soldier.at().distance_squared_to(boarding) <= 144.0:
			return [Goal.VEHICLE, boarding]
		if safe and boarding != Vector3.INF:
			var normal_boarding := home_safe and kind in [Goal.DEFEND, Goal.MIDFIELD, Goal.RALLY, Goal.TAKE_FLAG, Goal.RAID]
			var defence_flight := director.vehicle_orders.is_intercept_job(id) and kind in [Goal.CHASE, Goal.CUT_OFF, Goal.DEFEND, Goal.MIDFIELD, Goal.RALLY, Goal.TAKE_FLAG, Goal.RAID]
			if normal_boarding or defence_flight:
				return [Goal.VEHICLE, boarding]
	if not CALM_GOALS.has(kind) or not safe:
		if goal == Goal.STATION:
			station_until = -1
		return next
	if not home_safe:
		return next
	var deploy_at := _deploy_goal()
	if deploy_at != Vector3.INF:
		return [Goal.DEPLOY, deploy_at]
	var pad := _station_detour()
	if pad != Vector3.INF:
		return [Goal.STATION, pad]
	var mate := game.soldier(gear.mate_id) if gear.mate_id != 0 else null
	if mate != null and not mate.dead:
		return [Goal.HELP, mate.at()]
	return next


func _deploy_goal() -> Vector3:
	var slot := soldier.loadout.pack
	var team := soldier.team
	if not soldier.deploy_ready or slot not in director.deploy_slots[team] or game.tick < deploy_retry:
		return Vector3.INF
	if goal == Goal.DEPLOY and game.tick - goal_started >= DEPLOY_TRY_TICKS:
		deploy_retry = game.tick + DEPLOY_RETRY_TICKS
		return Vector3.INF
	var pos := soldier.at()
	var best := Vector3.INF
	var best_distance := DEPLOY_SITE_RANGE
	for site: Vector3 in director.deploy_open[team]:
		var distance := pos.distance_to(site)
		if distance < best_distance:
			best = site
			best_distance = distance
	return best


func _aim_deploy(command: PlayerCommand) -> void:
	if goal != Goal.DEPLOY or not soldier.deploy_ready or not soldier.grounded or combat.fighting(self) or escape_ticks > 0:
		return
	var to := goal_target - soldier.at()
	var range_to := Vector2(to.x, to.z).length()
	if range_to > 5.0 or absf(to.y) > 1.5:
		return
	command.yaw = atan2(-to.x, -to.z) if range_to > 0.01 else yaw
	command.pitch = -0.25
	command.buttons &= ~(PlayerCommand.SKI | PlayerCommand.JUMP | PlayerCommand.JET)
	var error := range_to - Match.DEPLOY_DISTANCE
	command.move = Vector2(0.0, clampf(error * 0.7, -1.0, 1.0))
	# Release between attempts so a failed placement can be tried again.
	if absf(error) < 0.55 and soldier.horizontal_speed() < 4.0 and game.tick % 12 == 0:
		command.buttons |= PlayerCommand.DEPLOY


## The pad of the nearest station in reach while the loadout worn isn't the
## role's, or Vector3.INF. A detour that takes too long is dropped for a
## while, so a bot can't keep trying for a pad it can't reach.
func _station_detour() -> Vector3:
	if game.tick < no_station_until:
		return Vector3.INF
	if soldier.loadout.equals(wanted_loadout()):
		station_until = -1
		return Vector3.INF
	if goal == Goal.STATION and station_until >= 0 and game.tick > station_until:
		station_until = -1
		no_station_until = game.tick + int(STATION_WAIT * 60.0)
		return Vector3.INF
	var pos := soldier.at()
	var best := Vector3.INF
	for pad in director.station_pads(soldier.team):
		if pad.distance_to(pos) < STATION_RANGE and pad.distance_to(pos) < best.distance_to(pos):
			best = pad
	if best != Vector3.INF and goal != Goal.STATION:
		station_until = game.tick + int(STATION_TIME * 60.0)
	return best


## The goal its role and the flags call for, as [Goal, position].
func _role_goal() -> Array:
	var team := soldier.team
	var own: Flag = game.flags.get(team)
	var theirs: Flag = game.flags.get(1 - team)
	var pos := soldier.at()
	var me := soldier.entity_id
	var boss := director.commander(team)
	if theirs != null and theirs.mode == Flag.Mode.CARRIED and theirs.carrier_id == me:
		if own != null and own.mode == Flag.Mode.DROPPED and own.at().distance_to(pos) < 60.0:
			return [Goal.RETURN_FLAG, own.at()]
		if own != null and own.mode == Flag.Mode.CARRIED and pos.distance_to(game.stands[team]) < HIDE_RANGE and boss != null:
			# It can't score until our flag is back, so it waits out of the way.
			return [Goal.HIDE, boss.hide_point()]
		return [Goal.CAPTURE, game.stands[team] + Vector3.DOWN * 0.5]
	# Sent by the commander to a dropped flag: ours to send home, theirs to
	# carry on with.
	var pickup: int = boss.pickups.get(me, -1) if boss != null else -1
	if pickup == team and own.mode == Flag.Mode.DROPPED:
		return [Goal.RETURN_FLAG, own.at()]
	if pickup == 1 - team and theirs.mode == Flag.Mode.DROPPED:
		return [Goal.TAKE_FLAG, theirs.at()]
	var holding_theirs := theirs != null and theirs.mode == Flag.Mode.CARRIED
	if own != null and own.mode == Flag.Mode.DROPPED:
		if role in [Role.DEFENCE, Role.LIGHT_DEFENCE, Role.CHASE] or own.at().distance_to(pos) < RETURN_RANGE:
			return [Goal.RETURN_FLAG, own.at()]
	if theirs != null and theirs.mode == Flag.Mode.DROPPED and role in [Role.OFFENCE, Role.ESCORT] and theirs.at().distance_to(pos) < RETURN_RANGE:
		return [Goal.TAKE_FLAG, theirs.at()]
	var own_taken := own != null and own.mode == Flag.Mode.CARRIED
	if own_taken:
		var carrier := game.soldier(own.carrier_id)
		if carrier != null:
			var near := carrier.at().distance_to(pos)
			if role == Role.CHASE and boss != null:
				var chase: Array = boss.chase_point(role_slot, pos)
				return [Goal.CUT_OFF if chase[1] else Goal.CHASE, chase[0]]
			# Anyone close, and light defence from anywhere, goes for it.
			if role == Role.LIGHT_DEFENCE or (role != Role.DEFENCE and near < 30.0) or (role == Role.DEFENCE and near < GUARD_RANGE) or (role != Role.ESCORT and holding_theirs):
				var lead := clampf(near / 40.0, 0.0, 2.0)
				return [Goal.CHASE, carrier.at() + carrier.vel() * lead]
	if role == Role.ESCORT:
		var runner := game.soldier(role_target)
		if runner != null and not runner.dead:
			return [Goal.ESCORT, _escort_spot(runner)]
	# Midfield backs off to defend when hurt, and careful light defence and
	# escorts too. Offence keeps going, since health doesn't come back and
	# turning round wastes the run.
	var backs_off := role == Role.MIDFIELD or (personality == Personality.CAREFUL and role in [Role.LIGHT_DEFENCE, Role.ESCORT])
	var low := soldier.health < low_health() and backs_off
	if holding_theirs and role != Role.DEFENCE:
		var carrier := game.soldier(theirs.carrier_id)
		if carrier != null and role == Role.LIGHT_DEFENCE and carrier.at().distance_to(game.stands[team]) < MEET_RANGE:
			# Out to meet it on the way in, clearing whoever waits for it.
			return [Goal.ESCORT, _escort_spot(carrier)]
		if carrier != null and role != Role.LIGHT_DEFENCE and carrier.at().distance_to(pos) < ESCORT_RANGE_FAR:
			return [Goal.ESCORT, _escort_spot(carrier)]
	if low:
		return [Goal.RETREAT, _defence_spot(role_slot + 1)]
	if role == Role.GENERATOR:
		var target_info := director.asset_info(role_target)
		if not target_info.is_empty() and not target_info.destroyed and target_info.team != team:
			return [Goal.RAID, _raid_spot(target_info)]
	if role == Role.REPAIR:
		var fix := _fix_goal()
		if not fix.is_empty():
			return fix
	if role == Role.OFFENCE and theirs != null and theirs.mode != Flag.Mode.CARRIED:
		var at := theirs.at()
		if theirs.mode == Flag.Mode.HOME:
			at = game.stands[1 - team] + Vector3.DOWN * 0.5
			if not _ready_to_attack():
				return [Goal.RALLY, _midfield_spot()]
			# Their flag turret first, while it's up and powered.
			var turret := director.asset_info(role_target)
			if not turret.is_empty() and not turret.destroyed and turret.team != team and director.power[turret.team]:
				return [Goal.RAID, turret.raid]
		return [Goal.TAKE_FLAG, at]
	if role == Role.DEFENCE or role == Role.LIGHT_DEFENCE:
		# Anyone coming for the flag gets met: what this bot knows close in,
		# and what the team knows further out for light defence.
		var stand := game.stands[team]
		var guard := GUARD_RANGE * (PRESS_GUARD if personality == Personality.AGGRESSIVE else 1.0)
		var room := _generator_room(team)
		var ids := perception.contacts.keys()
		ids.sort()
		for id: int in ids:
			if perception.knows(id):
				var guess := perception.guess_position(id, game.tick)
				if guess.distance_to(stand) < guard or (room != Vector3.INF and guess.distance_to(room) < guard):
					return [Goal.CHASE, guess]
		if role == Role.LIGHT_DEFENCE and boss != null:
			var threats := boss.threats(WATCH_RANGE)
			if not threats.is_empty():
				return [Goal.CHASE, threats[0][1]]
			return [Goal.DEFEND, boss.watch_point(role_slot)]
		return [Goal.DEFEND, _defence_spot(role_slot)]
	# Midfield, and the roles for later milestones, hold the middle. An
	# aggressive one goes after whoever it's fighting nearby.
	if personality == Personality.AGGRESSIVE and combat.target_id != 0 and perception.knows(combat.target_id):
		var guess := perception.guess_position(combat.target_id, game.tick)
		if guess.distance_to(pos) < PRESS_RANGE:
			return [Goal.CHASE, guess]
	return [Goal.MIDFIELD, _midfield_spot()]


## Where a repair bot goes, as [Goal, position], or empty with nothing to
## fix: the spot by its asset with a repair pack on; without one, a station
## with power, or else the spot anyway to guard it until it
## respawns in its role's loadout.
func _fix_goal() -> Array:
	var info := director.asset_info(role_target)
	if info.is_empty() or info.team != soldier.team:
		return []
	if soldier.loadout.pack != Pack.REPAIR:
		var pos := soldier.at()
		var best := Vector3.INF
		for pad in director.station_pads(soldier.team):
			if pad.distance_to(pos) < best.distance_to(pos):
				best = pad
		if best != Vector3.INF:
			return [Goal.STATION, best]
	return [Goal.FIX, info.stand]


## Where to go to shoot an asset on a raid: the nearest perch above a
## generator's room while out of it, else its raid spot.
func _raid_spot(info: Dictionary) -> Vector3:
	var pos := soldier.at()
	var perches: Array = info.get("perches", [])
	if perches.is_empty() or BotCombat.in_room(pos, info):
		return info.raid
	var best: Vector3 = perches[0]
	for at: Vector3 in perches:
		if at.distance_to(pos) < best.distance_to(pos):
			best = at
	return best


## The GENERATOR point in a team's generator room, or Vector3.INF.
func _generator_room(team: int) -> Vector3:
	var rooms := director.graph.interest_points(RouteGraph.GENERATOR, team)
	return director.graph.points[rooms[0]] if not rooms.is_empty() else Vector3.INF


## Health below which the bot backs off, by its personality.
func low_health() -> float:
	match personality:
		Personality.CAREFUL:
			return CAREFUL_HEALTH
		Personality.AGGRESSIVE:
			return AGGRESSIVE_HEALTH
	return BotCombat.LOW_HEALTH


## Where an escort goes round a runner: the first ahead of it, clearing the
## way, the next two behind to either side, where chasers come from.
func _escort_spot(runner: Soldier) -> Vector3:
	var at := runner.at()
	var heading := Vector3(runner.vel().x, 0.0, runner.vel().z)
	if heading.length() < 5.0:
		# Standing or slow: towards where it's going, home with a flag or
		# their stand without.
		var carrying := game.carried_flag(runner.entity_id) != null
		var goal_at := game.stands[runner.team if carrying else 1 - runner.team]
		heading = Vector3(goal_at.x - at.x, 0.0, goal_at.z - at.z)
	heading = heading.normalized() if heading.length() > 0.1 else Vector3.FORWARD
	var side := heading.cross(Vector3.UP)
	var spot := at + runner.vel() * 0.5
	match role_slot % 3:
		0:
			spot += heading * 25.0
		1:
			spot += -heading * 10.0 + side * 12.0
		2:
			spot += -heading * 10.0 - side * 12.0
	return spot


## Offence goes for a flag at home together: it waits at the rally point
## until the team's other living offence bots are there or already on their
## way, or it's waited long enough.
func _ready_to_attack() -> bool:
	if attacking:
		return true
	var boss := director.commander(soldier.team)
	if boss != null and boss.attack_now():
		# Told to take the flag: no waiting for the others.
		attacking = true
		return true
	if goal != Goal.RALLY or not at_goal:
		rally_tick = -1
		return false
	if rally_tick < 0:
		rally_tick = game.tick
	var waiting := 0
	var ready := 0
	# Other bots as they were before this tick's work, which they may be
	# doing now on other threads.
	for brain in director.brains:
		if brain.soldier.team != soldier.team or brain.role != Role.OFFENCE or brain.soldier.dead:
			continue
		waiting += 1
		var is_ready := brain.ready_seen if brain != self else (attacking or (goal == Goal.RALLY and at_goal))
		if is_ready:
			ready += 1
	if ready >= waiting or (game.tick - rally_tick) / 60.0 > RALLY_WAIT:
		attacking = true
	return attacking


## A defence spot, those nearest the lane enemies come in by most first.
func _defence_spot(slot: int) -> Vector3:
	var graph := director.graph
	var spots := graph.interest_points(RouteGraph.DEFENCE, soldier.team)
	if spots.is_empty():
		return game.stands[soldier.team]
	var boss := director.commander(soldier.team)
	if boss != null and boss.lanes != null and boss.lanes.count > 0:
		var toward := boss.lanes.approach(soldier.team, boss.main_threat_lane())
		spots.sort_custom(func(a: int, b: int) -> bool:
			var da := graph.points[a].distance_to(toward)
			var db := graph.points[b].distance_to(toward)
			return da < db or (da == db and a < b))
	return graph.points[spots[slot % spots.size()]]


## A high spot on the bot's own half; for a sniper in midfield, a sniper
## perch there if the map has one it can get to without a must-jet climb.
func _midfield_spot() -> Vector3:
	var graph := director.graph
	var mine: Array[int] = []
	var home_x := game.stands[soldier.team].x
	if personality == Personality.SNIPER and role == Role.MIDFIELD:
		var perches := director.perches(soldier.team)
		if not perches.is_empty():
			return graph.points[perches[role_slot % perches.size()]]
	for point in graph.interest_points(RouteGraph.HIGH_GROUND, -1):
		var p := graph.points[point]
		if signf(p.x) == signf(home_x) and absf(p.x) < absf(home_x) - 30.0:
			mine.append(point)
	if mine.is_empty():
		return game.stands[soldier.team].lerp(game.stands[1 - soldier.team], 0.3)
	return graph.points[mine[role_slot % mine.size()]]


## Goals the bot stops and stands guard at, and how close counts.
func _hold_range() -> float:
	match goal:
		Goal.DEFEND, Goal.MIDFIELD, Goal.RETREAT, Goal.HIDE:
			return ARRIVE_RANGE
		Goal.CUT_OFF:
			return 12.0
		Goal.RALLY:
			return 15.0
		Goal.ESCORT:
			return 10.0
		Goal.CAPTURE:
			return 1.0
		Goal.HELP:
			return BotGear.MATE_HOLD
		Goal.FIX:
			return FIX_RANGE
		Goal.RAID:
			var info := director.asset_info(role_target)
			if not info.is_empty() and info.kind != BaseAsset.Kind.GENERATOR:
				return RAID_RANGE
			return ARRIVE_RANGE * 0.5
	return -1.0


## True when the steering should jet ahead for speed: going for their flag
## at home on the last stretch.
func wants_jet_in() -> bool:
	if goal != Goal.TAKE_FLAG:
		return false
	var theirs: Flag = game.flags.get(1 - soldier.team)
	if theirs == null or theirs.mode != Flag.Mode.HOME:
		return false
	var to := goal_target - soldier.at()
	var flat := Vector2(to.x, to.z).length()
	return flat < JET_IN_FAR and flat > JET_IN_NEAR


## Slows to a stop at the end of the route, where a flag goal runs through.
func slow_at_end() -> bool:
	return goal != Goal.TAKE_FLAG and goal != Goal.RETURN_FLAG and goal != Goal.CHASE


func _check_goal() -> void:
	var reach := _hold_range()
	if reach < 0.0:
		at_goal = false
		return
	var to := goal_target - soldier.at()
	var near := Vector2(to.x, to.z).length() < reach and absf(to.y) < ARRIVE_HEIGHT
	if goal == Goal.RAID and reach == RAID_RANGE:
		# Stops short of a turret or sensor while it can shoot it.
		var flat := Vector2(to.x, to.z).length()
		at_goal = combat.asset_seen == role_target and absf(to.y) < RAID_HEIGHT and flat < reach * (1.25 if at_goal else 1.0)
		return
	if goal == Goal.RAID and combat.asset_seen == role_target:
		# Stops wherever it can shoot down through an opening.
		var info := director.asset_info(role_target)
		var from := soldier.at()
		if not info.is_empty() and BotCombat.lobbing(from, info) and from.distance_to(BotCombat.asset_aim(from, info)) < BotCombat.LOB_REACH:
			at_goal = true
			return
	if near and not at_goal:
		stats.routes += 1
		stats.route_seconds.append((game.tick - goal_started) / 60.0)
	# A little room before it sets off again, so it doesn't jitter at the edge.
	at_goal = near or (at_goal and Vector2(to.x, to.z).length() < reach * 2.0 + 2.0)


## Standing at a goal it holds.
func holding() -> bool:
	return goal == Goal.HOLD or (at_goal and _hold_range() >= 0.0)


## Stands still, looking towards the enemy base, and lets the energy fill.
func _hold_command() -> PlayerCommand:
	var command := PlayerCommand.new()
	command.yaw = yaw
	command.pitch = 0.0
	if _ctf():
		var to := game.stands[1 - soldier.team] - soldier.at()
		command.yaw = atan2(-to.x, -to.z)
	return command


## Sends the bot to a route graph point, where it stops and holds.
func go_to(point: int) -> void:
	goal = Goal.POINT
	goal_point = point
	goal_started = game.tick
	replan()


func _set_goal(next: Goal) -> void:
	goal = next
	var team := 1 - soldier.team if next == Goal.ENEMY_STAND else soldier.team
	var stands := director.graph.interest_points(RouteGraph.FLAG_STAND, team)
	goal_point = stands[0] if not stands.is_empty() else -1
	goal_started = game.tick
	replan()


func _arrived() -> void:
	stats.routes += 1
	stats.route_seconds.append((game.tick - goal_started) / 60.0)
	if goal == Goal.POINT:
		goal = Goal.HOLD
		goal_point = -1
		path.clear()
		_search = null
		return
	_set_goal(Goal.HOME_STAND if goal == Goal.ENEMY_STAND else Goal.ENEMY_STAND)


func _near(point: Vector3) -> bool:
	var to := point - soldier.at()
	return Vector2(to.x, to.z).length() < ARRIVE_RANGE and absf(to.y) < ARRIVE_HEIGHT


## Plans a route to the goal from the nearest point ahead, at the bot's speed and
## energy, keeping away from links it got stuck on.
func replan() -> void:
	if Prof.on:
		var prof_t := Time.get_ticks_usec()
		_replan()
		Prof.add("bot.replan", Time.get_ticks_usec() - prof_t)
		Prof.count("replans")
	else:
		_replan()


## No route, or off it or unable to make its turn, and no search going that
## will bring a new one.
func _needs_route() -> bool:
	return _search == null and (path.is_empty() or _off_route() or _cant_turn())


## Starts a search for a new route, dropping any still going. One done at
## once is taken now; otherwise the bot keeps its old route until it's done.
func _replan() -> void:
	_search = null
	var graph := director.graph
	if _ctf() and goal >= Goal.TAKE_FLAG:
		var prof_t0 := Time.get_ticks_usec() if Prof.on else 0
		goal_point = graph.nearest(goal_target)
		if Prof.on:
			Prof.add("bot.replan.nearest", Time.get_ticks_usec() - prof_t0)
		planned_for = goal_target
		planned_tick = game.tick
	if goal_point < 0:
		path.clear()
		path_index = 0
		return
	var prof_a := Time.get_ticks_usec() if Prof.on else 0
	var avoid_links := {}
	for key: String in avoid.keys():
		if avoid[key] <= game.tick:
			avoid.erase(key)
			continue
		var ends := key.split(":")
		var link := graph.link_between(int(ends[0]), int(ends[1]))
		if link != null:
			avoid_links[link] = RoutePlanner.AVOID_COST
	if goal == Goal.CAPTURE:
		# A carrier keeps off the enemy's spawn, where they come back to life.
		for link: RouteGraph.Link in director.links_near_spawns(1 - soldier.team, CARRIER_KEEP_OFF):
			avoid_links[link] = float(avoid_links.get(link, 0.0)) + CARRIER_AVOID_COST
		# And keeps to the lanes that worked for the team's carriers.
		var boss := director.commander(soldier.team)
		if boss != null:
			var costs := boss.carry_costs()
			for link: RouteGraph.Link in costs:
				avoid_links[link] = float(avoid_links.get(link, 0.0)) + costs[link]
			# And round the enemies the team knows of.
			for point in boss.points_near_enemies(ENEMY_REACH):
				for link: RouteGraph.Link in graph.out_links[point]:
					avoid_links[link] = float(avoid_links.get(link, 0.0)) + ENEMY_COST
	if Prof.on:
		Prof.add("bot.replan.avoid", Time.get_ticks_usec() - prof_a)
	var prof_t := Time.get_ticks_usec() if Prof.on else 0
	var start := graph.start_point(soldier.at(), soldier.vel())
	if Prof.on:
		Prof.add("bot.replan.start_point", Time.get_ticks_usec() - prof_t)
	# In the bot phase the search takes its first points after work(), from
	# the tick's shared pool; outside it, at once.
	var first := 0 if Soldier.use_snapshot else BotDirector.SEARCH_FIRST
	_search = director.begin_plan(start, goal_point, soldier.vel(), soldier.energy, avoid_links, first, director.shut_for(soldier.team))
	if not Soldier.use_snapshot:
		director.owe_points(_search.expanded)
	_search_tick = game.tick
	_search_new = Soldier.use_snapshot and not _search.done
	if _search.done:
		if Soldier.use_snapshot and not _search.key.is_empty() and _search.expanded > 0:
			found.append(_search)
		_take_route()


## Follows the route the search found.
func _take_route() -> void:
	var old_target: int = path[path_index] if path_index < path.size() else -1
	var old_best := best_distance
	var old_no_progress := no_progress
	path.assign(_search.result)
	path_index = 0
	_search = null
	path_start = soldier.at()
	best_distance = INF
	no_progress = 0.0
	advance()
	if old_target >= 0 and path_index < path.size() and path[path_index] == old_target:
		# Still heading for the same point, so it's still as stuck as it was.
		best_distance = old_best
		no_progress = old_no_progress


## The point being steered towards.
func target() -> Vector3:
	if direct:
		return goal_target
	return director.graph.points[path[path_index]]


## The start of the leg being steered along.
func leg_start() -> Vector3:
	if direct:
		return direct_start
	return director.graph.points[path[path_index - 1]] if path_index > 0 else path_start


## True on the last leg, to the goal.
func is_last() -> bool:
	return direct or path_index == path.size() - 1


## The link being followed, or null on the way to the first point.
func current_link() -> RouteGraph.Link:
	if direct or path_index == 0:
		return null
	var from := path[path_index - 1]
	var to := path[path_index]
	if from != _link_from or to != _link_to:
		_link_from = from
		_link_to = to
		_link = director.graph.link_between(from, to)
	return _link


## Moves on to the next point once the bot is close to this one, or past it
## along the next leg.
func advance() -> void:
	if direct:
		return
	var graph := director.graph
	var pos := soldier.at()
	var speed := soldier.horizontal_speed()
	while path_index < path.size() - 1:
		var p := graph.points[path[path_index]]
		var q := graph.points[path[path_index + 1]]
		# Into or out of a generator room, a point counts only at its own
		# height, as the room is right under the deck.
		var room := graph.room_of(path[path_index]) >= 0 or (path_index > 0 and graph.room_of(path[path_index - 1]) >= 0)
		if room and absf(pos.y - p.y) > ROOM_HEIGHT:
			break
		var to_p := Vector2(p.x - pos.x, p.z - pos.z)
		var reach := maxf(4.0, speed * 0.3)
		var passed := false
		var leg := Vector2(q.x - p.x, q.z - p.z)
		var from_p := Vector2(pos.x - p.x, pos.z - p.z)
		if leg.length() > 0.1 and from_p.dot(leg) > 0.0:
			var side := absf(from_p.cross(leg.normalized()))
			passed = side < 5.0 and absf(pos.y - p.y) < 15.0
		# Gone past it to one side: turning back costs more than going on.
		var start := leg_start()
		var leg_in := Vector2(p.x - start.x, p.z - start.z)
		if leg_in.length() > 0.1 and from_p.dot(leg_in) > 0.0 and to_p.length() < 15.0 and absf(pos.y - p.y) < 15.0:
			passed = true
		if to_p.length() < reach or passed:
			path_index += 1
			best_distance = INF
			no_progress = 0.0
			escapes = 0
		else:
			break


## A point lookahead metres further along the route from where the bot is,
## for it to steer at.
func aim_point(lookahead: float) -> Vector3:
	if direct:
		return goal_target
	var graph := director.graph
	var pos := soldier.at()
	var a := leg_start()
	var b := target()
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var t := 0.0
	if ab.length_squared() > 0.01:
		t = clampf(Vector2(pos.x - a.x, pos.z - a.z).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var at := a.lerp(b, t)
	var left := lookahead
	var k := path_index
	var before := a
	while true:
		var next := graph.points[path[k]]
		var step := Vector2(next.x - at.x, next.z - at.z).length()
		if step >= left:
			return at.lerp(next, left / step)
		left -= step
		at = next
		# Nor past the way into or out of a generator room, right under the deck.
		if graph.room_of(path[k]) >= 0 or (k + 1 < path.size() and graph.room_of(path[k + 1]) >= 0):
			return at
		k += 1
		if k >= path.size():
			return at
		# Don't look round a sharp corner, so the bot doesn't cut it into
		# whatever's on the inside.
		var into := Vector2(next.x - before.x, next.z - before.z)
		var after := graph.points[path[k]]
		var out := Vector2(after.x - next.x, after.z - next.z)
		if into.length() > 0.1 and out.length() > 0.1 and absf(into.angle_to(out)) > deg_to_rad(35.0):
			return at
		before = next
	return at


## Going too fast to make the turn to the next point, so a route that
## carries on more the way it's going is better.
func _cant_turn() -> bool:
	var v := Vector2(soldier.vel().x, soldier.vel().z)
	var to := Vector2(target().x - soldier.at().x, target().z - soldier.at().z)
	return v.length() > 20.0 and to.length() > 1.0 and absf(v.angle_to(to)) > deg_to_rad(70.0)


func _off_route() -> bool:
	var pos := soldier.at()
	var a := leg_start()
	var b := target()
	var closest := Geometry3D.get_closest_point_to_segment(Vector3(pos.x, 0.0, pos.z), Vector3(a.x, 0.0, a.z), Vector3(b.x, 0.0, b.z))
	if closest.distance_to(Vector3(pos.x, 0.0, pos.z)) > OFF_ROUTE:
		return true
	# Slid well below both ends of the leg, say back down a slope it couldn't
	# get up. A dip between the ends is fine.
	return minf(a.y, b.y) - pos.y > OFF_ROUTE_BELOW


## Counts no progress towards the next point, and picks an escape move when
## there's been none for STUCK_TIME: a hop with the jet, then backing off to
## one side, then another way round with the link avoided. Runs on the
## ticks the bot works, after moving on along the route.
func _check_stuck(delta: float) -> void:
	var prof_t := Time.get_ticks_usec() if Prof.on else 0
	advance()
	if Prof.on:
		Prof.add("stuck.advance", Time.get_ticks_usec() - prof_t)
	delta *= WORK_TICKS
	var to := target() - soldier.at()
	var distance := to.length()
	# Heading back after going wide is progress too. Only across the ground,
	# so bobbing up and down under a ledge isn't.
	var flat := Vector3(to.x, 0.0, to.z)
	var closing := Vector3(soldier.vel().x, 0.0, soldier.vel().z).dot(flat / maxf(flat.length(), 0.01))
	# Too long on one leg is stuck too, say sliding back down each time it
	# nearly makes a climb.
	var leg_key := -2 if direct else path[path_index]
	if leg_key != leg_target:
		leg_target = leg_key
		leg_ticks = 0
	leg_ticks += WORK_TICKS
	var leg_limit := maxf(LEG_TIME, leg_start().distance_to(target()) / 3.0)
	if leg_ticks > int(leg_limit * 60.0) and escape_ticks == 0:
		leg_ticks = 0
		no_progress = STUCK_TIME
	elif distance < best_distance - PROGRESS or (closing > CLOSING_SPEED and escape_ticks == 0):
		best_distance = distance
		no_progress = 0.0
		stuck = false
		return
	no_progress += delta
	if stuck:
		stats.time_stuck += delta
	if no_progress < STUCK_TIME or escape_ticks > 0:
		return
	if not stuck:
		stats.time_stuck += STUCK_TIME
	stuck = true
	no_progress = 0.0
	best_distance = distance
	escapes += 1
	escape = [Escape.JET, Escape.BACK_OFF, Escape.OTHER_WAY][(escapes - 1) % 3]
	escape_ticks = ESCAPE_TICKS
	escape_side = -1.0 if rng.randf() < 0.5 else 1.0
	var from := path[path_index - 1] if path_index > 0 and not direct else -1
	var pos := soldier.at()
	stats.stuck_spots.append({
		"tick": game.tick,
		"bot": soldier.entity_id,
		"position": [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1), snappedf(pos.z, 0.1)],
		"link": [from, leg_target],
		"escape": ESCAPE_NAMES[escape],
	})
	if escape == Escape.OTHER_WAY and from >= 0:
		avoid["%d:%d" % [from, leg_target]] = game.tick + int(AVOID_TIME * 60.0)


func _escape_command() -> PlayerCommand:
	var command := PlayerCommand.new()
	var to := target() - soldier.at()
	var heading := atan2(-to.x, -to.z)
	command.yaw = heading
	command.pitch = 0.0
	var done := ESCAPE_TICKS - escape_ticks
	match escape:
		Escape.JET:
			if refilling:
				# Out of energy: stand still, which holds on any slope a soldier
				# can stand on, until there's enough to jet out.
				refilling = soldier.energy < BotSteering.rest_until(soldier) and soldier.grounded
				escape_ticks += WORK_TICKS
				if refilling:
					var down := BotSteering.rest_wish(soldier)
					if down != Vector3.ZERO:
						var local := Basis(Vector3.UP, command.yaw).inverse() * down
						command.move = Vector2(local.x, -local.z)
					return command
				# Full enough: the jet out starts now, with its jump.
				escape_ticks = ESCAPE_TICKS
				return command
			if done == 0 and soldier.energy < ESCAPE_ENERGY and soldier.grounded:
				refilling = true
				escape_ticks += WORK_TICKS
				return command
			# Jump and jet up towards the next point, a little to one side.
			command.move = Vector2(escape_side * 0.3, 1.0).normalized()
			if done < 2:
				command.buttons |= PlayerCommand.JUMP
			if soldier.energy > 2.0:
				command.buttons |= PlayerCommand.JET
		Escape.BACK_OFF, Escape.OTHER_WAY:
			# Back away to one side, then jet up for a fresh line.
			command.move = Vector2(escape_side * 0.7, -1.0).normalized()
			if done > ESCAPE_TICKS * 2 / 3 and soldier.energy > 20.0:
				command.buttons |= PlayerCommand.JET
	return command


func _track(delta: float) -> void:
	var pos := soldier.at()
	var moved := pos.distance_to(last_position)
	# Respawning or being set somewhere isn't travel.
	if moved < soldier.tuning.max_speed * delta * 2.0:
		stats.distance += moved
	last_position = pos
	var speed := soldier.vel().length()
	stats.speed_sum += speed
	stats.ticks += 1
	stats.top_speed = maxf(stats.top_speed, speed)


## A line for the debug overlay on what the bot is doing.
func describe() -> String:
	var doing := ESCAPE_NAMES[escape] if escape_ticks > 0 else steering.doing
	if refilling:
		doing = "refill to jet out"
	elif holding():
		doing = "hold"
	var fight := ""
	if combat.target_id != 0:
		fight = "  fights %d with %s" % [combat.target_id, Weapon.all[combat.weapon].short_name]
	var name_ := ROLE_NAMES[role]
	if role_target != 0:
		name_ += " %d" % role_target
	var boss := director.commander(soldier.team)
	if boss != null and boss.order_locks.has(soldier.entity_id):
		name_ += " (ordered)"
	if GOAL_NAMES[goal] != ROLE_NAMES[role]:
		name_ += ", " + GOAL_NAMES[goal]
	var who := "%s, %s" % [BotDirector.SKILL_NAMES[BotDirector.skill_level(skill)], PERSONALITY_NAMES[personality]]
	var wears := BotLoadouts.describe(soldier.loadout, soldier.pack_on)
	return "%s: %s%s\n%s  %.0f m/s  energy %.0f  health %.0f  knows %d\n%s" % [name_, doing, fight, who, soldier.vel().length(), soldier.energy, soldier.health, perception.known_count(), wears]


func get_state() -> Dictionary:
	return {
		"yaw": yaw,
		"pitch": pitch,
		"skill": skill,
		"personality": personality,
		"think_offset": think_offset,
		"work_parity": work_parity,
		"steer": _steer.duplicate(),
		"goal": goal,
		"goal_point": goal_point,
		"goal_target": goal_target,
		"planned_for": planned_for,
		"planned_tick": planned_tick,
		"direct": direct,
		"direct_start": direct_start,
		"no_direct_until": no_direct_until,
		"at_goal": at_goal,
		"attacking": attacking,
		"rally_tick": rally_tick,
		"role": role,
		"role_slot": role_slot,
		"role_target": role_target,
		"refilling": refilling,
		"combat": combat.get_state(),
		"gear": gear.get_state(),
		"kit_picks": kit_picks.duplicate(),
		"kit_rng_seed": kit_rng.seed,
		"kit_rng_state": kit_rng.state,
		"station_until": station_until,
		"no_station_until": no_station_until,
		"deploy_retry": deploy_retry,
		"path": path.duplicate(),
		"path_index": path_index,
		"path_start": path_start,
		"search": _search.to_state() if _search != null else null,
		"search_tick": _search_tick,
		"avoid": avoid.duplicate(),
		"best_distance": best_distance,
		"leg_target": leg_target,
		"leg_ticks": leg_ticks,
		"no_progress": no_progress,
		"escapes": escapes,
		"escape": escape,
		"escape_ticks": escape_ticks,
		"escape_side": escape_side,
		"stuck": stuck,
		"was_dead": was_dead,
		"last_position": last_position,
		"goal_started": goal_started,
		"perception": perception.get_state(),
		"steering": steering.get_state(),
		"stats": stats.duplicate(true),
		"rng_seed": rng.seed,
		"rng_state": rng.state,
	}


func set_state(state: Dictionary) -> void:
	yaw = state.yaw
	pitch = state.pitch
	skill = state.skill
	personality = state.get("personality", Personality.DEFAULT)
	think_offset = state.think_offset
	work_parity = state.get("work_parity", 0)
	_steer = state.get("steer", {}).duplicate()
	goal = state.goal
	goal_point = state.goal_point
	goal_target = state.goal_target
	planned_for = state.planned_for
	planned_tick = state.planned_tick
	direct = state.direct
	direct_start = state.direct_start
	no_direct_until = state.no_direct_until
	at_goal = state.at_goal
	attacking = state.attacking
	rally_tick = state.rally_tick
	role = state.role
	role_slot = state.role_slot
	role_target = state.role_target
	refilling = state.refilling
	combat.set_state(state.combat)
	gear.set_state(state.get("gear", {}))
	kit_picks = state.get("kit_picks", {}).duplicate()
	if state.has("kit_rng_seed"):
		kit_rng.seed = state.kit_rng_seed
		kit_rng.state = state.kit_rng_state
	station_until = state.get("station_until", -1)
	no_station_until = state.get("no_station_until", 0)
	deploy_retry = state.get("deploy_retry", 0)
	path.assign(state.path)
	path_index = state.path_index
	path_start = state.path_start
	var search = state.get("search")
	_search = RoutePlanner.Search.from_state(director.graph, search) if search != null else null
	_search_tick = state.get("search_tick", -1)
	avoid = state.avoid.duplicate()
	best_distance = state.best_distance
	leg_target = state.leg_target
	leg_ticks = state.leg_ticks
	no_progress = state.no_progress
	escapes = state.escapes
	escape = state.escape
	escape_ticks = state.escape_ticks
	escape_side = state.escape_side
	stuck = state.stuck
	was_dead = state.was_dead
	last_position = state.last_position
	goal_started = state.goal_started
	perception.set_state(state.perception)
	steering.set_state(state.steering)
	stats = state.stats.duplicate(true)
	if state.has("rng_seed"):
		rng.seed = state.rng_seed
		rng.state = state.rng_state


## An array of n zeros, for counts per weapon.
static func _zeros(n: int) -> Array:
	var out := []
	out.resize(n)
	out.fill(0)
	return out
