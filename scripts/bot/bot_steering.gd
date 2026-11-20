class_name BotSteering
extends RefCounted

## Turns a bot's planned route into a command each tick, the way a good
## player moves: look and push towards a point a little further along the
## route, ski whenever it keeps or builds speed, jet up climbs only once the
## speed won't carry it over and save energy on the way down, slow down
## before tight turns and the goal, and hop over things it runs into.

## Least energy a heavy waits for below a wall it has to jet over.
const HEAVY_WALL_ENERGY := 40.0
## Speed the bot slows to for the goal and the tightest turns, in m/s.
const ARRIVE_SPEED := 8.0
const CORNER_SPEED := 12.0
## Slowing the bot plans on when braking, in m/s². Braking on the ground is
## much harder, but a fast bot is often in the air.
const BRAKE := 12.0
## Below this speed on a climb the bot jets, if it has energy.
const CLIMB_SPEED := 18.0
## Energy a bot wants before it starts a jet climb, so it doesn't spend its
## last on the bottom of a hill.
const CLIMB_RESERVE := 30.0
## Energy a bot waits for when it's out below a climb it can't run up.
const REST_UNTIL := 95.0
## Ground flatter than this, as the floor normal's height, is good to stand
## on and wait for energy, about 30°.
const FLAT_ENOUGH := 0.86
## Ticks of jetting to get over something in the way, and the energy it
## needs to start. steer() runs every BotBrain.WORK_TICKS ticks.
const HOP_TICKS := 40
const HOP_ENERGY := 15.0

## Running in to their flag, the bot jets ahead while slower than this, in
## m/s, and with more energy than this.
const JET_IN_SPEED := 30.0
const JET_IN_ENERGY := 40.0

## Waiting for energy below a climb.
var resting := false
## Where it last waited for energy.
var rest_spot := Vector3.INF
## Ticks left of a hop over something in the way.
var hop_ticks := 0
## Jetting up a climb, which carries on until the energy runs low.
var climbing := false
## What it's doing, for the debug overlay.
var doing := ""


func reset() -> void:
	hop_ticks = 0
	climbing = false
	resting = false
	doing = ""


