class_name CrowdManager
extends Node3D

## Node-free scheduled urban citizen simulation powered by NPCScheduler:
## - Connected citywide sidewalk, crosswalk, park greenway & creek footbridge graph
## - 1,040 procedural citizens across 7 roles following staggered 24-hour daily routines
## - Traffic-signal-obeying crosswalks with live bidirectional vehicle yielding
## - Bus stop waiting/boarding at transit shelters + plaza/cafe/fountain lingering
## - 8m spatial-hash local crowd separation + weather-reactive umbrellas & hurry speed
## - Rendered in 3 MultiMesh draw calls (pedestrians + commuter bags + rain umbrellas)

const VIS_RANGE := 155.0
const SEP_CELL_SIZE := 8.0
const PED_WALK_SHADER_PATH := "res://src/city_world/shaders/pedestrian_walk.gdshader"
const NPCSchedulerScript := preload("res://src/city_world/traffic/npc_scheduler.gd")
const TrafficManagerScript := preload("res://src/city_world/traffic/traffic_manager.gd")

const STATE_INDOORS := 0
const STATE_WALKING := 1
const STATE_WAITING_CROSSWALK := 2
const STATE_WAITING_BUS := 3
const STATE_LINGERING := 4

static var _cached_ped_mesh: ArrayMesh = null
static var _cached_bag_mesh: ArrayMesh = null
static var _cached_umbrella_mesh: ArrayMesh = null
static var _cached_accessory_shader: Shader = null

var scheduler: RefCounted = null
var _plan: CityPlan = null
var _traffic_manager: Node3D = null
var _last_sync_hour: float = -99.0
var _cur_time_hour: float = 10.5
var _cur_rain: float = 0.0
var _sim_time: float = 0.0

# Performance & quality scaling (managed by PerformanceController)
var density_scale: float = 1.0
var vis_range_scale: float = 1.0
var far_lod_divisor: int = 4
var _sim_frame_idx: int = 0
var _last_cam_pos: Vector3 = Vector3.ZERO

# Per-citizen flat typed simulation arrays
var _ped_count: int = 0
var _p_state: PackedInt32Array = PackedInt32Array()
var _p_slot_idx: PackedInt32Array = PackedInt32Array()
var _p_cur_anchor: PackedInt32Array = PackedInt32Array()
var _p_target_anchor: PackedInt32Array = PackedInt32Array()
var _p_path_idx: PackedInt32Array = PackedInt32Array()
var _p_edge_id: PackedInt32Array = PackedInt32Array()
var _p_edge_dir: PackedInt32Array = PackedInt32Array()
var _p_s: PackedFloat32Array = PackedFloat32Array()
var _p_cur_speed: PackedFloat32Array = PackedFloat32Array()
var _p_phase: PackedFloat32Array = PackedFloat32Array()
var _p_lat_off: PackedFloat32Array = PackedFloat32Array()
var _p_sep_lat: PackedFloat32Array = PackedFloat32Array()
var _p_linger_timer: PackedFloat32Array = PackedFloat32Array()
var _p_has_umbrella: PackedByteArray = PackedByteArray()
var _p_pos: PackedVector3Array = PackedVector3Array()
var _p_fwd: PackedVector3Array = PackedVector3Array()
var _p_paths: Array = [] # Array[Array[Dictionary {edge_id, dir}]]

var _sep_grid: Dictionary = {}
var _active_crosswalk_peds: PackedVector3Array = PackedVector3Array()

var _ped_mmi: MultiMeshInstance3D = null
var _ped_mm: MultiMesh = null
var _ped_mat: ShaderMaterial = null
var _bag_mmi: MultiMeshInstance3D = null
var _bag_mm: MultiMesh = null
var _umb_mmi: MultiMeshInstance3D = null
var _umb_mm: MultiMesh = null
var _acc_mat: ShaderMaterial = null


func set_traffic_manager(tm: Node3D) -> void:
	_traffic_manager = tm


func setup(p_plan: CityPlan, _p_mats: MaterialLibrary) -> void:
	_clear_renderers()
	_reset_state()
	_plan = p_plan
	if _plan == null or _plan.terrain == null or _plan.road_graph == null:
		return

	_ensure_shared_meshes()
	scheduler = NPCSchedulerScript.new()
	scheduler.build(_plan)
	if scheduler.citizens.is_empty() or scheduler.edges.is_empty():
		return

	_init_citizen_arrays()
	_build_renderers()
	_sync_all_citizens_to_hour(10.5, 0.0)
	step(0.0, _plan.spawn_position, 0.0, 10.5, 0.0)


func step(
	delta: float,
	cam_pos: Vector3,
	_night_factor: float,
	time_hour: float = 10.5,
	weather_rain: float = 0.0
) -> void:
	if _plan == null or _ped_mm == null or _ped_count <= 0:
		return

	var dt := clampf(delta, 0.0, 0.05)
	_sim_time += dt
	_sim_frame_idx += 1
	_last_cam_pos = cam_pos
	_cur_time_hour = fposmod(time_hour, 24.0)
	_cur_rain = clampf(weather_rain, 0.0, 1.0)

	# Detect manual time-of-day jumps (T / [ / ] / --time=) and immediately project all citizen routines
	if _last_sync_hour < 0.0:
		_sync_all_citizens_to_hour(_cur_time_hour, _cur_rain)
	else:
		var dh := absf(fposmod(_cur_time_hour - _last_sync_hour + 12.0, 24.0) - 12.0)
		if dh > 0.28:
			_sync_all_citizens_to_hour(_cur_time_hour, _cur_rain)
	_last_sync_hour = _cur_time_hour

	if dt > 0.0:
		_rebuild_sep_grid(cam_pos)
		_simulate_citizens(dt)

	if _traffic_manager != null and is_instance_valid(_traffic_manager):
		_traffic_manager.set_active_crosswalk_peds(_active_crosswalk_peds)

	_upload_multimeshes(cam_pos)


func set_performance_profile(p_density_scale: float, p_vis_scale: float = 1.0, p_far_lod_divisor: int = 4) -> void:
	density_scale = clampf(p_density_scale, 0.20, 1.0)
	vis_range_scale = clampf(p_vis_scale, 0.45, 1.30)
	far_lod_divisor = clampi(p_far_lod_divisor, 1, 6)


func _get_effective_citizen_cap() -> int:
	if _ped_count <= 0:
		return 0
	if density_scale >= 0.995:
		return _ped_count
	return clampi(int(round(float(_ped_count) * density_scale)), mini(48, _ped_count), _ped_count)


