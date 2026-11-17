// A blast's ball and ring: a bright core facing you and a hot edge, in two
// hard bands, fading out as life goes from 0 to 1.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec4 core : source_color = vec4(1.0, 0.97, 0.8, 1.0);
uniform vec4 edge : source_color = vec4(1.0, 0.5, 0.12, 1.0);
instance uniform float life = 0.0;

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	ALBEDO = facing > mix(0.55, 0.98, life) ? core.rgb : edge.rgb;
	ALPHA = 1.0 - smoothstep(0.5, 1.0, life);
}
