shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

global uniform float weather_rain;
global uniform float night_factor;
global uniform float weather_lightning;

varying float v_phase;

void vertex() {
	v_phase = INSTANCE_CUSTOM.r;
	if (weather_rain < 0.02) {
		VERTEX = vec3(0.0);
	} else {
		float cyc = fract(TIME * 2.8 + v_phase);
		float s = mix(0.25, 1.15, cyc);
		VERTEX.xz *= s;
	}
}

void fragment() {
	if (weather_rain < 0.02) {
		discard;
	}
	float cyc = fract(TIME * 2.8 + v_phase);
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring_radius = mix(0.18, 0.90, cyc);
	float ring = 1.0 - smoothstep(0.0, 0.16, abs(r - ring_radius));
	float fade = (1.0 - cyc) * smoothstep(0.0, 0.12, cyc);

	vec3 day_col = vec3(0.82, 0.88, 0.94);
	vec3 night_col = vec3(0.36, 0.44, 0.56);
	vec3 col = mix(day_col, night_col, night_factor) + vec3(0.35, 0.45, 0.60) * weather_lightning;

	ALBEDO = col;
	ALPHA = ring * fade * clamp(weather_rain * 1.15, 0.0, 1.0) * 0.45;
}
