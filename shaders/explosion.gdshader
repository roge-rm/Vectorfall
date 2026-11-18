// A blast's lumpy ball and ring in flat ink style: a pale core facing you, a
// hot edge and a dark rim that grow inwards as life goes from 0 to 1. It's
// opaque so its ink outline matches; the blast shrinks away instead of
// fading.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform vec4 core : source_color = vec4(1.0, 0.95, 0.75, 1.0);
uniform vec4 edge : source_color = vec4(0.95, 0.45, 0.12, 1.0);
uniform vec4 smoke : source_color = vec4(0.3, 0.26, 0.24, 1.0);
instance uniform float life = 0.0;

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	vec3 colour = facing > mix(0.45, 1.01, life) ? core.rgb : edge.rgb;
	if (facing < mix(-0.1, 0.9, life * life)) {
		colour = smoke.rgb;
	}
	ALBEDO = colour;
}
