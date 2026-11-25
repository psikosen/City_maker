class_name EnvironmentGenerator
extends RefCounted

## Generates contextual 2028 street-level props (streetlights, smart signals, transit shelters,
## EV charging stations, street trees, park furniture, bollards, and parked EVs).

const BILLBOARD_ADS := [
	["MERIDIAN FIBER", "10G SYMMETRIC METRO"],
	["SOLARIS EV", "ZERO-EMISSION FLEET"],
	["KINETIC LABS", "NEXT-GEN ROBOTICS"],
	["AUSTIN METRO", "RAPID RAIL & BUS"],
	["VERDANT BANK", "GREEN CITY BONDS"],
	["CLOUDLINE AIR", "NONSTOP TERMINAL B"],
]

const MAX_DECALS_PER_CHUNK := 10
const GRID_CELL_BP := 32.0
const GRID_CELL_PROP := 16.0
const GRID_CELL_ROAD := 64.0


static func generate(
	config: CityConfig,
	terrain: TerrainData,
	road_graph: RoadGraph,
	parcels: Array,
	blueprints: Array[BuildingBlueprint],
	rng: RandomNumberGenerator,
	park_walkways: Array = []
) -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	if not config.enable_props:
		return props

	# Precompute building entrance & fire-bay exclusion zones and spatial hashes.
	var door_zones: Array[Vector2] = []
	for bp in blueprints:
		var door_w := bp.get_door_world_pos()
		var app_w := bp.get_approach_world_pos()
		door_zones.append(Vector2(door_w.x, door_w.z))
		door_zones.append(Vector2(app_w.x, app_w.z))
		if bp.archetype == "fire_station":
			for bx_off: float in [-bp.width * 0.06, bp.width * 0.16, bp.width * 0.34]:
				door_zones.append(bp.local_to_world_2d(Vector2(bx_off, bp.depth * 0.5 + 2.8)))

	var parcel_map: Dictionary = {}
	for p in parcels:
		parcel_map[p.id] = p

	var bp_grid := _build_bp_grid(blueprints)
	var door_grid := _build_pt_grid(door_zones, GRID_CELL_PROP)
	var road_grid := _build_road_grid(road_graph)
	var creek_x_range := _compute_creek_x_range(terrain, 32.0)
	var walkway_aabbs := _build_walkway_aabbs(park_walkways)
	var placed_2d: Array[Vector2] = []
	var placed_grid: Dictionary = {}
	var placed_fence_mids: Dictionary = {}

	# 1. Smart traffic signals & corner street-name signs at intersections.
	for node in road_graph.nodes:
		var k := node.incident_edge_ids.size()
		if k < 3:
			continue

		if node.has_traffic_signal:
			for i in range(mini(k, 4)):
				var e := road_graph.edges[node.incident_edge_ids[i]]
				var other := road_graph.get_other_node(e, node.id)
				var dir := (road_graph.nodes[other].pos - node.pos).normalized()
				var right := Vector2(-dir.y, dir.x)
				var trim := e.trim_a if e.node_a == node.id else e.trim_b
				var pos2 := node.pos + dir * (trim - 0.6) + right * (e.road_width * 0.5 + 0.55)
				var yaw := atan2(-dir.x, -dir.y)
				var y := node.elevation + 0.15
				props.append(_make_prop("traffic_signal", Vector3(pos2.x, y, pos2.y), yaw, config))
				_add_placed(pos2, placed_2d, placed_grid)
				var btn_pos := node.pos + dir * (trim - 1.55) + right * (e.road_width * 0.5 + 0.52)
				if _outside_bps_fast(btn_pos, bp_grid, 1.0):
					props.append(_make_prop("crosswalk_button", Vector3(btn_pos.x, y, btn_pos.y), atan2(right.x, right.y), config))
					_add_placed(btn_pos, placed_2d, placed_grid)

		# Corner stacked street-name sign post at >= 3-way intersections
		var corner_names: Array[String] = []
		for eid in node.incident_edge_ids:
			var sname := road_graph.edges[eid].street_name
			if sname != "" and not (sname in corner_names):
				corner_names.append(sname)
				if corner_names.size() >= 2:
					break
		if not corner_names.is_empty():
			var se := road_graph.edges[node.incident_edge_ids[0]]
			if not se.is_bridge:
				var s_other := road_graph.get_other_node(se, node.id)
				var s_dir := (road_graph.nodes[s_other].pos - node.pos).normalized()
				var s_right := Vector2(-s_dir.y, s_dir.x)
				var s_trim := se.trim_a if se.node_a == node.id else se.trim_b
				var ss_pos := node.pos + s_dir * (s_trim - 0.5) - s_right * (se.road_width * 0.5 + 0.58)
				if _is_clear_fast(ss_pos, 1.8, 3.6, placed_grid, door_grid) and _outside_bps_fast(ss_pos, bp_grid, 1.5):
					var ss_prop := _make_prop("street_sign", Vector3(ss_pos.x, node.elevation + 0.15, ss_pos.y), atan2(s_dir.x, s_dir.y), config)
					ss_prop["label_a"] = corner_names[0]
					ss_prop["label_b"] = corner_names[1] if corner_names.size() > 1 else ""
					props.append(ss_prop)
					_add_placed(ss_pos, placed_2d, placed_grid)

	# 1b. Paved residential driveways for house_pitched & townhouse (before curb/yard scatter so aprons stay clear).
	var driveway_boxes := _generate_residential_driveways(
		config, terrain, road_graph, road_grid, creek_x_range, parcel_map, blueprints, bp_grid, walkway_aabbs, door_grid, placed_grid, props, rng
	)

	var downtown_c := Vector2(config.world_size * 0.5, config.world_size * 0.5)

	# 2. Streetlights, trees, transit shelters, EV chargers, hydrants, benches, planters, kiosks, billboards & EVs.
	for e in road_graph.edges:
		if e.sidewalk_width < 1.2 or e.samples.size() < 2:
			continue
		var pa := road_graph.nodes[e.node_a].pos
		var pb := road_graph.nodes[e.node_b].pos
		var edge_len := pa.distance_to(pb)
		var usable := edge_len - (e.trim_a + e.trim_b) - 4.0
		if usable < 14.0:
			continue

		var dir := (pb - pa).normalized()
		var right := Vector2(-dir.y, dir.x)
		var yaw_forward := atan2(dir.x, dir.y)
		var half_r := e.road_width * 0.5

		# Streetlights every ~28m on alternating sides.
		var spacing := 26.0 if e.road_class == "arterial" else 34.0
		var steps := maxi(1, int(floor(usable / spacing)))
		for si in range(steps):
			var dist_along := e.trim_a + 4.0 + (float(si) + 0.5) * (usable / float(steps))
			var t := dist_along / edge_len
			if e.is_bridge and t >= e.bridge_start_t - 0.03 and t <= e.bridge_end_t + 0.03:
				continue
			var p3 := road_graph.sample_edge_point_3d(e, t)
			var side: float = 1.0 if (si % 2 == 0 or e.road_class == "arterial") else -1.0
			var sides: Array[float] = [side]
			if e.road_class == "arterial":
				sides = [1.0, -1.0]
			for s_sign in sides:
				var p2 := Vector2(p3.x, p3.z) + right * (s_sign * (half_r + 0.48))
				if _is_clear_fast(p2, 2.2, 3.6, placed_grid, door_grid) and _driveways_clear(p2, 1.4, driveway_boxes):
					var pole_yaw := atan2(-right.x * s_sign, -right.y * s_sign)
					props.append(_make_prop("streetlight", Vector3(p2.x, p3.y + 0.15, p2.y), pole_yaw, config))
					_add_placed(p2, placed_2d, placed_grid)

		# Transit shelter & EV charger along arterials/collectors.
		if e.road_class == "arterial" and usable > 34.0:
			var t_bus := clampf((e.trim_a + usable * 0.35) / edge_len, 0.25, 0.75)
			if not (e.is_bridge and t_bus >= e.bridge_start_t - 0.06 and t_bus <= e.bridge_end_t + 0.06):
				var p3_b := road_graph.sample_edge_point_3d(e, t_bus)
				var shelter_pos := Vector2(p3_b.x, p3_b.z) + right * (half_r + e.sidewalk_width - 0.85)
				if _is_clear_fast(shelter_pos, 3.6, 3.6, placed_grid, door_grid) and _outside_bps_fast(shelter_pos, bp_grid, 2.4):
					props.append(_make_prop("transit_shelter", Vector3(shelter_pos.x, p3_b.y + 0.15, shelter_pos.y), atan2(-right.x, -right.y), config))
					_add_placed(shelter_pos, placed_2d, placed_grid)

		if (e.road_class == "arterial" or e.road_class == "collector") and usable > 30.0 and rng.randf() < 0.55:
			var t_ev := clampf((e.trim_a + usable * 0.65) / edge_len, 0.25, 0.75)
			if not (e.is_bridge and t_ev >= e.bridge_start_t - 0.05 and t_ev <= e.bridge_end_t + 0.05):
				var p3_ev := road_graph.sample_edge_point_3d(e, t_ev)
				var ev_pos := Vector2(p3_ev.x, p3_ev.z) - right * (half_r + 0.75)
				if _is_clear_fast(ev_pos, 2.8, 3.6, placed_grid, door_grid) and _outside_bps_fast(ev_pos, bp_grid, 2.0):
					props.append(_make_prop("ev_charger", Vector3(ev_pos.x, p3_ev.y + 0.15, ev_pos.y), atan2(right.x, right.y), config))
					_add_placed(ev_pos, placed_2d, placed_grid)

		# Municipal waste & recycling trashcans along arterial/collector sidewalks.
		if (e.road_class == "arterial" or e.road_class == "collector") and usable > 24.0:
			for frac: float in ([0.22, 0.50, 0.78] if e.road_class == "arterial" else [0.30, 0.70]):
				var t_bin := clampf((e.trim_a + usable * frac) / edge_len, 0.14, 0.86)
				if e.is_bridge and t_bin >= e.bridge_start_t - 0.05 and t_bin <= e.bridge_end_t + 0.05:
					continue
				var p3_bin := road_graph.sample_edge_point_3d(e, t_bin)
				var s_bin := 1.0 if int(round(frac * 10.0)) % 2 == 0 else -1.0
				var bin_pos := Vector2(p3_bin.x, p3_bin.z) + right * (s_bin * (half_r + minf(e.sidewalk_width - 0.45, 0.72)))
				if _is_clear_fast(bin_pos, 2.2, 3.6, placed_grid, door_grid) and _outside_bps_fast(bin_pos, bp_grid, 1.5):
					var bin_prop := _make_prop("trashcan", Vector3(bin_pos.x, p3_bin.y + 0.15, bin_pos.y), atan2(-right.x * s_bin, -right.y * s_bin), config)
					bin_prop["variant"] = 0 if e.road_class == "arterial" else 1
					props.append(bin_prop)
					_add_placed(bin_pos, placed_2d, placed_grid)

		# Fire hydrants, mailboxes, utility boxes, planters, downtown benches, bike racks, kiosks & billboards.
		var mid2 := (pa + pb) * 0.5
		var is_urban_core := mid2.distance_to(downtown_c) <= config.world_size * 0.34 or e.road_class == "arterial"

		if (e.road_class == "arterial" or e.road_class == "collector") and usable > 18.0:
			var t_hyd := clampf((e.trim_a + 6.5) / edge_len, 0.09, 0.30)
			if not (e.is_bridge and t_hyd >= e.bridge_start_t - 0.05 and t_hyd <= e.bridge_end_t + 0.05):
				var p3_h := road_graph.sample_edge_point_3d(e, t_hyd)
				var h_pos := Vector2(p3_h.x, p3_h.z) + right * (half_r + 0.52)
				if _is_clear_fast(h_pos, 1.8, 3.6, placed_grid, door_grid) and _outside_bps_fast(h_pos, bp_grid, 1.2) and _driveways_clear(h_pos, 1.4, driveway_boxes):
					props.append(_make_prop("fire_hydrant", Vector3(h_pos.x, p3_h.y + 0.15, h_pos.y), atan2(-right.x, -right.y), config))
					_add_placed(h_pos, placed_2d, placed_grid)

		if (e.road_class == "arterial" or e.road_class == "collector") and usable > 26.0 and rng.randf() < 0.42:
			var t_mb := clampf((e.trim_a + usable * 0.16) / edge_len, 0.12, 0.88)
			if not (e.is_bridge and t_mb >= e.bridge_start_t - 0.05 and t_mb <= e.bridge_end_t + 0.05):
				var p3_mb := road_graph.sample_edge_point_3d(e, t_mb)
				var mb_pos := Vector2(p3_mb.x, p3_mb.z) - right * (half_r + minf(e.sidewalk_width - 0.55, 0.78))
				if _is_clear_fast(mb_pos, 2.2, 3.6, placed_grid, door_grid) and _outside_bps_fast(mb_pos, bp_grid, 1.5) and _driveways_clear(mb_pos, 1.4, driveway_boxes):
					props.append(_make_prop("mailbox", Vector3(mb_pos.x, p3_mb.y + 0.15, mb_pos.y), atan2(right.x, right.y), config))
					_add_placed(mb_pos, placed_2d, placed_grid)

		if e.road_class == "collector" and usable > 24.0 and rng.randf() < 0.38:
			var t_ub := clampf((e.trim_a + usable * 0.82) / edge_len, 0.12, 0.88)
			if not (e.is_bridge and t_ub >= e.bridge_start_t - 0.05 and t_ub <= e.bridge_end_t + 0.05):
				var p3_ub := road_graph.sample_edge_point_3d(e, t_ub)
				var ub_pos := Vector2(p3_ub.x, p3_ub.z) + right * (half_r + maxf(0.55, e.sidewalk_width - 0.52))
				if _is_clear_fast(ub_pos, 2.2, 3.6, placed_grid, door_grid) and _outside_bps_fast(ub_pos, bp_grid, 1.5) and _driveways_clear(ub_pos, 1.4, driveway_boxes):
					props.append(_make_prop("utility_box", Vector3(ub_pos.x, p3_ub.y + 0.15, ub_pos.y), atan2(-right.x, -right.y), config))
					_add_placed(ub_pos, placed_2d, placed_grid)

		if e.road_class == "arterial" and e.sidewalk_width >= 2.25 and usable > 34.0 and rng.randf() < 0.45:
			var t_lk := clampf((e.trim_a + usable * 0.62) / edge_len, 0.16, 0.84)
			if not (e.is_bridge and t_lk >= e.bridge_start_t - 0.05 and t_lk <= e.bridge_end_t + 0.05):
				var p3_lk := road_graph.sample_edge_point_3d(e, t_lk)
				var lk_pos := Vector2(p3_lk.x, p3_lk.z) + right * (half_r + e.sidewalk_width - 0.44)
				if _is_clear_fast(lk_pos, 3.0, 3.6, placed_grid, door_grid) and _outside_bps_fast(lk_pos, bp_grid, 1.15):
					props.append(_make_prop("parcel_locker", Vector3(lk_pos.x, p3_lk.y + 0.15, lk_pos.y), atan2(-right.x, -right.y), config))
					_add_placed(lk_pos, placed_2d, placed_grid)

		if is_urban_core and e.sidewalk_width >= 2.2 and usable > 28.0:
			for frac: float in [0.28, 0.72]:
				var t_pl := clampf((e.trim_a + usable * frac) / edge_len, 0.14, 0.86)
				if e.is_bridge and t_pl >= e.bridge_start_t - 0.05 and t_pl <= e.bridge_end_t + 0.05:
					continue
				var p3_pl := road_graph.sample_edge_point_3d(e, t_pl)
				var s_pl := -1.0 if frac < 0.5 else 1.0
				var pl_pos := Vector2(p3_pl.x, p3_pl.z) + right * (s_pl * (half_r + e.sidewalk_width - 0.76))
				if _is_clear_fast(pl_pos, 2.4, 3.6, placed_grid, door_grid) and _outside_bps_fast(pl_pos, bp_grid, 1.6):
					props.append(_make_prop("planter_box", Vector3(pl_pos.x, p3_pl.y + 0.15, pl_pos.y), yaw_forward, config))
					_add_placed(pl_pos, placed_2d, placed_grid)

		if e.road_class == "arterial" and e.sidewalk_width >= 2.5 and usable > 32.0:
			var t_sb := clampf((e.trim_a + usable * 0.44) / edge_len, 0.20, 0.80)
			if not (e.is_bridge and t_sb >= e.bridge_start_t - 0.05 and t_sb <= e.bridge_end_t + 0.05):
				var p3_sb := road_graph.sample_edge_point_3d(e, t_sb)
				var sb_pos := Vector2(p3_sb.x, p3_sb.z) - right * (half_r + e.sidewalk_width - 0.78)
				if _is_clear_fast(sb_pos, 2.8, 3.6, placed_grid, door_grid) and _outside_bps_fast(sb_pos, bp_grid, 1.8):
					props.append(_make_prop("sidewalk_bench", Vector3(sb_pos.x, p3_sb.y + 0.15, sb_pos.y), atan2(right.x, right.y), config))
					_add_placed(sb_pos, placed_2d, placed_grid)

		if is_urban_core and usable > 26.0 and rng.randf() < 0.46:
			var t_bk := clampf((e.trim_a + usable * 0.62) / edge_len, 0.18, 0.82)
			if not (e.is_bridge and t_bk >= e.bridge_start_t - 0.05 and t_bk <= e.bridge_end_t + 0.05):
				var p3_bk := road_graph.sample_edge_point_3d(e, t_bk)
				var bk_pos := Vector2(p3_bk.x, p3_bk.z) + right * (half_r + 0.68)
				if _is_clear_fast(bk_pos, 2.4, 3.6, placed_grid, door_grid) and _outside_bps_fast(bk_pos, bp_grid, 1.6):
					props.append(_make_prop("bike_rack", Vector3(bk_pos.x, p3_bk.y + 0.15, bk_pos.y), yaw_forward, config))
					_add_placed(bk_pos, placed_2d, placed_grid)

		if is_urban_core and e.road_class == "arterial" and usable > 32.0:
			for frac_kk: float in [0.56, 0.36, 0.78]:
				var t_kk := clampf((e.trim_a + usable * frac_kk) / edge_len, 0.18, 0.84)
				if e.is_bridge and t_kk >= e.bridge_start_t - 0.05 and t_kk <= e.bridge_end_t + 0.05:
					continue
				var s_kk := 1.0 if frac_kk < 0.65 else -1.0
				var p3_kk := road_graph.sample_edge_point_3d(e, t_kk)
				var kk_pos := Vector2(p3_kk.x, p3_kk.z) + right * (s_kk * (half_r + e.sidewalk_width - 0.84))
				if _is_clear_fast(kk_pos, 3.2, 3.6, placed_grid, door_grid) and _outside_bps_fast(kk_pos, bp_grid, 2.0):
					var kk_prop := _make_prop("city_kiosk", Vector3(kk_pos.x, p3_kk.y + 0.15, kk_pos.y), atan2(-right.x * s_kk, -right.y * s_kk), config)
					kk_prop["label_a"] = e.street_name if e.street_name != "" else "METRO CENTER"
					props.append(kk_prop)
					_add_placed(kk_pos, placed_2d, placed_grid)
					break

		if e.road_class == "arterial" and usable > 34.0 and rng.randf() < 0.65:
			var bb_placed := false
			for frac_bb: float in [0.16, 0.84, 0.34, 0.66, 0.50]:
				if bb_placed:
					break
				var t_bb := clampf((e.trim_a + usable * frac_bb) / edge_len, 0.14, 0.86)
				if e.is_bridge and t_bb >= e.bridge_start_t - 0.08 and t_bb <= e.bridge_end_t + 0.08:
					continue
				var p3_bb := road_graph.sample_edge_point_3d(e, t_bb)
				for s_bb: float in [1.0, -1.0]:
					var bb_pos := Vector2(p3_bb.x, p3_bb.z) + right * (s_bb * (half_r + e.sidewalk_width + 1.25))
					var hy_bb := terrain.sample_height(bb_pos.x, bb_pos.y)
					if hy_bb < terrain.water_level + 0.6 or terrain.distance_to_creek(bb_pos) <= terrain.creek_half_width + 3.5:
						continue
					if _is_clear_fast(bb_pos, 4.2, 3.6, placed_grid, door_grid) and _outside_bps_fast(bb_pos, bp_grid, 1.55):
						var ad_idx := rng.randi() % BILLBOARD_ADS.size()
						var bb_yaw := yaw_forward + s_bb * 1.08
						var bb_prop := _make_prop("billboard", Vector3(bb_pos.x, hy_bb, bb_pos.y), bb_yaw, config)
						bb_prop["variant"] = ad_idx
						bb_prop["label_a"] = BILLBOARD_ADS[ad_idx][0]
						bb_prop["label_b"] = BILLBOARD_ADS[ad_idx][1]
						props.append(bb_prop)
						_add_placed(bb_pos, placed_2d, placed_grid)
						bb_placed = true
						break

		# Street trees along sidewalks.
		var tree_count := int(floor(usable / 22.0))
		for ti in range(tree_count):
			var d_along := e.trim_a + 7.5 + float(ti) * 22.0 + rng.randf_range(-2.5, 2.5)
			var t := clampf(d_along / edge_len, 0.15, 0.85)
			if e.is_bridge and t >= e.bridge_start_t - 0.05 and t <= e.bridge_end_t + 0.05:
				continue
			var p3_t := road_graph.sample_edge_point_3d(e, t)
			var s_sign := 1.0 if rng.randf() < 0.5 else -1.0
			var curb_inset := clampf(e.sidewalk_width * 0.48, 0.84, minf(e.sidewalk_width - 0.60, 1.06))
			var t_pos := Vector2(p3_t.x, p3_t.z) + right * (s_sign * (half_r + curb_inset))
			if _is_clear_fast(t_pos, 3.0, 3.6, placed_grid, door_grid) and _outside_bps_fast(t_pos, bp_grid, 2.7) and _driveways_clear(t_pos, 1.8, driveway_boxes):
				var scale_v := rng.randf_range(0.85, 1.22)
				var t_yaw := rng.randf_range(0.0, TAU)
				var t_base := Vector3(t_pos.x, p3_t.y + 0.15, t_pos.y)
				var prop := _make_prop("street_tree", t_base, t_yaw, config)
				prop["bed_yaw"] = yaw_forward
				prop["scale"] = scale_v
				prop["species"] = _pick_street_species(e.road_class, rng)
				prop["variant"] = rng.randi_range(0, TreeGenerator.VARIANT_COUNT - 1)
				props.append(prop)
				_add_placed(t_pos, placed_2d, placed_grid)
				# Tuck ornamental groundcover fern/flowers cleanly inside the street-aligned soil bed
				var bed_off_a := dir * 0.36 + right * (s_sign * 0.20)
				var bed_off_b := -dir * 0.34 - right * (s_sign * 0.20)
				props.append(_make_flora("bush", t_base + Vector3(bed_off_a.x, 0.03, bed_off_a.y), rng.randf_range(0.0, TAU), rng.randf_range(0.38, 0.50), "ornamental_fern" if rng.randf() < 0.6 else "boxwood", rng.randi(), config))
				props.append(_make_flora("flower_patch", t_base + Vector3(bed_off_b.x, 0.03, bed_off_b.y), rng.randf_range(0.0, TAU), rng.randf_range(0.56, 0.72), FloraGenerator.FLOWER_SPECIES[rng.randi() % FloraGenerator.FLOWER_SPECIES.size()], rng.randi(), config))

		# Parked EV cars along local/collector curb edge (strictly inside curb lane, clear of junctions & driveways).
		if (e.road_class == "local" or e.road_class == "collector") and usable > 26.0 and rng.randf() < 0.72:
			var t_car := rng.randf_range(0.32, 0.68)
			if not (e.is_bridge and t_car >= e.bridge_start_t - 0.08 and t_car <= e.bridge_end_t + 0.08):
				var p3_c := road_graph.sample_edge_point_3d(e, t_car)
				var s_sign := 1.0 if rng.randf() < 0.5 else -1.0
				var c_pos := Vector2(p3_c.x, p3_c.z) + right * (s_sign * (half_r - 1.15))
				if _is_clear_fast(c_pos, 5.2, 3.6, placed_grid, door_grid) and _driveways_clear(c_pos, 2.2, driveway_boxes):
					var car_prop := _make_prop("parked_ev", Vector3(c_pos.x, p3_c.y, c_pos.y), yaw_forward if s_sign > 0 else yaw_forward + PI, config)
					car_prop["variant"] = rng.randi() % 4
					props.append(car_prop)
					_add_placed(c_pos, placed_2d, placed_grid)

	# 2b. Alleyway service micro-realism, commercial/industrial rear yards, & residential lot fencing.
	var dumpster_spots := _generate_alley_and_service_yards(
		config, terrain, road_graph, road_grid, creek_x_range, parcel_map, blueprints, bp_grid, walkway_aabbs, door_grid, placed_2d, placed_grid, driveway_boxes, placed_fence_mids, props, rng
	)
	_generate_residential_lot_fences(
		config, terrain, road_graph, road_grid, creek_x_range, parcel_map, blueprints, bp_grid, walkway_aabbs, door_grid, driveway_boxes, placed_fence_mids, props
	)

	# 3. Paved-plaza gazebos/fountains, trailside benches/trashcans/bollards, and park trees (keeping walkways & water clear!).
	var plaza_park_ids: Dictionary = {}
	var fountain_count := 0
	for w_var in park_walkways:
		var w: Dictionary = w_var
		var kind := String(w.get("kind", ""))
		if kind == "plaza":
			var pc: Vector2 = w["center"]
			var prad: float = float(w.get("radius", 3.6))
			var pid := String(w.get("parcel_id", ""))
			var is_fountain := bool(w.get("has_fountain", false))
			var is_gazebo := bool(w.get("has_gazebo", false))
			var is_major := bool(w.get("is_major_plaza", false))
			var blocked_angs: Array = w.get("blocked_angles", [])
			if is_fountain or is_gazebo:
				var hy_g := terrain.sample_height(pc.x, pc.y) + 0.05
				if is_fountain:
					props.append(_make_prop("park_fountain", Vector3(pc.x, hy_g, pc.y), 0.0, config))
					fountain_count += 1
				else:
					props.append(_make_prop("park_gazebo", Vector3(pc.x, hy_g, pc.y), rng.randf_range(0.0, TAU), config))
				_add_placed(pc, placed_2d, placed_grid)
				if pid != "":
					plaza_park_ids[pid] = true
				# Plant flowering shrubs & blossom clusters around outer border (keeping promenade walkable)
				var flora_r := (prad + 0.85) if is_major else (prad * 0.74)
				for g_ang: float in [0.785, 2.356, 3.927, 5.498]:
					if is_major and not _is_angle_clear(g_ang, blocked_angs, 0.45):
						continue
					var f_pt := pc + Vector2(cos(g_ang), sin(g_ang)) * flora_r
					if terrain.distance_to_creek(f_pt) >= terrain.creek_half_width + 2.2 and (not is_major or road_graph.distance_to_road_corridor(f_pt) >= 0.8):
						var f_hy := terrain.sample_height(f_pt.x, f_pt.y)
						if f_hy >= terrain.water_level + 0.35:
							var sp_b := String(FloraGenerator.BUSH_SPECIES[(int(round(g_ang * 2.0)) + rng.randi()) % FloraGenerator.BUSH_SPECIES.size()])
							props.append(_make_flora("bush", Vector3(f_pt.x, f_hy, f_pt.y), rng.randf_range(0.0, TAU), rng.randf_range(0.68, 0.92), sp_b, rng.randi(), config))
							var fl_pt := f_pt + Vector2(cos(g_ang + 0.45), sin(g_ang + 0.45)) * 0.65
							var fl_hy := terrain.sample_height(fl_pt.x, fl_pt.y)
							if fl_hy >= terrain.water_level + 0.35:
								var sp_fl := String(FloraGenerator.FLOWER_SPECIES[rng.randi() % FloraGenerator.FLOWER_SPECIES.size()])
								props.append(_make_flora("flower_patch", Vector3(fl_pt.x, fl_hy, fl_pt.y), rng.randf_range(0.0, TAU), rng.randf_range(0.85, 1.15), sp_fl, rng.randi(), config))
			# Seat a bench and litter bin neatly along the plaza apron facing inward (skipping walkway exits)
			var b_ang := rng.randf_range(0.0, TAU)
			for k_off in range(2):
				var ang := b_ang + float(k_off) * PI
				if not _is_angle_clear(ang, blocked_angs, 0.45):
					continue
				var side_pt := pc + Vector2(cos(ang), sin(ang)) * (prad + 0.95)
				if terrain.distance_to_creek(side_pt) >= terrain.creek_half_width + 2.4 and _is_clear_fast(side_pt, 2.5, 3.6, placed_grid, door_grid) and _outside_bps_fast(side_pt, bp_grid, 2.0) and _walkway_clear_fast(side_pt, 0.6, walkway_aabbs):
					var hy_s := terrain.sample_height(side_pt.x, side_pt.y)
					if hy_s >= terrain.water_level + 0.40:
						var face := (pc - side_pt).normalized()
						if k_off == 0:
							if not is_major:
								props.append(_make_prop("bench", Vector3(side_pt.x, hy_s, side_pt.y), atan2(-face.x, -face.y), config))
						else:
							var pbin := _make_prop("trashcan", Vector3(side_pt.x, hy_s, side_pt.y), atan2(-face.x, -face.y), config)
							pbin["variant"] = rng.randi() % 2
							props.append(pbin)
						_add_placed(side_pt, placed_2d, placed_grid)
		elif kind == "path":
			var pts: PackedVector2Array = w.get("points", PackedVector2Array())
			var pwidth := float(w.get("width", 2.2))
			var style_w := String(w.get("style", ""))
			if pts.size() < 2:
				continue
			var lamp_accum := 6.0
			var bench_accum := 14.0
			for si in range(pts.size() - 1):
				var a := pts[si]
				var b := pts[si + 1]
				var seg_len := a.distance_to(b)
				if seg_len < 0.2:
					continue
				var dir := (b - a) / seg_len
				var side_n := Vector2(-dir.y, dir.x)
				var mid := (a + b) * 0.5
				lamp_accum += seg_len
				bench_accum += seg_len
				if lamp_accum >= 18.0:
					lamp_accum = 0.0
					var side_s := 1.0 if (si % 2 == 0) else -1.0
					var b_pos := mid + side_n * (side_s * (pwidth * 0.5 + 0.36))
					if terrain.distance_to_creek(b_pos) >= terrain.creek_half_width + 2.0 and _walkway_clear_fast(b_pos, 0.25, walkway_aabbs) and _is_clear_fast(b_pos, 2.4, 3.6, placed_grid, door_grid) and _outside_bps_fast(b_pos, bp_grid, 1.8):
						var hy_l := terrain.sample_height(b_pos.x, b_pos.y)
						if hy_l >= terrain.water_level + 0.32:
							props.append(_make_prop("path_bollard", Vector3(b_pos.x, hy_l, b_pos.y), atan2(-side_n.x * side_s, -side_n.y * side_s), config))
							_add_placed(b_pos, placed_2d, placed_grid)
					# Plant alternating border flower & fern clusters beside greenway/loop path edges
					if style_w == "greenway" or style_w == "loop":
						var fl_pos := mid + side_n * (-side_s * (pwidth * 0.5 + 0.92))
						if terrain.distance_to_creek(fl_pos) >= terrain.creek_half_width + 1.8 and _walkway_clear_fast(fl_pos, 0.25, walkway_aabbs) and _outside_bps_fast(fl_pos, bp_grid, 2.0):
							var hy_fl := terrain.sample_height(fl_pos.x, fl_pos.y)
							if hy_fl >= terrain.water_level + 0.30:
								var is_sh := (si % 3 == 0)
								if is_sh:
									props.append(_make_flora("bush", Vector3(fl_pos.x, hy_fl, fl_pos.y), rng.randf_range(0.0, TAU), rng.randf_range(0.65, 0.96), FloraGenerator.BUSH_SPECIES[rng.randi() % FloraGenerator.BUSH_SPECIES.size()], rng.randi(), config))
								else:
									props.append(_make_flora("flower_patch", Vector3(fl_pos.x, hy_fl, fl_pos.y), rng.randf_range(0.0, TAU), rng.randf_range(0.85, 1.25), FloraGenerator.FLOWER_SPECIES[rng.randi() % FloraGenerator.FLOWER_SPECIES.size()], rng.randi(), config))
				if bench_accum >= 38.0 and (style_w == "greenway" or style_w == "loop"):
					bench_accum = 0.0
					var side_s2 := -1.0 if style_w == "greenway" else 1.0
					var bench_pt := mid + side_n * (side_s2 * (pwidth * 0.5 + 0.92))
					if terrain.distance_to_creek(bench_pt) >= terrain.creek_half_width + 2.4 and _walkway_clear_fast(bench_pt, 0.45, walkway_aabbs) and _is_clear_fast(bench_pt, 3.2, 3.6, placed_grid, door_grid) and _outside_bps_fast(bench_pt, bp_grid, 2.2):
						var hy_be := terrain.sample_height(bench_pt.x, bench_pt.y)
						if hy_be >= terrain.water_level + 0.42:
							var inward := -side_n * side_s2
							props.append(_make_prop("bench", Vector3(bench_pt.x, hy_be, bench_pt.y), atan2(-inward.x, -inward.y), config))
							_add_placed(bench_pt, placed_2d, placed_grid)
							var bin_pt := bench_pt + dir * 1.45
							if _walkway_clear_fast(bin_pt, 0.35, walkway_aabbs) and _is_clear_fast(bin_pt, 1.0, 3.6, placed_grid, door_grid):
								var gbin := _make_prop("trashcan", Vector3(bin_pt.x, terrain.sample_height(bin_pt.x, bin_pt.y), bin_pt.y), atan2(-inward.x, -inward.y), config)
								gbin["variant"] = 1
								props.append(gbin)
								_add_placed(bin_pt, placed_2d, placed_grid)

	# 3b. Reserve flat clearings for community & school multi-sport basketball courts before park tree scatter
	var sport_court_boxes: Array[Dictionary] = []
	var school_parcel_ids := {}
	for bp in blueprints:
		if bp.archetype == "school":
			school_parcel_ids[bp.parcel_id] = bp
	var court_candidates: Array = []
	for p in parcels:
		if school_parcel_ids.has(p.id):
			court_candidates.append(p)
	for p in parcels:
		if p.is_park and not school_parcel_ids.has(p.id):
			court_candidates.append(p)

	for pass_slope: float in [1.35, 3.2]:
		if sport_court_boxes.size() >= 2:
			break
		for p in court_candidates:
			if sport_court_boxes.size() >= 2:
				break
			var min_c := Vector2(INF, INF)
			var max_c := Vector2(-INF, -INF)
			for v in p.polygon:
				min_c.x = minf(min_c.x, v.x)
				min_c.y = minf(min_c.y, v.y)
				max_c.x = maxf(max_c.x, v.x)
				max_c.y = maxf(max_c.y, v.y)
			if max_c.x - min_c.x < 14.0 or max_c.y - min_c.y < 14.0:
				continue
			var p_center := (min_c + max_c) * 0.5
			var placed_on_p := false
			for _ca in range(40):
				if placed_on_p:
					break
				var pt_c: Vector2 = p_center if _ca == 0 else Vector2(rng.randf_range(min_c.x + 8.0, max_c.x - 8.0), rng.randf_range(min_c.y + 8.0, max_c.y - 8.0))
				if not ParcelData.point_in_convex_polygon(pt_c, p.polygon, -6.8):
					continue
				if terrain.distance_to_creek(pt_c) < terrain.creek_half_width + 8.5:
					continue
				if road_graph.distance_to_road_corridor(pt_c) < 9.8:
					continue
				if not _outside_bps_fast(pt_c, bp_grid, 9.2) or not _walkway_clear_fast(pt_c, 6.8, walkway_aabbs):
					continue
				if not _is_clear_fast(pt_c, 9.8, 3.6, placed_grid, door_grid):
					continue
				var yaw_opt := 0.0 if (_ca % 2 == 0) else PI * 0.5
				var ax_x := Vector2(cos(yaw_opt), -sin(yaw_opt))
				var ax_z := Vector2(sin(yaw_opt), cos(yaw_opt))
				var min_h := INF
				var max_h := -INF
				var valid_corners := true
				for sx_c: float in [-5.8, 0.0, 5.8]:
					for sz_c: float in [-8.8, 0.0, 8.8]:
						var cp: Vector2 = pt_c + ax_x * sx_c + ax_z * sz_c
						if not ParcelData.point_in_convex_polygon(cp, p.polygon, -0.5) or road_graph.distance_to_road_corridor(cp) < 1.2 or not _outside_bps_fast(cp, bp_grid, 1.4) or terrain.distance_to_creek(cp) < terrain.creek_half_width + 2.4 or not _walkway_clear_fast(cp, 1.2, walkway_aabbs):
							valid_corners = false
							break
						var ch := terrain.sample_height(cp.x, cp.y)
						min_h = minf(min_h, ch)
						max_h = maxf(max_h, ch)
					if not valid_corners:
						break
				if not valid_corners or min_h < terrain.water_level + 0.45 or (max_h - min_h) > pass_slope:
					continue
				var base_y := max_h - 0.02
				props.append(_make_prop("sport_court", Vector3(pt_c.x, base_y, pt_c.y), yaw_opt, config))
				_add_placed(pt_c, placed_2d, placed_grid)
				sport_court_boxes.append({"center": pt_c, "yaw": yaw_opt})
				placed_on_p = true

	for p in parcels:
		if not p.is_park:
			continue
		var min_v := Vector2(INF, INF)
		var max_v := Vector2(-INF, -INF)
		for v in p.polygon:
			min_v.x = minf(min_v.x, v.x)
			min_v.y = minf(min_v.y, v.y)
			max_v.x = maxf(max_v.x, v.x)
			max_v.y = maxf(max_v.y, v.y)

		var trees_added := 0
		for _attempt in range(70):
			if trees_added >= 24:
				break
			var pt := Vector2(rng.randf_range(min_v.x, max_v.x), rng.randf_range(min_v.y, max_v.y))
			if not ParcelData.point_in_convex_polygon(pt, p.polygon, -1.2):
				continue
			if terrain.distance_to_creek(pt) < terrain.creek_half_width + 2.5:
				continue
			var hy := terrain.sample_height(pt.x, pt.y)
			if hy < terrain.water_level + 0.35:
				continue
			if not _walkway_clear_fast(pt, 1.9, walkway_aabbs) or not _courts_clear(pt, 2.2, sport_court_boxes):
				continue
			if _is_clear_fast(pt, 4.5, 3.6, placed_grid, door_grid):
				var prop := _make_prop("park_tree", Vector3(pt.x, hy, pt.y), rng.randf_range(0.0, TAU), config)
				prop["scale"] = rng.randf_range(0.88, 1.38)
				prop["species"] = _pick_park_species(rng)
				prop["variant"] = rng.randi_range(0, TreeGenerator.VARIANT_COUNT - 1)
				props.append(prop)
				_add_placed(pt, placed_2d, placed_grid)
				trees_added += 1

		# Park grove ornamental bushes & wildflower drifts
		var park_flora := 0
		for _pf in range(44):
			if park_flora >= 22:
				break
			var f_pt := Vector2(rng.randf_range(min_v.x, max_v.x), rng.randf_range(min_v.y, max_v.y))
			if not ParcelData.point_in_convex_polygon(f_pt, p.polygon, -1.2):
				continue
			if terrain.distance_to_creek(f_pt) < terrain.creek_half_width + 2.2:
				continue
			var hy_pf := terrain.sample_height(f_pt.x, f_pt.y)
			if hy_pf < terrain.water_level + 0.35 or not _walkway_clear_fast(f_pt, 1.1, walkway_aabbs) or not _courts_clear(f_pt, 1.4, sport_court_boxes):
				continue
			if park_flora % 3 == 0:
				props.append(_make_flora("bush", Vector3(f_pt.x, hy_pf, f_pt.y), rng.randf_range(0.0, TAU), rng.randf_range(0.75, 1.18), FloraGenerator.BUSH_SPECIES[rng.randi() % FloraGenerator.BUSH_SPECIES.size()], rng.randi(), config))
			else:
				props.append(_make_flora("flower_patch", Vector3(f_pt.x, hy_pf, f_pt.y), rng.randf_range(0.0, TAU), rng.randf_range(0.90, 1.35), FloraGenerator.FLOWER_SPECIES[rng.randi() % FloraGenerator.FLOWER_SPECIES.size()], rng.randi(), config))
			park_flora += 1

		# Fallback creek-bank benches & bins if parcel had no mapped walkway
		if not plaza_park_ids.has(p.id):
			var benches_added := 0
			for _attempt in range(30):
				if benches_added >= 3:
					break
				var pt := Vector2(rng.randf_range(min_v.x, max_v.x), rng.randf_range(min_v.y, max_v.y))
				if not ParcelData.point_in_convex_polygon(pt, p.polygon, -2.0):
					continue
				var dc := terrain.distance_to_creek(pt)
				if dc < terrain.creek_half_width + 3.0 or dc > terrain.creek_half_width + 14.0:
					continue
				var hy := terrain.sample_height(pt.x, pt.y)
				if hy < terrain.water_level + 0.5:
					continue
				if _walkway_clear_fast(pt, 1.0, walkway_aabbs) and _is_clear_fast(pt, 5.0, 3.6, placed_grid, door_grid):
					props.append(_make_prop("bench", Vector3(pt.x, hy, pt.y), rng.randf_range(0.0, TAU), config))
					_add_placed(pt, placed_2d, placed_grid)
					benches_added += 1

			var park_bins := 0
			for _attempt in range(20):
				if park_bins >= 2:
					break
				var pt_b := Vector2(rng.randf_range(min_v.x, max_v.x), rng.randf_range(min_v.y, max_v.y))
				if not ParcelData.point_in_convex_polygon(pt_b, p.polygon, -1.6):
					continue
				if terrain.distance_to_creek(pt_b) < terrain.creek_half_width + 2.8:
					continue
				var hy_b := terrain.sample_height(pt_b.x, pt_b.y)
				if hy_b < terrain.water_level + 0.45:
					continue
				if _walkway_clear_fast(pt_b, 0.9, walkway_aabbs) and _is_clear_fast(pt_b, 3.2, 3.6, placed_grid, door_grid) and _outside_bps_fast(pt_b, bp_grid, 1.5):
					var pbin := _make_prop("trashcan", Vector3(pt_b.x, hy_b, pt_b.y), rng.randf_range(0.0, TAU), config)
					pbin["variant"] = rng.randi() % 2
					props.append(pbin)
					_add_placed(pt_b, placed_2d, placed_grid)
					park_bins += 1

	# 4. Yard & unbuilt-lot trees inside residential/open parcels for richer neighborhood greenery.
	for p in parcels:
		if p.is_park or p.district_zone == "light_industrial" or p.district_zone == "beachfront":
			continue
		var min_v := Vector2(INF, INF)
		var max_v := Vector2(-INF, -INF)
		for v in p.polygon:
			min_v.x = minf(min_v.x, v.x)
			min_v.y = minf(min_v.y, v.y)
			max_v.x = maxf(max_v.x, v.x)
			max_v.y = maxf(max_v.y, v.y)
		var box_area := maxf(0.0, (max_v.x - min_v.x) * (max_v.y - min_v.y))
		var max_trees := clampi(int(box_area / 450.0), 2, 5) if p.has_building else clampi(int(box_area / 280.0), 3, 12)
		var added := 0
		for _attempt in range(28):
			if added >= max_trees:
				break
			var pt := Vector2(rng.randf_range(min_v.x, max_v.x), rng.randf_range(min_v.y, max_v.y))
			if not ParcelData.point_in_convex_polygon(pt, p.polygon, -1.8):
				continue
			if terrain.distance_to_creek(pt) < terrain.creek_half_width + 2.5:
				continue
			if not _walkway_clear_fast(pt, 1.9, walkway_aabbs):
				continue
			if not _outside_bps_fast(pt, bp_grid, 4.4) or not _driveways_clear(pt, 1.8, driveway_boxes):
				continue
			if _is_clear_fast(pt, 4.5, 3.6, placed_grid, door_grid):
				var hy := terrain.sample_height(pt.x, pt.y)
				var prop := _make_prop("park_tree", Vector3(pt.x, hy, pt.y), rng.randf_range(0.0, TAU), config)
				prop["scale"] = rng.randf_range(0.8, 1.22)
				prop["species"] = _pick_yard_species(rng)
				prop["variant"] = rng.randi_range(0, TreeGenerator.VARIANT_COUNT - 1)
				props.append(prop)
				_add_placed(pt, placed_2d, placed_grid)
				added += 1

		# Yard ornamental bushes and wildflower patches across residential/open parcels
		var flora_cap := clampi(int(box_area / 320.0), 3, 10)
		for fi in range(flora_cap):
			var fpt := Vector2(rng.randf_range(min_v.x, max_v.x), rng.randf_range(min_v.y, max_v.y))
			if not ParcelData.point_in_convex_polygon(fpt, p.polygon, -1.0):
				continue
			if terrain.distance_to_creek(fpt) < terrain.creek_half_width + 2.0 or road_graph.distance_to_road_corridor(fpt) < 0.8:
				continue
			if not _walkway_clear_fast(fpt, 1.2, walkway_aabbs) or not _outside_bps_fast(fpt, bp_grid, 1.4) or not _driveways_clear(fpt, 1.2, driveway_boxes):
				continue
			var hy_f := terrain.sample_height(fpt.x, fpt.y)
			if hy_f < terrain.water_level + 0.30:
				continue
			if fi % 2 == 0:
				props.append(_make_flora("bush", Vector3(fpt.x, hy_f, fpt.y), rng.randf_range(0.0, TAU), rng.randf_range(0.65, 1.05), FloraGenerator.BUSH_SPECIES[rng.randi() % FloraGenerator.BUSH_SPECIES.size()], rng.randi(), config))
			else:
				props.append(_make_flora("flower_patch", Vector3(fpt.x, hy_f, fpt.y), rng.randf_range(0.0, TAU), rng.randf_range(0.85, 1.25), FloraGenerator.FLOWER_SPECIES[rng.randi() % FloraGenerator.FLOWER_SPECIES.size()], rng.randi(), config))

	# 5. Foundation entrance shrubs & flowers flanking civic, church & residential entrances
	for bp in blueprints:
		if not (bp.archetype in ["church", "municipal_hall", "house_pitched", "townhouse", "apartment_midrise"] or bp.venue_type in ["library", "post_office", "cafe", "gallery"]):
			continue
		var porch_off := (float(bp.get("porch_depth")) if bool(bp.get("has_porch")) else 0.0)
		var side_off := bp.door_width * 0.5 + (1.35 if porch_off > 0.3 else 0.95)
		if side_off + 0.65 > bp.width * 0.5:
			continue
		var front_z := bp.depth * 0.5 + porch_off + 0.56
		var has_gar := bool(bp.get("has_garage"))
		var gar_x := float(bp.get("garage_local_x")) if has_gar else 0.0
		for s_dir: float in [-1.0, 1.0]:
			var lx_b := bp.door_local_x + s_dir * side_off
			if has_gar and absf(lx_b - gar_x) < 1.85:
				continue
			var l_xz := Vector2(lx_b, front_z)
			var w_xz := bp.local_to_world_2d(l_xz)
			if road_graph.distance_to_road_corridor(w_xz) < 0.35 or not _outside_bps_fast(w_xz, bp_grid, 0.25) or not _driveways_clear(w_xz, 0.7, driveway_boxes):
				continue
			var h_land := maxf(bp.sidewalk_y, terrain.sample_height(w_xz.x, w_xz.y))
			var sp_eb := "boxwood" if bp.archetype in ["municipal_hall", "church"] else "flowering_azalea"
			props.append(_make_flora("bush", Vector3(w_xz.x, h_land, w_xz.y), bp.yaw, 0.72, sp_eb, int(bp.floors), config))
			var lx_fl := bp.door_local_x + s_dir * (side_off + 0.78)
			if has_gar and absf(lx_fl - gar_x) < 1.85:
				continue
			var fl_l := bp.local_to_world_2d(Vector2(lx_fl, front_z - 0.02))
			if road_graph.distance_to_road_corridor(fl_l) >= 0.35 and _outside_bps_fast(fl_l, bp_grid, 0.25) and _driveways_clear(fl_l, 0.7, driveway_boxes):
				var h_fl := maxf(bp.sidewalk_y, terrain.sample_height(fl_l.x, fl_l.y))
				props.append(_make_flora("flower_patch", Vector3(fl_l.x, h_fl, fl_l.y), bp.yaw + s_dir * 0.6, 0.92, FloraGenerator.FLOWER_SPECIES[int(bp.width) % FloraGenerator.FLOWER_SPECIES.size()], int(bp.floors), config))

	# 6. Outdoor sidewalk cafe bistro seating + A-frame chalkboard signs in front of cafes & restaurants
	for bp in blueprints:
		if not (bp.venue_type in ["cafe", "restaurant"]):
			continue
		var a_placed := false
		for a_dx: float in [bp.door_width * 0.5 + 0.85, -(bp.door_width * 0.5 + 0.85), 1.85, -1.85]:
			if a_placed:
				break
			var ax := clampf(bp.door_local_x + a_dx, -bp.width * 0.45, bp.width * 0.45)
			if absf(ax - bp.door_local_x) < bp.door_width * 0.5 + 0.65:
				continue
			for a_dz: float in [0.76, 1.05]:
				var a_world := bp.local_to_world_2d(Vector2(ax, bp.depth * 0.5 + a_dz))
				if road_graph.distance_to_road_corridor(a_world) >= 0.35 and _outside_bps_fast(a_world, bp_grid, 0.25) and _is_clear_fast(a_world, 1.15, 1.35, placed_grid, door_grid):
					props.append(_make_prop("a_frame_sign", Vector3(a_world.x, bp.sidewalk_y, a_world.y), bp.yaw, config))
					_add_placed(a_world, placed_2d, placed_grid)
					a_placed = true
					break
		for side_sign: float in [-1.0, 1.0]:
			var seated := false
			for off_x: float in [2.65, 2.05, 3.30]:
				if seated:
					break
				var sx := clampf(bp.door_local_x + side_sign * off_x, -bp.width * 0.46, bp.width * 0.46)
				if absf(sx - bp.door_local_x) < bp.door_width * 0.5 + 1.05:
					continue
				for off_z: float in [1.35, 0.96]:
					var c_world := bp.local_to_world_2d(Vector2(sx, bp.depth * 0.5 + off_z))
					if road_graph.distance_to_road_corridor(c_world) >= 0.42 and _outside_bps_fast(c_world, bp_grid, 0.35) and _is_clear_fast(c_world, 1.75, 1.65, placed_grid, door_grid):
						var c_prop := _make_prop("cafe_seating", Vector3(c_world.x, bp.sidewalk_y, c_world.y), bp.yaw + side_sign * 0.2, config)
						c_prop["variant"] = rng.randi() % 3
						props.append(c_prop)
						_add_placed(c_world, placed_2d, placed_grid)
						seated = true
						break

	# 7. Guarantee at least one park fountain per seed even on small-park seeds
	if fountain_count == 0:
		for p in parcels:
			if not p.is_park or fountain_count > 0 or p.polygon.is_empty():
				continue
			var p_mid := Vector2.ZERO
			for pv in p.polygon:
				p_mid += pv
			p_mid /= float(p.polygon.size())
			var hy_fp := terrain.sample_height(p_mid.x, p_mid.y)
			if ParcelData.point_in_convex_polygon(p_mid, p.polygon, -3.5) and terrain.distance_to_creek(p_mid) >= terrain.creek_half_width + 4.5 and hy_fp >= terrain.water_level + 0.45 and _outside_bps_fast(p_mid, bp_grid, 4.0) and _walkway_clear_fast(p_mid, 3.6, walkway_aabbs) and _courts_clear(p_mid, 4.5, sport_court_boxes) and _is_clear_fast(p_mid, 4.5, 3.6, placed_grid, door_grid):
				props.append(_make_prop("park_fountain", Vector3(p_mid.x, hy_fp + 0.05, p_mid.y), 0.0, config))
				_add_placed(p_mid, placed_2d, placed_grid)
				fountain_count += 1

	# 8. Creek shoreline riprap boulder clusters & wetland reed/cattail tufts (zero colliders).
	_generate_creek_riprap_and_reeds(config, terrain, road_graph, road_grid, walkway_aabbs, props, rng)

	# 8b. Coastal beachfront boardwalk, walkable ocean pier, lifeguard towers, umbrellas, surfboard racks & palms.
	_generate_beachfront_features(config, terrain, road_graph, road_grid, blueprints, bp_grid, door_grid, placed_2d, placed_grid, props, rng)

	# 9. Clustered distance-faded Forward+ weathering Decals (capped <= 16 per chunk).
	_generate_clustered_decals(config, terrain, road_graph, park_walkways, dumpster_spots, props)

	return props


