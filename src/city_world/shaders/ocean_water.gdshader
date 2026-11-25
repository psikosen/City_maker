shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Coastal Ocean & Breaking Surf Water Shader (Forward+):
// - 4-wave directional Gerstner displacement rolling onshore toward the sandy beach
// - DEPTH_TEXTURE Beer-Lambert aquamarine -> deep ocean chromatic absorption
// - Guarded SCREEN_TEXTURE planar refraction + RGB-dispersed underwater sand caustics
// - Rhythmic onshore breaking surf foam bands + lacy cellular foam + wave crest whitecaps
// - Schlick Fresnel sky/sunset/cloud/moon reflections + sparkling GGX sun glitter

uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

uniform vec3 shallow_color : source_color = vec3(0.08, 0.56, 0.60);
uniform vec3 mid_color : source_color = vec3(0.04, 0.28, 0.42);
uniform vec3 deep_color : source_color = vec3(0.015, 0.075, 0.16);
uniform vec3 sky_reflect_color : source_color = vec3(0.58, 0.77, 0.94);

global uniform float night_factor;
global uniform float sun_elevation;
global uniform float weather_cloud_cover;
global uniform float weather_rain;
global uniform float weather_lightning;
global uniform float weather_snow_depth;
global uniform vec2 wind_vector;
global uniform vec3 sun_direction;

varying vec3 v_world_pos;
varying float v_wave_crest;
varying float v_shore_prox;

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

float fbm2(vec2 p) {
	return noise2d(p) * 0.62 + noise2d(p * 2.13 + vec2(3.7, 1.9)) * 0.38;
}

float caustic_web(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 1.6;
	float d2 = 1.6;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			float h = hash21(i + g);
			vec2 o = vec2(fract(h * 13.7), fract(h * 37.3));
			vec2 d = g + o - f;
			float dist = dot(d, d);
			if (dist < d1) {
				d2 = d1;
				d1 = dist;
			} else if (dist < d2) {
				d2 = dist;
			}
		}
	}
	return smoothstep(0.19, 0.018, sqrt(d2) - sqrt(d1));
}

vec3 gerstner_wave(vec2 dir_in, float steepness, float wavelength, float speed_mult, vec3 wp, float t, inout vec3 tang, inout vec3 binorm) {
	vec2 dir = normalize(dir_in);
	float k = 6.2831853 / wavelength;
	float c = sqrt(9.8 / k) * speed_mult;
	float f = k * (dot(dir, wp.xz) - c * t);
	float a = steepness / k;
	float sf = sin(f);
	float cf = cos(f);

	tang += vec3(-dir.x * dir.x * steepness * sf, dir.x * steepness * cf, -dir.x * dir.y * steepness * sf);
	binorm += vec3(-dir.x * dir.y * steepness * sf, dir.y * steepness * cf, -dir.y * dir.y * steepness * sf);
	return vec3(dir.x * a * cf, a * sf, dir.y * a * cf);
}

