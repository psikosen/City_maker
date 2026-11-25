class_name RoadBuilder
extends RefCounted

## Builds road asphalt, intersections, raised sidewalks, curb ramps, crosswalks,
## lane markings, bridges, and matched primitive/convex colliders from RoadGraph.

static func build_roads(road_graph: RoadGraph, terrain: TerrainData, mats: MaterialLibrary, chunk_size: float = 128.0) -> Node3D:
	var root := Node3D.new()
	root.name = "RoadNetwork"

	var eff_chunk_size := maxf(16.0, chunk_size)
	var world_size := terrain.size_m if terrain != null else 2304.0
	var chunks_per_axis := maxi(1, int(round(world_size / eff_chunk_size)))
	var chunk_buckets: Dictionary = {} # Vector2i -> Dictionary[String, SurfaceTool]

	var collision_body := StaticBody3D.new()
	collision_body.name = "RoadCollision"
	root.add_child(collision_body)

	# 1. Build every RoadEdge (asphalt, sidewalks, curb ramps, ADA pads, markings, bridges, storm drains, manholes, colliders).
	for e in road_graph.edges:
		_build_edge(e, road_graph, terrain, chunk_buckets, eff_chunk_size, chunks_per_axis, collision_body)

	# 2. Build every RoadNode (junction asphalt polygon + sidewalk corner aprons + colliders).
	for n in road_graph.nodes:
		_build_junction(n, road_graph, chunk_buckets, eff_chunk_size, chunks_per_axis, collision_body)

	# 3. Commit per-chunk meshes under RoadChunk_x_z so off-screen road chunks frustum-cull cleanly.
	var sorted_chunks: Array = chunk_buckets.keys()
	sorted_chunks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	for cc_var in sorted_chunks:
		var cc: Vector2i = cc_var
		var layer_map: Dictionary = chunk_buckets[cc]
		var chunk_node := Node3D.new()
		chunk_node.name = "RoadChunk_%d_%d" % [cc.x, cc.y]
		root.add_child(chunk_node)

		if layer_map.has("asphalt"):
			_commit_surface(layer_map["asphalt"], "AsphaltMesh_%d_%d" % [cc.x, cc.y], mats.asphalt_mat, chunk_node, false, true, 0.0)
		if layer_map.has("sidewalk"):
			_commit_surface(layer_map["sidewalk"], "SidewalkMesh_%d_%d" % [cc.x, cc.y], mats.sidewalk_mat, chunk_node, false, true, 0.0)
		if layer_map.has("marking_white"):
			_commit_surface(layer_map["marking_white"], "MarkingsWhiteMesh_%d_%d" % [cc.x, cc.y], mats.marking_white_mat, chunk_node, false, false, 0.0)
		if layer_map.has("marking_yellow"):
			_commit_surface(layer_map["marking_yellow"], "MarkingsYellowMesh_%d_%d" % [cc.x, cc.y], mats.marking_yellow_mat, chunk_node, false, false, 0.0)
		if layer_map.has("bridge"):
			_commit_surface(layer_map["bridge"], "BridgeConcreteMesh_%d_%d" % [cc.x, cc.y], mats.bridge_concrete_mat, chunk_node, true, true, 0.0)
		if layer_map.has("drain"):
			_commit_surface(layer_map["drain"], "StormDrainsMesh_%d_%d" % [cc.x, cc.y], mats.dark_metal_mat, chunk_node, false, false, 150.0)
		if layer_map.has("ada"):
			_commit_surface(layer_map["ada"], "AdaTactilePadsMesh_%d_%d" % [cc.x, cc.y], mats.ada_tactile_mat, chunk_node, false, false, 150.0)

	return root


static func _get_chunk_st(chunk_buckets: Dictionary, pt_xz: Vector2, layer_key: String, chunk_size: float, chunks_per_axis: int) -> SurfaceTool:
	var cc := Vector2i(
		clampi(int(floor(pt_xz.x / chunk_size)), 0, chunks_per_axis - 1),
		clampi(int(floor(pt_xz.y / chunk_size)), 0, chunks_per_axis - 1)
	)
	var layer_map: Dictionary
	if chunk_buckets.has(cc):
		layer_map = chunk_buckets[cc]
	else:
		layer_map = {}
		chunk_buckets[cc] = layer_map
	if layer_map.has(layer_key):
		return layer_map[layer_key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	layer_map[layer_key] = st
	return st


static func _commit_surface(
	st: SurfaceTool,
	node_name: String,
	mat: Material,
	parent: Node3D,
	cast_shadows: bool = false,
	decal_layer_2: bool = false,
	vis_end: float = 0.0
) -> void:
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	if not cast_shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if decal_layer_2:
		mi.set_layer_mask_value(2, true)
	if vis_end > 0.0:
		mi.visibility_range_end = vis_end
		mi.visibility_range_end_margin = 18.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mi)


