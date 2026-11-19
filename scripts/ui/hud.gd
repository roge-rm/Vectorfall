class_name Hud
extends Control

## The match HUD in the paperback cover look: the score bar with the clock
## and a status line, the three colour stripe, a compass strip with both
## flags, a feed of what your bots say and who killed whom, the crosshair and
## hit markers, arrows towards whoever hurt you, the status panel (health,
## jet energy, weapon, ammo and speed), flag messages, markers and arrows for
## both flags, the respawn count and the end of match card. It only reads the
## soldier and the match and hears the match's signals. Sizes are design
## pixels on a 390 pixel high screen (InkUi.unit()), and while the touch
## controls show, the feed and the status panel keep clear of them.

signal restart_requested
signal menu_requested

const FEED_LINES := 5
const FEED_TIME := 6.0
## How long a line from your team's bots shows.
const CHAT_TIME := 7.0
const HIT_TIME := 0.25
const HURT_TIME := 1.5
const MESSAGE_TIME := 3.5
## Design pixels the HUD keeps between itself and the touch controls.
const TOUCH_GAP := 6.0
const COMPASS_NAMES: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

var soldier: Soldier
var game: Match
## The touch controls, which the HUD keeps clear of while they show.
var touch: TouchControls
## Feed lines, oldest first: {parts: [[words, InkUi.Face]], team, left}.
var _lines: Array[Dictionary] = []
## Seconds left on the hit marker, and whether the hit killed.
var _hit_left := 0.0
var _hit_killed := false
## Where recent damage came from, with seconds left to show it.
var _hurts: Array[Dictionary] = []
var _flash := 0.0
var _message := ""
var _message_left := 0.0
var _end: Control
var _end_band: MenuKit.Band
var _end_score: Label
var _restart_button: Button
## Bottom of the score bar and compass, and top of the status panel, from the
## last frame, for the flag arrows.
var _top_edge := 0.0
var _bottom_edge := 0.0
var _compass := Rect2()
## The touch controls' rects for this frame, from _touch_rects().
var _avoid: Array[Rect2] = []


func _init() -> void:
	name = "Hud"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = InkUi.theme()
	_make_end_card()


## The results: a cream card titled with the winner, the score, Restart and
## Main menu, over the game dimmed.
func _make_end_card() -> void:
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
	_restart_button = MenuKit.button("Restart (R)", restart_requested.emit, MenuKit.BUTTON_SIZE, false, true)
	box.add_child(_restart_button)
	box.add_child(MenuKit.button("Main menu", menu_requested.emit, MenuKit.BUTTON_SIZE, true))


## Listens to a match for hits and kills.
func watch(value: Match) -> void:
	game = value
	game.damaged.connect(_on_damaged)
	game.killed.connect(_on_killed)
	game.flag_taken.connect(_on_flag_taken)
	game.flag_dropped.connect(_on_flag_dropped)
	game.flag_returned.connect(_on_flag_returned)
	game.flag_captured.connect(_on_flag_captured)
	game.match_over.connect(_on_match_over)


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


func _on_match_over(team: int) -> void:
	_end.visible = true
	_end_band.title = "DRAW" if team < 0 else ("%s team wins" % Soldier.TEAM_NAMES[team]).to_upper()
	_end_band.queue_redraw()
	_end_score.text = ("%s %d : %d %s" % [Soldier.TEAM_NAMES[0], game.scores[0], game.scores[1], Soldier.TEAM_NAMES[1]]).to_upper()
	# Focus for a gamepad or keyboard.
	_restart_button.grab_focus.call_deferred()


func _on_damaged(victim_id: int, attacker_id: int, _amount: float, from: Vector3) -> void:
	if soldier == null:
		return
	if attacker_id == soldier.entity_id and victim_id != soldier.entity_id:
		_hit_left = HIT_TIME
		_hit_killed = false
	if victim_id == soldier.entity_id:
		_flash = 0.35
		if attacker_id != soldier.entity_id:
			_hurts.append({ "from": from, "left": HURT_TIME })


func _on_killed(victim_id: int, killer_id: int, weapon_slot: int) -> void:
	if soldier != null and killer_id == soldier.entity_id and victim_id != killer_id:
		_hit_left = HIT_TIME * 2.0
		_hit_killed = true
	var victim := game.soldier(victim_id)
	var killer := game.soldier(killer_id)
	var weapon := Weapon.all[weapon_slot].short_name.to_lower()
	var parts: Array = []
	if killer == null or killer == victim:
		parts = [[_name(victim), InkUi.Face.SERIF_BOLD], [" " + weapon + ", self", InkUi.Face.ITALIC]]
	else:
		parts = [[_name(killer), InkUi.Face.SERIF_BOLD], [" " + weapon + " ", InkUi.Face.ITALIC], [_name(victim), InkUi.Face.SERIF_BOLD]]
	var by := killer if killer != null else victim
	_add_line(parts, by.team if by != null else 0, FEED_TIME)


