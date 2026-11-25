class_name FloraGenerator
extends RefCounted

## Pure-GDScript botanical procedural bush and flower patch generator.
## Produces cached multi-surface ArrayMeshes (bark twigs, leaf sprigs, 3D stems & petals)
## for instanced per-chunk MultiMeshInstance3D rendering.

const GOLDEN_ANGLE_RAD := 2.39996323
const VARIANT_COUNT := 2

const BUSH_SPECIES := ["boxwood", "flowering_azalea", "ornamental_fern", "lavender_shrub"]
const FLOWER_SPECIES := ["bluebonnet", "coneflower", "marigold", "wildflower_daisy"]

static var _cache: Dictionary = {}


static func get_flora_bundle(kind: String, species: String, variant: int) -> Dictionary:
	var v_idx := posmod(variant, VARIANT_COUNT)
	var key := "%s_%s_%d" % [kind, species, v_idx]
	if _cache.has(key):
		return _cache[key]

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ 0x51A7F01A

	var bundle: Dictionary
	if kind == "riprap" or species == "riprap_boulder":
		bundle = _generate_riprap_bundle(rng)
	elif kind == "reed" or species == "cattail_reed":
		bundle = _generate_reed_bundle(rng)
	elif kind == "bush":
		bundle = _generate_bush_bundle(species, rng)
	else:
		bundle = _generate_flower_bundle(species, rng)

	_cache[key] = bundle
	return bundle


static func _generate_bush_bundle(species: String, rng: RandomNumberGenerator) -> Dictionary:
	var bark_st := SurfaceTool.new()
	bark_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fol_st := SurfaceTool.new()
	fol_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blos_st := SurfaceTool.new()
	blos_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	if species == "ornamental_fern":
		var frond_count := 15
		var dark_frond := Color(0.08, 0.27, 0.10)
		var tip_frond := Color(0.19, 0.44, 0.14)
		for fi in range(frond_count):
			var az := float(fi) * GOLDEN_ANGLE_RAD + rng.randf_range(-0.14, 0.14)
			var tier := float(fi) / float(frond_count)
			var len_f := lerpf(0.55, 0.88, 1.0 - tier * 0.45) * rng.randf_range(0.92, 1.08)
			var rise_f := lerpf(0.28, 0.56, tier)
			_emit_curved_frond(blos_st, Vector3(0.0, 0.04, 0.0), az, len_f, rise_f, 0.16, dark_frond, tip_frond)
		return {
			"bark_mesh": null,
			"foliage_mesh": null,
			"blossom_mesh": blos_st.commit(),
		}

	var is_boxwood := (species == "boxwood")
	var is_lavender := (species == "lavender_shrub")
	var twig_count := 9 if is_boxwood else 8
	var mound_r := 0.52 if is_boxwood else (0.58 if species == "flowering_azalea" else 0.44)
	var mound_h := 0.72 if is_boxwood else (0.76 if species == "flowering_azalea" else 0.52)
	var canopy_center := Vector3(0.0, mound_h * 0.55, 0.0)

	for ti in range(twig_count):
		var az := float(ti) * GOLDEN_ANGLE_RAD + rng.randf_range(-0.18, 0.18)
		var ring_r := 0.06 if ti == 0 else lerpf(0.14, mound_r * 0.72, float(ti) / float(twig_count))
		var h_reach := mound_h * rng.randf_range(0.58, 0.96)
		var base_pt := Vector3(cos(az) * 0.05, 0.0, sin(az) * 0.05)
		var mid_pt := Vector3(cos(az) * ring_r * 0.52, h_reach * 0.55, sin(az) * ring_r * 0.52)
		var tip_pt := Vector3(cos(az) * ring_r, h_reach, sin(az) * ring_r)

		_emit_tapered_limb(bark_st, base_pt, mid_pt, 0.032, 0.020)
		_emit_tapered_limb(bark_st, mid_pt, tip_pt, 0.020, 0.010)

		var sph_n := (tip_pt - canopy_center).normalized()
		if sph_n.length_squared() < 0.01:
			sph_n = Vector3.UP
		var card_cnt := 4 if is_boxwood else 3
		for ci in range(card_cnt):
			var c_az := az + float(ci) * GOLDEN_ANGLE_RAD
			var card_off := Vector3(cos(c_az), rng.randf_range(-0.35, 0.45), sin(c_az)) * 0.14
			var c_pos := tip_pt + card_off
			var card_sz := (0.46 if is_boxwood else 0.44) * rng.randf_range(0.88, 1.14)
			var shade := Color(0.28, 0.35, 0.48, rng.randf())
			_emit_crossed_sprig(fol_st, c_pos, c_az, rng.randf_range(-0.4, 0.4), card_sz, sph_n, shade)

		if species == "flowering_azalea" and ti % 2 == 0:
			var blos_col := Color(0.93, 0.36, 0.56) if rng.randf() < 0.65 else Color(0.97, 0.74, 0.84)
			var b_pt := tip_pt + Vector3(cos(az) * 0.10, 0.12, sin(az) * 0.10)
			_emit_rosette(blos_st, b_pt, Vector3(cos(az) * 0.35, 1.0, sin(az) * 0.35).normalized(), 0.085, 5, blos_col, Color(0.96, 0.85, 0.35), 0.7)

	if is_lavender:
		var stalk_col := Color(0.28, 0.46, 0.28)
		var petal_a := Color(0.50, 0.30, 0.84)
		var petal_b := Color(0.68, 0.50, 0.94)
		for si in range(13):
			var s_az := float(si) * GOLDEN_ANGLE_RAD + rng.randf_range(-0.15, 0.15)
			var sr := rng.randf_range(0.10, 0.36)
			var s_base := Vector3(cos(s_az) * sr * 0.4, 0.22, sin(s_az) * sr * 0.4)
			var s_top := Vector3(cos(s_az) * sr * 1.15, rng.randf_range(0.68, 0.96), sin(s_az) * sr * 1.15)
			_emit_stalk(blos_st, s_base, s_top, 0.011, stalk_col, 0.6)
			_emit_raceme_spike(blos_st, s_top.lerp(s_base, 0.32), s_top, 0.042, 4, petal_a, petal_b, 0.9)

	return {
		"bark_mesh": bark_st.commit(),
		"foliage_mesh": fol_st.commit(),
		"blossom_mesh": blos_st.commit() if (species == "flowering_azalea" or is_lavender) else null,
	}


