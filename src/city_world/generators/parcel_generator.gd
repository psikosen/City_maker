class_name ParcelGenerator
extends RefCounted

## Subdivides city blocks into strictly non-overlapping, street-fronting parcels
## via exact convex half-plane partitioning.

static func generate(config: CityConfig, terrain: TerrainData, road_graph: RoadGraph, blocks: Array, rng: RandomNumberGenerator) -> Array:
	var parcels: Array = []
	var parcel_seq := 0

	for blk in blocks:
		var poly: PackedVector2Array = blk.buildable_polygon
		if poly.size() < 3 or ParcelData.signed_area(poly) < 400.0:
			continue

		if blk.district_zone == "civic_park":
			var park_p := _make_parcel(
				"parcel_%04d" % parcel_seq,
				blk,
				poly,
				0,
				road_graph,
				terrain,
				config,
				true
			)
			parcel_seq += 1
			parcels.append(park_p)
			continue

		var target_lot_w := 19.0
		var target_depth := 28.0
		match blk.district_zone:
			"downtown_mixed":
				target_lot_w = 22.8
				target_depth = 33.0
			"commercial_corridor":
				target_lot_w = 20.4
				target_depth = 30.0
			"residential_hills":
				target_lot_w = 15.6
				target_depth = 25.5
			"light_industrial":
				target_lot_w = 28.5
				target_depth = 37.0

		# Partition block cleanly into disjoint street-fronting strips and lots.
		var raw_lots := _partition_block_into_lots(blk, target_lot_w, target_depth, rng)
		for lot_info in raw_lots:
			var lot_poly: PackedVector2Array = lot_info["poly"]
			if lot_poly.size() < 3 or absf(ParcelData.signed_area(lot_poly)) < 160.0:
				continue
			var p := _make_parcel_from_frontage(
				"parcel_%04d" % parcel_seq,
				blk,
				lot_poly,
				lot_info["front_p0"],
				lot_info["front_p1"],
				lot_info["road_id"],
				road_graph,
				terrain,
				config,
				false
			)
			parcel_seq += 1
			parcels.append(p)

	# Dedicated coastal oceanfront parcels lining the south side of OCEANFRONT BLVD!
	if terrain != null and terrain.beach_enabled:
		parcel_seq = _generate_beachfront_parcels(config, terrain, road_graph, parcels, parcel_seq, rng)

	return parcels


static func _generate_beachfront_parcels(
	config: CityConfig,
	terrain: TerrainData,
	road_graph: RoadGraph,
	parcels: Array,
	parcel_seq: int,
	rng: RandomNumberGenerator
) -> int:
	var south_z := terrain.coast_road_z
	var coast_blk := ParcelData.CityBlock.new()
	coast_blk.id = 9900
	coast_blk.district_zone = "beachfront"

	for edge in road_graph.edges:
		if edge.is_bridge:
			continue
		var pa := road_graph.nodes[edge.node_a].pos
		var pb := road_graph.nodes[edge.node_b].pos
		if absf(pa.y - south_z) > 5.0 or absf(pb.y - south_z) > 5.0:
			continue
		var x_min := minf(pa.x, pb.x) + 12.0
		var x_max := maxf(pa.x, pb.x) - 12.0
		if x_max - x_min < 22.0:
			continue

		var half_corr := edge.road_width * 0.5 + edge.sidewalk_width
		var z_top := south_z + half_corr + 1.15
		var lot_depth := 30.0
		var z_bot := z_top + lot_depth

		var cur_x := x_min
		while cur_x + 19.0 <= x_max:
			var lot_w := minf(rng.randf_range(21.0, 26.5), x_max - cur_x)
			if lot_w < 18.0:
				break
			var mid_x := cur_x + lot_w * 0.5
			var mid_z := (z_top + z_bot) * 0.5
			# Keep clear of the river estuary mouth & shoreline swash
			var creek_d := terrain.distance_to_creek(Vector2(mid_x, mid_z))
			var shore_z := terrain.get_beach_shore_z(mid_x)
			if creek_d >= terrain.creek_half_width + 26.0 and z_bot < shore_z - 36.0:
				var x0 := cur_x + 1.0
				var x1 := cur_x + lot_w - 1.0
				var lot_poly := PackedVector2Array([
					Vector2(x0, z_top),
					Vector2(x1, z_top),
					Vector2(x1, z_bot),
					Vector2(x0, z_bot),
				])
				# Verify all 4 corners stay clear of roads and river
				var clear := true
				for c in lot_poly:
					if road_graph.distance_to_road_corridor(c) < 0.75 or terrain.distance_to_creek(c) < terrain.creek_half_width + 4.0:
						clear = false
						break
				if clear:
					var p := _make_parcel_from_frontage(
						"parcel_%04d" % parcel_seq,
						coast_blk,
						lot_poly,
						Vector2(x0, z_top),
						Vector2(x1, z_top),
						edge.id,
						road_graph,
						terrain,
						config,
						false
					)
					p.front_setback = 2.6
					p.side_setback = 2.0
					p.rear_setback = 4.6
					parcel_seq += 1
					parcels.append(p)
			cur_x += lot_w
	return parcel_seq


