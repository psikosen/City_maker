class_name ParkWalkwayBuilder
extends RefCounted

## Materializes terrain-draped flagstone park walkways and paved gazebo plazas
## batched by chunk with chamfered ground-anchored stone curbs (zero Z-fighting or floating).


static func build_walkways(
	walkways: Array,
	terrain: TerrainData,
	config: CityConfig,
	chunk_roots: Dictionary,
	mats: MaterialLibrary
) -> void:
	if walkways.is_empty():
		return

	var chunk_sts: Dictionary = {}
	var edging_sts: Dictionary = {}
	var plaza_trim_sts: Dictionary = {}
	var embank_stone_sts: Dictionary = {}
	var embank_cap_sts: Dictionary = {}
	for w_var in walkways:
		var w: Dictionary = w_var
		var kind := String(w.get("kind", "path"))
		if kind == "plaza":
			var center: Vector2 = w["center"]
			var rad: float = float(w["radius"])
			var cc := _chunk_of(center, config)
			var st := _get_chunk_st(chunk_sts, cc)
			var pst := _get_chunk_st(plaza_trim_sts, cc)
			var is_major := bool(w.get("is_major_plaza", false))
			_emit_plaza_disc(st, pst, center, rad, is_major, terrain)
			if is_major:
				var p_parent: Node3D = chunk_roots.get(cc, null)
				if p_parent != null:
					_build_major_plaza_features(p_parent, w, terrain, mats)
		elif kind == "footbridge":
			var fpts: PackedVector2Array = w["points"]
			var fw := float(w.get("width", 2.6))
			if fpts.size() >= 2:
				var f_cc := _chunk_of(w.get("center", fpts[0]), config)
				var f_parent: Node3D = chunk_roots.get(f_cc, null)
				if f_parent != null:
					_build_footbridge(f_parent, String(w.get("id", "footbridge")), fpts[0], fpts[1], fw, terrain, mats)
		elif kind == "overlook":
			var o_cc := _chunk_of(w.get("center", Vector2.ZERO), config)
			var o_parent: Node3D = chunk_roots.get(o_cc, null)
			if o_parent != null:
				_build_boardwalk_overlook(o_parent, w, terrain, mats)
		elif kind == "embankment_wall":
			var wpts: PackedVector2Array = w.get("points", PackedVector2Array())
			if wpts.size() >= 2:
				var e_cc := _chunk_of(w.get("center", wpts[0]), config)
				var wst := _get_chunk_st(embank_stone_sts, e_cc)
				var cst := _get_chunk_st(embank_cap_sts, e_cc)
				_emit_embankment_wall(wst, cst, wpts[0], wpts[1], float(w.get("width", 0.85)), float(w.get("top_y0", 2.5)), float(w.get("top_y1", 2.5)), terrain)
		else:
			var pts: PackedVector2Array = w["points"]
			var width := float(w.get("width", 2.2))
			if pts.size() < 2:
				continue
			_emit_walkway_ribbon(chunk_sts, edging_sts, pts, width, terrain, config)

	for cc_key in chunk_sts.keys():
		var st: SurfaceTool = chunk_sts[cc_key]
		var mesh := st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "ParkWalkways_%d_%d" % [cc_key.x, cc_key.y]
		mi.mesh = mesh
		mi.material_override = mats.walkway_mat
		mi.set_layer_mask_value(2, true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 360.0
		mi.visibility_range_end_margin = 35.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		var parent: Node3D = chunk_roots.get(cc_key, null)
		if parent != null:
			parent.add_child(mi)

	for cc_key in edging_sts.keys():
		var est: SurfaceTool = edging_sts[cc_key]
		var emesh := est.commit()
		if emesh == null or emesh.get_surface_count() == 0:
			continue
		var emi := MeshInstance3D.new()
		emi.name = "ParkWalkwayEdging_%d_%d" % [cc_key.x, cc_key.y]
		emi.mesh = emesh
		emi.material_override = mats.bridge_concrete_mat
		emi.set_layer_mask_value(2, true)
		emi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		emi.visibility_range_end = 220.0
		emi.visibility_range_end_margin = 24.0
		emi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		var parent_e: Node3D = chunk_roots.get(cc_key, null)
		if parent_e != null:
			parent_e.add_child(emi)

	for cc_key in plaza_trim_sts.keys():
		var pst: SurfaceTool = plaza_trim_sts[cc_key]
		var pmesh := pst.commit()
		if pmesh == null or pmesh.get_surface_count() == 0:
			continue
		var pmi := MeshInstance3D.new()
		pmi.name = "ParkPlazaBorders_%d_%d" % [cc_key.x, cc_key.y]
		pmi.mesh = pmesh
		pmi.material_override = mats.limestone_mat
		pmi.set_layer_mask_value(2, true)
		pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pmi.visibility_range_end = 300.0
		pmi.visibility_range_end_margin = 28.0
		pmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		var parent_p: Node3D = chunk_roots.get(cc_key, null)
		if parent_p != null:
			parent_p.add_child(pmi)

	for cc_key in embank_stone_sts.keys():
		var wst: SurfaceTool = embank_stone_sts[cc_key]
		var wmesh := wst.commit()
		if wmesh != null and wmesh.get_surface_count() > 0:
			var wmi := MeshInstance3D.new()
			wmi.name = "CreekEmbankmentWalls_%d_%d" % [cc_key.x, cc_key.y]
			wmi.mesh = wmesh
			wmi.material_override = mats.limestone_mat
			wmi.set_layer_mask_value(2, true)
			wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			wmi.visibility_range_end = 230.0
			wmi.visibility_range_end_margin = 24.0
			wmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			var parent_w: Node3D = chunk_roots.get(cc_key, null)
			if parent_w != null:
				parent_w.add_child(wmi)

	for cc_key in embank_cap_sts.keys():
		var cst: SurfaceTool = embank_cap_sts[cc_key]
		var cmesh := cst.commit()
		if cmesh != null and cmesh.get_surface_count() > 0:
			var cmi := MeshInstance3D.new()
			cmi.name = "CreekEmbankmentCaps_%d_%d" % [cc_key.x, cc_key.y]
			cmi.mesh = cmesh
			cmi.material_override = mats.bridge_concrete_mat
			cmi.set_layer_mask_value(2, true)
			cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cmi.visibility_range_end = 220.0
			cmi.visibility_range_end_margin = 24.0
			cmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			var parent_c: Node3D = chunk_roots.get(cc_key, null)
			if parent_c != null:
				parent_c.add_child(cmi)


static func _get_chunk_st(chunk_sts: Dictionary, cc: Vector2i) -> SurfaceTool:
	if chunk_sts.has(cc):
		return chunk_sts[cc]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	chunk_sts[cc] = st
	return st


static func _emit_walkway_ribbon(chunk_sts: Dictionary, edging_sts: Dictionary, pts: PackedVector2Array, width: float, terrain: TerrainData, config: CityConfig) -> void:
	var sub_pts := _subdivide_for_terrain(pts, 1.35)
	if sub_pts.size() < 2:
		return
	var hw := width * 0.5
	var rim_w := hw + 0.14
	for i in range(sub_pts.size() - 1):
		var a2 := sub_pts[i]
		var b2 := sub_pts[i + 1]
		var cc := _chunk_of((a2 + b2) * 0.5, config)
		var st := _get_chunk_st(chunk_sts, cc)
		var est := _get_chunk_st(edging_sts, cc)
		var ta := _tangent_at(sub_pts, i)
		var tb := _tangent_at(sub_pts, i + 1)
		var sa := Vector2(-ta.y, ta.x)
		var sb := Vector2(-tb.y, tb.x)

		var ya_l := _h(terrain, a2 - sa * hw) + 0.048
		var ya_r := _h(terrain, a2 + sa * hw) + 0.048
		var yb_l := _h(terrain, b2 - sb * hw) + 0.048
		var yb_r := _h(terrain, b2 + sb * hw) + 0.048

		var a_l := Vector3(a2.x - sa.x * hw, ya_l, a2.y - sa.y * hw)
		var a_r := Vector3(a2.x + sa.x * hw, ya_r, a2.y + sa.y * hw)
		var b_l := Vector3(b2.x - sb.x * hw, yb_l, b2.y - sb.y * hw)
		var b_r := Vector3(b2.x + sb.x * hw, yb_r, b2.y + sb.y * hw)
		_emit_quad_up(st, a_l, a_r, b_l, b_r)

		# Smooth flush stone TrailEdging curb strip along both path shoulders + ground skirt
		var a_top_l := Vector3(a2.x - sa.x * rim_w, ya_l + 0.012, a2.y - sa.y * rim_w)
		var b_top_l := Vector3(b2.x - sb.x * rim_w, yb_l + 0.012, b2.y - sb.y * rim_w)
		var a_top_r := Vector3(a2.x + sa.x * rim_w, ya_r + 0.012, a2.y + sa.y * rim_w)
		var b_top_r := Vector3(b2.x + sb.x * rim_w, yb_r + 0.012, b2.y + sb.y * rim_w)
		var a_l_ed := Vector3(a_l.x, ya_l + 0.012, a_l.z)
		var b_l_ed := Vector3(b_l.x, yb_l + 0.012, b_l.z)
		var a_r_ed := Vector3(a_r.x, ya_r + 0.012, a_r.z)
		var b_r_ed := Vector3(b_r.x, yb_r + 0.012, b_r.z)
		_emit_quad_up(est, a_top_l, a_l_ed, b_top_l, b_l_ed)
		_emit_quad_up(est, a_r_ed, a_top_r, b_r_ed, b_top_r)

		var a_rim_l := Vector3(a2.x - sa.x * (rim_w + 0.04), ya_l - 0.12, a2.y - sa.y * (rim_w + 0.04))
		var b_rim_l := Vector3(b2.x - sb.x * (rim_w + 0.04), yb_l - 0.12, b2.y - sb.y * (rim_w + 0.04))
		var a_rim_r := Vector3(a2.x + sa.x * (rim_w + 0.04), ya_r - 0.12, a2.y + sa.y * (rim_w + 0.04))
		var b_rim_r := Vector3(b2.x + sb.x * (rim_w + 0.04), yb_r - 0.12, b2.y + sb.y * (rim_w + 0.04))
		_emit_quad_auto_n(est, a_rim_l, a_top_l, b_rim_l, b_top_l, Vector3(-sa.x, 0.35, -sa.y).normalized())
		_emit_quad_auto_n(est, a_top_r, a_rim_r, b_top_r, b_rim_r, Vector3(sa.x, 0.35, sa.y).normalized())


static func _emit_plaza_disc(st: SurfaceTool, trim_st: SurfaceTool, center: Vector2, rad: float, is_major: bool, terrain: TerrainData) -> void:
	var segs := 20 if is_major else 14
	var base_y := _h(terrain, center) + 0.055
	var c3 := Vector3(center.x, base_y, center.y)
	var r_mid := rad * 0.48
	for i in range(segs):
		var a0 := float(i) * TAU / float(segs)
		var a1 := float(i + 1) * TAU / float(segs)
		var m0 := Vector2(center.x + cos(a0) * r_mid, center.y + sin(a0) * r_mid)
		var m1 := Vector2(center.x + cos(a1) * r_mid, center.y + sin(a1) * r_mid)
		var p0 := Vector2(center.x + cos(a0) * rad, center.y + sin(a0) * rad)
		var p1 := Vector2(center.x + cos(a1) * rad, center.y + sin(a1) * rad)
		var ym0 := lerpf(base_y, maxf(base_y - 0.14, _h(terrain, m0) + 0.052), 0.55)
		var ym1 := lerpf(base_y, maxf(base_y - 0.14, _h(terrain, m1) + 0.052), 0.55)
		var y0 := maxf(base_y - 0.30, _h(terrain, p0) + 0.048)
		var y1 := maxf(base_y - 0.30, _h(terrain, p1) + 0.048)
		var vm0 := Vector3(m0.x, ym0, m0.y)
		var vm1 := Vector3(m1.x, ym1, m1.y)
		var v0 := Vector3(p0.x, y0, p0.y)
		var v1 := Vector3(p1.x, y1, p1.y)
		_emit_tri_n(st, c3, vm0, vm1, Vector3.UP)
		_emit_quad_up(st, vm0, vm1, v0, v1)

		var r_out := rad + 0.28
		var o0 := Vector3(center.x + cos(a0) * r_out, y0 - 0.55, center.y + sin(a0) * r_out)
		var o1 := Vector3(center.x + cos(a1) * r_out, y1 - 0.55, center.y + sin(a1) * r_out)
		var mid_a := (a0 + a1) * 0.5
		_emit_quad_auto_n(st, v0, v1, o0, o1, Vector3(cos(mid_a), 0.3, sin(mid_a)).normalized())

		if is_major:
			# Decorative outer stone border ring + inner centerpiece apron ring
			var rb_in := rad - 0.68
			var rb_out := rad + 0.06
			var bi0 := Vector2(center.x + cos(a0) * rb_in, center.y + sin(a0) * rb_in)
			var bi1 := Vector2(center.x + cos(a1) * rb_in, center.y + sin(a1) * rb_in)
			var bo0 := Vector2(center.x + cos(a0) * rb_out, center.y + sin(a0) * rb_out)
			var bo1 := Vector2(center.x + cos(a1) * rb_out, center.y + sin(a1) * rb_out)
			var ybi0 := lerpf(ym0, y0, (rb_in - r_mid) / maxf(0.1, rad - r_mid)) + 0.018
			var ybi1 := lerpf(ym1, y1, (rb_in - r_mid) / maxf(0.1, rad - r_mid)) + 0.018
			var ybo0 := y0 + 0.018
			var ybo1 := y1 + 0.018
			_emit_quad_up(trim_st, Vector3(bi0.x, ybi0, bi0.y), Vector3(bi1.x, ybi1, bi1.y), Vector3(bo0.x, ybo0, bo0.y), Vector3(bo1.x, ybo1, bo1.y))
			_emit_quad_auto_n(trim_st, Vector3(bo0.x, ybo0, bo0.y), Vector3(bo1.x, ybo1, bo1.y), Vector3(bo0.x, ybo0 - 0.28, bo0.y), Vector3(bo1.x, ybo1 - 0.28, bo1.y), Vector3(cos(mid_a), 0.2, sin(mid_a)).normalized())

			if rad >= 7.2:
				var ri0 := 3.25
				var ri1 := 3.55
				var ii0 := Vector2(center.x + cos(a0) * ri0, center.y + sin(a0) * ri0)
				var ii1 := Vector2(center.x + cos(a1) * ri0, center.y + sin(a1) * ri0)
				var io0 := Vector2(center.x + cos(a0) * ri1, center.y + sin(a0) * ri1)
				var io1 := Vector2(center.x + cos(a1) * ri1, center.y + sin(a1) * ri1)
				var yii := base_y + 0.016
				_emit_quad_up(trim_st, Vector3(ii0.x, yii, ii0.y), Vector3(ii1.x, yii, ii1.y), Vector3(io0.x, yii, io0.y), Vector3(io1.x, yii, io1.y))


static func _subdivide_for_terrain(pts: PackedVector2Array, step_m: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.is_empty():
		return out
	out.append(pts[0])
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / step_m)))
		for k in range(1, n + 1):
			out.append(a.lerp(b, float(k) / float(n)))
	return out


