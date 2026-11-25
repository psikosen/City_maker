shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 grass_base : source_color = vec3(0.28, 0.42, 0.20);
uniform vec3 grass_tip : source_color = vec3(0.41, 0.56, 0.25);
uniform vec3 grass_dry : source_color = vec3(0.48, 0.50, 0.26);
uniform float wind_strength = 0.09;

global uniform vec2 wind_vector;
global uniform float weather_wetness;
global uniform float weather_snow_depth;
global uniform float weather_slush;

varying float v_height;
varying float v_seed;
varying float v_meadow;
varying vec3 v_up_view;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
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
	v_height = COLOR.r;
	vec3 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_seed = hash21(world_origin.xz * 0.73);
	v_meadow = noise2d(world_origin.xz * 0.06);

	// Traveling rolling wind gust field in world XZ synchronized with global wind_vector
	float w_mag = clamp(length(wind_vector), 0.25, 3.2);
	vec2 w_dir = length(wind_vector) > 0.001 ? wind_vector / length(wind_vector) : vec2(0.86, 0.51);
	float gust = noise2d(world_origin.xz * 0.09 + wind_vector * (TIME * 0.45));
	float micro_sway = sin(TIME * (2.9 + w_mag * 0.7) + world_origin.x * 1.1 + world_origin.z * 0.9) * 0.32;
	float bend = v_height * v_height * wind_strength * w_mag * (0.4 + gust * 1.35 + micro_sway);

	VERTEX.x += bend * w_dir.x;
	VERTEX.z += bend * w_dir.y;
	VERTEX.y -= abs(bend) * 0.18;
	v_up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	vec3 base_n = FRONT_FACING ? NORMAL : -NORMAL;
	NORMAL = normalize(mix(base_n, v_up_view, 0.78));

	vec3 tip_col = mix(grass_tip, grass_dry, smoothstep(0.35, 0.78, v_meadow) * 0.52);
	vec3 col = mix(grass_base, tip_col, smoothstep(0.0, 0.90, v_height));
	col *= mix(0.84, 1.12, smoothstep(0.0, 0.85, v_height));
	col *= mix(0.90, 1.12, v_seed);
	col *= mix(1.0, 0.82, weather_wetness);

	float snow_cov = clamp(weather_snow_depth * mix(0.65, 1.35, v_height) * (1.0 - weather_slush * 0.45), 0.0, 0.94);
	col = mix(col, vec3(0.88, 0.92, 0.97), snow_cov);

	ALBEDO = col;
	ROUGHNESS = mix(mix(0.84, 0.28, weather_wetness), 0.78, snow_cov);
	METALLIC = 0.0;
	SPECULAR = mix(mix(0.18, 0.65, weather_wetness), 0.38, snow_cov);
	BACKLIGHT = mix(vec3(0.42, 0.58, 0.24), vec3(0.55, 0.62, 0.70), snow_cov);
}
