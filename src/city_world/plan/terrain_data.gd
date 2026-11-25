class_name TerrainData
extends RefCounted

## Authoritative terrain heightfield and hydrological features for the city plan.
var size_m: float = 2304.0
var step_m: float = 1.0
var grid_w: int = 2305
var grid_d: int = 2305
var heights: PackedFloat32Array = PackedFloat32Array()
var water_level: float = 1.2
var creek_polyline: PackedVector2Array = PackedVector2Array()
var creek_half_width: float = 22.0
var beach_enabled: bool = true
var beach_shore_z: float = 2138.0
var beach_phase: float = 0.0
var coast_road_z: float = 2022.0


func get_beach_shore_z(wx: float) -> float:
	if not beach_enabled:
		return size_m + 500.0
	return beach_shore_z + sin(wx * 0.0042 + beach_phase) * 16.0 + cos(wx * 0.0105 - beach_phase * 0.6) * 7.0


func get_beach_sand_factor(wx: float, wz: float) -> float:
	if not beach_enabled:
		return 0.0
	var sz := get_beach_shore_z(wx)
	# Smoothly blend from grass to golden sand starting just south of OCEANFRONT BLVD (sz - 96m -> sz - 56m)
	return clampf((wz - (sz - 96.0)) / 40.0, 0.0, 1.0)


func is_in_beach_zone(wx: float, wz: float) -> bool:
	return beach_enabled and wz > get_beach_shore_z(wx) - 104.0


func initialize(p_size_m: float, p_step_m: float) -> void:
	size_m = p_size_m
	step_m = p_step_m
	grid_w = int(round(size_m / step_m)) + 1
	grid_d = int(round(size_m / step_m)) + 1
	heights.resize(grid_w * grid_d)
	heights.fill(0.0)


func get_vertex_height(ix: int, iz: int) -> float:
	var cx := clampi(ix, 0, grid_w - 1)
	var cz := clampi(iz, 0, grid_d - 1)
	return heights[cz * grid_w + cx]


func set_vertex_height(ix: int, iz: int, h: float) -> void:
	if ix < 0 or ix >= grid_w or iz < 0 or iz >= grid_d:
		return
	heights[iz * grid_w + ix] = h


func sample_height(x: float, z: float) -> float:
	## Exact barycentric interpolation matching Godot HeightMapShape3D diagonal (1,0)-(0,1).
	var gx := clampf(x / step_m, 0.0, float(grid_w - 1) - 0.0001)
	var gz := clampf(z / step_m, 0.0, float(grid_d - 1) - 0.0001)
	var ix := int(floor(gx))
	var iz := int(floor(gz))
	var fx := gx - float(ix)
	var fz := gz - float(iz)

	var h00 := get_vertex_height(ix, iz)
	var h10 := get_vertex_height(ix + 1, iz)
	var h01 := get_vertex_height(ix, iz + 1)
	var h11 := get_vertex_height(ix + 1, iz + 1)

	if fx + fz <= 1.0:
		return h00 + fx * (h10 - h00) + fz * (h01 - h00)
	var u := 1.0 - fx
	var v := 1.0 - fz
	return h11 + u * (h01 - h11) + v * (h10 - h11)


func sample_slope(x: float, z: float) -> float:
	var d := step_m
	var hx0 := sample_height(x - d, z)
	var hx1 := sample_height(x + d, z)
	var hz0 := sample_height(x, z - d)
	var hz1 := sample_height(x, z + d)
	var dx := (hx1 - hx0) / (2.0 * d)
	var dz := (hz1 - hz0) / (2.0 * d)
	return sqrt(dx * dx + dz * dz)


func sample_min_max_in_obb(center: Vector2, half_extents: Vector2, yaw: float) -> Vector2:
	var right := Vector2(cos(yaw), -sin(yaw))
	var forward := Vector2(sin(yaw), cos(yaw))
	var min_y := INF
	var max_y := -INF
	var steps_x := maxi(2, int(ceil(half_extents.x * 2.0 / 2.0)))
	var steps_z := maxi(2, int(ceil(half_extents.y * 2.0 / 2.0)))
	for sx in range(steps_x + 1):
		var tx := lerpf(-half_extents.x, half_extents.x, float(sx) / float(steps_x))
		for sz in range(steps_z + 1):
			var tz := lerpf(-half_extents.y, half_extents.y, float(sz) / float(steps_z))
			var pt := center + right * tx + forward * tz
			var h := sample_height(pt.x, pt.y)
			min_y = minf(min_y, h)
			max_y = maxf(max_y, h)
	return Vector2(min_y, max_y)


func distance_to_creek(pt: Vector2) -> float:
	var n := creek_polyline.size()
	if n < 2:
		return INF
	var approx_i := clampi(int(round((pt.y + 8.0) / 8.0)), 0, n - 2)
	var lo := maxi(0, approx_i - 10)
	var hi := mini(n - 2, approx_i + 10)
	var min_d := INF
	for i in range(lo, hi + 1):
		var closest := Geometry2D.get_closest_point_to_segment(pt, creek_polyline[i], creek_polyline[i + 1])
		min_d = minf(min_d, pt.distance_to(closest))
	if min_d <= 64.0:
		return min_d
	for i in range(0, lo):
		var closest := Geometry2D.get_closest_point_to_segment(pt, creek_polyline[i], creek_polyline[i + 1])
		min_d = minf(min_d, pt.distance_to(closest))
	for i in range(hi + 1, n - 1):
		var closest := Geometry2D.get_closest_point_to_segment(pt, creek_polyline[i], creek_polyline[i + 1])
		min_d = minf(min_d, pt.distance_to(closest))
	return min_d


func get_chunk_heightmap_data(chunk_x: int, chunk_z: int, chunk_size: float) -> PackedFloat32Array:
	var verts_per_side := int(round(chunk_size / step_m)) + 1
	var start_ix := int(round(float(chunk_x) * chunk_size / step_m))
	var start_iz := int(round(float(chunk_z) * chunk_size / step_m))
	var out := PackedFloat32Array()
	out.resize(verts_per_side * verts_per_side)
	for lz in range(verts_per_side):
		for lx in range(verts_per_side):
			out[lz * verts_per_side + lx] = get_vertex_height(start_ix + lx, start_iz + lz)
	return out


func compute_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var buf := PackedInt32Array()
	buf.append(grid_w)
	buf.append(grid_d)
	buf.append(int(round(creek_half_width * 100.0)))
	buf.append(int(round(water_level * 100.0)))
	var total := heights.size()
	if total > 0:
		var stride := maxi(1, total / 65536)
		var idx := 0
		while idx < total:
			buf.append(int(round(heights[idx] * 1000.0)))
			idx += stride
	ctx.update(buf.to_byte_array())
	return ctx.finish().hex_encode().substr(0, 16)