static func _tangent_at(pts: PackedVector2Array, idx: int) -> Vector2:
	var i0 := maxi(0, idx - 1)
	var i1 := mini(pts.size() - 1, idx + 1)
	var v := pts[i1] - pts[i0]
	if v.length_squared() < 0.0001:
		return Vector2(1.0, 0.0)
	return v.normalized()


static func _h(terrain: TerrainData, pt: Vector2) -> float:
	return terrain.sample_height(pt.x, pt.y) if terrain != null else 0.0


static func _emit_quad_up(st: SurfaceTool, a_l: Vector3, a_r: Vector3, b_l: Vector3, b_r: Vector3) -> void:
	var n := (a_r - a_l).cross(b_l - a_l).normalized()
	if n.y < 0.0:
		_emit_quad_auto_n(st, a_r, a_l, b_r, b_l, Vector3.UP)
	else:
		_emit_quad_auto_n(st, a_l, a_r, b_l, b_r, Vector3.UP)


static func _emit_quad_auto_n(st: SurfaceTool, tl: Vector3, tr: Vector3, bl: Vector3, br: Vector3, desired_n: Vector3) -> void:
	var n_test := (bl - tl).cross(tr - tl)
	var pts := [tl, tr, bl, tr, br, bl] if n_test.dot(desired_n) >= 0.0 else [tl, bl, tr, tr, bl, br]
	var n := desired_n.normalized()
	for p in pts:
		st.set_normal(n)
		st.add_vertex(p)


