class_name NPCScheduler
extends RefCounted

## Builds a connected citywide PedestrianGraph (sidewalks, crosswalks, park greenways,
## creek footbridges, building door anchors, transit shelters & plaza smart-objects),
## provides cached bounded A* pedestrian routing, and generates a deterministic roster
## of procedural citizens with 24-hour staggered daily schedules.

const BP_CELL_SIZE := 64.0
const NODE_CELL_SIZE := 32.0
const TARGET_CITIZEN_COUNT := 1040

# Citizen Roles
const ROLE_OFFICE := 0
const ROLE_RETAIL := 1
const ROLE_STUDENT := 2
const ROLE_MEDIC := 3
const ROLE_INDUSTRIAL := 4
const ROLE_RESIDENT := 5
const ROLE_NIGHT_SHIFT := 6

# Anchor Categories
const ANCHOR_HOME := 0
const ANCHOR_OFFICE := 1
const ANCHOR_SCHOOL := 2
const ANCHOR_HOSPITAL := 3
const ANCHOR_RETAIL := 4
const ANCHOR_DINING := 5
const ANCHOR_INDUSTRIAL := 6
const ANCHOR_CIVIC := 7
const ANCHOR_PARK_PLAZA := 8
const ANCHOR_BUS_STOP := 9

# Daily Activity Types
const ACT_INDOORS := 0
const ACT_TRAVEL := 1
const ACT_LINGER_OUTDOOR := 2
const ACT_BUS_WAIT := 3

const FIRST_NAMES := [
	"Maya", "Liam", "Sofia", "Noah", "Elena", "Marcus", "Chloe", "Mateo",
	"Priya", "Owen", "Nadia", "Caleb", "Hana", "Julian", "Amara", "Leo",
	"Clara", "Devon", "Tessa", "Isaac", "Aisha", "Nolan", "Sienna", "Samir",
]

const LAST_NAMES := [
	"Morales", "Chen", "Patel", "Brooks", "Kim", "Rivera", "Okafor", "Bennett",
	"Sato", "Alvarez", "Foster", "Nguyen", "Reed", "Gomez", "Kowalski", "Park",
	"Ramirez", "Hayes", "Singh", "Campbell", "Ortiz", "Walsh", "Lin", "Vargas",
]


class PedNode:
	var id: int = -1
	var pos: Vector3 = Vector3.ZERO
	var kind: String = "sidewalk" # sidewalk, park, footbridge
	var edge_ids: PackedInt32Array = PackedInt32Array()


class PedEdge:
	var id: int = -1
	var node_a: int = -1
	var node_b: int = -1
	var points: PackedVector3Array = PackedVector3Array()
	var cum_lengths: PackedFloat32Array = PackedFloat32Array()
	var total_length: float = 0.0
	var is_crosswalk: bool = false
	var signal_node_id: int = -1
	var crosses_ns_traffic: bool = false
	var kind: String = "sidewalk" # sidewalk, crosswalk, park, footbridge


class Anchor:
	var id: int = -1
	var category: int = ANCHOR_HOME
	var node_id: int = -1
	var pos: Vector3 = Vector3.ZERO
	var facing: Vector3 = Vector3(0.0, 0.0, 1.0)
	var building_id: String = ""
	var venue_type: String = ""
	var is_outdoor: bool = false


class ScheduleSlot:
	var start_h: float = 0.0
	var end_h: float = 24.0
	var activity: int = ACT_INDOORS
	var anchor_id: int = -1
	var label: String = "home"


class CitizenProfile:
	var id: int = -1
	var display_name: String = ""
	var role: int = ROLE_RESIDENT
	var walk_speed: float = 1.35
	var body_scale: float = 1.0
	var palette_seed: float = 0.5
	var umbrella_seed: float = 0.5
	var has_bag: bool = false
	var uses_bus: bool = false
	var home_anchor_id: int = -1
	var work_anchor_id: int = -1
	var lunch_anchor_id: int = -1
	var leisure_anchor_id: int = -1
	var home_bus_anchor_id: int = -1
	var work_bus_anchor_id: int = -1
	var schedule: Array[ScheduleSlot] = []


var nodes: Array[PedNode] = []
var edges: Array[PedEdge] = []
var anchors: Array[Anchor] = []
var anchors_by_cat: Dictionary = {} # int category -> Array[int]
var citizens: Array[CitizenProfile] = []

var _plan: CityPlan = null
var _bp_grid: Dictionary = {}
var _node_grid: Dictionary = {} # Vector2i -> Array[int]
var _path_cache: Dictionary = {} # String "a_b" -> Array[Dictionary]
var _crosswalk_edge_count: int = 0
var _park_edge_count: int = 0


func build(p_plan: CityPlan) -> void:
	nodes.clear()
	edges.clear()
	anchors.clear()
	anchors_by_cat.clear()
	citizens.clear()
	_bp_grid.clear()
	_node_grid.clear()
	_path_cache.clear()
	_crosswalk_edge_count = 0
	_park_edge_count = 0

	_plan = p_plan
	if _plan == null or _plan.terrain == null or _plan.road_graph == null:
		return

	_build_bp_grid()
	_build_pedestrian_graph()
	if nodes.is_empty() or edges.is_empty():
		return
	_build_anchors()
	_generate_citizens()


func get_crosswalk_edge_count() -> int:
	return _crosswalk_edge_count


func get_park_edge_count() -> int:
	return _park_edge_count


func evaluate_citizen_slot(c: CitizenProfile, hour: float) -> Dictionary:
	## Returns {slot_idx, slot, prev_anchor_id, progress} for any 24h clock value.
	var h := fposmod(hour, 24.0)
	var cnt := c.schedule.size()
	if cnt == 0:
		return {"slot_idx": 0, "slot": null, "prev_anchor_id": c.home_anchor_id, "progress": 0.0}
	for si in range(cnt):
		var sl := c.schedule[si]
		if h >= sl.start_h and h < sl.end_h:
			var prev_sl := c.schedule[posmod(si - 1, cnt)]
			var span := maxf(0.01, sl.end_h - sl.start_h)
			return {
				"slot_idx": si,
				"slot": sl,
				"prev_anchor_id": prev_sl.anchor_id,
				"progress": clampf((h - sl.start_h) / span, 0.0, 1.0),
			}
	var last_sl := c.schedule[cnt - 1]
	return {
		"slot_idx": cnt - 1,
		"slot": last_sl,
		"prev_anchor_id": c.schedule[maxi(0, cnt - 2)].anchor_id,
		"progress": 0.5,
	}


