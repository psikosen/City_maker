shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

global uniform float night_factor;
global uniform float weather_rain;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 41.3);
	return fract(p.x * p.y);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Jewel-toned cathedral stained-glass diamond & rosette mosaic with dark lead cames
	vec3 an = abs(v_world_normal);
	vec2 plane_uv = (an.x > an.z) ? v_world_pos.zy : v_world_pos.xy;
	vec2 grid = plane_uv * 2.8;
	vec2 diamond = vec2(grid.x + grid.y, grid.x - grid.y);
	vec2 id = floor(diamond);
	vec2 f = fract(diamond);

	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float lead = 1.0 - smoothstep(0.055, 0.11, edge);

	float h = hash21(id);
	vec3 jewel = vec3(0.14, 0.34, 0.78);
	if (h < 0.22) {
		jewel = vec3(0.76, 0.16, 0.18);
	} else if (h < 0.44) {
		jewel = vec3(0.88, 0.62, 0.14);
	} else if (h < 0.62) {
		jewel = vec3(0.12, 0.56, 0.38);
	} else if (h < 0.78) {
		jewel = vec3(0.46, 0.20, 0.68);
	}

	float shade = 0.76 + 0.32 * hash21(id + 7.3);
	vec3 glass_col = jewel * shade;
	vec3 lead_col = vec3(0.10, 0.11, 0.12);
	vec3 col = mix(glass_col, lead_col, lead);

	float glow = mix(0.28, 1.45, clamp(night_factor + weather_rain * 0.35, 0.0, 1.0));
	ALBEDO = col * 0.65;
	EMISSION = glass_col * glow * (1.0 - lead);
	ROUGHNESS = mix(0.10, 0.65, lead);
	METALLIC = mix(0.05, 0.55, lead);
	SPECULAR = 0.85;
}
