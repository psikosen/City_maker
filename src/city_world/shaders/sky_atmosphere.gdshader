shader_type sky;
render_mode use_half_res_pass;

global uniform float night_factor;
global uniform float sun_elevation;
global uniform float weather_cloud_cover;
global uniform float weather_rain;
global uniform float weather_lightning;
global uniform vec2 wind_vector;
global uniform vec3 sun_direction;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 43.21);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float hash31(vec3 p) {
	p = fract(p * vec3(127.1, 311.7, 74.7));
	p += dot(p, p + 37.9);
	return fract(p.x * p.y * p.z);
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

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.52;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int i = 0; i < 4; i++) {
		v += amp * noise2d(p);
		p = rot * p * 2.04 + vec2(17.1, 31.7);
		amp *= 0.5;
	}
	return v;
}

float worley2(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float min_d = 1.6;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(n + g);
			vec2 r = g + o - f;
			min_d = min(min_d, dot(r, r));
		}
	}
	return clamp(1.0 - sqrt(min_d) * 0.85, 0.0, 1.0);
}

float hg_phase(float cos_theta, float g) {
	float g2 = g * g;
	return (1.0 - g2) / max(0.001, 4.0 * 3.1415926 * pow(1.0 + g2 - 2.0 * g * cos_theta, 1.5));
}

// Numerically stable ray distance (km) from ground to curved-earth atmospheric shell at altitude h_km
float ray_sphere_shell_km(float dir_y, float h_km) {
	const float R_EARTH_KM = 6371.0;
	float b = R_EARTH_KM * max(dir_y, 0.0);
	float c_term = h_km * (h_km + 2.0 * R_EARTH_KM);
	return c_term / max(0.0001, sqrt(b * b + c_term) + b);
}

float sample_cumulus_density(vec3 pos_km, float h_base, float h_top, float coverage, vec2 wind_drift) {
	float h_frac = clamp((pos_km.y - h_base) / max(0.05, h_top - h_base), 0.0, 1.0);
	// Soft anvil cloud base with tall puffy cauliflower cumulus towers
	float base_ramp = smoothstep(0.0, 0.26, h_frac);
	float top_taper = 1.0 - smoothstep(mix(0.45, 0.86, coverage), 1.0, h_frac);
	float height_env = base_ramp * top_taper;
	if (height_env < 0.004) {
		return 0.0;
	}

	// Wind shear tilts cumulus tops gently downwind
	vec2 p = pos_km.xz + wind_drift + wind_vector * (h_frac * 0.34);

	// Distinct scattered cumulus air-masses with bold Worley cauliflower billows
	float macro_raw = fbm(p * 0.21 + vec2(3.1, -5.4));
	float weather_macro = smoothstep(0.26, 0.68, macro_raw);
	float base_fbm = fbm(p * 0.44);
	float w1 = worley2(p * 0.72 + vec2(1.4, 2.2));
	float w2 = worley2(p * 1.55 - vec2(2.7, 1.1));
	float billow = smoothstep(0.24, 0.76, mix(base_fbm, w1 * 0.64 + w2 * 0.36, 0.58));
	float base_shape = clamp(mix(weather_macro, billow, 0.62), 0.0, 1.0);

	float anvil_bias = 1.0 - h_frac * 0.22;
	float shape_at_h = base_shape * anvil_bias;

	float thresh = mix(0.86, 0.16, clamp(coverage, 0.0, 1.0));
	float softness = mix(0.14, 0.24, coverage);
	float d = smoothstep(thresh - softness * 0.22, thresh + softness, shape_at_h) * height_env;

	if (d > 0.01) {
		float detail = fbm(p * 2.15 + vec2(8.3, -4.1));
		d = max(0.0, d - (1.0 - detail) * 0.30 * (1.0 - d * 0.40));
	}
	return d;
}

