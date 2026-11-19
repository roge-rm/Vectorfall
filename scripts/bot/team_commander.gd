class_name TeamCommander
extends RefCounted

## One team's commander, the same code for both teams. It hands out the bots'
## roles from the score, the time, both flags and what the team knows of the
## enemy: what its bots saw, heard or were hit by, faded over time. Each person
## on the team counts as one of its players, with a role read from what they
## do, so the bots fill the rest. It learns within a match which lanes enemy
## attackers come in by and enemy carriers run home by, and which lanes worked
## for its own carriers. It thinks twice a second on its own tick, uses no ray
## casts and no random numbers, and keeps everything in get_state().

## Ticks between thinks; team 1 thinks half way between team 0's.
const THINK_TICKS := 30
## Seconds in a role before a bot can be moved, unless the flags call for it.
const MIN_ROLE_TIME := 10.0
## Seconds an enemy is remembered after the last report of it.
const KNOWN_MEMORY := 12.0
## Seconds of a person's movement read for their role, and how long a new
## reading has to hold before it counts.
const PERSON_WINDOW := 4.0
const PERSON_SETTLE := 2.0
## A person this close to their stand on average is defending, in metres.
const HOME_RANGE := 90.0
## Known enemies this close to our stand are a threat, in metres.
const THREAT_RANGE := 160.0
## Seconds extra defence stays after a threat goes.
const THREAT_HOLD := 10.0
## Enemy approaches are read between these distances from our stand.
const APPROACH_NEAR := 60.0
const APPROACH_FAR := 320.0
## Warnings: enemies this close behind a person, at most one each this often.
const WARN_RANGE := 60.0
const WARN_GAP := 6.0
## The nearest bot this close to a person covers them, picking targets near
## them first, in metres.
const COVER_RANGE := 100.0
## Share of the time left below which a team behind presses.
const LATE := 0.35
## Offence this close to the enemy stand, or this much closer to it than the
## enemy carrier, is committed and keeps attacking when our flag is taken, in
## metres.
const COMMITTED_RANGE := 250.0
const COMMITTED_AHEAD := 150.0
## Metres of route a carrier going home by a lane is worth for each share of
## the enemy carriers seen to use it.
const ESCAPE_WEIGHT := 400.0
## Our carrier waits this far from our stand while our flag is out, in metres.
const HIDE_NEAR := 40.0
const HIDE_FAR := 120.0
## An enemy carrier this close to its stand is home, waiting for its flag,
## and every chaser goes for it, in metres.
const CARRIER_HOME := 150.0
## Seconds between role count samples for the report.
const HISTORY_GAP := 10.0
## Decisions kept for the report and overlay.
const DECISIONS_KEPT := 400
## Roles filled first come first.
const FILL_ORDER: Array[int] = [BotBrain.Role.CHASE, BotBrain.Role.ESCORT, BotBrain.Role.DEFENCE, BotBrain.Role.LIGHT_DEFENCE, BotBrain.Role.OFFENCE, BotBrain.Role.MIDFIELD]
## Roles a bot can be pulled from at once when the flags call for it.
const URGENT_ROLES: Array[int] = [BotBrain.Role.CHASE, BotBrain.Role.ESCORT]

## Seconds an order from a person lasts, unless it's done sooner.
const ORDER_TIME := 50.0
## Bots an order sends: to defence, to escort, to attack.
const ORDER_DEFENDERS := 2
const ORDER_ESCORTS := 2
const ORDER_ATTACKERS := 2
## Seconds between reports to the team, and before the same report again.
## Answers to orders and warnings don't wait for the first.
const REPORT_GAP := 3.0
const REPEAT_GAP := 15.0
## Lines kept for the report and tests.
const CHAT_KEPT := 100

## Sent when a bot sees an enemy coming up behind a person on its team.
signal warned(team: int, person_id: int, enemy_id: int)
## A bot says a line (BotLines.Line) to its team, as text and later voice.
signal said(team: int, speaker_id: int, line: int, text: String)

var team := 0
var director: BotDirector
var game: Match
var lanes: Lanes
var think_offset := 0
## Enemy id to { position, velocity, tick, approach }: what the team knows.
## approach is the lane it was last seen coming at our flag in, or -1.
var known := {}
## Bot id to the tick it took its role.
var role_since := {}
## Person id to { role, pending, pending_tick, samples }, samples being
## [tick, position] pairs over PERSON_WINDOW.
var people := {}
## Learnt weights per lane: enemies coming at our flag, enemy carriers going
## home, and our carriers (up for captures, down for deaths on the way).
var attack_lanes: Array[float] = []
var escape_lanes: Array[float] = []
var carry_lanes: Array[float] = []
## Carrier id to the lanes it has used with the flag.
var carrier_lanes := {}
## The enemy carrier's likely lanes home, likeliest first.
var escape_order: Array[int] = []
## Bot id to the flag team it's sent to pick up or return.
var pickups := {}
## Bot id to the person it covers.
var covers := {}
## Person id to the tick they were last warned.
var warn_ticks := {}
## Team role counts it wants, role to count, and a line on what it's after.
var wants := {}
var plan_text := ""
var threat_until := -1
var decisions: Array[Dictionary] = []
var history: Array[Dictionary] = []
var _history_tick := -1000000
## Bot id to a role a person gave it: { role, target, until, order, by }.
## until is a tick, or -1 for a role from a person in commander mode, kept
## until they change it. The commander plans the rest round these.
var order_locks := {}
## Offence goes for their flag without waiting for the others until this tick.
var urgent_until := -1
## Lines said: the last report's tick, the tick each line and subject was last
## said, and the last CHAT_KEPT as { seconds, speaker, line, text }.
var report_tick := -1000000
var said_ticks := {}
var chat: Array[Dictionary] = []
## The lane last reported for the enemy carrier of our flag, or -1.
var reported_lane := -1


func _init(on_team: int, bots: BotDirector) -> void:
	team = on_team
	director = bots
	game = bots.game
	think_offset = team * THINK_TICKS / 2


## Connects to the match's flag events for learning. Called once by the
## director.
func watch() -> void:
	game.flag_taken.connect(_on_flag_taken)
	game.flag_dropped.connect(_on_flag_dropped)
	game.flag_captured.connect(_on_flag_captured)
	game.flag_returned.connect(_on_flag_returned)
	game.ordered.connect(_on_ordered)


