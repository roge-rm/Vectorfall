class_name Cel
extends RefCounted

## Makes the cel shaded materials, shared by colour, and turns their outlines
## on and off together.

const CEL := preload("res://shaders/cel.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")

static var _materials: Dictionary[String, ShaderMaterial] = {}
static var _meshes: Dictionary[String, ArrayMesh] = {}
static var _glows: Dictionary[String, StandardMaterial3D] = {}
static var _outline: ShaderMaterial
static var _near_outline: ShaderMaterial
static var _outlines_on := true


## A cel material in this colour. team_amount is how much the instance's team
## colour shows through. outlined is false for things like the ground that
## shouldn't get the outline pass. near is for things right in front of the
## camera, like the gun in your hands, which get a thinner outline.
static func material(colour: Color, team_amount := 0.0, outlined := true, vertex_colour := false, near := false) -> ShaderMaterial:
	var key := "%s/%s/%s/%s/%s" % [colour.to_html(), team_amount, outlined, vertex_colour, near]
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
		made.set_meta("near", near)
		if _outlines_on:
			made.next_pass = _outline_for(made)
	_materials[key] = made
	return made


## Gives a mesh its team colour by swapping its cel materials for copies in
## that colour, shared by material and colour. A per-instance uniform would
## need a uniform slot per mesh, and GLES3 runs out with a few soldiers.
static func set_team(view: GeometryInstance3D, colour: Color) -> void:
	var override := view.material_override as ShaderMaterial
	if override != null and override.shader == CEL:
		view.material_override = _team_copy(override, colour)
	var mesh_view := view as MeshInstance3D
	if mesh_view == null or mesh_view.mesh == null:
		return
	for k in mesh_view.mesh.get_surface_count():
		var surface := mesh_view.get_surface_override_material(k) as ShaderMaterial
		if surface == null:
			surface = mesh_view.mesh.surface_get_material(k) as ShaderMaterial
		if surface != null and surface.shader == CEL:
			mesh_view.set_surface_override_material(k, _team_copy(surface, colour))


static func _team_copy(source: ShaderMaterial, colour: Color) -> ShaderMaterial:
	var base: ShaderMaterial = source.get_meta("team_base", source)
	if float(base.get_shader_parameter("team_amount")) <= 0.0:
		return base
	var key := "team/%d/%s" % [base.get_instance_id(), colour.to_html()]
	if _materials.has(key):
		return _materials[key]
	var made := base.duplicate() as ShaderMaterial
	made.set_shader_parameter("team_colour", colour)
	made.set_meta("team_base", base)
	_materials[key] = made
	return made


## The ground's material, which colours by steepness and a patch noise kept
## in the vertex colours.
static func ground_material() -> ShaderMaterial:
	var made := ShaderMaterial.new()
	made.shader = CEL
	made.set_shader_parameter("ground", true)
	made.set_shader_parameter("rim_amount", 0.0)
	return made


## A flat unshaded colour for things that glow, like flames and shots.
static func glow(colour: Color, vertex_colour := false) -> StandardMaterial3D:
	var key := "%s/%s" % [colour.to_html(), vertex_colour]
	if _glows.has(key):
		return _glows[key]
	var made := StandardMaterial3D.new()
	made.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	made.albedo_color = colour
	made.vertex_color_use_as_albedo = vertex_colour
	made.disable_fog = true
	if colour.a < 1.0:
		made.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glows[key] = made
	return made


## Shared box, cylinder and sphere meshes with outline normals, by size.
static func box(size: Vector3) -> ArrayMesh:
	var key := "box/%s" % size
	if not _meshes.has(key):
		var made := BoxMesh.new()
		made.size = size
		_meshes[key] = hull_mesh(made)
	return _meshes[key]


static func cylinder(top_radius: float, bottom_radius: float, height: float, sides := 8) -> ArrayMesh:
	var key := "cylinder/%s/%s/%s/%s" % [top_radius, bottom_radius, height, sides]
	if not _meshes.has(key):
		var made := CylinderMesh.new()
		made.top_radius = top_radius
		made.bottom_radius = bottom_radius
		made.height = height
		made.radial_segments = sides
		made.rings = 1
		_meshes[key] = hull_mesh(made)
	return _meshes[key]


static func sphere(radius: float, height: float, sides := 12) -> ArrayMesh:
	var key := "sphere/%s/%s/%s" % [radius, height, sides]
	if not _meshes.has(key):
		var made := SphereMesh.new()
		made.radius = radius
		made.height = height
		made.radial_segments = sides
		made.rings = maxi(sides / 2, 3)
		_meshes[key] = hull_mesh(made)
	return _meshes[key]


## A copy of a mesh with outline normals in CUSTOM0: at each corner, the sum
## of the different face normals meeting there, scaled so every face moves
## out by the full outline width. The hull stays closed at hard edges, where
## pushing along each face's own normal would leave gaps.
static func hull_mesh(source: Mesh) -> ArrayMesh:
	var made := ArrayMesh.new()
	for s in source.get_surface_count():
		var arrays := source.surface_get_arrays(s)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		# Each corner's different normals, by where the corner is.
		var faces: Dictionary[Vector3i, Array] = {}
		for k in points.size():
			var key := Vector3i((points[k] * 1000.0).round())
			if not faces.has(key):
				faces[key] = []
			var list: Array = faces[key]
			var n := normals[k]
			var known := false
			for other: Vector3 in list:
				if other.dot(n) > 0.999:
					known = true
					break
			if not known:
				list.append(n)
		var custom := PackedFloat32Array()
		custom.resize(points.size() * 4)
		for k in points.size():
			var list: Array = faces[Vector3i((points[k] * 1000.0).round())]
			var sum := Vector3.ZERO
			for n: Vector3 in list:
				sum += n
			var hull := sum.normalized() if sum.length() > 0.001 else normals[k]
			var least := 1.0
			for n: Vector3 in list:
				least = minf(least, hull.dot(n))
			hull *= 1.0 / maxf(least, 0.4)
			custom[k * 4] = hull.x
			custom[k * 4 + 1] = hull.y
			custom[k * 4 + 2] = hull.z
			custom[k * 4 + 3] = 1.0
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		var flags := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		made.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return made


static func outline() -> ShaderMaterial:
	if _outline == null:
		_outline = ShaderMaterial.new()
		_outline.shader = OUTLINE
	return _outline


## The outline pass for things close to the camera: no lower limit on
## distance, so it stays thin.
static func near_outline() -> ShaderMaterial:
	if _near_outline == null:
		_near_outline = ShaderMaterial.new()
		_near_outline.shader = OUTLINE
		_near_outline.set_shader_parameter("min_distance", 0.0)
		_near_outline.set_shader_parameter("width", 0.004)
	return _near_outline


static func _outline_for(made: ShaderMaterial) -> ShaderMaterial:
	return near_outline() if made.get_meta("near", false) else outline()


static func set_outlines(on: bool) -> void:
	_outlines_on = on
	for made: ShaderMaterial in _materials.values():
		if made.has_meta("outlined"):
			made.next_pass = _outline_for(made) if on else null


static func outlines_on() -> bool:
	return _outlines_on