vec3 compute_sky_base(vec3 dir, vec3 sun_dir, vec3 moon_dir) {
	float y_up = clamp(dir.y, 0.0, 1.0);
	float horizon = pow(1.0 - y_up, 3.4);
	float day_blend = smoothstep(-0.14, 0.24, sun_elevation);
	float sunset_band = smoothstep(-0.16, 0.03, sun_elevation) * (1.0 - smoothstep(0.06, 0.38, sun_elevation));

			// Clear daytime Rayleigh palette (rich blue sky above crisp horizon glow)
			vec3 day_zenith = vec3(0.08, 0.31, 0.85);
			vec3 day_horizon = vec3(0.45, 0.72, 0.96);

	// Golden hour / twilight scatter gradient
	float sun_cos = dot(dir, sun_dir);
	float sun_fwd = pow(max(sun_cos, 0.0), 3.0);
	vec3 dusk_zenith = vec3(0.08, 0.13, 0.34);
	vec3 dusk_horizon = mix(vec3(0.36, 0.32, 0.49), vec3(1.18, 0.46, 0.19), 0.45 + 0.55 * sun_fwd);

	// Midnight sky base
	vec3 night_zenith = vec3(0.006, 0.011, 0.025);
	vec3 night_horizon = vec3(0.018, 0.029, 0.056);

	vec3 clear_zenith = mix(night_zenith, day_zenith, day_blend);
	vec3 clear_horizon = mix(night_horizon, day_horizon, day_blend);
	clear_zenith = mix(clear_zenith, dusk_zenith, sunset_band * 0.78);
	clear_horizon = mix(clear_horizon, dusk_horizon, sunset_band * 0.92);

	vec3 col = mix(clear_zenith, clear_horizon, horizon);

	// Solar Mie glow
	if (sun_elevation > -0.18) {
		float mie = hg_phase(sun_cos, 0.78) * 0.44;
		vec3 mie_col = mix(vec3(1.25, 0.56, 0.22), vec3(1.06, 0.97, 0.84), smoothstep(-0.05, 0.32, sun_elevation));
		col += mie_col * mie * (1.0 - smoothstep(0.42, 0.96, weather_cloud_cover) * 0.82) * smoothstep(-0.18, 0.08, sun_elevation);
	}

	// Lunar scatter glow
	float moon_cos = dot(dir, moon_dir);
	if (moon_dir.y > -0.12) {
		float moon_halo = pow(max(moon_cos, 0.0), 22.0) * 0.14;
		col += vec3(0.32, 0.45, 0.68) * moon_halo * night_factor * (1.0 - smoothstep(0.45, 0.95, weather_cloud_cover) * 0.75);
	}

	// Only shift sky base toward overcast slate when cloud cover actually approaches overcast/storm
	float storm_veil = smoothstep(0.56, 0.96, weather_cloud_cover);
	vec3 storm_day = mix(vec3(0.28, 0.34, 0.42), vec3(0.43, 0.48, 0.55), horizon);
	vec3 storm_night = mix(vec3(0.014, 0.020, 0.034), vec3(0.052, 0.046, 0.042), horizon);
	vec3 storm_sky = mix(storm_night, storm_day, day_blend);
	col = mix(col, storm_sky, storm_veil * 0.88);

	// Subtle warm urban dome glow near horizon at night
	col += vec3(0.065, 0.045, 0.024) * horizon * night_factor * (0.35 + 0.65 * weather_cloud_cover);

	// Lightning sheet flash illuminating sky & cloud dome
	col += vec3(0.68, 0.78, 1.05) * weather_lightning * (0.32 + 0.45 * storm_veil);

	// Lower hemisphere ground reflection continuity (keeps IBL & glass crisp)
	if (dir.y < 0.0) {
		vec3 ground_b = mix(vec3(0.022, 0.026, 0.036), vec3(0.22, 0.25, 0.28), day_blend * (1.0 - storm_veil * 0.45));
		col = mix(col, ground_b, smoothstep(0.0, -0.35, dir.y));
	}
	return max(col, vec3(0.0));
}

