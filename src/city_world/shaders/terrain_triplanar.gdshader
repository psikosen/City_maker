shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float water_level = 1.6;
uniform float detail_strength = 0.22;

global uniform float weather_wetness;
global uniform float weather_puddles;
global uniform float weather_snow_depth;
global uniform float weather_slush;
global uniform float night_factor;
global uniform float weather_cloud_cover;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec3 v_vert_col;
varying float v_sand_mask;
varying float v_snow_pile;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += amp * value_noise(p);
		p *= 2.07;
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// COLOR.a packs coastal beach sand mask (0 = natural land, 1 = golden sandy beach/dune)
	v_sand_mask = clamp(COLOR.a, 0.0, 1.0);
	v_vert_col = COLOR.rgb;

	// Real vertex-displaced snow piling on upward-facing dry terrain above waterline
	float snow_pile = 0.0;
	if (weather_snow_depth > 0.01) {
		float above_w = smoothstep(water_level + 0.18, water_level + 0.85, wp.y);
		float up_w = smoothstep(0.45, 0.86, wn.y);
		float drift = value_noise(wp.xz * 0.065) * 0.65 + value_noise(wp.xz * 0.21) * 0.35;
		snow_pile = weather_snow_depth * above_w * up_w * mix(0.68, 1.25, drift) * (1.0 - weather_slush * 0.35);
		VERTEX.y += snow_pile * 0.22;
		wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	}
	v_snow_pile = snow_pile;
	v_world_pos = wp;
	v_world_normal = wn;
}