func find_edge_path(start_node_id: int, goal_node_id: int, max_expansions: int = 260) -> Array[Dictionary]:
	## Bounded A* returning ordered Array[{edge_id: int, dir: int}] from start_node_id to goal_node_id.
	var empty: Array[Dictionary] = []
	if start_node_id < 0 or goal_node_id < 0 or start_node_id >= nodes.size() or goal_node_id >= nodes.size():
		return empty
	if start_node_id == goal_node_id:
		return empty

	var cache_key := "%d_%d" % [start_node_id, goal_node_id]
	if _path_cache.has(cache_key):
		return _path_cache[cache_key]

	var goal_pos := nodes[goal_node_id].pos
	var open_nodes: Array[int] = [start_node_id]
	var g_score: Dictionary = {start_node_id: 0.0}
	var f_score: Dictionary = {start_node_id: nodes[start_node_id].pos.distance_to(goal_pos)}
	var came_from: Dictionary = {} # node_id -> [prev_node_id, edge_id, dir]
	var closed: Dictionary = {}

	var best_node := start_node_id
	var best_h := nodes[start_node_id].pos.distance_to(goal_pos)
	var expansions := 0
	var reached := false

	while not open_nodes.is_empty() and expansions < max_expansions:
		# Pick lowest f_score in open list (small active frontier <= ~80 nodes)
		var best_i := 0
		var best_f := float(f_score.get(open_nodes[0], INF))
		for oi in range(1, open_nodes.size()):
			var f_v := float(f_score.get(open_nodes[oi], INF))
			if f_v < best_f:
				best_f = f_v
				best_i = oi
		var cur: int = open_nodes[best_i]
		open_nodes[best_i] = open_nodes[open_nodes.size() - 1]
		open_nodes.pop_back()

		if cur == goal_node_id:
			reached = true
			best_node = cur
			break
		if closed.has(cur):
			continue
		closed[cur] = true
		expansions += 1

		var cur_h := nodes[cur].pos.distance_to(goal_pos)
		if cur_h < best_h:
			best_h = cur_h
			best_node = cur

		var cur_g := float(g_score[cur])
		var cur_node := nodes[cur]
		for eid in cur_node.edge_ids:
			var ed := edges[eid]
			var nxt := ed.node_b if ed.node_a == cur else ed.node_a
			if closed.has(nxt):
				continue
			var dir_v := 1 if ed.node_a == cur else -1
			# Slight preference for park walkways & mild penalty on signalized crossings
			var cost := ed.total_length
			if ed.is_crosswalk:
				cost += 5.0
			elif ed.kind == "park" or ed.kind == "footbridge":
				cost *= 0.92
			var tent_g := cur_g + cost
			if tent_g < float(g_score.get(nxt, INF)):
				came_from[nxt] = [cur, eid, dir_v]
				g_score[nxt] = tent_g
				f_score[nxt] = tent_g + nodes[nxt].pos.distance_to(goal_pos)
				if not (nxt in open_nodes):
					open_nodes.append(nxt)

	var end_target := goal_node_id if reached else best_node
	var path: Array[Dictionary] = []
	var walk_n := end_target
	var guard := 0
	while walk_n != start_node_id and came_from.has(walk_n) and guard < 180:
		var info: Array = came_from[walk_n]
		path.append({"edge_id": int(info[1]), "dir": int(info[2])})
		walk_n = int(info[0])
		guard += 1
	path.reverse()

	if _path_cache.size() < 2400:
		_path_cache[cache_key] = path
	return path


func get_fallback_walk_path(start_node_id: int, salt: int) -> Array[Dictionary]:
	## Returns a 2-to-4 edge local neighborhood stroll starting at start_node_id.
	var out: Array[Dictionary] = []
	if start_node_id < 0 or start_node_id >= nodes.size():
		return out
	var cur := start_node_id
	var prev_eid := -1
	for step_i in range(3):
		var n := nodes[cur]
		if n.edge_ids.is_empty():
			break
		var chosen_eid := n.edge_ids[posmod(salt + step_i * 7, n.edge_ids.size())]
		if chosen_eid == prev_eid and n.edge_ids.size() > 1:
			chosen_eid = n.edge_ids[posmod(salt + step_i * 7 + 1, n.edge_ids.size())]
		var ed := edges[chosen_eid]
		var dir_v := 1 if ed.node_a == cur else -1
		out.append({"edge_id": chosen_eid, "dir": dir_v})
		cur = ed.node_b if dir_v == 1 else ed.node_a
		prev_eid = chosen_eid
	return out


func _build_bp_grid() -> void:
	for bp in _plan.blueprints:
		var r_pad := maxf(bp.width, bp.depth) * 0.72 + 1.5
		var cx0 := int(floor((bp.center.x - r_pad) / BP_CELL_SIZE))
		var cx1 := int(floor((bp.center.x + r_pad) / BP_CELL_SIZE))
		var cz0 := int(floor((bp.center.y - r_pad) / BP_CELL_SIZE))
		var cz1 := int(floor((bp.center.y + r_pad) / BP_CELL_SIZE))
		for cz in range(cz0, cz1 + 1):
			for cx in range(cx0, cx1 + 1):
				var key := Vector2i(cx, cz)
				var arr: Array
				if _bp_grid.has(key):
					arr = _bp_grid[key]
				else:
					arr = []
					_bp_grid[key] = arr
				arr.append(bp)


func _is_outside_buildings(pt2: Vector2, margin: float) -> bool:
	var key := Vector2i(int(floor(pt2.x / BP_CELL_SIZE)), int(floor(pt2.y / BP_CELL_SIZE)))
	if not _bp_grid.has(key):
		return true
	for bp_v in _bp_grid[key]:
		var bp: BuildingBlueprint = bp_v
		var dx := pt2.x - bp.center.x
		var dz := pt2.y - bp.center.y
		var cy := cos(bp.yaw)
		var sy := sin(bp.yaw)
		var lx := absf(dx * cy - dz * sy)
		var lz := absf(dx * sy + dz * cy)
		if lx < bp.width * 0.5 + margin and lz < bp.depth * 0.5 + margin:
			return false
	return true


func _is_safe_park_point(pt2: Vector2, terrain: TerrainData) -> float:
	var ws := _plan.config.world_size
	if pt2.x < 16.0 or pt2.x > ws - 16.0 or pt2.y < 16.0 or pt2.y > ws - 16.0:
		return -INF
	if terrain.distance_to_creek(pt2) < terrain.creek_half_width + 1.2:
		return -INF
	var hy := terrain.sample_height(pt2.x, pt2.y)
	if hy < terrain.water_level + 0.35:
		return -INF
	if not _is_outside_buildings(pt2, 0.70):
		return -INF
	return hy + 0.05


