shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform vec2 wind_vector;
global uniform float weather_wetness;

varying vec3 v_col;
varying float v_sway;

void vertex() {
	vec3 root_wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float w_mag = clamp(length(wind_vector), 0.25, 3.0);
	vec2 w_dir = length(wind_vector) > 0.001 ? wind_vector / length(wind_vector) : vec2(0.86, 0.51);
	float phase = dot(root_wp.xz, w_dir * 0.14) + VERTEX.x * 2.1 + VERTEX.z * 1.9;
	float sway_amp = COLOR.a * clamp(VERTEX.y * 1.35, 0.0, 1.0) * 0.055 * w_mag;
	float wave = sin(TIME * (2.6 + w_mag * 0.8) + phase) + 0.35 * sin(TIME * 5.1 + phase * 1.7);
	VERTEX.x += w_dir.x * wave * sway_amp;
	VERTEX.z += w_dir.y * wave * sway_amp;
	VERTEX.y -= abs(wave) * sway_amp * 0.16;

	v_col = COLOR.rgb;
	v_sway = COLOR.a;
}

void fragment() {
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	ALBEDO = v_col * mix(1.0, 0.85, weather_wetness);
	ROUGHNESS = mix(0.66, 0.24, weather_wetness);
	METALLIC = 0.0;
	SPECULAR = mix(0.45, 0.78, weather_wetness);
	BACKLIGHT = v_col * 0.38;
}
