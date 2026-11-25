shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 asphalt_base : source_color = vec3(0.14, 0.15, 0.17);
uniform float surface_dampness = 0.24;

global uniform float weather_rain;
global uniform float weather_wetness;
global uniform float weather_puddles;
global uniform float weather_snow_depth;
global uniform float weather_slush;

varying vec3 v_world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(311.7, 127.1));
	p += dot(p, p + 19.19);
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

vec2 rain_ripple_grad(vec2 p, float t) {
	vec2 pi = floor(p);
	vec2 pf = fract(p) - 0.5;
	float h0 = hash21(pi);
	vec2 jit = vec2(hash21(pi + vec2(3.1, 7.2)), hash21(pi + vec2(8.4, 2.9))) - 0.5;
	vec2 d = pf - jit * 0.42;
	float dist = length(d);
	float cyc = fract(t + h0);
	float ring = exp(-abs(dist - cyc * 0.45) * 24.0) * (1.0 - cyc) * sin((dist - cyc * 0.45) * 34.0);
	float env = smoothstep(0.48, 0.24, dist);
	return (dist > 0.001 ? d / dist : vec2(0.0)) * ring * env;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 xz = v_world_pos.xz;
	float fw = max(fwidth(xz.x), fwidth(xz.y));
	float grit_fade = 1.0 - smoothstep(0.03, 0.18, fw);

	// Multi-scale mineral aggregate grit + crushed limestone flecks + bitumen resurfacing patches
	float patch_n = noise2d(xz * 0.14);
	float grit_mid = noise2d(xz * 6.5);
	float grit_fine = mix(0.5, noise2d(xz * 22.0), grit_fade);
	float stone_fleck = smoothstep(0.80, 0.96, hash21(floor(xz * 28.0))) * grit_fade;

	vec3 col = asphalt_base;
	col *= mix(0.92, 1.07, patch_n);
	col *= mix(0.94, 1.06, grit_mid * 0.55 + grit_fine * 0.45);
	col += vec3(0.042, 0.043, 0.045) * stone_fleck * (1.0 - weather_wetness * 0.55);

	// Subtle sealed maintenance seams (calm contrast, free of harsh blotches)
	float crack_n = noise2d(xz * 0.38 + vec2(noise2d(xz * 0.9) * 1.4));
	float crack = (1.0 - smoothstep(0.008, 0.022, abs(crack_n - 0.5))) * grit_fade;
	col = mix(col, asphalt_base * 0.54, crack * 0.32);

	// Gentle wheel-path polish + weather wetness + smooth rain puddles for SSR reflections
	float wear = smoothstep(0.42, 0.80, noise2d(xz * 0.25 + 11.3));
	float damp_noise = noise2d(xz * 0.18 + 3.7) * 0.65 + noise2d(xz * 0.62) * 0.35;
	float eff_puddle = clamp(surface_dampness + weather_puddles * 0.92, 0.0, 1.25);
	float puddle = smoothstep(0.54 - weather_puddles * 0.28, 0.75 - weather_puddles * 0.14, damp_noise) * clamp(eff_puddle, 0.0, 1.0);
	col = mix(col, col * 0.88, wear * 0.30);
	col *= mix(1.0, 0.54, weather_wetness);
	col = mix(col, col * 0.60, puddle);

	// Distance-gated aggregate micro-bump smoothed cleanly inside wet film & rain puddles + active raindrop rings
	if (grit_fade > 0.015) {
		float eps = 0.04;
		float g0 = grit_fine * 0.65 + grit_mid * 0.35;
		float gx = noise2d((xz + vec2(eps, 0.0)) * 22.0) * 0.65 + noise2d((xz + vec2(eps, 0.0)) * 6.5) * 0.35;
		float gz = noise2d((xz + vec2(0.0, eps)) * 22.0) * 0.65 + noise2d((xz + vec2(0.0, eps)) * 6.5) * 0.35;
		vec3 world_bump = vec3((g0 - gx) * 0.20, 0.0, (g0 - gz) * 0.20) * grit_fade * (1.0 - max(puddle * 0.94, weather_wetness * 0.62));
		if (weather_rain > 0.02 && puddle > 0.05) {
			vec2 rp = rain_ripple_grad(xz * 1.45, TIME * 1.9) + rain_ripple_grad(xz * 2.15 + vec2(4.7, 1.9), TIME * 2.3 + 0.35);
			world_bump += vec3(rp.x, 0.0, rp.y) * puddle * weather_rain * grit_fade * 0.34;
		}
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(world_bump, 0.0)).xyz);
	}

	// Snow piling along shoulders & quiet patches while tire-worn wheel tracks stay slushy & dark!
	float snow_cov = 0.0;
	if (weather_snow_depth > 0.01) {
		float drift_n = patch_n * 0.55 + damp_noise * 0.45;
		// Tire tracks carve distinct dark wet slush ruts through snow-covered asphalt
		float rut_clear = wear * (0.96 + weather_slush * 0.42);
		float raw_snow = weather_snow_depth * 1.18 - rut_clear - (1.0 - drift_n) * 0.34;
		snow_cov = clamp(smoothstep(0.06, 0.52, raw_snow), 0.0, 1.0);
		vec3 fresh_snow = mix(vec3(0.84, 0.89, 0.95), vec3(0.95, 0.97, 0.99), grit_mid);
		vec3 road_slush = vec3(0.24, 0.27, 0.31);
		vec3 s_col = mix(fresh_snow, road_slush, clamp(weather_slush * 0.72 + wear * 0.48, 0.0, 0.90));
		float snow_glint = smoothstep(0.89, 0.99, hash21(floor(xz * 22.0))) * grit_fade * (1.0 - weather_slush);
		s_col += vec3(0.24, 0.27, 0.32) * snow_glint;
		col = mix(col, s_col, snow_cov);
		// Also darken wet salted tire ruts exposed beneath the snow
		col *= mix(1.0, 0.62, wear * clamp(weather_snow_depth * 0.9, 0.0, 1.0) * (1.0 - snow_cov));
	}

	float dry_rough = mix(0.93, 0.58, wear * 0.65 + crack * 0.25);
	float wet_rough = mix(dry_rough, 0.18, clamp(weather_wetness + weather_slush * 0.55, 0.0, 1.0));
	float road_rough = mix(wet_rough, 0.016, puddle);
	float snow_rough = mix(0.76, 0.20, clamp(weather_slush + wear * 0.25, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = mix(road_rough, snow_rough, snow_cov);
	METALLIC = 0.02 * (1.0 - snow_cov);
	SPECULAR = mix(mix(mix(0.36, 0.80, clamp(weather_wetness + weather_slush * 0.4, 0.0, 1.0)), 0.96, puddle), mix(0.42, 0.82, weather_slush), snow_cov);
}