void fragment() {
	vec2 xz = v_world_pos.xz;
	float macro_n = fbm(xz * 0.045);
	float mid_n = value_noise(xz * 0.36) * 0.65 + value_noise(xz * 0.88) * 0.35;
	float fine_fw = max(fwidth(xz.x), fwidth(xz.y));
	float fine_fade = 1.0 - smoothstep(0.06, 0.28, fine_fw);
	float micro_n = mix(0.5, value_noise(xz * 4.8), fine_fade);

	float slope = 1.0 - clamp(v_world_normal.y, 0.0, 1.0);
	vec3 base_col = v_vert_col;

	// Natural grounded meadow/park turf variation: deep clover shadows, olive turf & sunlit dry grass
	vec3 lush_tint = base_col * vec3(0.76, 0.90, 0.72);
	vec3 dry_tint = base_col * vec3(1.06, 0.94, 0.72);
	vec3 col = mix(lush_tint, dry_tint, smoothstep(0.30, 0.76, macro_n));
	// Subtle organic soil/moss dapple to break up uniform urban grass parcels
	float patch_soil = smoothstep(0.70, 0.88, mid_n) * (1.0 - smoothstep(0.05, 0.22, slope));
	col = mix(col, vec3(0.24, 0.23, 0.17), patch_soil * 0.26);

	// Soft grass blade micro-variation
	float ds = detail_strength * 0.92;
	col *= mix(1.0 - ds, 1.0 + ds * 0.60, mid_n * 0.58 + micro_n * 0.42);

	// Stratified exposed soil & bedrock layers on steeper embankments and creek banks
	float rock_band = value_noise(vec2(xz.x * 0.22 + xz.y * 0.22, v_world_pos.y * 2.6));
	float rock_grit = value_noise(xz * 1.15) * 0.65 + value_noise(xz * 2.6) * 0.35;
	float steep_mask = smoothstep(0.08, 0.34, slope);
	vec3 rock_col = mix(vec3(0.28, 0.25, 0.22), vec3(0.46, 0.42, 0.36), rock_band * 0.6 + rock_grit * 0.4);
	col = mix(col, rock_col, steep_mask * 0.88 * (1.0 - v_sand_mask * 0.85));

	// Coastal golden beach sand + pulsing wet swash zone right along ocean surf run-up!
	float shore_dist = v_world_pos.y - water_level;
	float swash_wet = 0.0;
	if (v_sand_mask > 0.01) {
		float wind_ripple = sin(xz.x * 1.35 + xz.y * 0.45 + mid_n * 3.4) * 0.5 + 0.5;
		// True linear RGB golden coastal sand (prevents sRGB washout under bright sun!)
		vec3 dry_sand = mix(vec3(0.45, 0.35, 0.20), vec3(0.58, 0.46, 0.27), macro_n * 0.55 + wind_ripple * 0.45);
		dry_sand *= mix(0.92, 1.07, micro_n);
		float quartz_sparkle = smoothstep(0.88, 0.992, hash21(floor(xz * 26.0))) * fine_fade;
		dry_sand += vec3(0.09, 0.08, 0.05) * quartz_sparkle;
		// Pulsing surf wave swash memory darkening & glazing sand near waterline
		float swash_pulse = 0.16 * sin(TIME * 1.35 + xz.x * 0.055);
		swash_wet = (1.0 - smoothstep(-0.08, 0.94 + swash_pulse, shore_dist)) * v_sand_mask;
		vec3 wet_sand = dry_sand * vec3(0.42, 0.39, 0.34);
		vec3 sand_col = mix(dry_sand, wet_sand, clamp(swash_wet + weather_wetness * 0.60, 0.0, 1.0));
		col = mix(col, sand_col, v_sand_mask);
	}

	// Wet dark silt & shoreline mud sheen near creek water level + weather wetness
	float river_wet = (1.0 - smoothstep(-0.15, 0.62, shore_dist)) * (1.0 - v_sand_mask);
	float wet_mask = clamp(river_wet + swash_wet + weather_wetness * 0.68, 0.0, 1.0);
	float rain_pud = weather_puddles * (1.0 - steep_mask) * smoothstep(0.58, 0.78, mid_n);
	vec3 bank_mud = mix(col * vec3(0.50, 0.50, 0.44), vec3(0.21, 0.19, 0.16), 0.38 * river_wet);
	col = mix(col, bank_mud, clamp(river_wet + weather_wetness * 0.62 * (1.0 - v_sand_mask), 0.0, 1.0));

	// Submerged Seabed & Riverbed: wave-rippled sand bars, dancing underwater caustics & Beer-Lambert marine tint
	if (shore_dist < 0.02) {
		float sub_depth = clamp(-shore_dist, 0.0, 10.0);
		float sub_blend = smoothstep(-0.02, 0.32, sub_depth);
		// Wave-sculpted seafloor sand ripples parallel to coastline
		float sea_ripple = sin(xz.y * 4.2 + sin(xz.x * 0.38) * 2.2 + mid_n * 2.6) * 0.5 + 0.5;
		vec3 seabed_sand = mix(vec3(0.18, 0.24, 0.22), vec3(0.32, 0.36, 0.30), sea_ripple * 0.65 + macro_n * 0.35);
		col = mix(col, seabed_sand, sub_blend * (0.55 + v_sand_mask * 0.40));
		// Direct world-space animated underwater sun caustics (visible when swimming underwater AND from above!)
		vec2 cw_uv1 = xz * 0.48 + vec2(macro_n, mid_n) * 1.15 + vec2(0.12, -0.34) * TIME;
		vec2 cw_uv2 = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * (xz * 0.76 - vec2(mid_n, macro_n) * 0.85) + vec2(-0.18, -0.24) * TIME;
		float c_n1 = abs(value_noise(cw_uv1 * 2.2) - 0.5);
		float c_n2 = abs(value_noise(cw_uv2 * 2.4) - 0.5);
		float caust_net = pow(clamp(1.0 - (c_n1 + c_n2) * 2.1, 0.0, 1.0), 2.4);
		float caust_str = sub_blend * (1.0 - smoothstep(0.4, 7.5, sub_depth)) * (1.0 - night_factor * 0.88) * (1.0 - weather_cloud_cover * 0.55);
		col += vec3(0.16, 0.42, 0.46) * caust_net * caust_str * 1.35;
		// Depth-graded turquoise -> deep sapphire marine lighting absorption
		vec3 marine_tint = mix(vec3(0.05, 0.32, 0.38), vec3(0.012, 0.085, 0.19), smoothstep(0.5, 5.8, sub_depth)) * (1.0 - night_factor * 0.82);
		col = mix(col, marine_tint, clamp(sub_depth * 0.14, 0.0, 0.68));
	}

	// Dynamic Snow Piling & Accumulation with drifts, crystal micro-sparkles & slush melt edges
	float snow_cov = 0.0;
	if (weather_snow_depth > 0.01) {
		float above_w = smoothstep(water_level + 0.18, water_level + 0.78, v_world_pos.y);
		float drift_n = macro_n * 0.55 + mid_n * 0.45;
		float raw_s = weather_snow_depth * 1.48 * (1.0 - steep_mask * 0.75) * above_w - (1.0 - drift_n) * 0.36;
		snow_cov = clamp(smoothstep(0.04, 0.44, raw_s), 0.0, 1.0);
		vec3 fresh_snow = mix(vec3(0.84, 0.89, 0.96), vec3(0.96, 0.98, 1.00), smoothstep(0.22, 0.78, mid_n));
		vec3 slush_col = vec3(0.56, 0.60, 0.65);
		vec3 s_col = mix(fresh_snow, slush_col, weather_slush * 0.65);
		float snow_glint = smoothstep(0.90, 0.995, hash21(floor(xz * 22.0))) * fine_fade * (1.0 - weather_slush);
		s_col += vec3(0.28, 0.31, 0.36) * snow_glint;
		col = mix(col, s_col, snow_cov);
	}

	// Distance-gated analytical world-space bump perturbation (skips 3-tap noise on far terrain pixels)
	if (fine_fade > 0.02) {
		float eps = 0.20;
		float h_c = value_noise(xz * 1.7) * 0.65 + value_noise(xz * 3.8) * 0.35 + rock_band * steep_mask * 0.55;
		float h_x = value_noise((xz + vec2(eps, 0.0)) * 1.7) * 0.65 + value_noise((xz + vec2(eps, 0.0)) * 3.8) * 0.35;
		float h_z = value_noise((xz + vec2(0.0, eps)) * 1.7) * 0.65 + value_noise((xz + vec2(0.0, eps)) * 3.8) * 0.35;
		if (steep_mask > 0.02) {
			h_x += value_noise(vec2((xz.x + eps) * 0.22 + xz.y * 0.22, v_world_pos.y * 2.6)) * steep_mask * 0.55;
			h_z += value_noise(vec2(xz.x * 0.22 + (xz.y + eps) * 0.22, v_world_pos.y * 2.6)) * steep_mask * 0.55;
		}
		float bump_str = mix(0.28, 0.14, max(snow_cov * 0.85, v_sand_mask * 0.55));
		vec3 world_bump = vec3((h_c - h_x) * bump_str, 0.0, (h_c - h_z) * bump_str) * fine_fade * (1.0 - max(rain_pud * 0.78, swash_wet * 0.85));
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(world_bump, 0.0)).xyz);
	}

	float base_rough = mix(0.94, 0.84, v_sand_mask);
	float wet_rough = mix(mix(base_rough, 0.22, wet_mask * 0.88), 0.045, max(rain_pud, swash_wet * 0.85));
	float snow_rough = mix(0.76, 0.24, weather_slush);
	ALBEDO = col;
	ROUGHNESS = mix(wet_rough, snow_rough, snow_cov);
	METALLIC = 0.0;
	SPECULAR = mix(mix(mix(0.18, 0.70, wet_mask), 0.90, max(rain_pud, swash_wet)), mix(0.42, 0.78, weather_slush), snow_cov);
}