static func _build_edge(
	e: RoadGraph.RoadEdge,
	road_graph: RoadGraph,
	terrain: TerrainData,
	chunk_buckets: Dictionary,
	chunk_size: float,
	chunks_per_axis: int,
	col_body: StaticBody3D
) -> void:
	var pa := road_graph.nodes[e.node_a].pos
	var pb := road_graph.nodes[e.node_b].pos
	var total_len := pa.distance_to(pb)
	if total_len < 1.0:
		return

	var t_start := clampf(e.trim_a / total_len, 0.0, 0.42)
	var t_end := clampf(1.0 - e.trim_b / total_len, 0.58, 1.0)
	if t_end <= t_start + 0.02:
		return

	var trimmed_len := (t_end - t_start) * total_len
	var seg_count := maxi(6, int(ceil(trimmed_len / 1.6)))
	var half_r := e.road_width * 0.5
	var sw_w := e.sidewalk_width
	var dir2 := (pb - pa).normalized()
	var side2 := Vector2(-dir2.y, dir2.x)
	var yaw := atan2(dir2.x, dir2.y)

	var prev_p := road_graph.sample_edge_point_3d(e, t_start)
	var ramp_len := 1.45

	for si in range(seg_count):
		var u0 := float(si) / float(seg_count)
		var u1 := float(si + 1) / float(seg_count)
		var t0 := lerpf(t_start, t_end, u0)
		var t1 := lerpf(t_start, t_end, u1)
		var p0 := prev_p
		var p1 := road_graph.sample_edge_point_3d(e, t1)
		prev_p = p1

		var seg_mid2 := Vector2((p0.x + p1.x) * 0.5, (p0.z + p1.z) * 0.5)
		var asphalt_st := _get_chunk_st(chunk_buckets, seg_mid2, "asphalt", chunk_size, chunks_per_axis)

		var t_mid := (t0 + t1) * 0.5
		var in_bridge := e.is_bridge and t_mid >= e.bridge_start_t and t_mid <= e.bridge_end_t

		# Asphalt top surface
		var a_p := Vector3(p0.x + side2.x * half_r, p0.y, p0.z + side2.y * half_r)
		var a_m := Vector3(p0.x - side2.x * half_r, p0.y, p0.z - side2.y * half_r)
		var b_p := Vector3(p1.x + side2.x * half_r, p1.y, p1.z + side2.y * half_r)
		var b_m := Vector3(p1.x - side2.x * half_r, p1.y, p1.z - side2.y * half_r)
		_emit_top_quad(asphalt_st, a_p, a_m, b_p, b_m)

		# Matched asphalt collision slab
		_add_segment_box_collider(col_body, p0, p1, yaw, e.road_width, 0.24, 0.0)

		# Center & multi-lane markings
		if e.road_class == "arterial":
			var marking_yellow_st := _get_chunk_st(chunk_buckets, seg_mid2, "marking_yellow", chunk_size, chunks_per_axis)
			var ym := 0.08
			var off := 0.14
			for s_off in [-off, off]:
				var c0 := Vector3(p0.x + side2.x * s_off, p0.y + 0.015, p0.z + side2.y * s_off)
				var c1 := Vector3(p1.x + side2.x * s_off, p1.y + 0.015, p1.z + side2.y * s_off)
				_emit_strip_quad(marking_yellow_st, c0, c1, side2, ym)
			if half_r >= 5.2 and si % 2 == 0:
				var marking_white_st := _get_chunk_st(chunk_buckets, seg_mid2, "marking_white", chunk_size, chunks_per_axis)
				var lane_off := half_r * 0.50
				for s_sign: float in [-1.0, 1.0]:
					var l_off: float = s_sign * lane_off
					var l0 := Vector3(p0.x + side2.x * l_off, p0.y + 0.015, p0.z + side2.y * l_off).lerp(Vector3(p1.x + side2.x * l_off, p1.y + 0.015, p1.z + side2.y * l_off), 0.15)
					var l1 := Vector3(p0.x + side2.x * l_off, p0.y + 0.015, p0.z + side2.y * l_off).lerp(Vector3(p1.x + side2.x * l_off, p1.y + 0.015, p1.z + side2.y * l_off), 0.85)
					_emit_strip_quad(marking_white_st, l0, l1, side2, 0.09)
		elif e.road_class == "collector" and si % 2 == 0:
			var marking_white_st := _get_chunk_st(chunk_buckets, seg_mid2, "marking_white", chunk_size, chunks_per_axis)
			var c0 := Vector3(p0.x, p0.y + 0.015, p0.z).lerp(Vector3(p1.x, p1.y + 0.015, p1.z), 0.15)
			var c1 := Vector3(p0.x, p0.y + 0.015, p0.z).lerp(Vector3(p1.x, p1.y + 0.015, p1.z), 0.85)
			_emit_strip_quad(marking_white_st, c0, c1, side2, 0.09)

		# Sidewalks + curbs + gentle crosswalk curb ramps
		if sw_w > 0.2:
			var sidewalk_st := _get_chunk_st(chunk_buckets, seg_mid2, "sidewalk", chunk_size, chunks_per_axis)
			var d0 := u0 * trimmed_len
			var d1 := u1 * trimmed_len
			var h0 := _curb_height_at_dist(d0, trimmed_len, ramp_len)
			var h1 := _curb_height_at_dist(d1, trimmed_len, ramp_len)

			var side_signs: Array[float] = [1.0, -1.0]
			var bevel_w := minf(0.055, sw_w * 0.12)
			var curb_drop0 := lerpf(0.0, 0.024, clampf((h0 - 0.04) / 0.11, 0.0, 1.0))
			var curb_drop1 := lerpf(0.0, 0.024, clampf((h1 - 0.04) / 0.11, 0.0, 1.0))
			for s_sign in side_signs:
				var inner_off: float = s_sign * half_r
				var lip_off: float = s_sign * (half_r + bevel_w)
				var outer_off: float = s_sign * (half_r + sw_w)

				var sw0_in := Vector3(p0.x + side2.x * inner_off, p0.y + h0 - curb_drop0, p0.z + side2.y * inner_off)
				var sw0_lip := Vector3(p0.x + side2.x * lip_off, p0.y + h0, p0.z + side2.y * lip_off)
				var sw0_out := Vector3(p0.x + side2.x * outer_off, p0.y + h0, p0.z + side2.y * outer_off)
				var sw1_in := Vector3(p1.x + side2.x * inner_off, p1.y + h1 - curb_drop1, p1.z + side2.y * inner_off)
				var sw1_lip := Vector3(p1.x + side2.x * lip_off, p1.y + h1, p1.z + side2.y * lip_off)
				var sw1_out := Vector3(p1.x + side2.x * outer_off, p1.y + h1, p1.z + side2.y * outer_off)

				if s_sign > 0.0:
					_emit_top_quad(sidewalk_st, sw0_out, sw0_lip, sw1_out, sw1_lip)
					_emit_top_quad(sidewalk_st, sw0_lip, sw0_in, sw1_lip, sw1_in)
					# Curb vertical face facing asphalt (-side2)
					_emit_side_quad(sidewalk_st, sw0_in, sw1_in, p0.y - 0.12, p1.y - 0.12)
					# Outer skirt facing outward (+side2)
					_emit_side_quad(sidewalk_st, sw1_out, sw0_out, p1.y - 0.45, p0.y - 0.45)
				else:
					_emit_top_quad(sidewalk_st, sw0_lip, sw0_out, sw1_lip, sw1_out)
					_emit_top_quad(sidewalk_st, sw0_in, sw0_lip, sw1_in, sw1_lip)
					# Curb vertical face facing asphalt (+side2)
					_emit_side_quad(sidewalk_st, sw1_in, sw0_in, p1.y - 0.12, p0.y - 0.12)
					# Outer skirt facing outward (-side2)
					_emit_side_quad(sidewalk_st, sw0_out, sw1_out, p0.y - 0.45, p1.y - 0.45)

				var sw_mid_off: float = (inner_off + outer_off) * 0.5
				var sp0 := Vector3(p0.x + side2.x * sw_mid_off, p0.y + h0, p0.z + side2.y * sw_mid_off)
				var sp1 := Vector3(p1.x + side2.x * sw_mid_off, p1.y + h1, p1.z + side2.y * sw_mid_off)
				_add_segment_box_collider(col_body, sp0, sp1, yaw, sw_w, 0.34, 0.0)

		# Bridge deck & safety parapets over creek
		if in_bridge:
			var bridge_st := _get_chunk_st(chunk_buckets, seg_mid2, "bridge", chunk_size, chunks_per_axis)
			var deck_w := half_r + sw_w + 0.45
			var b0_p := Vector3(p0.x + side2.x * deck_w, p0.y - 0.08, p0.z + side2.y * deck_w)
			var b0_m := Vector3(p0.x - side2.x * deck_w, p0.y - 0.08, p0.z - side2.y * deck_w)
			var b1_p := Vector3(p1.x + side2.x * deck_w, p1.y - 0.08, p1.z + side2.y * deck_w)
			var b1_m := Vector3(p1.x - side2.x * deck_w, p1.y - 0.08, p1.z - side2.y * deck_w)
			_emit_side_quad(bridge_st, b1_p, b0_p, p1.y - 0.78, p0.y - 0.78)
			_emit_side_quad(bridge_st, b0_m, b1_m, p0.y - 0.78, p1.y - 0.78)
			# Bottom underside of bridge deck
			_emit_top_quad(bridge_st, b0_m + Vector3(0, -0.7, 0), b0_p + Vector3(0, -0.7, 0), b1_m + Vector3(0, -0.7, 0), b1_p + Vector3(0, -0.7, 0))

			# Guardrail parapets along outer edge of bridge sidewalks
			var rail_signs: Array[float] = [1.0, -1.0]
			for s_sign in rail_signs:
				var rail_off: float = s_sign * (half_r + sw_w + 0.16)
				var r0 := Vector3(p0.x + side2.x * rail_off, p0.y + 1.05, p0.z + side2.y * rail_off)
				var r1 := Vector3(p1.x + side2.x * rail_off, p1.y + 1.05, p1.z + side2.y * rail_off)
				_emit_box_beam(bridge_st, r0 - Vector3(0, 0.5, 0), r1 - Vector3(0, 0.5, 0), side2, 0.28, 1.05)
				_add_segment_box_collider(col_body, r0, r1, yaw, 0.30, 1.15, 0.0)

	# River bridge piers (every ~16m) + cross-caps + arterial architectural portal towers.
	if e.is_bridge:
		var t_lo := e.bridge_start_t + 0.03
		var t_hi := e.bridge_end_t - 0.03
		var span_m := (e.bridge_end_t - e.bridge_start_t) * total_len
		var n_piers := clampi(int(round(span_m / 16.0)) + 1, 3, 6) if t_hi > t_lo else 1
		var pier_lat := half_r + 0.6
		for pi in range(n_piers):
			var pt_t := lerpf(t_lo, t_hi, float(pi) / float(n_piers - 1)) if n_piers > 1 else (e.bridge_start_t + e.bridge_end_t) * 0.5
			var deck_p := road_graph.sample_edge_point_3d(e, pt_t)
			var bed_y := terrain.sample_height(deck_p.x, deck_p.z) - 1.2
			var pier_h := maxf(1.5, deck_p.y - 0.65 - bed_y)
			for s_sign: float in [-1.0, 1.0]:
				var pier_pos: Vector2 = Vector2(deck_p.x, deck_p.z) + side2 * (s_sign * pier_lat)
				var bridge_pier_st := _get_chunk_st(chunk_buckets, pier_pos, "bridge", chunk_size, chunks_per_axis)
				_emit_prism_box(bridge_pier_st, Vector3(pier_pos.x, bed_y + pier_h * 0.5, pier_pos.y), yaw, Vector3(1.1, pier_h, 1.6))
			var cap_st := _get_chunk_st(chunk_buckets, Vector2(deck_p.x, deck_p.z), "bridge", chunk_size, chunks_per_axis)
			var cap_l := Vector3(deck_p.x - side2.x * pier_lat, deck_p.y - 1.02, deck_p.z - side2.y * pier_lat)
			var cap_r := Vector3(deck_p.x + side2.x * pier_lat, deck_p.y - 1.02, deck_p.z + side2.y * pier_lat)
			_emit_box_beam(cap_st, cap_l, cap_r, dir2, 1.35, 0.58)

		if e.road_class == "arterial" and span_m >= 36.0:
			var pylon_lat := half_r + sw_w + 0.42
			for p_frac: float in [0.16, 0.84]:
				var pt_p := lerpf(e.bridge_start_t, e.bridge_end_t, p_frac)
				var dp := road_graph.sample_edge_point_3d(e, pt_p)
				var portal_st := _get_chunk_st(chunk_buckets, Vector2(dp.x, dp.z), "bridge", chunk_size, chunks_per_axis)
				var pylon_h := 7.6
				var pylon_cy := dp.y - 0.6 + pylon_h * 0.5
				for s_sign: float in [-1.0, 1.0]:
					var pp := Vector2(dp.x, dp.z) + side2 * (s_sign * pylon_lat)
					_emit_prism_box(portal_st, Vector3(pp.x, pylon_cy, pp.y), yaw, Vector3(0.85, pylon_h, 1.20))
				var arch_l := Vector3(dp.x - side2.x * (pylon_lat + 0.42), dp.y + 6.35, dp.z - side2.y * (pylon_lat + 0.42))
				var arch_r := Vector3(dp.x + side2.x * (pylon_lat + 0.42), dp.y + 6.35, dp.z + side2.y * (pylon_lat + 0.42))
				_emit_box_beam(portal_st, arch_l, arch_r, dir2, 1.05, 1.15)

	# Crosswalk zebra stripes & inbound stop bars at both road entry ends (when not an alley).
	if e.road_class != "alley" and trimmed_len > 10.0:
		for end_pair in [[t_start + 1.2 / total_len, -1.0, t_start + 3.0 / total_len], [t_end - 1.2 / total_len, 1.0, t_end - 3.0 / total_len]]:
			var end_t := float(end_pair[0])
			var lane_sign := float(end_pair[1])
			var bar_t := float(end_pair[2])
			var cp := road_graph.sample_edge_point_3d(e, clampf(end_t, t_start, t_end))
			var cw_st := _get_chunk_st(chunk_buckets, Vector2(cp.x, cp.z), "marking_white", chunk_size, chunks_per_axis)
			var stripe_w := 0.45
			var stripe_step := 1.05
			var bar_len := 2.0
			var x_off := -half_r + 0.75
			while x_off <= half_r - 0.75:
				var c_start := Vector3(cp.x + side2.x * x_off - dir2.x * (bar_len * 0.5), cp.y + 0.018, cp.z + side2.y * x_off - dir2.y * (bar_len * 0.5))
				var c_end := Vector3(cp.x + side2.x * x_off + dir2.x * (bar_len * 0.5), cp.y + 0.018, cp.z + side2.y * x_off + dir2.y * (bar_len * 0.5))
				_emit_strip_quad(cw_st, c_start, c_end, side2, stripe_w)
				x_off += stripe_step

			if trimmed_len > 14.0 and half_r >= 3.0:
				var sp := road_graph.sample_edge_point_3d(e, clampf(bar_t, t_start, t_end))
				var sb_st := _get_chunk_st(chunk_buckets, Vector2(sp.x, sp.z), "marking_white", chunk_size, chunks_per_axis)
				var sb_c := lane_sign * (half_r * 0.50)
				var sb_w := maxf(1.2, half_r - 0.85)
				var sb0 := Vector3(sp.x + side2.x * sb_c - dir2.x * 0.21, sp.y + 0.019, sp.z + side2.y * sb_c - dir2.y * 0.21)
				var sb1 := Vector3(sp.x + side2.x * sb_c + dir2.x * 0.21, sp.y + 0.019, sp.z + side2.y * sb_c + dir2.y * 0.21)
				_emit_strip_quad(sb_st, sb0, sb1, side2, sb_w)

	# Curb storm drain grates, ADA truncated-dome ramp pads, and cast-iron road manhole covers
	if e.road_class != "alley" and sw_w >= 1.8 and not e.is_bridge and trimmed_len > 14.0:
		for end_u: float in [0.65, trimmed_len - 0.65]:
			var u0 := maxf(0.1, end_u - 0.36)
			var u1 := minf(trimmed_len - 0.1, end_u + 0.36)
			var rt0 := lerpf(t_start, t_end, u0 / trimmed_len)
			var rt1 := lerpf(t_start, t_end, u1 / trimmed_len)
			var rp0 := road_graph.sample_edge_point_3d(e, rt0)
			var rp1 := road_graph.sample_edge_point_3d(e, rt1)
			var ada_st := _get_chunk_st(chunk_buckets, Vector2((rp0.x + rp1.x) * 0.5, (rp0.z + rp1.z) * 0.5), "ada", chunk_size, chunks_per_axis)
			var h0_ada := _curb_height_at_dist(u0, trimmed_len, ramp_len) + 0.014
			var h1_ada := _curb_height_at_dist(u1, trimmed_len, ramp_len) + 0.014
			for s_sign: float in [-1.0, 1.0]:
				var pad_lat: float = s_sign * (half_r + minf(sw_w * 0.44, 0.72))
				var p0_ada := Vector3(rp0.x + side2.x * pad_lat, rp0.y + h0_ada, rp0.z + side2.y * pad_lat)
				var p1_ada := Vector3(rp1.x + side2.x * pad_lat, rp1.y + h1_ada, rp1.z + side2.y * pad_lat)
				_emit_strip_quad(ada_st, p0_ada, p1_ada, side2, 0.78)

	if (e.road_class == "arterial" or e.road_class == "collector") and not e.is_bridge and trimmed_len > 18.0:
		var drain_d := 8.0
		while drain_d <= trimmed_len - 8.0:
			var dt := lerpf(t_start, t_end, drain_d / trimmed_len)
			var dp := road_graph.sample_edge_point_3d(e, dt)
			var drain_st := _get_chunk_st(chunk_buckets, Vector2(dp.x, dp.z), "drain", chunk_size, chunks_per_axis)
			for s_sign: float in [-1.0, 1.0]:
				var g_lat: float = s_sign * (half_r - 0.42)
				for slot_i: int in [-1, 0, 1]:
					var slat_off: float = g_lat + float(slot_i) * 0.13
					var g0 := Vector3(dp.x + side2.x * slat_off - dir2.x * 0.48, dp.y + 0.016, dp.z + side2.y * slat_off - dir2.y * 0.48)
					var g1 := Vector3(dp.x + side2.x * slat_off + dir2.x * 0.48, dp.y + 0.016, dp.z + side2.y * slat_off + dir2.y * 0.48)
					_emit_strip_quad(drain_st, g0, g1, side2, 0.07)
			# Cast-iron manhole hatch in travel lane every storm drain station
			var mh_lat := half_r * 0.42 * (1.0 if int(round(drain_d)) % 2 == 0 else -1.0)
			var m0 := Vector3(dp.x + side2.x * mh_lat - dir2.x * 0.36, dp.y + 0.014, dp.z + side2.y * mh_lat - dir2.y * 0.36)
			var m1 := Vector3(dp.x + side2.x * mh_lat + dir2.x * 0.36, dp.y + 0.014, dp.z + side2.y * mh_lat + dir2.y * 0.36)
			_emit_strip_quad(drain_st, m0, m1, side2, 0.72)
			drain_d += 34.0


