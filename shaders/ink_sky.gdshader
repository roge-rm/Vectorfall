// The ink sky: a gradient from the horizon up, a sun disc with an ink ring,
// the same paper colour as the ground with no grain, and halftone dots towards
// the horizon if asked (only tools/shots/mockup_shot uses those).
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.5, 0.47, 0.42);
uniform vec3 horizon : source_color = vec3(0.86, 0.77, 0.6);
uniform vec3 ground : source_color = vec3(0.6, 0.52, 0.36);
uniform vec3 sun_colour : source_color = vec3(1.0, 0.95, 0.8);
uniform vec3 ink : source_color = vec3(0.07, 0.05, 0.04);
uniform vec3 paper : source_color = vec3(0.98, 0.93, 0.84);
uniform float sun_size = 0.9985;
// Flat bands in the gradient, 0 for a smooth one.
uniform float bands = 0.0;
// Size of the halftone dots at the horizon, 0 for none.
uniform float dots = 0.0;
uniform vec3 dot_colour : source_color = vec3(1.0);
uniform float dot_spacing = 7.0;
// The screen's height in pixels, so the dots keep their size.
uniform float screen_height = 720.0;

void sky() {
	float up = EYEDIR.y;
	float t = pow(max(up, 0.0), 0.6);
	if (bands > 0.0) {
		t = floor(t * bands + 0.5) / bands;
	}
	vec3 colour = up > 0.0 ? mix(horizon, zenith, t) : mix(horizon, ground, clamp(-up * 6.0, 0.0, 1.0));
	if (LIGHT0_ENABLED) {
		float s = dot(EYEDIR, LIGHT0_DIRECTION);
		if (s > sun_size) {
			colour = sun_colour * 1.5;
		} else if (s > sun_size - 0.0006) {
			colour = ink;
		}
	}
	colour *= paper;
	if (!AT_CUBEMAP_PASS) {
		vec2 px = FRAGCOORD.xy * 720.0 / screen_height;
		if (dots > 0.0 && up > 0.0) {
			vec2 r = vec2(px.x + px.y, px.x - px.y) * 0.7071 / dot_spacing;
			float d = length(fract(r) - 0.5) * 2.0;
			float radius = dots * (1.0 - smoothstep(0.0, 0.45, up));
			colour = mix(colour, dot_colour, smoothstep(radius + 0.25, radius, d) * step(0.02, radius));
		}
	}
	COLOR = colour;
}
