shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 facing_color : source_color = vec3(0.16, 0.24, 0.34);
uniform vec3 glancing_color : source_color = vec3(0.05, 0.09, 0.15);
uniform bool use_instance_custom = false;

global uniform float weather_wetness;
global uniform float weather_snow_depth;

varying vec3 v_local_pos;
varying vec3 v_local_normal;
varying vec4 v_custom;
varying vec4 v_color;

float hash31(vec3 p) {
	p = fract(p * vec3(127.1, 311.7, 74.7));
	p += dot(p, p + 31.32);
	return fract(p.x * p.y * p.z);
}

void vertex() {
	v_local_pos = VERTEX;
	v_local_normal = NORMAL;
	v_custom = INSTANCE_CUSTOM;
	v_color = COLOR;
}

void fragment() {
	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 2.6);

	// Metallic flake sparkle fading out smoothly at distance to avoid pixel shimmer
	vec3 fp = v_local_pos * 180.0;
	float fw = max(max(fwidth(fp.x), fwidth(fp.y)), fwidth(fp.z));
	float flake_fade = 1.0 - smoothstep(0.35, 1.1, fw);
	float flake = hash31(floor(fp));
	float sparkle = smoothstep(0.75, 0.98, flake) * flake_fade;

	// Micro rain-bead texture on hood/roof clearcoat
	float rain_bead = smoothstep(0.68, 0.92, hash31(floor(v_local_pos * 48.0))) * weather_wetness * flake_fade;

	if (use_instance_custom) {
		bool is_shadow = (v_color.r < 0.15 && v_color.g < 0.15 && v_color.b < 0.15);
		bool is_glass = (v_color.g > 0.70 && v_color.r < 0.30 && v_color.b < 0.30);
		bool is_trim = (v_color.b > 0.70 && v_color.r < 0.30 && v_color.g < 0.30);
		bool is_livery = (v_color.r > 0.35 && v_color.g > 0.35 && v_color.b < 0.25);
		bool is_alloy = (v_color.r > 0.35 && v_color.g > 0.35 && v_color.b > 0.70);
		// Subtle lower-body AO grounding near rocker panels & wheel wells
		float body_ao = mix(0.76, 1.03, smoothstep(0.14, 0.78, v_local_pos.y));

		if (is_shadow) {
			// Matte non-specular underbody ambient-occlusion contact shadow skirt
			ALBEDO = vec3(0.020, 0.022, 0.026) * mix(1.0, 0.65, weather_wetness);
			METALLIC = 0.0;
			ROUGHNESS = 1.0;
			SPECULAR = 0.0;
			CLEARCOAT = 0.0;
			CLEARCOAT_ROUGHNESS = 1.0;
		} else if (is_glass) {
			vec3 glass_c = mix(vec3(0.022, 0.036, 0.060), vec3(0.06, 0.12, 0.18), fresnel * 0.70);
			ALBEDO = glass_c * mix(1.0, 0.88, weather_wetness);
			METALLIC = 0.18;
			ROUGHNESS = mix(0.050, 0.022, weather_wetness);
			SPECULAR = 0.96;
			CLEARCOAT = 1.0;
			CLEARCOAT_ROUGHNESS = mix(0.02, 0.01 + rain_bead * 0.06, weather_wetness);
		} else if (is_alloy) {
			// Machined aluminum wheel hubs, chrome grille bars & exhaust trim
			ALBEDO = vec3(0.76, 0.78, 0.81) * body_ao * mix(1.0, 0.88, weather_wetness);
			METALLIC = 0.88;
			ROUGHNESS = mix(0.24, 0.14, weather_wetness);
			SPECULAR = 0.92;
			CLEARCOAT = 0.35;
			CLEARCOAT_ROUGHNESS = 0.15;
		} else if (is_trim) {
			ALBEDO = vec3(0.055, 0.058, 0.065) * body_ao * mix(1.0, 0.74, weather_wetness);
			METALLIC = 0.10;
			ROUGHNESS = mix(0.80, 0.38, weather_wetness);
			SPECULAR = mix(0.26, 0.64, weather_wetness);
			CLEARCOAT = 0.0;
			CLEARCOAT_ROUGHNESS = 0.5;
		} else if (is_livery) {
			// Livery encoded by INSTANCE_CUSTOM.a: <0.35 white fleet, 0.35-0.65 taxi black/amber check, 0.65-0.85 emergency navy/red, >0.85 transit teal
			vec3 liv_c = vec3(0.88, 0.90, 0.93);
			if (v_custom.a > 0.85) {
				liv_c = vec3(0.14, 0.68, 0.74);
			} else if (v_custom.a > 0.65) {
				liv_c = vec3(0.10, 0.24, 0.56);
			} else if (v_custom.a > 0.35) {
				float check = step(0.5, fract(v_local_pos.z * 5.0));
				liv_c = mix(vec3(0.08, 0.08, 0.09), vec3(0.95, 0.74, 0.10), check);
			}
			liv_c *= body_ao * mix(1.0, 0.86, weather_wetness);
			ALBEDO = liv_c;
			METALLIC = 0.32;
			ROUGHNESS = mix(0.24, 0.08, weather_wetness);
			SPECULAR = mix(0.75, 0.92, weather_wetness);
			CLEARCOAT = 0.85;
			CLEARCOAT_ROUGHNESS = mix(0.05, 0.02 + rain_bead * 0.07, weather_wetness);
		} else {
			vec3 face_c = v_custom.rgb;
			vec3 glance_c = face_c * vec3(0.38, 0.44, 0.54);
			vec3 col = mix(face_c, glance_c, fresnel * 0.74);
			col += face_c * sparkle * 0.28;
			col *= body_ao * mix(1.0, 0.86, weather_wetness);
			float roof_snow = clamp(smoothstep(0.68, 0.94, v_local_normal.y) * smoothstep(0.28, 0.92, weather_snow_depth) * 0.72, 0.0, 0.78);
			col = mix(col, vec3(0.91, 0.94, 0.98), roof_snow);
			ALBEDO = col;
			METALLIC = 0.72 * (1.0 - roof_snow);
			ROUGHNESS = mix(mix(mix(0.26, 0.11, sparkle), 0.065, weather_wetness), 0.78, roof_snow);
			SPECULAR = mix(mix(0.85, 0.96, weather_wetness), 0.42, roof_snow);
			CLEARCOAT = 1.0 - roof_snow;
			CLEARCOAT_ROUGHNESS = mix(0.032, 0.015 + rain_bead * 0.08, weather_wetness);
		}
	} else {
		vec3 col = mix(facing_color, glancing_color, fresnel * 0.72);
		col += facing_color * sparkle * 0.28;
		col *= mix(1.0, 0.86, weather_wetness);

		ALBEDO = col;
		METALLIC = 0.72;
		ROUGHNESS = mix(mix(0.28, 0.12, sparkle), 0.07, weather_wetness);
		SPECULAR = mix(0.85, 0.95, weather_wetness);
		CLEARCOAT = 1.0;
		CLEARCOAT_ROUGHNESS = mix(0.035, 0.015 + rain_bead * 0.08, weather_wetness);
	}
}
