class_name TreeGenerator
extends RefCounted

## Pure-Godot botanical procedural tree generator (no external Blender assets).
## Combines deterministic seeded L-system/stochastic growth (SimonDev),
## golden-angle 137.508° phyllotaxis & root flare (Jaleed Khan),
## phototropism + tip-radius pruning (Pezzza's Work), and 3-tier MultiMesh LODs
## with hierarchical wind attributes packed in vertex COLOR (PlantFactory concept).

const GOLDEN_ANGLE_RAD := 2.39996323  # 137.507764 degrees
const VARIANT_COUNT := 4

const SPECIES_PRESETS := {
	"oak": {
		"trunk_radius": 0.34,
		"trunk_height": 2.35,
		"max_depth": 3,
		"seg_steps": 4,
		"fork_angle": 0.78,
		"child_count": 4,
		"length_decay": 0.78,
		"radius_decay": 0.63,
		"min_tip_radius": 0.030,
		"phototropism": 0.20,
		"gnarl": 0.24,
		"flare_strength": 0.62,
		"leaf_size": 1.26,
		"leaf_clusters": 6,
		"canopy_center": Vector3(0.0, 3.85, 0.0),
	},
	"austin_pecan": {
		"trunk_radius": 0.28,
		"trunk_height": 2.85,
		"max_depth": 3,
		"seg_steps": 4,
		"fork_angle": 0.64,
		"child_count": 4,
		"length_decay": 0.78,
		"radius_decay": 0.62,
		"min_tip_radius": 0.026,
		"phototropism": 0.26,
		"gnarl": 0.16,
		"flare_strength": 0.48,
		"leaf_size": 1.18,
		"leaf_clusters": 6,
		"canopy_center": Vector3(0.0, 4.65, 0.0),
	},
	"cedar_elm": {
		"trunk_radius": 0.22,
		"trunk_height": 2.15,
		"max_depth": 3,
		"seg_steps": 3,
		"fork_angle": 0.68,
		"child_count": 4,
		"length_decay": 0.76,
		"radius_decay": 0.61,
		"min_tip_radius": 0.024,
		"phototropism": 0.22,
		"gnarl": 0.18,
		"flare_strength": 0.40,
		"leaf_size": 1.08,
		"leaf_clusters": 6,
		"canopy_center": Vector3(0.0, 3.45, 0.0),
	},
	"planter_shrub": {
		"trunk_radius": 0.13,
		"trunk_height": 0.68,
		"max_depth": 2,
		"seg_steps": 3,
		"fork_angle": 0.82,
		"child_count": 4,
		"length_decay": 0.78,
		"radius_decay": 0.58,
		"min_tip_radius": 0.020,
		"phototropism": 0.24,
		"gnarl": 0.20,
		"flare_strength": 0.22,
		"leaf_size": 0.92,
		"leaf_clusters": 6,
		"canopy_center": Vector3(0.0, 1.45, 0.0),
	},
	"weeping_willow": {
		"trunk_radius": 0.34,
		"trunk_height": 2.30,
		"max_depth": 3,
		"seg_steps": 4,
		"fork_angle": 0.76,
		"child_count": 4,
		"length_decay": 0.84,
		"radius_decay": 0.58,
		"min_tip_radius": 0.022,
		"phototropism": -0.32,
		"gnarl": 0.20,
		"flare_strength": 0.54,
		"leaf_size": 1.15,
		"leaf_clusters": 7,
		"canopy_center": Vector3(0.0, 3.10, 0.0),
	},
}

# Cache: key "species_variant" -> Dictionary { bark_lods, foliage_lods, trunk_radius, trunk_height, crown_height, canopy_center }
static var _cache: Dictionary = {}