static func _curb_height_at_dist(d: float, total_len: float, ramp_len: float) -> float:
	var h := 0.15
	if d < ramp_len:
		var u := clampf(d / ramp_len, 0.0, 1.0)
		h = minf(h, lerpf(0.04, 0.15, u * u * (3.0 - 2.0 * u)))
	if total_len - d < ramp_len:
		var u := clampf((total_len - d) / ramp_len, 0.0, 1.0)
		h = minf(h, lerpf(0.04, 0.15, u * u * (3.0 - 2.0 * u)))
	return h


static func _build_junction(
	node: RoadGraph.RoadNode,
	road_graph: RoadGraph,
	chunk_buckets: Dictionary,
	chunk_size: float,
	chunks_per_axis: int,
	col_body: StaticBody3D
) -> void:
	if node.junction_polygon.size() < 3:
		return

	var asphalt_st := _get_chunk_st(chunk_buckets, node.pos, "asphalt", chunk_size, chunks_per_axis)
	var sidewalk_st := _get_chunk_st(chunk_buckets, node.pos, "sidewalk", chunk_size, chunks_per_axis)

	var y := node.elevation
	_emit_triangulated_poly_top(asphalt_st, node.junction_polygon, y)
	_add_triangulated_slab_collider(col_body, node.junction_polygon, y, 0.24)

	# Build corner sidewalk aprons with smooth 6-segment rounded intersection curb fillets.
	var k := node.incident_edge_ids.size()
	if k < 2:
		return

	var items: Array[Dictionary] = []
	for eid in node.incident_edge_ids:
		var e := road_graph.edges[eid]
		var other := road_graph.get_other_node(e, node.id)
		var dir := (road_graph.nodes[other].pos - node.pos).normalized()
		var trim := e.trim_a if e.node_a == node.id else e.trim_b
		items.append({
			"e": e,
			"dir": dir,
			"left": Vector2(-dir.y, dir.x),
			"ang": atan2(dir.y, dir.x),
			"trim": trim,
		})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["ang"]) < float(b["ang"])
	)

	for i in range(k):
		var a: Dictionary = items[i]
		var b: Dictionary = items[(i + 1) % k]
		var ea: RoadGraph.RoadEdge = a["e"]
		var eb: RoadGraph.RoadEdge = b["e"]
		if ea.sidewalk_width <= 0.1 and eb.sidewalk_width <= 0.1:
			continue

		var ua: Vector2 = a["dir"]
		var ub: Vector2 = b["dir"]
		var la: Vector2 = a["left"]
		var lb: Vector2 = b["left"]
		var hwa := ea.road_width * 0.5
		var hwb := eb.road_width * 0.5
		var swa := ea.sidewalk_width
		var swb := eb.sidewalk_width

		var p_a := node.pos + ua * float(a["trim"])
		var p_b := node.pos + ub * float(b["trim"])

		var a_in := p_a + la * hwa
		var a_out := p_a + la * (hwa + swa)
		var b_in := p_b - lb * hwb
		var b_out := p_b - lb * (hwb + swb)

		var fillet := RoadGraph.compute_curb_fillet_pts(a_in, ua, b_in, ub, 6)
		var corner_poly := PackedVector2Array([a_in, a_out])
		# Compute intersection of outer sidewalk rays if non-parallel.
		var det := ua.x * (-ub.y) - ua.y * (-ub.x)
		if absf(det) > 0.18:
			var rhs := b_out - a_out
			var s := (rhs.x * (-ub.y) - rhs.y * (-ub.x)) / det
			var outer_inter := a_out + ua * clampf(s, -22.0, 4.0)
			if outer_inter.distance_to(a_out) > 0.3 and outer_inter.distance_to(b_out) > 0.3:
				corner_poly.append(outer_inter)
		corner_poly.append(b_out)
		for fi in range(fillet.size() - 1, 0, -1):
			corner_poly.append(fillet[fi])

		if absf(ParcelData.signed_area(corner_poly)) > 0.25:
			_emit_triangulated_poly_top(sidewalk_st, corner_poly, y + 0.04)
			# Curved 6-segment vertical curb face facing into intersection road
			for fi in range(fillet.size() - 1):
				var f0 := fillet[fi]
				var f1 := fillet[fi + 1]
				_emit_side_quad(sidewalk_st, Vector3(f1.x, y + 0.04, f1.y), Vector3(f0.x, y + 0.04, f0.y), y - 0.15, y - 0.15)
			_add_triangulated_slab_collider(col_body, corner_poly, y + 0.04, 0.26)


