class_name Atmosphere
extends Node3D

## The sun, gradient sky, ambient light and distance fog for a map.

const SKY := preload("res://shaders/sky.gdshader")
const HORIZON := Color(0.72, 0.82, 0.9)

var sun: DirectionalLight3D
var environment: Environment


func _init() -> void:
	name = "Atmosphere"
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-35.0), 0.0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = false
	add_child(sun)

	var sky_material := ShaderMaterial.new()
	sky_material.shader = SKY
	sky_material.set_shader_parameter("horizon", HORIZON)
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	# Flat ambient keeps the dark band from going black.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.6, 0.72)
	environment.ambient_light_energy = 0.55
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_color = HORIZON
	environment.fog_density = 0.0012
	environment.fog_sky_affect = 0.0
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
