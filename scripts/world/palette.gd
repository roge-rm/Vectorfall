class_name Palette
extends Resource

## A map's colours and light: sky, sun, ambient, fog, ink and paper, the
## ground's colours by slope and height, and the colour of built things. The
## map script picks one and Atmosphere puts it on the scene. All of them keep
## the world's colours below the team colours, which are the strongest.

## The team colours in use, set by Atmosphere from its palette.
static var teams: Array[Color] = Soldier.TEAM_COLOURS.duplicate()

@export var title := ""
## Team 0 and team 1, which every team coloured thing reads through team().
@export var team_colours: Array[Color] = Soldier.TEAM_COLOURS.duplicate()
@export var zenith := Color(0.5, 0.47, 0.42)
@export var horizon := Color(0.86, 0.77, 0.6)
## The sky below the horizon.
@export var sky_ground := Color(0.6, 0.52, 0.36)
## Pointing at the sun.
@export var sun_direction := Vector3(-0.369, 0.766, 0.527)
@export var sun_colour := Color(1.0, 0.9, 0.74)
@export var ambient := Color(0.62, 0.56, 0.5)
@export var ambient_energy := 0.5
@export var fog_colour := Color(0.86, 0.77, 0.6)
@export var fog_density := 0.0016
@export var ink := Color(0.07, 0.05, 0.04)
@export var paper := Color(0.98, 0.93, 0.84)
## How much the paper grain darkens, 0 to 1. The sky has none.
@export var grit := 0.06
## Flat ground in two patch colours, gentle slopes and steep slopes.
@export var grass := Color(0.66, 0.58, 0.4)
@export var grass_dark := Color(0.6, 0.52, 0.36)
@export var dirt := Color(0.62, 0.48, 0.34)
@export var rock := Color(0.48, 0.44, 0.4)
## Flat ground below low_height and above high_height, in metres.
@export var low := Color(0.7, 0.62, 0.45)
@export var low_height := -1000.0
@export var high := Color(0.85, 0.8, 0.7)
@export var high_height := 1000.0
## Decks, ramps and pillars, and loose rocks.
@export var structure := Color(0.66, 0.63, 0.58)
@export var boulder := Color(0.48, 0.44, 0.4)
## Colour strength of everything but the team colours, 0 to 1.
@export var saturation := 0.75
## The middle and dark bands are multiplied by these, white for none.
@export var mid_tint := Color(1.0, 1.0, 1.0)
@export var dark_tint := Color(1.0, 1.0, 1.0)
## Hatching in this colour instead of ink, by its alpha.
@export var hatch_colour := Color(0.0, 0.0, 0.0, 0.0)
## Added to the lit band above highlight_edge (n.l), by its alpha.
@export var highlight := Color(0.0, 0.0, 0.0, 0.0)
@export var highlight_edge := 0.9
## How much team colours ignore the colour of the light, 0 to 1, so a
## strongly coloured sun doesn't mute them.
@export var team_white_light := 0.0
## Soldiers' blob shadows: colour with alpha as strength, and how many
## times longer than wide they stretch away from the sun, 1 for round.
@export var blob_colour := Color(0.0, 0.0, 0.0, 0.45)
@export var blob_length := 1.0
## Where the bands change, in n.l: lit above lit_edge, middle above
## mid_edge, and hatching crosses below deep_edge. A low sun needs them
## lower, or flat ground falls into shade.
@export var lit_edge := 0.72
@export var mid_edge := 0.3
@export var deep_edge := -0.15
## Brightness of the middle and dark bands.
@export var shade_mid := 0.5
@export var shade_dark := 0.18
## Shade in its own hue, by its alpha: the middle band goes half way to it
## and the dark band all the way, keeping their brightness. Clear for none.
@export var shade_colour := Color(0.0, 0.0, 0.0, 0.0)
## Hatching in the shade, if the hatching setting is on too.
@export var hatching := true
## Outline width, 1 for the usual, and how much it wobbles like a brush.
@export var line_width := 1.0
@export var line_brush := 0.15

## Light strips along built things, by alpha, like tech lights at dusk.
@export var tech_glow := Color(0.0, 0.0, 0.0, 0.0)