func _get_or_add_node(pos: Vector3, kind: String, merge_radius: float = 2.4) -> int:
	var gx := int(floor(pos.x / NODE_CELL_SIZE))
	var gz := int(floor(pos.z / NODE_CELL_SIZE))
	var mr2 := merge_radius * merge_radius
	var best_id := -1
	var best_d2 := mr2
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var k := Vector2i(gx + ox, gz + oz)
			if not _node_grid.has(k):
				continue
			for nid_var in _node_grid[k]:
				var nid: int = nid_var
				var np := nodes[nid].pos
				var dx := np.x - pos.x
				var dz := np.z - pos.z
				var dy := absf(np.y - pos.y)
				var d2 := dx * dx + dz * dz
				if d2 < best_d2 and dy < 1.2:
					best_d2 = d2
					best_id = nid
	if best_id != -1:
		return best_id

	var n := PedNode.new()
	n.id = nodes.size()
	n.pos = pos
	n.kind = kind
	nodes.append(n)
	var cell := Vector2i(gx, gz)
	var arr: Array = _node_grid.get(cell, [])
	arr.append(n.id)
	_node_grid[cell] = arr
	return n.id


func _find_nearest_node(pt2: Vector2, max_dist: float = 48.0, pref_kind: String = "") -> int:
	var gx := int(floor(pt2.x / NODE_CELL_SIZE))
	var gz := int(floor(pt2.y / NODE_CELL_SIZE))
	var span := maxi(1, int(ceil(max_dist / NODE_CELL_SIZE)))
	var best_id := -1
	var best_d2 := max_dist * max_dist
	for oz in range(-span, span + 1):
		for ox in range(-span, span + 1):
			var k := Vector2i(gx + ox, gz + oz)
			if not _node_grid.has(k):
				continue
			for nid_var in _node_grid[k]:
				var nid: int = nid_var
				var nd := nodes[nid]
				if nd.edge_ids.is_empty():
					continue
				if pref_kind != "" and nd.kind != pref_kind:
					continue
				var dx := nd.pos.x - pt2.x
				var dz := nd.pos.z - pt2.y
				var d2 := dx * dx + dz * dz
				if d2 < best_d2:
					best_d2 = d2
					best_id = nid
	return best_id


func _has_edge_between(na: int, nb: int) -> bool:
	for eid in nodes[na].edge_ids:
		var ed := edges[eid]
		if (ed.node_a == na and ed.node_b == nb) or (ed.node_a == nb and ed.node_b == na):
			return true
	return false


func _add_ped_edge(
	na: int,
	nb: int,
	pts: PackedVector3Array,
	kind: String,
	is_crosswalk: bool = false,
	signal_node_id: int = -1,
	crosses_ns: bool = false
) -> int:
	if na == nb or pts.size() < 2:
		return -1
	if _has_edge_between(na, nb):
		return -1
	var clean_pts := pts.duplicate()
	clean_pts[0] = nodes[na].pos
	clean_pts[clean_pts.size() - 1] = nodes[nb].pos
	var cum := PackedFloat32Array()
	cum.resize(clean_pts.size())
	cum[0] = 0.0
	for i in range(1, clean_pts.size()):
		cum[i] = cum[i - 1] + clean_pts[i - 1].distance_to(clean_pts[i])
	var total_len := cum[clean_pts.size() - 1]
	if total_len < 1.2:
		return -1

	var ed := PedEdge.new()
	ed.id = edges.size()
	ed.node_a = na
	ed.node_b = nb
	ed.points = clean_pts
	ed.cum_lengths = cum
	ed.total_length = total_len
	ed.kind = kind
	ed.is_crosswalk = is_crosswalk
	ed.signal_node_id = signal_node_id
	ed.crosses_ns_traffic = crosses_ns
	edges.append(ed)
	nodes[na].edge_ids.append(ed.id)
	nodes[nb].edge_ids.append(ed.id)
	if is_crosswalk:
		_crosswalk_edge_count += 1
	elif kind == "park" or kind == "footbridge":
		_park_edge_count += 1
	return ed.id


