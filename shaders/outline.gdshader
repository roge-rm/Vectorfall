// Inverted hull outline, used as the cel material's next pass. Back faces are
// pushed out by an amount that grows with distance, so the line stays about
// the same width on screen, up to max_distance. Meshes made with
// Cel.hull_mesh() carry smoothed normals in CUSTOM0, scaled so flat faces
// move out the full width and corners stay closed; others use their normals.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, fog_disabled;

uniform vec4 colour : source_color = vec4(0.05, 0.05, 0.08, 1.0);
// Outline width in metres per metre of distance.
uniform float width = 0.0035;
uniform float min_distance = 2.0;
uniform float max_distance = 80.0;

void vertex() {
	vec3 hull = CUSTOM0.xyz;
	if (dot(hull, hull) < 0.01) {
		hull = NORMAL;
	}
	vec4 view_position = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_normal = (MODELVIEW_MATRIX * vec4(hull, 0.0)).xyz;
	float distance = clamp(-view_position.z, min_distance, max_distance);
	view_position.xyz += view_normal * width * distance;
	POSITION = PROJECTION_MATRIX * view_position;
}

void fragment() {
	ALBEDO = colour.rgb;
}
