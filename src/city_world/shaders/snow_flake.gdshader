shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

global uniform float weather_snow;
global uniform float night_factor;
global uniform float sun_elevation;
global uniform float weather_lightning;

varying float v_alpha;
varying float v_seed;

void vertex() {
	v_alpha = INSTANCE_CUSTOM.w;
	v_seed = INSTANCE_CUSTOM.z;
	if (v_alpha < 0.01) {
		VERTEX = vec3(0.0);
	} else {
		vec3 center_w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		vec3 cam_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		vec3 cam_right = (INV_VIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz;
		vec3 cam_up = (INV_VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;

		float cam_dist = length(cam_pos - center_w);
		float cam_fade = smoothstep(0.95, 2.6, cam_dist);
		v_alpha *= cam_fade;

		float sz = mix(0.028, 0.068, clamp(INSTANCE_CUSTOM.y - 0.55, 0.0, 1.0));
		float ang = TIME * 1.2 + v_seed;
		float ca = cos(ang);
		float sa = sin(ang);
		vec2 rv = vec2(VERTEX.x * ca - VERTEX.y * sa, VERTEX.x * sa + VERTEX.y * ca);
		vec3 wp = center_w + cam_right * (rv.x * sz) + cam_up * (rv.y * sz);
		VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
	}
}

void fragment() {
	if (v_alpha < 0.01) {
		discard;
	}
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	if (r > 1.0) {
		discard;
	}
	float soft_disc = pow(1.0 - r * r, 1.45);
	// Soft warm-gold tint at sunset, cool silver-blue under night streetlights
	float sunset_band = smoothstep(-0.12, 0.05, sun_elevation) * (1.0 - smoothstep(0.08, 0.34, sun_elevation));
	vec3 day_col = mix(vec3(0.94, 0.96, 0.99), vec3(1.0, 0.88, 0.78), sunset_band * 0.55);
	vec3 night_col = vec3(0.58, 0.66, 0.78);
	vec3 col = mix(day_col, night_col, night_factor);
	col += vec3(0.35, 0.45, 0.60) * weather_lightning;

	ALBEDO = col;
	ALPHA = soft_disc * v_alpha * 0.78;
}