func _build_pedestrian_graph() -> void:
	var terrain := _plan.terrain
	var road_graph := _plan.road_graph
	var road_node_corners: Dictionary = {} # road_node_id -> Array[int]

	# 1. Urban & neighborhood road sidewalks + intersection crosswalks
	for e in road_graph.edges:
		if e.road_class == "alley" or e.sidewalk_width < 1.4 or e.samples.size() < 2:
			continue
		var pa := road_graph.nodes[e.node_a].pos
		var pb := road_graph.nodes[e.node_b].pos
		var edge_len := pa.distance_to(pb)
		if edge_len < 14.0:
			continue
		var t_start := clampf((e.trim_a + 1.2) / edge_len, 0.04, 0.44)
		var t_end := clampf(1.0 - (e.trim_b + 1.2) / edge_len, 0.56, 0.96)
		if t_end <= t_start + 0.04:
			continue

		var dir2 := (pb - pa) / edge_len
		var side2 := Vector2(-dir2.y, dir2.x)
		var is_ns_road := absf(dir2.y) >= absf(dir2.x)
		var half_r := e.road_width * 0.5
		var sw_w := e.sidewalk_width
		var sw_off := half_r + clampf(sw_w * 0.62, 1.0, sw_w - 0.36)
		var segs := maxi(4, int(ceil((t_end - t_start) * edge_len / 5.0)))

		var start_corners := [-1, -1] # index 0: s_sign=-1, index 1: s_sign=+1
		var end_corners := [-1, -1]

		for side_i in range(2):
			var s_sign := -1.0 if side_i == 0 else 1.0
			var run := PackedVector3Array()
			var run_started_at_a := true
			var run_ended_at_b := false
			for si in range(segs + 1):
				var t := lerpf(t_start, t_end, float(si) / float(segs))
				var p3 := road_graph.sample_edge_point_3d(e, t)
				var pt2 := Vector2(p3.x, p3.z) + side2 * (s_sign * sw_off)
				var sw_y := p3.y + 0.15
				var in_bridge := e.is_bridge and t >= e.bridge_start_t and t <= e.bridge_end_t
				var creek_ok := in_bridge or (terrain.distance_to_creek(pt2) >= terrain.creek_half_width + 0.9)
				if sw_y >= terrain.water_level + 0.35 and creek_ok and _is_outside_buildings(pt2, 0.72):
					if run.is_empty():
						run_started_at_a = (si <= 1)
					run.append(Vector3(pt2.x, sw_y, pt2.y))
					run_ended_at_b = (si >= segs - 1)
				else:
					if run.size() >= 2:
						var na := _get_or_add_node(run[0], "sidewalk", 2.2)
						var nb := _get_or_add_node(run[run.size() - 1], "sidewalk", 2.2)
						_add_ped_edge(na, nb, run, "sidewalk")
						if run_started_at_a:
							start_corners[side_i] = na
					run = PackedVector3Array()
					run_started_at_a = false
					run_ended_at_b = false
			if run.size() >= 2:
				var na := _get_or_add_node(run[0], "sidewalk", 2.2)
				var nb := _get_or_add_node(run[run.size() - 1], "sidewalk", 2.2)
				_add_ped_edge(na, nb, run, "sidewalk")
				if run_started_at_a:
					start_corners[side_i] = na
				if run_ended_at_b:
					end_corners[side_i] = nb

		# Register corners at both road endpoints and add signalized/unsignalized crosswalks across the roadway
		for end_pair in [[e.node_a, start_corners, t_start], [e.node_b, end_corners, t_end]]:
			var rn_id := int(end_pair[0])
			var c_pair: Array = end_pair[1]
			var c_t := float(end_pair[2])
			var rn := road_graph.nodes[rn_id]
			var corner_list: Array = road_node_corners.get(rn_id, [])
			for cid in c_pair:
				if cid != -1 and not (cid in corner_list):
					corner_list.append(cid)
			road_node_corners[rn_id] = corner_list
			if c_pair[0] != -1 and c_pair[1] != -1:
				var p_left := nodes[c_pair[0]].pos
				var p_right := nodes[c_pair[1]].pos
				var road_mid := road_graph.sample_edge_point_3d(e, c_t)
				var cw_pts := PackedVector3Array([
					p_left,
					Vector3(lerpf(p_left.x, road_mid.x, 0.35), road_mid.y + 0.05, lerpf(p_left.z, road_mid.z, 0.35)),
					Vector3(road_mid.x, road_mid.y + 0.04, road_mid.z),
					Vector3(lerpf(road_mid.x, p_right.x, 0.65), road_mid.y + 0.05, lerpf(road_mid.z, p_right.z, 0.65)),
					p_right,
				])
				var sig_nid := rn_id if rn.has_traffic_signal else -1
				_add_ped_edge(c_pair[0], c_pair[1], cw_pts, "crosswalk", true, sig_nid, is_ns_road)

	# 2. Connect adjacent sidewalk corners around the SAME corner quadrant of an intersection (turning a corner on the sidewalk!)
	for rn_id in road_node_corners.keys():
		var c_list: Array = road_node_corners[rn_id]
		var rn := road_graph.nodes[rn_id]
		var cnt := c_list.size()
		for i in range(cnt):
			for j in range(i + 1, cnt):
				var na: int = c_list[i]
				var nb: int = c_list[j]
				if _has_edge_between(na, nb):
					continue
				var pa3 := nodes[na].pos
				var pb3 := nodes[nb].pos
				var dist := pa3.distance_to(pb3)
				if dist > 13.0 or dist < 1.2:
					continue
				# Only join corners on the SAME side of the junction (midline stays outside asphalt center!)
				var mid2 := Vector2((pa3.x + pb3.x) * 0.5, (pa3.z + pb3.z) * 0.5)
				if mid2.distance_to(rn.pos) < 3.6:
					continue
				if not _is_outside_buildings(mid2, 0.55):
					continue
				if terrain.distance_to_creek(mid2) < terrain.creek_half_width + 0.8:
					continue
				var corner_pts := PackedVector3Array([
					pa3,
					Vector3(mid2.x, (pa3.y + pb3.y) * 0.5, mid2.y),
					pb3,
				])
				_add_ped_edge(na, nb, corner_pts, "sidewalk")

	# 3. Park greenways, loops, entrances & creek footbridges
	var park_endpoints: Array[int] = []
	for pw_var in _plan.park_walkways:
		var pw: Dictionary = pw_var
		var kind := String(pw.get("kind", ""))
		var style := String(pw.get("style", ""))
		var pts2: PackedVector2Array = pw.get("points", PackedVector2Array())
		if pts2.size() < 2:
			continue

		if kind == "footbridge":
			var fb_pts := PackedVector3Array()
			var n_fb := pts2.size()
			var deck_y0 := maxf(terrain.water_level + 1.55, terrain.sample_height(pts2[0].x, pts2[0].y) + 0.25)
			var deck_y1 := maxf(terrain.water_level + 1.55, terrain.sample_height(pts2[n_fb - 1].x, pts2[n_fb - 1].y) + 0.25)
			for fi in range(n_fb):
				var frac := float(fi) / float(maxi(1, n_fb - 1))
				var arch := sin(frac * PI) * 0.95
				var fy := lerpf(deck_y0, deck_y1, frac) + arch
				fb_pts.append(Vector3(pts2[fi].x, fy, pts2[fi].y))
			var fa := _get_or_add_node(fb_pts[0], "footbridge", 3.2)
			var fb := _get_or_add_node(fb_pts[fb_pts.size() - 1], "footbridge", 3.2)
			_add_ped_edge(fa, fb, fb_pts, "footbridge")
			park_endpoints.append(fa)
			park_endpoints.append(fb)
			continue

		if kind != "path" or not (style in ["greenway", "loop", "entrance", "greenway_spur"]):
			continue

		# Break long greenways into ~55m segments so side trails & entrances stitch naturally
		var run := PackedVector3Array()
		var run_len := 0.0
		for i in range(pts2.size()):
			var pt2 := pts2[i]
			var y := _is_safe_park_point(pt2, terrain)
			if y > -1000.0:
				var p3 := Vector3(pt2.x, y, pt2.y)
				if not run.is_empty():
					run_len += run[run.size() - 1].distance_to(p3)
				run.append(p3)
				if run_len >= 55.0 and run.size() >= 2:
					var na := _get_or_add_node(run[0], "park", 3.2)
					var nb := _get_or_add_node(run[run.size() - 1], "park", 3.2)
					_add_ped_edge(na, nb, run, "park")
					park_endpoints.append(na)
					park_endpoints.append(nb)
					run = PackedVector3Array([p3])
					run_len = 0.0
			else:
				if run.size() >= 2:
					var na := _get_or_add_node(run[0], "park", 3.2)
					var nb := _get_or_add_node(run[run.size() - 1], "park", 3.2)
					_add_ped_edge(na, nb, run, "park")
					park_endpoints.append(na)
					park_endpoints.append(nb)
				run = PackedVector3Array()
				run_len = 0.0
		if run.size() >= 2:
			var na := _get_or_add_node(run[0], "park", 3.2)
			var nb := _get_or_add_node(run[run.size() - 1], "park", 3.2)
			_add_ped_edge(na, nb, run, "park")
			park_endpoints.append(na)
			park_endpoints.append(nb)

	# 4. Stitch park/footbridge endpoints to nearby sidewalk nodes so citizens walk seamlessly street <-> park
	var stitched := {}
	for pn_id in park_endpoints:
		if stitched.has(pn_id):
			continue
		stitched[pn_id] = true
		var pn := nodes[pn_id]
		var sw_id := _find_nearest_node(Vector2(pn.pos.x, pn.pos.z), 24.0, "sidewalk")
		if sw_id != -1 and not _has_edge_between(pn_id, sw_id):
			var sw_p := nodes[sw_id].pos
			var mid2 := Vector2((pn.pos.x + sw_p.x) * 0.5, (pn.pos.z + sw_p.z) * 0.5)
			if _is_outside_buildings(mid2, 0.70) and terrain.distance_to_creek(mid2) >= terrain.creek_half_width + 1.0:
				var hy_m := terrain.sample_height(mid2.x, mid2.y) + 0.06
				var conn := PackedVector3Array([pn.pos, Vector3(mid2.x, hy_m, mid2.y), sw_p])
				_add_ped_edge(pn_id, sw_id, conn, "park")


