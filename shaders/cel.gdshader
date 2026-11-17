// Cel shading for everything solid: flat colour, three hard light bands from
// the sun, a rim light on the lit side, and a team colour per instance.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
// How much of the instance's team colour replaces the albedo.
uniform float team_amount : hint_range(0.0, 1.0) = 0.0;
// Multiplies by the mesh's vertex colours.
uniform bool use_vertex_colour = false;
// Ground made in code: the vertex colour holds the ground's steepness in red
// (the normal's y) and a patch noise in green, and each pixel picks one of
// the ground colours from them, so the colours meet at hard edges.
uniform bool ground = false;
uniform vec4 grass : source_color = vec4(0.45, 0.62, 0.32, 1.0);
uniform vec4 grass_dark : source_color = vec4(0.37, 0.53, 0.28, 1.0);
uniform vec4 dirt : source_color = vec4(0.62, 0.55, 0.4, 1.0);
uniform vec4 rock : source_color = vec4(0.55, 0.53, 0.5, 1.0);
// Where the bands change, in how directly the sun hits the surface.
uniform float lit_edge = 0.72;
uniform float mid_edge = 0.3;
// Light in the lit, middle and dark bands, on top of the ambient light.
uniform float shade_lit = 1.0;
uniform float shade_mid = 0.55;
uniform float shade_dark = 0.12;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.35;
uniform float rim_edge : hint_range(0.0, 1.0) = 0.62;

instance uniform vec4 team_colour : source_color = vec4(1.0);

void fragment() {
	vec3 colour = mix(albedo.rgb, team_colour.rgb, team_amount);
	if (ground) {
		float up = COLOR.r;
		colour = COLOR.g > 0.5 ? grass.rgb : grass_dark.rgb;
		if (up < 0.72) {
			colour = rock.rgb;
		} else if (up < 0.84) {
			colour = dirt.rgb;
		}
	} else if (use_vertex_colour) {
		colour *= COLOR.rgb;
	}
	ALBEDO = colour;
}

void light() {
	float n_dot_l = dot(NORMAL, LIGHT);
	float band = n_dot_l > lit_edge ? shade_lit : (n_dot_l > mid_edge ? shade_mid : shade_dark);
	float rim = step(rim_edge, 1.0 - max(dot(NORMAL, VIEW), 0.0)) * step(0.0, n_dot_l) * rim_amount;
	DIFFUSE_LIGHT += (band + rim) * ATTENUATION * LIGHT_COLOR / PI;
}