@export_group("Ground detail")
## A third ground colour in patches about patch_size metres across,
## covering about patch_amount of the flat ground (0 for none).
@export var patch_colour := Color(1.0, 1.0, 1.0)
@export var patch_amount := 0.0
@export var patch_size := 6.0
## A fourth in the gaps between those patches, covering about
## patch_alt_amount.
@export var patch_alt := Color(1.0, 1.0, 1.0)
@export var patch_alt_amount := 0.0
## A soft drift towards this colour (multiplied) across the ground, by up
## to variation, over about variation_size metres.
@export var variation_colour := Color(1.0, 1.0, 1.0)
@export var variation := 0.0
@export var variation_size := 30.0
## Steep rock in level bands strata metres high, every other one rock_alt.
## 0 for none.
@export var rock_alt := Color(0.5, 0.5, 0.5)
@export var strata := 0.0

@export_group("Sky detail")
## A third sky colour at middle_height (0 horizon, 1 straight up), by its
## alpha, and flat bands instead of a smooth gradient (0 for smooth).
@export var sky_middle := Color(0.0, 0.0, 0.0, 0.0)
@export var sky_middle_height := 0.3
@export var sky_bands := 0.0
## Clouds covering about cloud_amount of the sky (0 for none), lit and
## shaded colours, and their size.
@export var cloud_amount := 0.0
@export var cloud_colour := Color(1.0, 0.97, 0.88)
@export var cloud_shade := Color(0.7, 0.72, 0.85)
@export var cloud_scale := 1.0
## Mountain ranges drawn in the sky, by alpha, with their top height as the
## sine of the angle above the horizon.
@export var far_range := Color(0.0, 0.0, 0.0, 0.0)
@export var far_range_height := 0.12
@export var near_range := Color(0.0, 0.0, 0.0, 0.0)
@export var near_range_height := 0.07


## A team's colour in the palette in use.
static func team(index: int) -> Color:
	return teams[index % teams.size()]


## Dry red rock: gold sand in the valleys, rose dust with sage scrub on the
## flats, sage on the tops, rose-brown slopes and maroon rock under a teal
## sky. The reds lean to crimson so
## the orange team stays apart from them.
static func desert() -> Palette:
	var made := Palette.new()
	made.title = "Red rock desert"
	made.zenith = Color(0.2, 0.5, 0.74)
	made.horizon = Color(0.95, 0.82, 0.62)
	made.sky_ground = Color(0.72, 0.6, 0.45)
	made.sun_direction = Vector3(-0.4, 0.8, 0.45)
	made.sun_colour = Color(1.0, 0.9, 0.74)
	made.ambient = Color(0.66, 0.58, 0.6)
	made.ambient_energy = 0.5
	made.fog_colour = Color(0.92, 0.8, 0.64)
	made.fog_density = 0.0018
	made.ink = Color(0.1, 0.04, 0.05)
	made.paper = Color(1.0, 0.95, 0.86)
	made.grass = Color(0.84, 0.62, 0.52)
	made.grass_dark = Color(0.62, 0.66, 0.44)
	made.dirt = Color(0.7, 0.46, 0.44)
	made.rock = Color(0.56, 0.22, 0.32)
	made.low = Color(0.94, 0.8, 0.52)
	made.low_height = -20.0
	made.high = Color(0.6, 0.62, 0.42)
	made.high_height = 1.0
	made.structure = Color(0.84, 0.8, 0.72)
	made.boulder = Color(0.52, 0.24, 0.32)
	made.saturation = 0.75
	return made


## Cold highland: green turf, heather slopes, slate rock, teal bog in the
## valleys and snow on the tops, under a grey-blue sky. The greens and
## purples keep the blue team apart from the world.
static func highland() -> Palette:
	var made := Palette.new()
	made.title = "Cold highland"
	made.zenith = Color(0.36, 0.46, 0.6)
	made.horizon = Color(0.82, 0.86, 0.86)
	made.sky_ground = Color(0.4, 0.5, 0.44)
	made.sun_direction = Vector3(0.3, 0.8, 0.52)
	made.sun_colour = Color(0.94, 0.96, 1.0)
	made.ambient = Color(0.56, 0.6, 0.68)
	made.ambient_energy = 0.55
	made.fog_colour = Color(0.8, 0.84, 0.85)
	made.fog_density = 0.0024
	made.ink = Color(0.04, 0.05, 0.08)
	made.paper = Color(0.95, 0.96, 0.95)
	made.grass = Color(0.44, 0.64, 0.4)
	made.grass_dark = Color(0.36, 0.56, 0.38)
	made.dirt = Color(0.56, 0.45, 0.6)
	made.rock = Color(0.4, 0.42, 0.5)
	made.low = Color(0.3, 0.52, 0.44)
	made.low_height = -22.0
	made.high = Color(0.93, 0.95, 0.98)
	made.high_height = 3.0
	made.structure = Color(0.7, 0.7, 0.68)
	made.boulder = Color(0.42, 0.44, 0.5)
	made.saturation = 0.75
	return made


