class_name Palette
extends Resource

## A map's colours and light: sky, sun, ambient, fog, ink and paper, the
## ground's colours by slope and height, and the colour of built things. The
## map script picks one and Atmosphere puts it on the scene. All of them keep
## the world's colours below the team colours, which are the strongest.

@export var title := ""
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
