class_name Settings
extends RefCounted

## Player settings, kept in user://settings.cfg. Changing one takes effect
## straight away: apply() sets the ones that live outside a match, and the
## match reads the rest when the settings screen says they changed.

## Tests point this somewhere else so they don't touch your settings.
const SAVE_PATH := "user://settings.cfg"
static var path := SAVE_PATH

const VIEW_DISTANCES: Array[float] = [600.0, 900.0, 1200.0, 1800.0, 2400.0]
const RENDER_SCALES: Array[float] = [0.5, 0.67, 0.8, 1.0]
const LOOK_SPEEDS: Array[float] = [0.25, 0.4, 0.55, 0.7, 0.85, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]
const TOUCH_SIZES: Array[float] = [0.8, 0.9, 1.0, 1.15, 1.3]
## Gyro aim speeds, times the phone's own turn, with 0 for off.
const GYRO_SPEEDS: Array[float] = [0.0, 0.5, 1.0, 1.5, 2.0]

enum PadLayout { XBOX, NINTENDO }

const FACE_ACTIONS: Array[StringName] = [
	&"ui_accept", &"ui_cancel", &"jump", &"ski", &"board", &"use", &"next_weapon", &"practice_reset",
]
## Godot numbers face buttons by their position.
const NINTENDO_BUTTONS := {
	JOY_BUTTON_A: JOY_BUTTON_B, JOY_BUTTON_B: JOY_BUTTON_A,
	JOY_BUTTON_X: JOY_BUTTON_Y, JOY_BUTTON_Y: JOY_BUTTON_X,
}
const RETROID_LETTERED_BUTTONS: Array[int] = [1, 0, 3, 2]
const RETROID_POSITIONAL_BUTTONS: Array[int] = [0, 1, 2, 3]
const RETROID_ANDROID_GUID := "526574726f696420506f636b65742043"
## Keep the Retroid mapping's other bindings when normalising its face buttons.
const RETROID_ANDROID_MAPPING := (
	RETROID_ANDROID_GUID + ",Retroid Pocket,a:b%d,b:b%d,back:b4,dpdown:b12,dpleft:b13,dpright:b14,dpup:b11,"
	+ "leftshoulder:b9,leftstick:b7,lefttrigger:a5,leftx:a0,lefty:a1,paddle1:b17,paddle2:b18,"
	+ "rightshoulder:b10,rightstick:b8,righttrigger:a4,rightx:a2,righty:a3,start:b6,x:b%d,y:b%d,platform:Android,"
)

## Graphics a slow device starts with, until the player picks their own.
const WEAK_VIEW_DISTANCE := 900.0
const WEAK_RENDER_SCALE := 0.5

static var outlines := not weak_device()
static var hatching := not weak_device()
## How far you can see, in metres: the camera's far plane, where the fog is
## nearly solid, and how far chunked ground is drawn.
static var view_distance := WEAK_VIEW_DISTANCE if weak_device() else 1200.0
## Share of the screen's resolution the 3D view is drawn at.
static var render_scale := WEAK_RENDER_SCALE if weak_device() else 1.0
## Look speed for each input scheme, times the normal speed.
static var look_touch := 1.0
static var look_mouse := 1.0
static var look_pad := 1.0
static var pad_layout := PadLayout.XBOX
static var _retroid_face_buttons: Array[int] = []
static var invert_look := false
## Size of the touch controls, times the normal size.
static var touch_size := 1.0
## How touch jets: 0 is the JET button only, 1 adds the move stick (double-tap
## and hold, or push past its ring). More schemes can follow.
static var touch_scheme := 0
## Turning the phone turns your view, times this, with 0 for off. Touch only.
static var gyro := 0.0
static var invert_gyro := false
## Aim assist for touch and the gamepad, an AimAssist.Level: 0 off, 1 low, 2 high.
static var aim_assist := 1
## Skis for you whenever you're faster than a run or in the air.
static var auto_ski := false
## Lets you hand out your bots' roles from the order menu.
static var commander_mode := false
## Volumes from 0 to 1.
static var sound_volume := 0.8
static var voice_volume := 0.8
static var music_volume := 0.4
## Saved loadouts (Loadout.to_dict()), and the index of the last one used,
## which you start a match in.
static var loadouts: Array[Dictionary] = default_loadouts()
static var loadout_slot := 0

const LOADOUT_SLOTS := 3


## True on a slow device, which starts with lower graphics: Android with 4
## cores or fewer, or under 3 GB of memory, like the Fire HD 8.
static func weak_device() -> bool:
	if not OS.has_feature("android"):
		return false
	var memory: int = OS.get_memory_info().get("physical", -1)
	return OS.get_processor_count() <= 4 or (memory > 0 and memory < 3 * 1024 * 1024 * 1024)