## A line a bot on your team said, with the bot's name in bold and its team
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
	# "Bot 7" reads as "Lime 7", like the design's feed.
	return who.display_name.replace("Bot", Soldier.TEAM_NAMES[who.team])


func _process(delta: float) -> void:
	if soldier == null:
		return
	# Counted down and dropped in place, with no new arrays each frame.
	for k in range(_lines.size() - 1, -1, -1):
		_lines[k].left -= delta
		if _lines[k].left <= 0.0:
			_lines.remove_at(k)
	_message_left = maxf(_message_left - delta, 0.0)
	_hit_left = maxf(_hit_left - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	for k in range(_hurts.size() - 1, -1, -1):
		_hurts[k].left -= delta
		if _hurts[k].left <= 0.0:
			_hurts.remove_at(k)
	queue_redraw()


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
	# An arc around the crosshair pointing at where each hit came from, up for
	# ahead.
	for hurt in _hurts:
		var to: Vector3 = hurt.from - soldier.global_position
		var local := Basis(Vector3.UP, -soldier.yaw) * to
		var angle := atan2(local.x, -local.z) - PI * 0.5
		var radius := 62.0 * u
		var alpha := clampf(hurt.left / HURT_TIME, 0.0, 1.0)
		draw_arc(centre, radius, angle - 0.37, angle + 0.37, 16, Color(InkUi.INK, alpha), 9.0 * u, true)
		draw_arc(centre, radius, angle - 0.35, angle + 0.35, 16, Color(InkUi.PINK, alpha), 5.0 * u, true)
	_avoid = _touch_rects()
	var avoid := _avoid
	_top_edge = 0.0
	if game != null:
		_top_edge = _draw_score(u)
	_bottom_edge = _draw_status(u, avoid)
	_draw_feed(u, avoid)
	if game != null:
		_draw_flag_markers(u)
	if _message_left > 0.0:
		_banner(Vector2(centre.x, size.y * 0.3), _message, 20, clampf(_message_left, 0.0, 1.0))
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
		cells.append((28.0 + 8.0) * u + InkUi.width(str(game.scores[team]), InkUi.Face.BLACK, score_px) + InkUi.width(Soldier.TEAM_NAMES[team], InkUi.Face.ITALIC, name_px))
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
		var rel := clampf(_heading_to(flag.global_position), -span, span)
		_diamond(Vector2(mid + rel / span * reach, y + height * 0.5), height * 0.42, Palette.team(team))
	return tip.y


## The status panel at the bottom middle: health and energy bars and the
## weapon line, with a SKI tag on top while ski is held. With the touch
## controls showing, it stays at the bottom and fits the gap between them,
## shrinking as a whole if the gap is narrower than it. Returns its top.
func _draw_status(screen_u: float, avoid: Array[Rect2]) -> float:
	var design_tall := 6.0 + 14.0 + 4.0 + 14.0 + 4.0 + 14.0 + 6.0 + 4.0
	var bottom := size.y - 12.0 * screen_u
	var full := Rect2((size.x - 220.0 * screen_u) * 0.5, bottom - design_tall * screen_u, 220.0 * screen_u, design_tall * screen_u)
	# The gap between the touch controls beside the panel's band.
	var low := 0.0
	var high := size.x
	for box in avoid:
		if box.end.y <= full.position.y or box.position.y >= bottom:
			continue
		if box.get_center().x < size.x * 0.5:
			low = maxf(low, box.end.x)
		else:
			high = minf(high, box.position.x)
	var k := clampf((high - low) / full.size.x, 0.35, 1.0)
	var u := screen_u * k
	var line := maxf(1.0, 2.0 * u)
	var label_px := roundi(14.0 * u)
	var weapon_px := roundi(11.0 * u)
	var tall := design_tall * u
	var wide := 220.0 * u
	var middle := clampf(size.x * 0.5, low + wide * 0.5, maxf(high - wide * 0.5, low + wide * 0.5))
	var rect := Rect2(middle - wide * 0.5, bottom - tall, wide, tall)
	InkUi.box(self, rect, InkUi.CREAM, line)
	var x := rect.position.x + line + 10.0 * u
	var bar_left := x + 54.0 * u
	var bar_right := rect.end.x - line - 10.0 * u
	var y := rect.position.y + line + 6.0 * u
	var health := soldier.health / soldier.tuning.health_max
	var energy := soldier.energy / soldier.tuning.energy_max
	var refilling := soldier.since_jet >= soldier.tuning.refill_delay or soldier.jetting
	var rows := [["HEALTH", health, InkUi.PINK], ["ENERGY", energy, InkUi.ORANGE if refilling else InkUi.ORANGE.darkened(0.3)]]
	var f := InkUi.face(InkUi.Face.BLACK)
	for row: Array in rows:
		var baseline := y + 7.0 * u + (f.get_ascent(label_px) - f.get_descent(label_px)) * 0.5
		InkUi.words(self, Vector2(x, baseline), row[0], InkUi.Face.BLACK, label_px, InkUi.INK)
		var bar := Rect2(bar_left, y + 3.0 * u, bar_right - bar_left, 8.0 * u)
		var edge := maxf(1.5, 1.5 * u)
		draw_rect(bar, InkUi.INK)
		var inside := bar.grow(-edge)
		draw_rect(inside, InkUi.CREAM)
		draw_rect(Rect2(inside.position, Vector2(inside.size.x * clampf(row[1], 0.0, 1.0), inside.size.y)), row[2])
		y += 18.0 * u
	var weapon := Weapon.all[soldier.weapon]
	var words := "%s · %d · %d m/s" % [weapon.name, soldier.ammo[soldier.weapon], roundi(soldier.horizontal_speed())]
	InkUi.words(self, Vector2(rect.get_center().x, y + 10.0 * u), words, InkUi.Face.ITALIC, weapon_px, InkUi.INK, HORIZONTAL_ALIGNMENT_CENTER)
	if soldier.ski_held:
		# Orange while skiing on the ground, ink while held in the air.
		var tag_px := roundi(12.0 * u)
		var tag_wide := InkUi.width("SKI", InkUi.Face.BLACK, tag_px) + 12.0 * u
		var tag := Rect2(rect.end.x - tag_wide, rect.position.y - 16.0 * u + line, tag_wide, 16.0 * u)
		var fill := InkUi.ORANGE if soldier.skiing else InkUi.INK
		draw_rect(tag, InkUi.INK)
		draw_rect(tag.grow(-line), fill)
		InkUi.centred(self, tag.get_center(), "SKI", InkUi.Face.BLACK, tag_px, _text_on(fill))
		return tag.position.y
	return rect.position.y


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
		var point := flag.global_position + Vector3.UP * 3.0
		var local := inverse * point
		var behind := local.z > -0.05
		var colour := Palette.team(team)
		var screen := Vector2(-1000.0, -1000.0) if behind else camera.unproject_position(point)
		var inside := not behind and Rect2(Vector2.ZERO, size).grow(-margin).has_point(screen)
		var at := screen
		var dir := Vector2.ZERO
		if not inside:
			dir = Vector2(local.x, -local.y)
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
		var state := ""
		match flag.mode:
			Flag.Mode.CARRIED:
				var carrier := game.soldier(flag.carrier_id)
				state = "CARRIER" if carrier != soldier else "YOU"
			Flag.Mode.DROPPED:
				state = "DROPPED"
		_diamond(at, radius, colour, flag.mode != Flag.Mode.HOME)
		var label := "%s flag" % ("Your" if _mine(team) else "Enemy")
		var metres := roundi(soldier.global_position.distance_to(flag.global_position))
		var shown := "%s  %d m" % [label, metres] if state == "" else "%s %s  %d m" % [label, state.to_lower(), metres]
		shown = shown.to_upper()
		var text_at := at + Vector2(0.0, radius * 2.8)
		if not inside and dir.y > 0.5:
			text_at = at + Vector2(0.0, -radius * 1.6)
		elif not inside:
			# Above the arrow when below it would run into a touch button.
			var label_box := Rect2(text_at - Vector2(60.0 * u, 12.0 * u), Vector2(120.0 * u, 14.0 * u))
			for box in _avoid:
				if box.intersects(label_box):
					text_at = at + Vector2(0.0, -radius * 1.6)
					break
		var font_size := _px(13.0)
		# The label stays on screen.
		var half_width := InkUi.width(shown, InkUi.Face.BLACK, font_size) * 0.5 + font_size * 0.4
		text_at.x = clampf(text_at.x, half_width, maxf(size.x - half_width, half_width))
		InkUi.text(self, text_at, shown, font_size, colour.lightened(0.15))


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
