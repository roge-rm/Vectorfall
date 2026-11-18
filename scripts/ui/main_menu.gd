class_name MainMenu
extends Node

## The first screen: Play (to match setup), Settings, How to play and Quit
## (not on Android), over a slow camera circling Ochre Fold. The map is built
## a few frames after the menu shows, without its route graph.

const MATCH_SCENE := "res://scenes/main.tscn"
## Radians a second the camera circles at.
const ORBIT_SPEED := 0.03

var map: GameMap
var camera: Camera3D
var ui: Control
var home: Control
var setup_screen: SetupScreen
var settings_screen: SettingsScreen
var how_to: HowToPlay
## Last input used, as a LocalInput.Device.
var device := LocalInput.Device.KEYBOARD
var _cover: ColorRect
var _loading: Label
var _angle := 0.4
var _starting := false


func _ready() -> void:
	Settings.load_file()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	if DisplayServer.is_touchscreen_available() and OS.has_feature("mobile"):
		device = LocalInput.Device.TOUCH
	camera = Camera3D.new()
	camera.fov = 60.0
	camera.far = 3000.0
	add_child(camera)
	camera.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.name = "MenuUi"
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = MenuKit.theme()
	layer.add_child(ui)
	# Paper over everything until the map is in.
	_cover = ColorRect.new()
	_cover.color = OchreFold.palette_for_map().horizon
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_cover)
	_make_home()
	setup_screen = SetupScreen.new()
	setup_screen.visible = false
	setup_screen.closed.connect(show_home)
	setup_screen.start_pressed.connect(start_match)
	ui.add_child(setup_screen)
	settings_screen = SettingsScreen.new()
	settings_screen.visible = false
	settings_screen.closed.connect(show_home)
	ui.add_child(settings_screen)
	how_to = HowToPlay.new()
	how_to.visible = false
	how_to.closed.connect(show_home)
	ui.add_child(how_to)
	_loading = MenuKit.heading("Loading", 40)
	_loading.set_anchors_preset(Control.PRESET_CENTER)
	_loading.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading.visible = false
	ui.add_child(_loading)
	show_home()
	_build_backdrop.call_deferred()


func _build_backdrop() -> void:
	# Two frames so the menu is on screen while the map builds.
	await get_tree().process_frame
	await get_tree().process_frame
	SoundBank.build()
	map = OchreFold.new(null, false)
	add_child(map)
	map.set_view_distance(Settings.view_distance)
	_place_camera()


func _make_home() -> void:
	home = Control.new()
	home.name = "Home"
	home.set_anchors_preset(Control.PRESET_FULL_RECT)
	home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(home)
	var title := Title.new()
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home.add_child(title)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	column.anchor_left = 0.06
	column.anchor_right = 0.36
	column.anchor_top = 0.36
	column.anchor_bottom = 0.95
	home.add_child(column)
	column.add_child(MenuKit.button("Play", show_setup, 34))
	column.add_child(MenuKit.button("Settings", show_settings, 34))
	column.add_child(MenuKit.button("How to play", show_how_to, 34))
	if not OS.has_feature("android"):
		column.add_child(MenuKit.button("Quit", func() -> void: get_tree().quit(), 34, true))
	var version := Label.new()
	version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "")
	version.add_theme_font_size_override("font_size", 20)
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.position -= Vector2(16.0, 10.0)
	home.add_child(version)


## The game's name in big paperback lettering.
class Title:
	extends Control

	func _draw() -> void:
		var short := minf(size.x, size.y)
		var font_size := roundi(short * 0.14)
		var at := Vector2(size.x * 0.06, size.y * 0.25)
		InkUi.text(self, at, "VECTORFALL", font_size, Palette.team(0).lightened(0.1), HORIZONTAL_ALIGNMENT_LEFT)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()


func _hide_all() -> void:
	for screen: Control in [home, setup_screen, settings_screen, how_to]:
		screen.visible = false


func show_home() -> void:
	_hide_all()
	home.visible = true
	MenuKit.focus_first(home)


func show_setup() -> void:
	_hide_all()
	setup_screen.open()


func show_settings() -> void:
	_hide_all()
	settings_screen.open()


func show_how_to() -> void:
	_hide_all()
	how_to.open(device)


## Starts a match with these choices, after a frame showing Loading.
func start_match(setup: MatchSetup) -> void:
	if _starting:
		return
	_starting = true
	MatchSetup.current = setup.duplicate()
	_hide_all()
	_loading.text = "Loading %s" % SetupScreen.MAP_TITLES[maxi(GameMap.NAMES.find(setup.map), 0)]
	_loading.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(MATCH_SCENE)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		device = LocalInput.Device.TOUCH
	elif event is InputEventJoypadButton:
		device = LocalInput.Device.GAMEPAD
	elif event is InputEventKey or (event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION):
		device = LocalInput.Device.KEYBOARD


## Circles team 0's base, high enough to see over it down the map.
func _place_camera() -> void:
	var base := Vector3(map.base_x(0), map.deck_height(), 0.0)
	var at := base + Vector3(cos(_angle) * 95.0, 38.0, sin(_angle) * 95.0)
	at.y = maxf(at.y, map.height_at(at.x, at.z) + 20.0)
	camera.look_at_from_position(at, base + Vector3(0.0, 6.0, 0.0))


func _process(delta: float) -> void:
	if map == null:
		return
	if _cover.visible:
		# Fades the paper away over 0.8 s, from the frame after the map is in.
		_cover.modulate.a -= minf(delta, 0.05) / 0.8
		_cover.visible = _cover.modulate.a > 0.0
	_angle += delta * ORBIT_SPEED
	_place_camera()
