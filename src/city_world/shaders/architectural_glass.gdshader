shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 glass_tint : source_color = vec3(0.06, 0.11, 0.17);
uniform vec3 interior_light_color : source_color = vec3(1.0, 0.84, 0.58);
uniform float interior_glow = 0.22;
uniform float reflection_strength = 0.72;

global uniform float time_of_day_hour;
global uniform float night_factor;
global uniform float weather_cloud_cover;
global uniform float weather_rain;
global uniform float weather_lightning;

varying vec3 v_local_normal;
varying vec3 v_local_ray;
varying vec4 v_vert_col;

float hash21(vec2 p) {
	p = fract(p * vec2(123.4, 789.1));
	p += dot(p, p + 45.2);
	return fract(p.x * p.y);
}

void vertex() {
	v_local_normal = normalize(NORMAL);
	v_vert_col = COLOR;
	vec3 cam_world = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_ray = world_pos - cam_world;
	v_local_ray = (inverse(MODEL_MATRIX) * vec4(world_ray, 0.0)).xyz;
}

void fragment() {
	vec3 n_loc = normalize(v_local_normal);
	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 4.0);

	// Horizontal glass panes (e.g. vestibule ceiling fixture) render cleanly without wall parallax.
	if (abs(n_loc.y) > 0.7) {
		float eff_ceil_glow = interior_glow + night_factor * 0.85;
		ALBEDO = glass_tint * 0.4 + interior_light_color * eff_ceil_glow;
		EMISSION = interior_light_color * eff_ceil_glow * 1.45;
		ROUGHNESS = 0.12;
		METALLIC = 0.1;
	} else {
		// Build outward facade orthonormal tangent frame (T horizontal, B vertical, N outward).
		vec3 up_ref = vec3(0.0, 1.0, 0.0);
		vec3 t_dir = normalize(cross(up_ref, n_loc));
		vec3 b_dir = cross(n_loc, t_dir);
		vec3 ray_loc = normalize(v_local_ray);

		// Use per-window normalized bay UVs [0..cols, 0..rows] so rooms never split mid-pane.
		vec2 bay_id = floor(UV);
		vec2 bay_uv = fract(UV);
		vec2 f_uv = vec2(bay_uv.x * 2.0 - 1.0, (1.0 - bay_uv.y) * 2.0 - 1.0);

		// Slim outer aluminum gasket frame on each pane
		float edge_x = min(bay_uv.x, 1.0 - bay_uv.x);
		float edge_y = min(bay_uv.y, 1.0 - bay_uv.y);
		float frame_mask = smoothstep(0.018, 0.032, min(edge_x, edge_y));

		// Trace ray inward into room box [-1..1, -1..1, depth=1.35]
		float r_u = dot(ray_loc, t_dir);
		float r_v = dot(ray_loc, b_dir);
		float r_n = min(-0.08, dot(ray_loc, n_loc));
		vec3 r_room = vec3(r_u, r_v, -r_n);

		float depth_room = 1.35;
		float t_back = depth_room / max(0.05, r_room.z);
		float sx = r_room.x >= 0.0 ? 1.0 : -1.0;
		float sy = r_room.y >= 0.0 ? 1.0 : -1.0;
		float t_x = abs((sx - f_uv.x) / max(0.002, abs(r_room.x)));
		float t_y = abs((sy - f_uv.y) / max(0.002, abs(r_room.y)));
		float t_hit = min(t_back, min(t_x, t_y));
		vec3 hit = vec3(f_uv, 0.0) + r_room * t_hit;

		// Stable room seed per window (COLOR.r = seed, COLOR.g = is_wide, COLOR.b = floor_norm).
		float pane_seed = hash21(bay_id + vec2(v_vert_col.r * 37.0, 11.3));
		float is_wide = v_vert_col.g;
		float floor_norm = v_vert_col.b;
		bool is_retail = floor_norm < 0.02;
		float depth_atten = exp(-hit.z * 0.58);

		vec3 ceiling_col = vec3(0.24, 0.25, 0.27);
		vec3 floor_col = vec3(0.09, 0.08, 0.07);
		vec3 wall_palette = mix(vec3(0.18, 0.20, 0.23), interior_light_color * 0.76, 0.25 + 0.55 * pane_seed);
		if (is_retail) {
			wall_palette = mix(vec3(0.26, 0.24, 0.22), interior_light_color * 0.92, 0.55 + 0.35 * pane_seed);
		}
		vec3 room_col = wall_palette;
		float emit_amt = 0.0;

		if (t_y < t_x && t_y < t_back && hit.y > 0.0) {
			// Ceiling plane with twin recessed LED panels (or retail showcase spotlights)
			float led_x = smoothstep(0.18, 0.06, abs(abs(hit.x) - 0.42));
			float led_z = smoothstep(0.12, 0.25, hit.z) * smoothstep(1.25, 0.95, hit.z);
			float led = led_x * led_z;
			room_col = mix(ceiling_col, interior_light_color * (is_retail ? 1.85 : 1.45), led);
			emit_amt = led * (is_retail ? 1.25 : 0.95);
		} else if (t_y < t_x && t_y < t_back && hit.y < 0.0) {
			// Interior floor with subtle corner AO
			float ao = smoothstep(1.35, 0.7, hit.z);
			room_col = floor_col * mix(0.65, 1.0, ao);
		} else if (t_back <= t_x && t_back <= t_y) {
			// Back interior wall with retail shelving/display or desk/bookshelf silhouette
			float furn_band = 1.0 - smoothstep(-0.35, -0.15, hit.y);
			float shelf_freq = is_retail ? 3.2 : 2.1;
			float shelf = step(0.16, fract(hit.x * shelf_freq + pane_seed)) * smoothstep(-0.25, 0.35, hit.y) * (1.0 - smoothstep(0.35, 0.55, hit.y));
			room_col = wall_palette * mix(1.0, 0.42, furn_band * 0.7 + shelf * 0.38);
			float wall_grad = smoothstep(-0.8, 0.9, hit.y);
			room_col *= mix(0.65, 1.15, wall_grad);
			emit_amt = wall_grad * (is_retail ? 0.62 : 0.35);
		} else {
			// Side interior return walls
			float wall_grad = smoothstep(-0.9, 0.9, hit.y);
			room_col = wall_palette * 0.78 * mix(0.65, 1.05, wall_grad);
			emit_amt = wall_grad * (is_retail ? 0.38 : 0.22);
		}

		// Mid-plane furniture / retail display / partition silhouette at z = 0.64 for multi-layer parallax
		float t_mid = 0.64 / max(0.05, r_room.z);
		if (t_mid < t_hit) {
			vec3 hit_mid = vec3(f_uv, 0.0) + r_room * t_mid;
			if (abs(hit_mid.x) < 0.96 && abs(hit_mid.y) < 0.96) {
				if (is_retail) {
					float table_hit = (1.0 - smoothstep(-0.48, -0.34, hit_mid.y)) * step(abs(hit_mid.x), 0.62);
					float rack_hit = smoothstep(0.18, 0.24, abs(hit_mid.x - (pane_seed - 0.5) * 0.6)) * (1.0 - step(0.32, abs(hit_mid.x - (pane_seed - 0.5) * 0.6))) * smoothstep(-0.6, 0.28, hit_mid.y) * (1.0 - smoothstep(0.28, 0.35, hit_mid.y));
					float mid_mask = max(table_hit, rack_hit);
					room_col = mix(room_col, vec3(0.08, 0.07, 0.07), mid_mask * 0.72);
				} else {
					float desk = (1.0 - smoothstep(-0.55, -0.40, hit_mid.y)) * step(abs(hit_mid.x), 0.72);
					float monitor = step(abs(hit_mid.x - (pane_seed - 0.5) * 0.5), 0.24) * smoothstep(-0.42, -0.36, hit_mid.y) * (1.0 - smoothstep(-0.08, -0.02, hit_mid.y));
					room_col = mix(room_col, vec3(0.05, 0.06, 0.08), desk * 0.75);
					if (monitor > 0.5) {
						vec3 scr_col = mix(vec3(0.28, 0.58, 0.95), vec3(0.85, 0.68, 0.42), fract(pane_seed * 13.7));
						room_col = mix(room_col, scr_col * 0.85, 0.85);
						emit_amt += 0.55 * step(0.60, pane_seed);
					}
				}
			}
		}

		// Venetian blinds / partial curtains on ~45% of upper non-wide residential/office panes
		float blind_mask = 0.0;
		if (!is_retail && is_wide < 0.5 && pane_seed > 0.54) {
			float drop_h = 0.25 + 0.52 * fract(pane_seed * 7.31);
			if (bay_uv.y < drop_h) {
				float slat = 0.65 + 0.35 * sin(bay_uv.y * 92.0);
				blind_mask = 0.72 * slat;
				room_col = mix(room_col, mix(vec3(0.26, 0.24, 0.22), interior_light_color * 0.65, night_factor * 0.6), blind_mask);
			}
		}

		// Diurnal time-of-day occupancy & color temperature shift synchronized with NPC schedules
		float hr = mod(time_of_day_hour, 24.0);
		float room_rand = hash21(bay_id + vec2(v_vert_col.r * 19.0, 5.7));
		float sleep_rand = hash21(bay_id + vec2(v_vert_col.r * 29.0, 13.1));
		float night_occ = 0.0;
		if (is_retail) {
			// Ground-floor shops/cafes bright 06:30-22:00, subtle security display lights overnight
			float open_morn = smoothstep(5.8 + room_rand * 1.4, 7.2 + room_rand * 1.4, hr);
			float close_eve = 1.0 - smoothstep(20.8 + sleep_rand * 1.8, 22.4 + sleep_rand * 1.8, hr);
			float shop_open = open_morn * close_eve;
			night_occ = mix(0.22 + 0.25 * step(0.65, room_rand), 0.94, shop_open);
		} else {
			// Staggered wake-up (05:30-07:45), bright dusk/evening (17:00-22:30), progressive bedtime (21:30-02:00)
			float evening_on = smoothstep(16.5 + room_rand * 1.2, 18.2 + room_rand * 1.2, hr);
			float bedtime_h = 21.3 + sleep_rand * 3.4; // staggered between 21:18 and 00:42
			float hr_late = (hr < 5.0) ? (hr + 24.0) : hr;
			float still_awake = 1.0 - smoothstep(bedtime_h, bedtime_h + 0.55, hr_late);
			float dawn_wake = smoothstep(5.4 + sleep_rand * 1.6, 6.4 + sleep_rand * 1.6, hr) * (1.0 - smoothstep(8.2, 9.2, hr));
			float late_owl = step(0.84, room_rand) * 0.85; // ~16% night-shift / cleaning / late-night rooms
			float active_prob = max(evening_on * still_awake, max(dawn_wake * step(0.32, room_rand), late_owl));
			float base_occ = (bay_id.y < 0.5) ? step(0.16, room_rand) : step(0.24, room_rand);
			night_occ = clamp(base_occ * active_prob, 0.0, 1.0);
		}
		// Color temperature variety: warm residential tungsten (2700K), crisp office/clinic LED (4200K), cozy retail amber
		vec3 room_lamp = is_retail
			? mix(vec3(1.0, 0.88, 0.64), vec3(0.95, 0.94, 0.88), step(0.55, pane_seed))
			: mix(vec3(1.0, 0.76, 0.42), vec3(0.76, 0.90, 1.0), step(0.62, pane_seed) * (0.4 + 0.6 * is_wide));
		room_col *= mix(vec3(1.0), room_lamp * mix(0.20, 1.72, night_occ), night_factor);
		room_col *= depth_atten;

		// Subtle streaming exterior rain droplets on wet window panes
		float drop_cell = hash21(floor(vec2(bay_uv.x * 16.0, bay_uv.y * 6.0 - TIME * 1.15)));
		float rain_film = smoothstep(0.84, 0.98, drop_cell) * weather_rain;

		// Keep ALBEDO physically dark so Godot Sky radiance, ReflectionProbes, and Hi-Z SSR drive crisp Fresnel reflections
		float retail_day_boost = is_retail ? 0.55 : 0.0;
		float eff_glow = mix(interior_glow + retail_day_boost, max(interior_glow * 0.85, mix(0.14, 2.20, night_occ)), night_factor);
		vec3 glass_albedo = mix(glass_tint * mix(0.48, 0.18, night_factor), glass_tint * 0.25 + room_col * 0.26, (1.0 - fresnel * 0.75) * (1.0 - blind_mask * 0.35));
		vec3 mullion_col = vec3(0.08, 0.09, 0.11);
		ALBEDO = mix(mullion_col, glass_albedo, frame_mask);
		EMISSION = room_col * (0.34 + emit_amt * 0.95) * eff_glow * (1.0 - fresnel * 0.65) * (1.0 - blind_mask * 0.42) * frame_mask;
		ROUGHNESS = mix(0.36, mix(0.045, 0.12, rain_film), frame_mask);
		METALLIC = mix(0.72, 0.14, frame_mask);
		SPECULAR = mix(0.65, clamp(0.68 + reflection_strength * 0.32, 0.0, 1.0), frame_mask);
	}
}