## The desert at golden hour: a low deep gold sun from the side, a sky from
## peach at the horizon to dusty rose overhead, warm violet shade and long
## violet shadows. Team colours ignore most of the sun's colour.
static func desert_golden_hour() -> Palette:
	var made := desert()
	made.title = "Red rock desert, golden hour"
	made.zenith = Color(0.72, 0.5, 0.58)
	made.horizon = Color(1.0, 0.78, 0.6)
	made.sky_ground = Color(0.74, 0.54, 0.46)
	made.sun_direction = Vector3(-0.72, 0.3, 0.62)
	made.lit_edge = 0.22
	made.mid_edge = -0.1
	made.deep_edge = -0.4
	made.sun_colour = Color(1.0, 0.72, 0.4)
	made.ambient = Color(0.6, 0.48, 0.72)
	made.ambient_energy = 0.55
	made.fog_colour = Color(0.98, 0.74, 0.6)
	made.ink = Color(0.12, 0.04, 0.09)
	made.paper = Color(1.0, 0.95, 0.88)
	made.mid_tint = Color(0.92, 0.82, 1.0)
	made.dark_tint = Color(0.78, 0.64, 0.95)
	made.hatch_colour = Color(0.24, 0.1, 0.3, 0.5)
	made.highlight = Color(1.0, 0.7, 0.35, 0.18)
	made.highlight_edge = 0.85
	made.team_white_light = 0.7
	# Less colour in the world, so orange stands out from gold sand.
	made.saturation = 0.6
	made.blob_colour = Color(0.3, 0.12, 0.42, 0.55)
	made.blob_length = 5.0
	return made


## A copy with dark brown ink and hatching on cream paper.
func sepia() -> Palette:
	var made := duplicate() as Palette
	made.title = title + ", sepia"
	made.ink = Color(0.25, 0.13, 0.06)
	made.paper = Color(1.0, 0.93, 0.8)
	made.hatch_colour = Color(0.0, 0.0, 0.0, 0.0)
	# The cream paper turns a blue sky green, so take some green out of it.
	made.zenith = Color(made.zenith.r + 0.06, made.zenith.g, minf(made.zenith.b + 0.06, 1.0))
	return made


## A copy with shade in burnt sienna and plum and a buttery highlight on
## the most lit faces.
func warm_shadows() -> Palette:
	var made := duplicate() as Palette
	made.title = title + ", warm shadows"
	made.mid_tint = Color(1.0, 0.64, 0.44)
	made.dark_tint = Color(0.78, 0.44, 0.62)
	made.hatch_colour = Color(0.36, 0.1, 0.16, 0.8)
	made.highlight = Color(1.0, 0.86, 0.45, 0.25)
	made.highlight_edge = 0.93
	made.team_white_light = 0.3
	return made


