class_name Hud
extends Control

## Crosshair, health and jet energy bars, speed, the ski light, weapons and
## ammo, hit markers, arrows towards whoever hurt you, a kill feed and the
## respawn count, the score and clock, flag messages, markers and arrows for
## both flags, a compass strip and the end of match screen. It only reads the
## soldier and the match and hears the match's signals.

signal restart_requested

const FEED_LINES := 5
const FEED_TIME := 6.0
const HIT_TIME := 0.25
const HURT_TIME := 1.5
const MESSAGE_TIME := 3.5

var soldier: Soldier
var game: Match
var _speed_label: Label
var _ski_label: Label
var _respawn_label: Label
var _weapon_labels: Array[Label] = []
var _feed: VBoxContainer
## Seconds left on the hit marker, and whether the hit killed.
var _hit_left := 0.0
var _hit_killed := false
## Where recent damage came from, with seconds left to show it.
var _hurts: Array[Dictionary] = []
var _flash := 0.0
var _message := ""
var _message_left := 0.0
var _end_panel: PanelContainer
var _end_title: Label
var _end_score: Label


func _init() -> void:
	name = "Hud"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_label = _label(26)
	_ski_label = _label(22)
	_ski_label.text = "SKI"
	_respawn_label = _label(34)
	for weapon in Weapon.all:
		_weapon_labels.append(_label(22))
	_feed = VBoxContainer.new()
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_feed)
	_make_end_panel()


func _make_end_panel() -> void:
	_end_panel = PanelContainer.new()
	_end_panel.visible = false
	_end_panel.set_anchors_preset(Control.PRESET_CENTER)
	_end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	_end_panel.add_child(box)
	_end_title = Label.new()
	_end_title.add_theme_font_size_override("font_size", 44)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_title)
	_end_score = Label.new()
	_end_score.add_theme_font_size_override("font_size", 30)
	_end_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_score)
	var button := Button.new()
	button.text = "Restart (R)"
	button.add_theme_font_size_override("font_size", 28)
	button.pressed.connect(restart_requested.emit)
	box.add_child(button)
	add_child(_end_panel)


func _label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


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
	_end_panel.visible = true
	if team < 0:
		_end_title.text = "Draw"
	else:
		_end_title.text = "%s team wins" % Soldier.TEAM_NAMES[team]
		_end_title.add_theme_color_override("font_color", Soldier.TEAM_COLOURS[team].lightened(0.2))
	_end_score.text = "%s %d : %d %s" % [Soldier.TEAM_NAMES[0], game.scores[0], game.scores[1], Soldier.TEAM_NAMES[1]]


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
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_OFF
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_font_size_override("normal_font_size", 20)
	line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	line.add_theme_constant_override("outline_size", 5)
	line.size_flags_horizontal = Control.SIZE_SHRINK_END
	var weapon := Weapon.all[weapon_slot].short_name
	if killer == null or killer == victim:
		line.text = "%s  [color=#ccc][%s][/color]  self" % [_name(victim), weapon]
	else:
		line.text = "%s  [color=#ccc][%s][/color]  %s" % [_name(killer), weapon, _name(victim)]
	line.set_meta("left", FEED_TIME)
	_feed.add_child(line)
	while _feed.get_child_count() > FEED_LINES:
		var oldest := _feed.get_child(0)
		_feed.remove_child(oldest)
		oldest.queue_free()


func _name(who: Soldier) -> String:
	if who == null:
		return "?"
	var shown := "You" if who == soldier else who.display_name
	return "[color=#%s]%s[/color]" % [Soldier.TEAM_COLOURS[who.team].lightened(0.25).to_html(false), shown]


