shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

global uniform float weather_wetness;
global uniform float night_factor;

varying vec4 v_custom;
varying vec4 v_color;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

vec3 pick_palette(float seed, int count, vec3 c0, vec3 c1, vec3 c2, vec3 c3, vec3 c4, vec3 c5) {
	int idx = int(floor(fract(seed) * float(count))) % count;
	if (idx == 0) return c0;
	if (idx == 1) return c1;
	if (idx == 2) return c2;
	if (idx == 3) return c3;
	if (idx == 4) return c4;
	return c5;
}

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_color = COLOR;

	float phase = INSTANCE_CUSTOM.r;
	float speed = INSTANCE_CUSTOM.g;
	float ped_scale = clamp(INSTANCE_CUSTOM.a, 0.78, 1.22);

	float stride_amp = clamp(speed / 1.35, 0.0, 1.35);
	float idle_w = 1.0 - smoothstep(0.05, 0.35, speed);
	float swing = sin(phase) * 0.56 * stride_amp;
	float bob = abs(cos(phase)) * 0.032 * stride_amp;
	// Gentle idle chest breathing & subtle head glance when waiting at crosswalks/bus stops/plazas
	float breathe = sin(TIME * 2.1 + phase * 3.0) * 0.008 * idle_w;
	float head_yaw = sin(TIME * 0.95 + phase * 5.0) * 0.24 * idle_w;

	float limb = COLOR.r;
	float ang = 0.0;
	float pivot_y = 0.0;

	if (limb > 0.15 && limb < 0.38) {
		// Left leg
		ang = swing;
		pivot_y = 0.80;
	} else if (limb >= 0.38 && limb < 0.62) {
		// Right leg
		ang = -swing;
		pivot_y = 0.80;
	} else if (limb >= 0.62 && limb < 0.88) {
		// Left arm (counter-swing + relaxed idle sway)
		ang = -swing * 0.74 + sin(TIME * 1.3 + phase) * 0.04 * idle_w;
		pivot_y = 1.38;
	} else if (limb >= 0.88) {
		// Right arm
		ang = swing * 0.74 - sin(TIME * 1.3 + phase) * 0.04 * idle_w;
		pivot_y = 1.38;
	}

	if (abs(ang) > 0.0001) {
		float ca = cos(ang);
		float sa = sin(ang);
		float dy = VERTEX.y - pivot_y;
		float dz = VERTEX.z;
		VERTEX.y = pivot_y + dy * ca + dz * sa;
		VERTEX.z = -dy * sa + dz * ca;

		float ny = NORMAL.y;
		float nz = NORMAL.z;
		NORMAL.y = ny * ca + nz * sa;
		NORMAL.z = -ny * sa + nz * ca;
	}

	// Subtle idle head look-around on upper head vertices (y > 1.44, torso limb_id == 0)
	if (limb < 0.15 && VERTEX.y > 1.44 && abs(head_yaw) > 0.001) {
		float cy = cos(head_yaw);
		float sy = sin(head_yaw);
		float hx = VERTEX.x;
		float hz = VERTEX.z;
		VERTEX.x = hx * cy + hz * sy;
		VERTEX.z = -hx * sy + hz * cy;
		float nhx = NORMAL.x;
		float nhz = NORMAL.z;
		NORMAL.x = nhx * cy + nhz * sy;
		NORMAL.z = -nhx * sy + nhz * cy;
	}

	if (COLOR.b < 0.5) {
		if (VERTEX.y > 0.85) {
			VERTEX.y += breathe;
		}
		VERTEX.y += bob;
	}
	VERTEX *= ped_scale;
}