## Warm sun and cool shade, like a painted animation background: gold sand,
## green grass with coral patches and mauve rock in a warm sun from the
## left, teal and violet shade, a deep blue sky with big cream clouds and
## blue mountains. Clean even ink lines, no grain or hatching.
static func sun_and_shade() -> Palette:
	var made := Palette.new()
	made.title = "Warm sun, cool shade"
	made.zenith = Color(0.1, 0.3, 0.72)
	made.horizon = Color(0.6, 0.8, 0.95)
	made.sky_ground = Color(0.5, 0.62, 0.5)
	made.cloud_amount = 0.42
	made.cloud_colour = Color(1.0, 0.96, 0.84)
	made.cloud_shade = Color(0.66, 0.66, 0.88)
	made.cloud_scale = 1.4
	made.far_range = Color(0.44, 0.52, 0.8, 1.0)
	made.far_range_height = 0.2
	made.near_range = Color(0.3, 0.5, 0.6, 1.0)
	made.near_range_height = 0.13
	made.sun_direction = Vector3(0.74, 0.56, 0.36)
	made.lit_edge = 0.45
	made.mid_edge = 0.12
	made.deep_edge = -0.3
	made.sun_colour = Color(1.0, 0.92, 0.74)
	made.ambient = Color(0.5, 0.6, 0.82)
	made.ambient_energy = 0.42
	made.shade_mid = 0.5
	made.shade_dark = 0.3
	made.dark_tint = Color(0.8, 0.7, 1.0)
	made.shade_colour = Color(0.12, 0.46, 0.74, 0.7)
	made.fog_colour = Color(0.66, 0.8, 0.94)
	made.fog_density = 0.0022
	made.ink = Color(0.07, 0.08, 0.16)
	made.paper = Color(1.0, 1.0, 1.0)
	made.grit = 0.0
	made.hatching = false
	made.line_brush = 0.0
	made.grass = Color(1.0, 0.72, 0.32)
	made.grass_dark = Color(0.46, 0.72, 0.3)
	made.patch_colour = Color(0.96, 0.5, 0.46)
	made.patch_amount = 0.22
	made.patch_size = 14.0
	made.patch_alt = Color(0.98, 0.84, 0.4)
	made.patch_alt_amount = 0.0
	made.dirt = Color(0.86, 0.66, 0.38)
	made.rock = Color(0.6, 0.46, 0.56)
	made.rock_alt = Color(0.7, 0.56, 0.52)
	made.strata = 3.0
	made.low = Color(1.0, 0.8, 0.44)
	made.high = Color(0.5, 0.74, 0.32)
	made.variation_colour = Color(1.1, 1.0, 0.78)
	made.variation = 0.25
	made.structure = Color(0.88, 0.86, 0.8)
	made.boulder = Color(0.6, 0.52, 0.64)
	made.saturation = 0.95
	made.team_white_light = 0.3
	made.blob_colour = Color(0.2, 0.16, 0.5, 0.5)
	made.blob_length = 2.5
	return made


## A 1970s sci-fi paperback cover: a sky from tangerine through magenta to
## purple, purple mountains, orange sand, turquoise rock in bands and mesa
## tops, purple shade and a tangerine haze. Bold even outlines, no grain or
## hatching, soft airbrushed drift across the sand.
static func paperback() -> Palette:
	var made := Palette.new()
	made.title = "Retro sci-fi paperback"
	# Lime and azure: orange would sink into the sand.
	made.team_colours = [Color("a0ff40"), Color("2f6bff")]
	made.zenith = Color(0.26, 0.1, 0.42)
	made.horizon = Color(1.0, 0.62, 0.28)
	made.sky_middle = Color(0.92, 0.24, 0.52, 1.0)
	made.sky_middle_height = 0.5
	made.sky_ground = Color(0.7, 0.4, 0.4)
	made.far_range = Color(0.52, 0.26, 0.6, 1.0)
	made.far_range_height = 0.3
	made.near_range = Color(0.34, 0.16, 0.44, 1.0)
	made.near_range_height = 0.17
	made.sun_direction = Vector3(-0.5, 0.62, 0.6)
	made.lit_edge = 0.6
	made.mid_edge = 0.2
	made.sun_colour = Color(1.0, 0.9, 0.72)
	made.ambient = Color(0.62, 0.42, 0.72)
	made.ambient_energy = 0.45
	made.shade_mid = 0.55
	made.shade_dark = 0.32
	made.shade_colour = Color(0.42, 0.18, 0.64, 0.62)
	made.fog_colour = Color(1.0, 0.6, 0.4)
	made.fog_density = 0.002
	made.ink = Color(0.14, 0.04, 0.18)
	made.paper = Color(1.0, 1.0, 1.0)
	made.grit = 0.0
	made.hatching = false
	made.line_width = 1.4
	made.line_brush = 0.0
	made.grass = Color(1.0, 0.72, 0.5)
	made.grass_dark = Color(0.98, 0.62, 0.46)
	made.patch_colour = Color(0.3, 0.74, 0.66)
	made.patch_amount = 0.14
	made.patch_size = 5.0
	made.dirt = Color(0.92, 0.5, 0.42)
	made.rock = Color(0.16, 0.66, 0.66)
	made.rock_alt = Color(0.1, 0.5, 0.58)
	made.strata = 2.0
	made.low = Color(1.0, 0.8, 0.54)
	made.high = Color(0.14, 0.7, 0.7)
	made.variation_colour = Color(1.0, 0.72, 0.9)
	made.variation = 0.45
	made.variation_size = 20.0
	made.structure = Color(0.86, 0.84, 0.94)
	made.boulder = Color(0.2, 0.62, 0.64)
	made.saturation = 1.0
	made.team_white_light = 0.4
	made.blob_colour = Color(0.3, 0.1, 0.45, 0.55)
	made.blob_length = 2.0
	return made