func _lanes() -> Lanes:
	if lanes == null:
		lanes = director.lanes()
		for k in lanes.count:
			# The front is the likeliest way in to start with.
			var prior := 1.5 if lanes.count == 3 and k == 1 else 1.0
			attack_lanes.append(prior)
			escape_lanes.append(prior)
			carry_lanes.append(0.0)
	return lanes


## Called every tick; thinks on its own tick.
func tick() -> void:
	if (game.tick + think_offset) % THINK_TICKS == 0:
		if Prof.on:
			var prof_t := Time.get_ticks_usec()
			think()
			Prof.add("commander%d" % team, Time.get_ticks_usec() - prof_t)
		else:
			think()


func think(force := false) -> void:
	if not game.flags.is_empty():
		_lanes()
	_update_knowledge()
	_read_people()
	if not game.flags.is_empty():
		_learn()
		_plan_chase()
		_report_carrier()
	_check_orders()
	_assign(force)
	_assign_pickups()
	_help_people()
	if not force and game.tick - _history_tick >= int(HISTORY_GAP * 60.0):
		_history_tick = game.tick
		history.append({ "seconds": snappedf(game.tick / 60.0, 0.1), "roles": role_counts_named(), "plan": plan_text })


## The team's soldiers by id, bots and people.
func members() -> Array[Soldier]:
	var found: Array[Soldier] = []
	var ids := game.entities.keys()
	ids.sort()
	for id: int in ids:
		var s := game.soldier(id)
		if s != null and s.team == team:
			found.append(s)
	return found


func brains() -> Array[BotBrain]:
	var found: Array[BotBrain] = []
	for brain in director.brains:
		if brain.soldier.team == team:
			found.append(brain)
	return found


func is_person(id: int) -> bool:
	return game.soldier(id) != null and director.brain_of(id) == null


## Merges what each bot knows into the team's picture, and forgets old reports.
func _update_knowledge() -> void:
	for brain in brains():
		if brain.soldier.dead:
			continue
		var contacts := brain.perception.contacts
		var ids := contacts.keys()
		ids.sort()
		for id: int in ids:
			var contact: Dictionary = contacts[id]
			if not contact.noticed:
				continue
			var entry: Dictionary = known.get(id, { "tick": -1000000, "approach": -1 })
			if contact.tick > entry.tick:
				entry.position = contact.position
				entry.velocity = contact.velocity
				entry.tick = contact.tick
				known[id] = entry
	for id: int in known.keys():
		var other := game.soldier(id)
		if other == null or other.dead or (game.tick - known[id].tick) / 60.0 > KNOWN_MEMORY:
			known.erase(id)


## Where the team thinks an enemy is now, or null if it doesn't know.
func known_position(id: int) -> Variant:
	if not known.has(id):
		return null
	var entry: Dictionary = known[id]
	var age := minf((game.tick - entry.tick) / 60.0, BotPerception.PREDICT_LIMIT)
	return entry.position + entry.velocity * age


## Known enemies close to our stand, nearest first, as [id, position].
func threats(reach: float) -> Array:
	var found := []
	if not game.stands.has(team):
		return found
	var stand: Vector3 = game.stands[team]
	var ids := known.keys()
	ids.sort()
	for id: int in ids:
		var at: Vector3 = known_position(id)
		if at.distance_to(stand) < reach:
			found.append([id, at])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[1].distance_to(stand) < b[1].distance_to(stand))
	return found


## Works out each person's role from where they've been over the last few
## seconds. A new reading has to hold PERSON_SETTLE seconds, except carrying
## the flag, which counts at once.
func _read_people() -> void:
	# People who left the match are forgotten.
	for id: int in people.keys():
		if game.soldier(id) == null:
			people.erase(id)
	for s in members():
		var id := s.entity_id
		if not is_person(id):
			continue
		var entry: Dictionary = people.get(id, { "role": BotBrain.Role.OFFENCE, "pending": -1, "pending_tick": 0, "samples": [] })
		people[id] = entry
		var samples: Array = entry.samples
		if s.dead:
			samples.clear()
			continue
		samples.append([game.tick, s.at()])
		while samples.size() > 1 and (game.tick - samples[0][0]) / 60.0 > PERSON_WINDOW:
			samples.pop_front()
		if game.flags.is_empty():
			continue
		var carrying := game.carried_flag(id) != null
		var enemy_carrier: Variant = null
		var own: Flag = game.flags.get(team)
		if own != null and own.mode == Flag.Mode.CARRIED:
			enemy_carrier = own.at()
		var reading := read_person(samples, carrying, game.stands[team], game.stands[1 - team], enemy_carrier)
		if reading < 0 or reading == entry.role:
			entry.pending = -1
			continue
		if carrying or reading != entry.pending:
			entry.pending = reading
			entry.pending_tick = game.tick
		if carrying or (game.tick - entry.pending_tick) / 60.0 >= PERSON_SETTLE:
			_decide("%s reads as %s" % [game.soldier(id).display_name, BotBrain.ROLE_NAMES[reading]])
			entry.role = reading
			entry.pending = -1


## A person's role from samples of [tick, position] over a few seconds, or -1
## if there aren't enough yet. enemy_carrier is where our flag's carrier is, or
## null.
static func read_person(samples: Array, carrying: bool, home: Vector3, enemy_home: Vector3, enemy_carrier: Variant) -> int:
	if carrying:
		return BotBrain.Role.OFFENCE
	if samples.size() < 2:
		return -1
	var first: Vector3 = samples[0][1]
	var last: Vector3 = samples[samples.size() - 1][1]
	var seconds: float = (samples[samples.size() - 1][0] - samples[0][0]) / 60.0
	if seconds < PERSON_SETTLE:
		return -1
	var home_sum := 0.0
	for sample: Array in samples:
		home_sum += (sample[1] as Vector3).distance_to(home)
	if home_sum / samples.size() < HOME_RANGE and last.distance_to(home) < HOME_RANGE:
		return BotBrain.Role.DEFENCE
	if enemy_carrier != null:
		var c: Vector3 = enemy_carrier
		if last.distance_to(c) < 200.0 and first.distance_to(c) - last.distance_to(c) > 2.0 * seconds:
			return BotBrain.Role.CHASE
	var closing := (first.distance_to(enemy_home) - last.distance_to(enemy_home)) / seconds
	if closing > 4.0 or last.distance_to(enemy_home) < 120.0:
		return BotBrain.Role.OFFENCE
	return BotBrain.Role.MIDFIELD


