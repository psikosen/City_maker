shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 shallow_color : source_color = vec3(0.09, 0.42, 0.45);
uniform vec3 deep_color : source_color = vec3(0.02, 0.11, 0.17);
uniform vec3 sky_reflect_color : source_color = vec3(0.58, 0.76, 0.92);
uniform float flow_speed = 0.65;

global uniform float night_factor;
global uniform float sun_elevation;
global uniform float weather_cloud_cover;
global uniform float weather_rain;
global uniform float weather_lightning;
global uniform float weather_snow_depth;
global uniform vec2 wind_vector;
global uniform vec3 sun_direction;

varying vec3 v_world_pos;
varying vec3 v_flow_data;
varying float v_wave_h;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
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

// Worley-like cellular web for crisp riverbed light caustics
float caustic_web(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float min_d1 = 1.6;
	float min_d2 = 1.6;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			float h = hash21(i + g);
			vec2 o = vec2(fract(h * 13.7), fract(h * 37.3));
			vec2 d = g + o - f;
			float dist = dot(d, d);
			if (dist < min_d1) {
				min_d2 = min_d1;
				min_d1 = dist;
			} else if (dist < min_d2) {
				min_d2 = dist;
			}
		}
	}
	float ridge = sqrt(min_d2) - sqrt(min_d1);
	return smoothstep(0.18, 0.02, ridge);
}

// Multi-scale flow-aligned wave height in creek local coordinates (u = across, v = downstream)
float stream_height(vec2 flow_uv, vec2 world_xz, float t, float speed_scale) {
	float spd = flow_speed * speed_scale;
	vec2 p1 = flow_uv * vec2(1.25, 0.52) + vec2(0.0, -t * spd * 1.10);
	vec2 p2 = flow_uv * vec2(3.15, 1.55) + vec2(t * 0.22, -t * spd * 1.55);
	vec2 p3 = world_xz * 6.4 + wind_vector * (-t * 0.70);
	return noise2d(p1) * 0.44 + noise2d(p2) * 0.34 + noise2d(p3) * 0.22;
}

// Analytical sky dome tint matched to sky_atmosphere.gdshader for coherent reflections
vec3 sample_sky_reflection(vec3 refl_dir, vec3 sun_dir_n, vec3 moon_dir_n, float h_val) {
	float y_up = clamp(refl_dir.y, 0.0, 1.0);
	float horizon = pow(1.0 - y_up, 3.2);
	float day_blend = smoothstep(-0.14, 0.24, sun_elevation);
	float sunset_band = smoothstep(-0.16, 0.03, sun_elevation) * (1.0 - smoothstep(0.06, 0.38, sun_elevation));

	float sun_cos = dot(refl_dir, sun_dir_n);
	float sun_fwd = pow(max(sun_cos, 0.0), 3.0);

	vec3 day_zenith = vec3(0.10, 0.35, 0.82);
	vec3 day_horizon = sky_reflect_color;
	vec3 dusk_zenith = vec3(0.08, 0.13, 0.34);
	vec3 dusk_horizon = mix(vec3(0.36, 0.32, 0.49), vec3(1.12, 0.46, 0.20), 0.45 + 0.55 * sun_fwd);
	vec3 night_zenith = vec3(0.008, 0.015, 0.032);
	vec3 night_horizon = vec3(0.022, 0.036, 0.068);

	vec3 clear_z = mix(night_zenith, day_zenith, day_blend);
	vec3 clear_h = mix(night_horizon, day_horizon, day_blend);
	clear_z = mix(clear_z, dusk_zenith, sunset_band * 0.76);
	clear_h = mix(clear_h, dusk_horizon, sunset_band * 0.90);
	vec3 refl_sky = mix(clear_z, clear_h, horizon);

	// Softly blend reflected sunlit cloud patches matching sky coverage
	float cloud_patch = smoothstep(0.58 - weather_cloud_cover * 0.32, 0.84, h_val);
	vec3 cloud_refl = mix(vec3(0.05, 0.07, 0.12), vec3(0.92, 0.94, 0.97), day_blend);
	cloud_refl = mix(cloud_refl, vec3(1.05, 0.62, 0.40), sunset_band * 0.65);
	cloud_refl = mix(cloud_refl, vec3(0.28, 0.33, 0.40), weather_cloud_cover * 0.65 * (1.0 - night_factor));
	refl_sky = mix(refl_sky, cloud_refl, cloud_patch * clamp(weather_cloud_cover * 1.4, 0.0, 0.88));

	float storm_veil = smoothstep(0.56, 0.96, weather_cloud_cover);
	vec3 storm_col = mix(vec3(0.02, 0.03, 0.05), vec3(0.34, 0.39, 0.46), day_blend);
	refl_sky = mix(refl_sky, storm_col, storm_veil * 0.78);

	refl_sky += vec3(0.58, 0.72, 0.96) * weather_lightning * 0.55;
	return refl_sky;
}