func steer(brain: BotBrain, _delta: float) -> PlayerCommand:
	var command := PlayerCommand.new()
	var s := brain.soldier
	var t := s.tuning
	var pos := s.at()
	var vh := Vector3(s.vel().x, 0.0, s.vel().z)
	var speed := vh.length()
	var lookahead := clampf(speed * 0.7, 6.0, 30.0)
	var prof_t := Time.get_ticks_usec() if Prof.on else 0
	var aim := brain.aim_point(lookahead)
	if Prof.on:
		Prof.add("steer.aim_point", Time.get_ticks_usec() - prof_t)
	var to_aim := aim - pos
	var flat := Vector3(to_aim.x, 0.0, to_aim.z)
	var dir := flat.normalized() if flat.length() > 0.1 else -s.back()
	var target := brain.target()
	var link := brain.current_link()
	var last := brain.is_last()

	# How fast to go: slow enough to stop at the goal and to make the next turn.
	var limit := t.max_speed
	var to_target := Vector2(target.x - pos.x, target.z - pos.z).length()
	if last:
		if brain.slow_at_end():
			limit = sqrt(ARRIVE_SPEED * ARRIVE_SPEED + 2.0 * BRAKE * to_target)
	else:
		var after := brain.director.graph.points[brain.path[brain.path_index + 1]]
		var into := Vector2(target.x - pos.x, target.z - pos.z)
		var out := Vector2(after.x - target.x, after.z - target.z)
		if into.length() > 0.1 and out.length() > 0.1:
			var turn := absf(into.angle_to(out))
			if turn > deg_to_rad(60.0):
				var corner := lerpf(25.0, CORNER_SPEED, clampf((turn - deg_to_rad(60.0)) / deg_to_rad(90.0), 0.0, 1.0))
				limit = sqrt(corner * corner + 2.0 * BRAKE * to_target)
	var heading_error := vh.angle_to(dir) if speed > 2.0 else 0.0
	var braking := speed > limit + 2.0 or (s.grounded and speed > 14.0 and heading_error > deg_to_rad(75.0))

	# Where to push. Skiing and in the air, pushing only adds speed in a
	# direction you're slower than a few m/s in, so to turn at speed the bot
	# pushes along the difference between where it's going and where it wants
	# to go.
	var wish := dir
	var correction := dir * speed - vh
	if braking:
		wish = (dir * minf(limit, t.run_speed) - vh).normalized()
	elif speed > t.run_speed + 1.0:
		wish = correction.normalized() if correction.length() > 0.3 else Vector3.ZERO

	# Skiing: whenever moving fast, in the air or going downhill, but not
	# while braking or slowly climbing, where running is quicker.
	# Up and down are along where the bot wants to go, and sliding the wrong
	# way it runs, which stops it quickest.
	var along := vh / speed if speed > 0.5 else dir
	var downhill := s.grounded and s.floor_normal.dot(dir) > 0.03
	var uphill := s.grounded and s.floor_normal.dot(dir) < -0.05
	var wrong_way := speed > 2.0 and heading_error > deg_to_rad(90.0)
	var ski := not braking and not (s.grounded and wrong_way) and (speed > t.run_speed + 1.5 or downhill or not s.grounded)
	if uphill and speed < t.run_speed + 1.0:
		ski = false

	# Jetting: over walls and gaps, and up climbs the speed won't carry.
	var jet := false
	var jump := false
	var rise := maxf(aim.y, target.y) - pos.y
	var carries := speed * speed / (2.0 * t.gravity)
	var wall_ahead := link != null and link.must_jet and to_target < 15.0 and target.y > pos.y - 0.5
	if Prof.on:
		prof_t = Time.get_ticks_usec()
	var blocked := hop_ticks == 0 and _blocked(s, dir)
	if Prof.on:
		Prof.add("steer.blocked", Time.get_ticks_usec() - prof_t)
	if blocked:
		# A jump clears about a metre, the jet more if there's energy for it.
		jump = s.grounded
		if s.energy > HOP_ENERGY:
			hop_ticks = HOP_TICKS
	# Energy the steep part of this leg needs on top of what the speed gives.
	var steep_need := 0.0
	if link != null and link.steep > 0.0 and target.y > pos.y + 3.0:
		steep_need = minf(maxf(link.steep - carries, 0.0) * RouteGraph.ENERGY_PER_METRE + 10.0, rest_until(s))
	if resting:
		# Out of energy below a climb it can't run up: wait for a tank.
		resting = s.energy < rest_until(s) and s.grounded
		climbing = not resting
	elif s.grounded and speed < 3.0 and rise > 3.0 and s.energy < CLIMB_RESERVE and brain.no_progress > 1.0 and pos.distance_to(rest_spot) > 5.0:
		# Only once in a place: if a full tank didn't get it moving, it's stuck.
		resting = true
		rest_spot = pos
	elif s.grounded and speed < 6.0 and not climbing and s.energy < steep_need and pos.distance_to(rest_spot) > 5.0:
		# Saves up before a steep climb instead of sliding back from half way.
		resting = true
		rest_spot = pos
	if resting:
		wish = rest_wish(s)
		ski = false
		brain.no_progress = 0.0
		doing = "wait for energy"
	elif hop_ticks > 0:
		hop_ticks = maxi(hop_ticks - BotBrain.WORK_TICKS, 0)
		jet = s.energy > 2.0
		doing = "hop"
	elif wall_ahead and s.grounded and s.energy < wall_energy(s, link) and not climbing:
		# Not enough energy to get over: wait for it by the wall.
		wish = Vector3.ZERO if to_target < 8.0 else dir
		ski = false
		brain.no_progress = 0.0
		doing = "wait for energy"
	elif wall_ahead:
		climbing = s.energy > 2.0
		jet = climbing
		jump = s.grounded
		doing = "jet over"
	elif rise > (0.3 if climbing else 1.5) and (carries < rise + 3.0 or speed < CLIMB_SPEED) and (climbing or s.vel().y > -3.0):
		if climbing:
			climbing = s.energy > 2.0
		else:
			climbing = s.energy > CLIMB_RESERVE
		jet = climbing
		doing = "jet climb" if jet else "climb"
	elif not s.grounded and s.vel().y < -2.0 and pos.y < target.y - 1.0 and s.energy > 10.0:
		# Falling short of a point above.
		jet = true
		doing = "jet gap"
	elif not braking and speed < JET_IN_SPEED and s.energy > JET_IN_ENERGY and s.vel().y < 4.0 and brain.wants_jet_in():
		# Builds speed on the run in to their flag.
		jet = true
		ski = true
		doing = "jet in"
	else:
		climbing = false
		doing = "brake" if braking else ("ski" if ski else "run")
	if not jet:
		climbing = false
	if jet and not braking:
		# The jet pushes along the push direction at speed, so push forward
		# with some correction.
		wish = (dir + correction / maxf(speed, 1.0) * 2.0).normalized()
	elif braking and not s.grounded and speed > limit + 8.0 and s.energy > 40.0:
		jet = true
		wish = -along
		doing = "air brake"

	command.yaw = atan2(-dir.x, -dir.z)
	command.pitch = clampf(atan2(to_aim.y, maxf(flat.length(), 1.0)), -0.6, 0.6)
	if wish != Vector3.ZERO:
		var local := Basis(Vector3.UP, command.yaw).inverse() * wish
		command.move = Vector2(local.x, -local.z).limit_length(1.0)
	if ski:
		command.buttons |= PlayerCommand.SKI
	if jet:
		command.buttons |= PlayerCommand.JET
	if jump:
		command.buttons |= PlayerCommand.JUMP
	return command