static func _make_flora(kind: String, pos: Vector3, yaw: float, scale_v: float, species: String, variant: int, config: CityConfig) -> Dictionary:
	var item := _make_prop(kind, pos, yaw, config)
	item["scale"] = scale_v
	item["species"] = species
	item["variant"] = posmod(variant, FloraGenerator.VARIANT_COUNT)
	return item


static func _make_prop(ptype: String, pos: Vector3, yaw: float, config: CityConfig) -> Dictionary:
	return {
		"type": ptype,
		"pos": pos,
		"yaw": yaw,
		"scale": 1.0,
		"variant": 0,
		"chunk": Vector2i(
			clampi(int(floor(pos.x / config.chunk_size)), 0, config.get_chunks_per_axis() - 1),
			clampi(int(floor(pos.z / config.chunk_size)), 0, config.get_chunks_per_axis() - 1)
		),
	}


static func _is_clear(pt: Vector2, min_dist: float, existing: Array[Vector2], door_zones: Array[Vector2]) -> bool:
	return _is_clear_apron(pt, min_dist, 3.6, existing, door_zones)


static func _is_clear_apron(pt: Vector2, min_dist: float, door_dist: float, existing: Array[Vector2], door_zones: Array[Vector2]) -> bool:
	for d in door_zones:
		if pt.distance_to(d) < door_dist:
			return false
	for e in existing:
		if pt.distance_to(e) < min_dist:
			return false
	return true