func get_pedestrian_count() -> int:
	return _ped_count


func get_crowd_stats() -> Dictionary:
	var walking := 0
	var waiting_cw := 0
	var waiting_bus := 0
	var lingering := 0
	var indoors := 0
	var umbrellas := 0
	var rain_on := _cur_rain > 0.22
	var eff_cap := _get_effective_citizen_cap()
	for i in range(_ped_count):
		var st := STATE_INDOORS if i >= eff_cap else _p_state[i]
		match st:
			STATE_INDOORS:
				indoors += 1
			STATE_WALKING:
				walking += 1
				if rain_on and _p_has_umbrella[i] == 1:
					umbrellas += 1
			STATE_WAITING_CROSSWALK:
				waiting_cw += 1
				if rain_on and _p_has_umbrella[i] == 1:
					umbrellas += 1
			STATE_WAITING_BUS:
				waiting_bus += 1
				if rain_on and _p_has_umbrella[i] == 1:
					umbrellas += 1
			STATE_LINGERING:
				lingering += 1
				if rain_on and _p_has_umbrella[i] == 1:
					umbrellas += 1
	return {
		"total": _ped_count,
		"outdoor": _ped_count - indoors,
		"walking": walking,
		"waiting_crosswalk": waiting_cw,
		"waiting_bus": waiting_bus,
		"lingering": lingering,
		"indoors": indoors,
		"umbrellas": umbrellas,
		"crosswalk_edges": scheduler.get_crosswalk_edge_count() if scheduler != null else 0,
		"graph_nodes": scheduler.nodes.size() if scheduler != null else 0,
		"graph_edges": scheduler.edges.size() if scheduler != null else 0,
	}


func get_citizen_snapshot(index: int) -> Dictionary:
	if scheduler == null or index < 0 or index >= _ped_count:
		return {}
	var c = scheduler.citizens[index]
	var eval: Dictionary = scheduler.evaluate_citizen_slot(c, _cur_time_hour)
	var sl = eval["slot"]
	return {
		"name": c.display_name,
		"role": c.role,
		"state": _p_state[index],
		"activity": sl.label if sl != null else "idle",
		"pos": _p_pos[index],
		"speed": _p_cur_speed[index],
	}


func _clear_renderers() -> void:
	for ch in get_children():
		remove_child(ch)
		ch.queue_free()
	_ped_mmi = null
	_ped_mm = null
	_ped_mat = null
	_bag_mmi = null
	_bag_mm = null
	_umb_mmi = null
	_umb_mm = null
	_acc_mat = null


func _reset_state() -> void:
	scheduler = null
	_last_sync_hour = -99.0
	_sim_time = 0.0
	_ped_count = 0
	_p_state.clear()
	_p_slot_idx.clear()
	_p_cur_anchor.clear()
	_p_target_anchor.clear()
	_p_path_idx.clear()
	_p_edge_id.clear()
	_p_edge_dir.clear()
	_p_s.clear()
	_p_cur_speed.clear()
	_p_phase.clear()
	_p_lat_off.clear()
	_p_sep_lat.clear()
	_p_linger_timer.clear()
	_p_has_umbrella.clear()
	_p_pos.clear()
	_p_fwd.clear()
	_p_paths.clear()
	_sep_grid.clear()
	_active_crosswalk_peds.clear()


func _init_citizen_arrays() -> void:
	_ped_count = scheduler.citizens.size()
	_p_state.resize(_ped_count)
	_p_slot_idx.resize(_ped_count)
	_p_cur_anchor.resize(_ped_count)
	_p_target_anchor.resize(_ped_count)
	_p_path_idx.resize(_ped_count)
	_p_edge_id.resize(_ped_count)
	_p_edge_dir.resize(_ped_count)
	_p_s.resize(_ped_count)
	_p_cur_speed.resize(_ped_count)
	_p_phase.resize(_ped_count)
	_p_lat_off.resize(_ped_count)
	_p_sep_lat.resize(_ped_count)
	_p_linger_timer.resize(_ped_count)
	_p_has_umbrella.resize(_ped_count)
	_p_pos.resize(_ped_count)
	_p_fwd.resize(_ped_count)
	_p_paths.resize(_ped_count)

	var rng := RandomNumberGenerator.new()
	rng.seed = _plan.config.world_seed + 7043
	for i in range(_ped_count):
		var c = scheduler.citizens[i]
		_p_state[i] = STATE_INDOORS
		_p_slot_idx[i] = -1
		_p_cur_anchor[i] = c.home_anchor_id
		_p_target_anchor[i] = c.home_anchor_id
		_p_path_idx[i] = 0
		_p_edge_id[i] = -1
		_p_edge_dir[i] = 1
		_p_s[i] = 0.0
		_p_cur_speed[i] = 0.0
		_p_phase[i] = rng.randf_range(0.0, TAU)
		_p_lat_off[i] = rng.randf_range(-0.34, 0.34)
		_p_sep_lat[i] = 0.0
		_p_linger_timer[i] = 0.0
		_p_has_umbrella[i] = 1 if rng.randf() < 0.72 else 0
		var home_a = scheduler.anchors[c.home_anchor_id]
		_p_pos[i] = home_a.pos
		_p_fwd[i] = home_a.facing
		_p_paths[i] = []


