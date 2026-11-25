class_name ParcelData
extends RefCounted

## City blocks, property parcels, zoning metadata, and 2D polygon/OBB geometry helpers.

class CityBlock:
	var id: int = -1
	var district_zone: String = "residential_hills"
	var raw_polygon: PackedVector2Array = PackedVector2Array()
	var buildable_polygon: PackedVector2Array = PackedVector2Array()
	var edge_road_ids: PackedInt32Array = PackedInt32Array()
	var edge_inset_dists: PackedFloat32Array = PackedFloat32Array()
	var center: Vector2 = Vector2.ZERO


class Parcel:
	var id: String = ""
	var block_id: int = -1
	var district_zone: String = "residential_hills"
	var polygon: PackedVector2Array = PackedVector2Array()
	var frontage_p0: Vector2 = Vector2.ZERO
	var frontage_p1: Vector2 = Vector2.ZERO
	var frontage_normal: Vector2 = Vector2(0, 1)
	var frontage_road_id: int = -1
	var frontage_road_t: float = 0.5
	var secondary_frontage_face: String = "" # "", "left", "right" relative to primary frontage
	var secondary_frontage_road_id: int = -1
	var sidewalk_elevation: float = 0.0
	var front_setback: float = 2.0
	var side_setback: float = 1.5
	var rear_setback: float = 1.5
	var is_park: bool = false
	var has_building: bool = false
	var chunk_coord: Vector2i = Vector2i.ZERO


static func ensure_ccw(poly: PackedVector2Array) -> PackedVector2Array:
	if poly.size() < 3:
		return poly
	if signed_area(poly) < 0.0:
		var rev := PackedVector2Array()
		for i in range(poly.size() - 1, -1, -1):
			rev.append(poly[i])
		return rev
	return poly


static func signed_area(poly: PackedVector2Array) -> float:
	var area := 0.0
	var n := poly.size()
	for i in range(n):
		var p0 := poly[i]
		var p1 := poly[(i + 1) % n]
		area += p0.x * p1.y - p1.x * p0.y
	return area * 0.5


static func polygon_centroid(poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in poly:
		sum += p
	return sum / float(poly.size())


static func point_in_convex_polygon(pt: Vector2, poly: PackedVector2Array, tolerance: float = 0.0) -> bool:
	var n := poly.size()
	if n < 3:
		return false
	for i in range(n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var edge := b - a
		var len_e := edge.length()
		if len_e < 0.0001:
			continue
		# For CCW polygon in (X, Z), inward left-hand normal is (-edge.y, edge.x).
		var inward := Vector2(-edge.y, edge.x) / len_e
		var d := (pt - a).dot(inward)
		if d < -tolerance:
			return false
	return true


static func min_edge_distance_in_convex_polygon(pt: Vector2, poly: PackedVector2Array) -> float:
	var n := poly.size()
	if n < 3:
		return -INF
	var min_d := INF
	for i in range(n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var edge := b - a
		var len_e := edge.length()
		if len_e < 0.0001:
			continue
		var inward := Vector2(-edge.y, edge.x) / len_e
		min_d = minf(min_d, (pt - a).dot(inward))
	return min_d


static func inset_convex_polygon_per_edge(poly: PackedVector2Array, edge_insets: PackedFloat32Array) -> PackedVector2Array:
	## Clips a CCW convex polygon inward by per-edge distances via Sutherland-Hodgman half-plane clipping.
	var n := poly.size()
	if n < 3 or edge_insets.size() != n:
		return PackedVector2Array()
	var current := poly
	for i in range(n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var edge := b - a
		var len_e := edge.length()
		if len_e < 0.001:
			continue
		var inward := Vector2(-edge.y, edge.x) / len_e
		var offset_pt := a + inward * edge_insets[i]
		current = _clip_poly_halfplane(current, offset_pt, inward)
		if current.size() < 3:
			return PackedVector2Array()
	return ensure_ccw(current)


static func _clip_poly_halfplane(poly: PackedVector2Array, plane_pt: Vector2, plane_normal: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	if n == 0:
		return out
	for i in range(n):
		var curr := poly[i]
		var nxt := poly[(i + 1) % n]
		var dc := (curr - plane_pt).dot(plane_normal)
		var dn := (nxt - plane_pt).dot(plane_normal)
		if dc >= 0.0:
			out.append(curr)
			if dn < 0.0:
				var t := dc / (dc - dn)
				out.append(curr.lerp(nxt, t))
		elif dn >= 0.0:
			var t := dc / (dc - dn)
			out.append(curr.lerp(nxt, t))
	return out


static func get_obb_corners(center: Vector2, half_extents: Vector2, yaw: float) -> PackedVector2Array:
	var right := Vector2(cos(yaw), -sin(yaw))
	var forward := Vector2(sin(yaw), cos(yaw))
	var r := right * half_extents.x
	var f := forward * half_extents.y
	return PackedVector2Array([
		center - r - f,
		center + r - f,
		center + r + f,
		center - r + f,
	])


static func obb_overlaps(c1: Vector2, he1: Vector2, yaw1: float, c2: Vector2, he2: Vector2, yaw2: float, margin: float = 0.0) -> bool:
	var max_span := he1.x + he1.y + he2.x + he2.y + absf(margin) * 3.0
	if absf(c1.x - c2.x) > max_span or absf(c1.y - c2.y) > max_span:
		return false
	var corners1 := get_obb_corners(c1, he1 + Vector2(margin, margin), yaw1)
	var corners2 := get_obb_corners(c2, he2 + Vector2(margin, margin), yaw2)
	var axes: Array[Vector2] = [
		Vector2(cos(yaw1), -sin(yaw1)),
		Vector2(sin(yaw1), cos(yaw1)),
		Vector2(cos(yaw2), -sin(yaw2)),
		Vector2(sin(yaw2), cos(yaw2)),
	]
	for axis in axes:
		var min1 := INF
		var max1 := -INF
		for p in corners1:
			var proj := p.dot(axis)
			min1 = minf(min1, proj)
			max1 = maxf(max1, proj)
		var min2 := INF
		var max2 := -INF
		for p in corners2:
			var proj := p.dot(axis)
			min2 = minf(min2, proj)
			max2 = maxf(max2, proj)
		if max1 <= min2 or max2 <= min1:
			return false
	return true