func _process(delta: float) -> void:
	if soldier == null:
		return
	var short := minf(size.x, size.y)
	_speed_label.text = "%d km/h" % roundi(soldier.horizontal_speed() * 3.6)
	_speed_label.position = Vector2(size.x * 0.5 - _speed_label.size.x * 0.5, size.y - short * 0.2 - _speed_label.size.y)
	# Bright while skiing on the ground, dim while held in the air.
	_ski_label.visible = soldier.ski_held
	_ski_label.modulate = Color(0.55, 1.0, 0.85) if soldier.skiing else Color(1, 1, 1, 0.45)
	_ski_label.position = Vector2(size.x * 0.5 + short * 0.25, size.y - short * 0.1 - _ski_label.size.y * 0.3)
	_respawn_label.visible = soldier.dead
	_respawn_label.text = "Respawning in %d" % ceili(maxf(soldier.respawn_in, 0.0))
	_respawn_label.position = Vector2(size.x * 0.5 - _respawn_label.size.x * 0.5, size.y * 0.3)
	# Weapons at the top left, the one in hand bright, clear of the touch
	# stick.
	var y := short * 0.03
	for k in _weapon_labels.size():
		var label := _weapon_labels[k]
		label.text = "%d  %s  %d" % [k + 1, Weapon.all[k].name, soldier.ammo[k]]
		label.modulate = Color.WHITE if k == soldier.weapon else Color(1, 1, 1, 0.45)
		label.position = Vector2(short * 0.04, y)
		y += label.size.y
	_feed.position = Vector2(size.x - _feed.size.x - short * 0.03, short * 0.03)
	_feed.size = Vector2(short * 0.9, 0.0)
	for line in _feed.get_children():
		var left: float = line.get_meta("left") - delta
		line.set_meta("left", left)
		line.modulate.a = clampf(left, 0.0, 1.0)
		if left <= 0.0:
			line.queue_free()
	_message_left = maxf(_message_left - delta, 0.0)
	_hit_left = maxf(_hit_left - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	for hurt in _hurts:
		hurt.left -= delta
	_hurts = _hurts.filter(func(hurt: Dictionary) -> bool: return hurt.left > 0.0)
	queue_redraw()


func _draw() -> void:
	var short := minf(size.x, size.y)
	var centre := size * 0.5
	var line := maxf(2.0, short * 0.003)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.1, 0.05, _flash * 0.4))
	var gap := short * 0.012
	var arm := short * 0.022
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(centre + dir * gap, centre + dir * (gap + arm), Color(0, 0, 0, 0.6), line + 2.0)
		draw_line(centre + dir * gap, centre + dir * (gap + arm), Color.WHITE, line)
	if soldier == null:
		return
	if game != null:
		_draw_match(short)
	if _hit_left > 0.0:
		var colour := Color(1.0, 0.25, 0.2) if _hit_killed else Color.WHITE
		var near := short * 0.018
		var far := short * 0.034
		for dir: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var d := dir.normalized()
			draw_line(centre + d * near, centre + d * far, Color(0, 0, 0, 0.6), line + 3.0)
			draw_line(centre + d * near, centre + d * far, colour, line + 1.0)
	# An arc around the crosshair pointing at where each hit came from, up for
	# ahead.
	for hurt in _hurts:
		var to: Vector3 = hurt.from - soldier.global_position
		var local := Basis(Vector3.UP, -soldier.yaw) * to
		var angle := atan2(local.x, -local.z) - PI * 0.5
		var radius := short * 0.16
		var alpha := clampf(hurt.left / HURT_TIME, 0.0, 1.0)
		draw_arc(centre, radius, angle - 0.35, angle + 0.35, 16, Color(1.0, 0.2, 0.15, 0.85 * alpha), short * 0.014, true)

	# Health above jet energy, bottom middle.
	var bar := Vector2(short * 0.45, short * 0.03)
	var corner := Vector2(size.x * 0.5 - bar.x * 0.5, size.y - short * 0.1)
	var health_corner := corner - Vector2(0.0, bar.y + short * 0.02)
	var health := soldier.health / soldier.tuning.health_max
	draw_rect(Rect2(health_corner - Vector2(3, 3), bar + Vector2(6, 6)), Color(0, 0, 0, 0.55))
	var health_colour := Color(0.4, 0.95, 0.45) if health > 0.35 else Color(1.0, 0.3, 0.25)
	draw_rect(Rect2(health_corner, Vector2(bar.x * health, bar.y)), health_colour)
	var share := soldier.energy / soldier.tuning.energy_max
	draw_rect(Rect2(corner - Vector2(3, 3), bar + Vector2(6, 6)), Color(0, 0, 0, 0.55))
	var colour := Color(0.35, 0.85, 1.0) if soldier.since_jet >= soldier.tuning.refill_delay or soldier.jetting else Color(0.25, 0.55, 0.7)
	if share < 0.2:
		colour = Color(1.0, 0.45, 0.3)
	draw_rect(Rect2(corner, Vector2(bar.x * share, bar.y)), colour)


func _text(at: Vector2, text: String, font_size: int, colour := Color.WHITE, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, align, -1.0, font_size).x
	var start := at
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		start.x -= width * 0.5
	font.draw_string_outline(get_canvas_item(), start, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 6, Color(0, 0, 0, 0.85))
	font.draw_string(get_canvas_item(), start, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, colour)


func _diamond(at: Vector2, radius: float, colour: Color, filled := true) -> void:
	var points := PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius * 0.75, 0), at + Vector2(0, radius), at + Vector2(-radius * 0.75, 0)])
	if filled:
		draw_colored_polygon(points, colour)
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, Color(0, 0, 0, 0.9), 4.0)
	draw_polyline(closed, Color.WHITE if filled else colour, 2.0)