func _sync_all_citizens_to_hour(hour: float, rain: float) -> void:
	_active_crosswalk_peds.clear()
	for i in range(_ped_count):
		var c = scheduler.citizens[i]
		var eval: Dictionary = scheduler.evaluate_citizen_slot(c, hour)
		var slot_idx: int = eval["slot_idx"]
		var sl = eval["slot"]
		var prev_aid: int = eval["prev_anchor_id"]
		var prog: float = eval["progress"]
		_p_slot_idx[i] = slot_idx
		_p_sep_lat[i] = 0.0
		if sl == null or sl.anchor_id < 0:
			_p_state[i] = STATE_INDOORS
			continue

		var target_a = scheduler.anchors[sl.anchor_id]
		var prev_a = scheduler.anchors[prev_aid] if (prev_aid >= 0 and prev_aid < scheduler.anchors.size()) else target_a
		_p_cur_anchor[i] = prev_a.id
		_p_target_anchor[i] = target_a.id

		if sl.activity == NPCSchedulerScript.ACT_INDOORS:
			_p_state[i] = STATE_INDOORS
			_p_cur_speed[i] = 0.0
			_p_pos[i] = target_a.pos
			_p_fwd[i] = target_a.facing
			_p_paths[i] = []
		elif sl.activity == NPCSchedulerScript.ACT_BUS_WAIT:
			if prog < 0.35:
				_start_route_at_progress(i, prev_a.node_id, target_a.node_id, prog / 0.35)
			else:
				_p_state[i] = STATE_WAITING_BUS
				_p_cur_speed[i] = 0.0
				var jit := _anchor_scatter_offset(i, 0.85)
				_p_pos[i] = target_a.pos + jit
				_p_fwd[i] = target_a.facing
				_p_linger_timer[i] = 10.0
		elif sl.activity == NPCSchedulerScript.ACT_LINGER_OUTDOOR:
			if prog < 0.32 or rain > 0.65:
				# En route to/from plaza or hurrying indoors during heavy storm
				var r_prog := clampf(prog / 0.32, 0.04, 0.94) if prog < 0.32 else clampf(prog, 0.08, 0.92)
				_start_route_at_progress(i, prev_a.node_id, target_a.node_id, r_prog)
			else:
				_p_state[i] = STATE_LINGERING
				_p_cur_speed[i] = 0.0
				var jit := _anchor_scatter_offset(i, 1.45)
				var lp: Vector3 = target_a.pos + jit
				if not scheduler._is_outside_buildings(Vector2(lp.x, lp.z), 0.65):
					lp = target_a.pos
				_p_pos[i] = lp
				_p_fwd[i] = target_a.facing.rotated(Vector3.UP, float(i % 9) * 0.55 - 2.2)
				_p_linger_timer[i] = 14.0 + float(i % 15) * 1.4
		else:
			# ACT_TRAVEL: actively walking sidewalks, crosswalks, parks & footbridges toward target!
			_start_route_at_progress(i, prev_a.node_id, target_a.node_id, clampf(prog, 0.04, 0.94))


func _start_route_at_progress(idx: int, start_nid: int, goal_nid: int, prog: float) -> void:
	var path: Array = scheduler.find_edge_path(start_nid, goal_nid)
	if path.is_empty():
		path = scheduler.get_fallback_walk_path(start_nid, idx * 13 + _p_slot_idx[idx] * 7)
	if path.is_empty():
		_p_state[idx] = STATE_INDOORS
		_p_cur_speed[idx] = 0.0
		return

	var total_len := 0.0
	for step_d in path:
		total_len += float(scheduler.edges[int(step_d["edge_id"])].total_length)
	if total_len < 1.0:
		_p_state[idx] = STATE_INDOORS
		return

	var target_dist := clampf(prog, 0.0, 0.96) * total_len
	var accum := 0.0
	var chosen_pi := 0
	var chosen_s := 0.0
	for pi in range(path.size()):
		var ed = scheduler.edges[int(path[pi]["edge_id"])]
		if accum + float(ed.total_length) >= target_dist or pi == path.size() - 1:
			chosen_pi = pi
			var local_d := clampf(target_dist - accum, 0.0, float(ed.total_length))
			var dir_v := int(path[pi]["dir"])
			chosen_s = local_d if dir_v == 1 else (float(ed.total_length) - local_d)
			break
		accum += float(ed.total_length)

	var step_cur: Dictionary = path[chosen_pi]
	var eid := int(step_cur["edge_id"])
	var dir_v := int(step_cur["dir"])
	var ed = scheduler.edges[eid]

	# Avoid spawning a pedestrian inside a red crosswalk on instant time jumps
	if ed.is_crosswalk and ed.signal_node_id != -1 and _traffic_manager != null:
		if _traffic_manager.get_pedestrian_walk_state(ed.signal_node_id, ed.crosses_ns_traffic) != TrafficManagerScript.PED_WALK:
			var curb_pad := 0.10 + float(idx % 5) * 0.11
			chosen_s = curb_pad if dir_v == 1 else maxf(0.08, float(ed.total_length) - curb_pad)
			_p_state[idx] = STATE_WAITING_CROSSWALK
		else:
			_p_state[idx] = STATE_WALKING
	else:
		_p_state[idx] = STATE_WALKING

	_p_paths[idx] = path
	_p_path_idx[idx] = chosen_pi
	_p_edge_id[idx] = eid
	_p_edge_dir[idx] = dir_v
	_p_s[idx] = chosen_s
	_p_cur_speed[idx] = float(scheduler.citizens[idx].walk_speed) if _p_state[idx] == STATE_WALKING else 0.0

	var init_lat := _compute_edge_lat_offset(ed, dir_v, _p_lat_off[idx], 0.0)
	var sm := _sample_edge(ed, chosen_s, dir_v, init_lat)
	_p_pos[idx] = sm["pos"]
	_p_fwd[idx] = sm["fwd"]
	if ed.is_crosswalk and _p_state[idx] == STATE_WALKING and chosen_s > 0.45 and chosen_s < float(ed.total_length) - 0.45:
		_active_crosswalk_peds.append(_p_pos[idx])


func _rebuild_sep_grid(cam_pos: Vector3) -> void:
	_sep_grid.clear()
	var eff_cap := _get_effective_citizen_cap()
	var sep_r := VIS_RANGE * vis_range_scale + 22.0
	var sep_r2 := sep_r * sep_r
	var cx_cam := cam_pos.x
	var cz_cam := cam_pos.z
	for i in range(eff_cap):
		if _p_state[i] == STATE_INDOORS:
			continue
		var p := _p_pos[i]
		var dx := p.x - cx_cam
		var dz := p.z - cz_cam
		if dx * dx + dz * dz > sep_r2:
			continue
		var ck := _sep_cell_key(p.x, p.z)
		var arr: Array
		if _sep_grid.has(ck):
			arr = _sep_grid[ck]
		else:
			arr = []
			_sep_grid[ck] = arr
		arr.append(i)