static func _generate_flower_bundle(species: String, rng: RandomNumberGenerator) -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var stem_dark := Color(0.15, 0.38, 0.14)
	var stem_light := Color(0.26, 0.54, 0.20)
	var shoots := 6 if species != "bluebonnet" else 5

	# Basal rosette leaf blades near root collar
	for li in range(8):
		var l_az := float(li) * GOLDEN_ANGLE_RAD + rng.randf_range(-0.15, 0.15)
		_emit_curved_frond(st, Vector3(0.0, 0.02, 0.0), l_az, rng.randf_range(0.18, 0.28), rng.randf_range(0.08, 0.14), 0.065, stem_dark, stem_light)

	for si in range(shoots):
		var az := float(si) * GOLDEN_ANGLE_RAD + rng.randf_range(-0.22, 0.22)
		var spread := rng.randf_range(0.08, 0.24) if si > 0 else 0.03
		var h := rng.randf_range(0.32, 0.54) if species != "bluebonnet" else rng.randf_range(0.38, 0.62)
		var base_p := Vector3(cos(az) * spread * 0.25, 0.0, sin(az) * spread * 0.25)
		var top_p := Vector3(cos(az) * spread, h, sin(az) * spread)
		var lean_dir := Vector3(cos(az) * 0.25, 1.0, sin(az) * 0.25).normalized()

		_emit_stalk(st, base_p, top_p, 0.012, stem_dark, 0.65)
		_emit_stalk_leaf(st, base_p.lerp(top_p, 0.42), az + 1.2, 0.11, 0.04, stem_light)

		match species:
			"bluebonnet":
				var bot_p := base_p.lerp(top_p, 0.48)
				_emit_raceme_spike(st, bot_p, top_p, 0.052, 5, Color(0.14, 0.28, 0.84), Color(0.92, 0.94, 0.99), 0.95)
			"coneflower":
				_emit_rosette(st, top_p, lean_dir, 0.105, 8, Color(0.84, 0.28, 0.62), Color(0.82, 0.44, 0.10), 0.95, true)
			"marigold":
				var c_a := Color(0.98, 0.58, 0.08)
				var c_b := Color(0.99, 0.78, 0.16)
				_emit_rosette(st, top_p, lean_dir, 0.090, 7, c_a, c_b, 0.95, false)
				_emit_rosette(st, top_p + lean_dir * 0.025, lean_dir, 0.058, 6, c_b, Color(0.90, 0.38, 0.05), 1.0, false)
			_:
				# Wildflower daisy (sunny white or warm golden)
				var white_petal := Color(0.98, 0.97, 0.93)
				var gold_petal := Color(0.98, 0.84, 0.18)
				var p_col := white_petal if (si % 2 == 0) else gold_petal
				_emit_rosette(st, top_p, lean_dir, 0.095, 8, p_col, Color(0.94, 0.66, 0.10), 0.95, false)

	return {
		"bark_mesh": null,
		"foliage_mesh": null,
		"blossom_mesh": st.commit(),
	}


