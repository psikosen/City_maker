class_name RoadGenerator
extends RefCounted

## Generates a connected, hierarchical neighborhood road graph (arterials, collectors,
## local streets, alleys, and creek bridges) together with exact convex city blocks.

const MIN_EDGE_LEN := 28.0
const MIN_CORNER_ANGLE_RAD := 0.85 # ~49 degrees
const MIN_BLOCK_AREA := 2200.0

const EW_STREET_NAMES := [
	"1ST ST", "2ND ST", "3RD ST", "4TH ST", "5TH ST", "6TH ST",
	"7TH ST", "8TH ST", "9TH ST", "10TH ST", "11TH ST", "12TH ST",
	"13TH ST", "14TH ST", "15TH ST", "16TH ST", "18TH ST", "20TH ST",
	"CESAR CHAVEZ ST", "RAINEY ST", "HOLLY ST", "BARTON SPRINGS RD",
	"OLTORF ST", "KOENIG LN", "RESEARCH BLVD", "PARMER LN",
	"METROPOLIS PKWY", "HARBOR BLVD",
]

const NS_AVENUE_NAMES := [
	"CONGRESS AVE", "LAVACA ST", "GUADALUPE ST", "COLORADO ST", "BRAZOS ST",
	"SAN JACINTO BLVD", "TRINITY ST", "RED RIVER ST", "NUECES ST", "RIO GRANDE ST",
	"LAMAR BLVD", "WEST AVE", "CHICON ST", "COMAL ST", "PLEASANT VALLEY RD",
	"RIVERSIDE DR", "SKYLINE AVE", "GRAND CENTRAL PKWY", "BROADWAY", "PARK AVE",
	"LEXINGTON AVE", "MADISON AVE",
]


class SubBlock:
	var verts: Array[int] = [] # Node IDs in CCW order
	var edges: Array[int] = [] # RoadEdge IDs matching verts[i] -> verts[(i+1)%n]
	var tag: String = "general"