static func _add_segment_box_collider(col_body: StaticBody3D, p0: Vector3, p1: Vector3, yaw: float, width: float, thickness: float, y_offset: float) -> void:
	var diff := p1 - p0
	var horiz_len := Vector2(diff.x, diff.z).length()
	var seg_len := diff.length()
	if seg_len < 0.05:
		return
	var pitch := atan2(diff.y, maxf(0.001, horiz_len))
	var mid := (p0 + p1) * 0.5
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, thickness, seg_len + 0.12)
	cs.shape = box
	# Construct basis: rotate yaw around Y, then tilt pitch around local X (matching +Z tangent going up by +diff.y -> pitch = -atan2(dy, dz)).
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch)
	var down_offset := basis.y * (-thickness * 0.5 + y_offset)
	cs.transform = Transform3D(basis, mid + down_offset)
	col_body.add_child(cs)


static func _add_polygon_slab_collider(col_body: StaticBody3D, poly: PackedVector2Array, top_y: float, thickness: float) -> void:
	if poly.size() < 3:
		return
	var pts := PackedVector3Array()
	for p in poly:
		pts.append(Vector3(p.x, top_y, p.y))
		pts.append(Vector3(p.x, top_y - thickness, p.y))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = shape
	col_body.add_child(cs)


static func _emit_top_quad(st: SurfaceTool, a_plus: Vector3, a_minus: Vector3, b_plus: Vector3, b_minus: Vector3) -> void:
	var n := (a_minus - a_plus).cross(b_plus - a_plus)
	# Godot CW top-face normal check: (b_plus - a_plus).cross(a_minus - a_plus)
	n = (b_plus - a_plus).cross(a_minus - a_plus).normalized()
	if n.y < 0.0:
		n = -n
	for v in [a_plus, a_minus, b_plus, a_minus, b_minus, b_plus]:
		st.set_normal(n)
		st.add_vertex(v)