func _clock_text() -> String:
	var seconds := ceili(game.time_left)
	return "%d:%02d" % [seconds / 60, seconds % 60]


## Score and clock at the top, the flag message and the markers and compass.
func _draw_match(short: float) -> void:
	var y := short * 0.06
	var font := roundi(short * 0.05)
	_text(Vector2(size.x * 0.5 - short * 0.2, y), "%d" % game.scores[0], font, Soldier.TEAM_COLOURS[0].lightened(0.15))
	_text(Vector2(size.x * 0.5, y), _clock_text(), font)
	_text(Vector2(size.x * 0.5 + short * 0.2, y), "%d" % game.scores[1], font, Soldier.TEAM_COLOURS[1].lightened(0.15))
	if _message_left > 0.0:
		var colour := Color(1, 1, 1, clampf(_message_left, 0.0, 1.0))
		_text(Vector2(size.x * 0.5, size.y * 0.3), _message, roundi(short * 0.055), colour)
	_draw_compass(short)
	_draw_flag_markers(short)


func _heading_to(point: Vector3) -> float:
	var d := point - soldier.global_position
	return wrapf(atan2(d.x, -d.z) + soldier.yaw, -PI, PI)


## A strip with the headings in front of you, and a mark for each flag.
func _draw_compass(short: float) -> void:
	var width := minf(size.x * 0.4, short * 0.9)
	var left := size.x * 0.5 - width * 0.5
	var y := short * 0.1
	var height := short * 0.035
	var span := PI * 0.5
	draw_rect(Rect2(left, y, width, height), Color(0, 0, 0, 0.35))
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	for k in 24:
		var bearing := k * TAU / 24.0
		var rel := wrapf(bearing + soldier.yaw, -PI, PI)
		if absf(rel) > span:
			continue
		var x := size.x * 0.5 + rel / span * width * 0.5
		var cardinal := k % 3 == 0
		draw_line(Vector2(x, y + height), Vector2(x, y + height - height * (0.6 if cardinal else 0.3)), Color(1, 1, 1, 0.8), 2.0)
		if cardinal:
			_text(Vector2(x, y + height * 0.55), names[k / 3], roundi(height * 0.55), Color(0.9, 0.95, 1.0) if k % 6 == 0 else Color(1, 1, 1, 0.7))
	draw_line(Vector2(size.x * 0.5, y + height), Vector2(size.x * 0.5, y + height + height * 0.35), Color.WHITE, 3.0)
	for team in game.flags:
		var flag := game.flags[team]
		var rel := clampf(_heading_to(flag.global_position), -span, span)
		var colour := Soldier.TEAM_COLOURS[team].lightened(0.2)
		_diamond(Vector2(size.x * 0.5 + rel / span * width * 0.5, y + height * 0.5), height * 0.55, colour)


func _draw_flag_markers(short: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var margin := short * 0.07
	var radius := short * 0.02
	var inverse := camera.global_transform.affine_inverse()
	for team in game.flags:
		var flag := game.flags[team]
		var point := flag.global_position + Vector3.UP * 3.0
		var local := inverse * point
		var behind := local.z > -0.05
		var colour := Soldier.TEAM_COLOURS[team].lightened(0.2)
		var screen := Vector2(-1000.0, -1000.0) if behind else camera.unproject_position(point)
		var inside := not behind and Rect2(Vector2.ZERO, size).grow(-margin).has_point(screen)
		var at := screen
		var dir := Vector2.ZERO
		if not inside:
			dir = Vector2(local.x, -local.y)
			dir = dir.normalized() if dir.length() > 0.001 else Vector2.DOWN
			# Arrows stay below the score and compass and above the bars.
			var top := short * 0.19
			var bottom := size.y - short * 0.24
			var middle := Vector2(size.x * 0.5, (top + bottom) * 0.5)
			var half := Vector2(size.x * 0.5 - margin, (bottom - top) * 0.5)
			var scale := minf(half.x / maxf(absf(dir.x), 0.0001), half.y / maxf(absf(dir.y), 0.0001))
			at = middle + dir * scale
			var tip := at + dir * radius * 2.4
			var side := dir.orthogonal() * radius * 0.9
			var arrow := PackedVector2Array([tip, at + dir * radius * 1.0 + side, at + dir * radius * 1.0 - side])
			draw_colored_polygon(arrow, colour)
			draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[0]]), Color(0, 0, 0, 0.9), 3.0)
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
		var text_at := at + Vector2(0.0, radius * 2.8)
		if not inside and dir.y > 0.5:
			text_at = at + Vector2(0.0, -radius * 1.6)
		_text(text_at, shown, roundi(short * 0.026), colour)