float star_layer(vec3 dir, float scale, float threshold) {
	vec3 cell = floor(dir * scale);
	float h = hash31(cell);
	if (h < threshold) {
		return 0.0;
	}
	vec3 center = normalize(cell + 0.5 + (vec3(hash31(cell + 1.1), hash31(cell + 2.3), hash31(cell + 3.7)) - 0.5) * 0.55);
	float ang = max(0.0, 1.0 - dot(dir, center));
	float size = 0.0000075 * (320.0 / scale);
	float core = pow(clamp(1.0 - ang / size, 0.0, 1.0), 2.6);
	float twinkle = 0.72 + 0.28 * sin(TIME * (1.8 + h * 3.5) + h * 51.0);
	return core * twinkle;
}

void sky() {
	vec3 dir = normalize(EYEDIR);

	vec3 sun_dir = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION) : normalize(sun_direction);
	vec3 moon_dir = LIGHT1_ENABLED ? normalize(LIGHT1_DIRECTION) : -sun_dir;

	if (AT_CUBEMAP_PASS) {
		vec3 cubemap_sky = compute_sky_base(dir, sun_dir, moon_dir);
		if (dir.y > 0.02 && weather_cloud_cover > 0.08) {
			float day_blend = smoothstep(-0.14, 0.24, sun_elevation);
			float sunset_band = smoothstep(-0.16, 0.03, sun_elevation) * (1.0 - smoothstep(0.06, 0.38, sun_elevation));
			vec3 c_fill = mix(vec3(0.06, 0.08, 0.13), vec3(0.76, 0.80, 0.86), day_blend);
			c_fill = mix(c_fill, vec3(0.88, 0.52, 0.36), sunset_band * 0.55);
			c_fill = mix(c_fill, vec3(0.32, 0.36, 0.42), weather_rain * 0.6);
			cubemap_sky = mix(cubemap_sky, c_fill, weather_cloud_cover * 0.32);
		}
		COLOR = cubemap_sky;
	} else if (AT_HALF_RES_PASS) {
		if (dir.y <= 0.004 || weather_cloud_cover < 0.02) {
			COLOR = vec3(0.0);
			ALPHA = 0.0;
		} else {
			vec3 light_dir = (sun_elevation > -0.04) ? sun_dir : moon_dir;

			float day_blend = smoothstep(-0.14, 0.24, sun_elevation);
			float sunset_band = smoothstep(-0.16, 0.03, sun_elevation) * (1.0 - smoothstep(0.06, 0.38, sun_elevation));
			float cos_l = dot(dir, light_dir);
			float phase = mix(hg_phase(cos_l, 0.62), hg_phase(cos_l, -0.22), 0.32) * 3.8;

			// Atmospheric horizon light tint for aerial perspective fade
			vec3 sky_horizon_col = compute_sky_base(normalize(vec3(dir.x, 0.06, dir.z)), sun_dir, moon_dir);

			vec3 cloud_lit = mix(vec3(0.16, 0.21, 0.32), vec3(1.18, 1.15, 1.09), day_blend);
			cloud_lit = mix(cloud_lit, vec3(1.38, 0.66, 0.34), sunset_band * (0.42 + 0.58 * max(dot(dir, sun_dir), 0.0)));
			cloud_lit *= mix(1.0, 0.52, weather_rain * 0.72);

			vec3 cloud_dark = mix(vec3(0.022, 0.032, 0.056), vec3(0.30, 0.38, 0.52), day_blend);
			cloud_dark = mix(cloud_dark, vec3(0.42, 0.30, 0.38), sunset_band * 0.55);
			cloud_dark = mix(cloud_dark, vec3(0.14, 0.17, 0.22), weather_rain * 0.72);

			const float H_BASE = 1.45;
			const float H_TOP = 3.25;
			float t0 = ray_sphere_shell_km(dir.y, H_BASE);
			float t1 = min(ray_sphere_shell_km(dir.y, H_TOP), t0 + 14.0);

			vec2 drift_cum = wind_vector * (TIME * 0.038);
			float horizon_dist_atten = smoothstep(0.004, 0.060, dir.y) * exp(-max(t0 - 15.0, 0.0) * 0.035);

			vec3 accum_col = vec3(0.0);
			float trans = 1.0;

			// 16-step jittered volumetric march eliminates any horizontal banding while keeping 3D cloud volumes
			if (t0 < 38.0 && horizon_dist_atten > 0.005) {
				const int STEPS = 20;
				float dt = max(0.04, (t1 - t0) / float(STEPS));
				float ray_jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
				for (int i = 0; i < STEPS; i++) {
					if (trans < 0.03) {
						break;
					}
					float t_cur = t0 + (float(i) + ray_jitter) * dt;
					vec3 p_km = dir * t_cur;
					float d = sample_cumulus_density(p_km, H_BASE, H_TOP, weather_cloud_cover, drift_cum);
					if (d > 0.008) {
						// 3-step light march toward sun/moon for genuine lit tops & shaded cloud bellies
						float od = 0.0;
						vec3 l_step = light_dir * 0.38;
						for (int li = 1; li <= 3; li++) {
							vec3 lp = p_km + l_step * float(li);
							od += sample_cumulus_density(lp, H_BASE, H_TOP, weather_cloud_cover, drift_cum) * (0.55 + float(li) * 0.20);
						}

						float beer = exp(-od * mix(1.95, 2.65, weather_rain));
						float powder = 1.0 - exp(-d * 2.8);
						float light_energy = mix(0.16, 1.0, clamp(beer * mix(0.65, 1.30, powder), 0.0, 1.0));
						float h_top_lift = clamp((p_km.y - H_BASE) / (H_TOP - H_BASE), 0.0, 1.0);

						vec3 step_col = mix(cloud_dark, cloud_lit, clamp(light_energy * (0.68 + 0.40 * h_top_lift), 0.0, 1.0));
						// Forward scattering silver lining around sun/moon
						step_col += cloud_lit * phase * beer * 0.30 * mix(0.25, 1.0, day_blend + night_factor * 0.25);

						// Thunderstorm internal cell flashes
						if (weather_lightning > 0.01) {
							float cell_glow = smoothstep(0.25, 0.85, fbm(p_km.xz * 0.75 + drift_cum * 1.3));
							step_col += vec3(0.76, 0.88, 1.25) * weather_lightning * (0.45 + 1.55 * cell_glow);
						}

						float step_sigma = d * mix(1.25, 1.85, weather_cloud_cover) * horizon_dist_atten;
						float step_alpha = 1.0 - exp(-step_sigma * dt * 1.05);
						step_col = mix(sky_horizon_col, step_col, exp(-t_cur * 0.016));
						accum_col += trans * step_col * step_alpha;
						trans *= (1.0 - step_alpha);
					}
				}
			}

			// High-altitude wispy cirrus layer at ~6.8km (softly faded near low horizon to prevent banding)
			if (trans > 0.08 && dir.y > 0.08) {
				float t_cir = ray_sphere_shell_km(dir.y, 6.8);
				vec2 c_uv = dir.xz * t_cir * 0.085 + drift_cum * 0.55;
				vec2 shear = mat2(vec2(0.92, 0.38), vec2(-0.34, 0.94)) * c_uv;
				float c_band = clamp((fbm(shear * vec2(1.0, 1.35)) - 0.30) / 0.44, 0.0, 1.0);
				float c_detail = fbm(shear * vec2(2.1, 2.8) + vec2(5.1, -3.4));
				float cir_cov = smoothstep(0.42, 0.82, c_band * 0.70 + c_detail * 0.30);
				float cir_fade = smoothstep(0.08, 0.24, dir.y) * mix(0.55, 0.18, weather_cloud_cover);
				float cir_alpha = cir_cov * cir_fade * (0.35 + 0.65 * clamp(weather_cloud_cover * 2.0, 0.0, 1.0));
				vec3 cir_col = mix(vec3(0.24, 0.30, 0.44), vec3(1.08, 1.05, 1.01), day_blend);
				cir_col = mix(cir_col, vec3(1.25, 0.68, 0.42), sunset_band * 0.72);
				cir_col += cloud_lit * hg_phase(cos_l, 0.68) * 0.35 * day_blend;
				accum_col += trans * cir_col * cir_alpha;
				trans *= (1.0 - cir_alpha);
			}

			float out_alpha = clamp(1.0 - trans, 0.0, 0.985);
			COLOR = accum_col;
			ALPHA = out_alpha;
		}
	} else {
		// Full-resolution sky dome
		vec3 sky_col = compute_sky_base(dir, sun_dir, moon_dir);
		float cloud_occlude = HALF_RES_COLOR.a;

		// Stars + subtle Milky Way dust band visible once twilight deepens into night
		if (dir.y > 0.0 && night_factor > 0.28) {
			float vis_star = smoothstep(0.28, 0.80, night_factor) * smoothstep(0.0, 0.28, dir.y) * (1.0 - smoothstep(0.15, 0.72, cloud_occlude));
			float s1 = star_layer(dir, 210.0, 0.992);
			float s2 = star_layer(dir, 390.0, 0.9955) * 0.65;
			float tint = hash31(floor(dir * 210.0) + 9.2);
			vec3 star_col = mix(vec3(0.78, 0.88, 1.0), vec3(1.0, 0.92, 0.78), tint);
			float milky = pow(max(0.0, 1.0 - abs(dot(dir, normalize(vec3(0.55, 0.45, -0.70))))), 3.0);
			float mw_noise = fbm(dir.xz / (dir.y + 0.5) * 2.2);
			sky_col += vec3(0.020, 0.028, 0.048) * milky * mw_noise * vis_star;
			sky_col += star_col * (s1 + s2) * 1.8 * vis_star;
		}

		// Sun disk
		if (LIGHT0_ENABLED && sun_elevation > -0.06) {
			vec3 sun_dir = normalize(LIGHT0_DIRECTION);
			float d_sun = dot(dir, sun_dir);
			float sun_disk = smoothstep(0.99935, 0.99968, d_sun);
			vec3 disk_col = mix(vec3(4.2, 1.4, 0.45), vec3(5.5, 5.1, 4.4), smoothstep(-0.02, 0.28, sun_elevation));
			sky_col += disk_col * sun_disk * (1.0 - smoothstep(0.30, 0.85, cloud_occlude)) * (1.0 - weather_rain * 0.8);
		}

		// Moon disk with subtle crater texture & silver rim
		if (LIGHT1_ENABLED || night_factor > 0.05) {
			vec3 sun_dir = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION) : normalize(sun_direction);
			vec3 moon_dir = LIGHT1_ENABLED ? normalize(LIGHT1_DIRECTION) : -sun_dir;
			if (moon_dir.y > -0.05) {
				float d_moon = dot(dir, moon_dir);
				float moon_r = 0.99925;
				float moon_mask = smoothstep(moon_r, moon_r + 0.00018, d_moon);
				if (moon_mask > 0.001) {
					vec3 up_ref = abs(moon_dir.y) > 0.92 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
					vec3 m_t = normalize(cross(up_ref, moon_dir));
					vec3 m_b = cross(moon_dir, m_t);
					vec2 m_uv = vec2(dot(dir - moon_dir, m_t), dot(dir - moon_dir, m_b)) * 32.0;
					float maria = fbm(m_uv * 1.4 + vec2(3.1, 1.7));
					float phase_shade = smoothstep(-0.35, 0.25, m_uv.x * 0.75 + m_uv.y * 0.25);
					vec3 moon_tex = mix(vec3(0.48, 0.52, 0.60), vec3(0.96, 0.98, 1.04), maria) * mix(0.28, 1.15, phase_shade);
					float moon_vis = clamp(night_factor * 1.1 + 0.12, 0.0, 1.0) * (1.0 - smoothstep(0.30, 0.85, cloud_occlude));
					sky_col = mix(sky_col, moon_tex * 1.35, moon_mask * moon_vis);
				}
			}
		}

		// Composite half-resolution premultiplied volumetric cloud deck
		sky_col = sky_col * (1.0 - HALF_RES_COLOR.a) + HALF_RES_COLOR.rgb;
		COLOR = sky_col;
	}
}
