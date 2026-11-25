class_name TerrainBuilder
extends RefCounted

## Builds per-chunk terrain visual meshes and matched HeightMapShape3D colliders,
## plus the creek water plane and distance-faded MultiMesh grass meadows.

static var _grass_tuft_mesh: ArrayMesh = null
static var _cached_index_map: Dictionary = {}


static func _get_chunk_indices(verts_per_side: int) -> PackedInt32Array:
	if _cached_index_map.has(verts_per_side):
		return _cached_index_map[verts_per_side]
	var quads := (verts_per_side - 1) * (verts_per_side - 1)
	var indices := PackedInt32Array()
	indices.resize(quads * 6)
	var ptr := 0
	for lz in range(verts_per_side - 1):
		var row0 := lz * verts_per_side
		var row1 := (lz + 1) * verts_per_side
		for lx in range(verts_per_side - 1):
			var i00 := row0 + lx
			var i10 := i00 + 1
			var i01 := row1 + lx
			var i11 := i01 + 1
			indices[ptr] = i00
			indices[ptr + 1] = i10
			indices[ptr + 2] = i01
			indices[ptr + 3] = i10
			indices[ptr + 4] = i11
			indices[ptr + 5] = i01
			ptr += 6
	_cached_index_map[verts_per_side] = indices
	return indices


static func build_terrain_chunk(
	terrain: TerrainData,
	cx: int,
	cz: int,
	chunk_size: float,
	mats: MaterialLibrary
) -> Node3D:
	var root := Node3D.new()
	root.name = "Terrain_%d_%d" % [cx, cz]

	var step := terrain.step_m
	var verts_per_side := int(round(chunk_size / step)) + 1
	var start_ix := int(round(float(cx) * chunk_size / step))
	var start_iz := int(round(float(cz) * chunk_size / step))

	# 1. Exact HeightMapShape3D physics collider centered on the chunk.
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var col := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = verts_per_side
	hm.map_depth = verts_per_side
	hm.map_data = terrain.get_chunk_heightmap_data(cx, cz, chunk_size)
	col.shape = hm
	body.position = Vector3((float(cx) + 0.5) * chunk_size, 0.0, (float(cz) + 0.5) * chunk_size)
	body.add_child(col)
	root.add_child(body)

	# 2. Matched indexed ArrayMesh using exact same vertex positions and diagonal split.
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	positions.resize(verts_per_side * verts_per_side)
	normals.resize(verts_per_side * verts_per_side)
	colors.resize(verts_per_side * verts_per_side)

	var h_arr := terrain.heights
	var gw := terrain.grid_w
	var gd := terrain.grid_d
	var w_lvl := terrain.water_level
	var two_step := 2.0 * step
	var c_grass := Color(0.22, 0.34, 0.16)
	var c_silt := Color(0.29, 0.26, 0.21)
	var c_ridge := Color(0.32, 0.38, 0.20)
	var c_rock := Color(0.38, 0.35, 0.31)

	for lz in range(verts_per_side):
		var gz := start_iz + lz
		var wz := float(gz) * step
		var c_gz := clampi(gz, 0, gd - 1)
		var cz_d := clampi(gz - 1, 0, gd - 1) * gw
		var cz_u := clampi(gz + 1, 0, gd - 1) * gw
		var row_g := c_gz * gw
		var row_out := lz * verts_per_side
		for lx in range(verts_per_side):
			var gx := start_ix + lx
			var wx := float(gx) * step
			var c_gx := clampi(gx, 0, gw - 1)
			var cx_l := clampi(gx - 1, 0, gw - 1)
			var cx_r := clampi(gx + 1, 0, gw - 1)
			var h := h_arr[row_g + c_gx]
			var idx := row_out + lx
			positions[idx] = Vector3(wx, h, wz)

			# Global finite-difference normal prevents lighting seams at chunk boundaries.
			var hl := h_arr[row_g + cx_l]
			var hr := h_arr[row_g + cx_r]
			var hd := h_arr[cz_d + c_gx]
			var hu := h_arr[cz_u + c_gx]
			var n := Vector3(hl - hr, two_step, hd - hu).normalized()
			normals[idx] = n

			var slope := 1.0 - n.y
			var col_v := c_grass
			if h < w_lvl + 0.35:
				col_v = c_silt
			elif h > 9.5:
				col_v = col_v.lerp(c_ridge, clampf((h - 9.5) / 6.0, 0.0, 0.8))
			if slope > 0.16:
				col_v = col_v.lerp(c_rock, clampf((slope - 0.16) / 0.35, 0.0, 0.85))
			var sand_f := terrain.get_beach_sand_factor(wx, wz)
			if sand_f > 0.01:
				col_v = col_v.lerp(Color(0.84, 0.77, 0.61), sand_f)
			colors[idx] = Color(col_v.r, col_v.g, col_v.b, sand_f)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = _get_chunk_indices(verts_per_side)

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = mesh
	mi.material_override = mats.terrain_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

	return root