static func get_species_bundle(species: String, variant: int) -> Dictionary:
	var sp: String = species if SPECIES_PRESETS.has(species) else "cedar_elm"
	var var_idx: int = posmod(variant, VARIANT_COUNT)
	var key := "%s_%d" % [sp, var_idx]
	if _cache.has(key):
		return _cache[key]

	var preset: Dictionary = SPECIES_PRESETS[sp]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash("tree_%s_%d_v2028" % [sp, var_idx]))

	var skeleton := _build_skeleton(preset, rng)
	var segments: Array = skeleton["segments"]
	var twigs: Array = skeleton["twigs"]
	var canopy_center: Vector3 = skeleton["canopy_center"]
	var max_h: float = maxf(2.0, float(skeleton["max_height"]))

	var bark_lods: Array[ArrayMesh] = [
		_build_bark_mesh(segments, max_h, 0, preset),
		_build_bark_mesh(segments, max_h, 1, preset),
		_build_bark_mesh(segments, max_h, 2, preset),
	]
	var foliage_lods: Array[ArrayMesh] = [
		_build_foliage_mesh(twigs, canopy_center, max_h, 0, preset, rng),
		_build_foliage_mesh(twigs, canopy_center, max_h, 1, preset, rng),
		_build_foliage_mesh(twigs, canopy_center, max_h, 2, preset, rng),
	]

	var bundle := {
		"species": sp,
		"variant": var_idx,
		"bark_lods": bark_lods,
		"foliage_lods": foliage_lods,
		"trunk_radius": float(preset["trunk_radius"]),
		"trunk_height": float(preset["trunk_height"]),
		"crown_height": max_h,
		"canopy_center": canopy_center,
	}
	_cache[key] = bundle
	return bundle


static func clear_cache() -> void:
	_cache.clear()


