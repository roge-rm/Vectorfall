class_name Cel
extends RefCounted

## Makes the cel shaded materials, shared by colour, and turns their outlines
## on and off together.

const CEL := preload("res://shaders/cel.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")

static var _materials: Dictionary[String, ShaderMaterial] = {}
static var _outline: ShaderMaterial
static var _outlines_on := true


## A cel material in this colour. team_amount is how much the instance's team
## colour shows through. outlined is false for things like the ground that
## shouldn't get the outline pass.
static func material(colour: Color, team_amount := 0.0, outlined := true, vertex_colour := false) -> ShaderMaterial:
	var key := "%s/%s/%s/%s" % [colour.to_html(), team_amount, outlined, vertex_colour]
	if _materials.has(key):
		return _materials[key]
	var made := ShaderMaterial.new()
	made.shader = CEL
	made.set_shader_parameter("albedo", colour)
	made.set_shader_parameter("team_amount", team_amount)
	made.set_shader_parameter("use_vertex_colour", vertex_colour)
	# Rim light only on team coloured things: on big flat ground it shows as a
	# bright band towards the horizon.
	made.set_shader_parameter("rim_amount", 0.35 if team_amount > 0.0 else 0.0)
	if outlined:
		made.set_meta("outlined", true)
		if _outlines_on:
			made.next_pass = outline()
	_materials[key] = made
	return made


static func outline() -> ShaderMaterial:
	if _outline == null:
		_outline = ShaderMaterial.new()
		_outline.shader = OUTLINE
	return _outline


static func set_outlines(on: bool) -> void:
	_outlines_on = on
	for made: ShaderMaterial in _materials.values():
		if made.has_meta("outlined"):
			made.next_pass = outline() if on else null


static func outlines_on() -> bool:
	return _outlines_on