vec3 sample_sky_reflection(vec3 refl_dir, vec3 sun_dir_n, float h_val) {
	float y_up = clamp(refl_dir.y, 0.0, 1.0);
	float horizon = pow(1.0 - y_up, 3.0);
	float day_blend = smoothstep(-0.14, 0.24, sun_elevation);
	float sunset_band = smoothstep(-0.16, 0.03, sun_elevation) * (1.0 - smoothstep(0.06, 0.38, sun_elevation));

	float sun_cos = dot(refl_dir, sun_dir_n);
	float sun_fwd = pow(max(sun_cos, 0.0), 3.0);

	vec3 day_zenith = vec3(0.09, 0.34, 0.84);
	vec3 day_horizon = sky_reflect_color;
	vec3 dusk_zenith = vec3(0.08, 0.13, 0.34);
	vec3 dusk_horizon = mix(vec3(0.36, 0.32, 0.50), vec3(1.16, 0.48, 0.20), 0.45 + 0.55 * sun_fwd);
	vec3 night_zenith = vec3(0.008, 0.016, 0.035);
	vec3 night_horizon = vec3(0.022, 0.038, 0.072);

	vec3 clear_z = mix(night_zenith, day_zenith, day_blend);
	vec3 clear_h = mix(night_horizon, day_horizon, day_blend);
	clear_z = mix(clear_z, dusk_zenith, sunset_band * 0.76);
	clear_h = mix(clear_h, dusk_horizon, sunset_band * 0.92);
	vec3 refl_sky = mix(clear_z, clear_h, horizon);

	float cloud_patch = smoothstep(0.56 - weather_cloud_cover * 0.32, 0.84, h_val);
	vec3 cloud_refl = mix(vec3(0.05, 0.07, 0.12), vec3(0.93, 0.95, 0.98), day_blend);
	cloud_refl = mix(cloud_refl, vec3(1.08, 0.62, 0.38), sunset_band * 0.65);
	cloud_refl = mix(cloud_refl, vec3(0.28, 0.33, 0.40), weather_cloud_cover * 0.65 * (1.0 - night_factor));
	refl_sky = mix(refl_sky, cloud_refl, cloud_patch * clamp(weather_cloud_cover * 1.4, 0.0, 0.88));

	float storm_veil = smoothstep(0.56, 0.96, weather_cloud_cover);
	vec3 storm_col = mix(vec3(0.02, 0.03, 0.05), vec3(0.34, 0.40, 0.48), day_blend);
	refl_sky = mix(refl_sky, storm_col, storm_veil * 0.78);
	refl_sky += vec3(0.60, 0.74, 0.98) * weather_lightning * 0.58;
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
	// COLOR.r encodes offshore wave envelope (0.18 near shallow swash -> 1.0 open ocean)
	float env = clamp(COLOR.r, 0.16, 1.0);
	v_shore_prox = 1.0 - env;
	float wind_mag = clamp(length(wind_vector), 0.5, 3.0);
	float storm_amp = mix(0.85, 1.65, clamp((wind_mag - 0.65) / 2.1, 0.0, 1.0)) * env;

	vec3 tang = vec3(1.0, 0.0, 0.0);
	vec3 binorm = vec3(0.0, 0.0, 1.0);
	vec3 disp = vec3(0.0);
	// Primary onshore swells traveling northward (-Z) into the south-facing beach!
	disp += gerstner_wave(vec2(0.14, -0.99), 0.14 * storm_amp, 28.0, 0.78, wp, TIME, tang, binorm);
	disp += gerstner_wave(vec2(-0.28, -0.96), 0.10 * storm_amp, 15.5, 0.92, wp, TIME, tang, binorm);
	disp += gerstner_wave(vec2(0.45, -0.89), 0.07 * storm_amp, 8.6, 1.08, wp, TIME, tang, binorm);
	disp += gerstner_wave(vec2(-0.62, -0.78), 0.05 * storm_amp, 4.9, 1.22, wp, TIME, tang, binorm);

	VERTEX += disp;
	NORMAL = normalize(cross(binorm, tang));
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wave_crest = clamp(disp.y * 2.2, 0.0, 1.0);
}

