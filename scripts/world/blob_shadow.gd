class_name BlobShadow
extends MeshInstance3D

## The round shadow under a soldier, laid on whatever is below it. It's only
## for looks and isn't part of the match state,
## so it's placed each frame, not each physics tick.

const SIZE := 1.4
## Height above the ground where the shadow has faded out.
const FADE_HEIGHT := 25.0
## Past this many metres from the camera, a shadow casts its ray only every
## FAR_EVERY frames.
const NEAR := 60.0
const FAR_EVERY := 4

const SHADER := preload("res://shaders/blob_shadow.gdshader")
static var _material: ShaderMaterial

var _frame := 0
## Height it last lay at, or INF when nothing was below.
var _ground_y := INF


func _init() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := PlaneMesh.new()
	quad.size = Vector2(SIZE, SIZE)
	mesh = quad
	material_override = _shared()


static func _shared() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material


## Takes the palette's shadow colour, and stretches every blob away from the
## sun by its blob_length.
static func set_palette(palette: Palette) -> void:
	var away := -Vector2(palette.sun_direction.x, palette.sun_direction.z)
	_shared().set_shader_parameter("colour", palette.blob_colour)
	_shared().set_shader_parameter("away", away.normalized() if away.length() > 0.01 else Vector2.ZERO)
	_shared().set_shader_parameter("stretch", maxf(palette.blob_length, 1.0) - 1.0)


func _ready() -> void:
	# Nothing to see without a screen, so no rays either.
	if DisplayServer.get_name() == "headless":
		visible = false
		set_process(false)
		return
	_frame = get_instance_id() % FAR_EVERY


func _process(_delta: float) -> void:
	var body := get_parent() as CollisionObject3D
	if body == null:
		return
	_frame += 1
	var camera := get_viewport().get_camera_3d()
	var far := camera != null and camera.global_position.distance_squared_to(body.global_position) > NEAR * NEAR
	if far and _frame % FAR_EVERY != 0 and _ground_y != INF:
		# Between rays, slides along with the body at the last ground height.
		var at := body.global_position
		global_position = Vector3(at.x, _ground_y, at.z)
		return
	follow(body)


## Casts down from the body and lies flat on what it finds.
func follow(body: CollisionObject3D) -> void:
	if not body.is_inside_tree():
		return
	var from := body.global_position + Vector3.UP * 0.2
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * FADE_HEIGHT, 0xFFFFFFFF, [body.get_rid()])
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		visible = false
		_ground_y = INF
		return
	visible = true
	var normal: Vector3 = hit.normal
	var basis := Basis(Quaternion(Vector3.UP, normal))
	global_transform = Transform3D(basis, hit.position + normal * 0.03)
	_ground_y = global_position.y
	set_instance_shader_parameter("fade", 1.0 - clampf((from.y - hit.position.y) / FADE_HEIGHT, 0.0, 1.0))
