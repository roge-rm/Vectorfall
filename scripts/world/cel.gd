class_name Cel
extends RefCounted

## Makes the ink materials, shared by colour, and turns their outlines and
## hatching on and off together. The palette's light, ink and paper go on
## every material through set_palette().

const CEL := preload("res://shaders/ink.gdshader")
const OUTLINE := preload("res://shaders/ink_outline.gdshader")

static var _materials: Dictionary[String, ShaderMaterial] = {}
## Ground materials, held weakly so a freed map's go away.
static var _grounds: Array[WeakRef] = []
static var _meshes: Dictionary[String, ArrayMesh] = {}
static var _glows: Dictionary[String, StandardMaterial3D] = {}
static var _outline: ShaderMaterial
static var _near_outline: ShaderMaterial
static var _figure_outline: ShaderMaterial
static var _effect_outline: ShaderMaterial
static var _outlines_on := true
static var _grain: ImageTexture
static var _soft: ImageTexture
static var _hatching_setting := true
static var _palette_hatching := true
## Outline widths before the palette's line_width, by outline material.
static var _widths: Dictionary[ShaderMaterial, float] = {}
static var _glow_points := Projection(Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO)
static var _glow_colours := Projection(Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO)
## Uniforms every ink material gets, from the palette and the settings.
static var _shared: Dictionary[String, Variant] = {}
## Uniforms only the ground gets.
static var _ground_shared: Dictionary[String, Variant] = {}


## An ink material in this colour. team_amount is how much the team colour
## shows through. outlined is false for things like the ground that shouldn't
## get the outline pass. With vertex_colour the albedo multiplies the vertex
## colours and the vertex alpha scales team_amount. near is for things right
## in front of the camera, like the gun in your hands, which get a thinner
## outline. figure is for soldiers, what they carry and flags, whose outline
## thins sooner with distance so it doesn't swallow them. small is for
## things a hand's width across, like mines and hand grenades, which get the
## effects' thin outline with no wobble.
static func material(colour: Color, team_amount := 0.0, outlined := true, vertex_colour := false, near := false, figure := false, small := false) -> ShaderMaterial:
	var key := "%s/%s/%s/%s/%s/%s/%s" % [colour.to_html(), team_amount, outlined, vertex_colour, near, figure, small]
	if _materials.has(key):
		return _materials[key]
	var made := ShaderMaterial.new()
	made.shader = CEL
	made.set_shader_parameter("albedo", colour)
	made.set_shader_parameter("team_amount", team_amount)
	made.set_shader_parameter("use_vertex_colour", vertex_colour)
	# Rim light only on team coloured things: on big flat ground it shows as a
	# bright band towards the horizon.
	made.set_shader_parameter("rim_amount", 0.3 if team_amount > 0.0 else 0.0)
	made.set_shader_parameter("camera_light", near)
	made.set_shader_parameter("paper_grain", paper_grain())
	_share(made, _shared)
	if outlined:
		made.set_meta("outlined", true)
		made.set_meta("near", near)
		made.set_meta("figure", figure)
		made.set_meta("small", small)
		if _outlines_on:
			made.next_pass = _outline_for(made)
	_materials[key] = made
	return made


## A material in a team's colour at full strength, for flags and team
## markings on bases. The palette holds the rest of the world below it.
static func team_material(colour: Color) -> ShaderMaterial:
	var key := "team_material/%s" % colour.to_html()
	if _materials.has(key):
		return _materials[key]
	var made := material(colour, 1.0).duplicate() as ShaderMaterial
	made.set_shader_parameter("team_colour", colour)
	made.set_meta("outlined", true)
	made.set_meta("near", false)
	made.next_pass = _outline_for(made) if _outlines_on else null
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


## The ground's material, which colours by steepness, height and a patch
## noise kept in the vertex colours, from the palette.
static func ground_material() -> ShaderMaterial:
	var made := ShaderMaterial.new()
	made.shader = CEL
	made.set_shader_parameter("ground", true)
	made.set_shader_parameter("rim_amount", 0.0)
	made.set_shader_parameter("paper_grain", paper_grain())
	made.set_shader_parameter("soft_noise", soft_noise())
	_share(made, _shared)
	_share(made, _ground_shared)
	_grounds = _grounds.filter(func(held: WeakRef) -> bool: return held.get_ref() != null)
	_grounds.append(weakref(made))
	return made