static func build_horizon_skirt(terrain: TerrainData, mats: MaterialLibrary) -> MeshInstance3D:
	## Single-draw-call rolling outer horizon hills seamlessly stitched to the 0..size_m city perimeter.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var s := terrain.size_m
	var step_seg := 192
	var rings := [0.0, 56.0, 190.0, 480.0, 1050.0, 1950.0, 3100.0]
	var creek_n := terrain.creek_polyline[0] if not terrain.creek_polyline.is_empty() else Vector2(s * 0.5, 0.0)
	var creek_s := terrain.creek_polyline[terrain.creek_polyline.size() - 1] if not terrain.creek_polyline.is_empty() else Vector2(s * 0.5, s)

	var eval_pt := func(wx: float, wz: float, dist_out: float) -> Vector3:
		var cx := clampf(wx, 0.0, s)
		var cz := clampf(wz, 0.0, s)
		var h_edge := terrain.sample_height(cx, cz)
		if dist_out <= 0.01:
			return Vector3(wx, h_edge, wz)
		var t := clampf(dist_out / 190.0, 0.0, 1.0)
		var smooth_t := t * t * (3.0 - 2.0 * t)
		# Keep the South ocean floor submerged cleanly under the endless ocean horizon!
		if terrain.beach_enabled and wz >= terrain.get_beach_shore_z(clampf(wx, 0.0, s)) - 4.0:
			var sea_d := clampf((wz - terrain.beach_shore_z) / 360.0, 0.0, 1.0)
			var seabed_y := lerpf(terrain.water_level - 1.2, terrain.water_level - 14.5, sea_d)
			return Vector3(wx, minf(h_edge, lerpf(h_edge, seabed_y, smooth_t)), wz)
		var hills := 5.6 + (sin(wx * 0.0044 + 0.85) * cos(wz * 0.0041 - 0.35) * 0.5 + 0.5) * 19.0
		hills += sin(wx * 0.0115 - wz * 0.0088) * 4.2 + clampf((dist_out - 120.0) * 0.012, 0.0, 14.0)
		var creek_x := creek_n.x if wz < 0.0 else (creek_s.x if wz > s else -9999.0)
		if (wz < 0.0 or wz > s) and absf(wx - creek_x) < terrain.creek_half_width + 32.0:
			var dc := absf(wx - creek_x) / (terrain.creek_half_width + 32.0)
			hills = lerpf(terrain.water_level + 0.85, hills, dc * dc)
		# Taper East/West coastal hills gently down to ocean level near the south coast
		if terrain.beach_enabled and wz > terrain.beach_shore_z - 140.0:
			var coast_t := clampf((wz - (terrain.beach_shore_z - 140.0)) / 140.0, 0.0, 1.0)
			hills = lerpf(hills, terrain.water_level - 2.5, coast_t * coast_t)
		return Vector3(wx, lerpf(h_edge, hills, smooth_t), wz)

	var sides := [
		[-1, 0], # North (-Z)
		[1, 0],  # South (+Z)
		[0, -1], # West (-X)
		[0, 1],  # East (+X)
	]
	for sd in sides:
		var z_dir := int(sd[0])
		var x_dir := int(sd[1])
		for ri in range(rings.size() - 1):
			var r0 := float(rings[ri])
			var r1 := float(rings[ri + 1])
			for si in range(step_seg):
				var u0 := float(si) / float(step_seg)
				var u1 := float(si + 1) / float(step_seg)
				var p00: Vector3
				var p10: Vector3
				var p01: Vector3
				var p11: Vector3
				if z_dir != 0:
					var z0 := -r0 if z_dir < 0 else (s + r0)
					var z1 := -r1 if z_dir < 0 else (s + r1)
					p00 = eval_pt.call(lerpf(-r0, s + r0, u0), z0, r0)
					p10 = eval_pt.call(lerpf(-r0, s + r0, u1), z0, r0)
					p01 = eval_pt.call(lerpf(-r1, s + r1, u0), z1, r1)
					p11 = eval_pt.call(lerpf(-r1, s + r1, u1), z1, r1)
				else:
					var x0 := -r0 if x_dir < 0 else (s + r0)
					var x1 := -r1 if x_dir < 0 else (s + r1)
					p00 = eval_pt.call(x0, lerpf(-r0, s + r0, u0), r0)
					p10 = eval_pt.call(x0, lerpf(-r0, s + r0, u1), r0)
					p01 = eval_pt.call(x1, lerpf(-r1, s + r1, u0), r1)
					p11 = eval_pt.call(x1, lerpf(-r1, s + r1, u1), r1)

				var sand_r0 := 1.0 if (terrain.beach_enabled and (z_dir > 0 or p00.z > terrain.beach_shore_z - 70.0)) else 0.0
				var sand_r1 := 1.0 if (terrain.beach_enabled and (z_dir > 0 or p01.z > terrain.beach_shore_z - 70.0)) else 0.0
				var c_r0 := Color(0.22, 0.34, 0.16).lerp(Color(0.28, 0.35, 0.21), clampf(r0 / 500.0, 0.0, 0.85))
				var c_r1 := Color(0.22, 0.34, 0.16).lerp(Color(0.28, 0.35, 0.21), clampf(r1 / 500.0, 0.0, 0.85))
				c_r0.a = sand_r0
				c_r1.a = sand_r1
				var n_test := (p10 - p00).cross(p01 - p00)
				if n_test.y < 0.0:
					var qn := (-n_test).normalized()
					for item in [[p00, c_r0], [p10, c_r0], [p01, c_r1], [p10, c_r0], [p11, c_r1], [p01, c_r1]]:
						st.set_normal(qn if qn.y > 0.1 else Vector3.UP)
						st.set_color(item[1])
						st.add_vertex(item[0])
				else:
					var n_up := n_test.normalized()
					for item in [[p00, c_r0], [p01, c_r1], [p10, c_r0], [p10, c_r0], [p01, c_r1], [p11, c_r1]]:
						st.set_normal(n_up if n_up.y > 0.1 else Vector3.UP)
						st.set_color(item[1])
						st.add_vertex(item[0])

	var mi := MeshInstance3D.new()
	mi.name = "HorizonTerrainSkirt"
	mi.mesh = st.commit()
	mi.material_override = mats.terrain_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func build_creek_water(terrain: TerrainData, mats: MaterialLibrary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "CreekWater"
	if terrain.creek_polyline.size() < 2:
		return mi

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_w := terrain.creek_half_width + 2.6
	var y := terrain.water_level
	var max_coord := terrain.size_m - 1.0

	# Subdivide along-creek segments to ~4m resolution strictly inland of the ocean bay mouth
	var raw_pts: Array[Vector2] = []
	for p in terrain.creek_polyline:
		var max_z_creek := (terrain.get_beach_shore_z(p.x) - 18.0) if terrain.beach_enabled else (terrain.size_m - 1.5)
		if p.y >= 1.5 and p.y <= max_z_creek:
			raw_pts.append(Vector2(clampf(p.x, 1.5, max_coord - 0.5), clampf(p.y, 1.5, max_coord - 0.5)))
	if raw_pts.size() < 2:
		return mi

	var dense_pts: Array[Vector2] = [raw_pts[0]]
	for i in range(raw_pts.size() - 1):
		var a := raw_pts[i]
		var b := raw_pts[i + 1]
		var seg_l := a.distance_to(b)
		var sub := maxi(1, int(ceil(seg_l / 4.0)))
		for s in range(1, sub + 1):
			dense_pts.append(a.lerp(b, float(s) / float(sub)))

	const LATERAL_SEGS := 12
	var cols := LATERAL_SEGS + 1
	var grid_pos: Array[PackedVector3Array] = []
	var grid_uv: Array[PackedVector2Array] = []
	var grid_col: Array[PackedColorArray] = []
	var accum_dist := 0.0

	for i in range(dense_pts.size()):
		if i > 0:
			accum_dist += dense_pts[i - 1].distance_to(dense_pts[i])
		var p_prev := dense_pts[maxi(0, i - 1)]
		var p_next := dense_pts[mini(dense_pts.size() - 1, i + 1)]
		var tang := (p_next - p_prev).normalized()
		if tang.length_squared() < 0.25:
			tang = Vector2(0.0, 1.0)
		var side := Vector2(-tang.y, tang.x)
		var c := dense_pts[i]

		var row_pos := PackedVector3Array()
		var row_uv := PackedVector2Array()
		var row_col := PackedColorArray()
		row_pos.resize(cols)
		row_uv.resize(cols)
		row_col.resize(cols)
		for li in range(cols):
			var u := float(li) / float(LATERAL_SEGS) # 0 = +side (left), 1 = -side (right)
			var offset := lerpf(half_w, -half_w, u)
			var wx := clampf(c.x + side.x * offset, 0.5, max_coord)
			var wz := clampf(c.y + side.y * offset, 0.5, max_coord)
			var center_w := 1.0 - absf(u * 2.0 - 1.0)
			row_pos[li] = Vector3(wx, y, wz)
			row_uv[li] = Vector2(u, accum_dist * 0.06)
			row_col[li] = Color(tang.x * 0.5 + 0.5, tang.y * 0.5 + 0.5, center_w, 1.0)
		grid_pos.append(row_pos)
		grid_uv.append(row_uv)
		grid_col.append(row_col)

	for i in range(dense_pts.size() - 1):
		var r0 := grid_pos[i]
		var r1 := grid_pos[i + 1]
		var uv0 := grid_uv[i]
		var uv1 := grid_uv[i + 1]
		var c0 := grid_col[i]
		var c1 := grid_col[i + 1]
		for li in range(LATERAL_SEGS):
			var p00 := r0[li]
			var p10 := r0[li + 1]
			var p01 := r1[li]
			var p11 := r1[li + 1]
			for vert in [
				[p00, uv0[li], c0[li]],
				[p10, uv0[li + 1], c0[li + 1]],
				[p01, uv1[li], c1[li]],
				[p10, uv0[li + 1], c0[li + 1]],
				[p11, uv1[li + 1], c1[li + 1]],
				[p01, uv1[li], c1[li]],
			]:
				st.set_normal(Vector3.UP)
				st.set_uv(vert[1])
				st.set_color(vert[2])
				st.add_vertex(vert[0])

	mi.mesh = st.commit()
	mi.material_override = mats.water_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func build_ocean_water(terrain: TerrainData, mats: MaterialLibrary) -> MeshInstance3D:
	## Single-draw-call coastal ocean surface: high-density near-shore Gerstner surf mesh
	## stitched seamlessly to an endless southern ocean horizon sheet!
	var mi := MeshInstance3D.new()
	mi.name = "CoastalOceanWater"
	if not terrain.beach_enabled:
		return mi

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := terrain.size_m
	var y := terrain.water_level
	var z_start := terrain.beach_shore_z - 34.0

	# 1. High-resolution near-shore Gerstner surf zone (x in [-180..s+180], z in [z_start..s+140])
	var x0_hi := -180.0
	var x1_hi := s + 180.0
	var z1_hi := s + 140.0
	var nx_hi := 220
	var nz_hi := 48
	var dx_hi := (x1_hi - x0_hi) / float(nx_hi)
	var dz_hi := (z1_hi - z_start) / float(nz_hi)
	for iz in range(nz_hi):
		var za := z_start + float(iz) * dz_hi
		var zb := z_start + float(iz + 1) * dz_hi
		for ix in range(nx_hi):
			var xa := x0_hi + float(ix) * dx_hi
			var xb := x0_hi + float(ix + 1) * dx_hi
			var ea := clampf((za - (terrain.get_beach_shore_z(clampf(xa, 0.0, s)) - 4.0)) / 36.0, 0.16, 1.0)
			var eb := clampf((zb - (terrain.get_beach_shore_z(clampf(xa, 0.0, s)) - 4.0)) / 36.0, 0.16, 1.0)
			var ca := Color(ea, 0.0, 0.0, 1.0)
			var cb := Color(eb, 0.0, 0.0, 1.0)
			var p00 := Vector3(xa, y, za)
			var p10 := Vector3(xb, y, za)
			var p01 := Vector3(xa, y, zb)
			var p11 := Vector3(xb, y, zb)
			for v in [[p00, ca], [p10, ca], [p01, cb], [p10, ca], [p11, cb], [p01, cb]]:
				st.set_normal(Vector3.UP)
				st.set_color(v[1])
				st.add_vertex(v[0])

	# 2. Endless outer ocean horizon sheets (South offshore + East/West coastal wings to 3100m!)
	var far_rings := [z1_hi, s + 360.0, s + 850.0, s + 1750.0, s + 3100.0]
	var x_cols := [-3100.0, -1400.0, x0_hi, s * 0.25, s * 0.5, s * 0.75, x1_hi, s + 1400.0, s + 3100.0]
	var full_c := Color(1.0, 0.0, 0.0, 1.0)
	for ri in range(far_rings.size() - 1):
		var za := float(far_rings[ri])
		var zb := float(far_rings[ri + 1])
		for ci in range(x_cols.size() - 1):
			var xa := float(x_cols[ci])
			var xb := float(x_cols[ci + 1])
			for p in [Vector3(xa, y, za), Vector3(xb, y, za), Vector3(xa, y, zb), Vector3(xb, y, za), Vector3(xb, y, zb), Vector3(xa, y, zb)]:
				st.set_normal(Vector3.UP)
				st.set_color(full_c)
				st.add_vertex(p)
	# East & West coastal wing extensions aligned with the high-res surf band
	for wing_pair in [[-3100.0, x0_hi], [x1_hi, s + 3100.0]]:
		var xa := float(wing_pair[0])
		var xb := float(wing_pair[1])
		for p in [Vector3(xa, y, z_start), Vector3(xb, y, z_start), Vector3(xa, y, z1_hi), Vector3(xb, y, z_start), Vector3(xb, y, z1_hi), Vector3(xa, y, z1_hi)]:
			st.set_normal(Vector3.UP)
			st.set_color(full_c)
			st.add_vertex(p)

	mi.mesh = st.commit()
	mi.material_override = mats.ocean_water_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func build_underwater_fish_schools(plan: CityPlan) -> MultiMeshInstance3D:
	## Single-draw-call GPU-animated tropical reef fish schools orbiting pier pilings & coral reefs!
	var terrain := plan.terrain
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "UnderwaterFishSchools"
	if terrain == null or not terrain.beach_enabled:
		return mmi

	# 1. Build sleek 3D reef fish mesh (fusiform body + dorsal fin + forked tail fin along Z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nose := Vector3(0.0, 0.0, 0.24)
	var mid_t := Vector3(0.0, 0.085, 0.04)
	var mid_b := Vector3(0.0, -0.075, 0.04)
	var mid_l := Vector3(0.045, 0.0, 0.04)
	var mid_r := Vector3(-0.045, 0.0, 0.04)
	var tail_root := Vector3(0.0, 0.0, -0.14)
	# 4-sided diamond fusiform fish body
	for tri in [
		[nose, mid_t, mid_l, Vector3(0.7, 0.4, 0.5).normalized()],
		[nose, mid_b, mid_t, Vector3(1.0, 0.0, 0.2).normalized()],
		[nose, mid_l, mid_b, Vector3(0.7, -0.4, 0.5).normalized()],
		[nose, mid_r, mid_t, Vector3(-0.7, 0.4, 0.5).normalized()],
		[nose, mid_b, mid_r, Vector3(-0.7, -0.4, 0.5).normalized()],
		[mid_t, tail_root, mid_l, Vector3(0.8, 0.3, -0.4).normalized()],
		[mid_l, tail_root, mid_b, Vector3(0.8, -0.3, -0.4).normalized()],
		[mid_r, tail_root, mid_t, Vector3(-0.8, 0.3, -0.4).normalized()],
		[mid_b, tail_root, mid_r, Vector3(-0.8, -0.3, -0.4).normalized()],
	]:
		for vi in range(3):
			st.set_normal(tri[3])
			st.set_color(Color(1.0, 0.0, 0.0, 1.0))
			st.add_vertex(tri[vi])
	# Dorsal fin & forked caudal tail fin (double-sided)
	var dors_tip := Vector3(0.0, 0.14, -0.05)
	var tail_top := Vector3(0.0, 0.11, -0.26)
	var tail_bot := Vector3(0.0, -0.10, -0.26)
	for fin_tri in [
		[mid_t, dors_tip, tail_root, Vector3.RIGHT],
		[mid_t, tail_root, dors_tip, Vector3.LEFT],
		[tail_root, tail_top, tail_bot, Vector3.RIGHT],
		[tail_root, tail_bot, tail_top, Vector3.LEFT],
	]:
		for vi in range(3):
			st.set_normal(fin_tri[3])
			st.set_color(Color(0.0, 1.0, 0.0, 1.0))
			st.add_vertex(fin_tri[vi])
	var fish_mesh := st.commit()

	# 2. GPU Vertex-Animated School Orbit & Tail-Undulation Shader
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform float night_factor;
varying vec4 v_custom;
varying vec4 v_color;
varying float v_z;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_color = COLOR;
	v_z = VERTEX.z;
	float phase = INSTANCE_CUSTOM.r * 6.2831853;
	float orbit_r = max(1.5, INSTANCE_CUSTOM.g);
	float spd = INSTANCE_CUSTOM.b;
	float ang = TIME * spd + phase;
	// Traveling sinusoidal swimming body + tail wave
	float tail_factor = clamp((0.20 - VERTEX.z) * 2.4, 0.0, 1.2);
	vec3 local_v = VERTEX;
	local_v.x += sin(TIME * 11.5 + phase * 3.0 + VERTEX.z * 14.0) * 0.038 * tail_factor;
	// Circular reef orbit oriented along tangent direction
	vec3 tangent = normalize(vec3(cos(ang), sin(TIME * 1.4 + phase) * 0.08, -sin(ang)));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), tangent));
	vec3 up = cross(tangent, right);
	vec3 orbit_off = vec3(sin(ang) * orbit_r, sin(TIME * 1.4 + phase) * 0.22, cos(ang) * orbit_r);
	VERTEX = orbit_off + right * local_v.x + up * local_v.y + tangent * local_v.z;
	NORMAL = normalize(right * NORMAL.x + up * NORMAL.y + tangent * NORMAL.z);
}

