class_name MainMenu
extends Node

## The first screen, a paperback cover: the title band, Play (to match
## setup), Settings, How to play and Quit (not on Android), and a framed
## cover picture. The sounds are made a couple of frames after it shows.

const MATCH_SCENE := "res://scenes/main.tscn"
const PRACTICE_SCENE := "res://scenes/ski_practice.tscn"
const DRILL_SCENE := "res://scenes/training_drill.tscn"

var ui: Control
var home: CoverPage
var setup_screen: SetupScreen
var settings_screen: SettingsScreen
var how_to: HowToPlay
var online: OnlineScreen
var ladder: LadderScreen
var drills: DrillsScreen
## Last input used, as a LocalInput.Device.
var device := LocalInput.Device.KEYBOARD
var _loading: Label
var _starting := false
var _home_focus: Control
## Frames shown, to make the sounds on the third.
var _frames := 0


func _ready() -> void:
	Settings.load_file()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	if DisplayServer.is_touchscreen_available() and OS.has_feature("mobile"):
		device = LocalInput.Device.TOUCH
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.name = "MenuUi"
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = MenuKit.theme()
	layer.add_child(ui)
	var back := ColorRect.new()
	back.color = InkUi.CREAM
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(back)
	home = CoverPage.new()
	home.name = "Home"
	ui.add_child(home)
	home.add_button("Play", show_setup)
	home.add_button("Bot ladder", show_ladder)
	home.add_button("Online", show_online)
	home.add_button("Settings", show_settings)
	home.add_button("How to play", show_how_to)
	if not OS.has_feature("android") and not OS.has_feature("web"):
		home.add_button("Quit", func() -> void: get_tree().quit(), false, true)
	setup_screen = SetupScreen.new()
	setup_screen.visible = false
	setup_screen.closed.connect(show_home)
	setup_screen.start_pressed.connect(start_match)
	ui.add_child(setup_screen)
	settings_screen = SettingsScreen.new()
	settings_screen.visible = false
	settings_screen.closed.connect(show_home)
	ui.add_child(settings_screen)
	how_to = HowToPlay.new(true)
	how_to.visible = false
	how_to.closed.connect(show_home)
	how_to.practice_pressed.connect(start_practice)
	how_to.drills_pressed.connect(show_drills)
	ui.add_child(how_to)
	online = OnlineScreen.new()
	online.hide()
	online.closed.connect(show_home)
	ui.add_child(online)
	ladder = LadderScreen.new()
	ladder.closed.connect(show_home)
	ladder.round_pressed.connect(start_ladder_round)
	ui.add_child(ladder)
	drills = DrillsScreen.new()
	drills.closed.connect(_return_to_how_to)
	drills.drill_pressed.connect(start_drill)
	ui.add_child(drills)
	_loading = MenuKit.heading("Loading", 48)
	_loading.set_anchors_preset(Control.PRESET_CENTER)
	_loading.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading.grow_vertical = Control.GROW_DIRECTION_BOTH
	_loading.visible = false
	ui.add_child(_loading)
	if BotLadder.active != BotLadder.Round.NONE:
		BotLadder.active = BotLadder.Round.NONE
		show_ladder()
	elif TrainingDrill.returning:
		TrainingDrill.returning = false
		show_drills()
	elif not OnlineClient.last_error.is_empty() or not OnlineScreen.linked_server().is_empty():
		show_online()
	else:
		show_home()


func _process(_delta: float) -> void:
	# The sounds are made once the menu has been on screen for two frames.
	_frames += 1
	if _frames == 2 and OS.has_feature("web"):
		JavaScriptBridge.eval("window.skifreiShown?.()")
	if _frames == 3:
		SoundBank.build()


## The map, team sizes and mode of the next match, for the cover's footnote.
static func footnote(setup: MatchSetup) -> String:
	var map_title := SetupScreen.MAP_TITLES[maxi(GameMap.NAMES.find(setup.map), 0)]
	return "%s · %d against %d · bots" % [map_title, setup.own_bots + 1, setup.enemy_bots]


func _hide_all() -> void:
	if home.visible:
		var focused := get_viewport().gui_get_focus_owner()
		if focused in home.buttons:
			_home_focus = focused
	for screen: Control in [home, setup_screen, settings_screen, how_to, online, ladder, drills]:
		screen.visible = false