## A flat unshaded colour for things that glow, like flames and shots, with
## an ink line unless it's see-through.
static func glow(colour: Color, vertex_colour := false) -> StandardMaterial3D:
	var key := "%s/%s" % [colour.to_html(), vertex_colour]
	if _glows.has(key):
		return _glows[key]
	var made := StandardMaterial3D.new()
	made.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	made.albedo_color = colour
	made.vertex_color_use_as_albedo = vertex_colour
	made.vertex_color_is_srgb = true
	made.disable_fog = true
	if colour.a < 1.0:
		made.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	elif _outlines_on:
		made.next_pass = effect_outline()
	_glows[key] = made
	return made


## Puts a palette's light, ink, paper and ground colours on every ink
## material, made now or later.
static func set_palette(palette: Palette) -> void:
	var direction := palette.sun_direction.normalized()
	for key: String in ["sun_colour", "ambient", "ambient_energy", "ink", "paper", "saturation", "grit", "mid_tint", "dark_tint", "hatch_colour", "highlight", "highlight_edge", "team_white_light", "lit_edge", "mid_edge", "deep_edge", "shade_colour"]:
		_shared[key] = palette.get(key)
	_shared["shade_mid"] = palette.shade_mid
	_shared["shade_dark"] = palette.shade_dark
	_shared["sun_direction"] = direction
	_palette_hatching = palette.hatching
	_shared["shadow_style"] = 1 if _hatching_setting and _palette_hatching else 0
	for key: String in ["grass", "grass_dark", "dirt", "rock", "low", "low_height", "high", "high_height", "patch_colour", "patch_amount", "patch_size", "patch_alt", "patch_alt_amount", "variation_colour", "variation", "variation_size", "rock_alt", "strata"]:
		_ground_shared[key] = palette.get(key)
	_share_all()
	for line: ShaderMaterial in [outline(), near_outline(), figure_outline(), effect_outline()]:
		if not _widths.has(line):
			_widths[line] = line.get_shader_parameter("width") if line.get_shader_parameter("width") != null else 0.0055
		line.set_shader_parameter("colour", palette.ink)
		line.set_shader_parameter("sun_direction", direction)
		line.set_shader_parameter("width", _widths[line] * palette.line_width)
		# The near and effect lines never wobble.
		if line != near_outline() and line != effect_outline():
			line.set_shader_parameter("brush", palette.line_brush)


## Lights things near a fire or energy effect: glow point index (0 to 3) at
## a world position, fading out over radius metres, in a colour whose alpha
## is its strength. A radius of 0 turns it off. One shared value, so every
## ink material sees it at no cost on the CPU.
static func set_glow(index: int, at: Vector3, radius: float, colour := Color(1.0, 0.6, 0.25, 0.6)) -> void:
	_glow_points[index] = Vector4(at.x, at.y, at.z, radius)
	_glow_colours[index] = Vector4(colour.r, colour.g, colour.b, colour.a)
	RenderingServer.global_shader_parameter_set("glow_points", _glow_points)
	RenderingServer.global_shader_parameter_set("glow_colours", _glow_colours)


static func clear_glows() -> void:
	for k in 4:
		set_glow(k, Vector3.ZERO, 0.0, Color(0.0, 0.0, 0.0, 0.0))


## The paper grain tile: 64 by 64 random greys, the same every run, which
## the ink shader reads with smooth filtering so the grain is soft.
static func paper_grain() -> ImageTexture:
	if _grain == null:
		var random := RandomNumberGenerator.new()
		random.seed = 7
		var bytes := PackedByteArray()
		bytes.resize(64 * 64)
		for k in bytes.size():
			bytes[k] = random.randi_range(0, 255)
		_grain = ImageTexture.create_from_image(Image.create_from_data(64, 64, false, Image.FORMAT_L8, bytes))
	return _grain


## A smooth 256 by 256 noise tile that repeats, the same every run, for
## soft colour changes across the ground and for clouds and mountains in
## the sky.
static func soft_noise() -> ImageTexture:
	if _soft == null:
		var noise := FastNoiseLite.new()
		noise.seed = 11
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 1.0 / 32.0
		noise.fractal_octaves = 2
		_soft = ImageTexture.create_from_image(noise.get_seamless_image(256, 256))
	return _soft


## Hatching in the shaded bands, on or off. It only shows if the palette
## has it too.
static func set_hatching(on: bool) -> void:
	_hatching_setting = on
	_shared["shadow_style"] = 1 if on and _palette_hatching else 0
	_share_all()


static func hatching_on() -> bool:
	return _hatching_setting


static func _share_all() -> void:
	for made: ShaderMaterial in _materials.values():
		_share(made, _shared)
	for held in _grounds:
		var made := held.get_ref() as ShaderMaterial
		if made != null:
			_share(made, _shared)
			_share(made, _ground_shared)


