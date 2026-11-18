class_name Settings
extends RefCounted

## Player settings, kept in user://settings.cfg. Changing one takes effect
## straight away: apply() sets the ones that live outside a match, and the
## match reads the rest when the settings screen says they changed.

## Tests point this somewhere else so they don't touch your settings.
static var path := "user://settings.cfg"

const VIEW_DISTANCES: Array[float] = [600.0, 900.0, 1200.0, 1800.0, 2400.0]
const RENDER_SCALES: Array[float] = [0.5, 0.67, 0.8, 1.0]
const LOOK_SPEEDS: Array[float] = [0.25, 0.4, 0.55, 0.7, 0.85, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]
const TOUCH_SIZES: Array[float] = [0.8, 0.9, 1.0, 1.15, 1.3]

static var outlines := true
static var hatching := true
## How far you can see, in metres: the camera's far plane, where the fog is
## nearly solid, and how far chunked ground is drawn.
static var view_distance := 1200.0
## Share of the screen's resolution the 3D view is drawn at.
static var render_scale := 1.0
## Look speed for each input scheme, times the normal speed.
static var look_touch := 1.0
static var look_mouse := 1.0
static var look_pad := 1.0
static var invert_look := false
## Size of the touch controls, times the normal size.
static var touch_size := 1.0
## Skis for you whenever you're faster than a run or in the air.
static var auto_ski := false
## Lets you hand out your bots' roles from the order menu.
static var commander_mode := false
## Volumes from 0 to 1, for sound effects and the bots' voices.
static var sound_volume := 0.8
static var voice_volume := 0.8


## Puts every setting back to how it starts.
static func reset() -> void:
	outlines = true
	hatching = true
	view_distance = 1200.0
	render_scale = 1.0
	look_touch = 1.0
	look_mouse = 1.0
	look_pad = 1.0
	invert_look = false
	touch_size = 1.0
	auto_ski = false
	commander_mode = false
	sound_volume = 0.8
	voice_volume = 0.8


## A setting by name, for the settings screen.
static func value(setting: String) -> Variant:
	match setting:
		"outlines":
			return outlines
		"hatching":
			return hatching
		"view_distance":
			return view_distance
		"render_scale":
			return render_scale
		"look_touch":
			return look_touch
		"look_mouse":
			return look_mouse
		"look_pad":
			return look_pad
		"invert_look":
			return invert_look
		"touch_size":
			return touch_size
		"auto_ski":
			return auto_ski
		"commander_mode":
			return commander_mode
		"sound_volume":
			return sound_volume
		"voice_volume":
			return voice_volume
	return null


static func set_value(setting: String, to: Variant) -> void:
	match setting:
		"outlines":
			outlines = to
		"hatching":
			hatching = to
		"view_distance":
			view_distance = to
		"render_scale":
			render_scale = to
		"look_touch":
			look_touch = to
		"look_mouse":
			look_mouse = to
		"look_pad":
			look_pad = to
		"invert_look":
			invert_look = to
		"touch_size":
			touch_size = to
		"auto_ski":
			auto_ski = to
		"commander_mode":
			commander_mode = to
		"sound_volume":
			sound_volume = to
		"voice_volume":
			voice_volume = to


static func load_file() -> void:
	var file := ConfigFile.new()
	if file.load(path) == OK:
		outlines = file.get_value("graphics", "outlines", outlines)
		hatching = file.get_value("graphics", "hatching", hatching)
		view_distance = clampf(file.get_value("graphics", "view_distance", view_distance), 300.0, 3000.0)
		render_scale = clampf(file.get_value("graphics", "render_scale", render_scale), 0.25, 1.0)
		look_touch = clampf(file.get_value("controls", "look_touch", look_touch), 0.1, 5.0)
		look_mouse = clampf(file.get_value("controls", "look_mouse", look_mouse), 0.1, 5.0)
		look_pad = clampf(file.get_value("controls", "look_pad", look_pad), 0.1, 5.0)
		invert_look = file.get_value("controls", "invert_look", invert_look)
		touch_size = clampf(file.get_value("controls", "touch_size", touch_size), 0.5, 2.0)
		auto_ski = file.get_value("controls", "auto_ski", auto_ski)
		commander_mode = file.get_value("bots", "commander", commander_mode)
		sound_volume = clampf(file.get_value("sound", "effects", sound_volume), 0.0, 1.0)
		voice_volume = clampf(file.get_value("sound", "voices", voice_volume), 0.0, 1.0)
	apply()


static func save_file() -> void:
	var file := ConfigFile.new()
	file.load(path)
	file.set_value("graphics", "outlines", outlines)
	file.set_value("graphics", "hatching", hatching)
	file.set_value("graphics", "view_distance", view_distance)
	file.set_value("graphics", "render_scale", render_scale)
	file.set_value("controls", "look_touch", look_touch)
	file.set_value("controls", "look_mouse", look_mouse)
	file.set_value("controls", "look_pad", look_pad)
	file.set_value("controls", "invert_look", invert_look)
	file.set_value("controls", "touch_size", touch_size)
	file.set_value("controls", "auto_ski", auto_ski)
	file.set_value("bots", "commander", commander_mode)
	file.set_value("sound", "effects", sound_volume)
	file.set_value("sound", "voices", voice_volume)
	file.save(path)


## Sets what doesn't belong to a match: outlines, hatching, render scale and
## the sound volumes.
static func apply() -> void:
	Cel.set_outlines(outlines)
	Cel.set_hatching(hatching)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		tree.root.scaling_3d_scale = render_scale
		# MSAA with a scaled 3D buffer leaks memory every frame on Android GLES3.
		tree.root.msaa_3d = Viewport.MSAA_2X if render_scale >= 1.0 else Viewport.MSAA_DISABLED
	Sound.set_volumes(sound_volume, voice_volume)


static func set_outlines(on: bool) -> void:
	outlines = on
	Cel.set_outlines(on)
	save_file()


static func set_hatching(on: bool) -> void:
	hatching = on
	Cel.set_hatching(on)
	save_file()
