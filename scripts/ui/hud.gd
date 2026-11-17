class_name Hud
extends Control

## Crosshair, health and jet energy bars, speed, the ski light, weapons and
## ammo, hit markers, arrows towards whoever hurt you, a kill feed and the
## respawn count. It only reads the soldier and hears the match's signals.

const FEED_LINES := 5
const FEED_TIME := 6.0
const HIT_TIME := 0.25
const HURT_TIME := 1.5

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