static func _share(made: ShaderMaterial, values: Dictionary[String, Variant]) -> void:
	for key in values:
		made.set_shader_parameter(key, values[key])


## One mesh from many parts, each a [mesh, transform, colour] with the
## colour's alpha as how much team colour it takes. Draw it with a
## material(Color.WHITE, 1.0, true, true) and it costs one draw call and one
## outline whatever the number of parts. The ink shader reads vertex colours
## as linear, so they're converted unless for_glow, since glow materials
## convert them themselves.
static func merged(parts: Array, for_glow := false) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Array in parts:
		var mesh: Mesh = part[0]
		var where: Transform3D = part[1]
		var colour: Color = part[2]
		if not for_glow:
			var team := colour.a
			colour = colour.srgb_to_linear()
			colour.a = team
		var normal_basis := where.basis.inverse().transposed()
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if indices.is_empty():
				indices.resize(points.size())
				for k in points.size():
					indices[k] = k
			for index in indices:
				tool.set_color(colour)
				tool.set_normal((normal_basis * normals[index]).normalized())
				tool.add_vertex(where * points[index])
	tool.index()
	return hull_mesh(tool.commit())


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


## A box with its edges and corners cut at 45 degrees, bevel metres in,
## so it catches a light band along each edge. Shared by size.
static func bevel_box(size: Vector3, bevel := 0.02) -> ArrayMesh:
	var half := size * 0.5
	var b := minf(bevel, minf(half.x, minf(half.y, half.z)) * 0.45)
	var key := "bevel/%s/%s" % [size, b]
	if _meshes.has(key):
		return _meshes[key]
	# A corner point with the axis "full" at the box face and the other two
	# pulled in by the bevel.
	var corner := func(full: int, signs: Vector3) -> Vector3:
		var p := half * signs
		for a in 3:
			if a != full:
				p[a] -= signs[a] * b
		return p
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for a in 3:
		var u := (a + 1) % 3
		var v := (a + 2) % 3
		for s: float in [1.0, -1.0]:
			# The face itself.
			var quad: Array[Vector3] = []
			for uv: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(-1, 1)]:
				var signs := Vector3.ZERO
				signs[a] = s
				signs[u] = uv.x
				signs[v] = uv.y
				quad.append(corner.call(a, signs))
			var normal := Vector3.ZERO
			normal[a] = s
			_quad(tool, quad, normal)
			# The edge between this face and the next axis's, along the third.
			for t: float in [1.0, -1.0]:
				var edge: Array[Vector3] = []
				for k in 4:
					var signs := Vector3.ZERO
					signs[a] = s
					signs[u] = t
					signs[v] = 1.0 if k == 0 or k == 3 else -1.0
					edge.append(corner.call(a if k < 2 else u, signs))
				var edge_normal := Vector3.ZERO
				edge_normal[a] = s
				edge_normal[u] = t
				_quad(tool, edge, edge_normal.normalized())
	for x: float in [1.0, -1.0]:
		for y: float in [1.0, -1.0]:
			for z: float in [1.0, -1.0]:
				var signs := Vector3(x, y, z)
				_triangle(tool, corner.call(0, signs), corner.call(1, signs), corner.call(2, signs), signs.normalized())
	tool.index()
	_meshes[key] = hull_mesh(tool.commit())
	return _meshes[key]


## A round shape turned from a profile of (radius, height) points from the
## bottom up, smooth around and with a hard edge at each profile point, and
## flat caps where the profile ends off the axis. Shared by profile.
static func lathe(profile: PackedVector2Array, sides := 10) -> ArrayMesh:
	var key := "lathe/%s/%d" % [profile, sides]
	if _meshes.has(key):
		return _meshes[key]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in profile.size() - 1:
		var p0 := profile[i]
		var p1 := profile[i + 1]
		var along := (p1 - p0).normalized()
		var out := Vector2(along.y, -along.x)
		for j in sides:
			var a0 := TAU * j / sides
			var a1 := TAU * (j + 1) / sides
			var n0 := Vector3(out.x * cos(a0), out.y, out.x * sin(a0))
			var n1 := Vector3(out.x * cos(a1), out.y, out.x * sin(a1))
			var v00 := Vector3(p0.x * cos(a0), p0.y, p0.x * sin(a0))
			var v01 := Vector3(p0.x * cos(a1), p0.y, p0.x * sin(a1))
			var v10 := Vector3(p1.x * cos(a0), p1.y, p1.x * sin(a0))
			var v11 := Vector3(p1.x * cos(a1), p1.y, p1.x * sin(a1))
			var facing := (n0 + n1).normalized()
			if p0.x > 0.0001:
				_triangle(tool, v00, v01, v11, facing, [n0, n1, n1])
			if p1.x > 0.0001:
				_triangle(tool, v00, v11, v10, facing, [n0, n1, n0])
	for end in [0, profile.size() - 1]:
		var p := profile[end]
		if p.x <= 0.0001:
			continue
		var normal := Vector3.DOWN if end == 0 else Vector3.UP
		for j in sides:
			var a0 := TAU * j / sides
			var a1 := TAU * (j + 1) / sides
			_triangle(tool, Vector3(0.0, p.y, 0.0), Vector3(p.x * cos(a0), p.y, p.x * sin(a0)), Vector3(p.x * cos(a1), p.y, p.x * sin(a1)), normal)
	tool.index()
	_meshes[key] = hull_mesh(tool.commit())
	return _meshes[key]