func _add_anchor(cat: int, pos: Vector3, facing: Vector3, bld_id: String, venue: String, is_outdoor: bool) -> int:
	var nid := _find_nearest_node(Vector2(pos.x, pos.z), 54.0)
	if nid == -1:
		return -1
	var a := Anchor.new()
	a.id = anchors.size()
	a.category = cat
	a.node_id = nid
	a.pos = pos
	a.facing = facing.normalized() if facing.length_squared() > 0.001 else Vector3(0.0, 0.0, 1.0)
	a.building_id = bld_id
	a.venue_type = venue
	a.is_outdoor = is_outdoor
	anchors.append(a)
	var list: Array = anchors_by_cat.get(cat, [])
	list.append(a.id)
	anchors_by_cat[cat] = list
	return a.id


func _build_anchors() -> void:
	# 1. Building doorway anchors mapped directly to real CityPlan blueprints
	for bp in _plan.blueprints:
		var app := bp.get_approach_world_pos()
		var pos := Vector3(app.x, bp.sidewalk_y + 0.04, app.z)
		var fwd2 := Vector2(sin(bp.yaw), cos(bp.yaw))
		var face := Vector3(fwd2.x, 0.0, fwd2.y)
		var cat := ANCHOR_RETAIL
		match bp.archetype:
			"house_pitched", "beach_house", "townhouse", "apartment_midrise":
				cat = ANCHOR_HOME
			"skyscraper_tower", "modern_office":
				cat = ANCHOR_OFFICE
			"mixed_use_midrise":
				cat = ANCHOR_DINING if bp.venue_type in ["cafe", "restaurant", "gym", "cinema"] else ANCHOR_OFFICE
			"school":
				cat = ANCHOR_SCHOOL
			"hospital":
				cat = ANCHOR_HOSPITAL
			"warehouse":
				cat = ANCHOR_INDUSTRIAL
			"municipal_hall", "police_station", "fire_station", "church", "civic_hall":
				cat = ANCHOR_CIVIC
			_:
				if bp.venue_type in ["cafe", "restaurant", "cinema", "gym"]:
					cat = ANCHOR_DINING
				elif bp.venue_type == "clinic":
					cat = ANCHOR_HOSPITAL
				else:
					cat = ANCHOR_RETAIL
		_add_anchor(cat, pos, face, bp.id, bp.venue_type, false)

	# 2. Outdoor smart activity anchors: transit shelters (bus stops), fountains, gazebos, cafe seating, benches, sport courts
	for pr in _plan.props:
		var pt := String(pr.get("type", ""))
		var pos3: Vector3 = pr.get("pos", Vector3.ZERO)
		var yaw := float(pr.get("yaw", 0.0))
		var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
		if pt == "transit_shelter":
			var wait_p := pos3 + fwd * 0.72
			_add_anchor(ANCHOR_BUS_STOP, wait_p, fwd, "", "transit_shelter", true)
		elif pt in ["park_fountain", "park_gazebo", "sport_court"]:
			var ring_p := pos3 + Vector3(3.2, 0.0, 0.8)
			if _is_outside_buildings(Vector2(ring_p.x, ring_p.z), 0.7):
				_add_anchor(ANCHOR_PARK_PLAZA, ring_p, -Vector3(3.2, 0.0, 0.8).normalized(), "", pt, true)
		elif pt in ["cafe_seating", "sidewalk_bench", "bench"]:
			var stand_p := pos3 + fwd * 0.85
			if _is_outside_buildings(Vector2(stand_p.x, stand_p.z), 0.65):
				_add_anchor(ANCHOR_PARK_PLAZA, stand_p, fwd, "", pt, true)
		elif pt in ["beach_boardwalk_seg", "beach_umbrella_set"]:
			if pos3.y >= _plan.terrain.water_level + 0.45 and _is_outside_buildings(Vector2(pos3.x, pos3.z), 0.75):
				var stand_b := pos3 + fwd * (0.35 if pt == "beach_boardwalk_seg" else 1.25)
				if _plan.terrain.sample_height(stand_b.x, stand_b.z) >= _plan.terrain.water_level + 0.40:
					_add_anchor(ANCHOR_PARK_PLAZA, Vector3(stand_b.x, maxf(pos3.y, _plan.terrain.sample_height(stand_b.x, stand_b.z)) + 0.04, stand_b.z), fwd, "", pt, true)


func _pick_anchor_in_radius(
	rng: RandomNumberGenerator,
	cat_list: Array[int],
	ref_pos: Vector3,
	min_r: float,
	max_r: float
) -> int:
	var pool: Array[int] = []
	for cat in cat_list:
		var ids: Array = anchors_by_cat.get(cat, [])
		for aid_var in ids:
			pool.append(int(aid_var))
	if pool.is_empty():
		return -1

	var near_pool: Array[int] = []
	var min_r2 := min_r * min_r
	var max_r2 := max_r * max_r
	for aid in pool:
		var d2 := anchors[aid].pos.distance_squared_to(ref_pos)
		if d2 >= min_r2 and d2 <= max_r2:
			near_pool.append(aid)
	if not near_pool.is_empty():
		return near_pool[rng.randi_range(0, near_pool.size() - 1)]

	# Pick closest reasonable fallback
	var best_id := pool[0]
	var best_err := INF
	var target_r := (min_r + max_r) * 0.5
	for _k in range(mini(24, pool.size())):
		var cand := pool[rng.randi_range(0, pool.size() - 1)]
		var err := absf(anchors[cand].pos.distance_to(ref_pos) - target_r)
		if err < best_err:
			best_err = err
			best_id = cand
	return best_id