static func _emit_tri_n(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, desired_n: Vector3) -> void:
	var n_test := (c - a).cross(b - a)
	var pts := [a, b, c] if n_test.dot(desired_n) >= 0.0 else [a, c, b]
	var n := desired_n.normalized()
	for p in pts:
		st.set_normal(n)
		st.add_vertex(p)


static func _chunk_of(pt: Vector2, config: CityConfig) -> Vector2i:
	return Vector2i(
		clampi(int(floor(pt.x / config.chunk_size)), 0, config.get_chunks_per_axis() - 1),
		clampi(int(floor(pt.y / config.chunk_size)), 0, config.get_chunks_per_axis() - 1)
	)


static func _build_footbridge(
	parent: Node3D,
	bridge_id: String,
	p_a: Vector2,
	p_b: Vector2,
	width: float,
	terrain: TerrainData,
	mats: MaterialLibrary
) -> void:
	var root := Node3D.new()
	root.name = "Footbridge_%s" % bridge_id
	parent.add_child(root)

	var body := StaticBody3D.new()
	body.name = "FootbridgeCollision"
	root.add_child(body)

	var y_a := maxf(_h(terrain, p_a) + 0.06, (terrain.water_level if terrain != null else 1.6) + 0.72)
	var y_b := maxf(_h(terrain, p_b) + 0.06, (terrain.water_level if terrain != null else 1.6) + 0.72)
	var w_lvl := terrain.water_level if terrain != null else 1.6
	var y_peak := maxf(maxf(y_a, y_b) + 1.85, w_lvl + 3.05)

	var ab := p_b - p_a
	var span := ab.length()
	if span < 4.0:
		return
	var dir2 := ab / span
	var yaw := atan2(dir2.x, dir2.y)
	var hw := width * 0.5

	var deck_st := SurfaceTool.new()
	deck_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steel_st := SurfaceTool.new()
	steel_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rail_st := SurfaceTool.new()
	rail_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone_st := SurfaceTool.new()
	stone_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var segs := maxi(12, int(ceil(span / 3.2)))
	var pts3: Array[Vector3] = []
	for i in range(segs + 1):
		var t := float(i) / float(segs)
		var pt2 := p_a.lerp(p_b, t)
		var base_y := lerpf(y_a, y_b, t)
		var arch_y := base_y + 4.0 * t * (1.0 - t) * (y_peak - base_y)
		pts3.append(Vector3(pt2.x, arch_y, pt2.y))

	for i in range(segs):
		var q0 := pts3[i]
		var q1 := pts3[i + 1]
		var diff := q1 - q0
		var seg_len := diff.length()
		var horiz := Vector2(diff.x, diff.z).length()
		var pitch := atan2(diff.y, maxf(0.001, horiz))
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch)
		var mid := (q0 + q1) * 0.5

		# Timber walkway deck + matched walkable collision box
		_emit_fb_box(deck_st, mid - b.y * 0.08, b, Vector3(width, 0.16, seg_len + 0.04))
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(width, 0.22, seg_len + 0.06)
		cs.shape = box
		cs.transform = Transform3D(b, mid - b.y * 0.11)
		body.add_child(cs)

		# Steel side arch stringers + handrails + side safety guardrail colliders
		for s_side: float in [-1.0, 1.0]:
			var lat := b.x * (s_side * (hw - 0.05))
			_emit_fb_box(steel_st, mid + lat - b.y * 0.14, b, Vector3(0.09, 0.26, seg_len + 0.05))
			_emit_fb_box(rail_st, mid + lat + Vector3.UP * 0.96, b, Vector3(0.065, 0.065, seg_len + 0.05))
			_emit_fb_box(steel_st, mid + lat + Vector3.UP * 0.52, b, Vector3(0.036, 0.036, seg_len + 0.04))
			var rc := CollisionShape3D.new()
			var rbox := BoxShape3D.new()
			rbox.size = Vector3(0.09, 1.0, seg_len + 0.04)
			rc.shape = rbox
			rc.transform = Transform3D(b, mid + lat + Vector3.UP * 0.50)
			body.add_child(rc)

	# Vertical railing stanchions, river piers & stone abutment piers anchored into both banks
	var pier_i0 := int(round(float(segs) * 0.28))
	var pier_i1 := int(round(float(segs) * 0.72))
	var pier_bot := w_lvl - 3.2
	for i in range(segs + 1):
		var q := pts3[i]
		var b_flat := Basis(Vector3.UP, yaw)
		for s_side: float in [-1.0, 1.0]:
			var lat := b_flat.x * (s_side * (hw - 0.05))
			_emit_fb_box(steel_st, q + lat + Vector3.UP * 0.45, b_flat, Vector3(0.06, 1.02, 0.06))
			if i == 0 or i == segs:
				_emit_fb_box(stone_st, q + lat + Vector3.UP * 0.52, b_flat, Vector3(0.24, 1.18, 0.24))
			elif i == pier_i0 or i == pier_i1:
				var pier_top := q.y - 0.14
				var ph := maxf(0.8, pier_top - pier_bot)
				_emit_fb_box(stone_st, Vector3(q.x, pier_bot + ph * 0.5, q.z) + lat, b_flat, Vector3(0.52, ph, 0.78))

	for end_pt in [pts3[0], pts3[segs]]:
		var b_flat := Basis(Vector3.UP, yaw)
		_emit_fb_box(stone_st, Vector3(end_pt.x, end_pt.y - 0.72, end_pt.z), b_flat, Vector3(width + 0.34, 1.44, 1.10))

	for entry in [
		[deck_st, "FootbridgeDeck", mats.wood_cedar_mat, true],
		[steel_st, "FootbridgeSteel", mats.dark_metal_mat, false],
		[rail_st, "FootbridgeRails", mats.light_metal_mat, false],
		[stone_st, "FootbridgeAbutments", mats.limestone_mat, false],
	]:
		var mesh: ArrayMesh = (entry[0] as SurfaceTool).commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = String(entry[1])
		mi.mesh = mesh
		mi.material_override = entry[2] as Material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(entry[3]) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 360.0
		mi.visibility_range_end_margin = 35.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mi)