## A lathe profile for a short cylinder of this radius and height, centred,
## with its rims cut in by bevel.
static func bevel_cylinder(radius: float, height: float, bevel := 0.015, sides := 10) -> ArrayMesh:
	var b := minf(bevel, minf(radius, height * 0.5) * 0.45)
	var h := height * 0.5
	return lathe(PackedVector2Array([Vector2(radius - b, -h), Vector2(radius, -h + b), Vector2(radius, h - b), Vector2(radius - b, h)]), sides)


static func _quad(tool: SurfaceTool, corners: Array[Vector3], normal: Vector3) -> void:
	_triangle(tool, corners[0], corners[1], corners[2], normal)
	_triangle(tool, corners[0], corners[2], corners[3], normal)


## One triangle facing along normal, wound as Godot's front faces
## (clockwise seen from the front), with its own or per corner normals.
static func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, normals := []) -> void:
	if (b - a).cross(c - a).length_squared() < 1e-12:
		return
	var order := [a, b, c]
	var order_normals: Array = normals if not normals.is_empty() else [normal, normal, normal]
	if (b - a).cross(c - a).dot(normal) > 0.0:
		order = [a, c, b]
		order_normals = [order_normals[0], order_normals[2], order_normals[1]]
	for k in 3:
		tool.set_normal(order_normals[k])
		tool.add_vertex(order[k])


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
		_near_outline.set_shader_parameter("width", 0.006)
		_near_outline.set_shader_parameter("brush", 0.0)
		_near_outline.set_shader_parameter("shadow_weight", 0.0)
	return _near_outline


## The outline pass for soldiers and flags: a quarter thinner than the
## world's, so their detail doesn't fill with ink. It stops growing at 18 m
## and thins to half by 50 m, so at 50 m it's under a pixel and the team
## colour shows, and it's less heavy on the shadow side.
static func figure_outline() -> ShaderMaterial:
	if _figure_outline == null:
		_figure_outline = ShaderMaterial.new()
		_figure_outline.shader = OUTLINE
		_figure_outline.set_shader_parameter("width", 0.0042)
		_figure_outline.set_shader_parameter("max_distance", 18.0)
		_figure_outline.set_shader_parameter("thin_distance", 50.0)
		_figure_outline.set_shader_parameter("thin_to", 0.5)
		_figure_outline.set_shader_parameter("shadow_weight", 0.4)
	return _figure_outline


## The outline pass for effects: shots, flames and blasts, a little thinner
## and with no wobble, since they move fast.
static func effect_outline() -> ShaderMaterial:
	if _effect_outline == null:
		_effect_outline = ShaderMaterial.new()
		_effect_outline.shader = OUTLINE
		_effect_outline.set_shader_parameter("min_distance", 0.5)
		_effect_outline.set_shader_parameter("width", 0.0045)
		_effect_outline.set_shader_parameter("brush", 0.0)
		_effect_outline.set_shader_parameter("shadow_weight", 0.0)
	return _effect_outline


static func _outline_for(made: ShaderMaterial) -> ShaderMaterial:
	if made.get_meta("near", false):
		return near_outline()
	if made.get_meta("small", false):
		return effect_outline()
	return figure_outline() if made.get_meta("figure", false) else outline()


static func set_outlines(on: bool) -> void:
	_outlines_on = on
	for made: ShaderMaterial in _materials.values():
		if made.has_meta("outlined"):
			made.next_pass = _outline_for(made) if on else null
	for made: StandardMaterial3D in _glows.values():
		if made.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			made.next_pass = effect_outline() if on else null


static func outlines_on() -> bool:
	return _outlines_on