void fragment() {
	if (v_color.b > 0.5) {
		// Ground contact shadow disc beneath feet
		ALBEDO = vec3(0.05, 0.055, 0.065) * mix(1.0, 0.72, weather_wetness);
		ROUGHNESS = 0.96;
		METALLIC = 0.0;
		SPECULAR = 0.04;
	} else {
	// INSTANCE_CUSTOM.b packs: floor(b) = citizen role (0..6), fract(b) = per-citizen seed
	int role = int(floor(max(0.0, v_custom.b)));
	float seed = fract(v_custom.b);
	float s1 = hash11(seed * 17.3 + 1.1);
	float s2 = hash11(seed * 31.7 + 2.7);
	float s3 = hash11(seed * 53.9 + 4.3);
	float s4 = hash11(seed * 79.1 + 6.9);

	float part = v_color.g;
	vec3 col;
	float rough = 0.82;

	if (part < 0.12) {
		// Skin tone
		col = pick_palette(
			s1, 6,
			vec3(0.84, 0.66, 0.54),
			vec3(0.75, 0.54, 0.41),
			vec3(0.62, 0.42, 0.30),
			vec3(0.45, 0.29, 0.20),
			vec3(0.89, 0.74, 0.63),
			vec3(0.55, 0.37, 0.26)
		);
		rough = 0.66;
	} else if (part < 0.38) {
		// Hair
		col = pick_palette(
			s2, 6,
			vec3(0.10, 0.08, 0.07),
			vec3(0.24, 0.15, 0.09),
			vec3(0.42, 0.28, 0.16),
			vec3(0.62, 0.50, 0.30),
			vec3(0.54, 0.54, 0.56),
			vec3(0.16, 0.11, 0.08)
		);
		rough = 0.72;
	} else if (part < 0.62) {
		// Role-authentic upper garment / jacket / shirt / scrubs
		if (role == 0) {
			// Office worker: tailored navy, charcoal, slate, camel, crisp shirt
			col = pick_palette(
				s3, 6,
				vec3(0.12, 0.17, 0.28),
				vec3(0.19, 0.20, 0.24),
				vec3(0.28, 0.32, 0.38),
				vec3(0.58, 0.50, 0.38),
				vec3(0.76, 0.78, 0.82),
				vec3(0.16, 0.22, 0.30)
			);
		} else if (role == 2) {
			// Student: vibrant hoodies & sweaters
			col = pick_palette(
				s3, 6,
				vec3(0.72, 0.22, 0.20),
				vec3(0.18, 0.44, 0.68),
				vec3(0.20, 0.52, 0.34),
				vec3(0.82, 0.60, 0.16),
				vec3(0.50, 0.26, 0.56),
				vec3(0.78, 0.76, 0.72)
			);
		} else if (role == 3) {
			// Hospital / Clinic Medic: medical teal scrubs & crisp lab coats
			col = pick_palette(
				s3, 6,
				vec3(0.12, 0.52, 0.56),
				vec3(0.18, 0.44, 0.64),
				vec3(0.88, 0.90, 0.92),
				vec3(0.14, 0.48, 0.52),
				vec3(0.22, 0.56, 0.62),
				vec3(0.84, 0.88, 0.90)
			);
		} else if (role == 4) {
			// Industrial / Logistics: safety amber vests & rugged navy work jackets
			col = pick_palette(
				s3, 6,
				vec3(0.86, 0.56, 0.10),
				vec3(0.16, 0.24, 0.36),
				vec3(0.76, 0.42, 0.12),
				vec3(0.24, 0.28, 0.30),
				vec3(0.80, 0.68, 0.14),
				vec3(0.20, 0.30, 0.38)
			);
		} else {
			// Retail, Residents & Night-shift: broad natural urban wardrobe
			col = pick_palette(
				s3, 6,
				vec3(0.16, 0.28, 0.44),
				vec3(0.64, 0.22, 0.20),
				vec3(0.20, 0.42, 0.32),
				vec3(0.74, 0.56, 0.22),
				vec3(0.32, 0.34, 0.38),
				vec3(0.76, 0.74, 0.70)
			);
		}
		rough = 0.84;
	} else if (part < 0.88) {
		// Pants / Trousers
		if (role == 3) {
			col = mix(vec3(0.12, 0.44, 0.50), vec3(0.16, 0.22, 0.32), step(0.55, s4));
		} else if (role == 0) {
			col = mix(vec3(0.13, 0.15, 0.20), vec3(0.24, 0.25, 0.28), s4);
		} else {
			col = pick_palette(
				s4, 6,
				vec3(0.14, 0.17, 0.24),
				vec3(0.20, 0.30, 0.46),
				vec3(0.48, 0.43, 0.34),
				vec3(0.16, 0.16, 0.18),
				vec3(0.28, 0.22, 0.18),
				vec3(0.24, 0.26, 0.28)
			);
		}
		rough = 0.86;
	} else {
		// Shoes
		col = mix(vec3(0.12, 0.12, 0.14), vec3(0.76, 0.76, 0.74), step(0.65, s2));
		rough = 0.68;
	}

	float ao_shade = clamp(v_color.a, 0.78, 1.05);
	col *= ao_shade;
	col *= mix(1.0, 0.80, weather_wetness);
	col *= mix(1.0, 1.06, night_factor);

	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.42, weather_wetness * 0.65);
	METALLIC = 0.0;
	SPECULAR = mix(0.28, 0.58, weather_wetness);
	}
}
