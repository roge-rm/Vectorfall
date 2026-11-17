class_name FirstPersonCamera
extends Camera3D

## Sits at a soldier's eyes each frame. It only reads the soldier.

var soldier: Soldier


func _init() -> void:
	name = "FirstPersonCamera"
	fov = 75.0
	near = 0.05
	far = 600.0
	cull_mask = 0xFFFFF & ~Soldier.OWN_BODY_LAYER


func _process(_delta: float) -> void:
	if soldier != null:
		global_transform = soldier.eye_transform()