## Team role counts for a team of size, everyone counted, from the situation:
## { diff (our score less theirs), late (time nearly up), own_taken (our flag
## carried off), we_carry (we hold theirs), runner (a person heading for their
## flag), threat (enemies near our flag), committed (offence close to their
## flag, which keeps attacking when ours is taken) }.
static func plan_counts(size: int, situation: Dictionary) -> Dictionary:
	var c := {}
	for role in BotBrain.ROLE_NAMES.size():
		c[role] = 0
	if size <= 0:
		return c
	var diff: int = situation.get("diff", 0)
	var defence := 1 if size >= 2 else 0
	var light := 1 if size >= 4 else 0
	var mid := 0
	# Ahead, more defence and someone in the middle; behind with time running
	# out, more pressure.
	if diff >= 1:
		light += 1
		mid += 1 if size >= 7 else 0
	if diff >= 2:
		defence += 1
	if situation.get("threat", false) and size >= 7:
		light += 1
	if diff < 0 and situation.get("late", false):
		light = 0
		mid = 0
	mid = maxi(mid, 0)
	# Offence keeps at least one, or two on a team of 5 or more.
	var min_offence := 2 if size >= 5 else 1
	while defence + light + mid > size - min_offence and (mid > 0 or light > 0):
		if mid > 0:
			mid -= 1
		else:
			light -= 1
	defence = mini(defence, maxi(size - min_offence, 0))
	var offence := size - defence - light - mid
	var escort := 0
	var chase := 0
	var we_carry: bool = situation.get("we_carry", false)
	if situation.get("own_taken", false):
		# Everyone useful after our flag, with one at home, offence close to
		# theirs and, if we have theirs, the carrier and one escort.
		escort = 1 if we_carry and size >= 4 else 0
		var committed: int = 0 if we_carry else mini(situation.get("committed", 0), offence)
		offence = 1 if we_carry else committed
		chase = maxi(size - defence - escort - offence, 0)
		light = 0
		mid = 0
	elif we_carry:
		# Escorts come from the offence that has nothing to take, then midfield.
		escort = mini(3 if size >= 6 else 1, maxi(offence - 1 + mid, 0))
		var from_offence := mini(escort, offence - 1)
		offence -= from_offence
		mid -= escort - from_offence
	if situation.get("runner", false) and not we_carry and offence >= 2:
		escort += 1
		offence -= 1
	c[BotBrain.Role.OFFENCE] = offence
	c[BotBrain.Role.DEFENCE] = defence
	c[BotBrain.Role.MIDFIELD] = mid
	c[BotBrain.Role.ESCORT] = escort
	c[BotBrain.Role.LIGHT_DEFENCE] = light
	c[BotBrain.Role.CHASE] = chase
	return c


func _situation() -> Dictionary:
	var own: Flag = game.flags.get(team)
	var theirs: Flag = game.flags.get(1 - team)
	var threat := threats(THREAT_RANGE).size()
	if threat >= 2 and own != null and own.mode == Flag.Mode.HOME:
		threat_until = game.tick + int(THREAT_HOLD * 60.0)
	var runner := false
	for id: int in people:
		if people[id].role == BotBrain.Role.OFFENCE and game.carried_flag(id) == null and not game.soldier(id).dead:
			runner = true
	return {
		"diff": game.scores[team] - game.scores[1 - team] if game.scores.size() > 1 else 0,
		"late": game.settings.time_limit > 0.0 and game.time_left < game.settings.time_limit * LATE,
		"own_taken": own != null and own.mode == Flag.Mode.CARRIED,
		"we_carry": theirs != null and theirs.mode == Flag.Mode.CARRIED,
		"runner": runner,
		"threat": game.tick < threat_until,
		"committed": _committed(),
	}


## Living offence bots close to the enemy stand, or ahead of the carrier of
## our flag on its way there: going for their flag stops it scoring.
func _committed() -> int:
	var n := 0
	var stand: Vector3 = game.stands[1 - team]
	var own: Flag = game.flags[team]
	var carrier_left := own.at().distance_to(stand) if own.mode == Flag.Mode.CARRIED else 0.0
	for brain in brains():
		if brain.role != BotBrain.Role.OFFENCE or brain.soldier.dead:
			continue
		var left := brain.soldier.at().distance_to(stand)
		if left < COMMITTED_RANGE or left < carrier_left - COMMITTED_AHEAD:
			n += 1
	return n


## Who a role is best given to, lower first: closest to where the role is.
func _fitness(brain: BotBrain, role: int) -> float:
	var s := brain.soldier
	var at := s.at()
	var penalty := 500.0 if s.dead else 0.0
	if game.flags.is_empty():
		return penalty
	penalty += _leaning(brain, role)
	var own: Flag = game.flags[team]
	match role:
		BotBrain.Role.DEFENCE, BotBrain.Role.LIGHT_DEFENCE:
			return penalty + at.distance_to(game.stands[team])
		BotBrain.Role.CHASE:
			return penalty + at.distance_to(own.at())
		BotBrain.Role.ESCORT:
			var runner := escort_target()
			return penalty + (at.distance_to(game.soldier(runner).at()) if runner != 0 else 0.0)
		BotBrain.Role.OFFENCE:
			return penalty + at.distance_to(game.stands[1 - team])
	return penalty


## Metres a bot's personality takes off its fitness for a role it likes, or
## adds for one it doesn't: careful bots like defence, snipers the middle.
func _leaning(brain: BotBrain, role: int) -> float:
	match brain.personality:
		BotBrain.Personality.CAREFUL:
			if role == BotBrain.Role.DEFENCE or role == BotBrain.Role.LIGHT_DEFENCE:
				return -60.0
			if role == BotBrain.Role.OFFENCE:
				return 60.0
		BotBrain.Personality.SNIPER:
			if role == BotBrain.Role.MIDFIELD:
				return -80.0
		BotBrain.Personality.AGGRESSIVE:
			if role == BotBrain.Role.OFFENCE or role == BotBrain.Role.CHASE:
				return -30.0
	return 0.0


