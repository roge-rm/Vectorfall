// A soft round shadow on a flat quad under a soldier, fading with height.
// With stretch above 0 it's an oval reaching away from the sun from the
// soldier's feet, stretch + 1 times longer than wide.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 colour : source_color = vec4(0.0, 0.0, 0.0, 0.45);
// Along the ground away from the sun, in world x and z.
uniform vec2 away = vec2(0.0);
uniform float stretch = 0.0;
instance uniform float fade = 1.0;

void vertex() {
	// The quad lies in its own x and z, only tipped to the slope, so world
	// x and z are close enough. 0.7 is half the quad, so the near edge stays
	// at the feet and the far edge moves out.
	VERTEX.xz += away * (dot(VERTEX.xz, away) + 0.7) * stretch;
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = colour.rgb;
	ALPHA = (1.0 - smoothstep(0.55, 1.0, r)) * colour.a * fade;
}
