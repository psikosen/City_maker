class_name RoadGraph
extends RefCounted

## Connected road, intersection, bridge, and vehicle lane graph.

class RoadNode:
	var id: int = -1
	var pos: Vector2 = Vector2.ZERO
	var elevation: float = 0.0
	var has_traffic_signal: bool = false
	var incident_edge_ids: Array[int] = []
	var miter_radius: float = 0.0
	var junction_polygon: PackedVector2Array = PackedVector2Array()
	var is_cul_de_sac: bool = false


class RoadEdge:
	var id: int = -1
	var node_a: int = -1
	var node_b: int = -1
	var road_class: String = "local" # arterial, collector, local, alley
	var street_name: String = ""
	var road_width: float = 7.5
	var sidewalk_width: float = 2.0
	var is_bridge: bool = false
	var bridge_start_t: float = 0.0
	var bridge_end_t: float = 0.0
	var trim_a: float = 0.0
	var trim_b: float = 0.0
	var samples: PackedVector3Array = PackedVector3Array()


class LaneSegment:
	var id: int = -1
	var edge_id: int = -1
	var start_node_id: int = -1
	var end_node_id: int = -1
	var direction: int = 1
	var lane_index: int = 0 # 0 = inner (left/passing), 1 = outer (right/curb/bus)
	var lane_count: int = 1 # Parallel lanes in this direction on the same edge
	var adjacent_lane_id: int = -1 # Parallel same-direction lane id for MOBIL lane changing
	var road_class: String = "local"
	var speed_limit: float = 13.9
	var points: PackedVector3Array = PackedVector3Array()
	var cum_lengths: PackedFloat32Array = PackedFloat32Array()
	var total_length: float = 0.0
	var next_lane_ids: PackedInt32Array = PackedInt32Array()
	var is_ns_axis: bool = false


var nodes: Array[RoadNode] = []
var edges: Array[RoadEdge] = []
var lanes: Array[LaneSegment] = []


func add_node(pos: Vector2) -> RoadNode:
	var n := RoadNode.new()
	n.id = nodes.size()
	n.pos = pos
	nodes.append(n)
	return n


func add_edge(node_a_id: int, node_b_id: int, road_class: String) -> RoadEdge:
	var e := RoadEdge.new()
	e.id = edges.size()
	e.node_a = node_a_id
	e.node_b = node_b_id
	e.road_class = road_class
	match road_class:
		"arterial":
			e.road_width = 12.0
			e.sidewalk_width = 3.0
		"collector":
			e.road_width = 9.0
			e.sidewalk_width = 2.4
		"local":
			e.road_width = 7.4
			e.sidewalk_width = 2.0
		"alley":
			e.road_width = 4.6
			e.sidewalk_width = 0.0
		_:
			e.road_width = 7.4
			e.sidewalk_width = 2.0
	edges.append(e)
	nodes[node_a_id].incident_edge_ids.append(e.id)
	nodes[node_b_id].incident_edge_ids.append(e.id)
	return e


func get_other_node(edge: RoadEdge, node_id: int) -> int:
	return edge.node_b if edge.node_a == node_id else edge.node_a


func is_graph_connected() -> bool:
	if nodes.is_empty():
		return false
	var visited := {}
	var queue: Array[int] = [0]
	visited[0] = true
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for eid in nodes[cur].incident_edge_ids:
			var e := edges[eid]
			var nxt := get_other_node(e, cur)
			if not visited.has(nxt):
				visited[nxt] = true
				queue.append(nxt)
	return visited.size() == nodes.size()


func sample_edge_point_3d(edge: RoadEdge, t: float) -> Vector3:
	if edge.samples.is_empty():
		var pa := nodes[edge.node_a].pos
		var pb := nodes[edge.node_b].pos
		var p := pa.lerp(pb, t)
		var y := lerpf(nodes[edge.node_a].elevation, nodes[edge.node_b].elevation, t)
		return Vector3(p.x, y, p.y)
	var ct := clampf(t, 0.0, 1.0)
	var fidx := ct * float(edge.samples.size() - 1)
	var i0 := int(floor(fidx))
	var i1 := mini(i0 + 1, edge.samples.size() - 1)
	var frac := fidx - float(i0)
	return edge.samples[i0].lerp(edge.samples[i1], frac)