func show_home() -> void:
	_hide_all()
	home.footnote = footnote(MatchSetup.load_saved())
	home.visible = true
	home.queue_redraw()
	if _home_focus != null:
		_home_focus.grab_focus()
	else:
		MenuKit.focus_first(home)


func show_setup() -> void:
	_hide_all()
	setup_screen.open()


func show_ladder() -> void:
	_hide_all()
	ladder.open()


func show_online() -> void:
	_hide_all()
	online.open()


func show_settings() -> void:
	_hide_all()
	settings_screen.open()


func show_how_to() -> void:
	_hide_all()
	how_to.open(device)


func _return_to_how_to() -> void:
	show_how_to()
	how_to.drills_button.grab_focus()


func show_drills() -> void:
	_hide_all()
	drills.open(TrainingDrill.selected)


func start_drill(index: int) -> void:
	if _starting:
		return
	_starting = true
	TrainingDrill.selected = index as TrainingDrill.Kind
	get_tree().change_scene_to_file(DRILL_SCENE)


func start_practice() -> void:
	if _starting:
		return
	_starting = true
	get_tree().change_scene_to_file(PRACTICE_SCENE)


func start_ladder_round(round_index: int) -> void:
	if _starting or not BotLadder.unlocked(round_index, BotLadder.completed()):
		return
	BotLadder.active = round_index
	if round_index == BotLadder.Round.SKI:
		start_practice()
	else:
		_load_match(BotLadder.match_setup(round_index).map)


## Starts a match with these choices, after a frame showing Loading.
func start_match(setup: MatchSetup) -> void:
	if _starting:
		return
	MatchSetup.current = setup.duplicate()
	_load_match(setup.map)


func _load_match(map_name: String) -> void:
	_starting = true
	_hide_all()
	_loading.text = ("Loading %s" % SetupScreen.MAP_TITLES[maxi(GameMap.NAMES.find(map_name), 0)]).to_upper()
	_loading.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(MATCH_SCENE)


func _notification(what: int) -> void:
	# Android's back button quits from the home screen; the other screens
	# go back home by themselves.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and home != null and home.visible and not _starting:
		get_tree().quit()


func _input(event: InputEvent) -> void:
	var previous := device
	if event is InputEventScreenTouch:
		device = LocalInput.Device.TOUCH
	elif event is InputEventJoypadButton:
		device = LocalInput.Device.GAMEPAD
	elif event is InputEventKey or ((event is InputEventMouseButton or event is InputEventMouseMotion)
			and event.device != InputEvent.DEVICE_ID_EMULATION):
		device = LocalInput.Device.KEYBOARD
	if device != previous and home != null:
		for button in home.buttons:
			button.highlight_hover = device != LocalInput.Device.GAMEPAD
			button.queue_redraw()