## Who escorts go with: our carrier, or else a person heading for their flag,
## or 0.
func escort_target() -> int:
	var theirs: Flag = game.flags.get(1 - team)
	if theirs != null and theirs.mode == Flag.Mode.CARRIED:
		return theirs.carrier_id
	var ids := people.keys()
	ids.sort()
	for id: int in ids:
		if people[id].role == BotBrain.Role.OFFENCE and not game.soldier(id).dead:
			return id
	return 0


## Hands out roles to the bots: works out the team's counts, takes off what
## the people are doing, keeps bots where they are when it can and moves the
## fewest. A bot stays in a role MIN_ROLE_TIME before moving, unless it's
## going to or from chasing or escorting.
func _assign(force: bool) -> void:
	var team_brains := brains()
	var people_count := 0
	for s in members():
		if is_person(s.entity_id):
			people_count += 1
	var size := team_brains.size() + people_count
	var situation := _situation() if not game.flags.is_empty() else {}
	wants = plan_counts(size, situation)
	var want := wants.duplicate()
	# People fill their own role's places first.
	var ids := people.keys()
	ids.sort()
	for id: int in ids:
		var role: int = people[id].role
		if want[role] > 0:
			want[role] -= 1
		else:
			for other: int in [BotBrain.Role.OFFENCE, BotBrain.Role.MIDFIELD, BotBrain.Role.LIGHT_DEFENCE, BotBrain.Role.ESCORT, BotBrain.Role.CHASE, BotBrain.Role.DEFENCE]:
				if want[other] > 0:
					want[other] -= 1
					break
	for _k in people_count - ids.size():
		# People not read yet count as offence.
		if want[BotBrain.Role.OFFENCE] > 0:
			want[BotBrain.Role.OFFENCE] -= 1
	var carrier := 0
	var theirs: Flag = game.flags.get(1 - team)
	if theirs != null and theirs.mode == Flag.Mode.CARRIED:
		carrier = theirs.carrier_id
	var next := {}
	var free: Array[BotBrain] = []
	# The carrier is the runner, whatever it was.
	for brain in team_brains:
		if brain.soldier.entity_id == carrier:
			next[brain] = BotBrain.Role.OFFENCE
			want[BotBrain.Role.OFFENCE] = maxi(want[BotBrain.Role.OFFENCE] - 1, 0)
	# Bots a person gave a role keep it, and fill its places first.
	for brain in team_brains:
		var lock: Dictionary = order_locks.get(brain.soldier.entity_id, {})
		if not lock.is_empty() and not next.has(brain):
			next[brain] = lock.role
			want[lock.role] = maxi(want[lock.role] - 1, 0)
	# Keep the best placed in each role up to its count.
	for role in BotBrain.ROLE_NAMES.size():
		var in_role: Array[BotBrain] = []
		for brain in team_brains:
			if not next.has(brain) and brain.role == role:
				in_role.append(brain)
		in_role.sort_custom(func(a: BotBrain, b: BotBrain) -> bool: return _better(a, b, role))
		var keep: int = want.get(role, 0)
		for k in in_role.size():
			if k < keep:
				next[in_role[k]] = role
				want[role] -= 1
			else:
				free.append(in_role[k])
	# Fill the places left, most urgent first, from the free bots that may move.
	for role in FILL_ORDER:
		while want[role] > 0:
			var pick: BotBrain = null
			for brain in free:
				if (force or _may_move(brain, role)) and (pick == null or _better(brain, pick, role)):
					pick = brain
			if pick == null and URGENT_ROLES.has(role):
				# Pulled from a role it's in for now, but never the last defence.
				for brain in team_brains:
					var current: int = next.get(brain, -1)
					if current == BotBrain.Role.OFFENCE and brain.soldier.entity_id == carrier:
						continue
					if order_locks.has(brain.soldier.entity_id):
						continue
					if current in [BotBrain.Role.OFFENCE, BotBrain.Role.MIDFIELD, BotBrain.Role.LIGHT_DEFENCE] and (pick == null or _better(brain, pick, role)):
						pick = brain
				if pick != null:
					want[next[pick]] += 1
			if pick == null:
				break
			free.erase(pick)
			next[pick] = role
			want[role] -= 1
	# Anyone left over stays where it was for now.
	for brain in free:
		next[brain] = brain.role
	var escort_of := escort_target()
	var enemy_carrier := 0
	var own: Flag = game.flags.get(team)
	if own != null and own.mode == Flag.Mode.CARRIED:
		enemy_carrier = own.carrier_id
	var slots := {}
	# Chasers take slots nearest the carrier first, so the nearest trails it.
	var ordered := team_brains.duplicate()
	ordered.sort_custom(func(a: BotBrain, b: BotBrain) -> bool:
		if next[a] != next[b]:
			return next[a] < next[b]
		if next[a] == BotBrain.Role.CHASE:
			return _better(a, b, BotBrain.Role.CHASE)
		return a.soldier.entity_id < b.soldier.entity_id)
	for brain: BotBrain in ordered:
		var role: int = next[brain]
		var id := brain.soldier.entity_id
		if role != brain.role or not role_since.has(id):
			if role_since.has(id):
				_decide("%s %s to %s" % [brain.soldier.display_name, BotBrain.ROLE_NAMES[brain.role], BotBrain.ROLE_NAMES[role]])
			role_since[id] = game.tick
			brain.role = role
		brain.role_slot = slots.get(role, 0)
		slots[role] = brain.role_slot + 1
		brain.role_target = escort_of if role == BotBrain.Role.ESCORT else (enemy_carrier if role == BotBrain.Role.CHASE else 0)
		var lock: Dictionary = order_locks.get(id, {})
		if not lock.is_empty() and lock.role == role and lock.target != 0:
			brain.role_target = lock.target
	var text := _describe_plan(situation)
	if text != plan_text:
		plan_text = text
		_decide(text)


## True if a is better placed than b for a role, ties going to the lower id.
func _better(a: BotBrain, b: BotBrain, role: int) -> bool:
	var fa := _fitness(a, role)
	var fb := _fitness(b, role)
	if fa != fb:
		return fa < fb
	return a.soldier.entity_id < b.soldier.entity_id


