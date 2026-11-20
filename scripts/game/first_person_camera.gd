class_name FirstPersonCamera
extends Camera3D

## Sits at a soldier's eyes each frame, with the weapon in view. While the
## soldier is dead it pulls back and looks down at the body. It only reads
## the soldier.

var soldier: Soldier:
	set(value):
		soldier = value
		view_model.soldier = value
var view_model := ViewModel.new()


func _init() -> void:
	name = "FirstPersonCamera"
	fov = 75.0
	near = 0.05
	far = 700.0
	cull_mask = 0xFFFFF & ~Soldier.OWN_BODY_LAYER
	add_child(view_model)


func _process(_delta: float) -> void:
	if soldier == null:
		return
	if soldier.dead:
		cull_mask = 0xFFFFF
		var back := Basis(Vector3.UP, soldier.yaw) * Vector3(0.0, 3.0, 4.0)
		var at := soldier.global_position + back
		look_at_from_position(at, soldier.global_position + Vector3.UP * 0.4)
	else:
		cull_mask = 0xFFFFF & ~Soldier.OWN_BODY_LAYER
		var eye := soldier.eye_transform()
		var hull: Vehicle = soldier.game.fleet.hulls.get(soldier.vehicle_id) if soldier.game != null else null
		if hull == null or hull.uses_personal_weapon(soldier.vehicle_seat):
			global_transform = eye
		else:
			var zoom := Vehicle.SIZE[hull.kind].z * 1.16
			var start := hull.global_position + Vector3.UP * Vehicle.SIZE[hull.kind].y * 0.72
			var flat := Basis(Vector3.UP, soldier.yaw)
			var at := start + flat * Vector3(0, 2.1 + zoom * 0.22, zoom + 2.2)
			var hit := soldier.game.world_ray(start, at, Match.WORLD_LAYER)
			if not hit.is_empty():
				at = (hit.position as Vector3).move_toward(start, 0.2)
			look_at_from_position(at, eye.origin - eye.basis.z * 110.0)
