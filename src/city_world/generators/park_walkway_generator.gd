class_name ParkWalkwayGenerator
extends RefCounted

## Generates terrain-conforming park walkways, paved gazebo plazas, and continuous
## creekside greenway trails linking civic parks back into the urban sidewalk grid.


static func generate(
	config: CityConfig,
	terrain: TerrainData,
	road_graph: RoadGraph,
	parcels: Array,
	blueprints: Array[BuildingBlueprint],
	rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var walkways: Array[Dictionary] = []
	if not config.enable_props:
		return walkways

	var greenway_samples: Array[Vector2] = []

	# 1. Continuous creekside greenway trails along both banks outside bridges and buildings.
	if terrain != null and terrain.creek_polyline.size() >= 2:
		var sampled_line := _resample_polyline(terrain.creek_polyline, 11.0)
		var trail_off := terrain.creek_half_width + 5.6
		for side_sign: float in [-1.0, 1.0]:
			var current_run: Array[Vector2] = []
			for i in range(sampled_line.size()):
				var p_cur := sampled_line[i]
				var p_prev := sampled_line[maxi(0, i - 1)]
				var p_next := sampled_line[mini(sampled_line.size() - 1, i + 1)]
				var tang := (p_next - p_prev)
				if tang.length_squared() < 0.01:
					continue
				tang = tang.normalized()
				var side_v := Vector2(-tang.y, tang.x) * side_sign
				var pt := p_cur + side_v * trail_off

				var road_hit := _nearest_road_hit(pt, road_graph)
				var near_blocking_road := false
				var sidewalk_snap := Vector2.INF
				if not road_hit.is_empty():
					var e: RoadGraph.RoadEdge = road_hit["edge"]
					var edge_pt: Vector2 = road_hit["edge_pt"]
					var d_road := float(road_hit["dist"])
					var clear_r := e.road_width * 0.5 + e.sidewalk_width + 1.8
					if d_road < clear_r:
						near_blocking_road = true
						if not e.is_bridge or (float(road_hit["t"]) < e.bridge_start_t or float(road_hit["t"]) > e.bridge_end_t):
							var out_dir := (pt - edge_pt).normalized()
							if out_dir.length_squared() > 0.1:
								sidewalk_snap = edge_pt + out_dir * (e.road_width * 0.5 + e.sidewalk_width * 0.55)

				var pt_valid := (not near_blocking_road) and _is_trail_point_valid(pt, config, terrain, blueprints, 3.0)
				if pt_valid:
					if current_run.is_empty() and sidewalk_snap != Vector2.INF and _is_trail_point_valid(sidewalk_snap, config, terrain, blueprints, 2.0):
						current_run.append(sidewalk_snap)
					current_run.append(pt)
				else:
					if not current_run.is_empty() and sidewalk_snap != Vector2.INF and _is_trail_point_valid(sidewalk_snap, config, terrain, blueprints, 2.0):
						if current_run[current_run.size() - 1].distance_to(sidewalk_snap) < 18.0:
							current_run.append(sidewalk_snap)
					_flush_greenway_run(current_run, walkways, greenway_samples, config, walkways.size())
					current_run = []
			_flush_greenway_run(current_run, walkways, greenway_samples, config, walkways.size())

	# 2. Park gazebo/fountain plazas, road-sidewalk entrance walkways, scenic loops, and greenway spurs.
	var plaza_seq := 0
	for p_var in parcels:
		var p: ParcelData.Parcel = p_var
		if not p.is_park or p.polygon.size() < 3:
			continue
		var bounds := _poly_bounds(p.polygon)
		var box_area := bounds.size.x * bounds.size.y
		if box_area < 280.0:
			continue

		var plaza_center := _pick_park_plaza_center(p, bounds, terrain, blueprints, rng)
		if plaza_center == Vector2.INF:
			continue

		var is_large_park := box_area > 900.0
		var has_gazebo := is_large_park and (plaza_seq % 2 == 0)
		var has_fountain := is_large_park and (plaza_seq % 2 == 1)
		plaza_seq += 1
		var edge_d := ParcelData.min_edge_distance_in_convex_polygon(plaza_center, p.polygon) - 0.85
		var creek_d := (terrain.distance_to_creek(plaza_center) - (terrain.creek_half_width + 3.0)) if terrain != null else 99.0
		var road_d := road_graph.distance_to_road_corridor(plaza_center) - 1.5
		var safe_r := minf(edge_d, minf(creek_d, road_d))
		var plaza_rad := 4.8 if has_fountain else (4.3 if has_gazebo else 2.9)
		if is_large_park and safe_r >= 7.0:
			plaza_rad = clampf(safe_r * 0.80, 7.0, 10.5)
		elif is_large_park and safe_r > 4.6:
			plaza_rad = clampf(safe_r, 4.6, 6.8)
		var is_major_plaza := is_large_park and plaza_rad >= 6.8
		var blocked_angles: Array[float] = []
		var plaza_dict := {
			"id": "plaza_%s" % p.id,
			"kind": "plaza",
			"style": "fountain_plaza" if has_fountain else "gazebo_plaza",
			"parcel_id": p.id,
			"center": plaza_center,
			"radius": plaza_rad,
			"has_gazebo": has_gazebo,
			"has_fountain": has_fountain,
			"is_major_plaza": is_major_plaza,
			"art_variant": plaza_seq % 3,
			"seed": rng.randi(),
			"blocked_angles": blocked_angles,
			"points": PackedVector2Array(),
			"width": 0.0,
			"chunk": _chunk_of(plaza_center, config),
		}
		walkways.append(plaza_dict)

		# Primary sidewalk connector from parcel road frontage into the plaza
		var entry_a := _nearest_dry_sidewalk_pt(plaza_center, p, road_graph, terrain, config, 180.0)
		var dir_a := Vector2.ZERO
		if entry_a != Vector2.INF and entry_a.distance_to(plaza_center) >= 4.0:
			var ent_pts := _build_organic_link(entry_a, plaza_center, 1.4 * (1.0 if rng.randf() < 0.5 else -1.0), terrain, blueprints, config)
			if ent_pts.size() >= 2:
				dir_a = (entry_a - plaza_center).normalized()
				blocked_angles.append(_plaza_exit_angle(plaza_center, ent_pts))
				walkways.append({
					"id": "ent_%s_a" % p.id,
					"kind": "path",
					"style": "entrance",
					"parcel_id": p.id,
					"center": plaza_center,
					"radius": 0.0,
					"has_gazebo": false,
					"points": ent_pts,
					"width": 2.4,
					"chunk": _chunk_of(plaza_center, config),
				})

		# Secondary sidewalk entrance on opposing perimeter if a nearby road exists
		var entry_b := _find_opposite_sidewalk_pt(plaza_center, dir_a, road_graph, terrain, 160.0)
		if entry_b != Vector2.INF and entry_b.distance_to(plaza_center) >= 5.5:
			var ent_b := _build_organic_link(entry_b, plaza_center, 1.2 * (1.0 if rng.randf() < 0.5 else -1.0), terrain, blueprints, config)
			if ent_b.size() >= 2:
				blocked_angles.append(_plaza_exit_angle(plaza_center, ent_b))
				walkways.append({
					"id": "ent_%s_b" % p.id,
					"kind": "path",
					"style": "entrance",
					"parcel_id": p.id,
					"center": plaza_center,
					"radius": 0.0,
					"has_gazebo": false,
					"points": ent_b,
					"width": 2.2,
					"chunk": _chunk_of(plaza_center, config),
				})

		# Link spacious park plaza to the nearest creekside greenway trail if close
		var best_gw := Vector2.INF
		var best_gw_d := 110.0
		for g_pt in greenway_samples:
			var dg := g_pt.distance_to(plaza_center)
			if dg < best_gw_d and dg > plaza_rad + 2.0:
				best_gw_d = dg
				best_gw = g_pt
		if best_gw != Vector2.INF:
			var spur_pts := _build_organic_link(plaza_center, best_gw, 1.0, terrain, blueprints, config)
			if spur_pts.size() >= 2:
				blocked_angles.append(_plaza_exit_angle(plaza_center, spur_pts))
				walkways.append({
					"id": "spur_%s" % p.id,
					"kind": "path",
					"style": "greenway_spur",
					"parcel_id": p.id,
					"center": (plaza_center + best_gw) * 0.5,
					"radius": 0.0,
					"has_gazebo": false,
					"points": spur_pts,
					"width": 2.2,
					"chunk": _chunk_of(plaza_center, config),
				})

		# Scenic interior park loop path connecting park groves back to gazebo plaza
		if is_large_park:
			var loop_pts := _build_park_loop(p, bounds, plaza_center, terrain, blueprints, config, rng)
			if loop_pts.size() >= 4:
				blocked_angles.append(_plaza_exit_angle(plaza_center, loop_pts, 1))
				blocked_angles.append(_plaza_exit_angle(plaza_center, loop_pts, loop_pts.size() - 2))
				walkways.append({
					"id": "loop_%s" % p.id,
					"kind": "path",
					"style": "loop",
					"parcel_id": p.id,
					"center": plaza_center,
					"radius": 0.0,
					"has_gazebo": false,
					"points": loop_pts,
					"width": 2.0,
					"chunk": _chunk_of(plaza_center, config),
				})

	# 3. Arched pedestrian footbridges spanning the creek between East/West greenways.
	var fb_centers: Array[Vector2] = []
	if terrain != null and terrain.creek_polyline.size() >= 6:
		var fb_line := _resample_polyline(terrain.creek_polyline, 18.0)
		var span_half := terrain.creek_half_width + 5.6
		for i in range(4, fb_line.size() - 4):
			var p_cur := fb_line[i]
			if p_cur.y < 115.0 or p_cur.y > config.world_size - 115.0:
				continue
			var too_close_fb := false
			for fbc in fb_centers:
				if fbc.distance_to(p_cur) < 195.0:
					too_close_fb = true
					break
			if too_close_fb:
				continue
			var tang := (fb_line[i + 1] - fb_line[i - 1]).normalized()
			var side_v := Vector2(-tang.y, tang.x)
			var west_pt := p_cur - side_v * span_half
			var east_pt := p_cur + side_v * span_half
			if not _is_trail_point_valid(west_pt, config, terrain, blueprints, 3.8):
				continue
			if not _is_trail_point_valid(east_pt, config, terrain, blueprints, 3.8):
				continue
			if road_graph.distance_to_road_corridor(p_cur) < 34.0:
				continue
			if road_graph.distance_to_road_corridor(west_pt) < 12.0 or road_graph.distance_to_road_corridor(east_pt) < 12.0:
				continue
			fb_centers.append(p_cur)
			walkways.append({
				"id": "footbridge_%d" % fb_centers.size(),
				"kind": "footbridge",
				"style": "creek_footbridge",
				"parcel_id": "",
				"center": p_cur,
				"radius": 0.0,
				"has_gazebo": false,
				"has_fountain": false,
				"points": PackedVector2Array([west_pt, east_pt]),
				"width": 2.6,
				"chunk": _chunk_of(p_cur, config),
			})
			if fb_centers.size() >= 6:
				break

	# 4. Cantilevered cedar boardwalk overlook decks branching from greenways to creek edge.
	var overlook_centers: Array[Vector2] = []
	if terrain != null and terrain.creek_polyline.size() >= 4:
		overlook_centers = _generate_boardwalk_overlooks(walkways, fb_centers, config, terrain, road_graph, blueprints, rng)

	# 5. Stepped limestone embankment retaining walls along bridge abutments, footbridges & creek plazas.
	if terrain != null and terrain.creek_polyline.size() >= 4:
		_generate_embankment_walls(walkways, greenway_samples, overlook_centers, config, terrain, road_graph, blueprints)

	return walkways


static func _flush_greenway_run(
	run: Array[Vector2],
	walkways: Array[Dictionary],
	greenway_samples: Array[Vector2],
	config: CityConfig,
	seq_id: int
) -> void:
	if run.size() < 2:
		return
	var total_len := 0.0
	for i in range(run.size() - 1):
		total_len += run[i].distance_to(run[i + 1])
	if total_len < 16.0:
		return
	var packed := _smooth_curve_points(run, 1.5, false)
	for pt in packed:
		greenway_samples.append(pt)
	var mid := run[run.size() / 2]
	walkways.append({
		"id": "greenway_%d" % seq_id,
		"kind": "path",
		"style": "greenway",
		"parcel_id": "",
		"center": mid,
		"radius": 0.0,
		"has_gazebo": false,
		"points": packed,
		"width": 2.4,
		"chunk": _chunk_of(mid, config),
	})


static func _build_organic_link(
	a: Vector2,
	b: Vector2,
	curve_amp: float,
	terrain: TerrainData,
	blueprints: Array[BuildingBlueprint],
	config: CityConfig
) -> PackedVector2Array:
	var ab := b - a
	var dist := ab.length()
	if dist < 2.0:
		return PackedVector2Array()
	var dir := ab / dist
	var perp := Vector2(-dir.y, dir.x)
	var mid_bend := (a + b) * 0.5 + perp * minf(absf(curve_amp), dist * 0.14) * signf(curve_amp)
	var use_bend := dist >= 10.0 and _segment_is_valid(a, mid_bend, terrain, blueprints, config, 2.0) and _segment_is_valid(mid_bend, b, terrain, blueprints, config, 2.0)
	if use_bend:
		var curved := _smooth_curve_points([a, mid_bend, b], 1.5, false)
		var curve_valid := true
		for cpt in curved:
			if not _is_trail_point_valid(cpt, config, terrain, blueprints, 1.6):
				curve_valid = false
				break
		if curve_valid:
			return curved
		return _subdivide_pts([a, mid_bend, b], 2.0)
	if _segment_is_valid(a, b, terrain, blueprints, config, 2.0):
		return _subdivide_pts([a, b], 2.0)
	return PackedVector2Array()


static func _build_park_loop(
	p: ParcelData.Parcel,
	bounds: Rect2,
	plaza_center: Vector2,
	terrain: TerrainData,
	blueprints: Array[BuildingBlueprint],
	config: CityConfig,
	rng: RandomNumberGenerator
) -> PackedVector2Array:
	var max_span := minf(48.0, maxf(bounds.size.x, bounds.size.y) * 0.48)
	var min_x := maxf(bounds.position.x + 2.6, plaza_center.x - max_span)
	var max_x := minf(bounds.end.x - 2.6, plaza_center.x + max_span)
	var min_y := maxf(bounds.position.y + 2.6, plaza_center.y - max_span)
	var max_y := minf(bounds.end.y - 2.6, plaza_center.y + max_span)
	var wps: Array[Vector2] = []
	for _try in range(36):
		if wps.size() >= 4:
			break
		var cand := Vector2(
			rng.randf_range(min_x, maxf(min_x + 0.5, max_x)),
			rng.randf_range(min_y, maxf(min_y + 0.5, max_y))
		)
		if not ParcelData.point_in_convex_polygon(cand, p.polygon, -2.5):
			continue
		if not _is_trail_point_valid(cand, config, terrain, blueprints, 3.2):
			continue
		if cand.distance_to(plaza_center) < 7.0:
			continue
		var too_close := false
		for prev in wps:
			if cand.distance_to(prev) < 9.0:
				too_close = true
				break
		if not too_close:
			wps.append(cand)

	if wps.size() < 2:
		return PackedVector2Array()

	wps.sort_custom(func(u: Vector2, v: Vector2) -> bool:
		var au := atan2(u.y - plaza_center.y, u.x - plaza_center.x)
		var av := atan2(v.y - plaza_center.y, v.x - plaza_center.x)
		return au < av
	)

	var valid_chain: Array[Vector2] = [plaza_center]
	for pt in wps:
		if _segment_is_valid(valid_chain[valid_chain.size() - 1], pt, terrain, blueprints, config, 2.2):
			valid_chain.append(pt)
	if valid_chain.size() < 3:
		return PackedVector2Array()
	if _segment_is_valid(valid_chain[valid_chain.size() - 1], plaza_center, terrain, blueprints, config, 2.2):
		var curved_loop := _smooth_curve_points(valid_chain, 1.5, true)
		var loop_ok := curved_loop.size() >= 6
		if loop_ok:
			for lpt in curved_loop:
				if not _is_trail_point_valid(lpt, config, terrain, blueprints, 1.6):
					loop_ok = false
					break
		if loop_ok:
			return curved_loop
		valid_chain.append(plaza_center)
	else:
		return PackedVector2Array()
	return _subdivide_pts(valid_chain, 2.5)


static func _smooth_curve_points(pts: Array[Vector2], step_m: float = 1.5, closed: bool = false) -> PackedVector2Array:
	## Applies symmetric cubic Bezier handle smoothing via Curve3D (matching baked trail splines).
	if pts.size() < 3:
		return _subdivide_pts(pts, step_m)
	var curve := Curve3D.new()
	curve.bake_interval = 0.45
	var n := pts.size()
	var end_count := (n + 1) if closed else n
	for i in range(end_count):
		var cur := pts[i % n]
		var prev := pts[posmod(i - 1, n)] if closed else pts[maxi(0, i - 1)]
		var nxt := pts[(i + 1) % n] if closed else pts[mini(n - 1, i + 1)]
		var tan2 := (nxt - prev).normalized() * minf(cur.distance_to(prev), cur.distance_to(nxt)) * 0.25
		if not closed:
			if i == 0:
				tan2 = (nxt - cur) * 0.22
			elif i == n - 1:
				tan2 = (cur - prev) * 0.22
		var t3 := Vector3(tan2.x, 0.0, tan2.y)
		curve.add_point(Vector3(cur.x, 0.0, cur.y), -t3, t3)
	var total_len := curve.get_baked_length()
	if total_len < 0.5:
		return _subdivide_pts(pts, step_m)
	var samples := maxi(3, int(ceil(total_len / maxf(0.4, step_m))))
	var out := PackedVector2Array()
	for si in range(samples + 1):
		var d := total_len * (float(si) / float(samples))
		var p3 := curve.sample_baked(d)
		out.append(Vector2(p3.x, p3.z))
	return out


static func _subdivide_pts(pts: Array[Vector2], max_step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var d := a.distance_to(b)
		var n := maxi(1, int(ceil(d / max_step)))
		for k in range(n):
			out.append(a.lerp(b, float(k) / float(n)))
	if not pts.is_empty():
		out.append(pts[pts.size() - 1])
	return out


static func _pick_park_plaza_center(
	p: ParcelData.Parcel,
	bounds: Rect2,
	terrain: TerrainData,
	blueprints: Array[BuildingBlueprint],
	rng: RandomNumberGenerator
) -> Vector2:
	var cent := ParcelData.polygon_centroid(p.polygon)
	var front_mid := (p.frontage_p0 + p.frontage_p1) * 0.5
	var inward := -p.frontage_normal.normalized() if p.frontage_normal.length_squared() > 0.01 else Vector2.ZERO
	var candidates: Array[Vector2] = []
	# Keep very large outer/perimeter parks anchored within walking reach of their street frontage.
	if bounds.size.x * bounds.size.y > 16000.0 or cent.distance_to(front_mid) > 55.0:
		if inward != Vector2.ZERO:
			candidates.append(front_mid + inward * 18.0)
			candidates.append(front_mid + inward * 26.0)
			candidates.append(cent.lerp(front_mid + inward * 14.0, 0.65))
		candidates.append(front_mid.lerp(cent, 0.28))
	candidates.append(cent)
	for _i in range(28):
		candidates.append(Vector2(
			rng.randf_range(bounds.position.x + 3.2, bounds.end.x - 3.2),
			rng.randf_range(bounds.position.y + 3.2, bounds.end.y - 3.2)
		))
	var best_pt := Vector2.INF
	var best_score := -INF
	var is_large := bounds.size.x * bounds.size.y > 900.0
	for pt in candidates:
		if not ParcelData.point_in_convex_polygon(pt, p.polygon, -3.5):
			if not ParcelData.point_in_convex_polygon(pt, p.polygon, -1.8):
				continue
		var creek_dist := INF
		if terrain != null:
			creek_dist = terrain.distance_to_creek(pt)
			if creek_dist < terrain.creek_half_width + 4.8:
				continue
			if terrain.sample_height(pt.x, pt.y) < terrain.water_level + 0.55:
				continue
		var b_clear := true
		for bp in blueprints:
			if ParcelData.obb_overlaps(pt, Vector2(4.2, 4.2), 0.0, bp.center, Vector2(bp.width * 0.5, bp.depth * 0.5), bp.yaw, 0.0):
				b_clear = false
				break
		if not b_clear:
			continue
		if not is_large:
			return pt
		var edge_clear := ParcelData.min_edge_distance_in_convex_polygon(pt, p.polygon)
		var creek_room := (creek_dist - (terrain.creek_half_width + 3.0)) if terrain != null else 20.0
		var room := minf(edge_clear, creek_room)
		var slope_pen := 0.0
		if terrain != null:
			var mm := terrain.sample_min_max_in_obb(pt, Vector2(6.5, 6.5), 0.0)
			slope_pen = maxf(0.0, (mm.y - mm.x) - 1.2) * 3.0
		var score := minf(room, 12.5) - slope_pen
		if room >= 9.0 and slope_pen <= 1.2:
			return pt
		if score > best_score:
			best_score = score
			best_pt = pt
	return best_pt


static func _nearest_dry_sidewalk_pt(
	target: Vector2,
	p: ParcelData.Parcel,
	road_graph: RoadGraph,
	terrain: TerrainData,
	config: CityConfig,
	max_dist: float
) -> Vector2:
	if p.frontage_road_id >= 0 and p.frontage_road_id < road_graph.edges.size():
		var fe: RoadGraph.RoadEdge = road_graph.edges[p.frontage_road_id]
		if not fe.is_bridge:
			for ft in [0.5, 0.3, 0.7]:
				var f_pt := p.frontage_p0.lerp(p.frontage_p1, ft) + p.frontage_normal * 1.15
				if f_pt.x < 17.0 or f_pt.x > config.world_size - 17.0 or f_pt.y < 17.0 or f_pt.y > config.world_size - 17.0:
					continue
				if road_graph.distance_to_road_corridor(f_pt) > 12.0:
					continue
				if terrain == null or (terrain.distance_to_creek(f_pt) >= terrain.creek_half_width + 1.8 and terrain.sample_height(f_pt.x, f_pt.y) >= terrain.water_level + 0.35):
					return f_pt
	return _find_opposite_sidewalk_pt(target, Vector2.ZERO, road_graph, terrain, max_dist)


static func _find_opposite_sidewalk_pt(
	target: Vector2,
	avoid_dir: Vector2,
	road_graph: RoadGraph,
	terrain: TerrainData,
	max_dist: float
) -> Vector2:
	var best_pt := Vector2.INF
	var best_d := max_dist
	for e in road_graph.edges:
		if e.is_bridge or e.road_class == "alley":
			continue
		for step_i in range(1, 8):
			var t := float(step_i) / 8.0
			var p3 := road_graph.sample_edge_point_3d(e, t)
			var ep := Vector2(p3.x, p3.z)
			var d := ep.distance_to(target)
			if d > best_d or d < 5.0:
				continue
			var toward := (target - ep).normalized()
			if avoid_dir != Vector2.ZERO and (-toward).dot(avoid_dir) > 0.25:
				continue
			var cand := ep + toward * (e.road_width * 0.5 + e.sidewalk_width * 0.5)
			if terrain != null:
				if terrain.distance_to_creek(cand) < terrain.creek_half_width + 1.8:
					continue
				if terrain.sample_height(cand.x, cand.y) < terrain.water_level + 0.35:
					continue
			best_d = d
			best_pt = cand
	return best_pt


static func _nearest_road_hit(pt: Vector2, road_graph: RoadGraph) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 28.0
	for e in road_graph.edges:
		var n0 := road_graph.nodes[e.node_a].pos
		var n1 := road_graph.nodes[e.node_b].pos
		var seg := n1 - n0
		var l2 := seg.length_squared()
		if l2 < 0.01:
			continue
		var t := clampf((pt - n0).dot(seg) / l2, 0.0, 1.0)
		var q := n0.lerp(n1, t)
		var d := pt.distance_to(q)
		if d < best_d:
			best_d = d
			best = {"edge": e, "edge_pt": q, "t": t, "dist": d}
	return best


static func _segment_is_valid(
	a: Vector2,
	b: Vector2,
	terrain: TerrainData,
	blueprints: Array[BuildingBlueprint],
	config: CityConfig,
	bld_margin: float
) -> bool:
	var steps := maxi(2, int(ceil(a.distance_to(b) / 2.5)))
	for i in range(1, steps):
		var pt := a.lerp(b, float(i) / float(steps))
		if not _is_trail_point_valid(pt, config, terrain, blueprints, bld_margin):
			return false
	return true


static func _is_trail_point_valid(
	pt: Vector2,
	config: CityConfig,
	terrain: TerrainData,
	blueprints: Array[BuildingBlueprint],
	bld_margin: float
) -> bool:
	if pt.x < 16.0 or pt.x > config.world_size - 16.0 or pt.y < 16.0 or pt.y > config.world_size - 16.0:
		return false
	if terrain != null:
		if terrain.distance_to_creek(pt) < terrain.creek_half_width + 2.4:
			return false
		if terrain.beach_enabled and pt.y > terrain.get_beach_shore_z(pt.x) - 36.0:
			return false
		if terrain.sample_height(pt.x, pt.y) < terrain.water_level + 0.30:
			return false
	for bp in blueprints:
		if ParcelData.obb_overlaps(pt, Vector2(bld_margin, bld_margin), 0.0, bp.center, Vector2(bp.width * 0.5, bp.depth * 0.5), bp.yaw, 0.0):
			return false
	return true


static func _resample_polyline(poly: PackedVector2Array, step_m: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if poly.is_empty():
		return out
	out.append(poly[0])
	for i in range(poly.size() - 1):
		var a := poly[i]
		var b := poly[i + 1]
		var seg_d := a.distance_to(b)
		var sub := maxi(1, int(ceil(seg_d / step_m)))
		for k in range(1, sub + 1):
			out.append(a.lerp(b, float(k) / float(sub)))
	return out


static func _poly_bounds(poly: PackedVector2Array) -> Rect2:
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for v in poly:
		min_v.x = minf(min_v.x, v.x)
		min_v.y = minf(min_v.y, v.y)
		max_v.x = maxf(max_v.x, v.x)
		max_v.y = maxf(max_v.y, v.y)
	return Rect2(min_v, max_v - min_v)


static func _chunk_of(pt: Vector2, config: CityConfig) -> Vector2i:
	return Vector2i(
		clampi(int(floor(pt.x / config.chunk_size)), 0, config.get_chunks_per_axis() - 1),
		clampi(int(floor(pt.y / config.chunk_size)), 0, config.get_chunks_per_axis() - 1)
	)


static func _plaza_exit_angle(plaza_center: Vector2, pts: PackedVector2Array, custom_idx: int = -1) -> float:
	if pts.is_empty():
		return 0.0
	var ref_pt := pts[0]
	if custom_idx >= 0 and custom_idx < pts.size():
		ref_pt = pts[custom_idx]
	else:
		var d0 := pts[0].distance_to(plaza_center)
		var d1 := pts[pts.size() - 1].distance_to(plaza_center)
		if d0 < d1 and pts.size() >= 2:
			ref_pt = pts[mini(2, pts.size() - 1)]
		elif pts.size() >= 2:
			ref_pt = pts[maxi(0, pts.size() - 3)]
	var dir := ref_pt - plaza_center
	return atan2(dir.y, dir.x)


static func _nearest_point_on_polyline(pt: Vector2, poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return pt
	var best := poly[0]
	var best_d2 := INF
	for i in range(poly.size() - 1):
		var q := Geometry2D.get_closest_point_to_segment(pt, poly[i], poly[i + 1])
		var d2 := pt.distance_squared_to(q)
		if d2 < best_d2:
			best_d2 = d2
			best = q
	return best


static func _generate_boardwalk_overlooks(
	walkways: Array[Dictionary],
	fb_centers: Array[Vector2],
	config: CityConfig,
	terrain: TerrainData,
	road_graph: RoadGraph,
	blueprints: Array[BuildingBlueprint],
	rng: RandomNumberGenerator
) -> Array[Vector2]:
	var placed: Array[Vector2] = []
	var overlook_seq := 0
	var ws := config.world_size

	for w in walkways:
		if placed.size() >= 10:
			break
		if String(w.get("style", "")) != "greenway":
			continue
		var pts: PackedVector2Array = w.get("points", PackedVector2Array())
		if pts.size() < 4:
			continue
		var accum := 12.0
		for i in range(1, pts.size() - 1):
			if placed.size() >= 10:
				break
			accum += pts[i - 1].distance_to(pts[i])
			if accum < 18.0:
				continue
			var gw_pt := pts[i]
			if gw_pt.x < 42.0 or gw_pt.x > ws - 42.0 or gw_pt.y < 42.0 or gw_pt.y > ws - 42.0:
				continue
			if road_graph.distance_to_road_corridor(gw_pt) < 18.0:
				continue

			var too_close := false
			for fbc in fb_centers:
				if fbc.distance_to(gw_pt) < 22.0:
					too_close = true
					break
			if too_close:
				continue
			for ov in placed:
				if ov.distance_to(gw_pt) < 56.0:
					too_close = true
					break
			if too_close:
				continue

			var c_pt := _nearest_point_on_polyline(gw_pt, terrain.creek_polyline)
			var dist_c := gw_pt.distance_to(c_pt)
			if dist_c < terrain.creek_half_width + 3.0 or dist_c > terrain.creek_half_width + 11.0:
				continue
			var to_creek := (c_pt - gw_pt) / dist_c
			var gw_h := terrain.sample_height(gw_pt.x, gw_pt.y)
			if gw_h < terrain.water_level + 0.50 or gw_h > terrain.water_level + 4.1:
				continue

			var deck_tip := c_pt - to_creek * (terrain.creek_half_width - 2.2)
			var deck_center := gw_pt.lerp(deck_tip, 0.58)
			if road_graph.distance_to_road_corridor(deck_tip) < 14.0:
				continue
			var clear_bld := true
			for check_pt in [gw_pt, deck_center, deck_tip]:
				for bp in blueprints:
					if ParcelData.obb_overlaps(check_pt, Vector2(3.2, 3.2), 0.0, bp.center, Vector2(bp.width * 0.5, bp.depth * 0.5), bp.yaw, 0.0):
						clear_bld = false
						break
				if not clear_bld:
					break
			if not clear_bld:
				continue

			accum = 0.0
			if rng.randf() > 0.72 and placed.size() >= 3:
				continue
			overlook_seq += 1
			var deck_y := maxf(gw_h + 0.06, terrain.water_level + 1.05)
			placed.append(gw_pt)
			walkways.append({
				"id": "overlook_%d" % overlook_seq,
				"kind": "overlook",
				"type": "overlook",
				"style": "cedar_overlook",
				"parcel_id": "",
				"center": deck_center,
				"anchor": gw_pt,
				"tip": deck_tip,
				"dir": to_creek,
				"width": 5.2,
				"spur_width": 2.6,
				"deck_y": deck_y,
				"anchor_y": gw_h,
				"radius": 0.0,
				"has_gazebo": false,
				"has_fountain": false,
				"points": PackedVector2Array([gw_pt, deck_tip]),
				"chunk": _chunk_of(deck_center, config),
			})
	return placed


static func _generate_embankment_walls(
	walkways: Array[Dictionary],
	greenway_samples: Array[Vector2],
	overlook_centers: Array[Vector2],
	config: CityConfig,
	terrain: TerrainData,
	road_graph: RoadGraph,
	blueprints: Array[BuildingBlueprint]
) -> void:
	var ws := config.world_size
	var wall_seq := 0

	# A. Stepped limestone wing retaining walls flanking creek road bridge abutments
	for e in road_graph.edges:
		if not e.is_bridge:
			continue
		var pa := road_graph.nodes[e.node_a].pos
		var pb := road_graph.nodes[e.node_b].pos
		var dir2 := (pb - pa).normalized()
		var side2 := Vector2(-dir2.y, dir2.x)
		var half_r := e.road_width * 0.5
		var sw_w := e.sidewalk_width
		for end_info in [[e.bridge_start_t, -1.0], [e.bridge_end_t, 1.0]]:
			var bt := float(end_info[0])
			var out_sign := float(end_info[1])
			var p3 := road_graph.sample_edge_point_3d(e, bt)
			var p2 := Vector2(p3.x, p3.z)
			for s_sign: float in [-1.0, 1.0]:
				var w0 := p2 + side2 * (s_sign * (half_r + sw_w + 0.55)) - dir2 * (out_sign * 0.5)
				var w1 := w0 + side2 * (s_sign * 6.0) + dir2 * (out_sign * 2.2)
				if w0.x < 14.0 or w0.x > ws - 14.0 or w1.x < 14.0 or w1.x > ws - 14.0:
					continue
				if w0.y < 14.0 or w0.y > ws - 14.0 or w1.y < 14.0 or w1.y > ws - 14.0:
					continue
				var w_mid := (w0 + w1) * 0.5
				if not _is_wall_clear(w0, w_mid, w1, greenway_samples, overlook_centers, blueprints):
					continue
				wall_seq += 1
				var top0 := maxf(p3.y - 0.22, terrain.sample_height(w0.x, w0.y) + 0.55)
				var top1 := terrain.sample_height(w1.x, w1.y) + 0.42
				walkways.append({
					"id": "embank_bridge_%d" % wall_seq,
					"kind": "embankment_wall",
					"style": "bridge_abutment_wall",
					"parcel_id": "",
					"center": w_mid,
					"radius": 0.0,
					"has_gazebo": false,
					"has_fountain": false,
					"points": PackedVector2Array([w0, w1]),
					"width": 0.85,
					"top_y0": top0,
					"top_y1": top1,
					"chunk": _chunk_of(w_mid, config),
				})

	# B. Bank retaining walls along creekside footbridge landings and near-creek plazas
	var existing_count := walkways.size()
	for wi in range(existing_count):
		var w := walkways[wi]
		var wkind := String(w.get("kind", ""))
		if wkind == "footbridge":
			var fpts: PackedVector2Array = w.get("points", PackedVector2Array())
			if fpts.size() < 2:
				continue
			var fdir := (fpts[1] - fpts[0]).normalized()
			var btang := Vector2(-fdir.y, fdir.x)
			for end_idx: int in [0, 1]:
				var end_pt := fpts[end_idx]
				var toward_creek := fdir if end_idx == 0 else -fdir
				var anchor := end_pt + toward_creek * 2.2
				for s_sign: float in [-1.0, 1.0]:
					var p0 := anchor + btang * (s_sign * 2.1)
					var p1 := anchor + btang * (s_sign * 7.2) - toward_creek * 0.5
					var mid := (p0 + p1) * 0.5
					if road_graph.distance_to_road_corridor(mid) < 8.0:
						continue
					if not _is_wall_clear(p0, mid, p1, greenway_samples, overlook_centers, blueprints):
						continue
					wall_seq += 1
					walkways.append({
						"id": "embank_fb_%d" % wall_seq,
						"kind": "embankment_wall",
						"style": "bank_retaining_wall",
						"parcel_id": "",
						"center": mid,
						"radius": 0.0,
						"has_gazebo": false,
						"has_fountain": false,
						"points": PackedVector2Array([p0, p1]),
						"width": 0.78,
						"top_y0": terrain.sample_height(p0.x, p0.y) + 0.55,
						"top_y1": terrain.sample_height(p1.x, p1.y) + 0.45,
						"chunk": _chunk_of(mid, config),
					})
		elif wkind == "plaza":
			var pc: Vector2 = w["center"]
			var prad: float = float(w.get("radius", 4.0))
			var cp := _nearest_point_on_polyline(pc, terrain.creek_polyline)
			var dist_cp := pc.distance_to(cp)
			if dist_cp < terrain.creek_half_width + prad + 10.0:
				var away := (pc - cp).normalized()
				var btang := Vector2(-away.y, away.x)
				var wall_c := cp + away * (terrain.creek_half_width + 2.2)
				var p0 := wall_c - btang * 4.5
				var p1 := wall_c + btang * 4.5
				if road_graph.distance_to_road_corridor(wall_c) >= 6.0 and _is_wall_clear(p0, wall_c, p1, greenway_samples, overlook_centers, blueprints):
					wall_seq += 1
					walkways.append({
						"id": "embank_plaza_%d" % wall_seq,
						"kind": "embankment_wall",
						"style": "plaza_retaining_wall",
						"parcel_id": "",
						"center": wall_c,
						"radius": 0.0,
						"has_gazebo": false,
						"has_fountain": false,
						"points": PackedVector2Array([p0, p1]),
						"width": 0.80,
						"top_y0": terrain.sample_height(p0.x, p0.y) + 0.60,
						"top_y1": terrain.sample_height(p1.x, p1.y) + 0.60,
						"chunk": _chunk_of(wall_c, config),
					})


static func _is_wall_clear(
	p0: Vector2,
	mid: Vector2,
	p1: Vector2,
	greenway_samples: Array[Vector2],
	overlook_centers: Array[Vector2],
	blueprints: Array[BuildingBlueprint]
) -> bool:
	for check_pt in [p0, mid, p1]:
		for gw in greenway_samples:
			if check_pt.distance_to(gw) < 1.65:
				return false
		for ov in overlook_centers:
			if check_pt.distance_to(ov) < 4.5:
				return false
		for bp in blueprints:
			if ParcelData.obb_overlaps(check_pt, Vector2(1.2, 1.2), 0.0, bp.center, Vector2(bp.width * 0.5, bp.depth * 0.5), bp.yaw, 0.0):
				return false
	return true