func _find_nearest_anchor_of_cat(cat: int, ref_pos: Vector3, max_r: float) -> int:
	var ids: Array = anchors_by_cat.get(cat, [])
	var best_id := -1
	var best_d2 := max_r * max_r
	for aid_var in ids:
		var aid := int(aid_var)
		var d2 := anchors[aid].pos.distance_squared_to(ref_pos)
		if d2 < best_d2:
			best_d2 = d2
			best_id = aid
	return best_id


func _generate_citizens() -> void:
	if anchors.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _plan.config.world_seed + 9137

	var all_homes: Array = anchors_by_cat.get(ANCHOR_HOME, [])
	if all_homes.is_empty():
		all_homes = []
		for a in anchors:
			all_homes.append(a.id)

	var downtown_c: Vector2 = _plan.district_centers.get("downtown_mixed", Vector2(_plan.config.world_size * 0.5, _plan.config.world_size * 0.5))
	var dt_ref := Vector3(downtown_c.x, 0.0, downtown_c.y)

	for ci in range(TARGET_CITIZEN_COUNT):
		var c := CitizenProfile.new()
		c.id = ci
		c.display_name = "%s %s" % [
			FIRST_NAMES[rng.randi() % FIRST_NAMES.size()],
			LAST_NAMES[rng.randi() % LAST_NAMES.size()],
		]

		# Weighted realistic urban demographics
		var rr := rng.randf()
		if rr < 0.27:
			c.role = ROLE_OFFICE
		elif rr < 0.44:
			c.role = ROLE_RETAIL
		elif rr < 0.58:
			c.role = ROLE_STUDENT
		elif rr < 0.66:
			c.role = ROLE_MEDIC
		elif rr < 0.76:
			c.role = ROLE_INDUSTRIAL
		elif rr < 0.92:
			c.role = ROLE_RESIDENT
		else:
			c.role = ROLE_NIGHT_SHIFT

		c.walk_speed = rng.randf_range(1.16, 1.58)
		if c.role == ROLE_STUDENT:
			c.body_scale = rng.randf_range(0.86, 0.99)
			c.walk_speed = rng.randf_range(1.30, 1.66)
		elif c.role == ROLE_RESIDENT and (ci % 4 == 0):
			# Park joggers / energetic walkers
			c.walk_speed = rng.randf_range(1.65, 2.05)
			c.body_scale = rng.randf_range(0.93, 1.08)
		else:
			c.body_scale = rng.randf_range(0.92, 1.09)

		c.palette_seed = rng.randf()
		c.umbrella_seed = rng.randf()
		c.has_bag = (c.role in [ROLE_OFFICE, ROLE_STUDENT, ROLE_MEDIC]) or (rng.randf() < 0.25)

		# Prefer placing ~74% of citizens within active urban/downtown & commercial corridors so street life is rich
		var home_id: int
		if rng.randf() < 0.74:
			home_id = _pick_anchor_in_radius(rng, [ANCHOR_HOME, ANCHOR_OFFICE, ANCHOR_RETAIL], dt_ref, 30.0, 520.0)
		else:
			home_id = int(all_homes[rng.randi_range(0, all_homes.size() - 1)])
		if home_id == -1:
			home_id = int(all_homes[0])
		c.home_anchor_id = home_id
		var home_pos := anchors[home_id].pos

		# Assign role-authentic workplace within walkable/transit distance
		match c.role:
			ROLE_OFFICE:
				c.work_anchor_id = _pick_anchor_in_radius(rng, [ANCHOR_OFFICE, ANCHOR_CIVIC], home_pos, 95.0, 480.0)
			ROLE_RETAIL:
				c.work_anchor_id = _pick_anchor_in_radius(rng, [ANCHOR_RETAIL, ANCHOR_DINING], home_pos, 85.0, 440.0)
			ROLE_STUDENT:
				c.work_anchor_id = _pick_anchor_in_radius(rng, [ANCHOR_SCHOOL], home_pos, 60.0, 900.0)
			ROLE_MEDIC:
				c.work_anchor_id = _pick_anchor_in_radius(rng, [ANCHOR_HOSPITAL], home_pos, 60.0, 900.0)
			ROLE_INDUSTRIAL:
				c.work_anchor_id = _pick_anchor_in_radius(rng, [ANCHOR_INDUSTRIAL, ANCHOR_RETAIL], home_pos, 100.0, 520.0)
			ROLE_NIGHT_SHIFT:
				c.work_anchor_id = _pick_anchor_in_radius(rng, [ANCHOR_HOSPITAL, ANCHOR_CIVIC, ANCHOR_INDUSTRIAL, ANCHOR_RETAIL], home_pos, 90.0, 560.0)
			_:
				c.work_anchor_id = _pick_anchor_in_radius(rng, [ANCHOR_PARK_PLAZA, ANCHOR_RETAIL, ANCHOR_DINING], home_pos, 80.0, 420.0)
		if c.work_anchor_id == -1:
			c.work_anchor_id = home_id

		var work_pos := anchors[c.work_anchor_id].pos
		c.lunch_anchor_id = _pick_anchor_in_radius(rng, [ANCHOR_DINING, ANCHOR_PARK_PLAZA, ANCHOR_RETAIL], work_pos, 45.0, 290.0)
		if c.lunch_anchor_id == -1:
			c.lunch_anchor_id = c.work_anchor_id

		c.leisure_anchor_id = _pick_anchor_in_radius(rng, [ANCHOR_PARK_PLAZA, ANCHOR_DINING, ANCHOR_RETAIL, ANCHOR_CIVIC], home_pos, 70.0, 440.0)
		if c.leisure_anchor_id == -1:
			c.leisure_anchor_id = c.lunch_anchor_id

		# Bus commuters: citizens with longer commutes who live & work near transit shelters
		var commute_dist := home_pos.distance_to(work_pos)
		if commute_dist > 340.0 and rng.randf() < 0.65:
			var hb := _find_nearest_anchor_of_cat(ANCHOR_BUS_STOP, home_pos, 260.0)
			var wb := _find_nearest_anchor_of_cat(ANCHOR_BUS_STOP, work_pos, 260.0)
			if hb != -1 and wb != -1 and hb != wb:
				c.uses_bus = true
				c.home_bus_anchor_id = hb
				c.work_bus_anchor_id = wb

		var jitter := rng.randf_range(-0.42, 0.42)
		_build_citizen_schedule(c, jitter, rng)
		citizens.append(c)


