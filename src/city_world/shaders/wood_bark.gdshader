shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 bark_dark : source_color = vec3(0.14, 0.10, 0.08);
uniform vec3 bark_ridge : source_color = vec3(0.32, 0.24, 0.18);
uniform vec3 moss_tint : source_color = vec3(0.18, 0.28, 0.14);

varying vec3 v_local_pos;
varying vec3 v_world_pos;

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(
			mix(hash31(i + vec3(0, 0, 0)), hash31(i + vec3(1, 0, 0)), u.x),
			mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), u.x),
			u.y
		),
		mix(
			mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), u.x),
			mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), u.x),
			u.y
		),
		u.z
	);
}

float bark_field(vec3 lp) {
	// High-frequency vertical fibrous bark furrows without blocky trunk bands
	vec3 p = vec3(lp.x * 38.0, lp.y * 4.5, lp.z * 38.0);
	float warp = noise3d(p * 0.45) * 1.1;
	float f1 = noise3d(p + vec3(warp, 0.0, warp));
	float f2 = noise3d(p * 2.4 + vec3(0.0, warp * 0.5, 0.0));
	float furrow = sin((f1 * 5.5 + f2 * 2.2) * 3.14159);
	return clamp(0.5 + 0.5 * furrow, 0.0, 1.0);
}

uniform float wind_strength : hint_range(0.0, 0.5) = 0.07;

global uniform vec2 wind_vector;
global uniform float weather_wetness;

void vertex() {
	vec3 root_wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float w_mag = clamp(length(wind_vector), 0.25, 3.2);
	vec2 wind_dir = length(wind_vector) > 0.001 ? wind_vector / length(wind_vector) : vec2(0.86, 0.51);
	vec2 wind_perp = vec2(-wind_dir.y, wind_dir.x);
	float macro_phase = dot(root_wp.xz, wind_dir * 0.068);
	float gust_wave = sin(TIME * (1.15 + w_mag * 0.35) + macro_phase) + 0.35 * sin(TIME * 2.05 + macro_phase * 1.6);
	float branch_osc = sin(TIME * 2.4 + macro_phase + COLOR.a * 6.28318);
	float eff_w = wind_strength * w_mag;
	vec2 offset_xz = wind_dir * (gust_wave * COLOR.r * 2.4 + branch_osc * COLOR.g * 0.75) * eff_w
		+ wind_perp * (branch_osc * COLOR.g * 0.45) * eff_w;
	VERTEX.x += offset_xz.x;
	VERTEX.z += offset_xz.y;
	v_local_pos = VERTEX;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float b0 = bark_field(v_local_pos);
	float fine = noise3d(v_local_pos * vec3(52.0, 12.0, 52.0));
	float ridge = smoothstep(0.20, 0.80, b0 * 0.72 + fine * 0.28);

	vec3 col = mix(bark_dark, bark_ridge, ridge);
	// Subtle moss near root flare
	float root_moss = (1.0 - smoothstep(0.05, 0.48, v_local_pos.y)) * smoothstep(0.45, 0.82, noise3d(v_world_pos * 3.8));
	col = mix(col, moss_tint, root_moss * 0.42);

	// Analytical micro-bump from radial bark ridges
	float eps = 0.018;
	float bx = bark_field(v_local_pos + vec3(eps, 0.0, 0.0));
	float bz = bark_field(v_local_pos + vec3(0.0, 0.0, eps));
	vec3 world_bump = (MODEL_MATRIX * vec4((b0 - bx) * 0.55, 0.0, (b0 - bz) * 0.55, 0.0)).xyz;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(world_bump, 0.0)).xyz);

	ALBEDO = col * mix(1.0, 0.58, weather_wetness);
	ROUGHNESS = mix(mix(0.96, 0.84, ridge), 0.36, weather_wetness);
	METALLIC = 0.0;
	SPECULAR = mix(0.45, 0.75, weather_wetness);
}