## Lush and painterly: rich greens with purple and yellow wildflowers, warm
## yellow drift and brown and grey rock, a blue sky with big puffy clouds and
## blue hills, warm afternoon sun and blue-green shade. Soft grain, no
## hatching, crisp outlines on characters.
static func meadow() -> Palette:
	var made := Palette.new()
	made.title = "Lush meadow"
	made.zenith = Color(0.18, 0.42, 0.85)
	made.horizon = Color(0.74, 0.88, 0.98)
	made.sky_ground = Color(0.4, 0.6, 0.4)
	made.cloud_amount = 0.5
	made.cloud_colour = Color(1.0, 1.0, 0.96)
	made.cloud_shade = Color(0.68, 0.74, 0.9)
	made.cloud_scale = 1.8
	made.far_range = Color(0.52, 0.62, 0.84, 1.0)
	made.far_range_height = 0.18
	made.near_range = Color(0.34, 0.56, 0.52, 1.0)
	made.near_range_height = 0.11
	made.sun_direction = Vector3(-0.6, 0.66, 0.44)
	made.lit_edge = 0.55
	made.mid_edge = 0.18
	made.sun_colour = Color(1.0, 0.88, 0.66)
	made.ambient = Color(0.52, 0.62, 0.78)
	made.ambient_energy = 0.45
	made.shade_mid = 0.52
	made.shade_dark = 0.3
	made.shade_colour = Color(0.18, 0.36, 0.56, 0.42)
	made.fog_colour = Color(0.72, 0.84, 0.96)
	made.fog_density = 0.0024
	made.ink = Color(0.06, 0.1, 0.08)
	made.paper = Color(1.0, 0.99, 0.95)
	made.grit = 0.03
	made.hatching = false
	made.line_brush = 0.2
	made.grass = Color(0.3, 0.62, 0.22)
	made.grass_dark = Color(0.2, 0.5, 0.26)
	made.patch_colour = Color(0.78, 0.52, 0.86)
	made.patch_amount = 0.16
	made.patch_size = 1.2
	made.patch_alt = Color(1.0, 0.95, 0.75)
	made.patch_alt_amount = 0.16
	made.dirt = Color(0.66, 0.5, 0.32)
	made.rock = Color(0.62, 0.62, 0.66)
	made.rock_alt = Color(0.72, 0.62, 0.5)
	made.strata = 1.5
	made.low = Color(0.24, 0.52, 0.34)
	made.high = Color(0.42, 0.7, 0.3)
	made.variation_colour = Color(1.5, 1.2, 0.5)
	made.variation = 0.6
	made.variation_size = 12.0
	made.structure = Color(0.86, 0.84, 0.78)
	made.boulder = Color(0.6, 0.6, 0.64)
	made.saturation = 0.95
	made.team_white_light = 0.3
	made.blob_colour = Color(0.1, 0.22, 0.36, 0.5)
	made.blob_length = 2.0
	return made