static func _emit_fb_box(st: SurfaceTool, center: Vector3, basis: Basis, size: Vector3) -> void:
	var hx := basis.x * (size.x * 0.5)
	var hy := basis.y * (size.y * 0.5)
	var hz := basis.z * (size.z * 0.5)
	var p000 := center - hx - hy - hz
	var p100 := center + hx - hy - hz
	var p010 := center - hx + hy - hz
	var p110 := center + hx + hy - hz
	var p001 := center - hx - hy + hz
	var p101 := center + hx - hy + hz
	var p011 := center - hx + hy + hz
	var p111 := center + hx + hy + hz
	_emit_quad_auto_n(st, p010, p110, p011, p111, basis.y)
	_emit_quad_auto_n(st, p001, p101, p000, p100, -basis.y)
	_emit_quad_auto_n(st, p011, p111, p001, p101, basis.z)
	_emit_quad_auto_n(st, p110, p010, p100, p000, -basis.z)
	_emit_quad_auto_n(st, p111, p110, p101, p100, basis.x)
	_emit_quad_auto_n(st, p010, p011, p000, p001, -basis.x)


static func _emit_fb_cyl(st: SurfaceTool, center: Vector3, top_r: float, bot_r: float, height: float, segs: int = 8) -> void:
	var top_c := center + Vector3(0.0, height * 0.5, 0.0)
	var bot_c := center - Vector3(0.0, height * 0.5, 0.0)
	for i in range(segs):
		var a0 := float(i) * TAU / float(segs)
		var a1 := float(i + 1) * TAU / float(segs)
		var r0 := Vector3(cos(a0), 0.0, sin(a0))
		var r1 := Vector3(cos(a1), 0.0, sin(a1))
		var t0 := top_c + r0 * top_r
		var t1 := top_c + r1 * top_r
		var b0 := bot_c + r0 * bot_r
		var b1 := bot_c + r1 * bot_r
		var mid_a := (a0 + a1) * 0.5
		var n := Vector3(cos(mid_a), 0.0, sin(mid_a)).normalized()
		_emit_quad_auto_n(st, t0, t1, b0, b1, n)
		_emit_tri_n(st, top_c, t1, t0, Vector3.UP)
		_emit_tri_n(st, bot_c, b0, b1, Vector3.DOWN)