func _make_slot(s_h: float, e_h: float, act: int, anchor_id: int, lbl: String) -> ScheduleSlot:
	var sl := ScheduleSlot.new()
	sl.start_h = clampf(s_h, 0.0, 24.0)
	sl.end_h = clampf(e_h, sl.start_h + 0.05, 24.0)
	sl.activity = act
	sl.anchor_id = anchor_id
	sl.label = lbl
	return sl


func _build_citizen_schedule(c: CitizenProfile, j: float, rng: RandomNumberGenerator) -> void:
	var s := c.schedule
	s.clear()
	var lunch_out := anchors[c.lunch_anchor_id].is_outdoor
	var leis_out := anchors[c.leisure_anchor_id].is_outdoor

	match c.role:
		ROLE_OFFICE:
			var t_wake := clampf(7.15 + j, 6.3, 8.1)
			var t_work := t_wake + 1.05
			var t_coffee := clampf(10.05 + rng.randf_range(-0.35, 0.75), 9.5, 11.1)
			var t_lunch := clampf(12.0 + j * 0.8, 11.4, 12.8)
			var t_back := t_lunch + 1.25
			var t_off := clampf(17.15 + j, 16.5, 18.1)
			var t_eve := t_off + 1.80
			var t_home := clampf(t_eve + 1.05, 19.3, 22.0)
			s.append(_make_slot(0.0, t_wake, ACT_INDOORS, c.home_anchor_id, "sleep"))
			if c.uses_bus:
				s.append(_make_slot(t_wake, t_wake + 0.35, ACT_BUS_WAIT, c.home_bus_anchor_id, "bus_commute"))
				s.append(_make_slot(t_wake + 0.35, t_work, ACT_TRAVEL, c.work_anchor_id, "commute_work"))
			else:
				s.append(_make_slot(t_wake, t_work, ACT_TRAVEL, c.work_anchor_id, "commute_work"))
			# ~45% of office workers step out for mid-morning coffee / client errands between 09:30 and 11:30
			if (c.id % 9) < 4 and t_coffee > t_work + 0.25 and t_coffee + 0.55 < t_lunch:
				s.append(_make_slot(t_work, t_coffee, ACT_INDOORS, c.work_anchor_id, "office_work"))
				s.append(_make_slot(t_coffee, t_coffee + 0.55, ACT_TRAVEL, c.lunch_anchor_id, "morning_walk"))
				s.append(_make_slot(t_coffee + 0.55, t_lunch, ACT_INDOORS, c.work_anchor_id, "office_work"))
			else:
				s.append(_make_slot(t_work, t_lunch, ACT_INDOORS, c.work_anchor_id, "office_work"))
			s.append(_make_slot(t_lunch, t_back, ACT_LINGER_OUTDOOR if lunch_out else ACT_TRAVEL, c.lunch_anchor_id, "lunch"))
			s.append(_make_slot(t_back, t_off, ACT_INDOORS, c.work_anchor_id, "office_work"))
			s.append(_make_slot(t_off, t_eve, ACT_LINGER_OUTDOOR if leis_out else ACT_TRAVEL, c.leisure_anchor_id, "evening_leisure"))
			s.append(_make_slot(t_eve, t_home, ACT_TRAVEL, c.home_anchor_id, "commute_home"))
			s.append(_make_slot(t_home, 24.0, ACT_INDOORS, c.home_anchor_id, "home_evening"))

		ROLE_RETAIL:
			# Split into morning-opening shift (08:30) and midday/evening shift (10:15-11:30 commute!)
			var late_shift := (c.id % 2 == 1)
			var t_go := clampf((10.15 if late_shift else 8.20) + j, 7.5, 11.1)
			var t_open := t_go + 0.90
			var t_brk := clampf((14.4 if late_shift else 13.0) + j * 0.7, 12.4, 15.2)
			var t_back := t_brk + 1.00
			var t_close := clampf((20.8 if late_shift else 18.1) + j, 17.4, 21.8)
			var t_home := clampf(t_close + 1.10, 18.8, 23.4)
			s.append(_make_slot(0.0, t_go, ACT_INDOORS, c.home_anchor_id, "sleep"))
			s.append(_make_slot(t_go, t_open, ACT_TRAVEL, c.work_anchor_id, "commute_shop"))
			s.append(_make_slot(t_open, t_brk, ACT_INDOORS, c.work_anchor_id, "retail_shift"))
			s.append(_make_slot(t_brk, t_back, ACT_LINGER_OUTDOOR if lunch_out else ACT_TRAVEL, c.lunch_anchor_id, "break"))
			s.append(_make_slot(t_back, t_close, ACT_INDOORS, c.work_anchor_id, "retail_shift"))
			s.append(_make_slot(t_close, t_home, ACT_TRAVEL, c.home_anchor_id, "commute_home"))
			s.append(_make_slot(t_home, 24.0, ACT_INDOORS, c.home_anchor_id, "home_evening"))

		ROLE_STUDENT:
			var t_go := clampf(7.30 + j * 0.6, 6.8, 7.8)
			var t_cls := t_go + 0.80
			var t_out := clampf(15.05 + j * 0.5, 14.7, 15.5)
			var t_hang := t_out + 1.95
			var t_home := t_hang + 0.85
			s.append(_make_slot(0.0, t_go, ACT_INDOORS, c.home_anchor_id, "sleep"))
			if c.uses_bus:
				s.append(_make_slot(t_go, t_go + 0.30, ACT_BUS_WAIT, c.home_bus_anchor_id, "school_bus"))
				s.append(_make_slot(t_go + 0.30, t_cls, ACT_TRAVEL, c.work_anchor_id, "to_school"))
			else:
				s.append(_make_slot(t_go, t_cls, ACT_TRAVEL, c.work_anchor_id, "to_school"))
			s.append(_make_slot(t_cls, t_out, ACT_INDOORS, c.work_anchor_id, "classes"))
			s.append(_make_slot(t_out, t_hang, ACT_LINGER_OUTDOOR if leis_out else ACT_TRAVEL, c.leisure_anchor_id, "after_school"))
			s.append(_make_slot(t_hang, t_home, ACT_TRAVEL, c.home_anchor_id, "walk_home"))
			s.append(_make_slot(t_home, 24.0, ACT_INDOORS, c.home_anchor_id, "homework"))

		ROLE_MEDIC:
			var t_go := clampf(6.60 + j, 6.0, 7.4)
			var t_in := t_go + 0.85
			var t_brk := clampf(12.6 + j, 11.8, 13.5)
			var t_back := t_brk + 0.90
			var t_off := clampf(18.6 + j, 17.8, 19.6)
			var t_home := t_off + 0.95
			s.append(_make_slot(0.0, t_go, ACT_INDOORS, c.home_anchor_id, "sleep"))
			s.append(_make_slot(t_go, t_in, ACT_TRAVEL, c.work_anchor_id, "commute_hospital"))
			s.append(_make_slot(t_in, t_brk, ACT_INDOORS, c.work_anchor_id, "medical_shift"))
			s.append(_make_slot(t_brk, t_back, ACT_LINGER_OUTDOOR if lunch_out else ACT_TRAVEL, c.lunch_anchor_id, "cafe_break"))
			s.append(_make_slot(t_back, t_off, ACT_INDOORS, c.work_anchor_id, "medical_shift"))
			s.append(_make_slot(t_off, t_home, ACT_TRAVEL, c.home_anchor_id, "commute_home"))
			s.append(_make_slot(t_home, 24.0, ACT_INDOORS, c.home_anchor_id, "rest"))

		ROLE_INDUSTRIAL:
			var t_go := clampf(6.15 + j * 0.7, 5.6, 6.8)
			var t_in := t_go + 0.80
			var t_deliv := clampf(10.0 + rng.randf_range(0.0, 1.1), 9.8, 11.1)
			var t_brk := clampf(11.65 + j * 0.6, 11.2, 12.2)
			var t_back := t_brk + 0.90
			var t_off := clampf(15.45 + j * 0.8, 14.8, 16.3)
			var t_err := t_off + 1.65
			var t_home := t_err + 0.85
			s.append(_make_slot(0.0, t_go, ACT_INDOORS, c.home_anchor_id, "sleep"))
			s.append(_make_slot(t_go, t_in, ACT_TRAVEL, c.work_anchor_id, "early_commute"))
			# Couriers & dispatch rounds between 09:45-11:15
			if c.id % 2 == 0:
				s.append(_make_slot(t_in, t_deliv, ACT_INDOORS, c.work_anchor_id, "warehouse_shift"))
				s.append(_make_slot(t_deliv, t_brk, ACT_TRAVEL, c.lunch_anchor_id, "midday_errand"))
			else:
				s.append(_make_slot(t_in, t_brk, ACT_INDOORS, c.work_anchor_id, "warehouse_shift"))
			s.append(_make_slot(t_brk, t_back, ACT_LINGER_OUTDOOR if lunch_out else ACT_TRAVEL, c.lunch_anchor_id, "lunch"))
			s.append(_make_slot(t_back, t_off, ACT_INDOORS, c.work_anchor_id, "warehouse_shift"))
			s.append(_make_slot(t_off, t_err, ACT_LINGER_OUTDOOR if leis_out else ACT_TRAVEL, c.leisure_anchor_id, "afternoon_errand"))
			s.append(_make_slot(t_err, t_home, ACT_TRAVEL, c.home_anchor_id, "commute_home"))
			s.append(_make_slot(t_home, 24.0, ACT_INDOORS, c.home_anchor_id, "home_evening"))

		ROLE_NIGHT_SHIFT:
			# Staggered evening & overnight workers (hospital, security, late-night dining, logistics)
			var t_break_n := clampf(1.6 + rng.randf_range(0.0, 2.6), 1.0, 4.2)
			var t_end_shift := clampf(6.3 + j * 0.7, 5.6, 7.1)
			var t_home_sleep := t_end_shift + 0.90
			var t_wake_pm := clampf(15.6 + j, 14.8, 16.8)
			var t_dinner := clampf(18.6 + j, 17.8, 19.6)
			var t_night_go := clampf(22.2 + rng.randf_range(-0.9, 1.0), 21.1, 23.3)
			var t_night_in := clampf(t_night_go + 0.85, t_night_go + 0.5, 23.95)
			s.append(_make_slot(0.0, t_break_n, ACT_INDOORS, c.work_anchor_id, "night_shift"))
			s.append(_make_slot(t_break_n, t_break_n + 0.75, ACT_TRAVEL, c.lunch_anchor_id, "night_break"))
			s.append(_make_slot(t_break_n + 0.75, t_end_shift, ACT_INDOORS, c.work_anchor_id, "night_shift"))
			s.append(_make_slot(t_end_shift, t_home_sleep, ACT_TRAVEL, c.home_anchor_id, "morning_home"))
			s.append(_make_slot(t_home_sleep, t_wake_pm, ACT_INDOORS, c.home_anchor_id, "day_sleep"))
			s.append(_make_slot(t_wake_pm, t_dinner, ACT_LINGER_OUTDOOR if leis_out else ACT_TRAVEL, c.leisure_anchor_id, "afternoon_out"))
			s.append(_make_slot(t_dinner, t_night_go, ACT_INDOORS, c.home_anchor_id, "prep_shift"))
			s.append(_make_slot(t_night_go, t_night_in, ACT_TRAVEL, c.work_anchor_id, "night_commute"))
			s.append(_make_slot(t_night_in, 24.0, ACT_INDOORS, c.work_anchor_id, "night_shift"))

		_:
			# ROLE_RESIDENT: morning park walk/jog, lively mid-morning & afternoon shopping/cafes, sunset stroll
			var t_morn := clampf(6.75 + j, 6.1, 7.8)
			var t_morn_end := t_morn + 1.80
			var t_mid := clampf(9.55 + rng.randf_range(0.0, 2.2), 9.4, 12.2)
			var t_mid_end := clampf(t_mid + 3.2, t_mid + 1.5, 15.6)
			var t_eve := clampf(17.1 + j, 16.5, 18.2)
			var t_eve_end := clampf(t_eve + 2.5, 19.2, 21.6)
			var t_home := t_eve_end + 0.90
			s.append(_make_slot(0.0, t_morn, ACT_INDOORS, c.home_anchor_id, "sleep"))
			s.append(_make_slot(t_morn, t_morn_end, ACT_LINGER_OUTDOOR if leis_out else ACT_TRAVEL, c.leisure_anchor_id, "morning_walk"))
			s.append(_make_slot(t_morn_end, t_mid, ACT_INDOORS, c.home_anchor_id, "at_home"))
			s.append(_make_slot(t_mid, t_mid_end, ACT_LINGER_OUTDOOR if lunch_out else ACT_TRAVEL, c.lunch_anchor_id, "midday_errand"))
			s.append(_make_slot(t_mid_end, t_eve, ACT_INDOORS, c.home_anchor_id, "afternoon_home"))
			s.append(_make_slot(t_eve, t_eve_end, ACT_LINGER_OUTDOOR if leis_out else ACT_TRAVEL, c.work_anchor_id, "evening_stroll"))
			s.append(_make_slot(t_eve_end, t_home, ACT_TRAVEL, c.home_anchor_id, "walk_home"))
			s.append(_make_slot(t_home, 24.0, ACT_INDOORS, c.home_anchor_id, "sleep"))
