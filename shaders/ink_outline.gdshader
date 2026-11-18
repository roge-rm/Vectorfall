// Inverted hull outline, used as the ink material's next pass. Back faces
// are pushed out by an amount that grows with distance, so the line stays
// about the same width on screen up to max_distance and thins past it. The
// line is heavier on the side away from the sun and wobbles like a brush.
// Meshes made with Cel.hull_mesh() carry smoothed normals in CUSTOM0, scaled
// so flat faces move out the full width and corners stay closed; others use
// their normals.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, fog_disabled;

uniform vec4 colour : source_color = vec4(0.07, 0.05, 0.04, 1.0);
// Outline width in metres per metre of distance.
uniform float width = 0.0055;
uniform float min_distance = 2.0;
uniform float max_distance = 70.0;
// Past max_distance the line thins further, to thin_to of its width by
// thin_distance. Off when thin_distance is 0.
uniform float thin_distance = 0.0;
uniform float thin_to = 1.0;
uniform vec3 sun_direction = vec3(-0.369, 0.766, 0.527);
// How much wider the line gets on the shadow side, 0 for an even line.
uniform float shadow_weight = 0.9;
// How much the width wobbles along the line, 0 to 1.
uniform float brush = 0.15;

void vertex() {
	vec3 hull = CUSTOM0.xyz;
	if (dot(hull, hull) < 0.01) {
		hull = NORMAL;
	}
	vec3 world_hull = normalize((MODEL_MATRIX * vec4(hull, 0.0)).xyz);
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float weight = 1.0 + shadow_weight * clamp(-dot(world_hull, sun_direction) + 0.3, 0.0, 1.3);
	weight *= 1.0 + brush * (sin(world.x * 7.0 + world.y * 5.0) * sin(world.z * 6.0 - world.y * 3.0));
	vec4 view_position = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// Scaled meshes keep the same line width.
	vec3 view_normal = (MODELVIEW_MATRIX * vec4(hull, 0.0)).xyz / length(MODEL_MATRIX[0].xyz);
	float distance = clamp(-view_position.z, min_distance, max_distance);
	if (thin_distance > max_distance) {
		distance *= mix(1.0, thin_to, smoothstep(max_distance, thin_distance, -view_position.z));
	}
	view_position.xyz += view_normal * width * weight * distance;
	POSITION = PROJECTION_MATRIX * view_position;
}

void fragment() {
	ALBEDO = colour.rgb;
}