static func _emit_strip_quad(st: SurfaceTool, p0: Vector3, p1: Vector3, side2: Vector2, half_w: float) -> void:
	var hw := half_w * 0.5
	var a_p := Vector3(p0.x + side2.x * hw, p0.y, p0.z + side2.y * hw)
	var a_m := Vector3(p0.x - side2.x * hw, p0.y, p0.z - side2.y * hw)
	var b_p := Vector3(p1.x + side2.x * hw, p1.y, p1.z + side2.y * hw)
	var b_m := Vector3(p1.x - side2.x * hw, p1.y, p1.z - side2.y * hw)
	_emit_top_quad(st, a_p, a_m, b_p, b_m)


static func _emit_side_quad(st: SurfaceTool, a_top: Vector3, b_top: Vector3, y_bot_a: float, y_bot_b: float) -> void:
	var a_bot := Vector3(a_top.x, y_bot_a, a_top.z)
	var b_bot := Vector3(b_top.x, y_bot_b, b_top.z)
	var n := (b_top - a_top).cross(a_bot - a_top).normalized()
	for v in [a_top, a_bot, b_top, a_bot, b_bot, b_top]:
		st.set_normal(n)
		st.add_vertex(v)


static func _emit_ccw_poly_top(st: SurfaceTool, poly: PackedVector2Array, y: float) -> void:
	var cent := ParcelData.polygon_centroid(poly)
	var vc := Vector3(cent.x, y, cent.y)
	var n := poly.size()
	for i in range(n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var va := Vector3(a.x, y, a.y)
		var vb := Vector3(b.x, y, b.y)
		for v in [vc, va, vb]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)


