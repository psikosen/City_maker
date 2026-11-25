class_name TerrainGenerator
extends RefCounted

## Generates natural hills, creek valleys, district pads, and grades terrain along road corridors.

static func generate_base_terrain(config: CityConfig, district_centers: Dictionary) -> TerrainData:
	var terrain := TerrainData.new()
	terrain.initialize(config.world_size, config.terrain_step)
	terrain.water_level = 1.6
	terrain.creek_half_width = 22.0
	terrain.beach_enabled = (config.world_size >= 1024.0)
	terrain.coast_road_z = config.world_size - 282.0
	terrain.beach_shore_z = config.world_size - 166.0
	terrain.beach_phase = float(district_centers.get("creek_phase", 0.0)) * 0.72 + 0.85

	# Sample river centerline from z = -8 to size + 8.
	var poly := PackedVector2Array()
	var step_c := 8.0
	var z := -8.0
	while z <= config.world_size + 8.01:
		var cx := DistrictGenerator.eval_creek_x(z, district_centers)
		poly.append(Vector2(cx, z))
		z += step_c
	terrain.creek_polyline = poly

	var noise := FastNoiseLite.new()
	noise.seed = config.world_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.0045
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.fractal_lacunarity = 2.05
	noise.fractal_gain = 0.48

	var detail_noise := FastNoiseLite.new()
	detail_noise.seed = config.world_seed + 9173
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail_noise.frequency = 0.016
	detail_noise.fractal_octaves = 2

	var res_center: Vector2 = district_centers["residential_hills"]
	var dt_center: Vector2 = district_centers["downtown_mixed"]
	var ind_center: Vector2 = district_centers["light_industrial"]
	var hill_radius := maxf(240.0, config.world_size * 0.46)
	var dt_radius := maxf(145.0, config.world_size * 0.28)
	var ind_radius := maxf(135.0, config.world_size * 0.26)
	var inv_hill := 1.0 / hill_radius
	var inv_dt := 1.0 / dt_radius
	var inv_ind := 1.0 / ind_radius
	var bank_reach := terrain.creek_half_width + 32.0
	var inv_bank := 1.0 / 32.0
	var creek_hw := terrain.creek_half_width
	var w_lvl := terrain.water_level

	var hill_r_sq := hill_radius * hill_radius
	var dt_r_sq := dt_radius * dt_radius
	var ind_r_sq := ind_radius * ind_radius
	var h_arr := terrain.heights
	var gw := terrain.grid_w

	for iz in range(terrain.grid_d):
		var wz := float(iz) * terrain.step_m
		var cx_at_z := DistrictGenerator.eval_creek_x(wz, district_centers)
		var dz_res := wz - res_center.y
		var dz_res_sq := dz_res * dz_res
		var dz_dt := wz - dt_center.y
		var dz_dt_sq := dz_dt * dz_dt
		var dz_ind := wz - ind_center.y
		var dz_ind_sq := dz_ind * dz_ind
		var row_offset := iz * gw
		for ix in range(gw):
			var wx := float(ix) * terrain.step_m

			# Base undulating terrain (3.8m to 9.2m).
			var n_val := noise.get_noise_2d(wx, wz) * 0.5 + 0.5
			var d_val := detail_noise.get_noise_2d(wx, wz)
			var h := 3.8 + n_val * 5.2 + d_val * 0.9

			# Elevate rolling hills toward the residential district & upper slopes.
			var dx_res := wx - res_center.x
			var res_sq := dx_res * dx_res + dz_res_sq
			if res_sq < hill_r_sq:
				var hill_w := 1.0 - sqrt(res_sq) * inv_hill
				h += (hill_w * hill_w) * 7.8

			# Gently level downtown & industrial pads toward ~4.6m - 5.4m so urban towers sit coherently.
			var dx_dt := wx - dt_center.x
			var dt_sq := dx_dt * dx_dt + dz_dt_sq
			var dt_w := (1.0 - sqrt(dt_sq) * inv_dt) if dt_sq < dt_r_sq else 0.0

			var dx_ind := wx - ind_center.x
			var ind_sq := dx_ind * dx_ind + dz_ind_sq
			var ind_w := (1.0 - sqrt(ind_sq) * inv_ind) if ind_sq < ind_r_sq else 0.0

			var urban_flat_w := clampf(maxf(dt_w, ind_w) * 1.15, 0.0, 0.88)
			if urban_flat_w > 0.0:
				h = lerpf(h, 4.8 + d_val * 0.35, urban_flat_w)

			# Carve broad river valley + deep navigation channel across the greenbelt.
			var dc := absf(wx - cx_at_z)
			if dc < bank_reach:
				if dc < creek_hw:
					var t_bed := dc / creek_hw
					var bed_curve := t_bed * t_bed * (2.0 - t_bed)
					var bed_h := lerpf(w_lvl - 3.1, w_lvl + 0.35, bed_curve)
					h = minf(h, bed_h)
				else:
					var bank_t := (dc - creek_hw) * inv_bank
					var smooth_b := bank_t * bank_t * (3.0 - 2.0 * bank_t)
					var bank_target := lerpf(w_lvl + 0.35, h, smooth_b)
					h = lerpf(bank_target, h, smooth_b * 0.4)

			# Sculpt South Coast Beachfront: elevated dune terrace -> wide golden beach -> ocean seabed!
			if terrain.beach_enabled:
				var shore_z := terrain.get_beach_shore_z(wx)
				var z_rel := wz - shore_z
				if z_rel > -148.0:
					var dune_undul := sin(wx * 0.025 + wz * 0.015) * 0.22 + d_val * 0.16
					var coast_h := h
					if z_rel < -72.0:
						# Gentle coastal shelf for OCEANFRONT BLVD & beach houses (~4.35m -> 3.05m)
						var tb := clampf((z_rel + 148.0) / 76.0, 0.0, 1.0)
						var sb := tb * tb * (3.0 - 2.0 * tb)
						var terrace_h := lerpf(4.45, 3.05, sb) + dune_undul * 0.5
						coast_h = lerpf(h, terrace_h, sb)
					elif z_rel < 0.0:
						# Wide 72m walkable golden sandy beach sloping smoothly down to shoreline water_level
						var ts := clampf((z_rel + 72.0) / 72.0, 0.0, 1.0)
						var ss := ts * ts * (2.2 - 1.2 * ts)
						coast_h = lerpf(3.05 + dune_undul * 0.45, w_lvl, ss)
					else:
						# Smooth underwater sandy ocean floor sloping from water_level down to -4.6m offshore
						var to := clampf(z_rel / 170.0, 0.0, 1.0)
						var so := pow(to, 0.78)
						coast_h = lerpf(w_lvl, w_lvl - 6.2, so)

					# Preserve river channel carved below coastal terrace; seamlessly merge river mouth into ocean bay
					if dc < bank_reach and z_rel < 18.0:
						var estuary_blend := clampf((z_rel + 40.0) / 58.0, 0.0, 1.0)
						h = minf(h, coast_h) if estuary_blend < 0.5 else lerpf(minf(h, coast_h), minf(coast_h, w_lvl - 2.6), (estuary_blend - 0.5) * 2.0)
					else:
						h = coast_h

			h_arr[row_offset + ix] = h

	return terrain