func _may_move(brain: BotBrain, to: int) -> bool:
	if URGENT_ROLES.has(to) or URGENT_ROLES.has(brain.role):
		return true
	return (game.tick - int(role_since.get(brain.soldier.entity_id, -1000000))) / 60.0 >= MIN_ROLE_TIME


func _describe_plan(situation: Dictionary) -> String:
	var parts: Array[String] = []
	for role in BotBrain.ROLE_NAMES.size():
		if wants.get(role, 0) > 0:
			parts.append("%d %s" % [wants[role], BotBrain.ROLE_NAMES[role]])
	var why: Array[String] = []
	if situation.get("own_taken", false):
		why.append("our flag taken")
	if situation.get("we_carry", false):
		why.append("we have theirs")
	if situation.get("threat", false):
		why.append("enemies near our flag")
	if situation.get("late", false) and situation.get("diff", 0) < 0:
		why.append("behind late")
	elif situation.get("diff", 0) > 0:
		why.append("ahead")
	if situation.get("runner", false):
		why.append("a person runs for theirs")
	return ", ".join(parts) + ("" if why.is_empty() else " (" + ", ".join(why) + ")")


## Learns from where known enemies and carriers go: enemies closing on our
## flag mark the lane they come in by, carriers the lanes they run.
func _learn() -> void:
	var stand: Vector3 = game.stands[team]
	var ids := known.keys()
	ids.sort()
	for id: int in ids:
		var entry: Dictionary = known[id]
		if game.tick - entry.tick > THINK_TICKS:
			continue
		var at: Vector3 = entry.position
		var distance := at.distance_to(stand)
		var toward := (entry.velocity as Vector3).dot((stand - at).normalized())
		if distance > APPROACH_NEAR and distance < APPROACH_FAR and toward > 3.0:
			var lane := lanes.lane_of(at)
			entry.approach = lane
			attack_lanes[lane] += 0.05
	for flag_team: int in game.flags:
		var flag := game.flags[flag_team]
		if flag.mode != Flag.Mode.CARRIED:
			continue
		var carrier := game.soldier(flag.carrier_id)
		if carrier == null or not lanes.in_lanes(carrier.at()):
			continue
		# Our flag's carrier is public, shown on everyone's screen.
		var lane := lanes.lane_of(carrier.at())
		var used: Array = carrier_lanes.get(carrier.entity_id, [])
		if not used.has(lane):
			used.append(lane)
		carrier_lanes[carrier.entity_id] = used
		if flag_team == team:
			escape_lanes[lane] += 0.05


## Orders the lanes the enemy carrier is likeliest to take home by: how far
## out of its way each one is, less what the team has seen enemy carriers do.
func _plan_chase() -> void:
	escape_order.clear()
	var own: Flag = game.flags[team]
	if own.mode != Flag.Mode.CARRIED:
		return
	var at := own.at()
	var home: Vector3 = game.stands[1 - team]
	var total := 0.0
	for w in escape_lanes:
		total += w
	var costs := {}
	for k in lanes.count:
		var a := lanes.approach(1 - team, k)
		costs[k] = at.distance_to(a) + a.distance_to(home) - ESCAPE_WEIGHT * escape_lanes[k] / maxf(total, 0.001)
		escape_order.append(k)
	escape_order.sort_custom(func(a: int, b: int) -> bool: return costs[a] < costs[b] or (costs[a] == costs[b] and a < b))


## Where a chaser in a slot heads, as [position, cutting off]: slot 0 and
## anyone close trail the carrier, the others cut off its likely lanes home,
## or wait at its stand once it's past them.
func chase_point(slot: int, from: Vector3) -> Array:
	var own: Flag = game.flags[team]
	var at := own.at()
	var lead := clampf(at.distance_to(from) / 40.0, 0.0, 2.0)
	var carrier := game.soldier(own.carrier_id)
	var trail := at + (carrier.vel() * lead if carrier != null else Vector3.ZERO)
	if slot == 0 or escape_order.is_empty() or from.distance_to(at) < 60.0 or slot > escape_order.size() + 1:
		return [trail, false]
	# Home or standing still, it's waiting for its own flag: everyone goes for it.
	var home: Vector3 = game.stands[1 - team]
	if at.distance_to(home) < CARRIER_HOME or (carrier != null and carrier.horizontal_speed() < 6.0):
		return [trail, false]
	# Their stand's route graph point, so the way there goes up the ramp.
	var stands := director.graph.interest_points(RouteGraph.FLAG_STAND, 1 - team)
	if not stands.is_empty():
		home = director.graph.points[stands[0]]
	if slot == escape_order.size() + 1:
		return [home, true]
	var cut := lanes.approach(1 - team, escape_order[slot - 1])
	if at.distance_to(home) < cut.distance_to(home) + 20.0:
		return [home, true]
	return [cut, true]


## Where light defence waits: part way out towards the lane enemies come in by
## most, the next lane for the next one.
func watch_point(slot: int) -> Vector3:
	var stand: Vector3 = game.stands[team]
	if lanes == null or lanes.count == 0:
		return stand
	var order := range(lanes.count)
	order.sort_custom(func(a: int, b: int) -> bool: return attack_lanes[a] > attack_lanes[b] or (attack_lanes[a] == attack_lanes[b] and a < b))
	var lane: int = order[slot % order.size()]
	var at := stand.lerp(lanes.approach(team, lane), 0.5)
	# On the route graph, so the way there is one bots can take.
	var point := director.graph.nearest(at)
	return director.graph.points[point] if point >= 0 else at


## The lane enemies come in by most.
func main_threat_lane() -> int:
	var best := 0
	for k in attack_lanes.size():
		if attack_lanes[k] > attack_lanes[best]:
			best = k
	return best


## Route graph points within reach of an enemy the team knows of, in point
## order, for a carrier's way home to go round.
func points_near_enemies(reach: float) -> Array[int]:
	var found: Array[int] = []
	var spots: Array[Vector3] = []
	var ids := known.keys()
	ids.sort()
	for id: int in ids:
		spots.append(known_position(id))
	if spots.is_empty():
		return found
	var points := director.graph.points
	for k in points.size():
		for at in spots:
			if points[k].distance_squared_to(at) < reach * reach:
				found.append(k)
				break
	return found