static func generate(config: CityConfig, terrain: TerrainData, district_centers: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var graph := RoadGraph.new()
	var s := config.world_size
	var m := clampf(s * 0.04, 32.0, 44.0) # Perimeter road inset scaled with world size.

	# Initial outer collector ring: pulled inland along South coast to make room for Beachfront & Ocean!
	var south_z := terrain.coast_road_z if terrain.beach_enabled else (s - m)
	var n0 := graph.add_node(Vector2(m, m))
	var n1 := graph.add_node(Vector2(s - m, m))
	var n2 := graph.add_node(Vector2(s - m, south_z))
	var n3 := graph.add_node(Vector2(m, south_z))

	var e0 := graph.add_edge(n0.id, n1.id, "collector")
	var e1 := graph.add_edge(n1.id, n2.id, "collector")
	var e2 := graph.add_edge(n2.id, n3.id, "collector")
	var e3 := graph.add_edge(n3.id, n0.id, "collector")

	var root_block := SubBlock.new()
	root_block.verts = [n0.id, n1.id, n2.id, n3.id]
	root_block.edges = [e0.id, e1.id, e2.id, e3.id]
	var sub_blocks: Array[SubBlock] = [root_block]

	var creek_x_base: float = float(district_centers["creek_x_base"])

	# 1. Primary East-West Arterial Spine (crosses the creek valley on a bridge!).
	var dt_center: Vector2 = district_centers["downtown_mixed"]
	var ew_t0 := clampf((dt_center.y + rng.randf_range(-18.0, 18.0) - m) / maxf(100.0, south_z - m), 0.36, 0.64)
	var ew_t1 := clampf(ew_t0 + rng.randf_range(-0.07, 0.07), 0.35, 0.65)
	# Note: side 3 goes (m, s-m) -> (m, m) [decreasing Z], side 1 goes (s-m, m) -> (s-m, s-m) [increasing Z].
	var split_ew := _split_block_on_edges(graph, sub_blocks, 0, 3, 1.0 - ew_t0, 1, ew_t1, "arterial")

	# 2. Primary North-South Arterial Spine intersecting the E-W arterial at a central Downtown hub.
	var hub_t := clampf((dt_center.x - m) / (s - 2.0 * m) + rng.randf_range(-0.04, 0.04), 0.28, 0.46)
	# Keep the N-S arterial safely west of the broad urban river channel.
	var approx_hub_x := lerpf(m, s - m, hub_t)
	if absf(approx_hub_x - creek_x_base) < 56.0:
		hub_t = clampf((creek_x_base - 90.0 - m) / (s - 2.0 * m), 0.28, 0.46)

	var ew_edge_id: int = split_ew["new_edge_id"]
	var hub_node_id := _split_graph_edge(graph, sub_blocks, ew_edge_id, hub_t)

	# Split North block (index 0) and South block (index 1) from hub_node_id to outer ring.
	var north_idx := _find_block_containing_node(sub_blocks, hub_node_id, true, graph)
	if north_idx != -1:
		_split_block_from_node(graph, sub_blocks, north_idx, hub_node_id, e0.id, clampf(hub_t + rng.randf_range(-0.04, 0.04), 0.26, 0.48), "arterial")

	var south_idx := _find_block_containing_node(sub_blocks, hub_node_id, false, graph)
	if south_idx != -1:
		_split_block_from_node(graph, sub_blocks, south_idx, hub_node_id, e2.id, 1.0 - clampf(hub_t + rng.randf_range(-0.04, 0.04), 0.26, 0.48), "arterial")

	# 3. Recursive neighborhood block subdivision.
	var target_blocks := mini(46, maxi(16, int(round(pow(s / 1536.0, 1.75) * 92.0))))
	var max_iters := maxi(48, target_blocks * 2 + 24)
	var area_scale := clampf((s / 512.0) * 0.42, 1.0, 1.38)
	var iter := 0
	while sub_blocks.size() < target_blocks and iter < max_iters:
		iter += 1
		# Pick the largest eligible block.
		var best_idx := -1
		var best_score := 0.0
		for bi in range(sub_blocks.size()):
			var b := sub_blocks[bi]
			if b.tag == "locked":
				continue
			var poly := _block_polygon(graph, b)
			var area := ParcelData.signed_area(poly)
			var cent := ParcelData.polygon_centroid(poly)
			var zone := DistrictGenerator.classify_block(cent, creek_x_base, terrain.creek_half_width, district_centers, s)
			var threshold := 7200.0 * area_scale
			if zone == "downtown_mixed" or zone == "commercial_corridor":
				threshold = 5400.0 * area_scale
			elif zone == "civic_park":
				threshold = 11500.0 * area_scale
			elif zone == "light_industrial":
				threshold = 9200.0 * area_scale
			if area > threshold and area > best_score:
				best_score = area
				best_idx = bi
		if best_idx == -1:
			break

		var chosen := sub_blocks[best_idx]
		var poly_c := _block_polygon(graph, chosen)
		var cent_c := ParcelData.polygon_centroid(poly_c)
		var zone_c := DistrictGenerator.classify_block(cent_c, creek_x_base, terrain.creek_half_width, district_centers, s)
		var rclass := "local"
		if best_score > 78000.0 * area_scale:
			rclass = "arterial"
		elif best_score > 16500.0 * area_scale:
			rclass = "collector"
		elif zone_c == "downtown_mixed" and best_score < 8200.0 * area_scale and rng.randf() < 0.45:
			rclass = "alley"

		var did_split := _try_subdivide_block(graph, sub_blocks, best_idx, rclass, creek_x_base, terrain, rng)
		if not did_split:
			# Mark un-splittable so the primary pass continues subdividing other blocks cleanly.
			sub_blocks[best_idx].tag = "locked"
			continue

	# Clean pass: allow remaining large unlocked blocks to split even if one block failed.
	for pass_i in range(maxi(18, target_blocks + 12)):
		if sub_blocks.size() >= target_blocks:
			break
		var candidate_idx := -1
		var candidate_area := 0.0
		for bi in range(sub_blocks.size()):
			if sub_blocks[bi].tag == "locked":
				continue
			var poly := _block_polygon(graph, sub_blocks[bi])
			var area := ParcelData.signed_area(poly)
			var cent := ParcelData.polygon_centroid(poly)
			var zone := DistrictGenerator.classify_block(cent, creek_x_base, terrain.creek_half_width, district_centers, s)
			var min_split_area := (5600.0 if (zone == "downtown_mixed" or zone == "commercial_corridor") else 8200.0) * area_scale
			if zone == "civic_park":
				min_split_area = 12500.0 * area_scale
			if area > min_split_area and area > candidate_area:
				candidate_area = area
				candidate_idx = bi
		if candidate_idx == -1:
			break
		var rclass := "arterial" if candidate_area > 78000.0 * area_scale else ("collector" if candidate_area > 15500.0 * area_scale else "local")
		if not _try_subdivide_block(graph, sub_blocks, candidate_idx, rclass, creek_x_base, terrain, rng):
			sub_blocks[candidate_idx].tag = "locked"

	# 4. Rebuild clean node incident_edge_ids from active edges.
	for n in graph.nodes:
		n.incident_edge_ids.clear()
	for e in graph.edges:
		graph.nodes[e.node_a].incident_edge_ids.append(e.id)
		graph.nodes[e.node_b].incident_edge_ids.append(e.id)

	# 4b. Assign deterministic corridor-coherent street names to every edge.
	_assign_street_names(graph, terrain, rng)

	# 5. Compute exact mitered intersection trims & rounded junction polygons (2D layout).
	_compute_intersections(graph)

	# 6. Detect creek crossings -> mark bridge spans & assign Hermite-smoothed elevations aligned cleanly to junction aprons!
	_compute_bridges_and_elevations(graph, terrain)

	# 7. Populate vehicle lane segments along each road edge.
	_build_lane_graph(graph)

	# 8. Convert SubBlocks to ParcelData.CityBlock objects.
	var out_blocks: Array = []
	for bi in range(sub_blocks.size()):
		var sb := sub_blocks[bi]
		var blk := ParcelData.CityBlock.new()
		blk.id = bi
		var poly := _block_polygon(graph, sb)
		blk.raw_polygon = ParcelData.ensure_ccw(poly)
		blk.center = ParcelData.polygon_centroid(blk.raw_polygon)

		var cx_at_z := DistrictGenerator.eval_creek_x(blk.center.y, district_centers)
		blk.district_zone = DistrictGenerator.classify_block(blk.center, cx_at_z, terrain.creek_half_width, district_centers, s)

		var road_ids := PackedInt32Array()
		var insets := PackedFloat32Array()
		for eid in sb.edges:
			road_ids.append(eid)
			var e := graph.edges[eid]
			insets.append(e.road_width * 0.5 + e.sidewalk_width + 0.6)
		blk.edge_road_ids = road_ids
		blk.edge_inset_dists = insets
		blk.buildable_polygon = ParcelData.inset_convex_polygon_per_edge(blk.raw_polygon, insets)
		out_blocks.append(blk)

	DistrictGenerator.ensure_district_diversity(out_blocks, district_centers)

	return {
		"road_graph": graph,
		"blocks": out_blocks,
	}


static func _block_polygon(graph: RoadGraph, sb: SubBlock) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for nid in sb.verts:
		poly.append(graph.nodes[nid].pos)
	return poly


static func _split_graph_edge(graph: RoadGraph, sub_blocks: Array[SubBlock], edge_id: int, t: float) -> int:
	var edge := graph.edges[edge_id]
	var u := edge.node_a
	var v := edge.node_b
	var pos := graph.nodes[u].pos.lerp(graph.nodes[v].pos, t)
	var mid_node := graph.add_node(pos)

	# Mutate existing edge to (u, mid_node) and append (mid_node, v).
	edge.node_b = mid_node.id
	var new_edge := graph.add_edge(mid_node.id, v, edge.road_class)
	new_edge.road_width = edge.road_width
	new_edge.sidewalk_width = edge.sidewalk_width

	for sb in sub_blocks:
		var k := sb.edges.size()
		for i in range(k):
			if sb.edges[i] == edge_id:
				var va := sb.verts[i]
				if va == u:
					sb.verts.insert(i + 1, mid_node.id)
					sb.edges[i] = edge_id
					sb.edges.insert(i + 1, new_edge.id)
				else:
					sb.verts.insert(i + 1, mid_node.id)
					sb.edges[i] = new_edge.id
					sb.edges.insert(i + 1, edge_id)
				break

	return mid_node.id


static func _split_block_on_edges(graph: RoadGraph, sub_blocks: Array[SubBlock], block_idx: int, side_a: int, t_a: float, side_b: int, t_b: float, road_class: String) -> Dictionary:
	var sb := sub_blocks[block_idx]
	var edge_a := sb.edges[side_a]
	var edge_b := sb.edges[side_b]
	var na := _split_graph_edge(graph, sub_blocks, edge_a, t_a)
	var nb := _split_graph_edge(graph, sub_blocks, edge_b, t_b)
	return _split_block_between_existing_nodes(graph, sub_blocks, block_idx, na, nb, road_class)


static func _split_block_from_node(graph: RoadGraph, sub_blocks: Array[SubBlock], block_idx: int, existing_node_id: int, target_edge_id: int, t_target: float, road_class: String) -> Dictionary:
	var nb := _split_graph_edge(graph, sub_blocks, target_edge_id, t_target)
	return _split_block_between_existing_nodes(graph, sub_blocks, block_idx, existing_node_id, nb, road_class)


static func _split_block_between_existing_nodes(graph: RoadGraph, sub_blocks: Array[SubBlock], block_idx: int, node_a: int, node_b: int, road_class: String) -> Dictionary:
	var sb := sub_blocks[block_idx]
	var ia := sb.verts.find(node_a)
	var ib := sb.verts.find(node_b)
	if ia == -1 or ib == -1 or ia == ib:
		return {"ok": false}

	var split_edge := graph.add_edge(node_a, node_b, road_class)
	var k := sb.verts.size()

	# Build Block 1: ia -> ... -> ib, then closing edge (node_b -> node_a).
	var b1 := SubBlock.new()
	var idx := ia
	while idx != ib:
		b1.verts.append(sb.verts[idx])
		b1.edges.append(sb.edges[idx])
		idx = (idx + 1) % k
	b1.verts.append(sb.verts[ib])
	b1.edges.append(split_edge.id)

	# Build Block 2: ib -> ... -> ia, then closing edge (node_a -> node_b).
	var b2 := SubBlock.new()
	idx = ib
	while idx != ia:
		b2.verts.append(sb.verts[idx])
		b2.edges.append(sb.edges[idx])
		idx = (idx + 1) % k
	b2.verts.append(sb.verts[ia])
	b2.edges.append(split_edge.id)

	sub_blocks[block_idx] = b1
	sub_blocks.append(b2)
	return {"ok": true, "new_edge_id": split_edge.id}


static func _find_block_containing_node(sub_blocks: Array[SubBlock], node_id: int, prefer_north: bool, graph: RoadGraph) -> int:
	var best_idx := -1
	var best_z := INF if prefer_north else -INF
	for i in range(sub_blocks.size()):
		if sub_blocks[i].verts.has(node_id):
			var cent := ParcelData.polygon_centroid(_block_polygon(graph, sub_blocks[i]))
			if prefer_north and cent.y < best_z:
				best_z = cent.y
				best_idx = i
			elif not prefer_north and cent.y > best_z:
				best_z = cent.y
				best_idx = i
	return best_idx


static func _try_subdivide_block(graph: RoadGraph, sub_blocks: Array[SubBlock], block_idx: int, road_class: String, _creek_x_base: float, terrain: TerrainData, rng: RandomNumberGenerator) -> bool:
	var sb := sub_blocks[block_idx]
	var k := sb.verts.size()
	if k < 4:
		return false

	# Find longest edge and its opposite edge (prefer splitting across the longest axis).
	var edge_lens: Array[float] = []
	var best_side := -1
	var best_len := 0.0
	for i in range(k):
		var pa := graph.nodes[sb.verts[i]].pos
		var pb := graph.nodes[sb.verts[(i + 1) % k]].pos
		var l := pa.distance_to(pb)
		edge_lens.append(l)
		if l > best_len:
			best_len = l
			best_side = i

	if best_side == -1 or best_len < MIN_EDGE_LEN * 2.0:
		return false

	# Try splitting best_side and its opposite side (best_side + k/2), then perpendicular pair,
	# plus best geometric opposing edge when T-junction vertices make k >= 5.
	var opp_side := (best_side + int(k / 2)) % k
	var side_pairs: Array[Array] = []
	if edge_lens[opp_side] >= MIN_EDGE_LEN * 1.9:
		side_pairs.append([best_side, opp_side])
	if k >= 5:
		var va_best := (graph.nodes[sb.verts[(best_side + 1) % k]].pos - graph.nodes[sb.verts[best_side]].pos).normalized()
		var best_geo_opp := -1
		var best_geo_len := 0.0
		for si in range(k):
			if si == best_side or si == opp_side or si == (best_side + 1) % k or si == (best_side + k - 1) % k:
				continue
			if edge_lens[si] < MIN_EDGE_LEN * 1.9:
				continue
			var v_si := (graph.nodes[sb.verts[(si + 1) % k]].pos - graph.nodes[sb.verts[si]].pos).normalized()
			if va_best.dot(v_si) < -0.45 and edge_lens[si] > best_geo_len:
				best_geo_len = edge_lens[si]
				best_geo_opp = si
		if best_geo_opp != -1:
			side_pairs.append([best_side, best_geo_opp])
	if k >= 4:
		var alt_a := (best_side + 1) % k
		var alt_b := (opp_side + 1) % k
		if edge_lens[alt_a] >= MIN_EDGE_LEN * 1.9 and edge_lens[alt_b] >= MIN_EDGE_LEN * 1.9:
			side_pairs.append([alt_a, alt_b])
	if side_pairs.is_empty():
		return false

	for pair in side_pairs:
		var s_a: int = int(pair[0])
		var s_b: int = int(pair[1])
		var ea := graph.edges[sb.edges[s_a]]
		var eb := graph.edges[sb.edges[s_b]]
		var va0 := graph.nodes[sb.verts[s_a]].pos
		var va1 := graph.nodes[sb.verts[(s_a + 1) % k]].pos
		var vb0 := graph.nodes[sb.verts[s_b]].pos
		var vb1 := graph.nodes[sb.verts[(s_b + 1) % k]].pos

		for attempt in range(8):
			var t_a: float
			if attempt < 4:
				t_a = rng.randf_range(0.40, 0.60)
			elif attempt < 6:
				t_a = rng.randf_range(0.24, 0.37)
			else:
				t_a = rng.randf_range(0.63, 0.76)
			var t_b := clampf((1.0 - t_a) + rng.randf_range(-0.06, 0.06), 0.22, 0.78)

			# Map t relative to edge direction vs block winding!
			var pa := va0.lerp(va1, t_a)
			var pb := vb0.lerp(vb1, t_b)

			# Keep junction split points out of the river channel and avoid placing N-S corridors inside the river.
			if terrain.distance_to_creek(pa) < terrain.creek_half_width + 18.0 or terrain.distance_to_creek(pb) < terrain.creek_half_width + 18.0:
				continue
			var dir := (pb - pa).normalized()
			if absf(dir.y) > 0.55:
				var runs_along_river := false
				for t_chk: float in [0.2, 0.35, 0.5, 0.65, 0.8]:
					if terrain.distance_to_creek(pa.lerp(pb, t_chk)) < terrain.creek_half_width + 15.0:
						runs_along_river = true
						break
				if runs_along_river:
					continue

			if pa.distance_to(pb) < MIN_EDGE_LEN:
				continue

			# Check sub-edge lengths against MIN_EDGE_LEN.
			if va0.distance_to(pa) < MIN_EDGE_LEN or va1.distance_to(pa) < MIN_EDGE_LEN:
				continue
			if vb0.distance_to(pb) < MIN_EDGE_LEN or vb1.distance_to(pb) < MIN_EDGE_LEN:
				continue

			# Validate split convex sub-polygons before committing to graph.
			var poly1 := _preview_split_poly(graph, sb, s_a, pa, s_b, pb, true)
			var poly2 := _preview_split_poly(graph, sb, s_a, pa, s_b, pb, false)
			if not _is_valid_block_polygon(poly1) or not _is_valid_block_polygon(poly2):
				continue

			# Convert block-relative t_a/t_b to edge-direction t_ea/t_eb.
			var t_ea := t_a if sb.verts[s_a] == ea.node_a else (1.0 - t_a)
			var t_eb := t_b if sb.verts[s_b] == eb.node_a else (1.0 - t_b)
			_split_block_on_edges(graph, sub_blocks, block_idx, s_a, t_ea, s_b, t_eb, road_class)
			return true

	return false


static func _preview_split_poly(graph: RoadGraph, sb: SubBlock, side_a: int, pa: Vector2, side_b: int, pb: Vector2, first_half: bool) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var k := sb.verts.size()
	if first_half:
		poly.append(pa)
		var idx := (side_a + 1) % k
		while idx != (side_b + 1) % k:
			poly.append(graph.nodes[sb.verts[idx]].pos)
			idx = (idx + 1) % k
		poly.append(pb)
	else:
		poly.append(pb)
		var idx := (side_b + 1) % k
		while idx != (side_a + 1) % k:
			poly.append(graph.nodes[sb.verts[idx]].pos)
			idx = (idx + 1) % k
		poly.append(pa)
	return poly


static func _is_valid_block_polygon(poly: PackedVector2Array) -> bool:
	var n := poly.size()
	if n < 3:
		return false
	if absf(ParcelData.signed_area(poly)) < MIN_BLOCK_AREA:
		return false
	for i in range(n):
		var p_prev := poly[(i - 1 + n) % n]
		var p_curr := poly[i]
		var p_next := poly[(i + 1) % n]
		var v1 := p_prev - p_curr
		var v2 := p_next - p_curr
		if v1.length() < MIN_EDGE_LEN or v2.length() < MIN_EDGE_LEN:
			return false
		var ang := absf(v1.angle_to(v2))
		if ang < MIN_CORNER_ANGLE_RAD or ang > PI - 0.15:
			return false
	return true


static func _compute_bridges_and_elevations(graph: RoadGraph, terrain: TerrainData) -> void:
	# 1. Assign base node elevations from terrain, keeping bridge-adjacent nodes safely above water.
	var bridge_clearance_y := terrain.water_level + 3.1
	for n in graph.nodes:
		var raw_y := terrain.sample_height(n.pos.x, n.pos.y)
		var d_creek := terrain.distance_to_creek(n.pos)
		if d_creek < terrain.creek_half_width + 18.0:
			raw_y = maxf(raw_y, bridge_clearance_y)
		n.elevation = raw_y

	# 2. Smooth node elevations along edges (2 relaxation passes) so slopes stay reasonable.
	for _pass in range(3):
		var next_elevs := PackedFloat32Array()
		next_elevs.resize(graph.nodes.size())
		for i in range(graph.nodes.size()):
			var n := graph.nodes[i]
			var raw_y := maxf(terrain.sample_height(n.pos.x, n.pos.y), terrain.water_level + 1.8)
			var sum_w := 1.0
			var sum_y := raw_y
			for eid in n.incident_edge_ids:
				var e := graph.edges[eid]
				var other_id := graph.get_other_node(e, n.id)
				var d := maxf(1.0, n.pos.distance_to(graph.nodes[other_id].pos))
				var w := 35.0 / d
				sum_y += graph.nodes[other_id].elevation * w
				sum_w += w
			next_elevs[i] = sum_y / sum_w
		for i in range(graph.nodes.size()):
			graph.nodes[i].elevation = next_elevs[i]

	# 3. Pass A: Detect creek crossings and finalize ALL bridge-adjusted node elevations BEFORE sampling edges!
	var edge_crossings := {}
	for e in graph.edges:
		var na := graph.nodes[e.node_a]
		var nb := graph.nodes[e.node_b]
		var edge_len := na.pos.distance_to(nb.pos)
		var steps := maxi(10, int(ceil(edge_len / 3.0)))
		var min_t_creek := 1.0
		var max_t_creek := 0.0
		var crosses_creek := false
		for s_i in range(steps + 1):
			var t := float(s_i) / float(steps)
			var p2 := na.pos.lerp(nb.pos, t)
			if terrain.distance_to_creek(p2) < terrain.creek_half_width + 5.5:
				crosses_creek = true
				min_t_creek = minf(min_t_creek, t)
				max_t_creek = maxf(max_t_creek, t)

		if crosses_creek and min_t_creek > 0.02 and max_t_creek < 0.98:
			e.is_bridge = true
			e.bridge_start_t = maxf(0.03, min_t_creek - 3.5 / edge_len)
			e.bridge_end_t = minf(0.97, max_t_creek + 3.5 / edge_len)
			var deck_y := maxf(bridge_clearance_y, maxf(na.elevation, nb.elevation))
			na.elevation = maxf(na.elevation, deck_y - 1.2)
			nb.elevation = maxf(nb.elevation, deck_y - 1.2)
			edge_crossings[e.id] = steps

	# 4. Pass B: Sample every edge at dense 2m intervals with flat junction approaches & Hermite transitions.
	for e in graph.edges:
		var na := graph.nodes[e.node_a]
		var nb := graph.nodes[e.node_b]
		var edge_len := na.pos.distance_to(nb.pos)
		var steps := maxi(10, int(ceil(edge_len / 2.0)))
		var t_flat_a := clampf((e.trim_a + 1.8) / maxf(1.0, edge_len), 0.10, 0.34)
		var t_flat_b := clampf((e.trim_b + 1.8) / maxf(1.0, edge_len), 0.10, 0.34)
		if t_flat_a + t_flat_b > 0.78:
			var sc := 0.78 / (t_flat_a + t_flat_b)
			t_flat_a *= sc
			t_flat_b *= sc
		e.samples.clear()
		for s_i in range(steps + 1):
			var t := float(s_i) / float(steps)
			var p2 := na.pos.lerp(nb.pos, t)
			var u_along := clampf((t - t_flat_a) / maxf(0.05, 1.0 - t_flat_a - t_flat_b), 0.0, 1.0)
			var ease_u := u_along * u_along * (3.0 - 2.0 * u_along)
			var line_y := lerpf(na.elevation, nb.elevation, ease_u)
			var terr_y := terrain.sample_height(p2.x, p2.y)
			var y := line_y
			if e.is_bridge:
				var deck_y := maxf(bridge_clearance_y + 0.4, maxf(na.elevation, nb.elevation) + 0.35)
				if t >= e.bridge_start_t and t <= e.bridge_end_t:
					var bt := (t - e.bridge_start_t) / maxf(0.01, e.bridge_end_t - e.bridge_start_t)
					y = deck_y + sin(bt * PI) * 0.35
				elif t < e.bridge_start_t:
					var u := clampf((t - t_flat_a * 0.65) / maxf(0.05, e.bridge_start_t - t_flat_a * 0.65), 0.0, 1.0)
					y = lerpf(na.elevation, deck_y, u * u * (3.0 - 2.0 * u))
				else:
					var end_span := maxf(0.05, (1.0 - t_flat_b * 0.65) - e.bridge_end_t)
					var u := clampf((t - e.bridge_end_t) / end_span, 0.0, 1.0)
					y = lerpf(deck_y, nb.elevation, u * u * (3.0 - 2.0 * u))
			else:
				# Keep crosswalks & junction approaches flat at node.elevation while gliding mid-span smoothly over terrain.
				var t_in := clampf(minf(t - t_flat_a, (1.0 - t_flat_b) - t) / 0.24, 0.0, 1.0)
				var mid_weight := (t_in * t_in * (3.0 - 2.0 * t_in)) * 0.36
				y = lerpf(line_y, maxf(terr_y, terrain.water_level + 1.4), mid_weight)
			e.samples.append(Vector3(p2.x, y, p2.y))


static func _compute_intersections(graph: RoadGraph) -> void:
	for n in graph.nodes:
		var k := n.incident_edge_ids.size()
		if k == 0:
			continue
		if k == 1:
			n.miter_radius = 4.0
			continue

		# Sort incident edges CCW around node.pos by outgoing angle.
		var items: Array[Dictionary] = []
		var max_total_w := 0.0
		var arterial_count := 0
		for eid in n.incident_edge_ids:
			var e := graph.edges[eid]
			var other_id := graph.get_other_node(e, n.id)
			var dir := (graph.nodes[other_id].pos - n.pos).normalized()
			var ang := atan2(dir.y, dir.x)
			var hw := e.road_width * 0.5
			var tw := hw + e.sidewalk_width
			max_total_w = maxf(max_total_w, tw)
			if e.road_class == "arterial" or e.road_class == "collector":
				arterial_count += 1
			items.append({
				"eid": eid,
				"dir": dir,
				"left": Vector2(-dir.y, dir.x),
				"ang": ang,
				"hw": hw,
				"tw": tw,
				"edge_len": n.pos.distance_to(graph.nodes[other_id].pos),
			})

		items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["ang"]) < float(b["ang"])
		)

		if k >= 3 and arterial_count >= 2:
			n.has_traffic_signal = true

		var trims: Array[float] = []
		trims.resize(k)
		for i in range(k):
			trims[i] = max_total_w + 1.5

		# Compute pairwise curb intersections between consecutive sorted edges.
		for i in range(k):
			var j := (i + 1) % k
			var a: Dictionary = items[i]
			var b: Dictionary = items[j]
			var ua: Vector2 = a["dir"]
			var ub: Vector2 = b["dir"]
			var la: Vector2 = a["left"]
			var lb: Vector2 = b["left"]
			var twa: float = a["tw"]
			var twb: float = b["tw"]

			# Left outer boundary of a: p_a + ua * s + la * twa
			# Right outer boundary of b: p_b + ub * t - lb * twb
			var rhs := (-lb * twb) - (la * twa)
			var det := ua.x * (-ub.y) - ua.y * (-ub.x)
			if absf(det) > 0.18:
				var s := (rhs.x * (-ub.y) - rhs.y * (-ub.x)) / det
				var t := (ua.x * rhs.y - ua.y * rhs.x) / det
				if s > 0.0 and s < 26.0:
					trims[i] = maxf(trims[i], s + 1.8)
				if t > 0.0 and t < 26.0:
					trims[j] = maxf(trims[j], t + 1.8)

		# Clamp trims safely to edge lengths and store on edges.
		var max_trim := 0.0
		for i in range(k):
			var it: Dictionary = items[i]
			var eid: int = it["eid"]
			var e := graph.edges[eid]
			var trim := clampf(trims[i], float(it["hw"]) + 1.0, float(it["edge_len"]) * 0.30)
			max_trim = maxf(max_trim, trim)
			it["trim"] = trim
			if e.node_a == n.id:
				e.trim_a = trim
			else:
				e.trim_b = trim

		# Emit rounded intersection apron polygon with smooth 6-segment cubic curb fillets
		var poly := PackedVector2Array()
		for i in range(k):
			var cur: Dictionary = items[i]
			var nxt: Dictionary = items[(i + 1) % k]
			var u_a: Vector2 = cur["dir"]
			var l_a: Vector2 = cur["left"]
			var p_a := n.pos + u_a * float(cur["trim"])
			var a_in := p_a + l_a * float(cur["hw"])

			var u_b: Vector2 = nxt["dir"]
			var l_b: Vector2 = nxt["left"]
			var p_b := n.pos + u_b * float(nxt["trim"])
			var b_in := p_b - l_b * float(nxt["hw"])

			var fillet := RoadGraph.compute_curb_fillet_pts(a_in, u_a, b_in, u_b, 6)
			for fp in fillet:
				poly.append(fp)

		n.miter_radius = max_trim
		n.junction_polygon = ParcelData.ensure_ccw(poly)


