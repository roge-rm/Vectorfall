class_name Hud
extends Control

## The match HUD in the paperback cover look: the score bar with the clock
## and a status line, the three colour stripe, a compass strip with both
## flags, a feed of what your bots say and who killed whom, the crosshair and
## hit markers, arrows towards whoever hurt you, health and energy arcs by the
## crosshair, the weapon line with the pack and what's left to throw over it,
## flag and base power messages, markers and arrows for
## both flags, a power mark by each team's score, a marker on your
## generator while it's hit or down, the respawn count and the end of match
## card. It only reads the
## soldier and the match and hears the match's signals. Sizes are design
## pixels on a 390 pixel high screen (InkUi.unit()), and while the touch
## controls show, the feed and the weapon line keep clear of them.

signal restart_requested
signal menu_requested
## The LOADOUT button under the respawn count, to pick what you respawn in.
signal loadout_requested

const FEED_LINES := 5
const FEED_TIME := 6.0
## How long a line from your team's bots shows.
const CHAT_TIME := 7.0
const HIT_TIME := 0.25
const AIR_HIT_TIME := 0.75
const SHIELD_FLASH_TIME := 0.26
const SHIELD_COLOUR := Color("94d9fd")
const HURT_TIME := 1.5
const MESSAGE_TIME := 3.5
const WAIT_FOR_FLAG := "Return your flag to score"
## Design pixels the HUD keeps between itself and the touch controls.
const TOUCH_GAP := 6.0
const COMPASS_NAMES: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
## Design pixels each score cell grows by for its power mark.
const BOLT_ROOM := 16.0
## Seconds your generator's marker shows after it's hit.
const GENERATOR_HIT_TIME := 4.0

var soldier: Soldier
var device := LocalInput.Device.KEYBOARD
var game: Match
## The touch controls, which the HUD keeps clear of while they show.
var touch: TouchControls
## Feed lines, oldest first: {parts: [[words, InkUi.Face]], team, left}.
var _lines: Array[Dictionary] = []
var _heard_calls := {}
## Seconds left on the hit marker, and whether the hit killed.
var _hit_left := 0.0
var _hit_killed := false
var _air_hit_left := 0.0
var _shield_flash_left := 0.0
## Where recent damage came from, with seconds left to show it.
var _hurts: Array[Dictionary] = []
var _flash := 0.0
var _message := ""
var _message_left := 0.0
## Seconds left on your generator's under attack marker.
var _generator_hit_left := 0.0
var _end: Control
var _end_band: MenuKit.Band
var _end_score: Label
var _ladder_status: Label
var _restart_button: Button
var _end_menu_button: Button
var _results_button: Button
var _map_button: Button
signal tactical_requested
signal results_requested
## Shown under the respawn count while you're dead.
var loadout_button: MenuKit.CoverButton
## Bottom of the score bar and compass, and top of the status panel, from the
## last frame, for the flag arrows.
var _top_edge := 0.0
var _bottom_edge := 0.0
## How much each status arc shows, 0 to 1, and how long its bar has been full.
var _health_show := 0.0
var _energy_show := 0.0
var _health_full_for := 0.0
var _energy_full_for := 0.0
var _compass := Rect2()
## The touch controls' rects for this frame, from _touch_rects().
var _avoid: Array[Rect2] = []


func _init(ladder_run := false) -> void:
	name = "Hud"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = InkUi.theme()
	loadout_button = MenuKit.button("Loadout", loadout_requested.emit, 18, false, true)
	loadout_button.name = "LoadoutButton"
	loadout_button.visible = false
	add_child(loadout_button)
	_map_button = MenuKit.button("Map", tactical_requested.emit, 22, false, true)
	_map_button.custom_minimum_size.x = MenuKit.px(76)
	_map_button.focus_mode = Control.FOCUS_NONE
	_map_button.hide()
	add_child(_map_button)
	_make_end_card(ladder_run)