static func _add_box_col(body: StaticBody3D, center: Vector3, basis: Basis, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.transform = Transform3D(basis, center)
	body.add_child(cs)


static func _build_boardwalk_overlook(parent: Node3D, w: Dictionary, terrain: TerrainData, mats: MaterialLibrary) -> void:
	var anchor: Vector2 = w["anchor"]
	var tip: Vector2 = w["tip"]
	var ab := tip - anchor
	var span := ab.length()
	if span < 3.5:
		return
	var dir2 := ab / span
	var side2 := Vector2(-dir2.y, dir2.x)
	var yaw := atan2(dir2.x, dir2.y)
	var b_flat := Basis(Vector3.UP, yaw)

	var deck_y := float(w.get("deck_y", _h(terrain, anchor) + 0.08))
	var anchor_y := float(w.get("anchor_y", _h(terrain, anchor))) + 0.05
	var water_lvl := terrain.water_level if terrain != null else 1.6
	var spur_w := float(w.get("spur_width", 2.6))
	var plat_w := float(w.get("width", 4.4))
	var plat_len := minf(3.5, span * 0.52)
	var spur_len := maxf(1.2, span - plat_len)

	var root := Node3D.new()
	root.name = "BoardwalkOverlook_%s" % String(w.get("id", "overlook"))
	parent.add_child(root)

	var body := StaticBody3D.new()
	body.name = "OverlookCollision"
	root.add_child(body)

	var cedar_st := SurfaceTool.new()
	cedar_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steel_st := SurfaceTool.new()
	steel_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Approach boardwalk spur (gentle entry ramp if deck_y sits higher than greenway anchor)
	var ramp_len := minf(2.6, spur_len)
	var dy_ramp := deck_y - anchor_y
	if absf(dy_ramp) > 0.04:
		var r_pitch := atan2(dy_ramp, ramp_len)
		var r_basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -r_pitch)
		var r_mid2 := anchor + dir2 * (ramp_len * 0.5)
		var r_mid := Vector3(r_mid2.x, (anchor_y + deck_y) * 0.5, r_mid2.y)
		var r_hyp := sqrt(ramp_len * ramp_len + dy_ramp * dy_ramp)
		_emit_fb_box(cedar_st, r_mid - r_basis.y * 0.08, r_basis, Vector3(spur_w, 0.16, r_hyp + 0.08))
		_add_box_col(body, r_mid - r_basis.y * 0.10, r_basis, Vector3(spur_w, 0.20, r_hyp + 0.10))
		if spur_len > ramp_len + 0.15:
			var rem_len := spur_len - ramp_len
			var s_mid2 := anchor + dir2 * (ramp_len + rem_len * 0.5)
			var s_mid := Vector3(s_mid2.x, deck_y, s_mid2.y)
			_emit_fb_box(cedar_st, s_mid - Vector3(0.0, 0.08, 0.0), b_flat, Vector3(spur_w, 0.16, rem_len + 0.06))
			_add_box_col(body, s_mid - Vector3(0.0, 0.10, 0.0), b_flat, Vector3(spur_w, 0.20, rem_len + 0.08))
	else:
		var s_mid2 := anchor + dir2 * (spur_len * 0.5)
		var s_mid := Vector3(s_mid2.x, deck_y, s_mid2.y)
		_emit_fb_box(cedar_st, s_mid - Vector3(0.0, 0.08, 0.0), b_flat, Vector3(spur_w, 0.16, spur_len + 0.06))
		_add_box_col(body, s_mid - Vector3(0.0, 0.10, 0.0), b_flat, Vector3(spur_w, 0.20, spur_len + 0.08))

	# 2. Widened cantilevered viewing deck platform over creek edge
	var plat_start2 := anchor + dir2 * spur_len
	var plat_mid2 := anchor + dir2 * (spur_len + plat_len * 0.5)
	var plat_mid := Vector3(plat_mid2.x, deck_y, plat_mid2.y)
	_emit_fb_box(cedar_st, plat_mid - Vector3(0.0, 0.08, 0.0), b_flat, Vector3(plat_w, 0.16, plat_len))
	_add_box_col(body, plat_mid - Vector3(0.0, 0.10, 0.0), b_flat, Vector3(plat_w, 0.20, plat_len))
	# Cantilevered steel I-beam substructure stringers underneath
	for sx: float in [-plat_w * 0.36, 0.0, plat_w * 0.36]:
		_emit_fb_box(steel_st, plat_mid + Vector3(side2.x * sx, -0.25, side2.y * sx) - Vector3(dir2.x * 0.45, 0.0, dir2.y * 0.45), b_flat, Vector3(0.14, 0.18, plat_len + 1.2))
	for sx_s: float in [-spur_w * 0.46, spur_w * 0.46]:
		var sp_c2 := anchor + dir2 * (spur_len * 0.5) + side2 * sx_s
		_emit_fb_box(steel_st, Vector3(sp_c2.x, deck_y - 0.16, sp_c2.y), b_flat, Vector3(0.10, 0.16, spur_len))

	# 3. Heavy timber pilings anchored deep into bank & creek bed (visual only, zero water colliders)
	for piling_pt2: Vector2 in [
		plat_start2 + side2 * (plat_w * 0.42),
		plat_start2 - side2 * (plat_w * 0.42),
		plat_mid2 + side2 * (plat_w * 0.42) + dir2 * (plat_len * 0.32),
		plat_mid2 - side2 * (plat_w * 0.42) + dir2 * (plat_len * 0.32),
		anchor + dir2 * (spur_len * 0.45) + side2 * (spur_w * 0.42),
		anchor + dir2 * (spur_len * 0.45) - side2 * (spur_w * 0.42),
	]:
		var bed_h := minf(_h(terrain, piling_pt2), water_lvl - 1.2) - 0.75
		var top_h := deck_y - 0.12
		var pile_h := maxf(1.2, top_h - bed_h)
		_emit_fb_cyl(cedar_st, Vector3(piling_pt2.x, bed_h + pile_h * 0.5, piling_pt2.y), 0.13, 0.14, pile_h, 8)

	# 4. Perimeter safety railings (leaving greenway entry at anchor completely open)
	var rail_segs: Array[Array] = []
	var sw_h := spur_w * 0.5 - 0.06
	var pw_h := plat_w * 0.5 - 0.06
	for s_side: float in [-1.0, 1.0]:
		rail_segs.append([anchor + side2 * (s_side * sw_h), plat_start2 + side2 * (s_side * sw_h), anchor_y, deck_y])
		rail_segs.append([plat_start2 + side2 * (s_side * sw_h), plat_start2 + side2 * (s_side * pw_h), deck_y, deck_y])
		rail_segs.append([plat_start2 + side2 * (s_side * pw_h), tip + side2 * (s_side * pw_h), deck_y, deck_y])
	rail_segs.append([tip - side2 * pw_h, tip + side2 * pw_h, deck_y, deck_y])

	for rs in rail_segs:
		var r_a: Vector2 = rs[0]
		var r_b: Vector2 = rs[1]
		var y_0 := float(rs[2])
		var y_1 := float(rs[3])
		var r_diff := r_b - r_a
		var r_len := r_diff.length()
		if r_len < 0.25:
			continue
		var r_dir := r_diff / r_len
		var r_yaw := atan2(r_dir.x, r_dir.y)
		var r_pitch := atan2(y_1 - y_0, r_len)
		var r_basis := Basis(Vector3.UP, r_yaw) * Basis(Vector3.RIGHT, -r_pitch)
		var r_hyp := sqrt(r_len * r_len + (y_1 - y_0) * (y_1 - y_0))
		var r_mid2 := (r_a + r_b) * 0.5
		var r_mid_y := (y_0 + y_1) * 0.5
		_emit_fb_box(cedar_st, Vector3(r_mid2.x, r_mid_y + 0.96, r_mid2.y), r_basis, Vector3(0.11, 0.07, r_hyp + 0.06))
		_emit_fb_box(steel_st, Vector3(r_mid2.x, r_mid_y + 0.50, r_mid2.y), r_basis, Vector3(0.04, 0.04, r_hyp + 0.02))
		_add_box_col(body, Vector3(r_mid2.x, r_mid_y + 0.50, r_mid2.y), r_basis, Vector3(0.12, 1.0, r_hyp + 0.06))
		var post_n := maxi(2, int(ceil(r_len / 1.45)) + 1)
		for pi in range(post_n):
			var pt_f := float(pi) / float(post_n - 1)
			var pp2 := r_a.lerp(r_b, pt_f)
			var py := lerpf(y_0, y_1, pt_f)
			_emit_fb_box(steel_st, Vector3(pp2.x, py + 0.48, pp2.y), Basis(Vector3.UP, r_yaw), Vector3(0.08, 0.96, 0.08))

	# 5. Two built-in cedar viewing benches on opposite sides of the platform
	for b_side: float in [-1.0, 1.0]:
		var bc2 := plat_mid2 + side2 * (b_side * (pw_h - 0.36))
		var b_yaw := yaw + (PI * 0.5 if b_side > 0.0 else -PI * 0.5)
		var b_basis := Basis(Vector3.UP, b_yaw)
		_emit_fb_box(cedar_st, Vector3(bc2.x, deck_y + 0.45, bc2.y), b_basis, Vector3(1.65, 0.07, 0.46))
		_emit_fb_box(cedar_st, Vector3(bc2.x, deck_y + 0.72, bc2.y) - b_basis.z * 0.20, b_basis, Vector3(1.65, 0.34, 0.06))
		for leg_x: float in [-0.66, 0.66]:
			_emit_fb_box(steel_st, Vector3(bc2.x, deck_y + 0.22, bc2.y) + b_basis.x * leg_x, b_basis, Vector3(0.07, 0.44, 0.42))
		_add_box_col(body, Vector3(bc2.x, deck_y + 0.42, bc2.y), b_basis, Vector3(1.68, 0.84, 0.52))

	for entry in [
		[cedar_st, "OverlookCedar", mats.wood_cedar_mat, true],
		[steel_st, "OverlookSteel", mats.dark_metal_mat, false],
	]:
		var mesh: ArrayMesh = (entry[0] as SurfaceTool).commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = String(entry[1])
		mi.mesh = mesh
		mi.material_override = entry[2] as Material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(entry[3]) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 260.0
		mi.visibility_range_end_margin = 24.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mi)


