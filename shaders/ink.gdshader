// Comic ink shading for everything solid: flat colour, three hard bands from
// a sun given as uniforms, hatching in ink over the shaded bands, light paper grain
// and the world's colours held below the team colour. Lit in the
// fragment, so the bands can be drawn with ink. Hatching and grain are in
// screen space, sized to a 720 pixel high screen. The defaults are the game's
// look; the palette and Cel set the rest.
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
// How much of the team colour replaces the albedo. With vertex colours, the
// vertex alpha says how much, and the albedo multiplies the vertex colour.
uniform float team_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 team_colour : source_color = vec4(1.0);
uniform bool use_vertex_colour = false;
// Ground made in code: the vertex colour holds the ground's steepness in red
// (the normal's y) and a patch noise in green. Each pixel picks a colour from
// them and its height, so colours meet at hard edges.
uniform bool ground = false;
uniform vec4 grass : source_color = vec4(0.66, 0.58, 0.4, 1.0);
uniform vec4 grass_dark : source_color = vec4(0.6, 0.52, 0.36, 1.0);
uniform vec4 dirt : source_color = vec4(0.62, 0.48, 0.34, 1.0);
uniform vec4 rock : source_color = vec4(0.48, 0.44, 0.4, 1.0);
// Flat ground below low_height and above high_height takes these instead.
uniform vec4 low : source_color = vec4(0.7, 0.62, 0.45, 1.0);
uniform vec4 high : source_color = vec4(0.85, 0.8, 0.7, 1.0);
uniform float low_height = -1000.0;
uniform float high_height = 1000.0;

uniform float lit_edge = 0.72;
uniform float mid_edge = 0.3;
uniform float shade_lit = 1.0;
uniform float shade_mid = 0.5;
uniform float shade_dark = 0.18;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.0;
uniform float rim_edge : hint_range(0.0, 1.0) = 0.62;

// The light, in world space, pointing at the sun.
uniform vec3 sun_direction = vec3(-0.369, 0.766, 0.527);
// Lit from above and behind the camera instead, for the gun in your hands,
// so it reads the same whichever way you face.
uniform bool camera_light = false;
uniform vec4 sun_colour : source_color = vec4(1.0, 0.9, 0.74, 1.0);
uniform vec4 ambient : source_color = vec4(0.62, 0.56, 0.5, 1.0);
uniform float ambient_energy = 0.5;

uniform vec4 ink : source_color = vec4(0.07, 0.05, 0.04, 1.0);
// 0 flat, 1 hatching, 2 halftone dots, 3 solid ink. The game uses 1, or 0
// with hatching off; the rest are for tools/shots/mockup_shot.
uniform int shadow_style = 1;
// Pixels between hatch lines or halftone dots.
uniform float hatch_spacing = 6.0;
// Share of each hatch line that's ink.
uniform float hatch_width = 0.32;
// Below this n.l hatching crosses, or solid ink starts (style 3).
uniform float deep_edge = -0.15;
// Ink in the middle band too: for hatching, lines when above 0; for halftone,
// dots this big (0 to 1).
uniform float mid_ink = 1.0;
// Colour strength of everything but the team colour.
uniform float saturation = 0.75;
// Paper grain over everything but the sky, and the paper's colour. The grain
// is a soft noise tile from Cel.paper_grain(), fixed to the screen so it
// doesn't crawl, in grain_size pixel cells at 720 pixels high.
uniform float grit = 0.06;
uniform float grain_size = 4.0;
uniform sampler2D paper_grain : hint_default_black, filter_linear, repeat_enable;
uniform vec4 paper : source_color = vec4(0.98, 0.93, 0.84, 1.0);

// Warm looks, all off by default. The middle and dark bands are multiplied
// by these tints, and hatching takes hatch_colour by its alpha instead of
// ink. Above highlight_edge the lit band gets highlight's colour added by
// its alpha. Team colours take 75% less of the tints and half the highlight.
uniform vec4 mid_tint : source_color = vec4(1.0);
uniform vec4 dark_tint : source_color = vec4(1.0);
uniform vec4 hatch_colour : source_color = vec4(0.0);
uniform vec4 highlight : source_color = vec4(0.0);
uniform float highlight_edge = 0.9;
// How much team colours ignore the colour of the sun and ambient light, so
// a gold sun doesn't turn blue grey. 0 lights them like everything else.
uniform float team_white_light : hint_range(0.0, 1.0) = 0.0;
// Glow from fire and energy: up to four points set by Cel.set_glow(), each
// a column, xyz the world position and w the radius in metres (0 for none),
// with its colour and strength in the same column of glow_colours.
global uniform mat4 glow_points;
global uniform mat4 glow_colours;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 0 to 1 from a pixel: a fine grain over a coarser blotch, both soft.
float grain(vec2 px) {
	vec2 cell = px / (grain_size * 64.0);
	return texture(paper_grain, cell).r * 0.6 + texture(paper_grain, cell * 0.37 + 0.5).r * 0.4;
}

// 1 on a diagonal line, with a pixel of soft edge.
float lines(vec2 px, float slope) {
	float d = fract((px.x + slope * px.y) / hatch_spacing);
	float aa = 1.0 / hatch_spacing;
	return smoothstep(hatch_width + aa, hatch_width, d) * smoothstep(0.0, aa, d);
}