static func _partition_block_into_lots(blk: ParcelData.CityBlock, target_lot_w: float, target_depth: float, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var poly := blk.buildable_polygon
	var n := poly.size()
	if n < 3:
		return []

	# Pick the longest non-alley frontage side as primary axis.
	var primary_side := 0
	var best_len := 0.0
	for i in range(n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var l := a.distance_to(b)
		if l > best_len:
			best_len = l
			primary_side = i

	var opp_side := (primary_side + int(n / 2)) % n
	var left_side := (primary_side - 1 + n) % n
	var right_side := (primary_side + 1) % n

	var p0 := poly[primary_side]
	var p1 := poly[(primary_side + 1) % n]
	var p_dir := (p1 - p0).normalized()
	var p_inward := Vector2(-p_dir.y, p_dir.x)

	# Measure depth perpendicular to primary_side.
	var max_depth := 0.0
	for v in poly:
		max_depth = maxf(max_depth, (v - p0).dot(p_inward))

	var results: Array[Dictionary] = []

	# Side-peel strips on deep wide blocks so side streets get active frontage too.
	var remaining := poly
	if best_len > 70.0 and max_depth > 48.0:
		var side_strip_d := clampf(target_depth * 0.88, 18.0, 26.0)
		var l0 := poly[left_side]
		var l1 := poly[(left_side + 1) % n]
		var l_in := Vector2(-(l1 - l0).y, (l1 - l0).x).normalized()
		var split_l := _split_poly_by_line(remaining, l0 + l_in * side_strip_d, l_in)
		var left_strip: PackedVector2Array = split_l["back"]
		var next_rem: PackedVector2Array = split_l["front"]
		if absf(ParcelData.signed_area(left_strip)) > 240.0 and next_rem.size() >= 3 and absf(ParcelData.signed_area(next_rem)) > 1100.0:
			remaining = next_rem
			var l_road := blk.edge_road_ids[left_side] if left_side < blk.edge_road_ids.size() else -1
			results.append_array(_slice_strip_along_edge(left_strip, l0, l1, l_road, target_lot_w, rng))

		if best_len > 92.0 and right_side != left_side and right_side != primary_side and right_side != opp_side:
			var r0 := poly[right_side]
			var r1 := poly[(right_side + 1) % n]
			var r_in := Vector2(-(r1 - r0).y, (r1 - r0).x).normalized()
			var split_r := _split_poly_by_line(remaining, r0 + r_in * side_strip_d, r_in)
			var right_strip: PackedVector2Array = split_r["back"]
			var rem_after_r: PackedVector2Array = split_r["front"]
			if absf(ParcelData.signed_area(right_strip)) > 240.0 and rem_after_r.size() >= 3 and absf(ParcelData.signed_area(rem_after_r)) > 1100.0:
				remaining = rem_after_r
				var r_road := blk.edge_road_ids[right_side] if right_side < blk.edge_road_ids.size() else -1
				results.append_array(_slice_strip_along_edge(right_strip, r0, r1, r_road, target_lot_w, rng))

	# Split remaining polygon into front half (facing primary_side) and back half (facing opp_side).
	if max_depth > 34.0:
		var mid_depth := max_depth * rng.randf_range(0.46, 0.54)
		var split_fb := _split_poly_by_line(remaining, p0 + p_inward * mid_depth, p_inward)
		var front_half: PackedVector2Array = split_fb["back"]
		var back_half: PackedVector2Array = split_fb["front"]

		if front_half.size() >= 3 and absf(ParcelData.signed_area(front_half)) > 220.0:
			var r_front := blk.edge_road_ids[primary_side] if primary_side < blk.edge_road_ids.size() else -1
			results.append_array(_slice_strip_along_edge(front_half, p0, p1, r_front, target_lot_w, rng))

		if back_half.size() >= 3 and absf(ParcelData.signed_area(back_half)) > 220.0:
			var b0 := poly[opp_side]
			var b1 := poly[(opp_side + 1) % n]
			var r_back := blk.edge_road_ids[opp_side] if opp_side < blk.edge_road_ids.size() else -1
			results.append_array(_slice_strip_along_edge(back_half, b0, b1, r_back, target_lot_w, rng))
	else:
		var r_front := blk.edge_road_ids[primary_side] if primary_side < blk.edge_road_ids.size() else -1
		results.append_array(_slice_strip_along_edge(remaining, p0, p1, r_front, target_lot_w, rng))

	return results


static func _slice_strip_along_edge(strip: PackedVector2Array, ref_p0: Vector2, ref_p1: Vector2, road_id: int, target_lot_w: float, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := (ref_p1 - ref_p0).normalized()
	if dir.length_squared() < 0.5:
		return out
	var inward := Vector2(-dir.y, dir.x)

	# Project strip vertices onto dir to find actual span.
	var min_s := INF
	var max_s := -INF
	for v in strip:
		var s := (v - ref_p0).dot(dir)
		min_s = minf(min_s, s)
		max_s = maxf(max_s, s)

	var span := max_s - min_s
	if span < 11.0:
		return out

	var count := maxi(1, int(round(span / target_lot_w)))
	count = mini(count, 14)
	if span / float(count) < 10.5 and count > 1:
		count -= 1

	# Slight organic variation in lot widths.
	var weights: Array[float] = []
	var w_sum := 0.0
	for _i in range(count):
		var w := rng.randf_range(0.84, 1.18)
		weights.append(w)
		w_sum += w

	var cur_poly := strip
	var cur_s := min_s
	for i in range(count):
		var lot_w := span * (weights[i] / w_sum)
		var next_s := cur_s + lot_w
		var lot_poly := cur_poly
		if i < count - 1:
			var split_res := _split_poly_by_line(cur_poly, ref_p0 + dir * next_s, dir)
			lot_poly = split_res["back"]
			cur_poly = split_res["front"]

		if lot_poly.size() >= 3 and absf(ParcelData.signed_area(lot_poly)) >= 160.0:
			# Determine best frontage segment on this clipped lot along ref_p0->ref_p1 direction.
			var f_edge := _find_closest_frontage_segment(lot_poly, inward)
			out.append({
				"poly": ParcelData.ensure_ccw(lot_poly),
				"front_p0": f_edge[0],
				"front_p1": f_edge[1],
				"road_id": road_id,
			})
		cur_s = next_s

	return out


static func _find_closest_frontage_segment(poly: PackedVector2Array, target_inward: Vector2) -> Array[Vector2]:
	var n := poly.size()
	var best_dot := -INF
	var best_p0 := poly[0]
	var best_p1 := poly[1 % n]
	for i in range(n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var e := b - a
		var l := e.length()
		if l < 2.0:
			continue
		var inw := Vector2(-e.y, e.x) / l
		var d := inw.dot(target_inward)
		if d > best_dot:
			best_dot = d
			best_p0 = a
			best_p1 = b
	return [best_p0, best_p1]


static func _split_poly_by_line(poly: PackedVector2Array, line_pt: Vector2, normal: Vector2) -> Dictionary:
	## Splits convex poly into 'front' (dot >= 0) and 'back' (dot <= 0).
	var front := PackedVector2Array()
	var back := PackedVector2Array()
	var n := poly.size()
	for i in range(n):
		var curr := poly[i]
		var nxt := poly[(i + 1) % n]
		var dc := (curr - line_pt).dot(normal)
		var dn := (nxt - line_pt).dot(normal)
		if dc >= 0.0:
			front.append(curr)
			if dn < 0.0:
				var t := dc / (dc - dn)
				var inter := curr.lerp(nxt, t)
				front.append(inter)
				back.append(inter)
		else:
			back.append(curr)
			if dn >= 0.0:
				var t := dc / (dc - dn)
				var inter := curr.lerp(nxt, t)
				front.append(inter)
				back.append(inter)

	return {
		"front": ParcelData.ensure_ccw(front) if front.size() >= 3 else PackedVector2Array(),
		"back": ParcelData.ensure_ccw(back) if back.size() >= 3 else PackedVector2Array(),
	}


static func _make_parcel(pid: String, blk: ParcelData.CityBlock, poly: PackedVector2Array, side_idx: int, road_graph: RoadGraph, terrain: TerrainData, config: CityConfig, is_park: bool) -> ParcelData.Parcel:
	var a := poly[side_idx]
	var b := poly[(side_idx + 1) % poly.size()]
	var rid := blk.edge_road_ids[side_idx] if side_idx < blk.edge_road_ids.size() else -1
	return _make_parcel_from_frontage(pid, blk, poly, a, b, rid, road_graph, terrain, config, is_park)


static func _make_parcel_from_frontage(pid: String, blk: ParcelData.CityBlock, poly: PackedVector2Array, fp0: Vector2, fp1: Vector2, rid: int, road_graph: RoadGraph, terrain: TerrainData, config: CityConfig, is_park: bool) -> ParcelData.Parcel:
	var p := ParcelData.Parcel.new()
	p.id = pid
	p.block_id = blk.id
	p.district_zone = blk.district_zone
	p.polygon = ParcelData.ensure_ccw(poly)

	# Verify frontage edge is actually adjacent to a road corridor; otherwise select the edge closest to a road.
	var chosen_p0 := fp0
	var chosen_p1 := fp1
	var mid_dist := road_graph.distance_to_road_corridor((chosen_p0 + chosen_p1) * 0.5)
	if mid_dist > 3.5 and p.polygon.size() >= 3:
		var best_d := INF
		for i in range(p.polygon.size()):
			var a := p.polygon[i]
			var b := p.polygon[(i + 1) % p.polygon.size()]
			if a.distance_to(b) < 4.0:
				continue
			var d := road_graph.distance_to_road_corridor((a + b) * 0.5)
			if d < best_d:
				best_d = d
				chosen_p0 = a
				chosen_p1 = b

	p.frontage_p0 = chosen_p0
	p.frontage_p1 = chosen_p1
	var e := chosen_p1 - chosen_p0
	var elen := maxf(0.01, e.length())
	# Outward normal points away from parcel interior (toward street).
	p.frontage_normal = Vector2(e.y, -e.x) / elen
	p.frontage_road_id = rid
	p.is_park = is_park

	var front_mid := (chosen_p0 + chosen_p1) * 0.5
	var road_q := road_graph.query_nearest_edge(front_mid)
	if road_q.get("valid", false):
		p.sidewalk_elevation = float(road_q["pos_3d"].y) + 0.15
		p.frontage_road_id = int(road_q["edge_id"])
		p.frontage_road_t = float(road_q["t"])
	else:
		p.sidewalk_elevation = terrain.sample_height(front_mid.x, front_mid.y)

	# Detect secondary street frontage on corner parcels (non-alley road adjacent to left/right edge).
	if not is_park and p.polygon.size() >= 3:
		var p_right := Vector2(p.frontage_normal.y, -p.frontage_normal.x)
		var best_sec_clear := INF
		for ei in range(p.polygon.size()):
			var ea := p.polygon[ei]
			var eb := p.polygon[(ei + 1) % p.polygon.size()]
			var seg_len := ea.distance_to(eb)
			if seg_len < 6.0:
				continue
			var emid := (ea + eb) * 0.5
			if emid.distance_to(front_mid) < 1.5:
				continue
			var e_out := Vector2((eb - ea).y, -(eb - ea).x) / seg_len
			var side_dot := e_out.dot(p_right)
			var side_name := ""
			if side_dot > 0.55:
				side_name = "right"
			elif side_dot < -0.55:
				side_name = "left"
			else:
				continue
			var srq := road_graph.query_nearest_edge(emid)
			if not srq.get("valid", false):
				continue
			var s_eid := int(srq["edge_id"])
			if s_eid == p.frontage_road_id or s_eid < 0 or s_eid >= road_graph.edges.size():
				continue
			var s_edge := road_graph.edges[s_eid]
			if s_edge.road_class == "alley" or s_edge.sidewalk_width < 1.0:
				continue
			var clearance := float(srq["dist"]) - (float(srq["half_road_w"]) + float(srq["sidewalk_w"]))
			if clearance <= 3.5 and clearance < best_sec_clear:
				best_sec_clear = clearance
				p.secondary_frontage_face = side_name
				p.secondary_frontage_road_id = s_eid

	match blk.district_zone:
		"downtown_mixed":
			p.front_setback = 1.6
			p.side_setback = 1.2
			p.rear_setback = 1.5
		"commercial_corridor":
			p.front_setback = 2.0
			p.side_setback = 1.4
			p.rear_setback = 1.8
		"light_industrial":
			p.front_setback = 3.2
			p.side_setback = 2.2
			p.rear_setback = 2.4
		_:
			p.front_setback = 2.8
			p.side_setback = 1.6
			p.rear_setback = 2.0

	var cent := ParcelData.polygon_centroid(p.polygon)
	p.chunk_coord = Vector2i(
		clampi(int(floor(cent.x / config.chunk_size)), 0, config.get_chunks_per_axis() - 1),
		clampi(int(floor(cent.y / config.chunk_size)), 0, config.get_chunks_per_axis() - 1)
	)
	return p
