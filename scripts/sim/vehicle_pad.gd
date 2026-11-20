class_name VehiclePad
extends Node3D

const RESPAWN := 20.0

var entity_id := 0
var team := 0
var kind := Vehicle.Kind.BIKE
var yaw := 0.0
var hull_id := 0
var remaining := 0.0
var lamp: MeshInstance3D
var _on := true


func _ready() -> void:
	name = "VehiclePad%d" % entity_id
	rotation.y = yaw
	lamp = VehicleLook.pad(self, kind, team)


func _process(_delta: float) -> void:
	var game := get_parent() as Match
	var powered := game.powered(team) and hull_id != 0
	if powered != _on:
		_on = powered
		lamp.material_override = Cel.glow(Palette.team(team)) if powered else Cel.material(Color(0.24, 0.21, 0.27))


func get_state() -> Dictionary:
	return {
		"id": entity_id, "team": team, "kind": kind, "position": position,
		"yaw": yaw, "hull": hull_id, "remaining": remaining,
	}


func set_state(state: Dictionary) -> void:
	position = state.position
	rotation.y = state.yaw
	yaw = state.yaw
	hull_id = state.hull
	remaining = state.remaining
