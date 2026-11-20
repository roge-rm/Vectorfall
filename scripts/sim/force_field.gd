class_name ForceField
extends StaticBody3D

## A force field over a way into a team's generator room: a box on its team's
## field layer (Match.field_layer()). Other teams' soldiers and dropped flags
## collide with that layer and its own team's don't, so teammates pass and
## enemies are blocked. Shots, blasts and mines go through. It's on while its team has power; off, it's on no layer and
## nothing collides with it. A see-through sheet in the team's colour, faint
## when off. Its origin is the box's middle. The match changes it only on
## physics ticks, and its look is made in _ready().

## The sheet's see-through amount, on and off.
const ON_ALPHA := 0.6
const OFF_ALPHA := 0.08

var entity_id := 0
var team := 0
var size := Vector3(3.0, 1.0, 3.0)
var on := true
var _sheet: MeshInstance3D


func _ready() -> void:
	name = "ForceField%d" % entity_id
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)
	_sheet = MeshInstance3D.new()
	_sheet.name = "Sheet"
	_sheet.mesh = Cel.box(Vector3(size.x, 0.06, size.z))
	_sheet.position = Vector3.UP * (size.y * 0.5 - 0.05)
	_sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sheet)
	set_on(on)


## Turns it on or off: its layer and how it looks.
func set_on(value: bool) -> void:
	on = value
	collision_layer = Match.field_layer(team) if on else 0
	if _sheet != null:
		var colour := Palette.team(team)
		colour.a = ON_ALPHA if on else OFF_ALPHA
		_sheet.material_override = Cel.glow(colour)


## True for a point on or in its box, give or take margin metres.
func touches(point: Vector3, margin := 0.15) -> bool:
	var d := (point - position).abs()
	var half := size * 0.5 + Vector3.ONE * margin
	return d.x <= half.x and d.y <= half.y and d.z <= half.z


func get_state() -> Dictionary:
	return {
		"kind": "field",
		"id": entity_id,
		"team": team,
		"position": position,
		"size": size,
		"on": on,
	}


func set_state(state: Dictionary) -> void:
	position = state.position
	size = state.size
	if on != state.on:
		set_on(state.on)
