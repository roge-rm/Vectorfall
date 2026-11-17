// A gradient sky with a sun disc, flat ground colour below the horizon.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.18, 0.36, 0.68);
uniform vec3 horizon : source_color = vec3(0.72, 0.82, 0.9);
uniform vec3 ground : source_color = vec3(0.42, 0.47, 0.45);
uniform vec3 sun_colour : source_color = vec3(1.0, 0.95, 0.8);
uniform float sun_size = 0.9985;

void sky() {
	float up = EYEDIR.y;
	vec3 colour = up > 0.0 ? mix(horizon, zenith, pow(up, 0.6)) : mix(horizon, ground, clamp(-up * 6.0, 0.0, 1.0));
	if (LIGHT0_ENABLED && dot(EYEDIR, LIGHT0_DIRECTION) > sun_size) {
		colour = sun_colour * 2.0;
	}
	COLOR = colour;
}
