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
		global_transform = soldier.eye_transform()
