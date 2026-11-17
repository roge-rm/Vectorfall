// Cel shading for everything solid: flat colour, hard light bands from the
// sun, a rim light on the lit side, and a team colour per instance.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
// How much of the instance's team colour replaces the albedo.
uniform float team_amount : hint_range(0.0, 1.0) = 0.0;
// Multiplies by the mesh's vertex colours, for ground made in code.
uniform bool use_vertex_colour = false;
// Light levels for the dark, middle and lit bands.
uniform float shade_dark = 0.0;
uniform float shade_mid = 0.45;
uniform float shade_lit = 1.0;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.35;
uniform float rim_edge : hint_range(0.0, 1.0) = 0.62;

instance uniform vec4 team_colour : source_color = vec4(1.0);

void fragment() {
	vec3 colour = mix(albedo.rgb, team_colour.rgb, team_amount);
	if (use_vertex_colour) {
		colour *= COLOR.rgb;
	}
	ALBEDO = colour;
}

void light() {
	float n_dot_l = dot(NORMAL, LIGHT);
	float band = n_dot_l > 0.45 ? shade_lit : (n_dot_l > 0.0 ? shade_mid : shade_dark);
	float rim = step(rim_edge, 1.0 - max(dot(NORMAL, VIEW), 0.0)) * step(0.0, n_dot_l) * rim_amount;
	DIFFUSE_LIGHT += (band + rim) * ATTENUATION * LIGHT_COLOR / PI;
}