static func _walkway_clear(pt: Vector2, extra_pad: float, walkways: Array) -> bool:
	for w_var in walkways:
		var w: Dictionary = w_var
		if String(w.get("kind", "")) == "plaza":
			var c: Vector2 = w["center"]
			if pt.distance_to(c) < float(w.get("radius", 3.5)) + extra_pad:
				return false
		else:
			var pts: PackedVector2Array = w.get("points", PackedVector2Array())
			var hw := float(w.get("width", 2.2)) * 0.5 + extra_pad
			for i in range(pts.size() - 1):
				var a := pts[i]
				var b := pts[i + 1]
				var ab := b - a
				var l2 := ab.length_squared()
				var q := a if l2 < 0.001 else a.lerp(b, clampf((pt - a).dot(ab) / l2, 0.0, 1.0))
				if pt.distance_to(q) < hw:
					return false
	return true


static func _outside_all_buildings(pt: Vector2, blueprints: Array[BuildingBlueprint], margin: float) -> bool:
	for bp in blueprints:
		if ParcelData.obb_overlaps(pt, Vector2(margin, margin), 0.0, bp.center, Vector2(bp.width * 0.5, bp.depth * 0.5), bp.yaw, 0.0):
			return false
	return true


static func _courts_clear(pt: Vector2, margin: float, courts: Array[Dictionary]) -> bool:
	for c_var in courts:
		var c: Dictionary = c_var
		if ParcelData.obb_overlaps(pt, Vector2(margin, margin), 0.0, Vector2(c["center"]), Vector2(5.9, 8.9), float(c["yaw"]), 0.0):
			return false
	return true


