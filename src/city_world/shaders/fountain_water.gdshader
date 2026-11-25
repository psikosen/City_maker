shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 water_tint : source_color = vec3(0.14, 0.52, 0.62);
uniform vec3 foam_tint : source_color = vec3(0.84, 0.94, 0.98);

varying vec3 v_world_pos;
varying float v_is_plume;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.56);
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
	// Plume/jet vertices encode upward flow flag in COLOR.r (> 0.5)
	v_is_plume = COLOR.r;
	if (v_is_plume > 0.5) {
		float pulse = sin(TIME * 7.5 - v_world_pos.y * 4.5 + v_world_pos.x * 2.0) * 0.025;
		VERTEX.xz += NORMAL.xz * pulse;
	}
}

void fragment() {
	vec2 p = v_world_pos.xz;
	if (v_is_plume > 0.5) {
		float streak = noise2d(vec2(v_world_pos.x * 9.0 + v_world_pos.z * 9.0, v_world_pos.y * 3.8 - TIME * 4.4));
		float crest = smoothstep(0.32, 0.86, streak);
		ALBEDO = mix(water_tint * 1.35, foam_tint, crest * 0.85);
		ALPHA = mix(0.45, 0.88, crest);
		ROUGHNESS = 0.14;
		SPECULAR = 0.85;
	} else {
		float r1 = sin(length(fract(p * 0.25) - 0.5) * 28.0 - TIME * 4.2);
		float r2 = noise2d(p * 3.8 + vec2(TIME * 0.65, -TIME * 0.52));
		float caust = smoothstep(0.54, 0.92, r2 * 0.72 + r1 * 0.28);
		ALBEDO = mix(water_tint, foam_tint * 0.95, caust * 0.55);
		ALPHA = 0.82;
		ROUGHNESS = 0.06;
		SPECULAR = 0.92;
		float eps = 0.05;
		float n_x = noise2d((p + vec2(eps, 0.0)) * 4.2 + TIME * 0.5);
		float n_z = noise2d((p + vec2(0.0, eps)) * 4.2 - TIME * 0.5);
		vec3 wb = vec3((r2 - n_x) * 0.55, 0.0, (r2 - n_z) * 0.55);
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(wb, 0.0)).xyz);
	}
}