static func _emit_tapered_limb(st: SurfaceTool, p0: Vector3, p1: Vector3, r0: float, r1: float) -> void:
	var seg_dir := (p1 - p0)
	if seg_dir.length_squared() < 0.0001:
		return
	var ax := seg_dir.normalized()
	var up_ref := Vector3.RIGHT if absf(ax.y) > 0.9 else Vector3.UP
	var u := ax.cross(up_ref).normalized()
	var v := ax.cross(u).normalized()
	const SEGS := 5
	for i in range(SEGS):
		var a0 := float(i) * TAU / float(SEGS)
		var a1 := float(i + 1) * TAU / float(SEGS)
		var n0 := u * cos(a0) + v * sin(a0)
		var n1 := u * cos(a1) + v * sin(a1)
		_emit_col_quad(
			st,
			p1 + n0 * r1, p1 + n1 * r1,
			p0 + n0 * r0, p0 + n1 * r0,
			(n0 + n1).normalized(),
			Color(0.22, 0.18, 0.0, 0.35),
			Color(0.28, 0.24, 0.0, 0.35)
		)


static func _emit_crossed_sprig(
	st: SurfaceTool,
	center: Vector3,
	yaw: float,
	pitch: float,
	size: float,
	sph_n: Vector3,
	vcol: Color
) -> void:
	var b1 := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var b2 := Basis(Vector3.UP, yaw + PI * 0.5) * Basis(Vector3.RIGHT, -pitch * 0.7)
	var h := size * 0.5
	for br: Basis in [b1, b2]:
		var rx := br.x * h
		var ry := br.y * h
		_emit_sprig_quad(
			st,
			center - rx + ry, center + rx + ry,
			center - rx - ry, center + rx - ry,
			sph_n, vcol
		)


static func _emit_sprig_quad(
	st: SurfaceTool,
	tl: Vector3,
	tr: Vector3,
	bl: Vector3,
	br: Vector3,
	normal: Vector3,
	col: Color
) -> void:
	var n := normal.normalized()
	var pts := [tl, tr, bl, tr, br, bl]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in range(6):
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])


static func _emit_stalk(st: SurfaceTool, p0: Vector3, p1: Vector3, rad: float, col: Color, sway_a: float) -> void:
	var ax := (p1 - p0).normalized()
	var up_r := Vector3.RIGHT if absf(ax.y) > 0.9 else Vector3.UP
	var u := ax.cross(up_r).normalized()
	var v := ax.cross(u).normalized()
	var c_bot := Color(col.r * 0.85, col.g * 0.85, col.b * 0.85, sway_a * 0.25)
	var c_top := Color(col.r, col.g, col.b, sway_a)
	for i in range(4):
		var a0 := float(i) * TAU / 4.0
		var a1 := float(i + 1) * TAU / 4.0
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		_emit_col_quad(st, p1 + d0 * (rad * 0.7), p1 + d1 * (rad * 0.7), p0 + d0 * rad, p0 + d1 * rad, (d0 + d1).normalized(), c_top, c_bot)