## The home screen: the ink title band with the tagline, the stripes, a
## column of numbered buttons, the framed cover picture, the footnote and the
## round version badge. Laid out in design pixels (a 390 pixel high screen at
## least 693 wide); on taller screens everything under the stripes is centred
## in the space left.
class CoverPage:
	extends Control

	const TAGLINE: Array[String] = ["Capture the flag", "Up to 32 players"]

	var footnote := ""
	var buttons: Array[MenuKit.CoverButton] = []
	var picture: CoverPicture
	## Over the picture, for the version badge.
	var _badge: Control
	var _title_font: FontVariation

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture = CoverPicture.new()
		add_child(picture)
		_badge = Control.new()
		_badge.set_anchors_preset(Control.PRESET_FULL_RECT)
		_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_badge.draw.connect(_draw_badge)
		add_child(_badge)
		_title_font = FontVariation.new()
		_title_font.base_font = InkUi.face(InkUi.Face.BLACK)

	func add_button(words: String, pressed: Callable, filled := false, back := false) -> void:
		var made := MenuKit.button(words, pressed, 36, back, filled, buttons.size() + 1)
		made.centre_words = false
		add_child(made)
		buttons.append(made)
		# Up and down go round the column.
		for k in buttons.size():
			var above := buttons[k - 1]
			var below := buttons[(k + 1) % buttons.size()]
			buttons[k].focus_neighbor_top = buttons[k].get_path_to(above)
			buttons[k].focus_neighbor_bottom = buttons[k].get_path_to(below)
		_layout()

	func _unit() -> float:
		return InkUi.unit(size, 693.0)

	## Space added above the content under the stripes, in design pixels.
	func _drop() -> float:
		return maxf(size.y / _unit() - InkUi.DESIGN_HEIGHT, 0.0) * 0.5

	func _layout() -> void:
		if size.y <= 0.0:
			return
		var u := _unit()
		var wide := size.x / u
		var drop := _drop()
		var tall := 54.0 if buttons.size() <= 3 else (39.0 if buttons.size() >= 5 else 46.0)
		var gap := 6.0 if buttons.size() >= 5 else 8.0
		var font_size := 32.0 if buttons.size() >= 5 else 36.0
		if buttons.size() == 6:
			tall = 34.0
			gap = 5.0
			font_size = 30.0
		for k in buttons.size():
			buttons[k].custom_minimum_size = Vector2(270.0, tall) * u
			buttons[k].position = Vector2(28.0, 132.0 + drop + k * (tall + gap)) * u
			buttons[k].size = buttons[k].custom_minimum_size
			buttons[k].font_size = roundi(font_size * u)
		var frame_width := minf(486.0, wide - 28.0 - 330.0)
		var frame := Rect2(wide - 28.0 - frame_width, 130.0 + drop, frame_width, frame_width * 236.0 / 486.0)
		picture.position = frame.position * u
		picture.size = frame.size * u
		_title_font.spacing_glyph = roundi(2.0 * u)
		queue_redraw()
		_badge.queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_layout()

	func _draw() -> void:
		var u := _unit()
		var wide := size.x
		var band := 92.0 * u
		draw_rect(Rect2(0.0, 0.0, wide, band), InkUi.INK)
		InkUi.stripes(self, Rect2(0.0, band, wide, 18.0 * u))
		var title_size := roundi(84.0 * u)
		_title_font.draw_string(get_canvas_item(), Vector2(28.0 * u, band - 12.0 * u), "SKIFREI", HORIZONTAL_ALIGNMENT_LEFT, -1.0, title_size, InkUi.CREAM)
		var tag_size := roundi(13.0 * u)
		for k in TAGLINE.size():
			var baseline := band - (14.0 + (TAGLINE.size() - 1 - k) * 17.0) * u
			InkUi.words(self, Vector2(wide - 28.0 * u, baseline), TAGLINE[k], InkUi.Face.ITALIC, tag_size, InkUi.AMBER, HORIZONTAL_ALIGNMENT_RIGHT)
		# The footnote sits under the buttons, at 330 with three of them.
		var last := buttons[-1] if not buttons.is_empty() else null
		var foot_y := 342.0 * u + _drop() * u
		if last != null:
			foot_y = maxf(foot_y, last.position.y + last.size.y + 22.0 * u)
		InkUi.words(self, Vector2(28.0 * u, foot_y), footnote, InkUi.Face.ITALIC, roundi(12.0 * u), InkUi.BROWN_GREY)

	## The version badge, over the stripes and the picture's corner, turned
	## 10 degrees.
	func _draw_badge() -> void:
		var u := _unit()
		var centre := Vector2(size.x - (18.0 + 31.0) * u, (104.0 + 31.0) * u)
		_badge.draw_circle(centre, 31.0 * u, InkUi.INK)
		_badge.draw_circle(centre, 29.0 * u, InkUi.PINK)
		_badge.draw_set_transform(centre, deg_to_rad(10.0))
		var version := "v%s" % ProjectSettings.get_setting("application/config/version", "")
		InkUi.centred(_badge, Vector2.ZERO, version, InkUi.Face.BLACK, roundi(18.0 * u), InkUi.CREAM)
		_badge.draw_set_transform(Vector2.ZERO)