static func _emit_embankment_wall(
	stone_st: SurfaceTool,
	cap_st: SurfaceTool,
	p0: Vector2,
	p1: Vector2,
	width: float,
	top_y0: float,
	top_y1: float,
	terrain: TerrainData
) -> void:
	var ab := p1 - p0
	var total_len := ab.length()
	if total_len < 1.5:
		return
	var dir := ab / total_len
	var yaw := atan2(dir.x, dir.y)
	var b := Basis(Vector3.UP, yaw)
	var tiers := clampi(int(round(total_len / 2.6)), 2, 4)
	var seg_len := total_len / float(tiers)

	for ti in range(tiers):
		var u := (float(ti) + 0.5) / float(tiers)
		var pt := p0.lerp(p1, u)
		var terr_y := _h(terrain, pt)
		var top_y := maxf(terr_y + 0.38, lerpf(top_y0, top_y1, u))
		var bot_y := terr_y - 1.25
		var wall_h := maxf(1.0, top_y - bot_y)
		# Lower stepped concrete/stone batter footing + main ashlar limestone wall + overhanging cap + end pilasters
		_emit_fb_box(stone_st, Vector3(pt.x, bot_y + wall_h * 0.35, pt.y), b, Vector3(width + 0.34, wall_h * 0.70, seg_len + 0.04))
		_emit_fb_box(stone_st, Vector3(pt.x, bot_y + wall_h * 0.5, pt.y), b, Vector3(width, wall_h, seg_len + 0.02))
		_emit_fb_box(cap_st, Vector3(pt.x, top_y + 0.07, pt.y), b, Vector3(width + 0.16, 0.14, seg_len + 0.06))
		if ti == 0 or ti == tiers - 1:
			var end_pt := p0 if ti == 0 else p1
			var end_top := maxf(_h(terrain, end_pt) + 0.48, top_y0 if ti == 0 else top_y1)
			var end_h := maxf(1.2, end_top + 0.22 - (terr_y - 1.25))
			_emit_fb_box(stone_st, Vector3(end_pt.x, (terr_y - 1.25) + end_h * 0.5, end_pt.y), b, Vector3(width + 0.22, end_h, width + 0.22))
			_emit_fb_box(cap_st, Vector3(end_pt.x, end_top + 0.26, end_pt.y), b, Vector3(width + 0.34, 0.12, width + 0.34))