static func _build_skeleton(preset: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var segments: Array = []
	var twigs: Array = []
	var trunk_r: float = float(preset["trunk_radius"])
	var trunk_h: float = float(preset["trunk_height"])
	var max_depth: int = int(preset["max_depth"])
	var root_phase: float = rng.randf_range(0.0, TAU)

	var max_y: float = trunk_h
	var canopy_acc: Vector3 = Vector3.ZERO
	var canopy_w: float = 0.0

	var stack: Array = [{
		"start": Vector3(0.0, -0.18, 0.0),
		"dir": Vector3(rng.randf_range(-0.04, 0.04), 1.0, rng.randf_range(-0.04, 0.04)).normalized(),
		"length": trunk_h + 0.18,
		"r0": trunk_r,
		"depth": 0,
		"parent_sway": 0.0,
		"parent_flex": 0.0,
	}]

	while not stack.is_empty():
		var item: Dictionary = stack.pop_back()
		var p_start: Vector3 = item["start"]
		var cur_dir: Vector3 = item["dir"]
		var total_len: float = float(item["length"])
		var r_start: float = float(item["r0"])
		var depth: int = int(item["depth"])
		var p_sway: float = float(item["parent_sway"])
		var p_flex: float = float(item["parent_flex"])

		var steps: int = maxi(2, int(preset["seg_steps"]) - (1 if depth >= max_depth else 0))
		var seg_len: float = total_len / float(steps)
		var r_decay_seg: float = 0.84 if depth == 0 else 0.78
		var r_end_branch: float = maxf(0.012, r_start * r_decay_seg)
		var phototropism: float = float(preset["phototropism"]) / maxf(0.35, seg_len)
		var gnarl: float = float(preset["gnarl"])

		var pts: Array[Vector3] = [p_start]
		var radii: Array[float] = []
		var sway_vals: Array[float] = []
		var flex_vals: Array[float] = []

		var flare_0: float = float(preset["flare_strength"]) if depth == 0 else 0.0
		radii.append(r_start * (1.0 + flare_0))
		sway_vals.append(p_sway)
		flex_vals.append(p_flex)

		var pos := p_start
		var local_gnarl: float = gnarl * (0.20 if depth == 0 else 0.90)
		for si in range(steps):
			var t_next: float = float(si + 1) / float(steps)
			var lateral := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.22, 0.28), rng.randf_range(-1.0, 1.0)) * local_gnarl
			var photo_pull: float = 0.55 if depth == 0 else (0.18 if (phototropism < 0.0 and depth == 1) else phototropism * (0.12 + 0.10 * float(depth)))
			var photo_vec := Vector3.UP * photo_pull
			cur_dir = (cur_dir + lateral + photo_vec).normalized()
			pos += cur_dir * seg_len
			pts.append(pos)

			var base_r: float = lerpf(r_start, r_end_branch, t_next)
			if depth == 0:
				var flare_f: float = float(preset["flare_strength"]) * pow(maxf(0.0, 1.0 - t_next * 1.4), 2.2)
				base_r *= (1.0 + flare_f)
			radii.append(base_r)

			var h_norm: float = clampf(pos.y / 6.0, 0.0, 1.0)
			var t_sway: float = clampf(p_sway + (1.0 - p_sway) * 0.25 * h_norm + float(depth) * 0.08 * t_next, 0.0, 0.78)
			var t_flex: float = clampf(p_flex + (0.04 if depth == 0 else 0.18) * t_next * (1.0 - p_flex * 0.4), 0.0, 0.90)
			sway_vals.append(t_sway)
			flex_vals.append(t_flex)
			max_y = maxf(max_y, pos.y)

		segments.append({
			"pts": pts,
			"radii": radii,
			"sway": sway_vals,
			"flex": flex_vals,
			"depth": depth,
			"phase": root_phase if depth == 0 else rng.randf_range(0.0, TAU),
		})

		var tip_pos := pts[pts.size() - 1]
		var tip_r: float = radii[radii.size() - 1]
		var tip_sway: float = sway_vals[sway_vals.size() - 1]
		var tip_flex: float = flex_vals[flex_vals.size() - 1]

		if depth >= max_depth - 1:
			twigs.append({
				"pos": tip_pos,
				"dir": cur_dir,
				"radius": tip_r,
				"depth": depth,
				"sway": tip_sway,
				"flex": tip_flex,
				"phase": rng.randf(),
			})
			canopy_acc += tip_pos
			canopy_w += 1.0
			if pts.size() >= 3:
				var mid_i: int = pts.size() / 2
				twigs.append({
					"pos": pts[mid_i],
					"dir": cur_dir,
					"radius": radii[mid_i],
					"depth": depth,
					"sway": sway_vals[mid_i],
					"flex": flex_vals[mid_i],
					"phase": rng.randf(),
				})
				canopy_acc += pts[mid_i]
				canopy_w += 1.0

		if depth < max_depth and tip_r > float(preset["min_tip_radius"]):
			var n_children: int = int(preset["child_count"])
			if depth > 0 and rng.randf() < 0.28:
				n_children = maxi(2, n_children - 1)

			var tangent_ref := Vector3.RIGHT if absf(cur_dir.y) > 0.9 else Vector3.UP
			var u_axis := cur_dir.cross(tangent_ref).normalized()
			var v_axis := cur_dir.cross(u_axis).normalized()
			var az_offset := rng.randf_range(0.0, TAU)
			var fork_ang: float = float(preset["fork_angle"]) * (0.95 if depth == 0 else 1.05)

			for ci in range(n_children):
				var phi := az_offset + float(ci) * GOLDEN_ANGLE_RAD + rng.randf_range(-0.22, 0.22)
				var radial_out := (u_axis * cos(phi) + v_axis * sin(phi)).normalized()
				var pitch := fork_ang * rng.randf_range(0.75, 1.22)
				var child_dir := (cur_dir * cos(pitch) + radial_out * sin(pitch)).normalized()
				# Tuck child start slightly back along parent tip so joints never detach visually
				var child_start := tip_pos - cur_dir * minf(0.10, tip_r * 0.45)
				var child_r := maxf(0.015, tip_r * float(preset["radius_decay"]) * rng.randf_range(0.88, 1.06))
				var child_len := maxf(0.45, total_len * float(preset["length_decay"]) * rng.randf_range(0.82, 1.12))

				stack.append({
					"start": child_start,
					"dir": child_dir,
					"length": child_len,
					"r0": child_r,
					"depth": depth + 1,
					"parent_sway": tip_sway,
					"parent_flex": tip_flex,
				})
		elif depth < max_depth - 1:
			# Tip cutoff still spawns terminal foliage tuft
			twigs.append({
				"pos": tip_pos,
				"dir": cur_dir,
				"radius": tip_r,
				"depth": depth,
				"sway": tip_sway,
				"flex": tip_flex,
				"phase": rng.randf(),
			})
			canopy_acc += tip_pos
			canopy_w += 1.0

	var canopy_center: Vector3 = preset["canopy_center"]
	if canopy_w > 0.0:
		canopy_center = canopy_acc / canopy_w

	return {
		"segments": segments,
		"twigs": twigs,
		"max_height": max_y,
		"canopy_center": canopy_center,
	}


