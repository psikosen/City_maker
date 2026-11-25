shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.71, 0.71, 0.68);
uniform float joint_spacing = 1.8;
uniform float joint_strength = 0.28;
uniform float roughness_base = 0.86;

global uniform float weather_rain;
global uniform float weather_wetness;
global uniform float weather_puddles;
global uniform float weather_snow_depth;
global uniform float weather_slush;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 41.3);
	return fract(p.x * p.y);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 an = abs(v_world_normal);
	vec2 tri_uv = v_world_pos.xz;
	if (an.x > an.y && an.x > an.z) {
		tri_uv = v_world_pos.zy;
	} else if (an.z > an.y && an.z > an.x) {
		tri_uv = v_world_pos.xy;
	}

	float macro = noise2d(tri_uv * 0.42);
	float speck = noise2d(tri_uv * 8.5);
	vec3 col = base_color * mix(0.95, 1.04, macro) * mix(0.96, 1.03, speck);

	// Derivative-filtered concrete slab expansion joints on horizontal surfaces
	float top_mask = smoothstep(0.65, 0.92, v_world_normal.y);
	vec2 j_uv = v_world_pos.xz / joint_spacing;
	vec2 cell = fract(j_uv);
	vec2 fw = max(fwidth(j_uv), vec2(0.001));
	float joint_fade = 1.0 - smoothstep(0.22, 0.68, max(fw.x, fw.y));

	float d_x = min(cell.x, 1.0 - cell.x);
	float d_y = min(cell.y, 1.0 - cell.y);
	float gx = 1.0 - smoothstep(0.0, max(0.016, fw.x * 1.15), d_x);
	float gy = 1.0 - smoothstep(0.0, max(0.016, fw.y * 1.15), d_y);
	float joint_line = max(gx, gy) * top_mask * joint_strength * 0.78 * joint_fade;

	vec2 slab_id = floor(j_uv);
	float slab_var = (hash21(slab_id) - 0.5) * 0.035 * top_mask;
	col = col * (1.0 + slab_var) * (1.0 - joint_line);

	float side_shade = (1.0 - top_mask) * 0.06;
	col *= (1.0 - side_shade);

	// Weather wetness & sidewalk/bridge puddles with animated raindrop rings + dry aggregate micro-normals
	float wet_surf = weather_wetness * mix(0.45, 1.0, top_mask);
	float pud_noise = noise2d(v_world_pos.xz * 0.24 + 5.1) * 0.65 + noise2d(v_world_pos.xz * 0.72) * 0.35;
	float puddle = smoothstep(0.62 - weather_puddles * 0.24, 0.78 - weather_puddles * 0.14, pud_noise) * weather_puddles * top_mask;
	col *= mix(1.0, 0.64, wet_surf);
	col = mix(col, col * 0.74, puddle * 0.8);

	float fw_tri = max(fwidth(tri_uv.x), fwidth(tri_uv.y));
	float dry_fade = 1.0 - smoothstep(0.03, 0.16, fw_tri);
	vec2 dry_grad = vec2(0.0);
	float wet_damp = 1.0 - max(puddle * 0.95, wet_surf * 0.55);
	if (dry_fade > 0.01 && wet_damp > 0.02) {
		float n_eps = 0.05;
		float n0 = noise2d(tri_uv * 9.5);
		float nu = noise2d((tri_uv + vec2(n_eps, 0.0)) * 9.5);
		float nv = noise2d((tri_uv + vec2(0.0, n_eps)) * 9.5);
		dry_grad = vec2(n0 - nu, n0 - nv) * 0.22 * dry_fade * wet_damp;
	}
	// Recessed expansion joint bevel normals on horizontal slabs
	vec3 joint_bump = vec3(0.0);
	if (top_mask > 0.01 && joint_fade > 0.01) {
		float jx_slope = (smoothstep(0.0, 0.035, cell.x) - smoothstep(0.0, 0.035, 1.0 - cell.x)) * (1.0 - smoothstep(0.02, 0.05, d_x));
		float jy_slope = (smoothstep(0.0, 0.035, cell.y) - smoothstep(0.0, 0.035, 1.0 - cell.y)) * (1.0 - smoothstep(0.02, 0.05, d_y));
		joint_bump = vec3(jx_slope, 0.0, jy_slope) * top_mask * joint_fade * joint_strength * 0.45;
	}
	vec3 tangent_a = (an.x > an.y && an.x > an.z) ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
	vec3 tangent_b = (an.y >= an.x && an.y >= an.z) ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
	vec3 world_bump = tangent_a * dry_grad.x + tangent_b * dry_grad.y + joint_bump;

	if (weather_rain > 0.02 && puddle > 0.05) {
		float fw_r = max(fwidth(v_world_pos.x), fwidth(v_world_pos.z));
		float r_fade = 1.0 - smoothstep(0.04, 0.22, fw_r);
		vec2 pi = floor(v_world_pos.xz * 1.55);
		vec2 pf = fract(v_world_pos.xz * 1.55) - 0.5;
		float h0 = hash21(pi);
		float dist = length(pf);
		float cyc = fract(TIME * 2.0 + h0);
		float ring = exp(-abs(dist - cyc * 0.42) * 24.0) * (1.0 - cyc) * sin((dist - cyc * 0.42) * 32.0);
		vec2 rdir = dist > 0.001 ? (pf / dist) : vec2(0.0);
		world_bump += vec3(rdir.x, 0.0, rdir.y) * ring * puddle * weather_rain * r_fade * 0.28;
	}
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(world_bump, 0.0)).xyz);

	// Snow piling on upward-facing sidewalks, plazas, bridges & flat roofs (with slushy melt transition)
	float snow_cov = 0.0;
	if (weather_snow_depth > 0.01 && top_mask > 0.15) {
		float drift_n = macro * 0.60 + pud_noise * 0.40;
		float raw_s = weather_snow_depth * 1.44 * top_mask - (1.0 - drift_n) * 0.34;
		snow_cov = clamp(smoothstep(0.04, 0.44, raw_s), 0.0, 1.0);
		vec3 fresh_snow = mix(vec3(0.85, 0.90, 0.96), vec3(0.96, 0.98, 1.00), speck);
		vec3 slush_col = vec3(0.54, 0.58, 0.64);
		vec3 s_col = mix(fresh_snow, slush_col, weather_slush * 0.68);
		float s_glint = smoothstep(0.90, 0.995, hash21(floor(v_world_pos.xz * 22.0))) * dry_fade * (1.0 - weather_slush);
		s_col += vec3(0.24, 0.27, 0.32) * s_glint;
		col = mix(col, s_col, snow_cov);
	}

	float base_r = clamp(roughness_base + speck * 0.11 - macro * 0.05 - slab_var * 0.5, 0.4, 0.98);
	float wet_r = mix(mix(base_r, 0.24, clamp(wet_surf + weather_slush * 0.45, 0.0, 1.0)), 0.025, puddle);
	float snow_r = mix(0.78, 0.22, weather_slush);
	ALBEDO = col;
	ROUGHNESS = mix(wet_r, snow_r, snow_cov);
	METALLIC = 0.0;
	SPECULAR = mix(mix(mix(0.45, 0.74, wet_surf), 0.94, puddle), mix(0.42, 0.78, weather_slush), snow_cov);
}