static func _pick_street_species(road_class: String, rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	if road_class == "arterial":
		if roll < 0.42:
			return "austin_pecan"
		if roll < 0.80:
			return "cedar_elm"
		return "planter_shrub"
	if roll < 0.52:
		return "cedar_elm"
	if roll < 0.82:
		return "austin_pecan"
	return "planter_shrub"


static func _pick_park_species(rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	if roll < 0.36:
		return "oak"
	if roll < 0.64:
		return "austin_pecan"
	if roll < 0.84:
		return "weeping_willow"
	return "cedar_elm"


static func _pick_yard_species(rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	if roll < 0.36:
		return "oak"
	if roll < 0.74:
		return "cedar_elm"
	return "planter_shrub"


static func _build_bp_grid(blueprints: Array[BuildingBlueprint]) -> Dictionary:
	var grid: Dictionary = {}
	for bp in blueprints:
		var r := sqrt(bp.width * bp.width + bp.depth * bp.depth) * 0.5 + 12.0
		var x0 := int(floor((bp.center.x - r) / GRID_CELL_BP))
		var x1 := int(floor((bp.center.x + r) / GRID_CELL_BP))
		var z0 := int(floor((bp.center.y - r) / GRID_CELL_BP))
		var z1 := int(floor((bp.center.y + r) / GRID_CELL_BP))
		for cx in range(x0, x1 + 1):
			for cz in range(z0, z1 + 1):
				var k := Vector2i(cx, cz)
				var list: Array = grid.get(k, [])
				list.append(bp)
				grid[k] = list
	return grid


static func _outside_bps_fast(pt: Vector2, bp_grid: Dictionary, margin: float, ignore_id: String = "") -> bool:
	var k := Vector2i(int(floor(pt.x / GRID_CELL_BP)), int(floor(pt.y / GRID_CELL_BP)))
	if not bp_grid.has(k):
		return true
	var list: Array = bp_grid[k]
	var m2 := Vector2(margin, margin)
	for bp_var in list:
		var bp: BuildingBlueprint = bp_var
		if ignore_id != "" and bp.id == ignore_id:
			continue
		if ParcelData.obb_overlaps(pt, m2, 0.0, bp.center, Vector2(bp.width * 0.5, bp.depth * 0.5), bp.yaw, 0.0):
			return false
	return true


static func _build_pt_grid(pts: Array[Vector2], cell_sz: float) -> Dictionary:
	var grid: Dictionary = {}
	for p in pts:
		var k := Vector2i(int(floor(p.x / cell_sz)), int(floor(p.y / cell_sz)))
		var list: Array = grid.get(k, [])
		list.append(p)
		grid[k] = list
	return grid


static func _add_placed(pt: Vector2, placed_2d: Array[Vector2], placed_grid: Dictionary) -> void:
	placed_2d.append(pt)
	var k := Vector2i(int(floor(pt.x / GRID_CELL_PROP)), int(floor(pt.y / GRID_CELL_PROP)))
	var list: Array = placed_grid.get(k, [])
	list.append(pt)
	placed_grid[k] = list


static func _is_clear_fast(pt: Vector2, min_dist: float, door_dist: float, placed_grid: Dictionary, door_grid: Dictionary) -> bool:
	var cx := int(floor(pt.x / GRID_CELL_PROP))
	var cz := int(floor(pt.y / GRID_CELL_PROP))
	var dd2 := door_dist * door_dist
	if door_dist > 0.0:
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var dk := Vector2i(cx + dx, cz + dz)
				if not door_grid.has(dk):
					continue
				for d_var in door_grid[dk]:
					var d: Vector2 = d_var
					if pt.distance_squared_to(d) < dd2:
						return false
	var md2 := min_dist * min_dist
	if min_dist > 0.0:
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var pk := Vector2i(cx + dx, cz + dz)
				if not placed_grid.has(pk):
					continue
				for e_var in placed_grid[pk]:
					var e: Vector2 = e_var
					if pt.distance_squared_to(e) < md2:
						return false
	return true


static func _build_walkway_aabbs(walkways: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for w_var in walkways:
		var w: Dictionary = w_var
		var kind := String(w.get("kind", ""))
		if kind == "embankment_wall":
			continue
		if kind == "plaza":
			var c: Vector2 = w["center"]
			var r := float(w.get("radius", 3.5))
			out.append({
				"is_plaza": true,
				"center": c,
				"radius": r,
				"min": Vector2(c.x - r, c.y - r),
				"max": Vector2(c.x + r, c.y + r),
			})
		else:
			var pts: PackedVector2Array = w.get("points", PackedVector2Array())
			if pts.size() < 2:
				continue
			var hw := float(w.get("width", 2.2)) * 0.5
			var mn := Vector2(INF, INF)
			var mx := Vector2(-INF, -INF)
			for pt in pts:
				mn.x = minf(mn.x, pt.x)
				mn.y = minf(mn.y, pt.y)
				mx.x = maxf(mx.x, pt.x)
				mx.y = maxf(mx.y, pt.y)
			out.append({
				"is_plaza": false,
				"points": pts,
				"hw": hw,
				"min": Vector2(mn.x - hw, mn.y - hw),
				"max": Vector2(mx.x + hw, mx.y + hw),
			})
	return out


static func _walkway_clear_fast(pt: Vector2, extra_pad: float, aabbs: Array[Dictionary]) -> bool:
	for item in aabbs:
		var mn: Vector2 = item["min"]
		var mx: Vector2 = item["max"]
		if pt.x < mn.x - extra_pad or pt.x > mx.x + extra_pad or pt.y < mn.y - extra_pad or pt.y > mx.y + extra_pad:
			continue
		if bool(item["is_plaza"]):
			var c: Vector2 = item["center"]
			if pt.distance_to(c) < float(item["radius"]) + extra_pad:
				return false
		else:
			var pts: PackedVector2Array = item["points"]
			var hw := float(item["hw"]) + extra_pad
			var hw2 := hw * hw
			for i in range(pts.size() - 1):
				var q := Geometry2D.get_closest_point_to_segment(pt, pts[i], pts[i + 1])
				if pt.distance_squared_to(q) < hw2:
					return false
	return true


static func _is_angle_clear(ang: float, blocked: Array, margin_rad: float) -> bool:
	for ba_var in blocked:
		if absf(wrapf(ang - float(ba_var), -PI, PI)) < margin_rad:
			return false
	return true


static func _build_road_grid(road_graph: RoadGraph) -> Dictionary:
	var grid: Dictionary = {}
	for e in road_graph.edges:
		var a := road_graph.nodes[e.node_a].pos
		var b := road_graph.nodes[e.node_b].pos
		var pad := e.road_width * 0.5 + e.sidewalk_width + 24.0
		var x0 := int(floor((minf(a.x, b.x) - pad) / GRID_CELL_ROAD))
		var x1 := int(floor((maxf(a.x, b.x) + pad) / GRID_CELL_ROAD))
		var z0 := int(floor((minf(a.y, b.y) - pad) / GRID_CELL_ROAD))
		var z1 := int(floor((maxf(a.y, b.y) + pad) / GRID_CELL_ROAD))
		for cx in range(x0, x1 + 1):
			for cz in range(z0, z1 + 1):
				var k := Vector2i(cx, cz)
				var list: Array = grid.get(k, [])
				list.append(e)
				grid[k] = list
	return grid


static func _fast_road_dist(pt: Vector2, road_grid: Dictionary, road_graph: RoadGraph) -> float:
	var k := Vector2i(int(floor(pt.x / GRID_CELL_ROAD)), int(floor(pt.y / GRID_CELL_ROAD)))
	if not road_grid.has(k):
		return 24.0
	var min_clearance := 24.0
	var list: Array = road_grid[k]
	for e_var in list:
		var e: RoadGraph.RoadEdge = e_var
		var a := road_graph.nodes[e.node_a].pos
		var b := road_graph.nodes[e.node_b].pos
		var closest := Geometry2D.get_closest_point_to_segment(pt, a, b)
		var d := pt.distance_to(closest) - (e.road_width * 0.5 + e.sidewalk_width)
		if d < min_clearance:
			min_clearance = d
	return min_clearance


static func _compute_creek_x_range(terrain: TerrainData, margin: float) -> Vector2:
	if terrain == null or terrain.creek_polyline.is_empty():
		return Vector2(INF, -INF)
	var min_x := INF
	var max_x := -INF
	for p in terrain.creek_polyline:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
	return Vector2(min_x - terrain.creek_half_width - margin, max_x + terrain.creek_half_width + margin)


static func _fast_creek_dist(pt: Vector2, terrain: TerrainData, creek_x_range: Vector2) -> float:
	if terrain == null or terrain.creek_polyline.size() < 2:
		return INF
	if pt.x < creek_x_range.x or pt.x > creek_x_range.y:
		return terrain.creek_half_width + 40.0
	var poly := terrain.creek_polyline
	var n := poly.size()
	var approx_idx := clampi(int(round((pt.y + 8.0) / 8.0)), 0, n - 2)
	var lo := maxi(0, approx_idx - 8)
	var hi := mini(n - 2, approx_idx + 8)
	var min_d := INF
	for i in range(lo, hi + 1):
		var closest := Geometry2D.get_closest_point_to_segment(pt, poly[i], poly[i + 1])
		min_d = minf(min_d, pt.distance_to(closest))
	return min_d


static func _driveways_clear(pt: Vector2, margin: float, driveway_boxes: Array[Dictionary]) -> bool:
	var m2 := Vector2(margin, margin)
	for db in driveway_boxes:
		if ParcelData.obb_overlaps(pt, m2, 0.0, Vector2(db["center"]), Vector2(db["half_extents"]), float(db["yaw"]), 0.0):
			return false
	return true


static func _generate_residential_driveways(
	config: CityConfig,
	terrain: TerrainData,
	road_graph: RoadGraph,
	road_grid: Dictionary,
	creek_x_range: Vector2,
	parcel_map: Dictionary,
	blueprints: Array[BuildingBlueprint],
	bp_grid: Dictionary,
	walkway_aabbs: Array[Dictionary],
	door_grid: Dictionary,
	placed_grid: Dictionary,
	props: Array[Dictionary],
	rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	for bp in blueprints:
		if not (bp.archetype in ["house_pitched", "townhouse"]):
			continue
		var parcel: ParcelData.Parcel = parcel_map.get(bp.parcel_id, null)
		if parcel == null or parcel.polygon.size() < 3:
			continue
		var forward := Vector2(sin(bp.yaw), cos(bp.yaw))
		var z_front := bp.depth * 0.5 + 0.04
		var has_gar := bool(bp.get("has_garage"))
		var gar_x := float(bp.get("garage_local_x")) if has_gar else 0.0
		var porch_clear := (bp.door_width * 0.5 + 1.45) if bool(bp.get("has_porch")) else (bp.door_width * 0.5 + 0.90)
		var first_side := 1.0 if rng.randf() < 0.5 else -1.0

		var cand_specs: Array[Array] = []
		if has_gar:
			cand_specs.append([gar_x, 3.00])
		else:
			for s_sign: float in [first_side, -first_side]:
				cand_specs.append([s_sign * (bp.width * 0.5 + 1.55), 2.60])
				var apron_x := clampf(bp.width * 0.34, 2.85, bp.width * 0.5 - 1.15)
				cand_specs.append([s_sign * apron_x, 2.60])

		for spec in cand_specs:
			var lx := float(spec[0])
			var drive_w := float(spec[1])
			if absf(lx - bp.door_local_x) < porch_clear + drive_w * 0.45:
				continue
			# Measure available forward span inside parcel up to sidewalk curb
			var z_end := z_front
			var d_step := 1.0
			while d_step <= 11.5:
				var test_pt := bp.local_to_world_2d(Vector2(lx, z_front + d_step))
				if not ParcelData.point_in_convex_polygon(test_pt, parcel.polygon, 0.15):
					break
				if _fast_road_dist(test_pt, road_grid, road_graph) < 0.25:
					break
				z_end = z_front + d_step
				d_step += 0.5
			var drive_len := z_end - z_front
			if drive_len < 2.2:
				continue
			var z_mid := (z_front + z_end) * 0.5
			var p_house := bp.local_to_world_2d(Vector2(lx, z_front))
			var p_mid := bp.local_to_world_2d(Vector2(lx, z_mid))
			var p_street := bp.local_to_world_2d(Vector2(lx, z_end))
			var corners_ok := true
			for sx: float in [-drive_w * 0.5, drive_w * 0.5]:
				for sz: float in [z_front + 0.2, z_end]:
					var cpt := bp.local_to_world_2d(Vector2(lx + sx, sz))
					if not ParcelData.point_in_convex_polygon(cpt, parcel.polygon, 0.22):
						corners_ok = false
						break
					if _fast_creek_dist(cpt, terrain, creek_x_range) < terrain.creek_half_width + 2.5 or terrain.sample_height(cpt.x, cpt.y) < terrain.water_level + 0.35:
						corners_ok = false
						break
					if not _outside_bps_fast(cpt, bp_grid, 0.65, bp.id):
						corners_ok = false
						break
				if not corners_ok:
					break
			if not corners_ok:
				continue
			if not _is_clear_fast(p_mid, 2.0, 2.5, placed_grid, door_grid) or not _is_clear_fast(p_street, 1.8, 2.3, placed_grid, door_grid):
				continue
			if not _walkway_clear_fast(p_mid, 0.9, walkway_aabbs):
				continue
			var y_h := terrain.sample_height(p_house.x, p_house.y)
			var y_m := terrain.sample_height(p_mid.x, p_mid.y)
			var y_s := terrain.sample_height(p_street.x, p_street.y)
			var dprop := _make_prop("driveway_pad", Vector3(p_mid.x, y_m, p_mid.y), atan2(forward.x, forward.y), config)
			dprop["width"] = drive_w
			dprop["length"] = drive_len
			dprop["dy0"] = y_h - y_m
			dprop["dy1"] = 0.0
			dprop["dy2"] = y_s - y_m
			props.append(dprop)
			boxes.append({
				"center": p_mid + forward * 0.75,
				"half_extents": Vector2(drive_w * 0.5 + 0.45, drive_len * 0.5 + 1.6),
				"yaw": bp.yaw,
			})
			break
	return boxes


static func _generate_alley_and_service_yards(
	config: CityConfig,
	terrain: TerrainData,
	road_graph: RoadGraph,
	road_grid: Dictionary,
	creek_x_range: Vector2,
	parcel_map: Dictionary,
	blueprints: Array[BuildingBlueprint],
	bp_grid: Dictionary,
	walkway_aabbs: Array[Dictionary],
	door_grid: Dictionary,
	placed_2d: Array[Vector2],
	placed_grid: Dictionary,
	driveway_boxes: Array[Dictionary],
	placed_fence_mids: Dictionary,
	props: Array[Dictionary],
	rng: RandomNumberGenerator
) -> Array[Vector2]:
	var dumpster_spots: Array[Vector2] = []

	# A. Alley corridor shoulders (outside the 4.6m alley roadway so centerlines stay 100% clear)
	for e in road_graph.edges:
		if e.road_class != "alley" or e.samples.size() < 2:
			continue
		var pa := road_graph.nodes[e.node_a].pos
		var pb := road_graph.nodes[e.node_b].pos
		var edge_len := pa.distance_to(pb)
		var usable := edge_len - (e.trim_a + e.trim_b) - 5.0
		if usable < 12.0:
			continue
		var dir := (pb - pa).normalized()
		var right := Vector2(-dir.y, dir.x)
		var half_r := e.road_width * 0.5
		var steps := maxi(1, int(floor(usable / 15.0)))
		for si in range(steps):
			var dist_along := e.trim_a + 2.5 + (float(si) + 0.5) * (usable / float(steps))
			var t := clampf(dist_along / edge_len, 0.14, 0.86)
			if e.is_bridge and t >= e.bridge_start_t - 0.05 and t <= e.bridge_end_t + 0.05:
				continue
			var p3 := road_graph.sample_edge_point_3d(e, t)
			var s_sign := 1.0 if (si % 2 == 0) else -1.0
			var pt := Vector2(p3.x, p3.z) + right * (s_sign * (half_r + 0.88))
			if _fast_road_dist(pt, road_grid, road_graph) < 0.45:
				continue
			if not _outside_bps_fast(pt, bp_grid, 1.05) or not _is_clear_fast(pt, 2.8, 3.6, placed_grid, door_grid):
				continue
			var hy := terrain.sample_height(pt.x, pt.y)
			if hy < terrain.water_level + 0.40 or _fast_creek_dist(pt, terrain, creek_x_range) < terrain.creek_half_width + 2.5:
				continue
			var face_yaw := atan2(-right.x * s_sign, -right.y * s_sign)
			var kind_roll := si % 3
			if kind_roll == 0:
				props.append(_make_prop("commercial_dumpster", Vector3(pt.x, hy, pt.y), face_yaw, config))
				dumpster_spots.append(pt)
			elif kind_roll == 1:
				var pst := _make_prop("pallet_stack", Vector3(pt.x, hy, pt.y), face_yaw, config)
				pst["variant"] = rng.randi() % 2
				props.append(pst)
			else:
				props.append(_make_prop("safety_bollard", Vector3(pt.x, hy, pt.y), face_yaw, config))
			_add_placed(pt, placed_2d, placed_grid)

	# B. Commercial & Industrial rear service yards + chain-link warehouse fencing
	for bp in blueprints:
		if not (bp.archetype in ["warehouse", "retail_anchor", "brick_shop", "mixed_use_midrise", "modern_office"]):
			continue
		var parcel: ParcelData.Parcel = parcel_map.get(bp.parcel_id, null)
		if parcel == null or parcel.polygon.size() < 3:
			continue
		var rear_yaw := bp.yaw + PI
		var z_wall := -bp.depth * 0.5 - 0.45

		# Wall-side AC condenser unit at rear facade
		for ac_lx: float in [bp.width * 0.24, -bp.width * 0.24, 0.0]:
			var ac_pt := bp.local_to_world_2d(Vector2(ac_lx, z_wall))
			if not ParcelData.point_in_convex_polygon(ac_pt, parcel.polygon, -0.42):
				continue
			if _fast_road_dist(ac_pt, road_grid, road_graph) < 0.95 or _fast_creek_dist(ac_pt, terrain, creek_x_range) < terrain.creek_half_width + 2.5:
				continue
			if not _outside_bps_fast(ac_pt, bp_grid, 0.55, bp.id) or not _walkway_clear_fast(ac_pt, 0.8, walkway_aabbs):
				continue
			if _is_clear_fast(ac_pt, 1.5, 3.0, placed_grid, door_grid):
				var hy_ac := terrain.sample_height(ac_pt.x, ac_pt.y)
				if hy_ac >= terrain.water_level + 0.35:
					props.append(_make_prop("ac_condenser", Vector3(ac_pt.x, hy_ac, ac_pt.y), rear_yaw, config))
					_add_placed(ac_pt, placed_2d, placed_grid)
					break

		# Rear dumpster + pallet stack + safety dock bollards
		var z_yard := -bp.depth * 0.5 - 1.55
		var dump_pt := bp.local_to_world_2d(Vector2(-bp.width * 0.24, z_yard))
		if ParcelData.point_in_convex_polygon(dump_pt, parcel.polygon, -0.85) and _fast_road_dist(dump_pt, road_grid, road_graph) >= 1.1 and _fast_creek_dist(dump_pt, terrain, creek_x_range) >= terrain.creek_half_width + 3.0 and _outside_bps_fast(dump_pt, bp_grid, 1.05) and _walkway_clear_fast(dump_pt, 1.1, walkway_aabbs) and _driveways_clear(dump_pt, 1.8, driveway_boxes) and _is_clear_fast(dump_pt, 2.5, 3.6, placed_grid, door_grid):
			var hy_d := terrain.sample_height(dump_pt.x, dump_pt.y)
			if hy_d >= terrain.water_level + 0.38:
				props.append(_make_prop("commercial_dumpster", Vector3(dump_pt.x, hy_d, dump_pt.y), rear_yaw, config))
				_add_placed(dump_pt, placed_2d, placed_grid)
				dumpster_spots.append(dump_pt)
				if bp.archetype == "warehouse" or bp.archetype == "retail_anchor":
					for b_off: float in [-1.32, 1.32]:
						var bol_pt := bp.local_to_world_2d(Vector2(-bp.width * 0.24 + b_off, z_yard + 0.45))
						if ParcelData.point_in_convex_polygon(bol_pt, parcel.polygon, -0.35) and _outside_bps_fast(bol_pt, bp_grid, 0.35) and _is_clear_fast(bol_pt, 0.8, 3.2, placed_grid, door_grid):
							props.append(_make_prop("safety_bollard", Vector3(bol_pt.x, terrain.sample_height(bol_pt.x, bol_pt.y), bol_pt.y), rear_yaw, config))
							_add_placed(bol_pt, placed_2d, placed_grid)

		var pal_pt := bp.local_to_world_2d(Vector2(bp.width * 0.24, z_yard))
		if ParcelData.point_in_convex_polygon(pal_pt, parcel.polygon, -0.75) and _fast_road_dist(pal_pt, road_grid, road_graph) >= 1.1 and _fast_creek_dist(pal_pt, terrain, creek_x_range) >= terrain.creek_half_width + 3.0 and _outside_bps_fast(pal_pt, bp_grid, 0.95) and _walkway_clear_fast(pal_pt, 1.0, walkway_aabbs) and _driveways_clear(pal_pt, 1.8, driveway_boxes) and _is_clear_fast(pal_pt, 2.2, 3.6, placed_grid, door_grid):
			var hy_p := terrain.sample_height(pal_pt.x, pal_pt.y)
			if hy_p >= terrain.water_level + 0.38:
				var p_prop := _make_prop("pallet_stack", Vector3(pal_pt.x, hy_p, pal_pt.y), rear_yaw + rng.randf_range(-0.25, 0.25), config)
				p_prop["variant"] = rng.randi() % 2
				props.append(p_prop)
				_add_placed(pal_pt, placed_2d, placed_grid)

		# Industrial yard chain-link perimeter fencing on warehouse parcels (with wide rear gate opening)
		if bp.archetype == "warehouse":
			_emit_parcel_fence_loop(
				parcel, bp, "chainlink_fence", "chainlink", 13.5, true,
				config, terrain, road_graph, road_grid, creek_x_range, bp_grid, walkway_aabbs, door_grid, driveway_boxes, placed_fence_mids, props
			)

	return dumpster_spots


static func _generate_residential_lot_fences(
	config: CityConfig,
	terrain: TerrainData,
	road_graph: RoadGraph,
	road_grid: Dictionary,
	creek_x_range: Vector2,
	parcel_map: Dictionary,
	blueprints: Array[BuildingBlueprint],
	bp_grid: Dictionary,
	walkway_aabbs: Array[Dictionary],
	door_grid: Dictionary,
	driveway_boxes: Array[Dictionary],
	placed_fence_mids: Dictionary,
	props: Array[Dictionary]
) -> void:
	for bp in blueprints:
		if not (bp.archetype in ["house_pitched", "townhouse"]):
			continue
		var parcel: ParcelData.Parcel = parcel_map.get(bp.parcel_id, null)
		if parcel == null or parcel.polygon.size() < 3:
			continue
		var f_style := "iron" if bp.archetype == "townhouse" else ("cedar" if posmod(hash(bp.id), 5) < 3 else "picket")
		_emit_parcel_fence_loop(
			parcel, bp, "lot_fence", f_style, 13.5, false,
			config, terrain, road_graph, road_grid, creek_x_range, bp_grid, walkway_aabbs, door_grid, driveway_boxes, placed_fence_mids, props
		)


static func _emit_parcel_fence_loop(
	parcel: ParcelData.Parcel,
	bp: BuildingBlueprint,
	ptype: String,
	f_style: String,
	bay_len: float,
	leave_rear_gate: bool,
	config: CityConfig,
	terrain: TerrainData,
	road_graph: RoadGraph,
	road_grid: Dictionary,
	creek_x_range: Vector2,
	bp_grid: Dictionary,
	walkway_aabbs: Array[Dictionary],
	door_grid: Dictionary,
	driveway_boxes: Array[Dictionary],
	placed_fence_mids: Dictionary,
	props: Array[Dictionary]
) -> void:
	var poly := parcel.polygon
	var n := poly.size()
	var forward := Vector2(sin(bp.yaw), cos(bp.yaw))
	var z_front_cut := bp.depth * 0.5 - 0.45

	for i in range(n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var edge := b - a
		var elen := edge.length()
		if elen < 2.6:
			continue
		var edir := edge / elen
		var inward := Vector2(-edir.y, edir.x)
		var pa := a + inward * 0.24
		var pb := b + inward * 0.24
		var mid_edge := (pa + pb) * 0.5
		var rel_mid := mid_edge - bp.center
		var mid_z := rel_mid.dot(forward)
		# Skip front street-facing parcel edge so porches, stoops, & driveways stay open
		if mid_z > bp.depth * 0.35 and _fast_road_dist(mid_edge, road_grid, road_graph) < 1.8:
			continue

		var bays := clampi(int(round(elen / bay_len)), 1, 2)
		for bi in range(bays):
			var u0 := float(bi) / float(bays)
			var u1 := float(bi + 1) / float(bays)
			if leave_rear_gate and mid_z < -bp.depth * 0.35:
				if bays == 1:
					continue
				if bi == 0:
					u1 = minf(u1, 0.34)
				else:
					u0 = maxf(u0, 0.66)
			var s0 := pa.lerp(pb, u0)
			var s1 := pa.lerp(pb, u1)
			var z0 := (s0 - bp.center).dot(forward)
			var z1 := (s1 - bp.center).dot(forward)
			if z0 > z_front_cut and z1 > z_front_cut:
				continue
			if z0 > z_front_cut:
				var frac := (z_front_cut - z1) / (z0 - z1)
				s0 = s1.lerp(s0, clampf(frac, 0.0, 1.0))
			elif z1 > z_front_cut:
				var frac := (z_front_cut - z0) / (z1 - z0)
				s1 = s0.lerp(s1, clampf(frac, 0.0, 1.0))
			var seg_len := s0.distance_to(s1)
			if seg_len < 2.8:
				continue
			var seg_mid := (s0 + s1) * 0.5
			var f_key := Vector2i(int(round(seg_mid.x * 0.24)), int(round(seg_mid.y * 0.24)))
			if placed_fence_mids.has(f_key):
				continue
			if _fast_road_dist(seg_mid, road_grid, road_graph) < 0.95:
				continue
			if _fast_creek_dist(seg_mid, terrain, creek_x_range) < terrain.creek_half_width + 2.5:
				continue
			if not _outside_bps_fast(seg_mid, bp_grid, 0.88) or not _outside_bps_fast(s0, bp_grid, 0.65) or not _outside_bps_fast(s1, bp_grid, 0.65):
				continue
			if not _is_clear_fast(seg_mid, 0.0, 2.8, {}, door_grid) or not _driveways_clear(seg_mid, 1.45, driveway_boxes):
				continue
			if not _walkway_clear_fast(seg_mid, 1.0, walkway_aabbs):
				continue
			var y0 := terrain.sample_height(s0.x, s0.y)
			var y1 := terrain.sample_height(s1.x, s1.y)
			if minf(y0, y1) < terrain.water_level + 0.32:
				continue
			placed_fence_mids[f_key] = true
			var seg_dir := (s1 - s0) / seg_len
			var fprop := _make_prop(ptype, Vector3(seg_mid.x, y0, seg_mid.y), atan2(seg_dir.x, seg_dir.y), config)
			fprop["length"] = seg_len
			fprop["dy"] = y1 - y0
			fprop["style"] = f_style
			props.append(fprop)


static func _generate_creek_riprap_and_reeds(
	config: CityConfig,
	terrain: TerrainData,
	road_graph: RoadGraph,
	road_grid: Dictionary,
	walkway_aabbs: Array[Dictionary],
	props: Array[Dictionary],
	rng: RandomNumberGenerator
) -> void:
	if terrain == null or terrain.creek_polyline.size() < 2:
		return
	var sampled := ParkWalkwayGenerator._resample_polyline(terrain.creek_polyline, 6.0)
	for i in range(1, sampled.size() - 1):
		var c_pt := sampled[i]
		if c_pt.y < 18.0 or c_pt.y > config.world_size - 18.0:
			continue
		if terrain.beach_enabled and c_pt.y > terrain.get_beach_shore_z(c_pt.x) - 34.0:
			continue
		if _fast_road_dist(c_pt, road_grid, road_graph) < 4.5:
			continue
		var tang := (sampled[i + 1] - sampled[i - 1]).normalized()
		if tang.length_squared() < 0.1:
			continue
		var side_v := Vector2(-tang.y, tang.x)
		for s_sign: float in [-1.0, 1.0]:
			var bank_out := side_v * s_sign
			# Riprap shoreline boulder clusters along water-line banks
			if rng.randf() < 0.65:
				var rr_off := terrain.creek_half_width + rng.randf_range(-0.55, 2.15)
				var rr_pt := c_pt + bank_out * rr_off
				if _fast_road_dist(rr_pt, road_grid, road_graph) >= 3.0 and _walkway_clear_fast(rr_pt, 1.35, walkway_aabbs):
					var hy_r := terrain.sample_height(rr_pt.x, rr_pt.y)
					if hy_r >= terrain.water_level - 0.35 and hy_r <= terrain.water_level + 1.35:
						var rprop := _make_prop("riprap_cluster", Vector3(rr_pt.x, hy_r, rr_pt.y), rng.randf_range(0.0, TAU), config)
						rprop["scale"] = rng.randf_range(0.80, 1.28)
						rprop["variant"] = rng.randi() % FloraGenerator.VARIANT_COUNT
						rprop["seed"] = rng.randi()
						rprop["slope_dir"] = -bank_out
						props.append(rprop)

			# Wetland reed & cattail tufts in patchy shallow water margins
			var drift := sin(c_pt.y * 0.045 + s_sign * 1.4) * 0.5 + cos(c_pt.y * 0.11) * 0.5
			if drift > -0.25 and rng.randf() < 0.72:
				var rd_off := terrain.creek_half_width + rng.randf_range(-2.15, 0.85)
				var rd_pt := c_pt + bank_out * rd_off
				if _fast_road_dist(rd_pt, road_grid, road_graph) >= 3.2 and _walkway_clear_fast(rd_pt, 1.25, walkway_aabbs):
					var hy_rd := terrain.sample_height(rd_pt.x, rd_pt.y)
					if hy_rd >= terrain.water_level - 0.50 and hy_rd <= terrain.water_level + 0.45:
						props.append(_make_flora("bush", Vector3(rd_pt.x, hy_rd, rd_pt.y), rng.randf_range(0.0, TAU), rng.randf_range(0.85, 1.30), "cattail_reed", rng.randi(), config))


static func _generate_clustered_decals(
	config: CityConfig,
	terrain: TerrainData,
	road_graph: RoadGraph,
	park_walkways: Array,
	dumpster_spots: Array[Vector2],
	props: Array[Dictionary]
) -> void:
	var by_chunk: Dictionary = {}
	var seq := 0

	var push_cand := func(kind: String, pos: Vector3, yaw: float, sz: Vector3, alb_mix: float, prio: int) -> void:
		seq += 1
		var cc := Vector2i(
			clampi(int(floor(pos.x / config.chunk_size)), 0, config.get_chunks_per_axis() - 1),
			clampi(int(floor(pos.z / config.chunk_size)), 0, config.get_chunks_per_axis() - 1)
		)
		var list: Array = by_chunk.get(cc, [])
		list.append({
			"kind": kind,
			"pos": pos,
			"yaw": yaw,
			"size": sz,
			"albedo_mix": alb_mix,
			"prio": prio,
			"seq": seq,
		})
		by_chunk[cc] = list

	# 1. Storm drain rust/grime & intersection stop-bar oil drips + alley wear
	for e in road_graph.edges:
		var pa := road_graph.nodes[e.node_a].pos
		var pb := road_graph.nodes[e.node_b].pos
		var total_len := pa.distance_to(pb)
		if total_len < 12.0:
			continue
		var dir2 := (pb - pa) / total_len
		var side2 := Vector2(-dir2.y, dir2.x)
		var yaw := atan2(dir2.x, dir2.y)
		var half_r := e.road_width * 0.5
		var t_start := clampf(e.trim_a / total_len, 0.0, 0.42)
		var t_end := clampf(1.0 - e.trim_b / total_len, 0.58, 1.0)
		var trimmed_len := (t_end - t_start) * total_len
		if trimmed_len < 12.0:
			continue

		if e.road_class == "alley":
			var ad := 6.0
			while ad <= trimmed_len - 6.0:
				var at := lerpf(t_start, t_end, ad / trimmed_len)
				var ap := road_graph.sample_edge_point_3d(e, at)
				push_cand.call("alley_grime", Vector3(ap.x, ap.y + 0.04, ap.z), yaw, Vector3(2.8, 0.65, 3.2), 0.72, 2)
				ad += 18.0
			continue

		if (e.road_class == "arterial" or e.road_class == "collector") and not e.is_bridge and trimmed_len > 18.0:
			var drain_d := 8.0
			while drain_d <= trimmed_len - 8.0:
				var dt := lerpf(t_start, t_end, drain_d / trimmed_len)
				var dp := road_graph.sample_edge_point_3d(e, dt)
				for s_sign: float in [-1.0, 1.0]:
					var dpos := Vector2(dp.x, dp.z) + side2 * (s_sign * (half_r - 0.42))
					push_cand.call("drain_rust", Vector3(dpos.x, dp.y + 0.04, dpos.y), yaw, Vector3(1.85, 0.65, 2.65), 0.74, 3)
				drain_d += 34.0

			if e.sidewalk_width >= 2.2:
				var sw_t := lerpf(t_start, t_end, 0.48)
				var sp3 := road_graph.sample_edge_point_3d(e, sw_t)
				var sw_pt := Vector2(sp3.x, sp3.z) + side2 * (half_r + e.sidewalk_width * 0.52)
				push_cand.call("sidewalk_crack", Vector3(sw_pt.x, sp3.y + 0.16, sw_pt.y), yaw + 0.4, Vector3(1.65, 0.65, 1.65), 0.68, 1)

		if trimmed_len > 16.0 and half_r >= 3.0:
			for bar_pair in [[t_start + 5.2 / total_len, -1.0], [t_end - 5.2 / total_len, 1.0]]:
				var bt := clampf(float(bar_pair[0]), t_start, t_end)
				var lsign := float(bar_pair[1])
				var bp3 := road_graph.sample_edge_point_3d(e, bt)
				var lane_pt := Vector2(bp3.x, bp3.z) + side2 * (lsign * (half_r * 0.50))
				push_cand.call("oil_stain", Vector3(lane_pt.x, bp3.y + 0.04, lane_pt.y), yaw, Vector3(1.85, 0.65, 3.0), 0.68, 2)

	# 2. Alley & service yard dumpster grime pads
	for dpt in dumpster_spots:
		var hy := terrain.sample_height(dpt.x, dpt.y)
		push_cand.call("alley_grime", Vector3(dpt.x, hy + 0.04, dpt.y), 0.0, Vector3(2.9, 0.75, 2.9), 0.76, 3)

	# 3. Park plaza perimeter weathering / drain grates
	for w_var in park_walkways:
		var w: Dictionary = w_var
		if String(w.get("kind", "")) != "plaza":
			continue
		var pc: Vector2 = w["center"]
		var prad: float = float(w.get("radius", 4.0))
		var r_grate := maxf(2.2, prad * 0.62)
		for g_ang: float in [0.6, 3.7]:
			var gp := pc + Vector2(cos(g_ang), sin(g_ang)) * r_grate
			var hy_p := terrain.sample_height(gp.x, gp.y)
			push_cand.call("sidewalk_crack" if g_ang < 2.0 else "drain_rust", Vector3(gp.x, hy_p + 0.06, gp.y), g_ang, Vector3(1.7, 0.65, 1.7), 0.68, 1)

	# 4. Cap per-chunk decals to MAX_DECALS_PER_CHUNK (16) prioritizing drains, dumpsters & stop-bars
	for cc_key in by_chunk.keys():
		var cands: Array = by_chunk[cc_key]
		cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var pa := int(a["prio"])
			var pb := int(b["prio"])
			if pa != pb:
				return pa > pb
			return int(a["seq"]) < int(b["seq"])
		)
		var cap := mini(MAX_DECALS_PER_CHUNK, cands.size())
		for di in range(cap):
			var c: Dictionary = cands[di]
			var dprop := _make_prop("weather_decal", c["pos"], float(c["yaw"]), config)
			dprop["decal_kind"] = String(c["kind"])
			dprop["size"] = c["size"]
			dprop["albedo_mix"] = float(c["albedo_mix"])
			props.append(dprop)


static func _generate_beachfront_features(
	config: CityConfig,
	terrain: TerrainData,
	road_graph: RoadGraph,
	road_grid: Dictionary,
	blueprints: Array[BuildingBlueprint],
	bp_grid: Dictionary,
	door_grid: Dictionary,
	placed_2d: Array[Vector2],
	placed_grid: Dictionary,
	props: Array[Dictionary],
	rng: RandomNumberGenerator
) -> void:
	if terrain == null or not terrain.beach_enabled:
		return
	var ws := config.world_size
	var x_min := 118.0
	var x_max := ws - 118.0
	var creek_excl := terrain.creek_half_width + 26.0
	var bw_points: Array[Vector2] = []
	var pier_xs: Array[float] = []

	# Helper closure for boardwalk Z curve smoothly nestled between beach house stairs & wide dry beach
	var get_bw_z := func(wx: float) -> float:
		var sz := terrain.get_beach_shore_z(wx)
		return maxf(terrain.coast_road_z + 49.5, sz - 50.0)

	# 1. Continuous walkable cedar beach boardwalk segments along the upper sandy beach
	var seg_step := 12.0
	var bx := x_min
	var bw_seq := 0
	while bx + seg_step <= x_max:
		var x0 := bx
		var x1 := bx + seg_step
		var xm := (x0 + x1) * 0.5
		var z0: float = get_bw_z.call(x0)
		var z1: float = get_bw_z.call(x1)
		var zm := (z0 + z1) * 0.5
		var p0 := Vector2(x0, z0)
		var p1 := Vector2(x1, z1)
		var pm := Vector2(xm, zm)
		bx += seg_step

		if terrain.distance_to_creek(pm) < creek_excl or terrain.distance_to_creek(p0) < creek_excl or terrain.distance_to_creek(p1) < creek_excl:
			continue
		if _fast_road_dist(pm, road_grid, road_graph) < 5.0:
			continue
		if not _outside_bps_fast(pm, bp_grid, 5.2) or not _outside_bps_fast(p0, bp_grid, 4.4) or not _outside_bps_fast(p1, bp_grid, 4.4):
			continue
		var y0 := terrain.sample_height(x0, z0)
		var y1 := terrain.sample_height(x1, z1)
		var ym := terrain.sample_height(xm, zm)
		if minf(y0, minf(y1, ym)) < terrain.water_level + 0.75:
			continue
		var seg_v := p1 - p0
		var seg_len := seg_v.length()
		var yaw := atan2(seg_v.x, seg_v.y)
		var deck_y0 := maxf(y0 + 0.24, terrain.water_level + 1.15)
		var deck_y1 := maxf(y1 + 0.24, terrain.water_level + 1.15)
		var deck_ym := (deck_y0 + deck_y1) * 0.5
		var bw_prop := _make_prop("beach_boardwalk_seg", Vector3(xm, deck_ym, zm), yaw, config)
		bw_prop["length"] = seg_len + 0.14
		bw_prop["width"] = 3.8
		bw_prop["dy"] = deck_y1 - deck_y0
		bw_prop["has_lamp"] = (bw_seq % 3 == 0)
		props.append(bw_prop)
		bw_points.append(pm)
		bw_seq += 1

	# 2. Signature walkable Ocean Fishing & Observation Pier(s) jutting south out over breaking surf
	var pier_targets := [ws * 0.36, ws * 0.68, ws * 0.24, ws * 0.78]
	for target_x: float in pier_targets:
		if pier_xs.size() >= 2:
			break
		var best_px := -1.0
		for scan_off: float in [0.0, -24.0, 24.0, -48.0, 48.0, -72.0, 72.0]:
			var cx := clampf(target_x + scan_off, x_min + 60.0, x_max - 60.0)
			var dup := false
			for ex in pier_xs:
				if absf(cx - ex) < 340.0:
					dup = true
					break
			if dup:
				continue
			var bw_z: float = get_bw_z.call(cx)
			var shore_z := terrain.get_beach_shore_z(cx)
			var start_pt := Vector2(cx, bw_z + 1.6)
			var shore_pt := Vector2(cx, shore_z)
			if terrain.distance_to_creek(start_pt) < terrain.creek_half_width + 78.0:
				continue
			if terrain.distance_to_creek(shore_pt) < terrain.creek_half_width + 88.0:
				continue
			if not _outside_bps_fast(start_pt, bp_grid, 8.5):
				continue
			if terrain.sample_height(cx, bw_z) < terrain.water_level + 0.9:
				continue
			best_px = cx
			break
		if best_px > 0.0:
			var bw_z: float = get_bw_z.call(best_px)
			var shore_z := terrain.get_beach_shore_z(best_px)
			var start_z := bw_z + 1.6
			var end_z := minf(ws - 24.0, maxf(shore_z + 36.0, start_z + 78.0))
			var pier_len := clampf(end_z - start_z, 62.0, 96.0)
			var mid_z := start_z + pier_len * 0.5
			var ground_start := terrain.sample_height(best_px, start_z)
			var deck_y := clampf(maxf(ground_start + 0.26, terrain.water_level + 2.45), terrain.water_level + 2.35, terrain.water_level + 3.65)
			var pier_prop := _make_prop("beach_pier", Vector3(best_px, deck_y, mid_z), 0.0, config)
			pier_prop["length"] = pier_len
			pier_prop["width"] = 5.4
			pier_prop["start_ground_y"] = ground_start
			pier_prop["water_level"] = terrain.water_level
			props.append(pier_prop)
			pier_xs.append(best_px)

			# Pair of surfboard racks welcoming visitors beside the pier entrance!
			for s_side: float in [-1.0, 1.0]:
				var rx := best_px + s_side * 5.2
				var rz := start_z + 2.2
				var ry := terrain.sample_height(rx, rz)
				if ry >= terrain.water_level + 0.7:
					var sr := _make_prop("surfboard_rack", Vector3(rx, ry, rz), s_side * -0.25, config)
					sr["variant"] = int(pier_xs.size() + (0 if s_side < 0.0 else 1)) % 4
					props.append(sr)
					_add_placed(Vector2(rx, rz), placed_2d, placed_grid)

	# 3. Elevated coastal Lifeguard Towers spaced along the open sandy mid-beach
	var lg_x := x_min + 62.0
	var lg_seq := 0
	while lg_x <= x_max - 62.0:
		var lx := lg_x + rng.randf_range(-16.0, 16.0)
		lg_x += 185.0
		var near_pier := false
		for px in pier_xs:
			if absf(lx - px) < 26.0:
				near_pier = true
				break
		if near_pier:
			continue
		var shore_z := terrain.get_beach_shore_z(lx)
		var bw_z_lg: float = get_bw_z.call(lx)
		var lz := clampf(shore_z - rng.randf_range(26.0, 38.0), bw_z_lg + 5.5, shore_z - 16.0)
		var lpt := Vector2(lx, lz)
		if terrain.distance_to_creek(lpt) < creek_excl + 12.0:
			continue
		if not _outside_bps_fast(lpt, bp_grid, 5.5):
			continue
		var ly := terrain.sample_height(lx, lz)
		if ly < terrain.water_level + 0.40:
			continue
		var lg_prop := _make_prop("lifeguard_tower", Vector3(lx, ly, lz), rng.randf_range(-0.18, 0.18), config)
		lg_prop["variant"] = lg_seq % 3
		props.append(lg_prop)
		_add_placed(lpt, placed_2d, placed_grid)
		lg_seq += 1
	# Guarantee >= 2 lifeguard towers on every coastal seed
	if lg_seq < 2:
		var scan_x := x_min + 80.0
		while scan_x <= x_max - 80.0 and lg_seq < 2:
			var shore_z := terrain.get_beach_shore_z(scan_x)
			var bw_z_lg: float = get_bw_z.call(scan_x)
			var lz := clampf(bw_z_lg + 8.5, bw_z_lg + 5.0, shore_z - 16.0)
			var lpt := Vector2(scan_x, lz)
			var ly := terrain.sample_height(scan_x, lz)
			if terrain.distance_to_creek(lpt) >= creek_excl + 10.0 and _outside_bps_fast(lpt, bp_grid, 5.0) and ly >= terrain.water_level + 0.35 and _is_clear_fast(lpt, 18.0, 4.0, placed_grid, door_grid):
				var lg_prop := _make_prop("lifeguard_tower", Vector3(scan_x, ly, lz), 0.0, config)
				lg_prop["variant"] = lg_seq % 3
				props.append(lg_prop)
				_add_placed(lpt, placed_2d, placed_grid)
				lg_seq += 1
			scan_x += 75.0

	# 4. Colorful Beach Umbrellas + Wooden Lounge Chairs scattered organically across dry golden sand
	var ux := x_min + 26.0
	var u_seq := 0
	while ux <= x_max - 26.0:
		ux += rng.randf_range(20.0, 34.0)
		var near_pier := false
		for px in pier_xs:
			if absf(ux - px) < 11.5:
				near_pier = true
				break
		if near_pier:
			continue
		var shore_z := terrain.get_beach_shore_z(ux)
		var bw_z: float = get_bw_z.call(ux)
		var z_lo := maxf(bw_z + 5.8, shore_z - 42.0)
		var z_hi := shore_z - 12.5
		if z_hi <= z_lo + 2.0:
			continue
		# Cluster 1-2 umbrella sets per beach bay
		var cluster_n := 2 if rng.randf() < 0.58 else 1
		for ci in range(cluster_n):
			var px_u := ux + (float(ci) - 0.5) * rng.randf_range(5.4, 8.2)
			var pz_u := rng.randf_range(z_lo, z_hi)
			var upt := Vector2(px_u, pz_u)
			if terrain.distance_to_creek(upt) < creek_excl + 6.0:
				continue
			if not _outside_bps_fast(upt, bp_grid, 4.5):
				continue
			if not _is_clear_fast(upt, 4.8, 3.0, placed_grid, door_grid):
				continue
			var uy := terrain.sample_height(px_u, pz_u)
			if uy < terrain.water_level + 0.55:
				continue
			var uprop := _make_prop("beach_umbrella_set", Vector3(px_u, uy, pz_u), rng.randf_range(-0.35, 0.35), config)
			uprop["variant"] = u_seq % 5
			props.append(uprop)
			_add_placed(upt, placed_2d, placed_grid)
			u_seq += 1

	# 5. Additional Surfboard Racks near beachfront houses & boardwalk access spots
	for b_idx in range(0, bw_points.size(), 9):
		var bpt := bw_points[b_idx]
		var near_p := false
		for px in pier_xs:
			if absf(bpt.x - px) < 16.0:
				near_p = true
				break
		if near_p:
			continue
		var spt := bpt + Vector2(0.0, 3.4)
		var sy := terrain.sample_height(spt.x, spt.y)
		if sy >= terrain.water_level + 0.7 and _is_clear_fast(spt, 3.8, 2.5, placed_grid, door_grid) and _outside_bps_fast(spt, bp_grid, 3.5):
			var srp := _make_prop("surfboard_rack", Vector3(spt.x, sy, spt.y), rng.randf_range(-0.3, 0.3), config)
			srp["variant"] = b_idx % 4
			props.append(srp)
			_add_placed(spt, placed_2d, placed_grid)

	# 6. Coastal Palm Trees framing the boardwalk, sandy dune line & beach house yards
	var palm_x := x_min + 12.0
	var palm_seq := 0
	while palm_x <= x_max - 12.0:
		palm_x += rng.randf_range(16.0, 26.0)
		var bw_z: float = get_bw_z.call(palm_x)
		var cand_zs: Array[float] = [bw_z - 3.6, bw_z + 4.4]
		for pz_c in cand_zs:
			if rng.randf() > 0.68:
				continue
			var ppt := Vector2(palm_x + rng.randf_range(-3.0, 3.0), pz_c + rng.randf_range(-1.0, 1.0))
			if terrain.distance_to_creek(ppt) < creek_excl + 2.0:
				continue
			if _fast_road_dist(ppt, road_grid, road_graph) < 4.5:
				continue
			if not _outside_bps_fast(ppt, bp_grid, 5.2):
				continue
			if not _is_clear_fast(ppt, 5.4, 3.8, placed_grid, door_grid):
				continue
			var skip_p := false
			for px in pier_xs:
				if absf(ppt.x - px) < 6.8 and ppt.y >= bw_z:
					skip_p = true
					break
			if skip_p:
				continue
			var py := terrain.sample_height(ppt.x, ppt.y)
			if py < terrain.water_level + 0.75:
				continue
			var pprop := _make_prop("beach_palm", Vector3(ppt.x, py, ppt.y), rng.randf_range(0.0, TAU), config)
			pprop["scale"] = rng.randf_range(0.86, 1.24)
			pprop["variant"] = palm_seq % 4
			props.append(pprop)
			_add_placed(ppt, placed_2d, placed_grid)
			palm_seq += 1

	# Also tuck coastal palms cleanly beside beach_house front/side edges along OCEANFRONT BLVD
	for bp in blueprints:
		if bp.archetype != "beach_house":
			continue
		for sx: float in [-1.0, 1.0]:
			if rng.randf() < 0.35:
				continue
			var wpt := bp.local_to_world_2d(Vector2(sx * (bp.width * 0.5 + 2.2), rng.randf_range(-1.5, 2.2)))
			if _fast_road_dist(wpt, road_grid, road_graph) < 3.0:
				continue
			if not _outside_bps_fast(wpt, bp_grid, 1.6) or not _is_clear_fast(wpt, 3.8, 3.2, placed_grid, door_grid):
				continue
			var py := terrain.sample_height(wpt.x, wpt.y)
			if py < terrain.water_level + 0.75:
				continue
			var pprop := _make_prop("beach_palm", Vector3(wpt.x, py, wpt.y), rng.randf_range(0.0, TAU), config)
			pprop["scale"] = rng.randf_range(0.84, 1.12)
			pprop["variant"] = palm_seq % 4
			props.append(pprop)
			_add_placed(wpt, placed_2d, placed_grid)
			palm_seq += 1

	# 7. Underwater Coral Reef Sanctuary & Swaying Kelp Forests along the ocean seabed & around piers
	var reef_seq := 0
	var kelp_seq := 0
	# A. Dense signature reef & kelp garden flanking each walkable ocean pier (for rich diving right under the pier!)
	for px_pier in pier_xs:
		var shore_p := terrain.get_beach_shore_z(px_pier)
		var rz_p := shore_p + 10.0
		while rz_p <= minf(ws - 14.0, shore_p + 96.0):
			for side_s: float in [-1.0, 1.0]:
				var rx_c := px_pier + side_s * rng.randf_range(3.6, 18.0)
				var rz_c := rz_p + rng.randf_range(-3.0, 3.0)
				var by_c := terrain.sample_height(rx_c, rz_c)
				var depth_c := terrain.water_level - by_c
				if depth_c >= 0.85:
					var rprop := _make_prop("coral_reef_cluster", Vector3(rx_c, by_c, rz_c), rng.randf_range(0.0, TAU), config)
					rprop["scale"] = clampf(rng.randf_range(0.88, 1.38), 0.75, depth_c * 0.62)
					rprop["variant"] = reef_seq % 5
					props.append(rprop)
					reef_seq += 1
				var kx_c := px_pier + side_s * rng.randf_range(2.8, 22.0)
				var kz_c := rz_p + rng.randf_range(-4.0, 4.0)
				var by_k := terrain.sample_height(kx_c, kz_c)
				var depth_k := terrain.water_level - by_k
				if depth_k >= 1.10:
					var kprop := _make_prop("underwater_kelp", Vector3(kx_c, by_k, kz_c), rng.randf_range(0.0, TAU), config)
					kprop["scale"] = clampf((depth_k - 0.35) / 2.6, 0.45, 1.35)
					kprop["variant"] = kelp_seq % 4
					props.append(kprop)
					kelp_seq += 1
			rz_p += 11.5

	# B. Coastal reef belt & kelp groves spanning the full southern ocean floor
	var rx_scan := x_min
	while rx_scan <= x_max:
		rx_scan += rng.randf_range(22.0, 36.0)
		var shore_s := terrain.get_beach_shore_z(rx_scan)
		for band_off: float in [16.0, 34.0, 56.0, 82.0]:
			var wz_s := shore_s + band_off + rng.randf_range(-5.0, 5.0)
			if wz_s > ws - 12.0:
				continue
			var wx_s := rx_scan + rng.randf_range(-8.0, 8.0)
			var by_s := terrain.sample_height(wx_s, wz_s)
			var depth_s := terrain.water_level - by_s
			if depth_s < 0.85:
				continue
			if (reef_seq + kelp_seq) % 2 == 0:
				var rprop := _make_prop("coral_reef_cluster", Vector3(wx_s, by_s, wz_s), rng.randf_range(0.0, TAU), config)
				rprop["scale"] = clampf(rng.randf_range(0.85, 1.35), 0.72, depth_s * 0.60)
				rprop["variant"] = reef_seq % 5
				props.append(rprop)
				reef_seq += 1
			else:
				var kprop := _make_prop("underwater_kelp", Vector3(wx_s, by_s, wz_s), rng.randf_range(0.0, TAU), config)
				kprop["scale"] = clampf((depth_s - 0.35) / 2.6, 0.42, 1.35)
				kprop["variant"] = kelp_seq % 4
				props.append(kprop)
				kelp_seq += 1