static func _build_bark_mesh(segments: Array, max_h: float, lod: int, preset: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var max_seg_depth: int = int(preset["max_depth"])
	if lod == 1:
		max_seg_depth = maxi(1, int(preset["max_depth"]) - 1)
	elif lod == 2:
		max_seg_depth = 1

	for seg in segments:
		var depth: int = int(seg["depth"])
		if depth > max_seg_depth:
			continue

		var pts: Array = seg["pts"]
		var radii: Array = seg["radii"]
		var sways: Array = seg["sway"]
		var flexes: Array = seg["flex"]
		var phase: float = float(seg["phase"])

		var ring_segs: int = 8 if (lod == 0 and depth == 0) else (6 if lod == 0 else (5 if lod == 1 else 4))
		if lod == 0 and depth >= 2:
			ring_segs = 5

		var rings: Array = []
		var ring_normals: Array = []
		var n_pts := pts.size()

		for pi in range(n_pts):
			var p: Vector3 = pts[pi]
			var tangent: Vector3
			if pi == 0:
				tangent = (pts[1] - pts[0]).normalized()
			elif pi == n_pts - 1:
				tangent = (pts[pi] - pts[pi - 1]).normalized()
			else:
				tangent = (pts[pi + 1] - pts[pi - 1]).normalized()

			var up_ref := Vector3.RIGHT if absf(tangent.y) > 0.92 else Vector3.UP
			var u_ax := tangent.cross(up_ref).normalized()
			var v_ax := tangent.cross(u_ax).normalized()
			var r_base: float = float(radii[pi])

			var ring_pts: Array[Vector3] = []
			var r_norms: Array[Vector3] = []
			for ri in range(ring_segs):
				var ang := float(ri) / float(ring_segs) * TAU
				var radial := u_ax * cos(ang) + v_ax * sin(ang)
				var flute: float = 1.0
				if depth == 0 and pi <= 1:
					var root_t: float = 1.0 - float(pi) * 0.65
					flute += 0.16 * root_t * cos(4.0 * ang + phase)
				ring_pts.append(p + radial * (r_base * flute))
				r_norms.append(radial.normalized())
			rings.append(ring_pts)
			ring_normals.append(r_norms)

		for pi in range(n_pts - 1):
			var r0: Array = rings[pi]
			var r1: Array = rings[pi + 1]
			var n0: Array = ring_normals[pi]
			var n1: Array = ring_normals[pi + 1]
			var v0: float = float(pi) * 0.5
			var v1: float = float(pi + 1) * 0.5

			var flex0: float = float(flexes[pi])
			var flex1: float = float(flexes[pi + 1])
			var sw0: float = clampf(float(sways[pi]), 0.0, 0.78)
			var sw1: float = clampf(float(sways[pi + 1]), 0.0, 0.78)
			if depth == 0 and pi == 0:
				sw0 = 0.0
				flex0 = 0.0

			var c0 := Color(sw0, flex0, 0.0, fmod(phase / TAU, 1.0))
			var c1 := Color(sw1, flex1, 0.0, fmod(phase / TAU, 1.0))

			for ri in range(ring_segs):
				var ni := (ri + 1) % ring_segs
				var u0 := float(ri) / float(ring_segs)
				var u1 := float(ri + 1) / float(ring_segs)

				_emit_bark_tri(st, r0[ri], r0[ni], r1[ri], n0[ri], n0[ni], n1[ri], c0, c0, c1, Vector2(u0, v0), Vector2(u1, v0), Vector2(u0, v1))
				_emit_bark_tri(st, r0[ni], r1[ni], r1[ri], n0[ni], n1[ni], n1[ri], c0, c1, c1, Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1))

	return st.commit()