func query_nearest_edge(pt: Vector2) -> Dictionary:
	var best_dist := INF
	var best_edge_id := -1
	var best_t := 0.0
	var best_pt3 := Vector3.ZERO
	for e in edges:
		var a := nodes[e.node_a].pos
		var b := nodes[e.node_b].pos
		var ab := b - a
		var len_sq := ab.length_squared()
		if len_sq < 0.0001:
			continue
		var t := clampf((pt - a).dot(ab) / len_sq, 0.0, 1.0)
		var proj := a + ab * t
		var d := pt.distance_to(proj)
		if d < best_dist:
			best_dist = d
			best_edge_id = e.id
			best_t = t
			best_pt3 = sample_edge_point_3d(e, t)
	if best_edge_id == -1:
		return {"valid": false}
	var edge := edges[best_edge_id]
	return {
		"valid": true,
		"dist": best_dist,
		"edge_id": best_edge_id,
		"t": best_t,
		"pos_3d": best_pt3,
		"half_road_w": edge.road_width * 0.5,
		"sidewalk_w": edge.sidewalk_width,
		"street_name": edge.street_name,
		"is_bridge": edge.is_bridge and best_t >= edge.bridge_start_t and best_t <= edge.bridge_end_t,
	}


func distance_to_road_corridor(pt: Vector2) -> float:
	var min_clearance := INF
	for e in edges:
		var a := nodes[e.node_a].pos
		var b := nodes[e.node_b].pos
		var closest := Geometry2D.get_closest_point_to_segment(pt, a, b)
		var d := pt.distance_to(closest) - (e.road_width * 0.5 + e.sidewalk_width)
		min_clearance = minf(min_clearance, d)
	return min_clearance


func compute_hash() -> String:
	var parts := PackedStringArray()
	for n in nodes:
		parts.append("N:%d,%.2f,%.2f,%.2f" % [n.id, n.pos.x, n.pos.y, n.elevation])
	for e in edges:
		parts.append("E:%d,%d-%d,%s,%s,%.2f,%.2f" % [e.id, e.node_a, e.node_b, e.road_class, e.street_name, e.bridge_start_t, e.bridge_end_t])
	var raw := "\n".join(parts)
	return raw.sha256_text().substr(0, 16)


static func compute_curb_fillet_pts(a_in: Vector2, ua: Vector2, b_in: Vector2, ub: Vector2, segs: int = 6) -> PackedVector2Array:
	## Computes a smooth cubic Bezier intersection curb fillet connecting a_in (tangent -ua) to b_in (tangent +ub).
	var pts := PackedVector2Array()
	var n_segs := maxi(1, segs)
	var det := (-ua.x) * (-ub.y) - (-ua.y) * (-ub.x)
	var chord := a_in.distance_to(b_in)
	var use_curve := false
	var ctrl_a := a_in
	var ctrl_b := b_in
	if absf(det) > 0.22 and chord > 0.65:
		var rhs := b_in - a_in
		var s := (rhs.x * (-ub.y) - rhs.y * (-ub.x)) / det
		var t := ((-ua.x) * rhs.y - (-ua.y) * rhs.x) / det
		if s > 0.35 and s < 14.0 and t > 0.35 and t < 14.0:
			var corner_pt := a_in - ua * s
			ctrl_a = a_in.lerp(corner_pt, 0.56)
			ctrl_b = b_in.lerp(corner_pt, 0.56)
			use_curve = true

	for i in range(n_segs + 1):
		var u := float(i) / float(n_segs)
		if use_curve:
			var om := 1.0 - u
			var pt := (om * om * om) * a_in + (3.0 * om * om * u) * ctrl_a + (3.0 * om * u * u) * ctrl_b + (u * u * u) * b_in
			pts.append(pt)
		else:
			pts.append(a_in.lerp(b_in, u))
	return pts