func _simulate_citizens(base_dt: float) -> void:
	_active_crosswalk_peds.clear()
	var rain_hurry := 1.18 if _cur_rain > 0.25 else 1.0
	var stopped_buses: PackedVector3Array = _traffic_manager.get_stopped_bus_positions() if _traffic_manager != null else PackedVector3Array()
	var eff_cap := _get_effective_citizen_cap()
	var near_r := VIS_RANGE * vis_range_scale + 22.0
	var near_r2 := near_r * near_r
	var lod_div := maxi(1, far_lod_divisor)
	var lod_slot := _sim_frame_idx % lod_div
	var sched_slot := _sim_frame_idx % 12
	var cam_x := _last_cam_pos.x
	var cam_z := _last_cam_pos.z

	for i in range(eff_cap):
		var c = scheduler.citizens[i]
		var st := _p_state[i]

		# 1. Staggered 12-bucket schedule transition evaluation (cuts ~91% of per-frame schedule scans!)
		var sl = null
		if (i % 12) == sched_slot:
			var eval: Dictionary = scheduler.evaluate_citizen_slot(c, _cur_time_hour)
			var slot_idx: int = eval["slot_idx"]
			sl = eval["slot"]
			if slot_idx != _p_slot_idx[i] and sl != null and sl.anchor_id >= 0:
				_p_slot_idx[i] = slot_idx
				var from_aid: int = _p_target_anchor[i] if _p_target_anchor[i] >= 0 else int(c.home_anchor_id)
				var to_aid: int = sl.anchor_id
				_p_cur_anchor[i] = from_aid
				_p_target_anchor[i] = to_aid
				if sl.activity == NPCSchedulerScript.ACT_INDOORS and from_aid == to_aid:
					_p_state[i] = STATE_INDOORS
					_p_cur_speed[i] = 0.0
					continue
				else:
					var start_nid: int = scheduler.anchors[from_aid].node_id
					var goal_nid: int = scheduler.anchors[to_aid].node_id
					_start_route_at_progress(i, start_nid, goal_nid, 0.0)
				st = _p_state[i]

		if st == STATE_INDOORS:
			continue

		var pos_cur := _p_pos[i]
		var cdx := pos_cur.x - cam_x
		var cdz := pos_cur.z - cam_z
		var is_far := (lod_div > 1) and (cdx * cdx + cdz * cdz > near_r2)
		if is_far and (i % lod_div) != lod_slot:
			continue
		var dt := clampf(base_dt * float(lod_div), 0.0, 0.16) if is_far else base_dt

		if sl == null and _p_slot_idx[i] >= 0 and _p_slot_idx[i] < c.schedule.size():
			sl = c.schedule[_p_slot_idx[i]]

		if st == STATE_LINGERING:
			_p_cur_speed[i] = lerpf(_p_cur_speed[i], 0.0, clampf(dt * 8.0, 0.0, 1.0))
			_p_linger_timer[i] -= dt * (2.6 if _cur_rain > 0.40 else 1.0)
			if _p_linger_timer[i] <= 0.0:
				# Take a short scenic neighborhood/park stroll or return to current anchor
				var cur_nid: int = scheduler.anchors[_p_target_anchor[i]].node_id
				var stroll: Array = scheduler.get_fallback_walk_path(cur_nid, i * 19 + int(_sim_time))
				if not stroll.is_empty():
					_p_paths[i] = stroll
					_p_path_idx[i] = 0
					var st0: Dictionary = stroll[0]
					_p_edge_id[i] = int(st0["edge_id"])
					_p_edge_dir[i] = int(st0["dir"])
					var ed0 = scheduler.edges[_p_edge_id[i]]
					_p_s[i] = 0.0 if _p_edge_dir[i] == 1 else float(ed0.total_length)
					_p_state[i] = STATE_WALKING
				else:
					_p_linger_timer[i] = 16.0
			continue

		if st == STATE_WAITING_BUS:
			_p_cur_speed[i] = lerpf(_p_cur_speed[i], 0.0, clampf(dt * 8.0, 0.0, 1.0))
			_p_linger_timer[i] -= dt
			var bus_arrived := false
			var my_p := _p_pos[i]
			for bp in stopped_buses:
				if my_p.distance_squared_to(bp) < 110.0:
					bus_arrived = true
					break
			if bus_arrived or _p_linger_timer[i] <= 0.0:
				# Board bus -> emerge at work/destination bus stop and walk the final block!
				if c.work_bus_anchor_id >= 0 and c.work_anchor_id >= 0:
					var wb_nid: int = scheduler.anchors[c.work_bus_anchor_id].node_id
					var w_nid: int = scheduler.anchors[c.work_anchor_id].node_id
					_start_route_at_progress(i, wb_nid, w_nid, 0.0)
				else:
					_p_state[i] = STATE_INDOORS
			continue

		var eid := _p_edge_id[i]
		if eid < 0 or eid >= scheduler.edges.size():
			_p_state[i] = STATE_INDOORS
			continue
		var ed = scheduler.edges[eid]
		var dir_v := _p_edge_dir[i]

		# Crosswalk traffic-light obedience at signalized curbs!
		if st == STATE_WAITING_CROSSWALK:
			_p_cur_speed[i] = lerpf(_p_cur_speed[i], 0.0, clampf(dt * 10.0, 0.0, 1.0))
			var can_go := true
			if ed.is_crosswalk and ed.signal_node_id != -1 and _traffic_manager != null:
				can_go = (_traffic_manager.get_pedestrian_walk_state(ed.signal_node_id, ed.crosses_ns_traffic) == TrafficManagerScript.PED_WALK)
			if can_go:
				_p_state[i] = STATE_WALKING
			continue

		# STATE_WALKING: compute local crowd separation (near camera only) + speed moderation
		var base_spd: float = float(c.walk_speed) * rain_hurry
		var want_spd := base_spd
		var target_sep_lat := 0.0
		if not is_far:
			var sep_push := _compute_local_separation(i, pos_cur, _p_fwd[i])
			want_spd = base_spd * float(sep_push["spd_mult"])
			target_sep_lat = clampf(float(sep_push["lat_push"]), -0.45, 0.45)
		_p_sep_lat[i] = lerpf(_p_sep_lat[i], target_sep_lat, clampf(dt * 5.0, 0.0, 1.0))
		var spd := lerpf(_p_cur_speed[i], want_spd, clampf(dt * 8.0, 0.0, 1.0))
		_p_cur_speed[i] = spd

		# Natural sidewalk keep-right bias + wider multi-abreast spread across zebra crosswalks
		var signed_lat := _compute_edge_lat_offset(ed, dir_v, _p_lat_off[i], _p_sep_lat[i])

		var s_next := _p_s[i] + float(dir_v) * spd * dt
		var ed_len: float = float(ed.total_length)
		var finished_edge := (dir_v == 1 and s_next >= ed_len) or (dir_v == -1 and s_next <= 0.0)

		if not finished_edge:
			_p_s[i] = s_next
			_p_phase[i] = fposmod(_p_phase[i] + spd * dt * 4.7, TAU)
			var sm := _sample_edge(ed, s_next, dir_v, signed_lat)
			_p_pos[i] = sm["pos"]
			_p_fwd[i] = sm["fwd"]
			if ed.is_crosswalk and s_next > 0.45 and s_next < ed_len - 0.45:
				_active_crosswalk_peds.append(_p_pos[i])
		else:
			# Advance to next edge in citizen's A* path
			var path: Array = _p_paths[i]
			var next_pi := _p_path_idx[i] + 1
			if next_pi < path.size():
				var nxt_step: Dictionary = path[next_pi]
				var nxt_eid := int(nxt_step["edge_id"])
				var nxt_dir := int(nxt_step["dir"])
				var nxt_ed = scheduler.edges[nxt_eid]
				_p_path_idx[i] = next_pi
				_p_edge_id[i] = nxt_eid
				_p_edge_dir[i] = nxt_dir
				var curb_pad := 0.08 + float(i % 5) * 0.11 if nxt_ed.is_crosswalk else 0.08
				_p_s[i] = curb_pad if nxt_dir == 1 else maxf(0.08, float(nxt_ed.total_length) - curb_pad)
				var nxt_lat := _compute_edge_lat_offset(nxt_ed, nxt_dir, _p_lat_off[i], _p_sep_lat[i])
				var sm_n := _sample_edge(nxt_ed, _p_s[i], nxt_dir, nxt_lat)
				_p_pos[i] = sm_n["pos"]
				_p_fwd[i] = sm_n["fwd"]
				# Check signal before stepping into a signalized crosswalk!
				if nxt_ed.is_crosswalk and nxt_ed.signal_node_id != -1 and _traffic_manager != null:
					if _traffic_manager.get_pedestrian_walk_state(nxt_ed.signal_node_id, nxt_ed.crosses_ns_traffic) != TrafficManagerScript.PED_WALK:
						_p_state[i] = STATE_WAITING_CROSSWALK
						_p_cur_speed[i] = 0.0
			else:
				# Reached destination anchor!
				_on_citizen_arrived(i, sl)


