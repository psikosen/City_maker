shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

global uniform float weather_rain;
global uniform float night_factor;
global uniform float weather_lightning;
global uniform vec2 wind_vector;

varying float v_alpha;

void vertex() {
	v_alpha = INSTANCE_CUSTOM.w;
	if (v_alpha < 0.01) {
		VERTEX = vec3(0.0);
	} else {
		vec3 center_w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		vec3 vel_w = vec3(wind_vector.x * 2.1, -18.5 * max(0.5, INSTANCE_CUSTOM.y), wind_vector.y * 2.1);
		vec3 fall_dir = normalize(vel_w);
		vec3 cam_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		vec3 to_cam = normalize(cam_pos - center_w);
		vec3 right_w = cross(fall_dir, to_cam);
		float r_len = length(right_w);
		right_w = r_len > 0.001 ? (right_w / r_len) : vec3(1.0, 0.0, 0.0);

		float cam_dist = length(cam_pos - center_w);
		float cam_fade = smoothstep(1.15, 3.25, cam_dist);
		v_alpha *= cam_fade;

		float drop_w = 0.0065;
		float drop_l = mix(0.42, 0.78, INSTANCE_CUSTOM.y) * (0.65 + 0.35 * weather_rain);
		vec3 wp = center_w + right_w * (VERTEX.x * drop_w) + fall_dir * (VERTEX.y * drop_l);
		VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
	}
}

void fragment() {
	if (v_alpha < 0.01) {
		discard;
	}
	float horiz = max(0.0, 1.0 - abs(UV.x * 2.0 - 1.0));
	float vert = sin(UV.y * 3.1415926);
	float mask = pow(horiz, 1.8) * pow(vert, 0.9);

	vec3 day_streak = vec3(0.76, 0.83, 0.90);
	vec3 night_streak = vec3(0.36, 0.44, 0.58);
	vec3 col = mix(day_streak, night_streak, night_factor);
	col += vec3(0.42, 0.52, 0.70) * weather_lightning;

	ALBEDO = col;
	ALPHA = mask * v_alpha * 0.24;
}