static func _emit_stalk_leaf(st: SurfaceTool, origin: Vector3, az: float, length: float, width: float, col: Color) -> void:
	var fwd := Vector3(cos(az), 0.35, sin(az)).normalized()
	var side := Vector3(-fwd.z, 0.0, fwd.x).normalized() * width
	var mid := origin + fwd * (length * 0.55) + Vector3.UP * (length * 0.08)
	var tip := origin + fwd * length - Vector3.UP * (length * 0.10)
	var n := (Vector3.UP + fwd * 0.25).normalized()
	var c0 := Color(col.r * 0.82, col.g * 0.85, col.b * 0.82, 0.45)
	var c1 := Color(col.r, col.g, col.b, 0.85)
	_emit_col_tri(st, origin, mid - side, tip, n, c0, c1, c1)
	_emit_col_tri(st, origin, tip, mid + side, n, c0, c1, c1)


static func _emit_curved_frond(
	st: SurfaceTool,
	origin: Vector3,
	az: float,
	length: float,
	rise: float,
	max_w: float,
	c_base: Color,
	c_tip: Color
) -> void:
	var fwd := Vector3(cos(az), 0.0, sin(az))
	var side := Vector3(-sin(az), 0.0, cos(az))
	var pts: Array[Vector3] = []
	var widths: Array[float] = [0.18, 1.0, 0.78, 0.08]
	for i in range(4):
		var t := float(i) / 3.0
		var y := sin(t * PI * 0.76) * rise + t * 0.06
		var r := t * length
		pts.append(origin + fwd * r + Vector3.UP * y)

	for i in range(3):
		var t0 := float(i) / 3.0
		var t1 := float(i + 1) / 3.0
		var col0 := c_base.lerp(c_tip, t0)
		var col1 := c_base.lerp(c_tip, t1)
		col0.a = 0.2 + t0 * 0.8
		col1.a = 0.2 + t1 * 0.8
		var w0 := max_w * widths[i] * 0.5
		var w1 := max_w * widths[i + 1] * 0.5
		var n := (Vector3.UP * 0.85 + fwd * 0.2).normalized()
		_emit_col_quad(st, pts[i + 1] - side * w1, pts[i + 1] + side * w1, pts[i] - side * w0, pts[i] + side * w0, n, col1, col0)


static func _emit_rosette(
	st: SurfaceTool,
	center: Vector3,
	axis_up: Vector3,
	radius: float,
	petals: int,
	petal_col: Color,
	center_col: Color,
	sway_a: float,
	droop: bool = false
) -> void:
	var up := axis_up.normalized()
	var ref := Vector3.RIGHT if absf(up.y) > 0.9 else Vector3.UP
	var u := up.cross(ref).normalized()
	var v := up.cross(u).normalized()

	var base_c := Color(petal_col.r * 0.82, petal_col.g * 0.82, petal_col.b * 0.82, sway_a)
	var tip_c := Color(petal_col.r, petal_col.g, petal_col.b, sway_a)
	var ctr_c := Color(center_col.r, center_col.g, center_col.b, sway_a)

	var p_lift := -radius * 0.24 if droop else radius * 0.22
	for pi in range(petals):
		var a := float(pi) * TAU / float(petals)
		var rad_d := u * cos(a) + v * sin(a)
		var tan_d := (u * -sin(a) + v * cos(a)) * (radius * 0.34)
		var p_in := center + rad_d * (radius * 0.16)
		var p_mid_l := center + rad_d * (radius * 0.65) + up * (p_lift * 0.4) - tan_d
		var p_mid_r := center + rad_d * (radius * 0.65) + up * (p_lift * 0.4) + tan_d
		var p_out := center + rad_d * radius + up * p_lift
		_emit_col_tri(st, p_in, p_mid_l, p_out, up, base_c, tip_c, tip_c)
		_emit_col_tri(st, p_in, p_out, p_mid_r, up, base_c, tip_c, tip_c)

	# 3D raised disk/cone center
	var disk_r := radius * 0.28
	var cone_tip := center + up * (radius * (0.42 if droop else 0.18))
	for pi in range(petals):
		var a0 := float(pi) * TAU / float(petals)
		var a1 := float(pi + 1) * TAU / float(petals)
		var d0 := center + (u * cos(a0) + v * sin(a0)) * disk_r
		var d1 := center + (u * cos(a1) + v * sin(a1)) * disk_r
		_emit_col_tri(st, d0, d1, cone_tip, up, ctr_c, ctr_c, ctr_c)