func _on_citizen_arrived(idx: int, sl) -> void:
	if sl == null or sl.anchor_id < 0:
		_p_state[idx] = STATE_INDOORS
		_p_cur_speed[idx] = 0.0
		return
	var target_a = scheduler.anchors[sl.anchor_id]
	_p_cur_anchor[idx] = target_a.id
	if sl.activity == NPCSchedulerScript.ACT_BUS_WAIT:
		_p_state[idx] = STATE_WAITING_BUS
		_p_cur_speed[idx] = 0.0
		_p_pos[idx] = target_a.pos + _anchor_scatter_offset(idx, 0.85)
		_p_fwd[idx] = target_a.facing
		_p_linger_timer[idx] = 18.0
	elif sl.activity == NPCSchedulerScript.ACT_LINGER_OUTDOOR and _cur_rain < 0.65:
		_p_state[idx] = STATE_LINGERING
		_p_cur_speed[idx] = 0.0
		var lp: Vector3 = target_a.pos + _anchor_scatter_offset(idx, 1.35)
		if not scheduler._is_outside_buildings(Vector2(lp.x, lp.z), 0.65):
			lp = target_a.pos
		_p_pos[idx] = lp
		_p_fwd[idx] = target_a.facing
		_p_linger_timer[idx] = 16.0 + float(idx % 12) * 1.5
	elif sl.activity == NPCSchedulerScript.ACT_TRAVEL and sl.label in ["midday_errand", "evening_stroll", "morning_walk", "afternoon_errand", "after_school", "evening_leisure", "lunch", "break"]:
		# Keep daytime/evening errand walkers strolling cleanly rather than vanishing prematurely
		var stroll: Array = scheduler.get_fallback_walk_path(target_a.node_id, idx * 23 + int(_sim_time))
		if not stroll.is_empty():
			_p_paths[idx] = stroll
			_p_path_idx[idx] = 0
			var st0: Dictionary = stroll[0]
			_p_edge_id[idx] = int(st0["edge_id"])
			_p_edge_dir[idx] = int(st0["dir"])
			var ed0 = scheduler.edges[_p_edge_id[idx]]
			_p_s[idx] = 0.0 if _p_edge_dir[idx] == 1 else float(ed0.total_length)
			_p_state[idx] = STATE_WALKING
		else:
			_p_state[idx] = STATE_INDOORS
			_p_cur_speed[idx] = 0.0
	else:
		# Entered home / office / school / hospital / shop doorway!
		_p_state[idx] = STATE_INDOORS
		_p_cur_speed[idx] = 0.0
		_p_pos[idx] = target_a.pos


func _compute_local_separation(self_idx: int, pos: Vector3, fwd: Vector3) -> Dictionary:
	var cx := int(floor(pos.x / SEP_CELL_SIZE))
	var cz := int(floor(pos.z / SEP_CELL_SIZE))
	var lat_push := 0.0
	var spd_mult := 1.0
	var right_x := -fwd.z
	var right_z := fwd.x
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var ck := (cx + ox + 512) * 2048 + (cz + oz + 512)
			if not _sep_grid.has(ck):
				continue
			for j_var in _sep_grid[ck]:
				var j: int = j_var
				if j == self_idx:
					continue
				var pj := _p_pos[j]
				var dx := pj.x - pos.x
				var dz := pj.z - pos.z
				var d2 := dx * dx + dz * dz
				if d2 > 3.24 or d2 < 0.0001:
					continue
				var fwd_d := dx * fwd.x + dz * fwd.z
				if fwd_d < -0.35:
					continue
				var lat_d := dx * right_x + dz * right_z
				if absf(lat_d) < 0.85:
					# Sidestep right away from nearby pedestrian
					lat_push += (0.42 if lat_d <= 0.0 else -0.42) * (1.0 - sqrt(d2) / 1.8)
					if fwd_d > 0.1 and fwd_d < 1.15 and absf(lat_d) < 0.42:
						spd_mult = minf(spd_mult, 0.58)
	return {"lat_push": lat_push, "spd_mult": spd_mult}


static func _compute_edge_lat_offset(ed, dir_val: int, personal_off: float, sep_lat: float) -> float:
	if ed.is_crosswalk:
		# Spread naturally 2-3 abreast across the 2.8m zebra crosswalk
		return (0.14 + personal_off * 2.15 + sep_lat * 1.25) * float(dir_val)
	# Keep-right sidewalk flow safely inside curb/facade clearances
	return (0.24 + personal_off * 0.72 + sep_lat) * float(dir_val)


