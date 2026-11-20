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
## Gun models for the soldier's carried weapons, by weapon slot, made again
## when they change.
var _guns: Dictionary[int, Node3D] = {}
var _built: Array[int] = []
var _team_colour := Color.WHITE
var _shots := 0
var _kick := 0.0
var _bob := 0.0
var _shown := -1
var _lower := 0.0


func _init() -> void:
	name = "ViewModel"


func set_team_colour(colour: Color) -> void:
	_team_colour = colour
	for slot: int in _guns:
		_colour(_guns[slot])


func _colour(gun: Node3D) -> void:
	for view in gun.find_children("*", "GeometryInstance3D", true, false):
		Cel.set_team(view as GeometryInstance3D, _team_colour)


## Builds models for the carried weapons and drops the rest.
func _build_guns() -> void:
	_built = soldier.weapons.duplicate()
	for slot: int in _guns.keys():
		if not _built.has(slot):
			_guns[slot].queue_free()
			_guns.erase(slot)
	for slot in _built:
		if _guns.has(slot):
			continue
		var gun := WeaponModels.build(slot, true)
		gun.scale = Vector3.ONE * SCALE
		gun.visible = false
		add_child(gun)
		_colour(gun)
		_guns[slot] = gun


func _process(delta: float) -> void:
	if soldier == null:
		return
	var hull: Vehicle = soldier.game.fleet.hulls.get(soldier.vehicle_id) if soldier.game != null else null
	visible = not soldier.dead and (hull == null or hull.uses_personal_weapon(soldier.vehicle_seat))
	if soldier.weapons != _built:
		_build_guns()
	if soldier.shots != _shots:
		_shots = soldier.shots
		_kick = 1.0
	_kick = move_toward(_kick, 0.0, delta * 8.0)
	if _shown != soldier.weapon_slot():
		_lower = 1.0
		_shown = soldier.weapon_slot()
	_lower = move_toward(_lower, 0.0, delta / Soldier.SWITCH_TIME)
	var pace := soldier.horizontal_speed() / soldier.tuning.run_speed if soldier.grounded and not soldier.skiing else 0.0
	_bob += delta * TAU * 1.6 * minf(pace, 1.0)
	var sway := Vector3(sin(_bob) * 0.012, -absf(cos(_bob)) * 0.01, 0.0) * minf(pace, 1.0)
	position = REST + sway + Vector3(0.0, -0.25 * _lower, 0.06 * _kick)
	rotation = Vector3(TIP + 0.12 * _kick, TURN, 0.0)
	for slot: int in _guns:
		_guns[slot].visible = slot == soldier.weapon_slot()
	if _guns.has(Weapon.CHAINGUN):
		var spinner := _guns[Weapon.CHAINGUN].get_node("Spinner") as Node3D
		spinner.rotation.z += soldier.spin * delta * 40.0