static func _emit_triangulated_poly_top(st: SurfaceTool, poly: PackedVector2Array, y: float) -> void:
	if poly.size() < 3:
		return
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		_emit_ccw_poly_top(st, ParcelData.ensure_ccw(poly), y)
		return
	for ti in range(0, tris.size(), 3):
		var a2 := poly[tris[ti]]
		var b2 := poly[tris[ti + 1]]
		var c2 := poly[tris[ti + 2]]
		var va := Vector3(a2.x, y, a2.y)
		var vb := Vector3(b2.x, y, b2.y)
		var vc := Vector3(c2.x, y, c2.y)
		var n_test := (vb - va).cross(vc - va)
		var order := [va, vc, vb] if n_test.y > 0.0 else [va, vb, vc]
		for v in order:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)


static func _add_triangulated_slab_collider(col_body: StaticBody3D, poly: PackedVector2Array, top_y: float, thickness: float) -> void:
	if poly.size() < 3:
		return
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		_add_polygon_slab_collider(col_body, poly, top_y, thickness)
		return
	for ti in range(0, tris.size(), 3):
		var a2 := poly[tris[ti]]
		var b2 := poly[tris[ti + 1]]
		var c2 := poly[tris[ti + 2]]
		var area2 := absf((b2.x - a2.x) * (c2.y - a2.y) - (b2.y - a2.y) * (c2.x - a2.x))
		var max_e := maxf(a2.distance_to(b2), maxf(b2.distance_to(c2), c2.distance_to(a2)))
		if max_e < 0.12 or (area2 / max_e) < 0.065:
			continue
		var pts := PackedVector3Array()
		for k in range(3):
			var p := poly[tris[ti + k]]
			pts.append(Vector3(p.x, top_y, p.y))
			pts.append(Vector3(p.x, top_y - thickness, p.y))
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = shape
		col_body.add_child(cs)