## The cover picture: a sunset over three rows of hills with halftone dots
## over it, a tower and a soldier falling with his jetpack lit, in a 3 px ink
## frame. Drawn from the design's 480 x 230 numbers, scaled to fit.
class CoverPicture:
	extends Control

	const SKY: Array[Color] = [Color("3a1a5c"), Color("c8487a"), Color("ff9a52")]
	const FAR := [0, 150, 60, 96, 110, 128, 170, 70, 240, 132, 300, 110, 380, 140, 480, 92, 480, 230, 0, 230]
	const MID := [0, 180, 90, 150, 200, 170, 300, 148, 420, 172, 480, 160, 480, 230, 0, 230]
	const NEAR := [0, 200, 140, 186, 260, 204, 480, 190, 480, 230, 0, 230]
	const TOWER := [96, 160, 104, 120, 116, 120, 124, 160]
	const TORSO := [0, 0, 14, -6, 22, 8, 18, 30, 6, 34, -4, 22]
	const LEFT_LEG := [6, 34, -2, 56, 6, 56, 12, 36]
	const RIGHT_LEG := [16, 32, 22, 54, 30, 52, 22, 30]
	const PACK := [-4, 22, -16, 46, -6, 50, 2, 30]
	const FLAME := [-10, 48, -20, 74, -2, 52]

	var _sky: GradientTexture2D
	var _dots: ImageTexture
	var _dot_scale := 0.0

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
		gradient.colors = PackedColorArray(SKY)
		_sky = GradientTexture2D.new()
		_sky.gradient = gradient
		_sky.fill_from = Vector2(0.0, 0.0)
		_sky.fill_to = Vector2(0.0, 1.0)
		_sky.width = 4
		_sky.height = 128

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	## A 6 x 6 design pixel tile with one dot in the middle, at this scale.
	func _dot_tile(s: float) -> ImageTexture:
		if _dots != null and is_equal_approx(s, _dot_scale):
			return _dots
		var n := maxi(3, roundi(6.0 * s))
		var image := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
		var r := 1.2 * n / 6.0
		var c := n * 0.5
		for y in n:
			for x in n:
				# Four samples a pixel for a soft edge.
				var hits := 0
				for sy in 2:
					for sx in 2:
						var p := Vector2(x + 0.25 + sx * 0.5, y + 0.25 + sy * 0.5)
						if p.distance_to(Vector2(c, c)) <= r:
							hits += 1
				image.set_pixel(x, y, Color(InkUi.INK, 0.35 * hits / 4.0))
		_dots = ImageTexture.create_from_image(image)
		_dot_scale = s
		return _dots

	func _points(numbers: Array, s: float, at := Vector2.ZERO, turn := 0.0) -> PackedVector2Array:
		var points := PackedVector2Array()
		for k in range(0, numbers.size(), 2):
			points.append((at + Vector2(numbers[k], numbers[k + 1]).rotated(turn)) * s)
		return points

	func _draw() -> void:
		var frame := 3.0 * size.y / 236.0
		var inside := Rect2(Vector2.ONE * frame, size - Vector2.ONE * frame * 2.0)
		draw_set_transform(inside.position)
		var s := inside.size.x / 480.0
		draw_texture_rect(_sky, Rect2(Vector2.ZERO, inside.size), false)
		draw_circle(Vector2(350.0, 96.0) * s, 56.0 * s, Color("ffd27a"))
		for bar: Vector2 in [Vector2(70.0, 5.0), Vector2(84.0, 6.0), Vector2(100.0, 8.0)]:
			draw_rect(Rect2(Vector2(290.0, bar.x) * s, Vector2(120.0, bar.y) * s), Color("c8487a"))
		draw_colored_polygon(_points(FAR, s), Color("4b2170"))
		draw_colored_polygon(_points(MID, s), Color("e2703a"))
		draw_colored_polygon(_points(NEAR, s), Color("f39a5a"))
		draw_texture_rect(_dot_tile(s), Rect2(Vector2.ZERO, inside.size), true)
		draw_colored_polygon(_points(TOWER, s), InkUi.INK)
		draw_rect(Rect2(Vector2(86.0, 112.0) * s, Vector2(48.0, 10.0) * s), InkUi.INK)
		var at := Vector2(220.0, 40.0)
		var turn := deg_to_rad(-14.0)
		draw_colored_polygon(_points(TORSO, s, at, turn), InkUi.INK)
		draw_circle((at + Vector2(12.0, -12.0).rotated(turn)) * s, 8.0 * s, InkUi.INK)
		draw_colored_polygon(_points(LEFT_LEG, s, at, turn), InkUi.INK)
		draw_colored_polygon(_points(RIGHT_LEG, s, at, turn), InkUi.INK)
		draw_colored_polygon(_points(PACK, s, at, turn), InkUi.ORANGE)
		draw_colored_polygon(_points(FLAME, s, at, turn), Color("ffd27a"))
		draw_set_transform(Vector2.ZERO)
		draw_rect(Rect2(Vector2.ONE * frame * 0.5, size - Vector2.ONE * frame), InkUi.INK, false, frame)