## A flat travel poster: one flat colour for each kind of thing, green
## grass, cream sand, plum rock, a pale sky with a teal mountain range and
## off-white base metal, with one blue-violet shade and hard edges. No
## gradients, fog, grain or hatching.
static func travel_poster() -> Palette:
	var made := Palette.new()
	made.title = "Flat travel poster"
	made.zenith = Color(0.62, 0.86, 0.88)
	made.horizon = Color(0.62, 0.86, 0.88)
	made.sky_ground = Color(0.62, 0.86, 0.88)
	made.far_range = Color(0.3, 0.56, 0.64, 1.0)
	made.far_range_height = 0.2
	made.sun_direction = Vector3(-0.6, 0.7, 0.4)
	made.lit_edge = 0.35
	made.mid_edge = 0.35
	made.deep_edge = -1.0
	made.sun_colour = Color(1.0, 1.0, 1.0)
	made.ambient = Color(1.0, 1.0, 1.0)
	made.ambient_energy = 0.0
	made.shade_mid = 0.62
	made.shade_dark = 0.62
	made.shade_colour = Color(0.24, 0.26, 0.6, 0.45)
	made.fog_density = 0.0
	made.ink = Color(0.1, 0.1, 0.14)
	made.paper = Color(1.0, 1.0, 1.0)
	made.grit = 0.0
	made.hatching = false
	made.line_width = 1.2
	made.line_brush = 0.0
	made.grass = Color(0.36, 0.64, 0.4)
	made.grass_dark = Color(0.36, 0.64, 0.4)
	made.dirt = Color(0.98, 0.86, 0.6)
	made.rock = Color(0.6, 0.34, 0.5)
	made.rock_alt = Color(0.6, 0.34, 0.5)
	made.low = Color(0.98, 0.86, 0.6)
	made.high = Color(0.36, 0.64, 0.4)
	made.structure = Color(0.94, 0.92, 0.86)
	made.boulder = Color(0.6, 0.34, 0.5)
	made.saturation = 1.0
	made.blob_colour = Color(0.2, 0.2, 0.45, 0.45)
	made.blob_length = 1.5
	return made


## Neon frontier at dusk: a low sun ahead behind the hills, a pink, magenta
## and indigo sky with dark purple ranges, rust ground and plum rock in
## violet shade, violet hatching, and cyan light strips on bases. Jets,
## blasts and energy light what's near them (Cel.set_glow) in cyan and
## magenta.
static func neon_frontier() -> Palette:
	var made := Palette.new()
	made.title = "Neon frontier"
	made.zenith = Color(0.1, 0.06, 0.28)
	made.horizon = Color(1.0, 0.46, 0.5)
	made.sky_middle = Color(0.6, 0.18, 0.58, 1.0)
	made.sky_middle_height = 0.22
	made.sky_ground = Color(0.4, 0.2, 0.3)
	made.cloud_amount = 0.3
	made.cloud_colour = Color(1.0, 0.6, 0.55)
	made.cloud_shade = Color(0.46, 0.22, 0.52)
	made.cloud_scale = 2.0
	made.far_range = Color(0.36, 0.16, 0.44, 1.0)
	made.far_range_height = 0.2
	made.near_range = Color(0.22, 0.1, 0.32, 1.0)
	made.near_range_height = 0.12
	made.sun_direction = Vector3(-0.75, 0.3, 0.55)
	made.lit_edge = 0.2
	made.mid_edge = -0.05
	made.deep_edge = -0.4
	made.sun_colour = Color(1.0, 0.62, 0.42)
	made.ambient = Color(0.46, 0.34, 0.7)
	made.ambient_energy = 0.55
	made.shade_mid = 0.5
	made.shade_dark = 0.28
	made.shade_colour = Color(0.36, 0.24, 0.8, 0.6)
	made.hatch_colour = Color(0.24, 0.1, 0.44, 0.8)
	made.fog_colour = Color(0.78, 0.36, 0.52)
	made.fog_density = 0.0035
	made.ink = Color(0.07, 0.03, 0.12)
	made.paper = Color(1.0, 1.0, 1.0)
	made.grit = 0.0
	made.line_brush = 0.05
	made.grass = Color(0.64, 0.34, 0.28)
	made.grass_dark = Color(0.54, 0.28, 0.3)
	made.patch_colour = Color(0.52, 0.36, 0.48)
	made.patch_amount = 0.15
	made.dirt = Color(0.6, 0.32, 0.32)
	made.rock = Color(0.4, 0.26, 0.38)
	made.rock_alt = Color(0.48, 0.28, 0.32)
	made.strata = 3.0
	made.low = Color(0.72, 0.42, 0.32)
	made.high = Color(0.6, 0.38, 0.4)
	made.structure = Color(0.56, 0.56, 0.66)
	made.boulder = Color(0.42, 0.28, 0.4)
	made.tech_glow = Color(0.3, 1.0, 1.0, 1.0)
	made.saturation = 0.95
	made.team_white_light = 0.6
	made.blob_colour = Color(0.14, 0.06, 0.3, 0.6)
	made.blob_length = 4.0
	return made