## Energy to wait for below a wall a link has to jet: a heavy's weak jet
## needs twice the link's and at least HEAVY_WALL_ENERGY.
static func wall_energy(s: Soldier, link: RouteGraph.Link) -> float:
	if s.loadout.armour == SoldierBody.Armour.HEAVY:
		return minf(maxf(link.energy * 2.0, HEAVY_WALL_ENERGY), rest_until(s))
	return link.energy


## Energy to wait for, at most a little under the armour's full tank.
static func rest_until(s: Soldier) -> float:
	return minf(REST_UNTIL, s.tuning.energy_max - 5.0)


## Where to walk while waiting for energy: down to flatter ground if it's
## standing on a slope it would slide on, else nowhere.
static func rest_wish(s: Soldier) -> Vector3:
	if not s.grounded or s.floor_normal.y >= FLAT_ENOUGH:
		return Vector3.ZERO
	var down := Vector3(s.floor_normal.x, 0.0, s.floor_normal.z)
	return down.normalized() if down.length() > 0.01 else Vector3.ZERO


## True if the soldier ran into a wall last tick while heading into it.
func _blocked(s: Soldier, dir: Vector3) -> bool:
	# Walls are what's steeper than the floor angle (50°), which takes in
	# everything this counts.
	for normal in s.wall_normals():
		if absf(normal.y) < 0.4 and normal.dot(dir) < -0.5:
			return true
	return false


func get_state() -> Dictionary:
	return { "hop_ticks": hop_ticks, "climbing": climbing, "resting": resting, "rest_spot": rest_spot, "doing": doing }


func set_state(state: Dictionary) -> void:
	hop_ticks = state.hop_ticks
	climbing = state.climbing
	resting = state.resting
	rest_spot = state.rest_spot
	doing = state.doing