static func grade_terrain_to_roads(terrain: TerrainData, road_graph: RoadGraph) -> void:
	## Modifies the authoritative heightfield along non-bridge road corridors and junctions
	## so roads sit flush with zero terrain clipping and smooth side embankments.
	var grid_w := terrain.grid_w
	var grid_d := terrain.grid_d
	var step := terrain.step_m

	# Accumulate blended weights and target heights per grid vertex to avoid edge-order bias.
	var target_sum := PackedFloat32Array()
	var weight_max := PackedFloat32Array()
	var weight_sum := PackedFloat32Array()
	var asphalt_depress := PackedFloat32Array()
	var n_verts := grid_w * grid_d
	target_sum.resize(n_verts)
	weight_max.resize(n_verts)
	weight_sum.resize(n_verts)
	asphalt_depress.resize(n_verts)
	target_sum.fill(0.0)
	weight_max.fill(0.0)
	weight_sum.fill(0.0)
	asphalt_depress.fill(0.0)

	var shoulder_w := 7.0

	# 1. Stamp each road edge segment.
	for edge in road_graph.edges:
		var pa := road_graph.nodes[edge.node_a].pos
		var pb := road_graph.nodes[edge.node_b].pos
		var edge_len := pa.distance_to(pb)
		if edge_len < 0.1:
			continue
		var half_r := edge.road_width * 0.5
		var total_w := half_r + edge.sidewalk_width
		var reach := total_w + shoulder_w

		var min_x := clampi(int(floor((minf(pa.x, pb.x) - reach) / step)), 0, grid_w - 1)
		var max_x := clampi(int(ceil((maxf(pa.x, pb.x) + reach) / step)), 0, grid_w - 1)
		var min_z := clampi(int(floor((minf(pa.y, pb.y) - reach) / step)), 0, grid_d - 1)
		var max_z := clampi(int(ceil((maxf(pa.y, pb.y) + reach) / step)), 0, grid_d - 1)

		var ab := pb - pa
		var len_sq := ab.length_squared()
		var inv_len_sq := 1.0 / maxf(0.0001, len_sq)
		var reach_sq := reach * reach

		for iz in range(min_z, max_z + 1):
			var wz := float(iz) * step
			for ix in range(min_x, max_x + 1):
				var wx := float(ix) * step
				var dx_p := wx - pa.x
				var dz_p := wz - pa.y
				var t := clampf((dx_p * ab.x + dz_p * ab.y) * inv_len_sq, 0.0, 1.0)
				if edge.is_bridge and t > edge.bridge_start_t and t < edge.bridge_end_t:
					continue
				var px := pa.x + ab.x * t
				var pz := pa.y + ab.y * t
				var ddx := wx - px
				var ddz := wz - pz
				var dist_sq := ddx * ddx + ddz * ddz
				if dist_sq > reach_sq:
					continue
				var dist := sqrt(dist_sq)

				var road_pt3 := road_graph.sample_edge_point_3d(edge, t)
				var w := 1.0
				if dist > total_w + 0.35:
					var u := (dist - (total_w + 0.35)) / (shoulder_w - 0.35)
					u = clampf(u, 0.0, 1.0)
					w = 1.0 - (u * u * (3.0 - 2.0 * u))

				var idx := iz * grid_w + ix
				target_sum[idx] += road_pt3.y * w
				weight_sum[idx] += w
				weight_max[idx] = maxf(weight_max[idx], w)

				if dist <= half_r + 0.25:
					asphalt_depress[idx] = maxf(asphalt_depress[idx], 0.14)

	# 2. Stamp intersection discs so junction centers stay crisp and flat.
	for node in road_graph.nodes:
		var reach := maxf(node.miter_radius, 8.0) + shoulder_w
		var min_x := clampi(int(floor((node.pos.x - reach) / step)), 0, grid_w - 1)
		var max_x := clampi(int(ceil((node.pos.x + reach) / step)), 0, grid_w - 1)
		var min_z := clampi(int(floor((node.pos.y - reach) / step)), 0, grid_d - 1)
		var max_z := clampi(int(ceil((node.pos.y + reach) / step)), 0, grid_d - 1)
		var flat_r := maxf(node.miter_radius + 1.5, 6.5)

		for iz in range(min_z, max_z + 1):
			var wz := float(iz) * step
			for ix in range(min_x, max_x + 1):
				var wx := float(ix) * step
				var dist := Vector2(wx, wz).distance_to(node.pos)
				if dist > flat_r + shoulder_w:
					continue
				var w := 1.0
				if dist > flat_r:
					var u := clampf((dist - flat_r) / shoulder_w, 0.0, 1.0)
					w = 1.0 - (u * u * (3.0 - 2.0 * u))
				var idx := iz * grid_w + ix
				target_sum[idx] += node.elevation * w
				weight_sum[idx] += w
				weight_max[idx] = maxf(weight_max[idx], w)
				if dist <= maxf(4.0, node.miter_radius - 0.5):
					asphalt_depress[idx] = maxf(asphalt_depress[idx], 0.14)

	# 3. Apply blended grading to terrain heightfield.
	for i in range(n_verts):
		var ws := weight_sum[i]
		if ws > 0.0001:
			var road_target := target_sum[i] / ws
			var alpha := clampf(weight_max[i], 0.0, 1.0)
			terrain.heights[i] = lerpf(terrain.heights[i], road_target, alpha) - asphalt_depress[i] * alpha


