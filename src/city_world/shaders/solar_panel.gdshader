shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 silicon_color : source_color = vec3(0.05, 0.09, 0.20);
uniform vec3 grid_color : source_color = vec3(0.68, 0.75, 0.82);

varying vec3 v_local_pos;

void vertex() {
	v_local_pos = VERTEX;
}

void fragment() {
	// Derivative-filtered monocrystalline 0.18m photovoltaic cell array
	vec2 p_uv = v_local_pos.xz / 0.18;
	vec2 cell = fract(p_uv);
	vec2 fw = max(fwidth(p_uv), vec2(0.001));
	float detail_fade = 1.0 - smoothstep(0.25, 0.75, max(fw.x, fw.y));

	float edge_dist = min(min(cell.x, 1.0 - cell.x), min(cell.y, 1.0 - cell.y));
	float corner_dist = abs(cell.x - 0.5) + abs(cell.y - 0.5);

	float seam = 1.0 - smoothstep(0.01, max(0.032, max(fw.x, fw.y) * 1.1), edge_dist);
	float diamond = smoothstep(0.84, 0.90, corner_dist);
	float busbar = (1.0 - smoothstep(0.0, max(0.014, fw.x * 0.9), abs(cell.x - 0.5))) * 0.55;
	float silver_mask = clamp(max(seam, max(diamond, busbar)), 0.0, 1.0) * detail_fade;

	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 3.0);
	vec3 cell_col = mix(silicon_color, vec3(0.14, 0.24, 0.44), fresnel * 0.65);

	ALBEDO = mix(cell_col, grid_color, silver_mask * 0.82);
	ROUGHNESS = mix(0.12, 0.36, silver_mask);
	METALLIC = mix(0.76, 0.90, silver_mask);
	SPECULAR = 0.88;
}