## Where our carrier waits while our flag is carried off: the route graph
## point HIDE_NEAR to HIDE_FAR metres from our stand furthest from the enemies
## the team knows of, nearer the stand on a tie.
func hide_point() -> Vector3:
	var stand: Vector3 = game.stands[team]
	var graph := director.graph
	var spots: Array[Vector3] = []
	var ids := known.keys()
	ids.sort()
	for id: int in ids:
		spots.append(known_position(id))
	var own: Flag = game.flags[team]
	if own.mode == Flag.Mode.CARRIED:
		spots.append(own.at())
	var best := stand
	var best_score := -INF
	for k in graph.points.size():
		var p := graph.points[k]
		var d := p.distance_to(stand)
		if d < HIDE_NEAR or d > HIDE_FAR:
			continue
		var clear := 200.0
		for at in spots:
			clear = minf(clear, p.distance_to(at))
		var score := clear - d * 0.1
		if score > best_score:
			best_score = score
			best = p
	return best


## Extra seconds for a carrier's route through each lane's links, from how our
## carriers did in each: nothing for the best lane, up to 2 a 100 m for one
## much worse.
func carry_costs() -> Dictionary:
	var costs := {}
	if lanes == null or lanes.count == 0:
		return costs
	var best: float = carry_lanes.max()
	for k in lanes.count:
		var worse := clampf(best - carry_lanes[k], 0.0, 2.0)
		if worse <= 0.0:
			continue
		for link: RouteGraph.Link in lanes.lane_links[k]:
			costs[link] = worse * 1.0 * link.length / 100.0
	return costs


## Sends the nearest bots to a dropped flag: two to return ours, one to pick
## up theirs.
func _assign_pickups() -> void:
	pickups.clear()
	for flag_team: int in game.flags:
		var flag := game.flags[flag_team]
		if flag.mode != Flag.Mode.DROPPED:
			continue
		var at := flag.at()
		var ranked: Array[BotBrain] = []
		for brain in brains():
			if not brain.soldier.dead and game.carried_flag(brain.soldier.entity_id) == null:
				ranked.append(brain)
		ranked.sort_custom(func(a: BotBrain, b: BotBrain) -> bool:
			var da := a.soldier.at().distance_to(at)
			var db := b.soldier.at().distance_to(at)
			return da < db or (da == db and a.soldier.entity_id < b.soldier.entity_id))
		var count := 2 if flag_team == team else 1
		for k in mini(count, ranked.size()):
			pickups[ranked[k].soldier.entity_id] = flag_team


## Picks a bot to cover each person, and warns a person of a known enemy
## coming up behind them.
func _help_people() -> void:
	covers.clear()
	var ids := people.keys()
	ids.sort()
	for id: int in ids:
		var person := game.soldier(id)
		if person == null or person.dead:
			continue
		var pos := person.at()
		var best: BotBrain = null
		for brain in brains():
			if brain.soldier.dead or game.carried_flag(brain.soldier.entity_id) != null:
				continue
			var d := brain.soldier.at().distance_to(pos)
			if d < COVER_RANGE and (best == null or d < best.soldier.at().distance_to(pos)):
				best = brain
		if best != null:
			covers[best.soldier.entity_id] = id
		var lock_ids := order_locks.keys()
		lock_ids.sort()
		for bot_id: int in lock_ids:
			if order_locks[bot_id].order == Orders.Kind.COVER_ME and order_locks[bot_id].target == id:
				covers[bot_id] = id
		if game.tick - int(warn_ticks.get(id, -1000000)) < int(WARN_GAP * 60.0):
			continue
		var facing := Vector3(-sin(person.yaw), 0.0, -cos(person.yaw))
		var enemy_ids := known.keys()
		enemy_ids.sort()
		for enemy_id: int in enemy_ids:
			if game.tick - known[enemy_id].tick > THINK_TICKS * 2:
				continue
			var at: Vector3 = known[enemy_id].position
			var to := Vector3(at.x - pos.x, 0.0, at.z - pos.z)
			if to.length() < WARN_RANGE and to.length() > 1.0 and facing.angle_to(to) > deg_to_rad(120.0):
				warn_ticks[id] = game.tick
				_decide("warn %s of %s behind" % [person.display_name, game.soldier(enemy_id).display_name])
				warned.emit(team, id, enemy_id)
				var speaker := _nearest_bot(pos)
				if speaker != null:
					say(speaker.soldier.entity_id, BotLines.Line.BEHIND_YOU, "", true, str(id))
				break


func _on_flag_taken(flag_team: int, soldier_id: int) -> void:
	var taker := game.soldier(soldier_id)
	if flag_team == team:
		var speaker := _nearest_bot(game.stands.get(team, Vector3.ZERO))
		if speaker != null:
			say(speaker.soldier.entity_id, BotLines.Line.FLAG_TAKEN)
		reported_lane = -1
	elif taker != null and taker.team == team:
		var speaker := director.brain_of(soldier_id)
		if speaker == null:
			speaker = _nearest_bot(taker.at())
		if speaker != null:
			say(speaker.soldier.entity_id, BotLines.Line.WE_HAVE_FLAG)
		# Their flag is taken: an order to take it is done.
		var ids := order_locks.keys()
		ids.sort()
		for bot_id: int in ids:
			if order_locks[bot_id].order == Orders.Kind.TAKE_FLAG:
				order_locks.erase(bot_id)
		urgent_until = -1
	if flag_team != team or lanes == null:
		return
	var entry: Dictionary = known.get(soldier_id, {})
	if entry.get("approach", -1) >= 0:
		attack_lanes[entry.approach] += 2.0
		_decide("enemy took our flag from the %s lane" % lanes.name_of(entry.approach))
	else:
		_decide("enemy took our flag")


func _on_flag_dropped(flag_team: int, soldier_id: int) -> void:
	if lanes == null:
		return
	var used: Array = carrier_lanes.get(soldier_id, [])
	carrier_lanes.erase(soldier_id)
	if flag_team != team and not used.is_empty():
		# Our carrier died out in a lane: that way did badly.
		var lane: int = used[used.size() - 1]
		carry_lanes[lane] -= 1.0
		_decide("our carrier died in the %s lane" % lanes.name_of(lane))
	elif flag_team == team and not used.is_empty():
		escape_lanes[used[used.size() - 1]] += 1.0