## The saved loadouts to start with: medium with the disc, chaingun and
## grenade launcher and a shield, light with the disc and blaster and an
## energy pack, and heavy with the disc, chaingun, mortar and grenade
## launcher and a repair pack.
static func default_loadouts() -> Array[Dictionary]:
	return [
		Loadout.make(SoldierBody.Armour.MEDIUM, [Weapon.DISC, Weapon.CHAINGUN, Weapon.GRENADE_LAUNCHER], Pack.SHIELD).to_dict(),
		Loadout.make(SoldierBody.Armour.LIGHT, [Weapon.DISC, Weapon.BLASTER], Pack.ENERGY).to_dict(),
		Loadout.make(SoldierBody.Armour.HEAVY, [Weapon.DISC, Weapon.CHAINGUN, Weapon.MORTAR, Weapon.GRENADE_LAUNCHER], Pack.REPAIR).to_dict(),
	]


## A saved loadout, trimmed to its armour.
static func loadout(slot: int) -> Loadout:
	return Loadout.from_dict(loadouts[clampi(slot, 0, LOADOUT_SLOTS - 1)]).fixed()


## The last loadout used, which a match starts you in.
static func current_loadout() -> Loadout:
	return loadout(loadout_slot)


## Keeps a loadout in a slot, makes it the last used and saves the file.
static func save_loadout(slot: int, value: Loadout) -> void:
	slot = clampi(slot, 0, LOADOUT_SLOTS - 1)
	loadouts[slot] = value.fixed().to_dict()
	loadout_slot = slot
	save_file()


## Puts every setting back to how it starts.
static func reset() -> void:
	var weak := weak_device()
	outlines = not weak
	hatching = not weak
	view_distance = WEAK_VIEW_DISTANCE if weak else 1200.0
	render_scale = WEAK_RENDER_SCALE if weak else 1.0
	look_touch = 1.0
	look_mouse = 1.0
	look_pad = 1.0
	pad_layout = PadLayout.XBOX
	invert_look = false
	touch_size = 1.0
	touch_scheme = 0
	gyro = 0.0
	invert_gyro = false
	aim_assist = 1
	auto_ski = false
	commander_mode = false
	sound_volume = 0.8
	voice_volume = 0.8
	music_volume = 0.4
	loadouts = default_loadouts()
	loadout_slot = 0


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
		"pad_layout":
			return pad_layout
		"invert_look":
			return invert_look
		"touch_size":
			return touch_size
		"touch_scheme":
			return touch_scheme
		"gyro":
			return gyro
		"invert_gyro":
			return invert_gyro
		"aim_assist":
			return aim_assist
		"auto_ski":
			return auto_ski
		"commander_mode":
			return commander_mode
		"sound_volume":
			return sound_volume
		"voice_volume":
			return voice_volume
		"music_volume":
			return music_volume
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
		"pad_layout":
			pad_layout = PadLayout.NINTENDO if to is int and to == PadLayout.NINTENDO else PadLayout.XBOX
		"invert_look":
			invert_look = to
		"touch_size":
			touch_size = to
		"touch_scheme":
			touch_scheme = to
		"gyro":
			gyro = to
		"invert_gyro":
			invert_gyro = to
		"aim_assist":
			aim_assist = to
		"auto_ski":
			auto_ski = to
		"commander_mode":
			commander_mode = to
		"sound_volume":
			sound_volume = to
		"voice_volume":
			voice_volume = to
		"music_volume":
			music_volume = to