static func _sep_cell_key(x: float, z: float) -> int:
	return (int(floor(x / SEP_CELL_SIZE)) + 512) * 2048 + (int(floor(z / SEP_CELL_SIZE)) + 512)


static func _anchor_scatter_offset(idx: int, radius: float) -> Vector3:
	var ang := float(posmod(idx * 137, 360)) * PI / 180.0
	var r := radius * (0.35 + 0.65 * float(posmod(idx * 29, 10)) / 9.0)
	return Vector3(cos(ang) * r, 0.0, sin(ang) * r)


func _sample_edge(ed, s: float, dir_val: int, signed_lat: float) -> Dictionary:
	var pts: PackedVector3Array = ed.points
	var cum: PackedFloat32Array = ed.cum_lengths
	var cnt := pts.size()
	var cs := clampf(s, 0.0, float(ed.total_length))

	var lo := 0
	var hi := cnt - 2
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if cum[mid] <= cs:
			lo = mid
		else:
			hi = mid - 1

	var s0 := cum[lo]
	var s1 := cum[lo + 1]
	var frac := clampf((cs - s0) / maxf(0.0001, s1 - s0), 0.0, 1.0)
	var pos := pts[lo].lerp(pts[lo + 1], frac)
	var seg_d := pts[lo + 1] - pts[lo]
	var fwd_xz := Vector2(seg_d.x, seg_d.z)
	if fwd_xz.length_squared() < 0.00001:
		fwd_xz = Vector2(0.0, 1.0)
	else:
		fwd_xz = fwd_xz.normalized()

	var right_xz := Vector2(-fwd_xz.y, fwd_xz.x)
	pos.x += right_xz.x * signed_lat
	pos.z += right_xz.y * signed_lat
	var travel_xz := fwd_xz * float(dir_val)
	return {
		"pos": pos,
		"fwd": Vector3(travel_xz.x, 0.0, travel_xz.y),
	}


func _build_renderers() -> void:
	var walk_shader := load(PED_WALK_SHADER_PATH) as Shader
	_ped_mat = ShaderMaterial.new()
	_ped_mat.shader = walk_shader

	var ws := _plan.config.world_size
	var city_aabb := AABB(Vector3(-24.0, -24.0, -24.0), Vector3(ws + 48.0, 160.0, ws + 48.0))

	_ped_mm = MultiMesh.new()
	_ped_mm.transform_format = MultiMesh.TRANSFORM_3D
	_ped_mm.use_custom_data = true
	_ped_mm.mesh = _cached_ped_mesh
	_ped_mm.instance_count = maxi(1, _ped_count)
	_ped_mm.visible_instance_count = 0

	_ped_mmi = MultiMeshInstance3D.new()
	_ped_mmi.name = "CityPedestrians"
	_ped_mmi.multimesh = _ped_mm
	_ped_mmi.material_override = _ped_mat
	_ped_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# NOTE: Do NOT set visibility_range_end on city-wide dynamic MultiMeshInstance3D!
	# Godot measures visibility_range_end from the camera to custom_aabb center, which
	# would hide all pedestrians whenever the camera is >VIS_RANGE from city center.
	# Per-instance distance culling is already performed against cam_pos in _upload_multimeshes().
	_ped_mmi.custom_aabb = city_aabb
	_ped_mmi.visible = false
	add_child(_ped_mmi)

	# Shared vertex-colored accessory shader for commuter backpacks & rain umbrellas
	_acc_mat = ShaderMaterial.new()
	_acc_mat.shader = _cached_accessory_shader

	_bag_mm = MultiMesh.new()
	_bag_mm.transform_format = MultiMesh.TRANSFORM_3D
	_bag_mm.use_custom_data = true
	_bag_mm.mesh = _cached_bag_mesh
	_bag_mm.instance_count = maxi(1, _ped_count)
	_bag_mm.visible_instance_count = 0

	_bag_mmi = MultiMeshInstance3D.new()
	_bag_mmi.name = "PedestrianBags"
	_bag_mmi.multimesh = _bag_mm
	_bag_mmi.material_override = _acc_mat
	_bag_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bag_mmi.custom_aabb = city_aabb
	_bag_mmi.visible = false
	add_child(_bag_mmi)

	_umb_mm = MultiMesh.new()
	_umb_mm.transform_format = MultiMesh.TRANSFORM_3D
	_umb_mm.use_custom_data = true
	_umb_mm.mesh = _cached_umbrella_mesh
	_umb_mm.instance_count = maxi(1, _ped_count)
	_umb_mm.visible_instance_count = 0

	_umb_mmi = MultiMeshInstance3D.new()
	_umb_mmi.name = "PedestrianUmbrellas"
	_umb_mmi.multimesh = _umb_mm
	_umb_mmi.material_override = _acc_mat
	_umb_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_umb_mmi.custom_aabb = city_aabb
	_umb_mmi.visible = false
	add_child(_umb_mmi)


func _upload_multimeshes(cam_pos: Vector3) -> void:
	var eff_vis := VIS_RANGE * vis_range_scale
	var vis_r2 := eff_vis * eff_vis
	var eff_cap := _get_effective_citizen_cap()
	var ped_slot := 0
	var bag_slot := 0
	var umb_slot := 0
	var rain_umbrellas := _cur_rain > 0.22

	for i in range(eff_cap):
		if _p_state[i] == STATE_INDOORS:
			continue
		var pos := _p_pos[i]
		var dx := pos.x - cam_pos.x
		var dz := pos.z - cam_pos.z
		if dx * dx + dz * dz > vis_r2:
			continue

		var f := _p_fwd[i]
		if f.length_squared() < 0.0001:
			f = Vector3(0.0, 0.0, 1.0)
		else:
			f = f.normalized()
		var r := Vector3.UP.cross(f)
		if r.length_squared() < 0.0001:
			r = Vector3.RIGHT
		else:
			r = r.normalized()
		var basis := Basis(r, Vector3.UP, f)
		var c = scheduler.citizens[i]
		var spd := _p_cur_speed[i]
		var role_seed := float(c.role) + float(c.palette_seed) * 0.94

		var b_scale: float = float(c.body_scale)
		if ped_slot < _ped_mm.instance_count:
			_ped_mm.set_instance_transform(ped_slot, Transform3D(basis, pos))
			_ped_mm.set_instance_custom_data(ped_slot, Color(_p_phase[i], spd, role_seed, b_scale))
			ped_slot += 1

		if c.has_bag and bag_slot < _bag_mm.instance_count:
			var bag_xf := Transform3D(basis.scaled(Vector3.ONE * b_scale), pos + Vector3(0.0, absf(cos(_p_phase[i])) * 0.028 * clampf(spd / 1.35, 0.0, 1.2), 0.0))
			_bag_mm.set_instance_transform(bag_slot, bag_xf)
			_bag_mm.set_instance_custom_data(bag_slot, Color(float(c.palette_seed), 0.0, 0.0, 1.0))
			bag_slot += 1

		if rain_umbrellas and _p_has_umbrella[i] == 1 and umb_slot < _umb_mm.instance_count:
			var bob := absf(cos(_p_phase[i])) * 0.025 * clampf(spd / 1.35, 0.0, 1.2)
			var umb_xf := Transform3D(basis.scaled(Vector3.ONE * b_scale), pos + Vector3(0.0, bob, 0.0))
			_umb_mm.set_instance_transform(umb_slot, umb_xf)
			_umb_mm.set_instance_custom_data(umb_slot, Color(float(c.umbrella_seed), 1.0, 0.0, 1.0))
			umb_slot += 1

	_ped_mm.visible_instance_count = ped_slot
	_ped_mmi.visible = (ped_slot > 0)
	_bag_mm.visible_instance_count = bag_slot
	_bag_mmi.visible = (bag_slot > 0)
	_umb_mm.visible_instance_count = umb_slot
	_umb_mmi.visible = (umb_slot > 0)


