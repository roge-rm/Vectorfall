class_name Atmosphere
extends Node3D

## The sun, ink sky, ambient light and distance fog for a map, from its
## palette. It also puts the palette on every ink material.

const SKY := preload("res://shaders/ink_sky.gdshader")

var palette: Palette
var sun: DirectionalLight3D
var environment: Environment
var sky_material: ShaderMaterial


func _init(from: Palette = null) -> void:
	name = "Atmosphere"
	palette = from if from != null else Palette.desert()
	sun = DirectionalLight3D.new()
	sun.light_energy = 1.0
	sun.shadow_enabled = false
	add_child(sun)
	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY
	sky_material.set_shader_parameter("soft_noise", Cel.soft_noise())
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_sky_affect = 0.0
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	apply(palette)


## Puts a palette on the sky, sun, fog and every ink material.
func apply(value: Palette) -> void:
	palette = value
	var direction := palette.sun_direction.normalized()
	sun.basis = Basis.looking_at(-direction, Vector3.UP if absf(direction.y) < 0.99 else Vector3.BACK)
	sun.light_color = palette.sun_colour
	sky_material.set_shader_parameter("zenith", palette.zenith)
	sky_material.set_shader_parameter("horizon", palette.horizon)
	sky_material.set_shader_parameter("ground", palette.sky_ground)
	sky_material.set_shader_parameter("sun_colour", palette.sun_colour)
	sky_material.set_shader_parameter("ink", palette.ink)
	sky_material.set_shader_parameter("paper", palette.paper)
	sky_material.set_shader_parameter("middle", palette.sky_middle)
	sky_material.set_shader_parameter("middle_height", palette.sky_middle_height)
	sky_material.set_shader_parameter("bands", palette.sky_bands)
	for key: String in ["cloud_amount", "cloud_colour", "cloud_shade", "cloud_scale", "far_range", "far_range_height", "near_range", "near_range_height"]:
		sky_material.set_shader_parameter(key, palette.get(key))
	environment.ambient_light_color = palette.ambient
	environment.ambient_light_energy = palette.ambient_energy
	environment.fog_light_color = palette.fog_colour
	environment.fog_density = palette.fog_density
	Palette.teams = palette.team_colours.duplicate()
	Cel.set_palette(palette)
	BlobShadow.set_palette(palette)


func _process(_delta: float) -> void:
	# Keeps the sky's grain the same size at any window size.
	var height := get_viewport().get_visible_rect().size.y
	sky_material.set_shader_parameter("screen_height", height)
