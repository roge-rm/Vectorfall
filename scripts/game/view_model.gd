class_name ViewModel
extends Node3D

## The weapon in your hands in first person, a child of the camera. It kicks
## back on each shot, bobs as you run, spins the chaingun's barrels and drops
## out of view while switching. It only reads the soldier.

## Where the gun sits in camera space, how far it turns in towards the middle
## of the screen and tips its muzzle up, in radians.
const REST := Vector3(0.25, -0.22, -0.42)
const TURN := 0.3
const TIP := 0.1
const SCALE := 0.56

var soldier: Soldier
var _guns: Array[Node3D] = []
var _shots := 0
var _kick := 0.0
var _bob := 0.0
var _shown := -1
var _lower := 0.0


func _init() -> void:
	name = "ViewModel"
	for slot in Weapon.all.size():
		var gun := WeaponModels.build(slot, true)
		gun.scale = Vector3.ONE * SCALE
		gun.visible = false
		add_child(gun)
		_guns.append(gun)


func set_team_colour(colour: Color) -> void:
	for gun in _guns:
		for view in gun.find_children("*", "GeometryInstance3D", true, false):
			Cel.set_team(view as GeometryInstance3D, colour)


func _process(delta: float) -> void:
	if soldier == null:
		return
	visible = not soldier.dead
	if soldier.shots != _shots:
		_shots = soldier.shots
		_kick = 1.0
	_kick = move_toward(_kick, 0.0, delta * 8.0)
	if _shown != soldier.weapon:
		_lower = 1.0
		_shown = soldier.weapon
	_lower = move_toward(_lower, 0.0, delta / Soldier.SWITCH_TIME)
	var pace := soldier.horizontal_speed() / soldier.tuning.run_speed if soldier.grounded and not soldier.skiing else 0.0
	_bob += delta * TAU * 1.6 * minf(pace, 1.0)
	var sway := Vector3(sin(_bob) * 0.012, -absf(cos(_bob)) * 0.01, 0.0) * minf(pace, 1.0)
	position = REST + sway + Vector3(0.0, -0.25 * _lower, 0.06 * _kick)
	rotation = Vector3(TIP + 0.12 * _kick, TURN, 0.0)
	for slot in _guns.size():
		_guns[slot].visible = slot == soldier.weapon
	var spinner := _guns[Weapon.CHAINGUN].get_node("Spinner") as Node3D
	spinner.rotation.z += soldier.spin * delta * 40.0