void fragment() {
	float species = v_custom.a;
	vec3 body_c = vec3(0.96, 0.72, 0.12); // Golden reef angelfish
	vec3 stripe_c = vec3(0.10, 0.14, 0.22);
	if (species > 0.75) {
		body_c = vec3(0.12, 0.82, 0.94); // Neon cyan damselfish
		stripe_c = vec3(0.95, 0.86, 0.20);
	} else if (species > 0.50) {
		body_c = vec3(0.96, 0.36, 0.12); // Coral clownfish
		stripe_c = vec3(0.96, 0.97, 0.99);
	} else if (species > 0.25) {
		body_c = vec3(0.68, 0.82, 0.94); // Silver-blue coastal jack
		stripe_c = vec3(0.18, 0.44, 0.72);
	}
	float band = smoothstep(0.35, 0.65, sin(v_z * 32.0));
	vec3 col = mix(body_c, stripe_c, band * 0.65);
	if (v_color.g > 0.5) {
		col = mix(body_c, vec3(0.96, 0.88, 0.30), 0.55);
	}
	ALBEDO = col * (1.0 - night_factor * 0.65);
	EMISSION = col * 0.22;
	ROUGHNESS = 0.22;
	METALLIC = 0.45;
	SPECULAR = 0.88;
}
"""
	var fish_mat := ShaderMaterial.new()
	fish_mat.shader = sh

	# 3. Collect school centers around ocean piers & along the coastal coral reef belt
	var school_centers: Array[Vector3] = []
	for pr in plan.props:
		if String(pr.get("type", "")) == "beach_pier":
			var ppos: Vector3 = pr["pos"]
			var plen := float(pr.get("length", 74.0))
			var sz := terrain.get_beach_shore_z(ppos.x)
			for z_off: float in [16.0, 32.0, 48.0]:
				var fz := minf(terrain.size_m - 16.0, maxf(sz + z_off, ppos.z - plen * 0.15 + z_off * 0.6))
				for sx: float in [-7.5, 7.5]:
					var fx := ppos.x + sx
					var by := terrain.sample_height(fx, fz)
					if terrain.water_level - by >= 1.35:
						school_centers.append(Vector3(fx, clampf((by + terrain.water_level) * 0.5, by + 0.65, terrain.water_level - 0.65), fz))
	var s := terrain.size_m
	var scan_x := 180.0
	while scan_x <= s - 180.0:
		var sz := terrain.get_beach_shore_z(scan_x)
		var fz := minf(s - 18.0, sz + 34.0)
		var by := terrain.sample_height(scan_x, fz)
		if terrain.water_level - by >= 1.35:
			school_centers.append(Vector3(scan_x, clampf((by + terrain.water_level) * 0.5, by + 0.65, terrain.water_level - 0.65), fz))
		scan_x += 165.0

	if school_centers.is_empty():
		return mmi

	var fish_per_school := 14
	var total_fish := school_centers.size() * fish_per_school
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = fish_mesh
	mm.instance_count = total_fish

	var rng := RandomNumberGenerator.new()
	rng.seed = int(plan.config.world_seed) ^ 0x5F3759DF
	var idx := 0
	for sc_i in range(school_centers.size()):
		var c: Vector3 = school_centers[sc_i]
		var species_val := float(sc_i % 4) * 0.28 + 0.10
		var base_spd := rng.randf_range(0.42, 0.72) * (1.0 if sc_i % 2 == 0 else -1.0)
		for fi in range(fish_per_school):
			var f_scale := rng.randf_range(0.85, 1.35)
			var jitter := Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(-0.32, 0.32), rng.randf_range(-1.2, 1.2))
			var xf := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * f_scale), c + jitter)
			mm.set_instance_transform(idx, xf)
			mm.set_instance_custom_data(idx, Color(
				rng.randf(),
				rng.randf_range(2.4, 5.8),
				base_spd * rng.randf_range(0.92, 1.08),
				species_val
			))
			idx += 1

	mmi.multimesh = mm
	mmi.material_override = fish_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(0.0, -12.0, terrain.coast_road_z), Vector3(s, 20.0, s - terrain.coast_road_z + 120.0))
	return mmi


static func build_chunk_grass(
	plan: CityPlan,
	cx: int,
	cz: int,
	chunk_size: float,
	mats: MaterialLibrary
) -> MultiMeshInstance3D:
	var terrain := plan.terrain
	var road_graph := plan.road_graph
	var x0 := float(cx) * chunk_size
	var z0 := float(cz) * chunk_size
	var x1 := minf(x0 + chunk_size, terrain.size_m - 2.0)
	var z1 := minf(z0 + chunk_size, terrain.size_m - 2.0)
	var c_min := Vector2(x0, z0)
	var c_max := Vector2(x1, z1)

	# Bucket buildings overlapping or adjacent to this chunk for fast OBB yard filtering.
	var nearby_bps: Array[Dictionary] = []
	for bp in plan.blueprints:
		var r_pad := maxf(bp.width, bp.depth) * 0.72 + bp.approach_length + 1.5
		if bp.center.x + r_pad < c_min.x or bp.center.x - r_pad > c_max.x:
			continue
		if bp.center.y + r_pad < c_min.y or bp.center.y - r_pad > c_max.y:
			continue
		nearby_bps.append({
			"center": bp.center,
			"right": Vector2(cos(bp.yaw), -sin(bp.yaw)),
			"forward": Vector2(sin(bp.yaw), cos(bp.yaw)),
			"hx": bp.width * 0.5 + 0.95,
			"hz_back": bp.depth * 0.5 + 0.95,
			"hz_front": bp.depth * 0.5 + bp.approach_length + 1.0,
		})

	var nearby_edges: Array[Dictionary] = []
	for e in road_graph.edges:
		var pa := road_graph.nodes[e.node_a].pos
		var pb := road_graph.nodes[e.node_b].pos
		var corr := e.road_width * 0.5 + e.sidewalk_width + 2.0
		if maxf(pa.x, pb.x) + corr < c_min.x or minf(pa.x, pb.x) - corr > c_max.x:
			continue
		if maxf(pa.y, pb.y) + corr < c_min.y or minf(pa.y, pb.y) - corr > c_max.y:
			continue
		nearby_edges.append({
			"a": pa,
			"b": pb,
			"half_corr": e.road_width * 0.5 + e.sidewalk_width,
		})

	var rng := RandomNumberGenerator.new()
	rng.seed = int(plan.config.world_seed) + cx * 73856093 + cz * 19349663

	var transforms: Array[Transform3D] = []
	var spacing := 1.25 if terrain.size_m >= 2000.0 else 1.05
	var gx := maxf(2.5, x0 + 0.8)
	while gx < x1 - 0.5:
		var gz := maxf(2.5, z0 + 0.8)
		while gz < z1 - 0.5:
			var wx := gx + rng.randf_range(-0.38, 0.38)
			var wz := gz + rng.randf_range(-0.38, 0.38)
			# Broad organic meadow drifts + residential lawn patches
			var patch_val := sin(wx * 0.07 + wz * 0.05) * 0.55 + cos(wx * 0.11 - wz * 0.09) * 0.45
			if patch_val > -0.22 and terrain.get_beach_sand_factor(wx, wz) < 0.35:
				var h := terrain.sample_height(wx, wz)
				if h > terrain.water_level + 0.70:
					var hl := terrain.sample_height(wx - 0.9, wz)
					var hr := terrain.sample_height(wx + 0.9, wz)
					var hd := terrain.sample_height(wx, wz - 0.9)
					var hu := terrain.sample_height(wx, wz + 0.9)
					var slope := 1.0 - Vector3(hl - hr, 1.8, hd - hu).normalized().y
					if slope < 0.17:
						var p2 := Vector2(wx, wz)
						if not _point_near_any_road(p2, nearby_edges, 1.05) and not _point_inside_any_building(p2, nearby_bps):
							var s := rng.randf_range(0.85, 1.35)
							var yaw := rng.randf_range(0.0, TAU)
							var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s * rng.randf_range(0.80, 1.15), s))
							transforms.append(Transform3D(basis, Vector3(wx, h - 0.02, wz)))
			gz += spacing
		gx += spacing

	if transforms.is_empty():
		return null

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _get_grass_tuft_mesh()
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GrassMultiMesh_%d_%d" % [cx, cz]
	mmi.multimesh = mm
	mmi.material_override = mats.grass_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 74.0
	mmi.visibility_range_end_margin = 12.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return mmi


static func _point_near_any_road(pt: Vector2, edges: Array[Dictionary], min_clear: float) -> bool:
	for ed in edges:
		var a: Vector2 = ed["a"]
		var b: Vector2 = ed["b"]
		var closest := Geometry2D.get_closest_point_to_segment(pt, a, b)
		if pt.distance_to(closest) - float(ed["half_corr"]) < min_clear:
			return true
	return false


static func _point_inside_any_building(pt: Vector2, boxes: Array[Dictionary]) -> bool:
	for b in boxes:
		var d: Vector2 = pt - b["center"]
		var lx: float = d.dot(b["right"])
		if absf(lx) > float(b["hx"]):
			continue
		var lz: float = d.dot(b["forward"])
		if lz >= -float(b["hz_back"]) and lz <= float(b["hz_front"]):
			return true
	return false


static func _get_grass_tuft_mesh() -> ArrayMesh:
	if _grass_tuft_mesh != null:
		return _grass_tuft_mesh

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 9 slim curved grass blades per tuft clump so lawns look soft rather than spiky
	for bi in range(9):
		var ang := float(bi) * 0.72 + 0.19
		var rad := 0.06 + float(bi % 3) * 0.075
		var off_x := cos(ang * 1.6) * rad
		var off_z := sin(ang * 1.6) * rad
		var ca := cos(ang)
		var sa := sin(ang)
		var w0 := 0.015
		var h_max := 0.16 + (float(bi % 3) * 0.038)
		var lean := 0.082

		var p0_l := Vector3(off_x - ca * w0, 0.0, off_z - sa * w0)
		var p0_r := Vector3(off_x + ca * w0, 0.0, off_z + sa * w0)
		var p1_l := Vector3(off_x - ca * w0 * 0.52 + sa * lean * 0.42, h_max * 0.55, off_z - sa * w0 * 0.52 - ca * lean * 0.42)
		var p1_r := Vector3(off_x + ca * w0 * 0.52 + sa * lean * 0.42, h_max * 0.55, off_z + sa * w0 * 0.52 - ca * lean * 0.42)
		var p2_t := Vector3(off_x + sa * lean, h_max, off_z - ca * lean)

		var n := Vector3(sa * 0.45, 0.88, -ca * 0.45).normalized()
		var c0 := Color(0.0, 0.0, 0.0, 1.0)
		var c1 := Color(0.55, 0.0, 0.0, 1.0)
		var c2 := Color(1.0, 0.0, 0.0, 1.0)

		for tri in [
			[p0_l, p0_r, p1_l, c0, c0, c1],
			[p0_r, p1_r, p1_l, c0, c1, c1],
			[p1_l, p1_r, p2_t, c1, c1, c2],
		]:
			for k in range(3):
				st.set_color(tri[k + 3])
				st.set_normal(n)
				st.add_vertex(tri[k])

	_grass_tuft_mesh = st.commit()
	return _grass_tuft_mesh