static func _build_major_plaza_features(parent: Node3D, w: Dictionary, terrain: TerrainData, mats: MaterialLibrary) -> void:
	var center: Vector2 = w["center"]
	var rad: float = float(w.get("radius", 8.0))
	var blocked: Array = w.get("blocked_angles", [])
	var art_var := int(w.get("art_variant", 0))
	var seed_v := int(w.get("seed", 0))

	var root := Node3D.new()
	root.name = "MajorPlazaFeatures_%s" % String(w.get("id", "plaza"))
	parent.add_child(root)

	var body := StaticBody3D.new()
	body.name = "MajorPlazaCollision"
	root.add_child(body)

	var cedar_st := SurfaceTool.new()
	cedar_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark_st := SurfaceTool.new()
	dark_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone_st := SurfaceTool.new()
	stone_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steel_st := SurfaceTool.new()
	steel_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gold_st := SurfaceTool.new()
	gold_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow_st := SurfaceTool.new()
	glow_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var base_y := _h(terrain, center) + 0.065
	var seed_off := float(posmod(seed_v, 628)) * 0.01

	# 1. Select well-spaced open perimeter angles that avoid walkway entrances/spurs
	var open_angles := _find_open_plaza_angles(blocked, seed_off)
	var pergola_ang := open_angles[0]
	var art_ang := wrapf(pergola_ang + PI, -PI, PI)
	var best_art_sep := -1.0
	for cand_a in open_angles:
		var sep := absf(wrapf(cand_a - pergola_ang, -PI, PI))
		if sep > best_art_sep:
			best_art_sep = sep
			art_ang = cand_a

	# 2. Timber-and-steel shade pergola arc along outer perimeter ring (walkable underneath)
	var perg_r := rad - 1.35
	var perg_span := clampf(4.6 / maxf(4.0, perg_r), 0.56, 0.86)
	var col_angles := [
		pergola_ang - perg_span * 0.5,
		pergola_ang - perg_span * 0.17,
		pergola_ang + perg_span * 0.17,
		pergola_ang + perg_span * 0.5,
	]
	for ca in col_angles:
		for r_off: float in [-0.72, 0.72]:
			var rp := center + Vector2(cos(ca), sin(ca)) * (perg_r + r_off)
			var py := maxf(base_y - 0.12, _h(terrain, rp) + 0.06)
			var b_rad := Basis(Vector3.UP, -ca)
			_emit_fb_box(stone_st, Vector3(rp.x, py + 0.16, rp.y), b_rad, Vector3(0.32, 0.34, 0.32))
			_emit_fb_box(dark_st, Vector3(rp.x, py + 1.60, rp.y), b_rad, Vector3(0.14, 2.86, 0.14))
			_add_box_col(body, Vector3(rp.x, py + 1.50, rp.y), b_rad, Vector3(0.22, 3.0, 0.22))
	# Curved fascia beams & cross cedar rafters at y = 3.0m
	var beam_y := base_y + 2.98
	for bi in range(col_angles.size() - 1):
		var a0: float = col_angles[bi]
		var a1: float = col_angles[bi + 1]
		var amid := (a0 + a1) * 0.5
		var chord := 2.0 * perg_r * sin((a1 - a0) * 0.5)
		var tang_yaw := atan2(-sin(amid), cos(amid))
		var b_t := Basis(Vector3.UP, tang_yaw)
		for r_off: float in [-0.72, 0.72]:
			var bm2 := center + Vector2(cos(amid), sin(amid)) * (perg_r + r_off)
			_emit_fb_box(dark_st, Vector3(bm2.x, beam_y, bm2.y), b_t, Vector3(0.12, 0.20, chord + 0.18))
	var rafter_n := 7
	for ri in range(rafter_n):
		var ra := lerpf(col_angles[0] - 0.04, col_angles[3] + 0.04, float(ri) / float(rafter_n - 1))
		var rm2 := center + Vector2(cos(ra), sin(ra)) * perg_r
		var r_dir := Vector2(cos(ra), sin(ra))
		var b_r := Basis(Vector3.UP, atan2(r_dir.x, r_dir.y))
		_emit_fb_box(cedar_st, Vector3(rm2.x, beam_y + 0.14, rm2.y), b_r, Vector3(0.10, 0.16, 2.15))

	# Curved bench beneath pergola + 2 additional curved seating ring bays in other open sectors
	var seat_angles: Array[float] = [pergola_ang]
	for cand_a in open_angles:
		if seat_angles.size() >= 3:
			break
		if absf(wrapf(cand_a - pergola_ang, -PI, PI)) > 0.75 and absf(wrapf(cand_a - art_ang, -PI, PI)) > 0.65:
			seat_angles.append(cand_a)

	for sa in seat_angles:
		var seat_r := rad - 1.25
		var seg_ang := 0.24
		for sub: int in [-1, 0, 1]:
			var ang: float = sa + float(sub) * seg_ang
			var sp2 := center + Vector2(cos(ang), sin(ang)) * seat_r
			var sy := maxf(base_y - 0.14, _h(terrain, sp2) + 0.06)
			var inward := (center - sp2).normalized()
			var b_seat := Basis(Vector3.UP, atan2(inward.x, inward.y))
			var seg_w := seat_r * seg_ang * 0.96
			_emit_fb_box(stone_st, Vector3(sp2.x, sy + 0.22, sp2.y), b_seat, Vector3(seg_w, 0.44, 0.50))
			_emit_fb_box(cedar_st, Vector3(sp2.x, sy + 0.47, sp2.y), b_seat, Vector3(seg_w + 0.04, 0.07, 0.54))
			_emit_fb_box(cedar_st, Vector3(sp2.x, sy + 0.72, sp2.y) - inward_3d(inward) * 0.22, b_seat, Vector3(seg_w, 0.32, 0.07))
			_add_box_col(body, Vector3(sp2.x, sy + 0.40, sp2.y), b_seat, Vector3(seg_w, 0.80, 0.58))

	# 3. Geometric public art sculpture on limestone plinth
	var art_r := rad * 0.56 if rad >= 8.2 else rad - 1.55
	var art2 := center + Vector2(cos(art_ang), sin(art_ang)) * art_r
	var art_y := maxf(base_y - 0.08, _h(terrain, art2) + 0.05)
	var art_p3 := Vector3(art2.x, art_y, art2.y)
	_emit_fb_cyl(stone_st, art_p3 + Vector3(0.0, 0.16, 0.0), 0.92, 0.98, 0.32, 8)
	_emit_fb_cyl(stone_st, art_p3 + Vector3(0.0, 0.46, 0.0), 0.68, 0.74, 0.34, 8)
	var plinth_cs := CollisionShape3D.new()
	var plinth_cyl := CylinderShape3D.new()
	plinth_cyl.radius = 0.95
	plinth_cyl.height = 2.6
	plinth_cs.shape = plinth_cyl
	plinth_cs.position = art_p3 + Vector3(0.0, 1.3, 0.0)
	body.add_child(plinth_cs)

	var b_art := Basis(Vector3.UP, art_ang + 0.4)
	if art_var == 0:
		# Twin interlocking monumental gold & brushed-steel angled arches
		var b1 := b_art * Basis(Vector3.FORWARD, 0.26)
		var b2 := b_art * Basis(Vector3.UP, 1.05) * Basis(Vector3.FORWARD, -0.26)
		_emit_fb_box(steel_st, art_p3 + Vector3(0.0, 1.65, 0.0) - b1.x * 0.22, b1, Vector3(0.18, 2.25, 0.18))
		_emit_fb_box(gold_st, art_p3 + Vector3(0.0, 1.85, 0.0) + b2.x * 0.22, b2, Vector3(0.16, 2.45, 0.16))
		_emit_fb_box(gold_st, art_p3 + Vector3(0.0, 2.65, 0.0), b_art * Basis(Vector3.RIGHT, 0.35), Vector3(0.95, 0.16, 0.16))
	elif art_var == 1:
		# Ascending kinetic spiral obelisk
		for tier_i in range(5):
			var ty := 0.85 + float(tier_i) * 0.44
			var sc := lerpf(0.62, 0.24, float(tier_i) / 4.0)
			var tb := Basis(Vector3.UP, art_ang + float(tier_i) * 0.48)
			_emit_fb_box(steel_st if tier_i % 2 == 0 else gold_st, art_p3 + Vector3(0.0, ty, 0.0), tb, Vector3(sc, 0.38, sc * 0.72))
	else:
		# Cantilevered geometric gateway & suspended bronze prism
		_emit_fb_box(steel_st, art_p3 + Vector3(0.0, 1.65, 0.0) + b_art.x * 0.36, b_art, Vector3(0.16, 2.15, 0.24))
		_emit_fb_box(steel_st, art_p3 + Vector3(0.0, 1.65, 0.0) - b_art.x * 0.36, b_art, Vector3(0.16, 2.15, 0.24))
		_emit_fb_box(steel_st, art_p3 + Vector3(0.0, 2.75, 0.0), b_art, Vector3(1.12, 0.18, 0.26))
		_emit_fb_box(gold_st, art_p3 + Vector3(0.0, 1.85, 0.0), b_art * Basis(Vector3.RIGHT, 0.78) * Basis(Vector3.FORWARD, 0.78), Vector3(0.46, 0.46, 0.46))

	# 4. Tall double-globe ornamental park lamps along clear perimeter points
	var lamp_r := rad - 0.42
	for l_idx in range(4):
		var la := seed_off + float(l_idx) * (PI * 0.5) + 0.32
		if not _is_plaza_angle_clear(la, blocked, 0.42):
			continue
		var lp2 := center + Vector2(cos(la), sin(la)) * lamp_r
		var ly := maxf(base_y - 0.18, _h(terrain, lp2) + 0.05)
		var lp3 := Vector3(lp2.x, ly, lp2.y)
		var tang := Vector2(-sin(la), cos(la))
		var b_lamp := Basis(Vector3.UP, atan2(tang.x, tang.y))
		_emit_fb_cyl(dark_st, lp3 + Vector3(0.0, 0.22, 0.0), 0.16, 0.22, 0.44, 8)
		_emit_fb_cyl(dark_st, lp3 + Vector3(0.0, 2.05, 0.0), 0.055, 0.09, 3.6, 8)
		_emit_fb_box(dark_st, lp3 + Vector3(0.0, 3.78, 0.0), b_lamp, Vector3(1.02, 0.08, 0.08))
		for gx_off: float in [-0.46, 0.46]:
			var g_pos := lp3 + b_lamp.x * gx_off + Vector3(0.0, 4.02, 0.0)
			_emit_fb_cyl(dark_st, g_pos - Vector3(0.0, 0.17, 0.0), 0.09, 0.06, 0.12, 8)
			_emit_fb_box(glow_st, g_pos, b_lamp, Vector3(0.24, 0.28, 0.24))
		var l_cs := CollisionShape3D.new()
		var l_cyl := CylinderShape3D.new()
		l_cyl.radius = 0.14
		l_cyl.height = 4.0
		l_cs.shape = l_cyl
		l_cs.position = lp3 + Vector3(0.0, 2.0, 0.0)
		body.add_child(l_cs)

	for entry in [
		[cedar_st, "PlazaPergolaCedar", mats.wood_cedar_mat, true],
		[dark_st, "PlazaMetals", mats.dark_metal_mat, true],
		[stone_st, "PlazaStoneTrim", mats.limestone_mat, false],
		[steel_st, "PlazaSculptureSteel", mats.light_metal_mat, true],
		[gold_st, "PlazaSculptureGold", mats.gold_metal_mat, false],
		[glow_st, "PlazaLampGlobes", mats.lamp_glow_mat, false],
	]:
		var mesh: ArrayMesh = (entry[0] as SurfaceTool).commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = String(entry[1])
		mi.mesh = mesh
		mi.material_override = entry[2] as Material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(entry[3]) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 220.0
		mi.visibility_range_end_margin = 22.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mi)


static func inward_3d(v2: Vector2) -> Vector3:
	return Vector3(v2.x, 0.0, v2.y)


static func _is_plaza_angle_clear(ang: float, blocked: Array, margin_rad: float) -> bool:
	for ba_var in blocked:
		var ba := float(ba_var)
		if absf(wrapf(ang - ba, -PI, PI)) < margin_rad:
			return false
	return true


static func _find_open_plaza_angles(blocked: Array, seed_off: float) -> Array[float]:
	var out: Array[float] = []
	for i in range(16):
		var a := wrapf(seed_off + float(i) * (TAU / 16.0), -PI, PI)
		if _is_plaza_angle_clear(a, blocked, 0.48):
			out.append(a)
	if out.is_empty():
		out.append(seed_off)
	if out.size() == 1:
		out.append(wrapf(out[0] + PI, -PI, PI))
	return out