func _on_flag_captured(scorer: int, soldier_id: int) -> void:
	if lanes == null:
		return
	var used: Array = carrier_lanes.get(soldier_id, [])
	carrier_lanes.erase(soldier_id)
	for lane: int in used:
		if scorer == team:
			carry_lanes[lane] += 2.0
		else:
			escape_lanes[lane] += 3.0
	if not used.is_empty():
		_decide("%s scored by the %s lane" % ["we" if scorer == team else "they", lanes.name_of(used[used.size() - 1])])


func _decide(text: String) -> void:
	decisions.append({ "seconds": snappedf(game.tick / 60.0, 0.1), "text": text })
	if decisions.size() > DECISIONS_KEPT:
		decisions.pop_front()


## Bots and people in each role now, by role name.
func role_counts_named() -> Dictionary:
	var counts := {}
	for brain in brains():
		var name_ := BotBrain.ROLE_NAMES[brain.role]
		counts[name_] = int(counts.get(name_, 0)) + 1
	for id: int in people:
		var name_ := "person " + BotBrain.ROLE_NAMES[people[id].role]
		counts[name_] = int(counts.get(name_, 0)) + 1
	return counts


func get_state() -> Dictionary:
	return {
		"known": known.duplicate(true),
		"role_since": role_since.duplicate(),
		"people": people.duplicate(true),
		"attack_lanes": attack_lanes.duplicate(),
		"escape_lanes": escape_lanes.duplicate(),
		"carry_lanes": carry_lanes.duplicate(),
		"carrier_lanes": carrier_lanes.duplicate(true),
		"escape_order": escape_order.duplicate(),
		"pickups": pickups.duplicate(),

		"covers": covers.duplicate(),
		"warn_ticks": warn_ticks.duplicate(),
		"wants": wants.duplicate(),
		"plan_text": plan_text,
		"threat_until": threat_until,
		"decisions": decisions.duplicate(true),
		"history": history.duplicate(true),
		"history_tick": _history_tick,
		"order_locks": order_locks.duplicate(true),
		"urgent_until": urgent_until,
		"report_tick": report_tick,
		"said_ticks": said_ticks.duplicate(),
		"chat": chat.duplicate(true),
		"reported_lane": reported_lane,
	}


func set_state(state: Dictionary) -> void:
	if not game.flags.is_empty():
		_lanes()
	known = state.known.duplicate(true)
	role_since = state.role_since.duplicate()
	people = state.people.duplicate(true)
	attack_lanes.assign(state.attack_lanes)
	escape_lanes.assign(state.escape_lanes)
	carry_lanes.assign(state.carry_lanes)
	carrier_lanes = state.carrier_lanes.duplicate(true)
	escape_order.assign(state.escape_order)
	pickups = state.pickups.duplicate()

	covers = state.covers.duplicate()
	warn_ticks = state.warn_ticks.duplicate()
	wants = state.wants.duplicate()
	plan_text = state.plan_text
	threat_until = state.threat_until
	decisions.assign(state.decisions.duplicate(true))
	history.assign(state.history.duplicate(true))
	_history_tick = state.history_tick
	order_locks = state.order_locks.duplicate(true)
	urgent_until = state.urgent_until
	report_tick = state.report_tick
	said_ticks = state.said_ticks.duplicate()
	chat.assign(state.chat.duplicate(true))
	reported_lane = state.reported_lane


func _on_flag_returned(flag_team: int, _soldier_id: int) -> void:
	if flag_team != team:
		return
	reported_lane = -1
	var speaker := _nearest_bot(game.stands.get(team, Vector3.ZERO))
	if speaker != null:
		say(speaker.soldier.entity_id, BotLines.Line.FLAG_RETURNED)


## Tells the team which lane the enemy carrier of our flag is heading for: the
## one it's in out in the middle, or the likeliest way home while it's still in
## our base. Once for each lane it goes to.
func _report_carrier() -> void:
	var own: Flag = game.flags[team]
	if own.mode != Flag.Mode.CARRIED or lanes == null or lanes.count == 0:
		return
	var at := own.at()
	var lane := lanes.lane_of(at) if lanes.in_lanes(at) else (escape_order[0] if not escape_order.is_empty() else -1)
	if lane < 0 or lane == reported_lane:
		return
	var speaker := _nearest_bot(at)
	if speaker != null and say(speaker.soldier.entity_id, BotLines.Line.CARRIER_LANE, lanes.title_of(lane)):
		reported_lane = lane


## The living bot nearest a spot, lower id on a tie, or null.
func _nearest_bot(at: Vector3) -> BotBrain:
	var best: BotBrain = null
	var best_d := INF
	for brain in brains():
		if brain.soldier.dead:
			continue
		var d := brain.soldier.at().distance_to(at)
		if d < best_d:
			best_d = d
			best = brain
	return best


## A bot says a line to its team, unless it's too soon: a report waits
## REPORT_GAP after the last one, and the same line about the same thing
## REPEAT_GAP. Warnings (now) skip the first wait. key tells apart lines with
## no subject, such as warnings to different people. True if said.
func say(speaker_id: int, line: int, subject := "", now := false, key := "") -> bool:
	var tag := "%d:%s:%s" % [line, subject, key]
	if not now and game.tick - report_tick < int(REPORT_GAP * 60.0):
		return false
	if game.tick - int(said_ticks.get(tag, -1000000)) < int(REPEAT_GAP * 60.0):
		return false
	said_ticks[tag] = game.tick
	if not now:
		report_tick = game.tick
	_speak(speaker_id, line, subject)
	return true


## An answer to a person's order: said at once, always.
func _answer(speaker_id: int, line: int, subject := "") -> void:
	_speak(speaker_id, line, subject)


func _speak(speaker_id: int, line: int, subject: String) -> void:
	var text := BotLines.text(line, subject)
	chat.append({ "seconds": snappedf(game.tick / 60.0, 0.1), "speaker": speaker_id, "line": line, "text": text })
	if chat.size() > CHAT_KEPT:
		chat.pop_front()
	said.emit(team, speaker_id, line, text)