// 1 inside a dot of this radius (0 to 1) on a 45 degree grid.
float dots(vec2 px, float radius) {
	vec2 r = vec2(px.x + px.y, px.x - px.y) * 0.7071 / hatch_spacing;
	float d = length(fract(r) - 0.5) * 2.0;
	float aa = 2.0 / hatch_spacing;
	return smoothstep(radius + aa, radius, d);
}

void fragment() {
	vec3 base = albedo.rgb;
	float team = team_amount;
	if (ground) {
		float up = COLOR.r;
		base = COLOR.g > 0.5 ? grass.rgb : grass_dark.rgb;
		float wobble = (COLOR.g - 0.5) * 6.0;
		if (world_position.y < low_height + wobble) {
			base = low.rgb;
		} else if (world_position.y > high_height + wobble) {
			base = high.rgb;
		}
		if (up < 0.72) {
			base = rock.rgb;
		} else if (up < 0.84) {
			base = dirt.rgb;
		}
	} else if (use_vertex_colour) {
		base *= COLOR.rgb;
		team *= COLOR.a;
	}
	float grey = dot(base, vec3(0.3, 0.55, 0.15));
	base = mix(vec3(grey), base, saturation);
	vec3 colour = mix(base, team_colour.rgb, team);

	vec3 light_dir = camera_light ? vec3(-0.35, 0.75, 0.56) : normalize((VIEW_MATRIX * vec4(sun_direction, 0.0)).xyz);
	float n_dot_l = dot(NORMAL, light_dir);
	float band = n_dot_l > lit_edge ? shade_lit : (n_dot_l > mid_edge ? shade_mid : shade_dark);
	// Team colours shade less, so they stay the strongest colours in shadow.
	band = mix(band, max(band, 0.8), team);
	float rim = step(rim_edge, 1.0 - max(dot(NORMAL, VIEW), 0.0)) * step(0.0, n_dot_l) * rim_amount;
	vec3 luma = vec3(0.3, 0.55, 0.15);
	float white = team * team_white_light;
	vec3 sun = mix(sun_colour.rgb, vec3(dot(sun_colour.rgb, luma)), white);
	vec3 sky = mix(ambient.rgb, vec3(dot(ambient.rgb, luma)), white);
	vec3 lit = colour * (sky * ambient_energy + (band + rim) * sun);
	vec3 tint = n_dot_l > lit_edge ? vec3(1.0) : (n_dot_l > mid_edge ? mid_tint.rgb : dark_tint.rgb);
	lit *= mix(tint, vec3(1.0), 0.75 * team);
	lit += colour * highlight.rgb * highlight.a * step(highlight_edge, n_dot_l) * (1.0 - 0.5 * team);

	// Fire and energy light the side facing them, fading out to the radius.
	vec3 glow = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		vec4 point = glow_points[i];
		if (point.w > 0.0) {
			vec3 to = (VIEW_MATRIX * vec4(point.xyz, 1.0)).xyz - VERTEX;
			float d = length(to);
			float fall = clamp(1.0 - d / point.w, 0.0, 1.0);
			float facing = clamp(dot(NORMAL, to / max(d, 0.001)) * 0.5 + 0.5, 0.0, 1.0);
			glow += glow_colours[i].rgb * glow_colours[i].a * fall * (2.0 - fall) * facing;
		}
	}
	// Tints towards the glow's hue as well as brightening, so it shows on
	// bright sand too. Team colours take half.
	float glow_amount = clamp(max(glow.r, max(glow.g, glow.b)), 0.0, 1.0);
	vec3 glow_hue = glow / max(glow_amount, 0.001);
	lit = mix(lit, lit * glow_hue * 1.6 + glow_hue * 0.15, glow_amount * (1.0 - 0.5 * team));

	vec2 px = FRAGCOORD.xy * 720.0 / VIEWPORT_SIZE.y;
	float inked = 0.0;
	if (shadow_style == 1) {
		// The gun in your hands only hatches its dark band, so it stays clean.
		if (n_dot_l <= mid_edge || (mid_ink > 0.0 && !camera_light && n_dot_l <= lit_edge)) {
			inked = lines(px, 1.0);
			if (n_dot_l < deep_edge) {
				inked = max(inked, lines(vec2(-px.x, px.y), 1.0));
			}
		}
		// Team colours stay readable in shadow.
		inked *= 1.0 - 0.7 * team;
	} else if (shadow_style == 2) {
		float dark = clamp((mid_edge - n_dot_l) / (mid_edge + 0.6), 0.0, 1.0);
		float radius = n_dot_l <= mid_edge ? mix(0.45, 0.95, dark) : (n_dot_l <= lit_edge ? mid_ink : 0.0);
		inked = dots(px, radius);
	} else if (shadow_style == 3) {
		inked = n_dot_l < deep_edge ? 1.0 - 0.75 * team : 0.0;
	}
	// Glow lifts the hatching off what it lights.
	inked *= 1.0 - 0.7 * glow_amount;
	lit = mix(lit, mix(ink.rgb, hatch_colour.rgb, hatch_colour.a), inked);
	lit *= paper.rgb;
	if (grit > 0.0) {
		lit *= 1.0 - grit * grain(px);
	}
	ALBEDO = lit;
}