static func _build_foliage_mesh(
	twigs: Array,
	canopy_center: Vector3,
	_max_h: float,
	lod: int,
	preset: Dictionary,
	rng: RandomNumberGenerator
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var base_leaf: float = float(preset["leaf_size"])
	var clusters_per_twig: int = int(preset["leaf_clusters"])
	var card_scale := 1.0
	var twig_step := 1
	if lod == 1:
		clusters_per_twig = maxi(2, clusters_per_twig - 2)
		card_scale = 1.38
	elif lod == 2:
		clusters_per_twig = 2
		twig_step = maxi(2, int(floor(float(twigs.size()) / 8.0)))
		card_scale = 2.15

	for ti in range(0, twigs.size(), twig_step):
		var tw: Dictionary = twigs[ti]
		var tw_pos: Vector3 = tw["pos"]
		var tw_dir: Vector3 = tw["dir"]
		var sw: float = float(tw["sway"])
		var fx: float = float(tw["flex"])
		var ph: float = float(tw["phase"])

		var sph_n := (tw_pos - canopy_center)
		if sph_n.length_squared() < 0.001:
			sph_n = Vector3.UP
		else:
			sph_n = (sph_n.normalized() + Vector3.UP * 0.25).normalized()

		for ci in range(clusters_per_twig):
			var az := float(ci) * GOLDEN_ANGLE_RAD + ph * TAU
			var spread := base_leaf * (0.28 if ci > 0 else 0.05)
			var up_jit := rng.randf_range(-0.18, 0.34)
			var offset := Vector3(cos(az) * spread, up_jit * base_leaf * 0.55, sin(az) * spread) + tw_dir * rng.randf_range(-0.08, 0.28)
			var c_pos := tw_pos + offset
			var c_size := base_leaf * card_scale * rng.randf_range(0.78, 1.24)
			var tilt_x := rng.randf_range(-0.55, 0.65)
			var tilt_z := rng.randf_range(-0.55, 0.55)
			var basis := Basis(Vector3.UP, az) * Basis(Vector3.RIGHT, tilt_x) * Basis(Vector3.FORWARD, tilt_z)
			var v_n := ((c_pos - canopy_center).normalized() + sph_n * 0.5 + Vector3.UP * 0.2).normalized()
			_emit_leaf_quad(st, c_pos, basis, c_size, sw, fx, ph, v_n)
			if lod == 0 and ci % 2 == 0:
				var cross_basis := basis * Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, 0.42)
				_emit_leaf_quad(st, c_pos, cross_basis, c_size * 0.92, sw, fx, ph, v_n)

	return st.commit()


static func _emit_bark_tri(
	st: SurfaceTool,
	p0: Vector3, p1: Vector3, p2: Vector3,
	n0: Vector3, n1: Vector3, n2: Vector3,
	c0: Color, c1: Color, c2: Color,
	uv0: Vector2, uv1: Vector2, uv2: Vector2
) -> void:
	st.set_color(c0)
	st.set_normal(n0)
	st.set_uv(uv0)
	st.add_vertex(p0)

	st.set_color(c1)
	st.set_normal(n1)
	st.set_uv(uv1)
	st.add_vertex(p1)

	st.set_color(c2)
	st.set_normal(n2)
	st.set_uv(uv2)
	st.add_vertex(p2)


static func _emit_leaf_quad(
	st: SurfaceTool,
	center: Vector3,
	basis: Basis,
	size: float,
	trunk_sway: float,
	limb_flex: float,
	phase: float,
	sph_normal: Vector3
) -> void:
	var hs := size * 0.5
	var right := basis.x * hs
	var up := basis.y * hs
	# Slight botanical leaf arch (camber) so quads never look flat edge-on
	var camber := basis.z * (hs * 0.14)

	var tl := center - right + up - camber
	var tr := center + right + up + camber
	var bl := center - right - up - camber
	var br := center + right - up - camber

	var c_base := Color(trunk_sway, limb_flex, 0.35, phase)
	var c_tip := Color(trunk_sway, limb_flex, 1.0, phase)

	var pts := [tl, tr, bl, tr, br, bl]
	var cols := [c_tip, c_tip, c_base, c_tip, c_base, c_base]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in range(6):
		st.set_color(cols[i])
		st.set_uv(uvs[i])
		st.set_normal(sph_normal)
		st.add_vertex(pts[i])