## A person on this team gave an order in their command this tick.
func _on_ordered(soldier_id: int, kind: int, arg: int) -> void:
	var person := game.soldier(soldier_id)
	if person == null or person.team != team or game.flags.is_empty():
		return
	var pos := person.at()
	var until := game.tick + int(ORDER_TIME * 60.0)
	_decide("%s orders %s" % [person.display_name, Orders.NAMES[kind] if kind > 0 and kind < Orders.NAMES.size() else "?"])
	match kind:
		Orders.Kind.DEFEND_FLAG:
			_send(game.stands[team], ORDER_DEFENDERS, BotBrain.Role.DEFENCE, 0, until, kind, soldier_id, BotLines.Line.DEFENCE_YES, [BotBrain.Role.DEFENCE])
		Orders.Kind.REPAIR_BASE:
			# Stand-in until there's a base to repair: one bot home on defence.
			_send(game.stands[team], 1, BotBrain.Role.DEFENCE, 0, until, kind, soldier_id, BotLines.Line.REPAIR_YES, [BotBrain.Role.DEFENCE])
		Orders.Kind.ESCORT_ME:
			if person.dead:
				return
			_send(pos, ORDER_ESCORTS, BotBrain.Role.ESCORT, soldier_id, until, kind, soldier_id, BotLines.Line.ESCORT_YES, [])
		Orders.Kind.COVER_ME:
			if person.dead:
				return
			_send(pos, 1, BotBrain.Role.ESCORT, soldier_id, until, kind, soldier_id, BotLines.Line.COVER_YES, [])
		Orders.Kind.ATTACK_GENERATOR:
			# Stand-in until there are generators: bots on offence.
			_send(game.stands[1 - team], ORDER_ATTACKERS, BotBrain.Role.OFFENCE, 0, until, kind, soldier_id, BotLines.Line.ATTACK_YES, [BotBrain.Role.OFFENCE])
		Orders.Kind.TAKE_FLAG:
			_send(game.stands[1 - team], 1, BotBrain.Role.OFFENCE, 0, until, kind, soldier_id, BotLines.Line.TAKE_YES, [BotBrain.Role.OFFENCE])
			urgent_until = until
		Orders.Kind.SET_ROLE:
			_set_role(person, Orders.arg_bot(arg), Orders.arg_role(arg))


## Sends the count bots nearest a spot, leaving out those already in a role
## in skip and those on another order, to a role for an order, and has the
## first answer. A carrier can't go, and says so if it's the nearest.
func _send(at: Vector3, count: int, role: int, target: int, until: int, kind: int, by: int, line: int, skip: Array) -> void:
	var ranked: Array[BotBrain] = []
	for brain in brains():
		var id := brain.soldier.entity_id
		var lock: Dictionary = order_locks.get(id, {})
		if not lock.is_empty() and lock.order != kind:
			continue
		if not skip.has(brain.role) and id != target:
			ranked.append(brain)
	ranked.sort_custom(func(a: BotBrain, b: BotBrain) -> bool:
		var da := a.soldier.at().distance_to(at) + (500.0 if a.soldier.dead else 0.0)
		var db := b.soldier.at().distance_to(at) + (500.0 if b.soldier.dead else 0.0)
		return da < db or (da == db and a.soldier.entity_id < b.soldier.entity_id))
	var sent := 0
	for brain in ranked:
		if sent >= count:
			break
		var id := brain.soldier.entity_id
		if game.carried_flag(id) != null:
			if sent == 0:
				_answer(id, BotLines.Line.CANT_CARRYING)
			continue
		_lock(brain, role, target, until, kind, by)
		if sent == 0:
			_answer(id, line)
		sent += 1


## Commander mode: a person gives a bot (0 for the nearest) a role to keep, or
## gives it back to the commander with Orders.AUTO.
func _set_role(person: Soldier, bot_id: int, role: int) -> void:
	var brain: BotBrain = director.brain_of(bot_id) if bot_id != 0 else null
	if bot_id == 0:
		var best_d := INF
		for b in brains():
			var d := b.soldier.at().distance_to(person.at()) + (500.0 if b.soldier.dead else 0.0)
			if d < best_d:
				best_d = d
				brain = b
	if brain == null or brain.soldier.team != team:
		return
	var id := brain.soldier.entity_id
	if role == Orders.AUTO:
		order_locks.erase(id)
		_answer(id, BotLines.Line.AUTO_YES)
		return
	if role < 0 or role >= BotBrain.ROLE_NAMES.size():
		return
	if game.carried_flag(id) != null and role != BotBrain.Role.OFFENCE:
		_answer(id, BotLines.Line.CANT_CARRYING)
		return
	_lock(brain, role, person.entity_id if role == BotBrain.Role.ESCORT else 0, -1, Orders.Kind.SET_ROLE, person.entity_id)
	_answer(id, BotLines.Line.ROLE_YES, BotBrain.ROLE_NAMES[role])


## Puts a bot in a role for an order now, and keeps it there.
func _lock(brain: BotBrain, role: int, target: int, until: int, kind: int, by: int) -> void:
	var id := brain.soldier.entity_id
	order_locks[id] = { "role": role, "target": target, "until": until, "order": kind, "by": by }
	if brain.role != role:
		_decide("%s %s to %s by order" % [brain.soldier.display_name, BotBrain.ROLE_NAMES[brain.role], BotBrain.ROLE_NAMES[role]])
		brain.role = role
	role_since[id] = game.tick
	brain.role_target = target
	brain.role_slot = 0


## Drops orders that have run out or are done: their time is up, or the
## person to escort or cover is dead or gone.
func _check_orders() -> void:
	var ids := order_locks.keys()
	ids.sort()
	for id: int in ids:
		var lock: Dictionary = order_locks[id]
		var gone := director.brain_of(id) == null
		if lock.until >= 0 and game.tick >= lock.until:
			gone = true
		if lock.target != 0:
			# Timed orders end when the person dies; a commander mode escort
			# only when they've left the match.
			var who := game.soldier(lock.target)
			if who == null or (lock.until >= 0 and who.dead):
				gone = true
		if gone:
			order_locks.erase(id)
			var who_name := game.soldier(id).display_name if game.soldier(id) != null else str(id)
			_decide("%s's order to play %s is over" % [who_name, BotBrain.ROLE_NAMES[lock.role]])


## Offence goes for their flag at once, after an order to take it.
func attack_now() -> bool:
	return game.tick < urgent_until