static func _ensure_shared_meshes() -> void:
	if _cached_ped_mesh == null:
		_cached_ped_mesh = _build_pedestrian_mesh()
	if _cached_bag_mesh == null:
		_cached_bag_mesh = _build_bag_mesh()
	if _cached_umbrella_mesh == null:
		_cached_umbrella_mesh = _build_umbrella_mesh()
	if _cached_accessory_shader == null:
		_cached_accessory_shader = Shader.new()
		_cached_accessory_shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform float weather_wetness;

varying vec4 v_custom;
varying vec4 v_color;

vec3 pick6(float s, vec3 c0, vec3 c1, vec3 c2, vec3 c3, vec3 c4, vec3 c5) {
	int idx = int(floor(fract(s) * 6.0)) % 6;
	if (idx == 0) return c0;
	if (idx == 1) return c1;
	if (idx == 2) return c2;
	if (idx == 3) return c3;
	if (idx == 4) return c4;
	return c5;
}

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_color = COLOR;
}

void fragment() {
	float seed = v_custom.r;
	bool is_umbrella = v_custom.g > 0.5;
	vec3 col;
	float rough = 0.68;
	if (v_color.b > 0.5) {
		// Handle / metallic shaft / bag straps
		col = vec3(0.14, 0.15, 0.17);
		rough = 0.45;
	} else if (is_umbrella) {
		col = pick6(
			seed,
			vec3(0.14, 0.24, 0.42),
			vec3(0.76, 0.18, 0.18),
			vec3(0.16, 0.46, 0.36),
			vec3(0.86, 0.64, 0.14),
			vec3(0.20, 0.20, 0.24),
			vec3(0.22, 0.50, 0.68)
		);
		rough = mix(0.42, 0.16, weather_wetness);
	} else {
		// Commuter backpacks / satchels
		col = pick6(
			seed,
			vec3(0.14, 0.16, 0.20),
			vec3(0.32, 0.20, 0.14),
			vec3(0.16, 0.28, 0.40),
			vec3(0.42, 0.18, 0.16),
			vec3(0.24, 0.32, 0.26),
			vec3(0.28, 0.28, 0.30)
		);
		rough = 0.80;
	}
	ALBEDO = col * mix(1.0, 0.84, weather_wetness);
	ROUGHNESS = rough;
	METALLIC = v_color.b > 0.5 ? 0.45 : 0.02;
}
"""


static func _build_pedestrian_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# COLOR encoding: (limb_id, part_id, is_shadow_disc, ao_shade)
	# limb_id: 0.0=torso/head, 0.25=left_leg, 0.50=right_leg, 0.75=left_arm, 1.0=right_arm
	# part_id: 0.0=skin, 0.25=hair, 0.50=jacket/shirt, 0.75=pants, 1.0=shoes
	# is_shadow_disc: 1.0 for flat ground contact shadow disc beneath feet

	# Ground contact shadow disc right beneath feet (y = 0.018, stays planted while walking)
	var sh_col := Color(0.0, 1.0, 1.0, 0.80)
	var sh_r := 0.24
	for si in range(6):
		var a0 := float(si) * TAU / 6.0
		var a1 := float(si + 1) * TAU / 6.0
		_emit_tri(st, Vector3(0.0, 0.018, 0.0), Vector3(cos(a1) * sh_r, 0.018, sin(a1) * sh_r), Vector3(cos(a0) * sh_r, 0.018, sin(a0) * sh_r), Vector3.UP, sh_col)

	# Tapered legs & sculpted shoes (feet at y=0.0, hip pivot y=0.80)
	_emit_tapered_box(st, Vector3(-0.092, 0.45, 0.0), Vector3(0.115, 0.70, 0.125), Vector2(0.14, 0.155), Color(0.25, 0.75, 0.0, 0.94))
	_emit_tapered_box(st, Vector3(-0.092, 0.05, 0.036), Vector3(0.125, 0.10, 0.23), Vector2(0.11, 0.18), Color(0.25, 1.0, 0.0, 0.90))
	_emit_tapered_box(st, Vector3(0.092, 0.45, 0.0), Vector3(0.115, 0.70, 0.125), Vector2(0.14, 0.155), Color(0.50, 0.75, 0.0, 0.94))
	_emit_tapered_box(st, Vector3(0.092, 0.05, 0.036), Vector3(0.125, 0.10, 0.23), Vector2(0.11, 0.18), Color(0.50, 1.0, 0.0, 0.90))

	# Pelvis + athletic tapered upper torso & shoulder yoke
	_emit_box(st, Vector3(0.0, 0.83, 0.0), Vector3(0.32, 0.14, 0.185), Color(0.0, 0.75, 0.0, 0.92))
	_emit_tapered_box(st, Vector3(0.0, 1.15, 0.0), Vector3(0.32, 0.52, 0.185), Vector2(0.41, 0.215), Color(0.0, 0.50, 0.0, 1.00))
	# Subtle collar/shoulder cap
	_emit_tapered_box(st, Vector3(0.0, 1.41, 0.0), Vector3(0.40, 0.06, 0.20), Vector2(0.18, 0.14), Color(0.0, 0.50, 0.0, 0.95))

	# Tapered arms & hands (shoulder pivot y=1.38)
	_emit_tapered_box(st, Vector3(-0.245, 1.12, 0.0), Vector3(0.088, 0.52, 0.098), Vector2(0.112, 0.118), Color(0.75, 0.50, 0.0, 0.96))
	_emit_box(st, Vector3(-0.245, 0.82, 0.01), Vector3(0.075, 0.095, 0.09), Color(0.75, 0.0, 0.0, 0.96))
	_emit_tapered_box(st, Vector3(0.245, 1.12, 0.0), Vector3(0.088, 0.52, 0.098), Vector2(0.112, 0.118), Color(1.0, 0.50, 0.0, 0.96))
	_emit_box(st, Vector3(0.245, 0.82, 0.01), Vector3(0.075, 0.095, 0.09), Color(1.0, 0.0, 0.0, 0.96))

	# Neck, sculpted beveled head & contoured hair cap (crown at y=1.72)
	_emit_box(st, Vector3(0.0, 1.45, 0.0), Vector3(0.095, 0.07, 0.095), Color(0.0, 0.0, 0.0, 0.92))
	_emit_tapered_box(st, Vector3(0.0, 1.565, 0.012), Vector3(0.155, 0.19, 0.165), Vector2(0.175, 0.185), Color(0.0, 0.0, 0.0, 1.00))
	_emit_tapered_box(st, Vector3(0.0, 1.665, -0.012), Vector3(0.188, 0.11, 0.205), Vector2(0.152, 0.165), Color(0.0, 0.25, 0.0, 0.95))

	return st.commit()


static func _build_bag_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fabric := Color(1.0, 0.0, 0.0, 1.0)
	var strap := Color(0.0, 0.0, 1.0, 1.0)
	# Sleek backpack worn on upper back (-Z)
	_emit_tapered_box(st, Vector3(0.0, 1.16, -0.175), Vector3(0.28, 0.36, 0.14), Vector2(0.23, 0.11), fabric)
	_emit_box(st, Vector3(0.0, 1.07, -0.25), Vector3(0.22, 0.14, 0.04), strap)
	return st.commit()


static func _build_umbrella_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var canopy := Color(1.0, 0.0, 0.0, 1.0)
	var shaft := Color(0.0, 0.0, 1.0, 1.0)

	# Held slightly off right shoulder (+0.16 X, +0.06 Z), domed 8-panel canopy at y=1.96..2.18
	var ux := 0.16
	var uz := 0.05
	_emit_box(st, Vector3(ux, 1.54, uz), Vector3(0.022, 1.10, 0.022), shaft)
	var apex := Vector3(ux, 2.18, uz)
	var mid_y := 2.09
	var rim_y := 1.94
	var mid_r := 0.32
	var rim_r := 0.56
	const PANELS := 8
	for pi in range(PANELS):
		var a0 := float(pi) * TAU / float(PANELS)
		var a1 := float(pi + 1) * TAU / float(PANELS)
		var m0 := Vector3(ux + cos(a0) * mid_r, mid_y, uz + sin(a0) * mid_r)
		var m1 := Vector3(ux + cos(a1) * mid_r, mid_y, uz + sin(a1) * mid_r)
		var r0 := Vector3(ux + cos(a0) * rim_r, rim_y, uz + sin(a0) * rim_r)
		var r1 := Vector3(ux + cos(a1) * rim_r, rim_y, uz + sin(a1) * rim_r)
		var ma := (a0 + a1) * 0.5
		var n_top := Vector3(cos(ma) * 0.35, 0.94, sin(ma) * 0.35).normalized()
		var n_rim := Vector3(cos(ma) * 0.62, 0.78, sin(ma) * 0.62).normalized()
		_emit_tri(st, apex, m0, m1, n_top, canopy)
		_emit_quad(st, m0, m1, r0, r1, n_rim, canopy)
	return st.commit()


static func _emit_box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color) -> void:
	_emit_tapered_box(st, center, size, Vector2(size.x, size.z), col)


static func _emit_tapered_box(st: SurfaceTool, center: Vector3, bot_size: Vector3, top_xz: Vector2, col: Color) -> void:
	var hx0 := bot_size.x * 0.5
	var hz0 := bot_size.z * 0.5
	var hx1 := top_xz.x * 0.5
	var hz1 := top_xz.y * 0.5
	var hy := bot_size.y * 0.5

	var b00 := center + Vector3(-hx0, -hy, -hz0)
	var b10 := center + Vector3(hx0, -hy, -hz0)
	var b01 := center + Vector3(-hx0, -hy, hz0)
	var b11 := center + Vector3(hx0, -hy, hz0)

	var t00 := center + Vector3(-hx1, hy, -hz1)
	var t10 := center + Vector3(hx1, hy, -hz1)
	var t01 := center + Vector3(-hx1, hy, hz1)
	var t11 := center + Vector3(hx1, hy, hz1)

	_emit_quad(st, t00, t10, t01, t11, Vector3.UP, col)
	_emit_quad(st, b01, b11, b00, b10, Vector3.DOWN, col)
	_emit_quad(st, t01, t11, b01, b11, (t01 - b01).cross(t11 - b01).normalized(), col)
	_emit_quad(st, t10, t00, b10, b00, (t10 - b10).cross(t00 - b10).normalized(), col)
	_emit_quad(st, t11, t10, b11, b10, (t11 - b11).cross(t10 - b11).normalized(), col)
	_emit_quad(st, t00, t01, b00, b01, (t00 - b00).cross(t01 - b00).normalized(), col)


static func _emit_quad(st: SurfaceTool, tl: Vector3, tr: Vector3, bl: Vector3, br: Vector3, desired_n: Vector3, col: Color) -> void:
	var n_test := (bl - tl).cross(tr - tl)
	var pts := [tl, tr, bl, tr, br, bl] if n_test.dot(desired_n) >= 0.0 else [tl, bl, tr, tr, bl, br]
	var n := desired_n.normalized()
	if n.length_squared() < 0.001:
		n = Vector3.UP
	for p in pts:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(p)


static func _emit_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, desired_n: Vector3, col: Color) -> void:
	var n_test := (c - a).cross(b - a)
	var pts := [a, b, c] if n_test.dot(desired_n) >= 0.0 else [a, c, b]
	var n := desired_n.normalized()
	if n.length_squared() < 0.001:
		n = Vector3.UP
	for p in pts:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(p)
