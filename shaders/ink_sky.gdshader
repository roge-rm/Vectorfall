// The ink sky: a gradient from the horizon up, a sun disc with an ink ring,
// the same paper colour as the ground with no grain, and halftone dots towards
// the horizon if asked (only tools/shots/mockup_shot uses those). Clouds and
// two mountain ranges on the horizon are there if the palette asks, outlined
// in ink.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.5, 0.47, 0.42);
uniform vec3 horizon : source_color = vec3(0.86, 0.77, 0.6);
uniform vec3 ground : source_color = vec3(0.6, 0.52, 0.36);
// A third colour in the gradient at middle_height (0 horizon, 1 straight
// up), by its alpha.
uniform vec4 middle : source_color = vec4(0.0);
uniform float middle_height = 0.3;
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
// Clouds on a flat layer, cloud_amount of the sky covered (0 for none), lit
// in cloud_colour with cloud_shade on the side away from the sun. soft_noise
// is Cel.soft_noise().
uniform sampler2D soft_noise : hint_default_black, filter_linear, repeat_enable;
uniform float cloud_amount = 0.0;
uniform float cloud_scale = 1.0;
uniform vec3 cloud_colour : source_color = vec3(1.0, 0.97, 0.88);
uniform vec3 cloud_shade : source_color = vec3(0.7, 0.72, 0.85);
// Two mountain ranges, the far one behind: colour, with alpha to show it,
// and top height (sin of the angle above the horizon).
uniform vec4 far_range : source_color = vec4(0.0);
uniform float far_range_height = 0.12;
uniform vec4 near_range : source_color = vec4(0.0);
uniform float near_range_height = 0.07;
// Pixels of ink along cloud and mountain edges.
uniform float edge_ink = 2.0;

// A mountain line around the horizon, 0 to 1, from the noise tile along
// the compass direction.
float ridge(float angle, float shift) {
	float a = angle / 6.2832;
	return texture(soft_noise, vec2(a * 2.0, shift)).r * 0.65 + texture(soft_noise, vec2(a * 7.0, shift + 0.3)).r * 0.35;
}

// 1 inside, 0 outside, and how far inside in pixels for the ink line.
vec2 shape(float inside) {
	float w = max(fwidth(inside), 0.00001);
	return vec2(step(0.0, inside), inside / w);
}

void sky() {
	float up = EYEDIR.y;
	float t = pow(max(up, 0.0), 0.6);
	if (bands > 0.0) {
		t = floor(t * bands + 0.5) / bands;
	}
	vec3 colour = mix(horizon, zenith, t);
	if (middle.a > 0.0) {
		float m = pow(middle_height, 0.6);
		vec3 two = t < m ? mix(horizon, middle.rgb, t / m) : mix(middle.rgb, zenith, (t - m) / (1.0 - m));
		colour = mix(colour, two, middle.a);
	}
	if (up <= 0.0) {
		colour = mix(horizon, ground, clamp(-up * 6.0, 0.0, 1.0));
	}
	if (LIGHT0_ENABLED) {
		float s = dot(EYEDIR, LIGHT0_DIRECTION);
		if (s > sun_size) {
			colour = sun_colour * 1.5;
		} else if (s > sun_size - 0.0006) {
			colour = ink;
		}
	}
	if (!AT_CUBEMAP_PASS) {
		if (cloud_amount > 0.0 && up > 0.02) {
			vec2 at = EYEDIR.xz / (up + 0.06) * 0.12 / cloud_scale;
			float n = texture(soft_noise, at).r * 0.7 + texture(soft_noise, at * 2.3 + 0.4).r * 0.3;
			// Thinner towards the horizon, so they don't pile up there.
			float inside = n - (1.0 - cloud_amount) - 0.1 * (1.0 - smoothstep(0.02, 0.25, up));
			vec2 cloud = shape(inside);
			if (cloud.x > 0.0) {
				// Shade where the cloud is thicker towards the sun than here,
				// and along the flat bottom.
				vec2 toward = normalize(LIGHT0_DIRECTION.xz + vec2(0.0001)) * 0.025;
				float lit = texture(soft_noise, at + toward).r * 0.7 + texture(soft_noise, (at + toward) * 2.3 + 0.4).r * 0.3;
				colour = (lit > n + 0.012 || inside < 0.035) ? cloud_shade : cloud_colour;
				colour = mix(colour, ink, step(cloud.y, edge_ink));
			}
		}
		float angle = atan(EYEDIR.x, EYEDIR.z);
		if (far_range.a > 0.0) {
			vec2 hill = shape(far_range_height * (0.35 + 0.65 * ridge(angle, 0.1)) - up);
			if (hill.x > 0.0) {
				colour = mix(colour, mix(far_range.rgb, ink, step(hill.y, edge_ink)), far_range.a);
			}
		}
		if (near_range.a > 0.0) {
			vec2 hill = shape(near_range_height * (0.3 + 0.7 * ridge(angle, 0.6)) - up);
			if (hill.x > 0.0) {
				colour = mix(colour, mix(near_range.rgb, ink, step(hill.y, edge_ink)), near_range.a);
			}
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