static func grade_terrain_to_buildings(terrain: TerrainData, blueprints: Array[BuildingBlueprint]) -> void:
	## Excavates terrain vertices under every building footprint cleanly below ground slab elevation
	## (tapered smoothly on side/rear setbacks) so sloped hillside terrain never pokes through floors.
	var grid_w := terrain.grid_w
	var grid_d := terrain.grid_d
	var step := terrain.step_m

	for bp in blueprints:
		var hw := bp.width * 0.5
		var hd := bp.depth * 0.5
		var pad_max_y := bp.base_y - 0.22
		var right := Vector2(cos(bp.yaw), -sin(bp.yaw))
		var forward := Vector2(sin(bp.yaw), cos(bp.yaw))
		var front_flat := 0.72
		var front_reach := 1.15
		var side_flat := 0.90
		var side_reach := 2.45
		var bound_r := sqrt(hw * hw + hd * hd) + side_reach + step

		var min_x := clampi(int(floor((bp.center.x - bound_r) / step)), 0, grid_w - 1)
		var max_x := clampi(int(ceil((bp.center.x + bound_r) / step)), 0, grid_w - 1)
		var min_z := clampi(int(floor((bp.center.y - bound_r) / step)), 0, grid_d - 1)
		var max_z := clampi(int(ceil((bp.center.y + bound_r) / step)), 0, grid_d - 1)

		for iz in range(min_z, max_z + 1):
			var wz := float(iz) * step
			for ix in range(min_x, max_x + 1):
				var wx := float(ix) * step
				var d := Vector2(wx, wz) - bp.center
				var lx := absf(d.dot(right))
				var lz := d.dot(forward)
				var dx_out := lx - hw
				var dz_out := (lz - hd) if lz >= 0.0 else (-lz - hd)
				var reach_z := front_reach if lz > 0.0 else side_reach
				var flat_z := front_flat if lz > 0.0 else side_flat
				if dx_out > side_reach or dz_out > reach_z:
					continue

				var t_x := clampf((dx_out - side_flat) / (side_reach - side_flat), 0.0, 1.0)
				var t_z := clampf((dz_out - flat_z) / (reach_z - flat_z), 0.0, 1.0)
				var u := maxf(t_x, t_z)
				var idx := iz * grid_w + ix
				var h_cur := terrain.heights[idx]
				if h_cur <= pad_max_y:
					continue
				var s := u * u * (3.0 - 2.0 * u)
				var cap := lerpf(pad_max_y, h_cur, s)
				terrain.heights[idx] = minf(h_cur, cap)