static func load_file() -> void:
	if path == SAVE_PATH and OS.has_feature("pc") and not FileAccess.file_exists(path):
		var previous := OS.get_user_data_dir().get_base_dir().path_join("Vectorfall/settings.cfg")
		if FileAccess.file_exists(previous):
			DirAccess.copy_absolute(previous, ProjectSettings.globalize_path(path))
	var file := ConfigFile.new()
	pad_layout = PadLayout.XBOX
	if file.load(path) == OK:
		outlines = file.get_value("graphics", "outlines", outlines)
		hatching = file.get_value("graphics", "hatching", hatching)
		view_distance = clampf(file.get_value("graphics", "view_distance", view_distance), 300.0, 3000.0)
		render_scale = clampf(file.get_value("graphics", "render_scale", render_scale), 0.25, 1.0)
		look_touch = clampf(file.get_value("controls", "look_touch", look_touch), 0.1, 5.0)
		look_mouse = clampf(file.get_value("controls", "look_mouse", look_mouse), 0.1, 5.0)
		look_pad = clampf(file.get_value("controls", "look_pad", look_pad), 0.1, 5.0)
		set_value("pad_layout", file.get_value("controls", "pad_layout", PadLayout.XBOX))
		invert_look = file.get_value("controls", "invert_look", invert_look)
		touch_size = clampf(file.get_value("controls", "touch_size", touch_size), 0.5, 2.0)
		touch_scheme = clampi(file.get_value("controls", "touch_scheme", touch_scheme), 0, 1)
		gyro = clampf(file.get_value("controls", "gyro", gyro), 0.0, 3.0)
		invert_gyro = file.get_value("controls", "invert_gyro", invert_gyro)
		aim_assist = clampi(file.get_value("controls", "aim_assist", aim_assist), 0, 2)
		auto_ski = file.get_value("controls", "auto_ski", auto_ski)
		commander_mode = file.get_value("bots", "commander", commander_mode)
		sound_volume = clampf(file.get_value("sound", "effects", sound_volume), 0.0, 1.0)
		voice_volume = clampf(file.get_value("sound", "voices", voice_volume), 0.0, 1.0)
		music_volume = clampf(file.get_value("sound", "music", music_volume), 0.0, 1.0)
		for k in LOADOUT_SLOTS:
			var saved: Variant = file.get_value("loadouts", "slot_%d" % (k + 1), loadouts[k])
			if saved is Dictionary:
				loadouts[k] = Loadout.from_dict(saved).fixed().to_dict()
		loadout_slot = clampi(file.get_value("loadouts", "last", loadout_slot), 0, LOADOUT_SLOTS - 1)
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
	file.set_value("controls", "pad_layout", pad_layout)
	file.set_value("controls", "invert_look", invert_look)
	file.set_value("controls", "touch_size", touch_size)
	file.set_value("controls", "touch_scheme", touch_scheme)
	file.set_value("controls", "gyro", gyro)
	file.set_value("controls", "invert_gyro", invert_gyro)
	file.set_value("controls", "aim_assist", aim_assist)
	file.set_value("controls", "auto_ski", auto_ski)
	file.set_value("bots", "commander", commander_mode)
	file.set_value("sound", "effects", sound_volume)
	file.set_value("sound", "voices", voice_volume)
	file.set_value("sound", "music", music_volume)
	for k in LOADOUT_SLOTS:
		file.set_value("loadouts", "slot_%d" % (k + 1), loadouts[k])
	file.set_value("loadouts", "last", loadout_slot)
	file.save(path)


## Sets what doesn't belong to a match: outlines, hatching, render scale and
## the sound volumes, and the gamepad bindings.
static func apply() -> void:
	Cel.set_outlines(outlines)
	Cel.set_hatching(hatching)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		tree.root.scaling_3d_scale = render_scale
		# MSAA with a scaled 3D buffer leaks memory every frame on Android GLES3.
		tree.root.msaa_3d = Viewport.MSAA_2X if render_scale >= 1.0 else Viewport.MSAA_DISABLED
	Sound.set_volumes(sound_volume, voice_volume, music_volume)
	_apply_pad_layout()


static func _apply_pad_layout() -> void:
	if Engine.has_singleton(DuoPanel.PLUGIN):
		var native := Engine.get_singleton(DuoPanel.PLUGIN)
		if native.call(&"isDuo"):
			var buttons := RETROID_LETTERED_BUTTONS if native.call(&"usesLetteredGamepad") else RETROID_POSITIONAL_BUTTONS
			if buttons != _retroid_face_buttons:
				# Godot uses the first mapping for a GUID on reconnect.
				Input.remove_joy_mapping(RETROID_ANDROID_GUID)
				Input.add_joy_mapping(RETROID_ANDROID_MAPPING % buttons, true)
				_retroid_face_buttons = buttons
	for action in FACE_ACTIONS:
		var defaults: Dictionary = ProjectSettings.get_setting("input/" + String(action))
		for event: InputEvent in defaults.events:
			var xbox := event as InputEventJoypadButton
			if xbox == null or not NINTENDO_BUTTONS.has(xbox.button_index):
				continue
			var nintendo := xbox.duplicate() as InputEventJoypadButton
			nintendo.button_index = NINTENDO_BUTTONS[xbox.button_index]
			var chosen := nintendo if pad_layout == PadLayout.NINTENDO else xbox
			var other := xbox if pad_layout == PadLayout.NINTENDO else nintendo
			if InputMap.action_has_event(action, other):
				InputMap.action_erase_event(action, other)
			if not InputMap.action_has_event(action, chosen):
				InputMap.action_add_event(action, chosen)


static func set_outlines(on: bool) -> void:
	outlines = on
	Cel.set_outlines(on)
	save_file()


static func set_hatching(on: bool) -> void:
	hatching = on
	Cel.set_hatching(on)
	save_file()