void fragment() {
	vec2 xz = v_world_pos.xz;
	float wind_mag = clamp(length(wind_vector), 0.5, 3.0);
	float fw = max(fwidth(xz.x), fwidth(xz.y));
	float detail_fade = 1.0 - smoothstep(0.06, 0.55, fw);

	// Dual-advected multi-scale capillary & swell micro-normals
	vec2 drift_a = vec2(0.18, -0.98) * (TIME * 0.55);
	vec2 drift_b = vec2(-0.42, -0.91) * (TIME * 0.82) - wind_vector * (TIME * 0.22);
	float h0 = fbm2(xz * 0.24 + drift_a) * 0.58 + fbm2(xz * 0.72 + drift_b) * 0.42;

	vec3 geom_world_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 world_bump = vec3(0.0);
	if (detail_fade > 0.01) {
		float eps = 0.14;
		float hx = fbm2((xz + vec2(eps, 0.0)) * 0.24 + drift_a) * 0.58 + fbm2((xz + vec2(eps, 0.0)) * 0.72 + drift_b) * 0.42;
		float hz = fbm2((xz + vec2(0.0, eps)) * 0.24 + drift_a) * 0.58 + fbm2((xz + vec2(0.0, eps)) * 0.72 + drift_b) * 0.42;
		float chop = mix(1.05, 1.75, clamp((wind_mag - 0.65) / 2.0, 0.0, 1.0));
		world_bump = vec3((h0 - hx) * chop, 0.0, (h0 - hz) * chop) * detail_fade;

		// Fine sparkling wind ripples up close
		float fine_fade = 1.0 - smoothstep(0.02, 0.16, fw);
		if (fine_fade > 0.01) {
			float f0 = noise2d(xz * 3.8 + drift_b * 1.8);
			float fx = noise2d((xz + vec2(0.05, 0.0)) * 3.8 + drift_b * 1.8);
			float fz = noise2d((xz + vec2(0.0, 0.05)) * 3.8 + drift_b * 1.8);
			world_bump += vec3((f0 - fx) * 0.55, 0.0, (f0 - fz) * 0.55) * fine_fade;
		}
		if (weather_rain > 0.02) {
			vec2 pi = floor(xz * 1.45);
			vec2 pf = fract(xz * 1.45) - 0.5;
			float rh = hash21(pi);
			float dist = length(pf);
			float cyc = fract(TIME * 2.2 + rh);
			float ring = exp(-abs(dist - cyc * 0.44) * 24.0) * (1.0 - cyc) * sin((dist - cyc * 0.44) * 34.0);
			vec2 rdir = dist > 0.001 ? (pf / dist) : vec2(0.0);
			world_bump += vec3(rdir.x, 0.0, rdir.y) * ring * weather_rain * detail_fade * 0.42;
		}
	}

	vec3 world_norm = normalize(geom_world_n + world_bump * 0.55);
	if (!FRONT_FACING) {
		// Underwater camera looking UP at the undulating ocean wave ceiling (Snell's Window!)
		vec3 under_norm = -world_norm;
		NORMAL = normalize((VIEW_MATRIX * vec4(under_norm, 0.0)).xyz);
		vec3 world_view_u = normalize(CAMERA_POSITION_WORLD - v_world_pos);
		vec3 sun_dir_u = normalize(sun_direction);
		float cos_theta = clamp(dot(under_norm, world_view_u), 0.0, 1.0);
		// Snell's critical angle for water -> air (n=1.333 -> cos(48.6 deg) ~= 0.661)
		float snell_window = smoothstep(0.42, 0.74, cos_theta);
		vec2 refr_up_uv = clamp(SCREEN_UV + vec2(under_norm.x, -under_norm.z) * 0.045, vec2(0.002), vec2(0.998));
		vec3 above_screen = textureLod(screen_tex, refr_up_uv, 0.0).rgb;
		float day_u = smoothstep(-0.14, 0.24, sun_elevation);
		vec3 sky_up = sample_sky_reflection(normalize(vec3(-world_view_u.x, max(0.15, -world_view_u.y), -world_view_u.z) + under_norm * 0.28), sun_dir_u, h0) * mix(0.22, 0.95, day_u);
		float sun_burst = pow(max(dot(-world_view_u, sun_dir_u + under_norm * 0.35), 0.0), 22.0) * day_u * (1.0 - weather_cloud_cover * 0.75) * 2.2;
		vec3 window_col = mix(above_screen, sky_up, 0.38) + vec3(0.95, 0.92, 0.78) * sun_burst;
		// Outside Snell's window: total internal reflection of turquoise-sapphire water & shimmering caustics
		float caust_u = caustic_web(xz * 0.48 + vec2(0.08, -0.32) * TIME);
		vec3 tir_col = mix(deep_color, shallow_color, 0.52) * mix(0.20, 0.88, day_u) + vec3(0.10, 0.32, 0.36) * caust_u * day_u;
		vec3 ceil_col = mix(tir_col, window_col, snell_window);
		ALBEDO = mix(shallow_color, vec3(0.75, 0.92, 0.96), snell_window * 0.35) * 0.25;
		EMISSION = ceil_col;
		ALPHA = mix(0.92, 0.68, snell_window);
		ROUGHNESS = 0.06;
		METALLIC = 0.05;
		SPECULAR = 0.95;
	} else {
	NORMAL = normalize((VIEW_MATRIX * vec4(world_norm, 0.0)).xyz);

	// Linear water depth from DEPTH_TEXTURE + guarded planar refraction
	float bg_z = view_depth_from_tex(SCREEN_UV, INV_PROJECTION_MATRIX);
	float raw_depth = clamp(VERTEX.z - bg_z, 0.0, 14.0);

	vec2 refr_off = vec2(world_norm.x, -world_norm.z) * (0.032 * smoothstep(0.04, 1.10, raw_depth));
	vec2 refr_uv = clamp(SCREEN_UV + refr_off, vec2(0.002), vec2(0.998));
	float refr_bg_z = view_depth_from_tex(refr_uv, INV_PROJECTION_MATRIX);
	float refr_depth = VERTEX.z - refr_bg_z;
	bool valid_refr = refr_depth > 0.02;
	vec2 sample_uv = valid_refr ? refr_uv : SCREEN_UV;
	float water_depth = valid_refr ? clamp(refr_depth, 0.0, 14.0) : raw_depth;
	float eff_bg_z = valid_refr ? refr_bg_z : bg_z;

	vec3 bed_screen = textureLod(screen_tex, sample_uv, 0.0).rgb;

	// Chromatic RGB-dispersed organic warped underwater sand caustics in shallow coastal surf
	float day_blend = smoothstep(-0.14, 0.24, sun_elevation);
	float caustic_atten = (1.0 - smoothstep(0.10, 3.2, water_depth)) * smoothstep(0.02, 0.22, water_depth) * (1.0 - night_factor * 0.90) * (1.0 - weather_cloud_cover * 0.62);
	if (caustic_atten > 0.02 && detail_fade > 0.02) {
		vec3 bed_ndc = vec3(sample_uv * 2.0 - 1.0, textureLod(depth_tex, sample_uv, 0.0).r);
		vec4 bed_vp = INV_PROJECTION_MATRIX * vec4(bed_ndc, 1.0);
		bed_vp.xyz /= max(0.0001, bed_vp.w);
		vec3 bed_world = (INV_VIEW_MATRIX * vec4(bed_vp.x, bed_vp.y, eff_bg_z, 1.0)).xyz;
		vec2 c_warp = vec2(
			fbm2(bed_world.xz * 0.22 + vec2(TIME * 0.18, -TIME * 0.14)),
			fbm2(bed_world.xz * 0.22 + vec2(-TIME * 0.15 + 17.3, TIME * 0.19))
		) * 1.45;
		vec2 c_uv = bed_world.xz * 0.44 + c_warp + vec2(0.06, -0.28) * TIME;
		vec2 c_uv2 = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * (bed_world.xz * 0.72 - c_warp * 0.75) + vec2(-0.12, -0.22) * TIME;
		float cr = caustic_web(c_uv + vec2(0.022, 0.014)) * 0.65 + caustic_web(c_uv2 + vec2(0.015, 0.010)) * 0.35;
		float cg = caustic_web(c_uv) * 0.65 + caustic_web(c_uv2) * 0.35;
		float cb = caustic_web(c_uv - vec2(0.022, 0.014)) * 0.65 + caustic_web(c_uv2 - vec2(0.015, 0.010)) * 0.35;
		vec3 caust_rgb = pow(clamp(vec3(cr, cg, cb), 0.0, 1.0), vec3(1.5));
		bed_screen = bed_screen * (1.0 + caust_rgb * caustic_atten * 0.48) + caust_rgb * vec3(0.05, 0.11, 0.12) * caustic_atten;
	}

	// Beer-Lambert depth absorption: emerald-turquoise crystal shallows -> sapphire -> deep ocean navy
	vec3 transmittance = exp(-water_depth * vec3(0.96, 0.34, 0.21));
	vec3 body_col = mix(shallow_color, mid_color, smoothstep(0.28, 2.8, water_depth));
	body_col = mix(body_col, deep_color, smoothstep(2.4, 8.8, water_depth));
	// Subsurface emerald wave-crest scatter when backlit by sun
	vec3 sun_dir_n = normalize(sun_direction);
	vec3 world_view = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	float sss = pow(max(dot(world_view, -sun_dir_n + world_norm * 0.45), 0.0), 3.0) * v_wave_crest * day_blend * (1.0 - weather_cloud_cover * 0.7);
	body_col += vec3(0.04, 0.32, 0.30) * sss * 0.85;
	body_col *= mix(0.14, 0.76, day_blend) * mix(1.0, 0.62, weather_cloud_cover * 0.52);
	body_col += vec3(0.06, 0.10, 0.15) * weather_lightning * 0.35;

	vec3 under_water = bed_screen * transmittance + body_col * (1.0 - transmittance);

	// Schlick dielectric Fresnel sky/cloud reflection + sun/moon ocean glitter path
	vec3 refl_dir = reflect(-world_view, world_norm);
	refl_dir.y = abs(refl_dir.y);
	vec3 refl_col = sample_sky_reflection(refl_dir, sun_dir_n, h0) * mix(0.18, 0.76, day_blend);

	vec3 half_sun = normalize(sun_dir_n + world_view);
	float ndh_sun = max(dot(world_norm, half_sun), 0.0);
	float spec_pow = mix(280.0, 48.0, weather_cloud_cover);
	float sun_glint = pow(ndh_sun, spec_pow) * smoothstep(-0.02, 0.14, sun_elevation) * (1.0 - weather_cloud_cover * 0.82) * 3.1;
	vec3 sun_glint_col = mix(vec3(1.22, 0.58, 0.24), vec3(1.18, 1.10, 0.96), smoothstep(-0.01, 0.30, sun_elevation));

	vec3 moon_dir_n = normalize(vec3(-sun_dir_n.x, -sun_dir_n.y + 0.08, -sun_dir_n.z));
	vec3 half_moon = normalize(moon_dir_n + world_view);
	float moon_glint = pow(max(dot(world_norm, half_moon), 0.0), 150.0) * night_factor * (1.0 - weather_cloud_cover * 0.78) * 0.72;
	refl_col += sun_glint_col * sun_glint + vec3(0.68, 0.82, 1.08) * moon_glint;

	float nov = clamp(dot(world_norm, world_view), 0.0, 1.0);
	float fresnel = clamp(0.035 + 0.84 * pow(1.0 - nov, 4.6), 0.0, 0.82);

	// Rhythmic breaking shoreline surf rollers + bubbly lacy foam + open-ocean whitecaps
	float foam_lace = fbm2(xz * 0.55 + vec2(0.0, TIME * 0.65)) * 0.65 + noise2d(xz * 2.1 - vec2(0.0, TIME * 1.1)) * 0.35;
	float surf_phase = sin(water_depth * 3.8 + TIME * 2.15 + noise2d(xz * 0.08) * 2.8);
	float surf_roller = smoothstep(0.45, 0.92, surf_phase) * smoothstep(2.4, 0.25, water_depth) * smoothstep(0.02, 0.18, water_depth);
	float edge_foam = (1.0 - smoothstep(0.02, 0.52, water_depth)) * smoothstep(0.28, 0.64, foam_lace);
	float roller_foam = surf_roller * smoothstep(0.30, 0.66, foam_lace) * 0.92;
	float crest_whitecap = smoothstep(0.46, 0.88, v_wave_crest + (wind_mag - 1.0) * 0.16) * smoothstep(0.42, 0.74, foam_lace) * 0.75;
	float winter_ice_rim = (1.0 - smoothstep(0.0, 0.75, water_depth)) * smoothstep(0.42, 0.88, weather_snow_depth) * 0.55;
	float foam = clamp(edge_foam * 0.95 + roller_foam + crest_whitecap + winter_ice_rim, 0.0, 0.96);

	vec3 foam_albedo = mix(vec3(0.92, 0.96, 0.98), vec3(0.26, 0.33, 0.44), night_factor);
	vec3 water_surface = mix(under_water, refl_col, fresnel);

	ALBEDO = foam_albedo * foam + body_col * 0.12;
	EMISSION = water_surface * (1.0 - foam * 0.90);
	ALPHA = smoothstep(0.008, 0.09, water_depth);
	ROUGHNESS = mix(0.04, 0.44, foam);
	METALLIC = 0.04;
	SPECULAR = 0.92;
	}
}
