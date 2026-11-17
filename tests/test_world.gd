class_name TestWorld
extends RefCounted

## Helpers for the headless tests: flat ground, scripted commands and checks.


## A command source that gives whatever command is set on it.
class Scripted:
	extends CommandSource
	var command := PlayerCommand.new()

	func make_command(_delta: float) -> PlayerCommand:
		return command.duplicate()


## A big flat floor with its top at y = 0.
static func flat_ground(parent: Node) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1000.0, 2.0, 1000.0)
	shape.shape = box
	shape.position.y = -1.0
	body.add_child(shape)
	parent.add_child(body)
	return body


## A slope going down towards +x at the given angle, its top edge at x = 0,
## y = 0.
static func slope(parent: Node, degrees: float, length := 200.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length, 2.0, 200.0)
	shape.shape = box
	body.rotation.z = -deg_to_rad(degrees)
	shape.position = Vector3(length * 0.5, -1.0, 0.0)
	body.add_child(shape)
	parent.add_child(body)
	return body


## A flat square of triangle mesh with its top at y = 0, centred on the
## origin, like the map's terrain.
static func mesh_ground(parent: Node, size: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var h := size * 0.5
	var mesh := ConcavePolygonShape3D.new()
	mesh.set_faces(PackedVector3Array([
		Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(-h, 0, h),
		Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h),
	]))
	shape.shape = mesh
	body.add_child(shape)
	parent.add_child(body)
	return body


class Checks:
	var failures := 0
	var passes := 0

	func check(ok: bool, what: String) -> void:
		print(("  ok    " if ok else "  FAIL  ") + what)
		if ok:
			passes += 1
		else:
			failures += 1

	func finish(tree: SceneTree) -> void:
		print("%d passed, %d failed" % [passes, failures])
		tree.quit(1 if failures > 0 else 0)