## The results: a cream card titled with the winner, the score, Restart and
## Main menu, over the game dimmed.
func _make_end_card(ladder_run: bool) -> void:
	_end = Control.new()
	_end.name = "MatchOver"
	_end.visible = false
	_end.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end.theme = MenuKit.theme()
	add_child(_end)
	var dim := ColorRect.new()
	dim.color = Color(InkUi.INK, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end.add_child(dim)
	var box := MenuKit.card(_end, "Match over", 320.0)
	_end_band = box.get_parent().get_parent().get_child(0) as MenuKit.Band
	_end_score = MenuKit.heading("", 30)
	box.add_child(_end_score)
	if ladder_run:
		_ladder_status = MenuKit.ink_label("", 15)
		_ladder_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_ladder_status.hide()
		box.add_child(_ladder_status)
	_results_button = MenuKit.button("Match results", results_requested.emit, MenuKit.BUTTON_SIZE)
	box.add_child(_results_button)
	_restart_button = MenuKit.button("Restart (R)", restart_requested.emit, MenuKit.BUTTON_SIZE, false, true)
	box.add_child(_restart_button)
	var menu_title := "Bot ladder" if ladder_run else "Main menu"
	_end_menu_button = MenuKit.button(menu_title, menu_requested.emit, MenuKit.BUTTON_SIZE, true)
	box.add_child(_end_menu_button)


func online_round() -> void:
	_restart_button.hide()


func show_ladder_clear(words: String) -> void:
	_ladder_status.text = words
	_ladder_status.show()


## Listens to a match for hits and kills.
func watch(value: Match) -> void:
	game = value
	game.damaged.connect(_on_damaged)
	game.shield_hit.connect(_on_shield_hit)
	game.air_hit.connect(_on_air_hit)
	game.killed.connect(_on_killed)
	game.carrier_stopped.connect(_on_carrier_stopped)
	game.flag_taken.connect(_on_flag_taken)
	game.flag_dropped.connect(_on_flag_dropped)
	game.flag_returned.connect(_on_flag_returned)
	game.flag_captured.connect(_on_flag_captured)
	game.match_over.connect(_on_match_over)
	game.power_lost.connect(_on_power_lost)
	game.power_back.connect(_on_power_back)
	game.asset_damaged.connect(_on_asset_damaged)
	game.deploy_result.connect(_on_deploy_result)
	game.resupplied.connect(func(id: int) -> void:
		if soldier != null and soldier.entity_id == id:
			_say("Ammo refilled"))


func _say(text: String) -> void:
	_message = text
	_message_left = MESSAGE_TIME


func _mine(flag_team: int) -> bool:
	return soldier != null and flag_team == soldier.team


func _on_flag_taken(team: int, soldier_id: int) -> void:
	if soldier != null and soldier_id == soldier.entity_id:
		_say("You have the enemy flag")
	elif _mine(team):
		_say("Your flag was taken")
	else:
		_say("Your team has the enemy flag")


func _on_flag_dropped(team: int, soldier_id: int) -> void:
	if soldier != null and soldier_id == soldier.entity_id:
		_say("You dropped the enemy flag")
	elif _mine(team):
		_say("Your flag was dropped")
	else:
		_say("The enemy flag was dropped")


func _on_flag_returned(team: int, soldier_id: int) -> void:
	if soldier != null and soldier_id == soldier.entity_id:
		_say("You returned your flag")
	elif _mine(team):
		_say("Your flag was returned")
	else:
		_say("The enemy flag was returned")


func _on_flag_captured(team: int, _soldier_id: int) -> void:
	_say("%s team captured the flag" % Soldier.TEAM_NAMES[team])


func _on_carrier_stopped(carrier_id: int, killer_id: int) -> void:
	var carrier := game.soldier(carrier_id)
	if soldier != null and carrier != null and carrier.team != soldier.team:
		_say("You stopped the carrier" if killer_id == soldier.entity_id else "Enemy carrier stopped")


func _on_power_lost(team: int) -> void:
	_say("Our generator is down" if _mine(team) else "Enemy generator destroyed")


func _on_power_back(team: int) -> void:
	_say("Our power is back" if _mine(team) else "Enemy power is back")


func _on_deploy_result(soldier_id: int, text: String) -> void:
	if soldier != null and soldier_id == soldier.entity_id:
		_say(text)


func _on_asset_damaged(asset_id: int, _attacker_id: int, _amount: float, _from: Vector3) -> void:
	var hit := game.asset(asset_id)
	if hit != null and hit.kind == BaseAsset.Kind.GENERATOR and _mine(hit.team):
		_generator_hit_left = GENERATOR_HIT_TIME


func _on_match_over(team: int) -> void:
	_end.visible = true
	_end_band.title = "DRAW" if team < 0 else ("%s team wins" % Soldier.TEAM_NAMES[team]).to_upper()
	_end_band.queue_redraw()
	_end_score.text = ("%s %d : %d %s" % [Soldier.TEAM_NAMES[0], game.scores[0], game.scores[1], Soldier.TEAM_NAMES[1]]).to_upper()
	# Focus for a gamepad or keyboard.
	if _ladder_status != null and _ladder_status.visible:
		_focus_end_button.call_deferred(_end_menu_button)
	else:
		focus_results()


func focus_results() -> void:
	_focus_end_button.call_deferred(_results_button)


func _focus_end_button(button: Button) -> void:
	if button.is_visible_in_tree():
		button.grab_focus()


func _on_shield_hit(victim_id: int, _amount: float, _from: Vector3) -> void:
	if soldier != null and victim_id == soldier.entity_id:
		_shield_flash_left = SHIELD_FLASH_TIME


func _on_air_hit(attacker_id: int, _victim_id: int) -> void:
	if soldier != null and attacker_id == soldier.entity_id:
		_air_hit_left = AIR_HIT_TIME


func _on_damaged(victim_id: int, attacker_id: int, amount: float, from: Vector3) -> void:
	if soldier == null:
		return
	if attacker_id == soldier.entity_id and victim_id != soldier.entity_id:
		_hit_left = HIT_TIME
		_hit_killed = false
	if victim_id == soldier.entity_id:
		if amount > 0.0:
			_flash = 0.35
		if attacker_id != soldier.entity_id:
			var colour := InkUi.PINK if amount > 0.0 else SHIELD_COLOUR
			_hurts.append({ "from": from, "left": HURT_TIME, "colour": colour })


func _on_killed(victim_id: int, killer_id: int, weapon_slot: int) -> void:
	if soldier != null and killer_id == soldier.entity_id and victim_id != killer_id:
		_hit_left = HIT_TIME * 2.0
		_hit_killed = true
	var victim := game.soldier(victim_id)
	var killer := game.soldier(killer_id)
	var weapon := Weapon.all[weapon_slot].short_name.to_lower()
	var parts: Array = []
	var machine := game.asset(killer_id)
	if killer == null and machine != null:
		parts = [[BaseAsset.NAMES[machine.kind], InkUi.Face.SERIF_BOLD], [" " + weapon + " ", InkUi.Face.ITALIC], [_name(victim), InkUi.Face.SERIF_BOLD]]
		_add_line(parts, machine.team, FEED_TIME)
		return
	if killer == null or killer == victim:
		parts = [[_name(victim), InkUi.Face.SERIF_BOLD], [" " + weapon + ", self", InkUi.Face.ITALIC]]
	else:
		parts = [[_name(killer), InkUi.Face.SERIF_BOLD], [" " + weapon + " ", InkUi.Face.ITALIC], [_name(victim), InkUi.Face.SERIF_BOLD]]
	var by := killer if killer != null else victim
	_add_line(parts, by.team if by != null else 0, FEED_TIME)


## A line from your team, with the speaker's name in bold and their team
## colour along the line's left edge.
func add_chat(speaker: Soldier, text: String) -> void:
	_add_line([[_name(speaker), InkUi.Face.SERIF_BOLD], [" " + text, InkUi.Face.ITALIC]], speaker.team if speaker != null else 0, CHAT_TIME)


func _add_line(parts: Array, team: int, seconds: float) -> void:
	_lines.append({"parts": parts, "team": team, "left": seconds})
	while _lines.size() > FEED_LINES:
		_lines.pop_front()


## Feed lines shown, oldest first, for tests and tools.
func feed_text() -> Array[String]:
	var shown: Array[String] = []
	for line in _lines:
		var words := ""
		for part: Array in line.parts:
			words += part[0]
		shown.append(words)
	return shown


func _name(who: Soldier) -> String:
	if who == null:
		return "?"
	if who == soldier:
		return "You"
	return who.display_name


func _process(delta: float) -> void:
	if soldier == null:
		return
	if game != null and not game.over:
		_hear_team_calls()
	# Counted down and dropped in place, with no new arrays each frame.
	for k in range(_lines.size() - 1, -1, -1):
		_lines[k].left -= delta
		if _lines[k].left <= 0.0:
			_lines.remove_at(k)
	_message_left = maxf(_message_left - delta, 0.0)
	_generator_hit_left = maxf(_generator_hit_left - delta, 0.0)
	_hit_left = maxf(_hit_left - delta, 0.0)
	_air_hit_left = maxf(_air_hit_left - delta, 0.0)
	_shield_flash_left = maxf(_shield_flash_left - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	# Each arc fades in while its bar isn't full and out a second after it is.
	var health_full := soldier.health >= soldier.tuning.health_max
	var energy_full := soldier.energy >= soldier.tuning.energy_max
	_health_full_for = _health_full_for + delta if health_full else 0.0
	_energy_full_for = _energy_full_for + delta if energy_full else 0.0
	_health_show = move_toward(_health_show, 0.0 if _health_full_for > 1.0 else 1.0, delta * 3.0)
	_energy_show = move_toward(_energy_show, 0.0 if _energy_full_for > 1.0 else 1.0, delta * 3.0)
	for k in range(_hurts.size() - 1, -1, -1):
		_hurts[k].left -= delta
		if _hurts[k].left <= 0.0:
			_hurts.remove_at(k)
	# Shown while dead and while on one of your stations.
	var show_loadout := soldier.dead or (game != null and game.station_under(soldier) != null)
	show_loadout = show_loadout and (game == null or not game.over)
	_map_button.visible = device == LocalInput.Device.TOUCH and game != null and game.arena != null and not game.over
	if _map_button.visible and touch != null:
		var pause_rect := touch.pause_rect()
		_map_button.position = Vector2(pause_rect.end.x + pause_rect.size.x * 0.45, pause_rect.position.y)
	if loadout_button.visible != show_loadout:
		loadout_button.visible = show_loadout
	if show_loadout:
		loadout_button.size = loadout_button.get_combined_minimum_size()
		loadout_button.position = Vector2((size.x - loadout_button.size.x) * 0.5, size.y * 0.38 + 30.0 * _u())
	queue_redraw()


func _hear_team_calls() -> void:
	var calls := game.team_calls.active(soldier.team)
	for kind: int in calls:
		var call: Dictionary = calls[kind]
		var seen: Vector2i = _heard_calls.get(kind, Vector2i.ZERO)
		var acknowledgements: PackedInt32Array = call.acks
		if seen.x != call.id:
			add_chat(game.soldier(call.by), Orders.CALL_NAMES[kind])
		if not acknowledgements.is_empty() and (seen.x != call.id or seen.y == 0) and call.by == soldier.entity_id:
			add_chat(game.soldier(acknowledgements[0]), "Acknowledged %s" % String(Orders.CALL_MARKERS[kind]).to_lower())
		_heard_calls[kind] = Vector2i(call.id, acknowledgements.size())


func _u() -> float:
	return InkUi.unit(size, 600.0)


func _px(design: float) -> int:
	return roundi(design * _u())


## Ink or cream, whichever reads on a fill.
static func _text_on(fill: Color) -> Color:
	return InkUi.INK if fill.get_luminance() > 0.45 else InkUi.CREAM


## Rects of the touch controls showing, grown by the HUD's gap.
func _touch_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if touch == null or not touch.visible:
		return rects
	var gap := TOUCH_GAP * _u()
	for k in TouchControls.BUTTONS.size():
		if not touch.button_shown(k):
			continue
		if k == TouchControls.ORDERS_BUTTON:
			rects.append(touch.orders_rect().grow(gap))
		else:
			var r := touch.button_radius(k) + gap
			rects.append(Rect2(touch.button_centre(k) - Vector2(r, r), Vector2(r, r) * 2.0))
	var ring := touch.stick_radius() + gap
	rects.append(Rect2(touch.stick_home() - Vector2(ring, ring), Vector2(ring, ring) * 2.0))
	rects.append(touch.pause_rect().grow(gap))
	return rects


func _draw() -> void:
	var u := _u()
	var centre := size * 0.5
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(InkUi.PINK, _flash * 0.4))
	# Four cream ticks in a 22 px box, 7 long and 2 thick.
	var half := 11.0 * u
	var tick := 7.0 * u
	var thick := maxf(2.0, 2.0 * u)
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(centre + dir * half, centre + dir * (half - tick), InkUi.CREAM, thick)
	if soldier == null:
		return
	if _hit_left > 0.0:
		var colour := InkUi.PINK if _hit_killed else InkUi.CREAM
		for dir: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var d := dir.normalized()
			InkUi.stroke(self, centre + d * 9.0 * u, centre + d * 17.0 * u, colour, thick)
	if _air_hit_left > 0.0:
		var alpha := clampf(_air_hit_left * 4.0, 0.0, 1.0)
		InkUi.centred(self, centre - Vector2(0.0, 29.0 * u), "AIR HIT", InkUi.Face.BLACK, _px(14), Color(InkUi.AMBER, alpha), 3)
	if _shield_flash_left > 0.0:
		var alpha := _shield_flash_left / SHIELD_FLASH_TIME
		var radius := lerpf(34.0, 25.0, alpha) * u
		draw_arc(centre, radius, 0.0, TAU, 40, Color(InkUi.INK, alpha), 4.0 * u, true)
		draw_arc(centre, radius, 0.0, TAU, 40, Color(SHIELD_COLOUR, alpha), 2.0 * u, true)
	# An arc around the crosshair pointing at where each hit came from, up for
	# ahead.
	for hurt in _hurts:
		var to: Vector3 = hurt.from - soldier.global_position
		var local := Basis(Vector3.UP, -soldier.yaw) * to
		var angle := atan2(local.x, -local.z) - PI * 0.5
		var radius := 62.0 * u
		var alpha := clampf(hurt.left / HURT_TIME, 0.0, 1.0)
		draw_arc(centre, radius, angle - 0.37, angle + 0.37, 16, Color(InkUi.INK, alpha), 9.0 * u, true)
		draw_arc(centre, radius, angle - 0.35, angle + 0.35, 16, Color(hurt.colour, alpha), 5.0 * u, true)
	_avoid = _touch_rects()
	var avoid := _avoid
	_top_edge = 0.0
	if game != null:
		_top_edge = _draw_score(u)
	_bottom_edge = _draw_status(u, avoid)
	if game != null and soldier.vehicle_id == 0 and not soldier.dead:
		var nearby := game.fleet.nearby(soldier)
		if nearby != null:
			var prompt := Vehicle.NAMES[nearby.kind]
			if device != LocalInput.Device.TOUCH:
				var key := "B" if device == LocalInput.Device.GAMEPAD else "R"
				prompt = "%s · Board [%s]" % [prompt, key]
			InkUi.centred(self, centre + Vector2(0, 46.0 * u), prompt, InkUi.Face.BLACK, _px(13), InkUi.CREAM, 3)
	_draw_feed(u, avoid)
	if game != null:
		_draw_sensor_marks(u)
		_draw_generator_marker(u)
		_draw_flag_markers(u)
		_draw_control_markers(u)
		_draw_waypoint(u)
		_draw_team_call(u)
	var words := notice()
	if not words.is_empty():
		var alpha := 1.0 if words == WAIT_FOR_FLAG else clampf(_message_left, 0.0, 1.0)
		_banner(Vector2(centre.x, size.y * 0.3), words, 20, alpha)
	if soldier.dead:
		_banner(Vector2(centre.x, size.y * 0.38), "Respawning in %d" % ceili(maxf(soldier.respawn_in, 0.0)), 26, 1.0)


## Big Shoulders words on a cream card with an ink edge, centred on at.
func _banner(at: Vector2, words: String, font_size: float, alpha: float) -> void:
	var u := _u()
	var text := words.to_upper()
	var px := roundi(font_size * u)
	var wide := InkUi.width(text, InkUi.Face.BLACK, px) + 24.0 * u
	var tall := font_size * 1.4 * u
	var rect := Rect2(at - Vector2(wide, tall) * 0.5, Vector2(wide, tall))
	InkUi.box(self, rect, Color(InkUi.CREAM, alpha), maxf(2.0, 2.0 * u))
	InkUi.centred(self, rect.get_center(), text, InkUi.Face.BLACK, px, Color(InkUi.INK, alpha))


func _clock_text() -> String:
	var seconds := ceili(game.time_left)
	return "%d:%02d" % [seconds / 60, seconds % 60]


## The line under the clock: who has which flag, or what wins.
func _status_line() -> String:
	if not game.hold_points.is_empty():
		for point in game.hold_points:
			if soldier.at().distance_squared_to(point.position) < 36.0 * 36.0:
				return "%s · %s" % [point.letter, point.status()]
		return "Capture and hold"
	if soldier == null:
		return ""
	var own := game.flags.get(soldier.team) as Flag
	var theirs := game.flags.get(1 - soldier.team) as Flag
	if own != null and own.mode == Flag.Mode.CARRIED:
		return "%s has your flag" % Soldier.TEAM_NAMES[1 - soldier.team]
	if theirs != null and theirs.mode == Flag.Mode.CARRIED:
		return "You have their flag" if theirs.carrier_id == soldier.entity_id else "Your team has their flag"
	if own != null and own.mode == Flag.Mode.DROPPED:
		return "Your flag is down"
	return "First to %d" % game.settings.capture_limit


## The score bar flush to the top, the stripe under it and the compass under
## that. Returns the bottom of the compass.
func _draw_score(u: float) -> float:
	var line := maxf(2.0, 2.0 * u)
	var score_px := _px(30.0)
	var name_px := _px(11.0)
	var clock_px := _px(22.0)
	var status_px := _px(10.0)
	var status := _status_line()
	var cells: Array[float] = []
	for team in 2:
		cells.append((28.0 + 8.0 + BOLT_ROOM) * u + InkUi.width(str(game.scores[team]), InkUi.Face.BLACK, score_px) + InkUi.width(Soldier.TEAM_NAMES[team], InkUi.Face.ITALIC, name_px))
	var middle := 32.0 * u + maxf(InkUi.width(_clock_text(), InkUi.Face.BOLD, clock_px), InkUi.width(status, InkUi.Face.ITALIC, status_px))
	var tall := 34.0 * u
	var wide := cells[0] + middle + cells[1] + line * 2.0
	var left := (size.x - wide) * 0.5
	draw_rect(Rect2(left, 0.0, wide, tall), InkUi.INK)
	var x := left + line
	var inner := tall - line
	for side in 3:
		var team := 0 if side == 0 else 1
		var cell := cells[0] if side == 0 else (middle if side == 1 else cells[1])
		var fill := InkUi.CREAM if side == 1 else Palette.team(team)
		var rect := Rect2(x, 0.0, cell, inner)
		draw_rect(rect, fill)
		if side == 1:
			var mid := rect.get_center().x
			InkUi.words(self, Vector2(mid, 19.0 * u), _clock_text(), InkUi.Face.BOLD, clock_px, InkUi.INK, HORIZONTAL_ALIGNMENT_CENTER)
			InkUi.words(self, Vector2(mid, 29.0 * u), status, InkUi.Face.ITALIC, status_px, InkUi.RUST, HORIZONTAL_ALIGNMENT_CENTER)
		else:
			var ink := _text_on(fill)
			var baseline := 26.0 * u
			var score := str(game.scores[team])
			var team_name := Soldier.TEAM_NAMES[team]
			# The power mark sits on the inner end, by the clock.
			var bolt_x := rect.end.x - 13.0 * u if side == 0 else rect.position.x + 13.0 * u
			_power_mark(Vector2(bolt_x, inner * 0.5), 16.0 * u, ink, power_mark_on(team))
			if side == 0:
				var after := InkUi.words(self, Vector2(x + 14.0 * u, baseline), score, InkUi.Face.BLACK, score_px, ink)
				InkUi.words(self, Vector2(x + 22.0 * u + after, baseline), team_name, InkUi.Face.ITALIC, name_px, ink)
			else:
				var after := InkUi.words(self, Vector2(rect.end.x - 14.0 * u, baseline), score, InkUi.Face.BLACK, score_px, ink, HORIZONTAL_ALIGNMENT_RIGHT)
				InkUi.words(self, Vector2(rect.end.x - 22.0 * u - after, baseline), team_name, InkUi.Face.ITALIC, name_px, ink, HORIZONTAL_ALIGNMENT_RIGHT)
		x += cell
		if side < 2:
			draw_rect(Rect2(x, 0.0, line, inner), InkUi.INK)
			x += line
	InkUi.stripes(self, Rect2(0.0, tall, size.x, 4.0 * u), true)
	return _draw_compass(u, maxf(wide, 180.0 * u), tall + 8.0 * u)


func _heading_to(point: Vector3) -> float:
	var d := point - soldier.global_position
	return wrapf(atan2(d.x, -d.z) + soldier.yaw, -PI, PI)


## A cream strip with the headings in front of you and a diamond for each
## flag, its top at y. Returns its bottom.
func _draw_compass(u: float, width: float, y: float) -> float:
	var line := maxf(2.0, 2.0 * u)
	var height := 15.0 * u
	var mid := size.x * 0.5
	var rect := Rect2(mid - width * 0.5, y, width, height)
	_compass = rect
	InkUi.box(self, rect, InkUi.CREAM, line)
	var span := PI * 0.5
	var reach := width * 0.5 - line * 2.0
	for k in 24:
		var bearing := k * TAU / 24.0
		var rel := wrapf(bearing + soldier.yaw, -PI, PI)
		if absf(rel) > span:
			continue
		var x := mid + rel / span * reach
		var cardinal := k % 3 == 0
		if cardinal and absf(x - mid) > reach - 8.0 * u:
			continue
		if cardinal:
			InkUi.centred(self, Vector2(x, y + height * 0.5), COMPASS_NAMES[k / 3], InkUi.Face.BLACK, _px(10.0), InkUi.INK if k % 6 == 0 else InkUi.BROWN_GREY)
		else:
			draw_line(Vector2(x, y + height - line), Vector2(x, y + height * 0.6), InkUi.INK, maxf(1.0, u))
	# A pointer under the middle.
	var tip := Vector2(mid, y + height + 5.0 * u)
	draw_colored_polygon(PackedVector2Array([tip, Vector2(mid - 4.0 * u, y + height), Vector2(mid + 4.0 * u, y + height)]), InkUi.INK)
	for team in game.flags:
		var flag := game.flags[team]
		if _jammed(flag):
			continue
		var rel := clampf(_heading_to(flag.global_position), -span, span)
		_diamond(Vector2(mid + rel / span * reach, y + height * 0.5), height * 0.42, Palette.team(team))
	for point in game.hold_points:
		var rel := clampf(_heading_to(point.position), -span, span)
		var at := Vector2(mid + rel / span * reach, y + height * 0.5)
		_diamond(at, height * 0.44, point.colour())
		InkUi.centred(self, at, point.letter, InkUi.Face.BLACK, _px(9.0), InkUi.INK)
	return tip.y


## Health and energy as thin arcs either side of the crosshair, health on the
## left and energy on the right, filling from the bottom up. Each one shows
## only while its bar isn't full. Under them, at the bottom middle between
## the touch controls, the weapon line in outlined words, with a SKI tag
## beside it while ski is held. Returns the top of the weapon line.
func _draw_status(u: float, avoid: Array[Rect2]) -> float:
	var centre := size * 0.5
	var radius := 50.0 * u
	var thick := maxf(2.0, 3.0 * u)
	var edge := maxf(1.0, 1.0 * u)
	# Half the sweep of each arc, in radians either side of level.
	var half := 0.45
	var health := clampf(soldier.health / soldier.tuning.health_max, 0.0, 1.0)
	var energy := clampf(soldier.energy / soldier.tuning.energy_max, 0.0, 1.0)
	var refilling := soldier.since_jet >= soldier.tuning.refill_delay or soldier.jetting
	var energy_fill := InkUi.ORANGE if refilling else InkUi.ORANGE.darkened(0.3)
	# Angles go clockwise from the right, so PI - half is low on the left and
	# half is low on the right.
	_status_arc(centre, radius, thick, edge, PI - half, PI + half, health, InkUi.PINK, _health_show)
	_status_arc(centre, radius, thick, edge, half, -half, energy, energy_fill, _energy_show)
	# The weapon line, kept in the gap between the touch controls: rounds
	# left, or the energy a shot takes.
	var weapon := Weapon.all[soldier.weapon_slot()]
	var amount := "%d energy" % roundi(weapon.energy_per_shot) if weapon.uses_energy() else str(soldier.ammo[soldier.weapon])
	var words := "%s · %s · %d m/s" % [weapon.name, amount, roundi(soldier.horizontal_speed())]
	var hull: Vehicle = game.fleet.hulls.get(soldier.vehicle_id) if game != null else null
	if hull != null:
		var at := Vector2(size.x * 0.5, size.y - 19.0 * u)
		var seat := "Pilot" if hull.flies() else "Driver"
		if soldier.vehicle_seat > 0:
			seat = "Gunner" if hull.kind == Vehicle.Kind.GUNSHIP else "Passenger"
		var readout := "%s · %s · %d m/s · %d%% hull" % [
			Vehicle.NAMES[hull.kind], seat, roundi(hull.velocity.length()), ceili(hull.health / Vehicle.MAX_HEALTH[hull.kind] * 100.0),
		]
		InkUi.centred(self, at, readout, InkUi.Face.BLACK, _px(13), InkUi.CREAM, 3)
		var hint := "Exit [B]" if device == LocalInput.Device.GAMEPAD else "Exit [R]"
		if hull.uses_personal_weapon(soldier.vehicle_seat):
			hint = "%s · %s" % [weapon.name, amount] if device == LocalInput.Device.TOUCH else "%s · %s · %s" % [weapon.name, amount, hint]
		if device != LocalInput.Device.TOUCH or hull.uses_personal_weapon(soldier.vehicle_seat):
			InkUi.centred(self, at - Vector2(0, 18.0 * u), hint, InkUi.Face.BLACK, _px(11), InkUi.CREAM, 3)
		return at.y - 32.0 * u
	var px := _px(13.0)
	var baseline := size.y - 14.0 * u
	var top := baseline - px
	var low := 0.0
	var high := size.x
	for box in avoid:
		if box.end.y <= top or box.position.y >= size.y:
			continue
		if box.get_center().x < size.x * 0.5:
			low = maxf(low, box.end.x)
		else:
			high = minf(high, box.position.x)
	var wide := InkUi.width(words, InkUi.Face.BLACK, px)
	var middle := clampf(size.x * 0.5, low + wide * 0.5, maxf(high - wide * 0.5, low + wide * 0.5))
	InkUi.words(self, Vector2(middle, baseline), words, InkUi.Face.BLACK, px, InkUi.CREAM, HORIZONTAL_ALIGNMENT_CENTER, maxi(3, roundi(px * 0.22)))
	top = _draw_kit(u, middle, top - 3.0 * u)
	if soldier.ski_held:
		# Orange while skiing on the ground, ink while held in the air.
		var line := maxf(1.0, 2.0 * u)
		var tag_px := _px(12.0)
		var tag_wide := InkUi.width("SKI", InkUi.Face.BLACK, tag_px) + 12.0 * u
		var tag := Rect2(middle - tag_wide * 0.5, top - 22.0 * u, tag_wide, 16.0 * u)
		var fill := InkUi.ORANGE if soldier.skiing else InkUi.INK
		draw_rect(tag, InkUi.INK)
		draw_rect(tag.grow(-line), fill)
		InkUi.centred(self, tag.get_center(), "SKI", InkUi.Face.BLACK, tag_px, _text_on(fill))
		return tag.position.y
	return top


## The small line over the weapon line, centred on middle with its bottom at
## bottom: the pack's name in a tag, orange while a shield or jammer is on or
## the repair pack is working, then the hand grenades and mines left.
## Returns its top.
func _draw_kit(u: float, middle: float, bottom: float) -> float:
	var px := _px(11.0)
	var words := "%d %s · %d %s" % [soldier.grenades, "grenade" if soldier.grenades == 1 else "grenades", soldier.mines, "mine" if soldier.mines == 1 else "mines"]
	words = words.to_upper()
	var tall := 15.0 * u
	var text_wide := InkUi.width(words, InkUi.Face.BLACK, px)
	var pack := soldier.pack()
	var tag_words := ""
	var tag_wide := 0.0
	var gap := 0.0
	if pack != null:
		tag_words = pack.short_name + (" ON" if soldier.pack_on and pack.use == Pack.Use.TOGGLE else "")
		if pack.use == Pack.Use.DEPLOY and not soldier.deploy_ready:
			tag_words += " EMPTY"
		tag_wide = InkUi.width(tag_words, InkUi.Face.BLACK, px) + 10.0 * u
		gap = 6.0 * u
	var left := middle - (tag_wide + gap + text_wide) * 0.5
	var row_middle := bottom - tall * 0.5
	if pack != null:
		var line := maxf(1.0, 2.0 * u)
		var tag := Rect2(left, bottom - tall, tag_wide, tall)
		var fill := InkUi.ORANGE if soldier.pack_on else InkUi.INK
		draw_rect(tag, InkUi.INK)
		draw_rect(tag.grow(-line), fill)
		InkUi.centred(self, tag.get_center(), tag_words, InkUi.Face.BLACK, px, _text_on(fill))
	InkUi.centred(self, Vector2(left + tag_wide + gap + text_wide * 0.5, row_middle), words, InkUi.Face.BLACK, px, InkUi.CREAM, maxi(2, roundi(px * 0.22)))
	return bottom - tall


## One status arc from start (empty end) towards finish, filled by amount: a
## faint track with the filled part in colour, both with an ink edge, all
## faded by show.
func _status_arc(centre: Vector2, radius: float, thick: float, edge: float, start: float, finish: float, amount: float, colour: Color, show: float) -> void:
	if show <= 0.0:
		return
	var a := show * 0.8
	var lip := edge / radius
	var dir := signf(finish - start)
	draw_arc(centre, radius, start - dir * lip, finish + dir * lip, 24, Color(InkUi.INK, a * 0.25), thick + edge * 2.0, true)
	if amount > 0.0:
		var end := lerpf(start, finish, amount)
		draw_arc(centre, radius, start - dir * lip, end + dir * lip, 24, Color(InkUi.INK, a), thick + edge * 2.0, true)
		draw_arc(centre, radius, start, end, 24, Color(colour, a), thick, true)


## The feed at the top left: cream boxes with the team colour down the left
## edge, newest at the bottom. It starts under the compass when the compass
## would reach it, and drops the oldest lines that would run into the touch
## controls.
func _draw_feed(u: float, avoid: Array[Rect2]) -> void:
	if _lines.is_empty():
		return
	var font_px := _px(12.0)
	var left := 12.0 * u
	var max_wide := 250.0 * u
	var top := 48.0 * u
	if game != null and left + max_wide + 8.0 * u > _compass.position.x:
		top = maxf(top, _top_edge + 8.0 * u)
	var tall := 12.0 * 1.3 * u + 6.0 * u
	var gap := 4.0 * u
	var limit := size.y
	var span := Rect2(left, top, max_wide, size.y - top)
	for box in avoid:
		if box.intersects(span) and box.position.y > top:
			limit = minf(limit, box.position.y)
	var room := clampi(floori((limit - top + gap) / (tall + gap)), 0, _lines.size())
	var shown := _lines.slice(_lines.size() - room)
	var f := InkUi.face(InkUi.Face.SERIF)
	var y := top
	for line in shown:
		var alpha := clampf(line.left, 0.0, 1.0)
		var wide := 0.0
		for part: Array in line.parts:
			wide += InkUi.width(part[0], part[1], font_px)
		var rect := Rect2(left, y, minf(wide + 20.0 * u, max_wide), tall)
		draw_rect(rect, Color(InkUi.CREAM, alpha))
		draw_rect(Rect2(rect.position, Vector2(4.0 * u, tall)), Color(Palette.team(line.team), alpha))
		var x := left + 12.0 * u
		var baseline := y + (tall + f.get_ascent(font_px) - f.get_descent(font_px)) * 0.5
		for part: Array in line.parts:
			if x > rect.end.x - 8.0 * u:
				break
			x += InkUi.words(self, Vector2(x, baseline), part[0], part[1], font_px, Color(InkUi.INK, alpha))
		y += tall + gap


func _diamond(at: Vector2, radius: float, colour: Color, filled := true) -> void:
	var points := PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius * 0.75, 0), at + Vector2(0, radius), at + Vector2(-radius * 0.75, 0)])
	if filled:
		InkUi.shape(self, points, colour, minf(size.x, size.y))
		return
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, InkUi.INK, 6.0)
	draw_polyline(closed, colour, 3.0)


