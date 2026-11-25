shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.25, 0.22, 0.20);

global uniform float weather_wetness;
global uniform float weather_snow_depth;
global uniform float weather_slush;

varying vec3 v_local_pos;
varying vec3 v_local_normal;
varying vec3 v_world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.4, 456.7));
	p += dot(p, p + 31.3);
	return fract(p.x * p.y);
}

void vertex() {
	vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (weather_snow_depth > 0.01 && wn.y > 0.35) {
		float up_m = smoothstep(0.35, 0.78, wn.y);
		VERTEX += NORMAL * (up_m * weather_snow_depth * 0.16 * (1.0 - weather_slush * 0.35));
	}
	v_local_pos = VERTEX;
	v_local_normal = NORMAL;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv_s = vec2(v_local_pos.x / 0.34, v_local_pos.z / 0.22);
	vec2 fw = max(fwidth(uv_s), vec2(0.001));
	float detail_fade = 1.0 - smoothstep(0.25, 0.72, max(fw.x, fw.y));

	float row = floor(uv_s.y);
	uv_s.x += mod(row, 2.0) * 0.5;
	vec2 cell = fract(uv_s);
	vec2 sid = floor(uv_s);

	float tab_var = mix(0.84, 1.16, hash21(sid));
	float course_line = mix(0.9, smoothstep(0.0, max(0.14, fw.y * 1.2), cell.y), detail_fade);
	float tab_gap = mix(0.95, smoothstep(0.0, max(0.04, fw.x), cell.x) * smoothstep(0.0, max(0.04, fw.x), 1.0 - cell.x), detail_fade);
	float grit = mix(0.92, 1.06, mix(0.5, hash21(floor(v_local_pos.xz * 24.0)), detail_fade));

	// Subtle shingle course edge normal relief
	vec3 world_bump = (MODEL_MATRIX * vec4(0.0, 0.0, (0.5 - cell.y) * 0.14 * detail_fade, 0.0)).xyz;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(world_bump, 0.0)).xyz);

	vec3 col = base_color * mix(1.0, tab_var, detail_fade) * grit * mix(0.68, 1.0, course_line * tab_gap);
	col *= mix(1.0, 0.64, weather_wetness);

	// Thick snow piling on upward-facing pitched roof slopes
	float snow_cov = 0.0;
	if (weather_snow_depth > 0.01 && v_local_normal.y > 0.32) {
		float up_m = smoothstep(0.32, 0.72, v_local_normal.y);
		float patch_n = hash21(floor(v_world_pos.xz * 0.45));
		snow_cov = clamp(smoothstep(0.05, 0.42, weather_snow_depth * 1.45 * up_m - (1.0 - patch_n) * 0.25), 0.0, 1.0);
		vec3 s_col = mix(vec3(0.88, 0.92, 0.97), vec3(0.97, 0.98, 1.00), grit * 0.5);
		s_col = mix(s_col, vec3(0.58, 0.62, 0.68), weather_slush * 0.60);
		col = mix(col, s_col, snow_cov);
	}

	ALBEDO = col;
	ROUGHNESS = mix(mix(0.89, 0.16, weather_wetness), mix(0.76, 0.24, weather_slush), snow_cov);
	METALLIC = 0.0;
	SPECULAR = mix(mix(0.45, 0.88, weather_wetness), mix(0.42, 0.78, weather_slush), snow_cov);
}
