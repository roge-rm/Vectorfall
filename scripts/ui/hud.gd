class_name Hud
extends Control

## Crosshair, jet energy bar, speed readout and ski light for one soldier.
## It only reads the soldier.

var soldier: Soldier
var _speed_label: Label
var _ski_label: Label


func _init() -> void:
	name = "Hud"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_label = Label.new()
	_speed_label.add_theme_font_size_override("font_size", 26)
	_speed_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_speed_label.add_theme_constant_override("outline_size", 6)
	add_child(_speed_label)
	_ski_label = Label.new()
	_ski_label.text = "SKI"
	_ski_label.add_theme_font_size_override("font_size", 22)
	_ski_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_ski_label.add_theme_constant_override("outline_size", 6)
	add_child(_ski_label)


func _process(_delta: float) -> void:
	if soldier == null:
		return
	_speed_label.text = "%d km/h" % roundi(soldier.horizontal_speed() * 3.6)
	var short := minf(size.x, size.y)
	_speed_label.position = Vector2(size.x * 0.5 - _speed_label.size.x * 0.5, size.y - short * 0.16 - _speed_label.size.y)
	# Bright while skiing on the ground, dim while held in the air.
	_ski_label.visible = soldier.ski_held
	_ski_label.modulate = Color(0.55, 1.0, 0.85) if soldier.skiing else Color(1, 1, 1, 0.45)
	_ski_label.position = Vector2(size.x * 0.5 + short * 0.25, size.y - short * 0.1 - _ski_label.size.y * 0.3)
	queue_redraw()


func _draw() -> void:
	var short := minf(size.x, size.y)
	var centre := size * 0.5
	var line := maxf(2.0, short * 0.003)
	var gap := short * 0.012
	var arm := short * 0.022
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(centre + dir * gap, centre + dir * (gap + arm), Color(0, 0, 0, 0.6), line + 2.0)
		draw_line(centre + dir * gap, centre + dir * (gap + arm), Color.WHITE, line)
	if soldier == null:
		return
	var bar := Vector2(short * 0.45, short * 0.03)
	var corner := Vector2(size.x * 0.5 - bar.x * 0.5, size.y - short * 0.1)
	var share := soldier.energy / soldier.tuning.energy_max
	draw_rect(Rect2(corner - Vector2(3, 3), bar + Vector2(6, 6)), Color(0, 0, 0, 0.55))
	var colour := Color(0.35, 0.85, 1.0) if soldier.since_jet >= soldier.tuning.refill_delay or soldier.jetting else Color(0.25, 0.55, 0.7)
	if share < 0.2:
		colour = Color(1.0, 0.45, 0.3)
	draw_rect(Rect2(corner, Vector2(bar.x * share, bar.y)), colour)
