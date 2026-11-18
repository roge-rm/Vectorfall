class_name InkUi
extends RefCounted

## The HUD's comic ink look: a bold slanted font, thick ink outlines with a
## dropped ink shadow, paper coloured fills, and a theme for labels, buttons
## and panels.

const INK := Color(0.07, 0.05, 0.04)
const PAPER := Color(0.98, 0.93, 0.84)
## Dropped shadow offset and outline width, as shares of the screen's short
## side.
const SHADOW := 0.005
const LINE := 0.004

static var _font: FontVariation
static var _theme: Theme


## The fallback font made bold and slanted like comic lettering.
static func font() -> Font:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = ThemeDB.fallback_font
		_font.variation_embolden = 0.9
		_font.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-0.18, 1.0), Vector2.ZERO)
		_font.spacing_glyph = 1
	return _font


## Text with a thick ink outline and an ink shadow, centred on at.x unless
## align says otherwise.
static func text(item: CanvasItem, at: Vector2, words: String, font_size: int, colour := PAPER, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var f := font()
	var width := f.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var start := at
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		start.x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		start.x -= width
	var outline := maxi(4, roundi(font_size * 0.28))
	var drop := Vector2(1.0, 1.0) * maxf(2.0, font_size * 0.08)
	var ink := Color(INK, colour.a)
	f.draw_string_outline(item.get_canvas_item(), start + drop, words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, outline, ink)
	f.draw_string(item.get_canvas_item(), start + drop, words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, ink)
	f.draw_string_outline(item.get_canvas_item(), start, words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, outline, ink)
	f.draw_string(item.get_canvas_item(), start, words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, colour)


## A comic panel: an ink shadow, an ink border and a fill.
static func panel(item: CanvasItem, rect: Rect2, fill: Color, short: float) -> void:
	var line := maxf(2.0, short * LINE)
	var drop := Vector2(1.0, 1.0) * maxf(2.0, short * SHADOW)
	item.draw_rect(Rect2(rect.position + drop, rect.size).grow(line), Color(INK, fill.a))
	item.draw_rect(rect.grow(line), Color(INK, maxf(fill.a, 0.9)))
	item.draw_rect(rect, fill)


## A closed shape filled and outlined in ink, with an ink shadow.
static func shape(item: CanvasItem, points: PackedVector2Array, fill: Color, short: float) -> void:
	var line := maxf(2.0, short * LINE)
	var drop := Vector2(1.0, 1.0) * maxf(2.0, short * SHADOW)
	var closed := points.duplicate()
	closed.append(points[0])
	var shadow := PackedVector2Array()
	for p in closed:
		shadow.append(p + drop)
	item.draw_polyline(shadow, Color(INK, fill.a), line * 2.0)
	item.draw_colored_polygon(points, fill)
	item.draw_polyline(closed, Color(INK, fill.a), line)


## A line with an ink edge round it.
static func stroke(item: CanvasItem, from: Vector2, to: Vector2, colour: Color, width: float) -> void:
	item.draw_line(from, to, Color(INK, colour.a), width + 4.0)
	item.draw_line(from, to, colour, width)


## Theme for HUD labels, buttons and panels.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	_theme.default_font = font()
	_theme.set_color("font_color", "Label", PAPER)
	_theme.set_color("font_outline_color", "Label", INK)
	_theme.set_constant("outline_size", "Label", 8)
	_theme.set_color("font_shadow_color", "Label", INK)
	_theme.set_constant("shadow_offset_x", "Label", 2)
	_theme.set_constant("shadow_offset_y", "Label", 3)
	var box := StyleBoxFlat.new()
	box.bg_color = PAPER
	box.border_color = INK
	box.set_border_width_all(4)
	box.shadow_color = INK
	box.shadow_offset = Vector2(5, 5)
	box.shadow_size = 1
	box.set_content_margin_all(18)
	_theme.set_stylebox("panel", "PanelContainer", box)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var button := box.duplicate() as StyleBoxFlat
		button.bg_color = INK if state == "pressed" else Color(0.95, 0.72, 0.3) if state == "hover" else PAPER
		button.set_content_margin_all(10)
		_theme.set_stylebox(state, "Button", button)
	for state: String in ["font_color", "font_hover_color", "font_focus_color"]:
		_theme.set_color(state, "Button", INK)
	_theme.set_color("font_pressed_color", "Button", PAPER)
	return _theme