static func _emit_raceme_spike(
	st: SurfaceTool,
	bot: Vector3,
	top: Vector3,
	max_rad: float,
	tiers: int,
	col_low: Color,
	col_high: Color,
	sway_a: float
) -> void:
	var ax := (top - bot).normalized()
	var ref := Vector3.RIGHT if absf(ax.y) > 0.9 else Vector3.UP
	var u := ax.cross(ref).normalized()
	var v := ax.cross(u).normalized()

	for ti in range(tiers):
		var frac := float(ti) / maxf(1.0, float(tiers - 1))
		var tier_c := bot.lerp(top, frac * 0.92)
		var r := max_rad * lerpf(1.0, 0.38, frac)
		var petal_c := col_low.lerp(col_high, frac * 0.72)
		petal_c.a = sway_a
		for k in range(3):
			var a := float(k) * (TAU / 3.0) + float(ti) * 0.9
			var d := u * cos(a) + v * sin(a)
			var side := u * -sin(a) + v * cos(a)
			var p0 := tier_c + d * (r * 0.25)
			var p1 := tier_c + d * r - ax * (r * 0.25) + side * (r * 0.45)
			var p2 := tier_c + d * r - ax * (r * 0.25) - side * (r * 0.45)
			var p3 := tier_c + d * (r * 0.85) + ax * (r * 0.55)
			_emit_col_tri(st, p0, p1, p3, d, petal_c, petal_c, petal_c)
			_emit_col_tri(st, p0, p3, p2, d, petal_c, petal_c, petal_c)


static func _emit_col_quad(
	st: SurfaceTool,
	tl: Vector3,
	tr: Vector3,
	bl: Vector3,
	br: Vector3,
	normal: Vector3,
	c_top: Color,
	c_bot: Color
) -> void:
	var n := normal.normalized()
	var n_test := (bl - tl).cross(tr - tl)
	var pts := [tl, tr, bl, tr, br, bl] if n_test.dot(n) >= 0.0 else [tl, bl, tr, tr, bl, br]
	var cols := [c_top, c_top, c_bot, c_top, c_bot, c_bot] if n_test.dot(n) >= 0.0 else [c_top, c_bot, c_top, c_top, c_bot, c_bot]
	for i in range(6):
		st.set_color(cols[i])
		st.set_normal(n)
		st.add_vertex(pts[i])


static func _emit_col_tri(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	normal: Vector3,
	ca: Color,
	cb: Color,
	cc: Color
) -> void:
	var n := normal.normalized()
	st.set_color(ca)
	st.set_normal(n)
	st.add_vertex(a)
	st.set_color(cb)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_color(cc)
	st.set_normal(n)
	st.add_vertex(c)


static func _generate_reed_bundle(rng: RandomNumberGenerator) -> Dictionary:
	## Wetland sedge/reed leaf cluster (reed_mesh -> reed_mat) plus wind-swaying cattail stalks (blossom_mesh).
	var reed_st := SurfaceTool.new()
	reed_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cattail_st := SurfaceTool.new()
	cattail_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var blade_base := Color(0.20, 0.34, 0.14)
	var blade_tip := Color(0.46, 0.50, 0.22)
	const BLADE_COUNT := 14
	for bi in range(BLADE_COUNT):
		var az := float(bi) * GOLDEN_ANGLE_RAD + rng.randf_range(-0.18, 0.18)
		var r_off := rng.randf_range(0.02, 0.20)
		var origin := Vector3(cos(az) * r_off, -0.04, sin(az) * r_off)
		var len_b := rng.randf_range(0.58, 1.08)
		var rise_b := len_b * rng.randf_range(0.72, 0.92)
		var w_b := rng.randf_range(0.042, 0.068)
		_emit_curved_frond(reed_st, origin, az, len_b * 0.48, rise_b, w_b, blade_base, blade_tip)

	var stem_col := Color(0.22, 0.39, 0.15)
	var head_col := Color(0.28, 0.14, 0.07)
	var tip_col := Color(0.56, 0.44, 0.25)
	var stalk_count := rng.randi_range(3, 4)
	for si in range(stalk_count):
		var az := float(si) * GOLDEN_ANGLE_RAD + rng.randf_range(-0.25, 0.25)
		var rad := rng.randf_range(0.04, 0.16)
		var lean := rng.randf_range(0.08, 0.22)
		var h := rng.randf_range(0.95, 1.32)
		var p_bot := Vector3(cos(az) * rad, -0.04, sin(az) * rad)
		var p_top := Vector3(cos(az) * (rad + lean), h, sin(az) * (rad + lean))
		var h_bot := p_bot.lerp(p_top, 0.72)
		var h_mid := p_bot.lerp(p_top, 0.89)
		_emit_stalk(cattail_st, p_bot, h_bot, 0.011, stem_col, 0.55)
		_emit_stalk(cattail_st, h_bot, h_mid, 0.029, head_col, 0.78)
		_emit_stalk(cattail_st, h_mid, p_top, 0.007, tip_col, 0.88)

	return {
		"bark_mesh": null,
		"foliage_mesh": null,
		"reed_mesh": reed_st.commit(),
		"blossom_mesh": cattail_st.commit(),
	}