float view_depth_from_tex(vec2 uv, mat4 inv_proj) {
	float d_raw = textureLod(depth_tex, uv, 0.0).r;
	vec3 ndc = vec3(uv * 2.0 - 1.0, d_raw);
	vec4 vp = inv_proj * vec4(ndc, 1.0);
	vp.xyz /= max(0.0001, vp.w);
	return vp.z;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_flow_data = vec3(COLOR.r * 2.0 - 1.0, COLOR.g * 2.0 - 1.0, COLOR.b);
	// Gentle 3D trochoidal river wave displacement scaled by channel center & wind speed
	float env = clamp(v_flow_data.z, 0.12, 1.0);
	float w_mag = clamp(length(wind_vector), 0.4, 3.0);
	float amp = mix(0.032, 0.095, clamp((w_mag - 0.5) / 2.2, 0.0, 1.0)) * env;
	float ph1 = wp.z * 0.48 - TIME * (1.85 + flow_speed * 0.6) + wp.x * 0.14;
	float ph2 = wp.x * 0.72 + wp.z * 0.34 - TIME * 2.35;
	float wy = (sin(ph1) * 0.62 + cos(ph2) * 0.38) * amp;
	VERTEX.y += wy;
	v_wave_h = wy;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 xz = v_world_pos.xz;
	vec2 flow_fwd = normalize(v_flow_data.xy + vec2(0.0, 0.0001));
	vec2 flow_right = vec2(-flow_fwd.y, flow_fwd.x);
	float center_vel = mix(0.45, 1.20, clamp(v_flow_data.z, 0.0, 1.0));
	vec2 flow_uv = vec2(dot(xz, flow_right), dot(xz, flow_fwd));

	float wind_mag = clamp(length(wind_vector), 0.4, 3.0);
	float chop = 1.38 * mix(0.95, 1.60, clamp((wind_mag - 0.8) / 1.8, 0.0, 1.0));
	float eps = 0.07;
	float t_flow = TIME * mix(0.95, 1.45, clamp(wind_mag * 0.4, 0.0, 1.0));

	float h0 = stream_height(flow_uv, xz, t_flow, center_vel);
	float hu = stream_height(flow_uv + vec2(eps, 0.0), xz + flow_right * eps, t_flow, center_vel);
	float hv = stream_height(flow_uv + vec2(0.0, eps), xz + flow_fwd * eps, t_flow, center_vel);
	vec2 local_grad = vec2(h0 - hu, h0 - hv) * chop;
	vec3 world_bump = vec3(
		flow_right.x * local_grad.x + flow_fwd.x * local_grad.y,
		0.0,
		flow_right.y * local_grad.x + flow_fwd.y * local_grad.y
	);

	// Expanding concentric raindrop rings hitting the creek surface during rain
	if (weather_rain > 0.02) {
		float fw_w = max(fwidth(xz.x), fwidth(xz.y));
		float r_fade = 1.0 - smoothstep(0.05, 0.25, fw_w);
		vec2 pi = floor(xz * 1.5);
		vec2 pf = fract(xz * 1.5) - 0.5;
		float rh = hash21(pi);
		float dist = length(pf);
		float cyc = fract(TIME * 2.3 + rh);
		float ring = exp(-abs(dist - cyc * 0.44) * 24.0) * (1.0 - cyc) * sin((dist - cyc * 0.44) * 34.0);
		vec2 rdir = dist > 0.001 ? (pf / dist) : vec2(0.0);
		world_bump += vec3(rdir.x, 0.0, rdir.y) * ring * weather_rain * r_fade * 0.46;
	}

	vec3 world_norm = normalize(vec3(world_bump.x, 1.0, world_bump.z));
	if (!FRONT_FACING) {
		vec3 under_norm = -world_norm;
		NORMAL = normalize((VIEW_MATRIX * vec4(under_norm, 0.0)).xyz);
		vec3 world_view_u = normalize(CAMERA_POSITION_WORLD - v_world_pos);
		float cos_theta = clamp(dot(under_norm, world_view_u), 0.0, 1.0);
		float snell_window = smoothstep(0.42, 0.74, cos_theta);
		vec2 refr_up_uv = clamp(SCREEN_UV + vec2(under_norm.x, -under_norm.z) * 0.038, vec2(0.002), vec2(0.998));
		vec3 above_screen = textureLod(screen_tex, refr_up_uv, 0.0).rgb;
		float day_u = smoothstep(-0.14, 0.24, sun_elevation);
		float caust_u = caustic_web(v_world_pos.xz * 0.75 + flow_fwd * (-TIME * 0.42));
		vec3 tir_col = mix(deep_color, shallow_color, 0.48) * mix(0.20, 0.85, day_u) + vec3(0.08, 0.26, 0.28) * caust_u * day_u;
		vec3 ceil_col = mix(tir_col, above_screen, snell_window);
		ALBEDO = shallow_color * 0.22;
		EMISSION = ceil_col;
		ALPHA = mix(0.90, 0.65, snell_window);
		ROUGHNESS = 0.06;
		METALLIC = 0.04;
		SPECULAR = 0.92;
	} else {
	NORMAL = normalize((VIEW_MATRIX * vec4(world_norm, 0.0)).xyz);

	// Unrefracted depth & screen-space planar refraction with above-water silhouette guard
	float bg_z = view_depth_from_tex(SCREEN_UV, INV_PROJECTION_MATRIX);
	float raw_depth = clamp(VERTEX.z - bg_z, 0.0, 5.0);

	vec2 refr_off = vec2(local_grad.x, -local_grad.y) * (0.024 * smoothstep(0.03, 0.75, raw_depth));
	vec2 refr_uv = clamp(SCREEN_UV + refr_off, vec2(0.002), vec2(0.998));
	float refr_bg_z = view_depth_from_tex(refr_uv, INV_PROJECTION_MATRIX);
	float refr_depth = VERTEX.z - refr_bg_z;
	bool valid_refr = refr_depth > 0.02;
	vec2 sample_uv = valid_refr ? refr_uv : SCREEN_UV;
	float water_depth = valid_refr ? clamp(refr_depth, 0.0, 5.0) : raw_depth;
	float eff_bg_z = valid_refr ? refr_bg_z : bg_z;

	vec3 bed_screen = textureLod(screen_tex, sample_uv, 0.0).rgb;

	// World-space riverbed coordinates for prismatic RGB-dispersed shallow caustics
	vec3 bed_ndc = vec3(sample_uv * 2.0 - 1.0, textureLod(depth_tex, sample_uv, 0.0).r);
	vec4 bed_vp = INV_PROJECTION_MATRIX * vec4(bed_ndc, 1.0);
	bed_vp.xyz /= max(0.0001, bed_vp.w);
	vec3 bed_world = (INV_VIEW_MATRIX * vec4(bed_vp.x, bed_vp.y, eff_bg_z, 1.0)).xyz;

	float day_blend = smoothstep(-0.14, 0.24, sun_elevation);
	float caustic_atten = (1.0 - smoothstep(0.08, 2.35, water_depth)) * (1.0 - night_factor * 0.90) * (1.0 - weather_cloud_cover * 0.62);
	if (caustic_atten > 0.01) {
		vec2 c_uv = bed_world.xz * 0.95 + flow_fwd * (-TIME * 0.46);
		float cr = caustic_web(c_uv + vec2(0.016, 0.010));
		float cg = caustic_web(c_uv);
		float cb = caustic_web(c_uv - vec2(0.016, 0.010));
		vec3 caust_rgb = vec3(cr, cg, cb);
		bed_screen = bed_screen * (1.0 + caust_rgb * caustic_atten * 0.72) + caust_rgb * vec3(0.09, 0.16, 0.16) * caustic_atten;
	}

	// Beer-Lambert chromatic depth absorption + deep mineral emerald-sapphire water tint
	vec3 transmittance = exp(-water_depth * vec3(0.96, 0.34, 0.24));
	float depth_t = smoothstep(0.06, 2.10, water_depth);
	vec3 water_body = mix(shallow_color, deep_color, depth_t) * mix(0.14, 0.58, day_blend) * mix(1.0, 0.58, weather_cloud_cover * 0.55);
	water_body += vec3(0.05, 0.09, 0.14) * weather_lightning * 0.35;
	vec3 under_water = bed_screen * transmittance + water_body * (1.0 - transmittance);

	// View-dependent sky & sun/moon reflections via Schlick dielectric Fresnel
	vec3 world_view = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	vec3 refl_dir = reflect(-world_view, world_norm);
	refl_dir.y = abs(refl_dir.y);

	vec3 sun_dir_n = normalize(sun_direction);
	vec3 moon_dir_n = normalize(vec3(-sun_dir_n.x, -sun_dir_n.y + 0.08, -sun_dir_n.z));
	vec3 refl_col = sample_sky_reflection(refl_dir, sun_dir_n, moon_dir_n, h0) * mix(0.18, 0.86, day_blend);

	// Sparkling anisotropic sun & moon GGX water glints
	vec3 half_sun = normalize(sun_dir_n + world_view);
	float ndh_sun = max(dot(world_norm, half_sun), 0.0);
	float spec_pow = mix(240.0, 44.0, weather_cloud_cover);
	float sun_glint = pow(ndh_sun, spec_pow) * smoothstep(-0.02, 0.14, sun_elevation) * (1.0 - weather_cloud_cover * 0.82) * 2.4;
	vec3 sun_glint_col = mix(vec3(1.15, 0.58, 0.25), vec3(1.15, 1.08, 0.96), smoothstep(-0.01, 0.30, sun_elevation));

	vec3 half_moon = normalize(moon_dir_n + world_view);
	float moon_glint = pow(max(dot(world_norm, half_moon), 0.0), 140.0) * night_factor * (1.0 - weather_cloud_cover * 0.78) * 0.58;
	refl_col += sun_glint_col * sun_glint + vec3(0.65, 0.78, 1.05) * moon_glint;

	float nov = clamp(dot(world_norm, world_view), 0.0, 1.0);
	float fresnel = 0.10 + 0.90 * pow(1.0 - nov, 3.8);
	fresnel = clamp(fresnel * 0.94, 0.0, 0.92);

	// Organic shoreline meniscus, bridge-pier cellular foam lacing, fast mid-stream riffles & winter bank ice rim
	float shore_band = 1.0 - smoothstep(0.02, 0.44, water_depth);
	float shore_cell = smoothstep(0.32, 0.66, h0 * 0.55 + noise2d(flow_uv * 2.4 - vec2(0.0, TIME * 0.95)) * 0.45);
	float shore_foam = shore_band * shore_cell;
	float riffle_foam = smoothstep(0.74, 0.92, h0 + max(v_wave_h, 0.0) * 1.6) * clamp(v_flow_data.z, 0.0, 1.0) * 0.28;
	float ice_rim = (1.0 - smoothstep(0.0, 0.85, water_depth)) * smoothstep(0.35, 0.88, weather_snow_depth) * 0.62;
	float foam = clamp(shore_foam * 0.88 + riffle_foam + ice_rim, 0.0, 0.92);

	vec3 foam_albedo = mix(vec3(0.84, 0.91, 0.94), vec3(0.24, 0.30, 0.40), night_factor);
	vec3 water_surface = mix(under_water, refl_col, fresnel);

	ALBEDO = foam_albedo * foam + mix(shallow_color, deep_color, depth_t) * 0.14;
	EMISSION = water_surface * (1.0 - foam * 0.88);
	ALPHA = smoothstep(0.01, 0.11, water_depth);
	ROUGHNESS = mix(0.05, 0.38, foam);
	METALLIC = 0.04;
	SPECULAR = 0.90;
	}
}