static func _emit_box_beam(st: SurfaceTool, p0: Vector3, p1: Vector3, side2: Vector2, width: float, height: float) -> void:
	var hw := width * 0.5
	var hh := height * 0.5
	var a_p := Vector3(p0.x + side2.x * hw, p0.y + hh, p0.z + side2.y * hw)
	var a_m := Vector3(p0.x - side2.x * hw, p0.y + hh, p0.z - side2.y * hw)
	var b_p := Vector3(p1.x + side2.x * hw, p1.y + hh, p1.z + side2.y * hw)
	var b_m := Vector3(p1.x - side2.x * hw, p1.y + hh, p1.z - side2.y * hw)
	_emit_top_quad(st, a_p, a_m, b_p, b_m)
	_emit_side_quad(st, b_p, a_p, p1.y - hh, p0.y - hh)
	_emit_side_quad(st, a_m, b_m, p0.y - hh, p1.y - hh)


static func _emit_prism_box(st: SurfaceTool, center: Vector3, yaw: float, size: Vector3) -> void:
	var right := Vector3(cos(yaw), 0.0, -sin(yaw)) * (size.x * 0.5)
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw)) * (size.z * 0.5)
	var ht := size.y * 0.5
	var c0 := center - right - fwd
	var c1 := center + right - fwd
	var c2 := center + right + fwd
	var c3 := center - right + fwd
	_emit_side_quad(st, Vector3(c0.x, center.y + ht, c0.z), Vector3(c1.x, center.y + ht, c1.z), center.y - ht, center.y - ht)
	_emit_side_quad(st, Vector3(c1.x, center.y + ht, c1.z), Vector3(c2.x, center.y + ht, c2.z), center.y - ht, center.y - ht)
	_emit_side_quad(st, Vector3(c2.x, center.y + ht, c2.z), Vector3(c3.x, center.y + ht, c3.z), center.y - ht, center.y - ht)
	_emit_side_quad(st, Vector3(c3.x, center.y + ht, c3.z), Vector3(c0.x, center.y + ht, c0.z), center.y - ht, center.y - ht)