static func _generate_riprap_bundle(rng: RandomNumberGenerator) -> Dictionary:
	## Low-poly quarried/water-worn shoreline boulder for chunked riprap MultiMesh clusters.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	const SLICES := 7
	const RINGS := 4
	var rx := rng.randf_range(0.50, 0.68)
	var ry := rng.randf_range(0.32, 0.44)
	var rz := rng.randf_range(0.46, 0.62)
	var p1 := rng.randf_range(0.0, TAU)
	var p2 := rng.randf_range(0.0, TAU)

	var verts: Array[PackedVector3Array] = []
	for ri in range(RINGS + 1):
		var v_frac := float(ri) / float(RINGS)
		var phi := lerpf(-PI * 0.42, PI * 0.50, v_frac)
		var cy := sin(phi)
		var cr := cos(phi)
		var ring := PackedVector3Array()
		for si in range(SLICES):
			var theta := float(si) * TAU / float(SLICES)
			var dir := Vector3(cos(theta) * cr, cy, sin(theta) * cr)
			var lump := 1.0 + 0.16 * sin(theta * 2.0 + p1) + 0.12 * cos(phi * 3.0 + theta + p2)
			var pt := Vector3(dir.x * rx * lump, dir.y * ry * lump, dir.z * rz * lump)
			pt.y = maxf(pt.y, -ry * 0.45)
			ring.append(pt)
		verts.append(ring)

	for ri in range(RINGS):
		var r0 := verts[ri]
		var r1 := verts[ri + 1]
		for si in range(SLICES):
			var sn := (si + 1) % SLICES
			var p00 := r0[si]
			var p10 := r0[sn]
			var p01 := r1[si]
			var p11 := r1[sn]
			if ri == 0:
				_emit_riprap_tri(st, p00, p11, p01)
				_emit_riprap_tri(st, p00, p10, p11)
			elif ri == RINGS - 1:
				_emit_riprap_tri(st, p00, p10, p01)
			else:
				_emit_riprap_tri(st, p00, p10, p11)
				_emit_riprap_tri(st, p00, p11, p01)

	# Close flat bottom cap so underside never appears open on steep bank angles
	var bot_ring := verts[0]
	var bot_c := Vector3(0.0, -ry * 0.45, 0.0)
	for si in range(SLICES):
		var sn := (si + 1) % SLICES
		_emit_riprap_tri(st, bot_c, bot_ring[sn], bot_ring[si])

	return {
		"bark_mesh": null,
		"foliage_mesh": null,
		"blossom_mesh": null,
		"riprap_mesh": st.commit(),
	}


static func _emit_riprap_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 0.000001:
		return
	var mid := (a + b + c) / 3.0
	var flip := n.dot(mid) < 0.0
	var p0 := a
	var p1 := c if flip else b
	var p2 := b if flip else c
	var fn := (p2 - p0).cross(p1 - p0).normalized()
	for p: Vector3 in [p0, p1, p2]:
		st.set_uv(Vector2(p.x + p.z, p.y))
		st.set_normal(fn)
		st.add_vertex(p)
