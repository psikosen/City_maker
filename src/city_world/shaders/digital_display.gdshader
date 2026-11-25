shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 bg_color : source_color = vec3(0.03, 0.05, 0.08);
uniform vec3 glow_primary : source_color = vec3(0.10, 0.90, 0.72);
uniform vec3 glow_accent : source_color = vec3(0.26, 0.65, 1.00);

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Crisp matte OLED glass bezel around UI screen
	vec2 buv = abs(UV - 0.5) * 2.0;
	float fw = max(fwidth(UV.x), fwidth(UV.y));
	float bezel = 1.0 - smoothstep(0.86 - fw, 0.90 + fw, max(buv.x, buv.y));

	// Horizontal schedule / charge telemetry UI rows + animated pulse bar
	float phase = v_world_pos.x * 0.37 + v_world_pos.z * 0.51;
	float scan = 0.88 + 0.12 * sin(UV.y * 120.0);

	// Top status header pill
	float header = step(0.14, UV.y) * (1.0 - step(0.26, UV.y)) * step(0.12, UV.x) * (1.0 - step(0.88, UV.x));

	// Three animated status / arrival bars in lower 60%
	float row_coord = (UV.y - 0.34) / 0.16;
	float row_idx = floor(row_coord);
	float in_row = step(0.0, row_idx) * (1.0 - step(3.0, row_idx));
	float row_f = fract(row_coord);
	float bar_band = smoothstep(0.20, 0.28, row_f) * (1.0 - smoothstep(0.72, 0.80, row_f));
	float bar_fill_len = 0.38 + 0.42 * fract(sin(row_idx * 17.3 + phase) * 43.1 + TIME * (0.14 + row_idx * 0.05));
	float bar = in_row * bar_band * step(0.14, UV.x) * (1.0 - smoothstep(bar_fill_len - 0.02, bar_fill_len + 0.02, UV.x));

	// Animated EV charging waveform pulse line near bottom
	float wave_y = 0.84 + 0.03 * sin(UV.x * 24.0 - TIME * 3.8 + phase);
	float wave = (1.0 - smoothstep(0.008, 0.024, abs(UV.y - wave_y))) * step(0.14, UV.x) * (1.0 - step(0.86, UV.x));

	vec3 ui_col = glow_primary * (header * 0.9 + wave * 1.15) + mix(glow_primary, glow_accent, 0.45) * bar;
	vec3 screen = (bg_color + ui_col * 0.35) * scan;

	ALBEDO = mix(vec3(0.05, 0.06, 0.07), screen, bezel);
	EMISSION = ui_col * bezel * 1.55 * scan;
	ROUGHNESS = mix(0.42, 0.06, bezel);
	METALLIC = mix(0.60, 0.12, bezel);
	SPECULAR = 0.88;
}
