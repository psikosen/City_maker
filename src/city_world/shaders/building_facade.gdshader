shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

instance uniform vec3 wall_color : source_color = vec3(-1.0, -1.0, -1.0);
uniform int style_mode = 0; // 0: historic_brick, 1: contemporary_2028, 2: suburban_siding, 3: industrial_steel

global uniform float weather_wetness;
global uniform float weather_rain;
global uniform float weather_snow_depth;
global uniform float weather_slush;

varying vec3 v_local_pos;
varying vec3 v_local_normal;

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

// Analytical derivative-filtered pulse in [0, 1] cell coordinates to prevent moire at distance.
float aa_interior_mask(float t, float border, float fw) {
	float w = max(border * 0.5, fw * 0.85);
	float lo = smoothstep(border - w, border + w, t);
	float hi = smoothstep(border - w, border + w, 1.0 - t);
	return lo * hi;
}

void vertex() {
	v_local_pos = VERTEX;
	v_local_normal = NORMAL;
}

void fragment() {
	vec3 an = abs(v_local_normal);
	vec2 uv_wall = (an.x > an.z) ? v_local_pos.zy : v_local_pos.xy;
	if (an.y > an.x && an.y > an.z) {
		uv_wall = v_local_pos.xz;
	}

	vec3 eff_wall_color = (wall_color.r >= 0.0) ? wall_color : ((COLOR.r + COLOR.g + COLOR.b < 2.98) ? COLOR.rgb : vec3(0.80, 0.79, 0.76));
	vec3 col = eff_wall_color;
	float rough = 0.85;
	float metal = 0.0;
	vec3 local_bump = vec3(0.0);

	// Ground-splash darkening near sidewalk level (local y in [0, 1.35]) + roofline rainwater runoff & sill drip stains
	float base_ao = smoothstep(-0.2, 1.35, v_local_pos.y);
	float rain_streak = noise2d(vec2(uv_wall.x * 1.4, uv_wall.y * 0.08));
	float fine_streak = noise2d(vec2(uv_wall.x * 4.8 + 13.7, uv_wall.y * 0.14));
	float sill_wash = noise2d(vec2(uv_wall.x * 2.1, uv_wall.y * 0.28 + 4.3));
	// Periodic floor-level subtle drip staining (~3.4m intervals) + macro tonal weathering patches
	float floor_band = fract(max(0.0, v_local_pos.y - 0.6) / 3.4);
	float under_sill_drip = exp(-floor_band * 5.2) * smoothstep(0.42, 0.85, fine_streak) * smoothstep(1.2, 3.0, v_local_pos.y);
	float macro_age = noise2d(uv_wall * 0.12 + vec2(3.1, 7.4));
	float grime = mix(0.75, 1.0, base_ao)
		* mix(0.90, 1.04, sill_wash * 0.50 + rain_streak * 0.35 + macro_age * 0.15)
		* (1.0 - under_sill_drip * 0.10);

	// Subtle horizontal stone/concrete water-table plinth darkening along very bottom 0.45m of masonry/siding
	float plinth_band = 1.0 - smoothstep(0.36, 0.48, v_local_pos.y);
	float plinth_blend = (style_mode == 0 || style_mode == 2) ? plinth_band * 0.24 : plinth_band * 0.14;

	if (style_mode == 0) {
		// Historic running-bond brick with derivative-filtered mortar (zero distance moire)
		vec2 brick_size = vec2(0.24, 0.085);
		float row = floor(uv_wall.y / brick_size.y);
		float x_off = mod(row, 2.0) * 0.5;
		vec2 b_uv = vec2(uv_wall.x / brick_size.x + x_off, uv_wall.y / brick_size.y);
		vec2 cell = fract(b_uv);
		vec2 bid = floor(b_uv);
		vec2 fw = max(fwidth(uv_wall / brick_size), vec2(0.001));
		float detail_fade = 1.0 - smoothstep(0.22, 0.65, max(fw.x, fw.y));

		float mortar_x = aa_interior_mask(cell.x, 0.06, fw.x);
		float mortar_y = aa_interior_mask(cell.y, 0.12, fw.y);
		float brick_mask = mix(0.86, mortar_x * mortar_y, detail_fade);

		float b_rand = hash21(bid);
		vec3 brick_col = eff_wall_color * mix(0.82, 1.18, b_rand);
		brick_col *= mix(0.93, 1.06, noise2d(uv_wall * 9.0));
		// Subtle darker soot/iron bricks scattered occasionally
		brick_col = mix(brick_col, eff_wall_color * 0.66, step(0.88, hash21(bid + 7.3)) * 0.55);

		vec3 mortar_col = mix(vec3(0.55, 0.52, 0.48), eff_wall_color * 0.72, 0.25);
		vec3 avg_brick = mix(mortar_col, eff_wall_color, 0.85);
		col = mix(avg_brick, mix(mortar_col, brick_col, brick_mask), mix(0.25, 1.0, detail_fade)) * grime;
		rough = mix(0.95, 0.84, brick_mask);

		if (detail_fade > 0.01) {
			float dx = (smoothstep(0.0, 0.08, cell.x) - smoothstep(0.0, 0.08, 1.0 - cell.x)) * (1.0 - brick_mask);
			float dy = (smoothstep(0.0, 0.14, cell.y) - smoothstep(0.0, 0.14, 1.0 - cell.y)) * (1.0 - brick_mask);
			local_bump = vec3(dx * 0.28, dy * 0.34, 0.0) * detail_fade;
		}
	} else if (style_mode == 1) {
		// Contemporary 2028 architectural fiber-cement & composite cladding panels
		vec2 panel_size = vec2(2.2, 1.55);
		vec2 p_uv = uv_wall / panel_size;
		vec2 cell = fract(p_uv);
		vec2 pid = floor(p_uv);
		vec2 fw = max(fwidth(p_uv), vec2(0.001));
		float detail_fade = 1.0 - smoothstep(0.3, 0.8, max(fw.x, fw.y));

		float seam_x = aa_interior_mask(cell.x, 0.013, fw.x);
		float seam_y = aa_interior_mask(cell.y, 0.018, fw.y);
		float panel_mask = mix(0.96, seam_x * seam_y, detail_fade);

		float p_var = hash21(pid);
		float micro_grain = noise2d(uv_wall * 3.5);
		vec3 panel_col = eff_wall_color * mix(0.93, 1.05, p_var) * mix(0.95, 1.04, micro_grain);
		col = mix(eff_wall_color * 0.40, panel_col, panel_mask) * grime;
		rough = mix(0.84, mix(0.46, 0.62, micro_grain), panel_mask);
		metal = 0.14 * panel_mask;

		if (detail_fade > 0.01) {
			float bx_bevel = (smoothstep(0.0, 0.032, cell.x) - smoothstep(0.0, 0.032, 1.0 - cell.x)) * (1.0 - panel_mask);
			float by_bevel = (smoothstep(0.0, 0.040, cell.y) - smoothstep(0.0, 0.040, 1.0 - cell.y)) * (1.0 - panel_mask);
			float grain_dx = micro_grain - noise2d((uv_wall + vec2(0.05, 0.0)) * 3.5);
			float grain_dy = micro_grain - noise2d((uv_wall + vec2(0.0, 0.05)) * 3.5);
			local_bump = vec3(bx_bevel * 0.24 + grain_dx * 0.06, by_bevel * 0.26 + grain_dy * 0.06, 0.0) * detail_fade;
		}
	} else if (style_mode == 2) {
		// Suburban horizontal clapboard lap siding with crisp under-shadow
		float course_h = 0.18;
		float v_uv = uv_wall.y / course_h;
		float fy = fract(v_uv);
		float row = floor(v_uv);
		float fw_y = max(fwidth(v_uv), 0.001);
		float detail_fade = 1.0 - smoothstep(0.25, 0.72, fw_y);

		float plank_var = hash21(vec2(row, floor(uv_wall.x * 0.25)));
		float grain = noise2d(vec2(uv_wall.x * 4.0, uv_wall.y * 16.0));
		float lap_shadow = mix(0.92, smoothstep(0.0, max(0.14, fw_y * 1.4), fy), detail_fade);
		col = eff_wall_color * mix(0.94, 1.05, plank_var) * mix(0.95, 1.04, grain);
		col *= mix(0.68, 1.04, lap_shadow) * grime;
		rough = 0.76;
		local_bump = vec3(0.0, (0.5 - fy) * 0.18 * detail_fade, 0.0);
	} else {
		// Industrial corrugated metal cladding above 1.8m precast concrete dado base
		float dado = smoothstep(1.65, 1.85, v_local_pos.y);
		float rib_u = uv_wall.x * 4.2;
		float fw_rib = fwidth(rib_u);
		float rib_fade = 1.0 - smoothstep(0.25, 0.75, fw_rib);
		float rib_phase = rib_u * 6.2831853;
		float rib = mix(0.5, sin(rib_phase) * 0.5 + 0.5, rib_fade);
		float rib_slope = cos(rib_phase) * rib_fade;

		vec3 metal_col = eff_wall_color * mix(0.82, 1.14, rib);
		vec3 dado_col = vec3(0.46, 0.47, 0.48) * mix(0.92, 1.07, noise2d(uv_wall * 3.2));
		col = mix(dado_col, metal_col, dado) * grime;
		rough = mix(0.88, 0.40, dado);
		metal = mix(0.0, 0.48, dado);
		local_bump = vec3(rib_slope * 0.28 * dado, 0.0, 0.0);
	}

	// Subtle stone/concrete ground plinth tint along the base 0.45m (heavy-to-light vertical grounding)
	col = mix(col, vec3(0.36, 0.35, 0.34) * mix(0.92, 1.06, noise2d(uv_wall * 3.8)), plinth_blend);
	rough = clamp(rough + (1.0 - grime) * 0.14 + plinth_blend * 0.12, 0.18, 0.98);

	if (dot(local_bump, local_bump) > 0.00001) {
		vec3 tangent_u = (an.x > an.z) ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
		vec3 tangent_v = vec3(0.0, 1.0, 0.0);
		vec3 local_n_off = tangent_u * local_bump.x + tangent_v * local_bump.y;
		vec3 world_n_off = (MODEL_MATRIX * vec4(local_n_off, 0.0)).xyz;
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(world_n_off, 0.0)).xyz);
	}

	// Rain-soaked exterior masonry/cladding darkening + snow ledges on sills/cornices/parapets
	float drip = noise2d(vec2(uv_wall.x * 3.8, uv_wall.y * 0.45 + TIME * (weather_rain > 0.02 ? 0.85 : 0.0)));
	float wet_wall = weather_wetness * mix(0.68, 1.0, drip);
	col *= mix(1.0, 0.72, wet_wall);
	rough = mix(rough, max(0.18, rough * 0.42), wet_wall);

	float ledge_snow = 0.0;
	if (weather_snow_depth > 0.01) {
		float up_ledge = smoothstep(0.48, 0.86, v_local_normal.y);
		float base_drift = (1.0 - smoothstep(0.0, 0.55, v_local_pos.y)) * 0.35;
		ledge_snow = clamp((up_ledge + base_drift) * weather_snow_depth * 1.25 * (1.0 - weather_slush * 0.35), 0.0, 0.96);
		vec3 s_col = mix(vec3(0.88, 0.92, 0.97), vec3(0.60, 0.64, 0.69), weather_slush * 0.60);
		col = mix(col, s_col, ledge_snow);
		rough = mix(rough, mix(0.76, 0.26, weather_slush), ledge_snow);
		metal *= (1.0 - ledge_snow);
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = mix(mix(0.50, 0.80, wet_wall), 0.44, ledge_snow);
}
