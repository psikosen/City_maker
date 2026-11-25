shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D leaf_atlas : source_color, hint_default_white, filter_linear_mipmap;
uniform vec3 leaf_dark : source_color = vec3(0.11, 0.26, 0.10);
uniform vec3 leaf_bright : source_color = vec3(0.28, 0.49, 0.19);
uniform vec3 canopy_center = vec3(0.0, 2.95, 0.0);
uniform float spherical_blend = 0.84;
uniform float alpha_scissor = 0.42;
uniform float wind_strength = 0.07;

global uniform vec2 wind_vector;
global uniform float weather_wetness;
global uniform float weather_snow_depth;
global uniform float weather_slush;

varying vec3 v_world_pos;
varying vec3 v_local_pos;
varying vec3 v_sphere_view;
varying float v_canopy_ao;
varying float v_leaf_tint;

void vertex() {
	vec3 root_wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float w_mag = clamp(length(wind_vector), 0.25, 3.2);
	vec2 wind_dir = length(wind_vector) > 0.001 ? wind_vector / length(wind_vector) : vec2(0.86, 0.51);
	vec2 wind_perp = vec2(-wind_dir.y, wind_dir.x);
	float macro_phase = dot(root_wp.xz, wind_dir * 0.068);
	float gust_wave = sin(TIME * (1.15 + w_mag * 0.35) + macro_phase) + 0.35 * sin(TIME * 2.05 + macro_phase * 1.6);
	float branch_osc = sin(TIME * 2.4 + macro_phase + COLOR.a * 6.28318);
	float eff_w = wind_strength * w_mag;
	vec2 macro_xz = wind_dir * (gust_wave * COLOR.r * 2.4 + branch_osc * COLOR.g * 0.75) * eff_w
		+ wind_perp * (branch_osc * COLOR.g * 0.45) * eff_w;

	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float flutter = sin(TIME * (5.2 + w_mag * 1.4) + wp.x * 1.8 + wp.y * 1.3 + COLOR.a * 6.28318) * COLOR.b;
	VERTEX.x += macro_xz.x + flutter * 0.32 * eff_w;
	VERTEX.y += cos(TIME * 4.6 + wp.z * 1.9 + COLOR.a * 6.28318) * COLOR.b * 0.18 * eff_w;
	VERTEX.z += macro_xz.y + cos(TIME * 4.9 + wp.x * 1.5 + wp.z * 1.7) * COLOR.b * 0.28 * eff_w;

	v_local_pos = VERTEX;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Per-species spherical canopy normal is pre-encoded in vertex NORMAL by TreeGenerator.
	vec3 sph_n = length(NORMAL) > 0.001 ? normalize(NORMAL) : vec3(0.0, 1.0, 0.0);
	v_sphere_view = normalize((MODELVIEW_MATRIX * vec4(sph_n, 0.0)).xyz);
	v_canopy_ao = mix(0.62, 1.16, clamp(COLOR.g * 0.65 + COLOR.r * 0.35, 0.0, 1.0));
	v_leaf_tint = COLOR.a;
}

void fragment() {
	vec4 tex = texture(leaf_atlas, UV);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;

	// Flip double-sided card normal before spherical normal transfer
	vec3 card_n = FRONT_FACING ? NORMAL : -NORMAL;
	NORMAL = normalize(mix(card_n, v_sphere_view, spherical_blend));

	float sun_mix = clamp(tex.g * 0.48 + v_canopy_ao * 0.34 + (v_leaf_tint - 0.5) * 0.28, 0.0, 1.0);
	vec3 col = mix(leaf_dark, leaf_bright, sun_mix);
	col *= tex.rgb * v_canopy_ao;
	col *= mix(1.0, 0.84, weather_wetness);

	// Winter snow frosting & accumulation on upper canopy crowns
	float snow_cap = 0.0;
	if (weather_snow_depth > 0.01) {
		float crown_up = smoothstep(0.68, 1.12, v_canopy_ao) * smoothstep(0.15, 0.75, sun_mix);
		snow_cap = clamp(crown_up * weather_snow_depth * 1.45 * (1.0 - weather_slush * 0.45), 0.0, 0.92);
		col = mix(col, vec3(0.90, 0.94, 0.98), snow_cap);
	}

	ALBEDO = col;
	ROUGHNESS = mix(mix(0.90, 0.26, weather_wetness), 0.78, snow_cap);
	METALLIC = 0.0;
	SPECULAR = mix(mix(0.16, 0.72, weather_wetness), 0.40, snow_cap);
	BACKLIGHT = mix(vec3(0.34, 0.58, 0.18), vec3(0.55, 0.62, 0.70), snow_cap);
}
