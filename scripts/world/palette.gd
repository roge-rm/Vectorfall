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
