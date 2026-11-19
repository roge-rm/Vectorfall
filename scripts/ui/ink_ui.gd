class_name InkUi
extends RefCounted

## The paperback cover look shared by the HUD, the touch controls and the
## menus: its colours, its two fonts (Big Shoulders Display for big upper case
## words, IBM Plex Serif for small text) and drawing helpers. Sizes in the
## design are pixels on a 390 pixel high screen; unit() turns them into
## pixels on this one.

const INK := Color("1a1410")
const CREAM := Color("f3e6c8")
const PAPER := CREAM
## Italic text on ink.
const AMBER := Color("f3b06a")
## Italic text on cream.
const RUST := Color("a2401c")
const BROWN_GREY := Color("6b5a48")
const ORANGE := Color("ff8a3d")
const PINK := Color("e0457b")
const PURPLE := Color("6a2c91")
const STRIPES: Array[Color] = [ORANGE, PINK, PURPLE]
## Height of the design's screen in its own pixels.
const DESIGN_HEIGHT := 390.0

enum Face { BLACK, BOLD, SERIF, SERIF_BOLD, ITALIC }

const FONT_FILES: Array[String] = [
	"res://art/fonts/BigShouldersDisplay-Black.ttf",
	"res://art/fonts/BigShouldersDisplay-Bold.ttf",
	"res://art/fonts/IBMPlexSerif-Medium.ttf",
	"res://art/fonts/IBMPlexSerif-Bold.ttf",
	"res://art/fonts/IBMPlexSerif-MediumItalic.ttf",
]

static var _fonts: Array[Font] = []
static var _theme: Theme


## One of the five faces the look uses.
static func face(which: Face) -> Font:
	if _fonts.is_empty():
		for path in FONT_FILES:
			_fonts.append(load(path) as Font)
	return _fonts[which]


## Big Shoulders Display Black, for the big upper case words.
static func font() -> Font:
	return face(Face.BLACK)


## Pixels per design pixel for a screen of this size: by its height, but no
## more than fits `design_width` design pixels across.
static func unit(screen: Vector2, design_width := 600.0) -> float:
	return minf(screen.y / DESIGN_HEIGHT, screen.x / design_width)


## Width of words in a face at a size.
static func width(words: String, which: Face, font_size: int) -> float:
	return face(which).get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x


## Words drawn with their baseline at at.y, starting at at.x, centred on it or
## ending at it. outline is an ink edge in pixels, for text over the game.
## Returns the width.
static func words(item: CanvasItem, at: Vector2, text: String, which: Face, font_size: int, colour: Color, align := HORIZONTAL_ALIGNMENT_LEFT, outline := 0) -> float:
	var f := face(which)
	var wide := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var start := at
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		start.x -= wide * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		start.x -= wide
	if outline > 0:
		f.draw_string_outline(item.get_canvas_item(), start, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, outline, Color(INK, colour.a))
	f.draw_string(item.get_canvas_item(), start, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, colour)
	return wide


## Words centred on at, both ways, in a face.
static func centred(item: CanvasItem, at: Vector2, text: String, which: Face, font_size: int, colour: Color, outline := 0) -> void:
	var f := face(which)
	var baseline := at.y + (f.get_ascent(font_size) - f.get_descent(font_size)) * 0.5
	words(item, Vector2(at.x, baseline), text, which, font_size, colour, HORIZONTAL_ALIGNMENT_CENTER, outline)


## Big Shoulders words with an ink edge, centred on at.x unless align says
## otherwise, for labels over the game.
static func text(item: CanvasItem, at: Vector2, text: String, font_size: int, colour := CREAM, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	words(item, at, text.to_upper(), Face.BLACK, font_size, colour, align, maxi(3, roundi(font_size * 0.22)))


## A box filled and outlined in ink, the line inside the rect.
static func box(item: CanvasItem, rect: Rect2, fill: Color, line: float) -> void:
	item.draw_rect(rect, Color(INK, fill.a))
	item.draw_rect(rect.grow(-line), fill)


## The kept name for a box with an ink edge.
static func panel(item: CanvasItem, rect: Rect2, fill: Color, short: float) -> void:
	box(item, rect.grow(maxf(2.0, short / DESIGN_HEIGHT * 2.0)), fill, maxf(2.0, short / DESIGN_HEIGHT * 2.0))


## A closed shape filled and outlined in ink.
static func shape(item: CanvasItem, points: PackedVector2Array, fill: Color, short: float) -> void:
	var line := maxf(1.5, short / DESIGN_HEIGHT * 1.5)
	var closed := points.duplicate()
	closed.append(points[0])
	item.draw_colored_polygon(points, fill)
	item.draw_polyline(closed, Color(INK, fill.a), line, true)


## A line with an ink edge round it.
static func stroke(item: CanvasItem, from: Vector2, to: Vector2, colour: Color, width: float) -> void:
	item.draw_line(from, to, Color(INK, colour.a), width + 4.0)
	item.draw_line(from, to, colour, width)


## The three colour stripe, as bars on top of each other or columns side by
## side.
static func stripes(item: CanvasItem, rect: Rect2, columns := false) -> void:
	for k in 3:
		if columns:
			var w := rect.size.x / 3.0
			item.draw_rect(Rect2(rect.position.x + w * k, rect.position.y, w, rect.size.y), STRIPES[k])
		else:
			var h := rect.size.y / 3.0
			item.draw_rect(Rect2(rect.position.x, rect.position.y + h * k, rect.size.x, h), STRIPES[k])


## Theme for the HUD's labels and panels: serif ink text on cream.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	_theme.default_font = face(Face.SERIF)
	_theme.set_color("font_color", "Label", INK)
	var panel_box := StyleBoxFlat.new()
	panel_box.bg_color = CREAM
	panel_box.border_color = INK
	panel_box.set_border_width_all(4)
	panel_box.set_content_margin_all(18)
	_theme.set_stylebox("panel", "PanelContainer", panel_box)
	return _theme
