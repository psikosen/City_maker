shader_type particles;

global uniform float weather_snow;
global uniform vec2 wind_vector;

uniform vec3 emitter_center = vec3(768.0, 12.0, 768.0);
uniform float box_half_xz = 24.0;
uniform float box_half_y = 13.0;
uniform int nearby_bld_count = 0;
uniform vec4 nearby_bld_obb[8]; // (center_x, center_z, cos_yaw, sin_yaw)
uniform vec4 nearby_bld_ext[8]; // (half_w, half_d, min_y, max_y)

float hash1u(uint x) {
	x = ((x >> 16u) ^ x) * 0x45d9f3bu;
	x = ((x >> 16u) ^ x) * 0x45d9f3bu;
	x = (x >> 16u) ^ x;
	return float(x & 0x00ffffffu) / float(0x01000000u);
}

bool is_inside_building(vec3 p) {
	for (int i = 0; i < 8; i++) {
		if (i >= nearby_bld_count) {
			break;
		}
		vec4 ext = nearby_bld_ext[i];
		if (p.y < ext.z - 0.1 || p.y > ext.w + 0.18) {
			continue;
		}
		vec4 obb = nearby_bld_obb[i];
		vec2 d = p.xz - obb.xy;
		float lx = abs(d.x * obb.z - d.y * obb.w);
		float lz = abs(d.x * obb.w + d.y * obb.z);
		if (lx < ext.x + 0.14 && lz < ext.y + 0.14) {
			return true;
		}
	}
	return false;
}

void start() {
	uint seed = uint(INDEX) * 2657u + 6133u + uint(RANDOM_SEED);
	float rx = (hash1u(seed) * 2.0 - 1.0) * box_half_xz;
	float ry = (hash1u(seed + 19u) * 2.0 - 1.0) * box_half_y;
	float rz = (hash1u(seed + 59u) * 2.0 - 1.0) * box_half_xz;
	float flake_sz = 0.65 + 0.85 * hash1u(seed + 107u);
	float phase = hash1u(seed + 211u) * 6.283185;

	TRANSFORM = mat4(
		vec4(1.0, 0.0, 0.0, 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(emitter_center + vec3(rx, ry, rz), 1.0)
	);
	VELOCITY = vec3(wind_vector.x * 1.45, -1.75 * flake_sz, wind_vector.y * 1.45);
	CUSTOM = vec4(hash1u(seed + 307u), flake_sz, phase, 1.0);
}

void process() {
	float flake_sz = CUSTOM.y > 0.1 ? CUSTOM.y : 1.0;
	float phase = CUSTOM.z;
	float gust_t = TIME * 1.35 + phase;
	// Gentle swirling turbulence + blizzard wind drift
	float swirl_x = sin(gust_t) * 0.72 + cos(gust_t * 1.7 + phase) * 0.35;
	float swirl_z = cos(gust_t * 1.15) * 0.72 - sin(gust_t * 1.45 + phase) * 0.35;
	float fall_spd = mix(1.45, 3.15, clamp(weather_snow, 0.0, 1.0)) * (0.72 + 0.38 * flake_sz);
	VELOCITY = vec3(wind_vector.x * 1.65 + swirl_x, -fall_spd, wind_vector.y * 1.65 + swirl_z);

	vec3 pos = TRANSFORM[3].xyz + VELOCITY * DELTA;
	vec3 rel = pos - emitter_center;
	float span_xz = box_half_xz * 2.0;
	float span_y = box_half_y * 2.0;
	rel.x = mod(rel.x + box_half_xz, span_xz) - box_half_xz;
	rel.y = mod(rel.y + box_half_y, span_y) - box_half_y;
	rel.z = mod(rel.z + box_half_xz, span_xz) - box_half_xz;
	pos = emitter_center + rel;
	TRANSFORM[3].xyz = pos;

	bool active_flake = (weather_snow > 0.02) && (CUSTOM.x <= clamp(weather_snow * 1.12, 0.0, 1.0));
	if (active_flake && is_inside_building(pos)) {
		active_flake = false;
	}
	float edge_fade = 1.0 - smoothstep(box_half_xz * 0.68, box_half_xz * 0.98, length(rel.xz));
	CUSTOM.w = active_flake ? edge_fade * clamp(weather_snow * 1.25, 0.0, 1.0) : 0.0;
}