func _draw_control_markers(u: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var bounds := Rect2(Vector2(85 * u, _top_edge + 20 * u), Vector2(size.x - 170 * u, size.y * 0.72 - _top_edge))
	for point in game.hold_points:
		var position_in_world := point.position + Vector3.UP * 7.0
		if camera.is_position_behind(position_in_world):
			continue
		var at := camera.unproject_position(position_in_world)
		if bounds.has_point(at):
			InkUi.centred(self, at, "%s · %d m" % [point.letter, int(soldier.at().distance_to(point.position))],
				InkUi.Face.BOLD, _px(15.0), point.colour(), 3)


func _draw_waypoint(u: float) -> void:
	var order: Dictionary = game.waypoints.get(soldier.entity_id, {})
	var camera := get_viewport().get_camera_3d()
	if order.is_empty() or soldier.dead or game.over or camera == null:
		return
	var point: Vector3 = order.at
	var at := _tactical_pin(camera, point, u)
	var distance := int(soldier.at().distance_to(point))
	_diamond(at, 7.0 * u, InkUi.CREAM, false)
	InkUi.centred(self, at + Vector2(0, 16.0 * u), "WAYPOINT · %d m" % distance,
		InkUi.Face.BOLD, _px(13), InkUi.CREAM, 3)


func _draw_team_call(u: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if soldier.dead or game.over or camera == null:
		return
	var call := game.team_calls.latest(soldier, true)
	if call.is_empty():
		call = game.team_calls.latest(soldier)
	if call.is_empty():
		return
	var point: Vector3 = call.at
	var at := _tactical_pin(camera, point + Vector3.UP * 7.0, u)
	at = _clear_of_touch(at, 18.0 * u)
	var label := "%s · %d m" % [String(Orders.CALL_MARKERS[call.kind]).to_upper(), int(soldier.at().distance_to(point))]
	if not call.acks.is_empty():
		label += " · %d ACK" % call.acks.size()
	draw_circle(at, 8.0 * u, InkUi.INK, true, -1.0, true)
	draw_circle(at, 6.0 * u, InkUi.AMBER, true, -1.0, true)
	InkUi.centred(self, at + Vector2(0, 16.0 * u), label, InkUi.Face.BOLD, _px(13), InkUi.AMBER, 3)


func _tactical_pin(camera: Camera3D, point: Vector3, u: float) -> Vector2:
	var local := camera.to_local(point)
	var at := camera.unproject_position(point)
	if local.z >= -0.05:
		var direction := Vector2(local.x, -local.y)
		if direction.is_zero_approx():
			direction = Vector2.DOWN
		at = size * 0.5 + direction.normalized() * size.length()
	return at.clamp(Vector2(85.0 * u, _top_edge + 18.0 * u), Vector2(size.x - 85.0 * u, size.y * 0.76))


func _draw_flag_markers(u: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var short := minf(size.x, size.y)
	var margin := short * 0.07
	var radius := 8.0 * u
	var inverse := camera.global_transform.affine_inverse()
	for team in game.flags:
		var flag := game.flags[team]
		if _jammed(flag):
			continue
		var point := flag.global_position + Vector3.UP * 3.0
		var local := inverse * point
		var behind := local.z > -0.05
		var colour := Palette.team(team)
		var screen := Vector2(-1000.0, -1000.0) if behind else camera.unproject_position(point)
		var inside := not behind and Rect2(Vector2.ZERO, size).grow(-margin).has_point(screen)
		var at := screen
		if not inside:
			var dir := Vector2(local.x, -local.y)
			dir = dir.normalized() if dir.length() > 0.001 else Vector2.DOWN
			# Arrows stay below the score and compass and above the status
			# panel.
			var top := _top_edge + radius * 3.0
			var bottom := _bottom_edge - radius * 4.0
			bottom = maxf(bottom, top + radius * 4.0)
			var middle := Vector2(size.x * 0.5, (top + bottom) * 0.5)
			var half := Vector2(size.x * 0.5 - margin, (bottom - top) * 0.5)
			var scale := minf(half.x / maxf(absf(dir.x), 0.0001), half.y / maxf(absf(dir.y), 0.0001))
			at = middle + dir * scale
			at = _clear_of_touch(at, radius * 3.0)
			var tip := at + dir * radius * 2.4
			var side := dir.orthogonal() * radius * 0.9
			var arrow := PackedVector2Array([tip, at + dir * radius * 1.0 + side, at + dir * radius * 1.0 - side])
			InkUi.shape(self, arrow, colour, short)
		_diamond(at, radius, colour, flag.mode != Flag.Mode.HOME)


## A lightning bolt half as wide as tall, centred on at: filled with power,
## an outline with a stroke through it without.
func _power_mark(at: Vector2, tall: float, colour: Color, on: bool) -> void:
	var points := PackedVector2Array()
	for p: Vector2 in [Vector2(0.12, -0.5), Vector2(-0.25, 0.08), Vector2(-0.02, 0.08), Vector2(-0.12, 0.5), Vector2(0.25, -0.08), Vector2(0.02, -0.08)]:
		points.append(at + p * tall)
	if on:
		draw_colored_polygon(points, colour)
		return
	var closed := points.duplicate()
	closed.append(points[0])
	var line := maxf(1.0, tall * 0.1)
	draw_polyline(closed, Color(colour, 0.6), line, true)
	draw_line(at + Vector2(-0.35, -0.4) * tall, at + Vector2(0.35, 0.4) * tall, colour, line * 1.5, true)


## A marker on your generator while it's being hit or is down, with what's
## wrong and how far it is, kept on screen.
func _draw_generator_marker(u: float) -> void:
	var words := generator_marker()
	if words.is_empty():
		return
	var own := game.generator(soldier.team)
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var point := own.centre() + Vector3.UP * 1.5
	var margin := minf(size.x, size.y) * 0.1
	var at := Vector2(size.x * 0.5, size.y - margin)
	if not camera.is_position_behind(point):
		at = camera.unproject_position(point)
	var top := _top_edge + margin
	at = Vector2(clampf(at.x, margin, size.x - margin), clampf(at.y, top, maxf(_bottom_edge - margin, top)))
	at = _clear_of_touch(at, 20.0 * u)
	var colour := InkUi.PINK
	var radius := 9.0 * u
	draw_circle(at, radius + maxf(2.0, 2.0 * u), InkUi.INK)
	draw_circle(at, radius, InkUi.CREAM if own.destroyed else colour)
	_power_mark(at, radius * 1.4, InkUi.INK, not own.destroyed)
	InkUi.text(self, at + Vector2(0.0, radius * 2.6), words, _px(12.0), colour)


## The words on your generator's marker, or empty while it doesn't show.
func generator_marker() -> String:
	if soldier == null or game == null or (soldier.team != 0 and soldier.team != 1):
		return ""
	var own := game.generator(soldier.team)
	if own == null or (not own.destroyed and _generator_hit_left <= 0.0):
		return ""
	var metres := roundi(soldier.global_position.distance_to(own.global_position))
	return (("Generator down  %d m" if own.destroyed else "Generator hit  %d m") % metres).to_upper()


## True while a team's power mark shows power on.
func power_mark_on(team: int) -> bool:
	return game != null and game.powered(team)


## The notice showing now, or empty.
func notice() -> String:
	if game != null and soldier != null and game.awaiting_flag_return(soldier):
		return WAIT_FOR_FLAG
	return _message if _message_left > 0.0 else ""


## A small open diamond over each enemy your team's sensor sees, while it's
## on screen. Match.sensed already leaves out jammers.
func _draw_sensor_marks(u: float) -> void:
	if soldier.team != 0 and soldier.team != 1:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var radius := 5.0 * u
	for id in game.sensed[soldier.team]:
		var other := game.soldier(id)
		if other == null or other.dead:
			continue
		var point := other.global_position + Vector3.UP * (other.tuning.height + 0.8)
		if camera.is_position_behind(point):
			continue
		var at := camera.unproject_position(point)
		if Rect2(Vector2.ZERO, size).has_point(at):
			_diamond(at, radius, Palette.team(other.team), false)


## True for a flag carried by an enemy with a sensor jammer on, which the
## markers and compass leave out.
func _jammed(flag: Flag) -> bool:
	return not game.tactical_flag_visible(soldier, flag)


## Pushes an edge marker towards the middle of the screen until it's clear of
## every touch button by `clear`, while the touch controls show.
func _clear_of_touch(at: Vector2, clear: float) -> Vector2:
	if touch == null or not touch.visible:
		return at
	for k in TouchControls.BUTTONS.size():
		var centre := touch.button_centre(k)
		var reach := touch.button_radius(k) + clear
		var dy := at.y - centre.y
		if at.distance_to(centre) < reach and absf(dy) < reach:
			var dx := sqrt(reach * reach - dy * dy)
			at.x = centre.x - dx if centre.x > size.x * 0.5 else centre.x + dx
	return at
