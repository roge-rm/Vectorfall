// A soft round shadow on a flat quad under a soldier, fading with height.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float strength = 0.45;
instance uniform float fade = 1.0;

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.0);
	ALPHA = (1.0 - smoothstep(0.55, 1.0, r)) * strength * fade;
}