static func _build_lane_graph(graph: RoadGraph) -> void:
	graph.lanes.clear()
	for e in graph.edges:
		if e.road_class == "alley" or e.samples.size() < 2:
			continue
		var pa := graph.nodes[e.node_a].pos
		var pb := graph.nodes[e.node_b].pos
		var edge_len := pa.distance_to(pb)
		if edge_len < 1.0:
			continue
		var edge_dir := (pb - pa) / edge_len
		var t_a := clampf(e.trim_a / edge_len, 0.0, 0.42)
		var t_b := clampf(1.0 - e.trim_b / edge_len, 0.58, 1.0)
		if t_b <= t_a + 0.02:
			t_a = 0.0
			t_b = 1.0
		var trimmed_len := (t_b - t_a) * edge_len
		var seg_count := maxi(6, int(ceil(trimmed_len / 2.5)))
		# Wide 12m arterials get 2 real parallel lanes per direction straddling the 3.0m dashed white divider!
		var lane_offsets: Array[float]
		if e.road_class == "arterial" and e.road_width >= 11.0:
			lane_offsets = [1.55, 4.35]
		elif e.road_class == "collector":
			lane_offsets = [1.95]
		else:
			lane_offsets = [1.58]
		var speed := 14.5 if e.road_class == "arterial" else (11.2 if e.road_class == "collector" else 8.4)
		var n_dir_lanes := lane_offsets.size()

		for dir_sign in [1, -1]:
			var dir_lane_ids: Array[int] = []
			var travel_dir := edge_dir * float(dir_sign)
			var is_ns := absf(travel_dir.y) >= absf(travel_dir.x)
			var right := Vector2(-edge_dir.y, edge_dir.x) * float(dir_sign)
			for li in range(n_dir_lanes):
				var lane_offset: float = lane_offsets[li]
				var lane := RoadGraph.LaneSegment.new()
				lane.id = graph.lanes.size()
				lane.edge_id = e.id
				lane.direction = dir_sign
				lane.lane_index = li
				lane.lane_count = n_dir_lanes
				lane.road_class = e.road_class
				lane.start_node_id = e.node_a if dir_sign == 1 else e.node_b
				lane.end_node_id = e.node_b if dir_sign == 1 else e.node_a
				lane.speed_limit = speed * (1.06 if (n_dir_lanes > 1 and li == 0) else 1.0)
				lane.is_ns_axis = is_ns
				var pts := PackedVector3Array()
				pts.resize(seg_count + 1)
				for i in range(seg_count + 1):
					var u := float(i) / float(seg_count)
					var t := lerpf(t_a, t_b, u) if dir_sign == 1 else lerpf(t_b, t_a, u)
					var p3 := graph.sample_edge_point_3d(e, t)
					pts[i] = Vector3(p3.x + right.x * lane_offset, p3.y + 0.02, p3.z + right.y * lane_offset)
				var cum := PackedFloat32Array()
				cum.resize(pts.size())
				cum[0] = 0.0
				for pi in range(1, pts.size()):
					cum[pi] = cum[pi - 1] + pts[pi - 1].distance_to(pts[pi])
				lane.points = pts
				lane.cum_lengths = cum
				lane.total_length = cum[pts.size() - 1]
				graph.lanes.append(lane)
				dir_lane_ids.append(lane.id)
			if dir_lane_ids.size() == 2:
				graph.lanes[dir_lane_ids[0]].adjacent_lane_id = dir_lane_ids[1]
				graph.lanes[dir_lane_ids[1]].adjacent_lane_id = dir_lane_ids[0]

	# Build outgoing lane connectivity at each node with lane-discipline alignment (inner->inner / outer->outer on straight/turns).
	var lanes_by_start: Dictionary = {}
	for lane in graph.lanes:
		var bucket: Array
		if lanes_by_start.has(lane.start_node_id):
			bucket = lanes_by_start[lane.start_node_id]
		else:
			bucket = []
			lanes_by_start[lane.start_node_id] = bucket
		bucket.append(lane)

	for lane in graph.lanes:
		var candidates: Array = lanes_by_start.get(lane.end_node_id, [])
		var in_dir := Vector2.ZERO
		if lane.points.size() >= 2:
			var p_end := lane.points[lane.points.size() - 1]
			var p_prev := lane.points[lane.points.size() - 2]
			in_dir = Vector2(p_end.x - p_prev.x, p_end.z - p_prev.z).normalized()

		# Group outgoing candidates by target edge so multi-lane arterials connect cleanly without crossing streams
		var by_edge: Dictionary = {}
		for cand_var in candidates:
			var cand: RoadGraph.LaneSegment = cand_var
			if cand.edge_id == lane.edge_id:
				continue
			var arr: Array = by_edge.get(cand.edge_id, [])
			arr.append(cand)
			by_edge[cand.edge_id] = arr

		var next_ids := PackedInt32Array()
		for eid in by_edge.keys():
			var out_lanes: Array = by_edge[eid]
			if out_lanes.size() == 1:
				var c0: RoadGraph.LaneSegment = out_lanes[0]
				# On a 2-lane arterial, restrict sharp right turns to outer lane (1) and sharp left turns to inner lane (0) if other outgoing options exist
				next_ids.append(c0.id)
			else:
				var c0: RoadGraph.LaneSegment = out_lanes[0]
				var out_dir := Vector2.ZERO
				if c0.points.size() >= 2:
					out_dir = Vector2(c0.points[1].x - c0.points[0].x, c0.points[1].z - c0.points[0].z).normalized()
				var cross_z := in_dir.x * out_dir.y - in_dir.y * out_dir.x # >0 = right turn in XZ (since +Z is south, +X is east), <0 = left turn
				var dot_v := in_dir.dot(out_dir)
				var chosen_idx := lane.lane_index
				if dot_v < 0.45:
					# Right turn prefers outer lane (1); left turn prefers inner lane (0)
					chosen_idx = 1 if cross_z > 0.0 else 0
				var matched: RoadGraph.LaneSegment = out_lanes[0]
				for ol_var in out_lanes:
					var ol: RoadGraph.LaneSegment = ol_var
					if ol.lane_index == chosen_idx:
						matched = ol
						break
				next_ids.append(matched.id)

		# Dead-end U-turn fallback if no non-same-edge outgoing lane exists
		if next_ids.is_empty():
			for cand_var in candidates:
				var cand: RoadGraph.LaneSegment = cand_var
				if cand.id != lane.id and cand.direction != lane.direction:
					if cand.lane_index == lane.lane_index or cand.lane_count == 1:
						next_ids.append(cand.id)
						break
			if next_ids.is_empty():
				for cand_var in candidates:
					var cand: RoadGraph.LaneSegment = cand_var
					if cand.id != lane.id:
						next_ids.append(cand.id)
						break
		lane.next_lane_ids = next_ids


static func _assign_street_names(graph: RoadGraph, terrain: TerrainData, rng: RandomNumberGenerator) -> void:
	var ew_shift := rng.randi_range(0, EW_STREET_NAMES.size() - 1)
	var ns_shift := rng.randi_range(0, NS_AVENUE_NAMES.size() - 1)
	for e in graph.edges:
		var pa := graph.nodes[e.node_a].pos
		var pb := graph.nodes[e.node_b].pos
		var delta := pb - pa
		var mid := (pa + pb) * 0.5
		if e.road_class == "alley":
			e.street_name = "MARKET ALLEY"
			continue
		if terrain != null and terrain.beach_enabled and absf(delta.x) >= absf(delta.y) and absf(mid.y - terrain.coast_road_z) < 6.0:
			e.street_name = "OCEANFRONT BLVD"
			continue
		if absf(delta.x) >= absf(delta.y):
			var band_z := int(round(mid.y / 82.0)) + ew_shift
			e.street_name = EW_STREET_NAMES[posmod(band_z, EW_STREET_NAMES.size())]
		else:
			var band_x := int(round(mid.x / 82.0)) + ns_shift
			e.street_name = NS_AVENUE_NAMES[posmod(band_x, NS_AVENUE_NAMES.size())]
