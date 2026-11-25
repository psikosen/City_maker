class_name TrafficManager
extends Node3D

## Node-free procedural urban vehicle & river vessel simulation featuring:
## - 8 sculpted procedural vehicle archetypes (Sedan, SUV, Hatchback, Pickup, Van, Bus, Taxi, Emergency)
## - Intelligent Driver Model (IDM) longitudinal physics with weather headway/speed adaptation
## - MOBIL-inspired polite lane changing on 4-lane arterials
## - Synchronized 3-aspect traffic signals, unprotected left-turn gap acceptance & deadlock watchdog
## - Scheduled arterial bus stops at transit shelters + live pedestrian crosswalk yielding
## - Time-of-day diurnal rush-hour demand waves & destination-biased routing
## - Dynamic body pitch/roll, blinking turn indicators & emergency roof lightbars

const CELL_SIZE := 16.0
const VIS_RANGE := 280.0
const SIGNAL_GREEN_TIME := 14.0
const SIGNAL_AMBER_TIME := 2.5
const SIGNAL_ALL_RED_TIME := 1.5
const SIGNAL_HALF_CYCLE := 18.0
const SIGNAL_CYCLE := 36.0
const TARGET_VEHICLE_COUNT := 620
const TARGET_BOAT_COUNT := 14
const BOAT_VIS_RANGE := 420.0

const VEH_SEDAN := 0
const VEH_SUV := 1
const VEH_HATCHBACK := 2
const VEH_PICKUP := 3
const VEH_VAN := 4
const VEH_BUS := 5
const VEH_TAXI := 6
const VEH_EMERGENCY := 7
const VEH_TYPE_COUNT := 8

const SIG_GREEN := 0
const SIG_AMBER := 1
const SIG_RED := 2

const PED_WALK := 0
const PED_FLASHING := 1
const PED_STOP := 2

const CAR_PAINT_SHADER_PATH := "res://src/city_world/shaders/car_paint.gdshader"

const TYPE_LENGTHS := [4.42, 4.68, 3.88, 5.28, 5.42, 10.20, 4.42, 4.65]
const TYPE_WIDTHS := [1.84, 1.96, 1.78, 2.02, 2.04, 2.44, 1.84, 1.92]
const TYPE_LIGHT_YS := [0.64, 0.74, 0.62, 0.78, 0.80, 0.88, 0.64, 0.68]
const TYPE_MAX_ACCEL := [3.4, 3.0, 3.6, 2.8, 2.5, 1.85, 3.5, 4.2]
const TYPE_COMF_DECEL := [3.8, 3.5, 4.0, 3.3, 3.1, 2.5, 3.8, 4.4]
const TYPE_HEADWAY := [1.25, 1.35, 1.18, 1.42, 1.48, 1.75, 1.15, 1.05]

const CAR_PALETTE := [
	Color(0.86, 0.88, 0.91),
	Color(0.15, 0.23, 0.35),
	Color(0.58, 0.16, 0.16),
	Color(0.22, 0.34, 0.29),
	Color(0.11, 0.12, 0.15),
	Color(0.62, 0.65, 0.69),
	Color(0.72, 0.65, 0.52),
	Color(0.13, 0.38, 0.58),
	Color(0.70, 0.34, 0.15),
	Color(0.32, 0.24, 0.38),
	Color(0.20, 0.44, 0.42),
]

const PICKUP_PALETTE := [
	Color(0.16, 0.24, 0.38),
	Color(0.58, 0.16, 0.14),
	Color(0.85, 0.87, 0.89),
	Color(0.22, 0.24, 0.26),
	Color(0.34, 0.38, 0.30),
]

const VAN_PALETTE := [
	Color(0.90, 0.92, 0.94),
	Color(0.22, 0.42, 0.66),
	Color(0.74, 0.76, 0.78),
]

const BUS_PALETTE := [
	Color(0.12, 0.46, 0.56),
	Color(0.14, 0.34, 0.62),
]

const BOAT_PALETTE := [
	Color(0.92, 0.94, 0.96),
	Color(0.14, 0.28, 0.48),
	Color(0.12, 0.44, 0.48),
	Color(0.68, 0.24, 0.18),
]

static var _cached_body_meshes: Array[ArrayMesh] = []
static var _cached_boat_mesh: ArrayMesh = null
static var _cached_light_mesh: ArrayMesh = null
static var _cached_signal_mesh: ArrayMesh = null
static var _cached_light_shader: Shader = null
static var _cached_signal_shader: Shader = null

var _plan: CityPlan = null
var _road_graph: RoadGraph = null
var _sim_time: float = 0.0
var _turn_counter: int = 0
var _cur_time_hour: float = 10.5
var _cur_weather_wetness: float = 0.0
var _active_target_count: int = 0
var _active_vehicle_count: int = 0
var _lane_changes_total: int = 0
var _downtown_center: Vector2 = Vector2.ZERO
var _residential_center: Vector2 = Vector2.ZERO

# Performance & quality scaling (controlled by PerformanceController)
var density_scale: float = 1.0
var vis_range_scale: float = 1.0
var far_lod_divisor: int = 4
var _sim_frame_idx: int = 0
var _last_cam_pos: Vector3 = Vector3.ZERO
var _last_demand_sync: float = -1.0
var _demand_check_timer: float = 0.0

# Flat typed simulation arrays for vehicles
var _veh_count: int = 0
var _v_type: PackedInt32Array = PackedInt32Array()
var _v_active: PackedByteArray = PackedByteArray()
var _v_priority_rank: PackedFloat32Array = PackedFloat32Array()
var _v_lane_id: PackedInt32Array = PackedInt32Array()
var _v_next_lane_id: PackedInt32Array = PackedInt32Array()
var _v_turn_dir: PackedInt32Array = PackedInt32Array() # -1=left, 0=straight, 1=right
var _v_s: PackedFloat32Array = PackedFloat32Array()
var _v_in_junction: PackedByteArray = PackedByteArray()
var _v_junc_p0: PackedVector3Array = PackedVector3Array()
var _v_junc_p1: PackedVector3Array = PackedVector3Array()
var _v_junc_p2: PackedVector3Array = PackedVector3Array()
var _v_junc_p3: PackedVector3Array = PackedVector3Array()
var _v_junc_len: PackedFloat32Array = PackedFloat32Array()
var _v_speed: PackedFloat32Array = PackedFloat32Array()
var _v_accel: PackedFloat32Array = PackedFloat32Array()
var _v_max_mult: PackedFloat32Array = PackedFloat32Array()
var _v_brake: PackedFloat32Array = PackedFloat32Array()
var _v_blinker: PackedInt32Array = PackedInt32Array() # 0=none, 1=left, 2=right, 3=hazard
var _v_pitch: PackedFloat32Array = PackedFloat32Array()
var _v_roll: PackedFloat32Array = PackedFloat32Array()
var _v_half_len: PackedFloat32Array = PackedFloat32Array()
var _v_lat_shift: PackedFloat32Array = PackedFloat32Array()
var _v_lc_offset: PackedFloat32Array = PackedFloat32Array()
var _v_lc_cooldown: PackedFloat32Array = PackedFloat32Array()
var _v_stuck_timer: PackedFloat32Array = PackedFloat32Array()
var _v_bus_dwell: PackedFloat32Array = PackedFloat32Array()
var _v_bus_last_stop: PackedInt32Array = PackedInt32Array()
var _v_pos: PackedVector3Array = PackedVector3Array()
var _v_dir: PackedVector3Array = PackedVector3Array()
var _v_color: PackedColorArray = PackedColorArray()

# Spatial hashes (16m cells) for IDM following, parked EVs, and live crossing pedestrians
var _veh_grid: Dictionary = {}
var _parked_grid: Dictionary = {}
var _ped_cross_grid: Dictionary = {}
var _lane_bus_stops: Dictionary = {} # lane_id -> Array[Dictionary {s, stop_idx, pos}]
var _stopped_bus_positions: PackedVector3Array = PackedVector3Array()

# Intersection signal phase offsets (node_id -> float seconds)
var _signal_offsets: Dictionary = {}

# MultiMesh renderers (8 vehicle types + 1 vehicle lights + 1 traffic signal lenses)
var _body_mmis: Array[MultiMeshInstance3D] = []
var _body_mms: Array[MultiMesh] = []
var _type_counts: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
var _lights_mmi: MultiMeshInstance3D = null
var _lights_mm: MultiMesh = null
var _lights_mat: ShaderMaterial = null

var _signals_mmi: MultiMeshInstance3D = null
var _signals_mm: MultiMesh = null
var _signals_mat: ShaderMaterial = null
var _sig_node_ids: PackedInt32Array = PackedInt32Array()
var _sig_is_ns: PackedByteArray = PackedByteArray()
var _sig_last_state: PackedInt32Array = PackedInt32Array()

# Ambient river vessels cruising along the river centerline
var _boat_count: int = 0
var _boat_s: PackedFloat32Array = PackedFloat32Array()
var _boat_dir: PackedInt32Array = PackedInt32Array()
var _boat_speed: PackedFloat32Array = PackedFloat32Array()
var _boat_lat: PackedFloat32Array = PackedFloat32Array()
var _boat_color: PackedColorArray = PackedColorArray()
var _river_pts: PackedVector3Array = PackedVector3Array()
var _river_cum: PackedFloat32Array = PackedFloat32Array()
var _river_total_len: float = 0.0
var _boat_mmi: MultiMeshInstance3D = null
var _boat_mm: MultiMesh = null


func setup(p_plan: CityPlan, _p_mats: MaterialLibrary) -> void:
	_clear_renderers()
	_reset_state()
	_plan = p_plan
	if _plan == null or _plan.road_graph == null:
		return
	_road_graph = _plan.road_graph
	if _road_graph.lanes.is_empty():
		return

	var ws := _plan.config.world_size
	_downtown_center = _plan.district_centers.get("downtown_mixed", Vector2(ws * 0.45, ws * 0.45))
	_residential_center = _plan.district_centers.get("residential_hills", Vector2(ws * 0.72, ws * 0.25))

	_ensure_shared_assets()
	_build_signal_table()
	_build_parked_ev_grid()
	_build_bus_stops_table()
	_spawn_vehicles()
	_spawn_river_boats()
	_build_renderers()
	_build_signal_lenses()

	var init_cam := _plan.spawn_position
	step(0.0, init_cam, 0.0, 10.5, 0.0, 0.0)


func step(
	delta: float,
	cam_pos: Vector3,
	night_factor: float,
	time_hour: float = 10.5,
	_weather_rain: float = 0.0,
	weather_wetness: float = 0.0
) -> void:
	if _plan == null or _road_graph == null:
		return

	var dt := clampf(delta, 0.0, 0.05)
	_sim_time += dt
	_sim_frame_idx += 1
	_last_cam_pos = cam_pos
	_cur_time_hour = fposmod(time_hour, 24.0)
	_cur_weather_wetness = clampf(weather_wetness, 0.0, 1.0)

	if _lights_mat != null:
		_lights_mat.set_shader_parameter("night_level", clampf(night_factor, 0.0, 1.0))
	if _signals_mat != null:
		_signals_mat.set_shader_parameter("night_level", clampf(night_factor, 0.0, 1.0))

	_update_signal_lenses()
	_demand_check_timer += dt
	var cur_demand := compute_diurnal_demand(_cur_time_hour) * density_scale
	if _last_demand_sync < 0.0 or absf(cur_demand - _last_demand_sync) > 0.015 or _demand_check_timer >= 0.35:
		_demand_check_timer = 0.0
		_last_demand_sync = cur_demand
		_update_diurnal_active_fleet()

	if _veh_count > 0:
		if dt > 0.0:
			_rebuild_vehicle_grid()
			_simulate_vehicles(dt)
		_upload_vehicle_multimeshes(cam_pos)

	if _boat_count > 0:
		if dt > 0.0:
			_simulate_river_boats(dt)
		_upload_river_boats(cam_pos)


func set_performance_profile(p_density_scale: float, p_vis_scale: float = 1.0, p_far_lod_divisor: int = 4) -> void:
	density_scale = clampf(p_density_scale, 0.20, 1.0)
	vis_range_scale = clampf(p_vis_scale, 0.45, 1.30)
	far_lod_divisor = clampi(p_far_lod_divisor, 1, 6)
	_last_demand_sync = -1.0
	if _plan != null and _veh_count > 0:
		_update_diurnal_active_fleet()


func get_vehicle_count() -> int:
	return _veh_count


func get_active_vehicle_count() -> int:
	return _active_vehicle_count


func get_pedestrian_walk_state(node_id: int, crosses_ns_traffic: bool) -> int:
	## Returns PED_WALK when the road being crossed is RED and perpendicular phase is GREEN.
	if not _signal_offsets.has(node_id):
		return PED_WALK
	var off := float(_signal_offsets[node_id])
	var phase := fposmod(_sim_time + off, SIGNAL_CYCLE)
	# Crossing a N-S road means pedestrians walk during the E-W active half!
	var active_half_t := (phase - SIGNAL_HALF_CYCLE) if crosses_ns_traffic else phase
	if active_half_t < 0.0 or active_half_t >= SIGNAL_HALF_CYCLE:
		return PED_STOP
	if active_half_t < SIGNAL_GREEN_TIME - 3.0:
		return PED_WALK
	if active_half_t < SIGNAL_GREEN_TIME + SIGNAL_AMBER_TIME:
		return PED_FLASHING
	return PED_STOP


func set_active_crosswalk_peds(positions: PackedVector3Array) -> void:
	## Called by CrowdManager each tick with positions of pedestrians actively crossing roadways.
	_ped_cross_grid.clear()
	for p in positions:
		var ck := _cell_key(p.x, p.z)
		var arr: Array
		if _ped_cross_grid.has(ck):
			arr = _ped_cross_grid[ck]
		else:
			arr = []
			_ped_cross_grid[ck] = arr
		arr.append(Vector2(p.x, p.z))


func get_stopped_bus_positions() -> PackedVector3Array:
	return _stopped_bus_positions


func get_traffic_period_label(hour: float = -1.0) -> String:
	var h := _cur_time_hour if hour < 0.0 else fposmod(hour, 24.0)
	if h >= 7.0 and h < 9.5:
		return "Morning Rush"
	if h >= 11.8 and h < 13.8:
		return "Lunch Peak"
	if h >= 16.5 and h < 19.2:
		return "Evening Rush"
	if h >= 19.2 and h < 22.3:
		return "Evening Flow"
	if h >= 22.3 or h < 5.5:
		return "Night Quiet"
	return "Midday Flow"


func get_traffic_stats() -> Dictionary:
	var moving := 0
	var stopped := 0
	var buses_active := 0
	for i in range(_veh_count):
		if _v_active[i] == 0:
			continue
		if _v_type[i] == VEH_BUS:
			buses_active += 1
		if _v_speed[i] > 0.6:
			moving += 1
		else:
			stopped += 1
	return {
		"total_pool": _veh_count,
		"active": _active_vehicle_count,
		"moving": moving,
		"stopped": stopped,
		"buses": buses_active,
		"boats": _boat_count,
		"lane_changes": _lane_changes_total,
		"period": get_traffic_period_label(),
	}


static func compute_diurnal_demand(hour: float) -> float:
	## Realistic 24-hour urban traffic volume curve in [0.24, 1.00].
	var h := fposmod(hour, 24.0)
	# Gaussian-like peaks for morning commute (8.1), midday/lunch (12.6), evening rush (17.6)
	var morning := exp(-pow((h - 8.1) / 1.45, 2.0)) * 0.78
	var midday := exp(-pow((h - 13.0) / 3.4, 2.0)) * 0.52
	var evening := exp(-pow((h - 17.6) / 1.75, 2.0)) * 0.80
	var late_eve := exp(-pow((h - 20.6) / 1.6, 2.0)) * 0.34
	return clampf(0.24 + maxf(maxf(morning, evening), maxf(midday, late_eve)), 0.24, 1.0)


func _update_diurnal_active_fleet() -> void:
	if _veh_count <= 0:
		_active_vehicle_count = 0
		return
	var demand := clampf(compute_diurnal_demand(_cur_time_hour) * density_scale, 0.08, 1.0)
	_active_target_count = maxi(12, int(round(float(_veh_count) * demand)))
	var active_now := 0
	for i in range(_veh_count):
		var want_on: int = 1 if _v_priority_rank[i] <= demand else 0
		if _v_active[i] == 0 and want_on == 1:
			# Re-enter smoothly without stacking on top of an already-active car
			if _is_spawn_slot_clear(i):
				_v_active[i] = 1
				_v_speed[i] = minf(_v_speed[i], 3.0)
				_v_stuck_timer[i] = 0.0
		elif _v_active[i] == 1 and want_on == 0:
			# Despawn gracefully once out of junction
			if _v_in_junction[i] == 0:
				_v_active[i] = 0
				_v_speed[i] = 0.0
		if _v_active[i] == 1:
			active_now += 1
	_active_vehicle_count = active_now


func _is_spawn_slot_clear(idx: int) -> bool:
	var p := _v_pos[idx]
	if not _veh_grid.is_empty():
		var cx := int(floor(p.x / CELL_SIZE))
		var cz := int(floor(p.z / CELL_SIZE))
		for oz in range(-1, 2):
			for ox in range(-1, 2):
				var ck := (cx + ox + 512) * 2048 + (cz + oz + 512)
				if not _veh_grid.has(ck):
					continue
				for j_var in _veh_grid[ck]:
					var j: int = j_var
					if j == idx or _v_active[j] == 0:
						continue
					if p.distance_squared_to(_v_pos[j]) < 64.0:
						return false
		return true
	for j in range(_veh_count):
		if j == idx or _v_active[j] == 0:
			continue
		var d2 := p.distance_squared_to(_v_pos[j])
		if d2 < 64.0:
			return false
	return true


func _clear_renderers() -> void:
	for ch in get_children():
		remove_child(ch)
		ch.queue_free()
	_body_mmis.clear()
	_body_mms.clear()
	_lights_mmi = null
	_lights_mm = null
	_lights_mat = null
	_signals_mmi = null
	_signals_mm = null
	_signals_mat = null
	_boat_mmi = null
	_boat_mm = null


func _reset_state() -> void:
	_sim_time = 0.0
	_turn_counter = 0
	_veh_count = 0
	_active_vehicle_count = 0
	_lane_changes_total = 0
	_type_counts = [0, 0, 0, 0, 0, 0, 0, 0]
	_v_type.clear()
	_v_active.clear()
	_v_priority_rank.clear()
	_v_lane_id.clear()
	_v_next_lane_id.clear()
	_v_turn_dir.clear()
	_v_s.clear()
	_v_in_junction.clear()
	_v_junc_p0.clear()
	_v_junc_p1.clear()
	_v_junc_p2.clear()
	_v_junc_p3.clear()
	_v_junc_len.clear()
	_v_speed.clear()
	_v_accel.clear()
	_v_max_mult.clear()
	_v_brake.clear()
	_v_blinker.clear()
	_v_pitch.clear()
	_v_roll.clear()
	_v_half_len.clear()
	_v_lat_shift.clear()
	_v_lc_offset.clear()
	_v_lc_cooldown.clear()
	_v_stuck_timer.clear()
	_v_bus_dwell.clear()
	_v_bus_last_stop.clear()
	_v_pos.clear()
	_v_dir.clear()
	_v_color.clear()
	_veh_grid.clear()
	_parked_grid.clear()
	_ped_cross_grid.clear()
	_lane_bus_stops.clear()
	_stopped_bus_positions.clear()
	_signal_offsets.clear()
	_sig_node_ids.clear()
	_sig_is_ns.clear()
	_sig_last_state.clear()
	_boat_count = 0
	_boat_s.clear()
	_boat_dir.clear()
	_boat_speed.clear()
	_boat_lat.clear()
	_boat_color.clear()
	_river_pts.clear()
	_river_cum.clear()
	_river_total_len = 0.0


func _build_signal_table() -> void:
	for n in _road_graph.nodes:
		if n.has_traffic_signal:
			# Green-wave corridor stagger along grid coordinates for smooth arterial progression
			var wave := (n.pos.x + n.pos.y) * 0.022
			_signal_offsets[n.id] = fposmod(wave + float(n.id % 5) * 1.1, SIGNAL_CYCLE)


func _get_node_axis_signal(node_id: int, is_ns: bool) -> int:
	var off := float(_signal_offsets.get(node_id, 0.0))
	var phase := fposmod(_sim_time + off, SIGNAL_CYCLE)
	if phase < SIGNAL_HALF_CYCLE:
		if not is_ns:
			return SIG_RED
		if phase < SIGNAL_GREEN_TIME:
			return SIG_GREEN
		if phase < SIGNAL_GREEN_TIME + SIGNAL_AMBER_TIME:
			return SIG_AMBER
		return SIG_RED
	else:
		if is_ns:
			return SIG_RED
		var local_t := phase - SIGNAL_HALF_CYCLE
		if local_t < SIGNAL_GREEN_TIME:
			return SIG_GREEN
		if local_t < SIGNAL_GREEN_TIME + SIGNAL_AMBER_TIME:
			return SIG_AMBER
		return SIG_RED


func _build_parked_ev_grid() -> void:
	for pr in _plan.props:
		if String(pr.get("type", "")) != "parked_ev":
			continue
		var pos3: Vector3 = pr.get("pos", Vector3.ZERO)
		var cell := _cell_key(pos3.x, pos3.z)
		var arr: Array
		if _parked_grid.has(cell):
			arr = _parked_grid[cell]
		else:
			arr = []
			_parked_grid[cell] = arr
		arr.append(Vector2(pos3.x, pos3.z))


func _build_bus_stops_table() -> void:
	## Maps every transit_shelter prop onto its closest curb/outer arterial lane s-coordinate.
	var stop_idx := 0
	for pr in _plan.props:
		if String(pr.get("type", "")) != "transit_shelter":
			continue
		var sp: Vector3 = pr.get("pos", Vector3.ZERO)
		var sp2 := Vector2(sp.x, sp.z)
		var best_lid := -1
		var best_s := 0.0
		var best_d2 := 100.0
		for lane in _road_graph.lanes:
			if lane.road_class != "arterial" and lane.road_class != "collector":
				continue
			if lane.lane_count > 1 and lane.lane_index != lane.lane_count - 1:
				continue
			if lane.total_length < 22.0 or lane.points.size() < 2:
				continue
			var p_start := lane.points[0]
			var p_end := lane.points[lane.points.size() - 1]
			var a2 := Vector2(p_start.x, p_start.z)
			var b2 := Vector2(p_end.x, p_end.z)
			var ab := b2 - a2
			var l2 := ab.length_squared()
			if l2 < 1.0:
				continue
			var t := clampf((sp2 - a2).dot(ab) / l2, 0.12, 0.84)
			var proj := a2 + ab * t
			var d2 := sp2.distance_squared_to(proj)
			if d2 < best_d2:
				best_d2 = d2
				best_lid = lane.id
				best_s = t * lane.total_length
		if best_lid != -1:
			var list: Array = _lane_bus_stops.get(best_lid, [])
			list.append({"s": best_s, "stop_idx": stop_idx, "pos": sp})
			_lane_bus_stops[best_lid] = list
			stop_idx += 1


func _spawn_vehicles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _plan.config.world_seed + 4021

	var arterial_lanes: Array[int] = []
	var outer_arterial_lanes: Array[int] = []
	var collector_lanes: Array[int] = []
	var local_lanes: Array[int] = []

	for lane in _road_graph.lanes:
		if lane.total_length < 11.0 or lane.points.size() < 2:
			continue
		if lane.road_class == "arterial":
			arterial_lanes.append(lane.id)
			if lane.lane_count == 1 or lane.lane_index == lane.lane_count - 1:
				outer_arterial_lanes.append(lane.id)
		elif lane.road_class == "collector":
			collector_lanes.append(lane.id)
		else:
			local_lanes.append(lane.id)

	var weighted_pool: Array[int] = []
	var comm_center: Vector2 = _plan.district_centers.get("commercial_corridor", _downtown_center)
	for lid in arterial_lanes:
		var l_a := _road_graph.lanes[lid]
		var l_mid := l_a.points[l_a.points.size() / 2]
		var near_core := Vector2(l_mid.x, l_mid.z).distance_to(_downtown_center) < 540.0 or Vector2(l_mid.x, l_mid.z).distance_to(comm_center) < 460.0
		var w_cnt := 11 if near_core else 4
		for _w in range(w_cnt):
			weighted_pool.append(lid)
	for lid in collector_lanes:
		var l_c := _road_graph.lanes[lid]
		var l_mid := l_c.points[l_c.points.size() / 2]
		var near_core := Vector2(l_mid.x, l_mid.z).distance_to(_downtown_center) < 500.0
		var w_cnt := 6 if near_core else 2
		for _w in range(w_cnt):
			weighted_pool.append(lid)
	for lid in local_lanes:
		weighted_pool.append(lid)

	if weighted_pool.is_empty():
		return

	var transit_pool: Array[int] = []
	transit_pool.append_array(outer_arterial_lanes)
	if transit_pool.size() < 6:
		transit_pool.append_array(arterial_lanes)
	if transit_pool.size() < 6:
		transit_pool.append_array(collector_lanes)
	if transit_pool.is_empty():
		transit_pool = weighted_pool

	var lane_spawn_s: Dictionary = {}
	var attempts := 0
	var max_attempts := TARGET_VEHICLE_COUNT * 18

	while _veh_count < TARGET_VEHICLE_COUNT and attempts < max_attempts:
		attempts += 1
		var r_type := rng.randf()
		var vtype := VEH_SEDAN
		if r_type < 0.055:
			vtype = VEH_BUS
		elif r_type < 0.085:
			vtype = VEH_EMERGENCY
		elif r_type < 0.145:
			vtype = VEH_TAXI
		elif r_type < 0.245:
			vtype = VEH_VAN
		elif r_type < 0.355:
			vtype = VEH_PICKUP
		elif r_type < 0.505:
			vtype = VEH_HATCHBACK
		elif r_type < 0.725:
			vtype = VEH_SUV

		var pool := transit_pool if vtype == VEH_BUS else weighted_pool
		var lid: int = pool[rng.randi_range(0, pool.size() - 1)]
		var lane := _road_graph.lanes[lid]
		var half_len: float = TYPE_LENGTHS[vtype] * 0.5
		var min_s := half_len + 1.8
		var max_s := lane.total_length - half_len - 4.5
		if max_s <= min_s:
			continue

		var s_val := rng.randf_range(min_s, max_s)
		var existing_s: Array = lane_spawn_s.get(lid, [])
		var clear := true
		var min_gap := half_len * 2.0 + 7.0
		for prev_s_var in existing_s:
			if absf(float(prev_s_var) - s_val) < min_gap:
				clear = false
				break
		if not clear:
			continue

		existing_s.append(s_val)
		lane_spawn_s[lid] = existing_s

		var sample := _sample_lane(lane, s_val)
		var pos: Vector3 = sample["pos"]
		var fwd: Vector3 = sample["dir"]

		var col: Color
		match vtype:
			VEH_BUS:
				var bc: Color = BUS_PALETTE[rng.randi_range(0, BUS_PALETTE.size() - 1)]
				col = Color(bc.r, bc.g, bc.b, 0.95)
			VEH_EMERGENCY:
				# Alternating police white-and-navy cruiser & municipal emergency responder
				var is_amb := (attempts % 3 == 0)
				col = Color(0.94, 0.95, 0.96, 0.74) if is_amb else Color(0.92, 0.94, 0.97, 0.74)
			VEH_TAXI:
				col = Color(0.95, 0.72, 0.08, 0.50)
			VEH_VAN:
				var vc: Color = VAN_PALETTE[rng.randi_range(0, VAN_PALETTE.size() - 1)]
				col = Color(vc.r, vc.g, vc.b, 0.15)
			VEH_PICKUP:
				var pc: Color = PICKUP_PALETTE[rng.randi_range(0, PICKUP_PALETTE.size() - 1)]
				col = Color(pc.r, pc.g, pc.b, 0.0)
			_:
				var cc: Color = CAR_PALETTE[rng.randi_range(0, CAR_PALETTE.size() - 1)]
				col = Color(cc.r, cc.g, cc.b, 0.0)

		# Priority rank determines when this vehicle joins diurnal traffic waves (buses/emergency/taxis stay on streets longer)
		var prio := rng.randf()
		if vtype == VEH_BUS or vtype == VEH_EMERGENCY:
			prio *= 0.28
		elif vtype == VEH_TAXI:
			prio *= 0.45
		elif vtype == VEH_VAN:
			prio = lerpf(0.22, 0.82, prio)

		var next_lid := _pick_next_lane(lane, vtype, _veh_count + attempts)
		var turn_d := _compute_turn_direction(lane, next_lid)

		_v_type.append(vtype)
		_v_active.append(1)
		_v_priority_rank.append(prio)
		_v_lane_id.append(lid)
		_v_next_lane_id.append(next_lid)
		_v_turn_dir.append(turn_d)
		_v_s.append(s_val)
		_v_in_junction.append(0)
		_v_junc_p0.append(Vector3.ZERO)
		_v_junc_p1.append(Vector3.ZERO)
		_v_junc_p2.append(Vector3.ZERO)
		_v_junc_p3.append(Vector3.ZERO)
		_v_junc_len.append(1.0)
		var mult := rng.randf_range(0.86, 1.09)
		if vtype == VEH_BUS:
			mult = rng.randf_range(0.76, 0.88)
		elif vtype == VEH_EMERGENCY:
			mult = rng.randf_range(1.05, 1.18)
		_v_max_mult.append(mult)
		_v_speed.append(lane.speed_limit * mult * 0.72)
		_v_accel.append(0.0)
		_v_brake.append(0.0)
		_v_blinker.append(0)
		_v_pitch.append(0.0)
		_v_roll.append(0.0)
		_v_half_len.append(half_len)
		_v_lat_shift.append(0.0)
		_v_lc_offset.append(0.0)
		_v_lc_cooldown.append(rng.randf_range(1.0, 4.5))
		_v_stuck_timer.append(0.0)
		_v_bus_dwell.append(0.0)
		_v_bus_last_stop.append(-1)
		_v_pos.append(pos)
		_v_dir.append(fwd)
		_v_color.append(col)
		_type_counts[vtype] += 1
		_veh_count += 1


func _compute_turn_direction(from_lane: RoadGraph.LaneSegment, to_lid: int) -> int:
	if to_lid < 0 or to_lid >= _road_graph.lanes.size() or from_lane.points.size() < 2:
		return 0
	var to_lane := _road_graph.lanes[to_lid]
	if to_lane.points.size() < 2:
		return 0
	var p_a := from_lane.points[from_lane.points.size() - 2]
	var p_b := from_lane.points[from_lane.points.size() - 1]
	var in2 := Vector2(p_b.x - p_a.x, p_b.z - p_a.z).normalized()
	var out2 := Vector2(to_lane.points[1].x - to_lane.points[0].x, to_lane.points[1].z - to_lane.points[0].z).normalized()
	var dot_v := in2.dot(out2)
	if dot_v > 0.62:
		return 0
	var cross_z := in2.x * out2.y - in2.y * out2.x
	return 1 if cross_z > 0.0 else -1


func _pick_next_lane(lane: RoadGraph.LaneSegment, vtype: int, salt: int) -> int:
	if lane.next_lane_ids.is_empty():
		return lane.id
	var n_cnt := lane.next_lane_ids.size()
	if n_cnt == 1:
		return lane.next_lane_ids[0]

	# Buses stay on arterial/collector corridors (preferring outer lanes for bus stops)
	if vtype == VEH_BUS:
		var preferred: Array[int] = []
		for nid in lane.next_lane_ids:
			var nl := _road_graph.lanes[nid]
			if nl.road_class == "arterial" or nl.road_class == "collector":
				preferred.append(nid)
		if not preferred.is_empty():
			return preferred[posmod(salt, preferred.size())]

	# Commuter rush-hour directional bias: morning pulls inward toward downtown, evening pulls toward residential hills
	var use_commute_goal := false
	var goal_xz := _downtown_center
	if _cur_time_hour >= 6.8 and _cur_time_hour < 9.8 and (salt % 3 != 0):
		use_commute_goal = true
		goal_xz = _downtown_center
	elif _cur_time_hour >= 16.5 and _cur_time_hour < 19.5 and (salt % 3 != 0):
		use_commute_goal = true
		goal_xz = _residential_center

	if use_commute_goal and vtype != VEH_BUS and vtype != VEH_EMERGENCY:
		var best_nid := lane.next_lane_ids[0]
		var best_score := -INF
		var node_pos := _road_graph.nodes[lane.end_node_id].pos
		var to_goal := goal_xz - node_pos
		if to_goal.length_squared() > 400.0:
			var goal_dir := to_goal.normalized()
			for idx_c in range(n_cnt):
				var nid := lane.next_lane_ids[idx_c]
				var nl := _road_graph.lanes[nid]
				if nl.points.size() < 2:
					continue
				var out_d := Vector2(nl.points[1].x - nl.points[0].x, nl.points[1].z - nl.points[0].z).normalized()
				var align := out_d.dot(goal_dir)
				var jitter := float(posmod(salt * 13 + idx_c * 7, 11)) * 0.04
				var road_bonus := 0.25 if nl.road_class == "arterial" else (0.10 if nl.road_class == "collector" else 0.0)
				var sc := align + road_bonus + jitter
				if sc > best_score:
					best_score = sc
					best_nid = nid
			return best_nid

	# Natural urban preference: favor continuing straight ~55% of the time rather than constantly zig-zagging
	var straight_id := -1
	for nid in lane.next_lane_ids:
		if _compute_turn_direction(lane, nid) == 0:
			straight_id = nid
			break
	if straight_id != -1 and posmod(salt, 10) < 5:
		return straight_id

	return lane.next_lane_ids[posmod(salt, n_cnt)]


func _rebuild_vehicle_grid() -> void:
	_veh_grid.clear()
	for i in range(_veh_count):
		if _v_active[i] == 0:
			continue
		var p := _v_pos[i]
		var ck := _cell_key(p.x, p.z)
		var bucket: Array
		if _veh_grid.has(ck):
			bucket = _veh_grid[ck]
		else:
			bucket = []
			_veh_grid[ck] = bucket
		bucket.append(i)


func _simulate_vehicles(base_dt: float) -> void:
	_stopped_bus_positions.clear()
	var weather_spd_scale := lerpf(1.0, 0.82, _cur_weather_wetness)
	var weather_headway_scale := lerpf(1.0, 1.38, _cur_weather_wetness)
	var near_r := VIS_RANGE * vis_range_scale + 36.0
	var near_r2 := near_r * near_r
	var lod_div := maxi(1, far_lod_divisor)
	var lod_slot := _sim_frame_idx % lod_div
	var cam_x := _last_cam_pos.x
	var cam_z := _last_cam_pos.z

	for i in range(_veh_count):
		if _v_active[i] == 0:
			continue

		var cur_pos := _v_pos[i]
		var cdx := cur_pos.x - cam_x
		var cdz := cur_pos.z - cam_z
		var is_far := (lod_div > 1) and (cdx * cdx + cdz * cdz > near_r2)
		if is_far and (i % lod_div) != lod_slot:
			continue
		var dt := clampf(base_dt * float(lod_div), 0.0, 0.16) if is_far else base_dt

		var vtype := _v_type[i]
		var lid := _v_lane_id[i]
		var lane := _road_graph.lanes[lid]
		var in_junc := _v_in_junction[i] == 1
		var cur_dir := _v_dir[i]
		var cur_spd := _v_speed[i]
		var half_len := _v_half_len[i]
		var turn_dir := _v_turn_dir[i]

		_v_lc_cooldown[i] = maxf(0.0, _v_lc_cooldown[i] - dt)

		var v0 := lane.speed_limit * _v_max_mult[i] * weather_spd_scale
		var a_max: float = TYPE_MAX_ACCEL[vtype]
		var b_comf: float = TYPE_COMF_DECEL[vtype]
		var t_headway: float = TYPE_HEADWAY[vtype] * weather_headway_scale
		var s0_min := 2.15 if vtype != VEH_BUS else 2.85

		# 1. Cornering speed moderation & turn-signal activation
		var blinker_state := 0
		var rem_s := lane.total_length - _v_s[i]
		if not in_junc:
			if turn_dir != 0 and rem_s < 24.0:
				blinker_state = 1 if turn_dir < 0 else 2
			if rem_s < 11.0 and turn_dir != 0:
				v0 = minf(v0, 6.2 if vtype != VEH_BUS else 5.2)
		else:
			if turn_dir != 0:
				blinker_state = 1 if turn_dir < 0 else 2
				v0 = minf(v0, 6.8 if vtype != VEH_BUS else 5.5)
			else:
				v0 = minf(v0, 9.6)

		# 2. Scheduled Transit Bus Stop Boarding at arterial transit_shelters
		var bus_dwelling := false
		var best_gap := 1e6
		var lead_speed := v0
		var stopping_for_rule := false

		if vtype == VEH_BUS and not in_junc:
			if _v_bus_dwell[i] > 0.0:
				_v_bus_dwell[i] = maxf(0.0, _v_bus_dwell[i] - dt)
				bus_dwelling = true
				blinker_state = 3 # hazard / right boarding blinkers
				best_gap = 0.2
				lead_speed = 0.0
				stopping_for_rule = true
				_stopped_bus_positions.append(cur_pos)
			elif _lane_bus_stops.has(lid):
				var stops: Array = _lane_bus_stops[lid]
				for st_var in stops:
					var st_d: Dictionary = st_var
					var st_idx := int(st_d["stop_idx"])
					if st_idx == _v_bus_last_stop[i]:
						continue
					var dist_stop := float(st_d["s"]) - _v_s[i]
					if dist_stop > -0.6 and dist_stop < 34.0:
						if dist_stop < 22.0:
							blinker_state = 2
						if dist_stop <= 1.1 and cur_spd < 1.1:
							_v_bus_last_stop[i] = st_idx
							_v_bus_dwell[i] = 4.6
							bus_dwelling = true
							blinker_state = 3
							best_gap = 0.2
							lead_speed = 0.0
							stopping_for_rule = true
							_stopped_bus_positions.append(cur_pos)
						else:
							var stop_gap := maxf(0.25, dist_stop)
							if stop_gap < best_gap:
								best_gap = stop_gap
								lead_speed = 0.0
								stopping_for_rule = true
						break

		# 3. Traffic Signal, Unprotected Left-Turn Yielding, "Don't Block the Box" & Crosswalk Pedestrians
		if not in_junc and not bus_dwelling:
			var end_node := _road_graph.nodes[lane.end_node_id]
			var stop_s := maxf(0.5, lane.total_length - 3.0 - half_len)
			var dist_to_stop := stop_s - _v_s[i]

			# 3a. Signalized intersection red/amber virtual lead vehicle
			if end_node.has_traffic_signal:
				var sig := _get_node_axis_signal(end_node.id, lane.is_ns_axis)
				var must_stop := false
				if sig == SIG_RED and dist_to_stop > -0.75:
					must_stop = true
				elif sig == SIG_AMBER and dist_to_stop > maxf(2.6, cur_spd * 0.65):
					must_stop = true
				if must_stop:
					var g_sig := maxf(0.15, dist_to_stop)
					if g_sig < best_gap:
						best_gap = g_sig
						lead_speed = 0.0
						stopping_for_rule = true
				elif sig == SIG_GREEN and turn_dir < 0 and dist_to_stop > -1.4 and dist_to_stop < 10.5 and _v_stuck_timer[i] < 4.5:
					# 3b. Unprotected left-turn gap acceptance against oncoming traffic approaching end_node
					if _has_oncoming_left_conflict(i, lane, end_node.id):
						var g_yield := maxf(0.2, dist_to_stop + 1.2)
						if g_yield < best_gap:
							best_gap = g_yield
							lead_speed = 0.0
							stopping_for_rule = true

			# 3c. "Don't block the box" exit lane clearance check before entering junction
			if dist_to_stop > -0.5 and dist_to_stop < 6.5 and _v_stuck_timer[i] < 4.8:
				var next_lid := _v_next_lane_id[i]
				if next_lid >= 0 and next_lid < _road_graph.lanes.size() and next_lid != lid:
					if _is_lane_entry_congested(next_lid, i):
						var g_box := maxf(0.2, dist_to_stop)
						if g_box < best_gap:
							best_gap = g_box
							lead_speed = 0.0
							stopping_for_rule = true

			# 3d. Yield to pedestrians actively crossing the crosswalk ahead!
			if not _ped_cross_grid.is_empty() and dist_to_stop > -2.0 and dist_to_stop < 18.0:
				var ped_gap := _query_crosswalk_pedestrian_gap(cur_pos, cur_dir, half_len)
				if ped_gap < best_gap:
					best_gap = ped_gap
					lead_speed = 0.0
					stopping_for_rule = true

		# 4. 16m Spatial-Hash Car Following + Intersection Cross-Conflict Clearance
		var cx := int(floor(cur_pos.x / CELL_SIZE))
		var cz := int(floor(cur_pos.z / CELL_SIZE))
		var veh_ahead_gap := 1e6
		var veh_ahead_spd := v0
		for oz in range(-1, 2):
			for ox in range(-1, 2):
				var ck := (cx + ox + 512) * 2048 + (cz + oz + 512)
				if not _veh_grid.has(ck):
					continue
				var bucket: Array = _veh_grid[ck]
				for j_var in bucket:
					var j: int = j_var
					if j == i:
						continue
					var pj := _v_pos[j]
					var dx := pj.x - cur_pos.x
					var dz := pj.z - cur_pos.z
					var d2 := dx * dx + dz * dz
					if d2 > 1024.0 or d2 < 0.0001:
						continue
					var fwd_d := dx * cur_dir.x + dz * cur_dir.z
					if fwd_d <= 0.0:
						continue
					var lat_d := absf(-dx * cur_dir.z + dz * cur_dir.x)
					var dj := _v_dir[j]
					var dot_d := cur_dir.x * dj.x + cur_dir.z * dj.z

					var same_stream := (lat_d < 1.85 and dot_d > 0.35)
					var junc_cross := (lat_d < 2.30 and fwd_d < 9.5 and (_v_in_junction[j] == 1 or in_junc))
					if not same_stream and not junc_cross:
						continue

					# Deadlock breaker: if both vehicles are stopped in a junction standoff, lower index proceeds
					if junc_cross and not same_stream and _v_stuck_timer[i] > 5.0 and i < j:
						continue

					var gap := fwd_d - half_len - _v_half_len[j]
					if gap < veh_ahead_gap:
						veh_ahead_gap = gap
						veh_ahead_spd = _v_speed[j]
					if gap < best_gap:
						best_gap = gap
						lead_speed = _v_speed[j]

		# 5. MOBIL-Inspired Polite Lane Changing on 4-Lane Arterials
		if not in_junc and not bus_dwelling and lane.adjacent_lane_id != -1 and _v_lc_cooldown[i] <= 0.0:
			if _v_s[i] > 12.0 and rem_s > 20.0:
				var want_lc := false
				if vtype == VEH_BUS and lane.lane_index == 0:
					want_lc = true
				elif turn_dir < 0 and lane.lane_index == 1 and rem_s < 58.0:
					want_lc = true
				elif turn_dir > 0 and lane.lane_index == 0 and rem_s < 58.0:
					want_lc = true
				elif veh_ahead_gap < 18.0 and veh_ahead_spd < v0 * 0.72 and cur_spd < v0 * 0.80 and vtype != VEH_BUS:
					want_lc = true
				if want_lc:
					var adj_lid := lane.adjacent_lane_id
					if _try_mobil_lane_change(i, lane, _road_graph.lanes[adj_lid]):
						lid = _v_lane_id[i]
						lane = _road_graph.lanes[lid]
						blinker_state = 1 if lane.lane_index == 0 else 2

		# Keep turn indicator active while smoothly sliding across lane divider
		if absf(_v_lc_offset[i]) > 0.25 and blinker_state == 0:
			blinker_state = 1 if _v_lc_offset[i] > 0.0 else 2

		# 6. Intelligent Driver Model (IDM) Longitudinal Acceleration Integration
		var free_ratio := cur_spd / maxf(0.5, v0)
		var free_term := 1.0 - (free_ratio * free_ratio * free_ratio * free_ratio)
		var inter_term := 0.0
		if best_gap < 48.0:
			var dv := cur_spd - lead_speed
			var s_star := s0_min + maxf(0.0, cur_spd * t_headway + (cur_spd * dv) / (2.0 * sqrt(a_max * b_comf)))
			var eff_gap := maxf(0.22, best_gap)
			var ratio := s_star / eff_gap
			inter_term = ratio * ratio

		var a_idm := a_max * (free_term - inter_term)
		if best_gap <= 1.25 and lead_speed < 0.35:
			a_idm = minf(a_idm, -6.5)
		a_idm = clampf(a_idm, -8.5, a_max)

		var next_spd := clampf(cur_spd + a_idm * dt, 0.0, v0 * 1.05)
		if next_spd < 0.08 and a_idm < 0.15:
			next_spd = 0.0

		# Deadlock watchdog timer (tracks unplanned standstill outside red lights / bus stops)
		if next_spd < 0.25 and not bus_dwelling:
			var waiting_red := false
			if not in_junc:
				var end_n := _road_graph.nodes[lane.end_node_id]
				if end_n.has_traffic_signal and _get_node_axis_signal(end_n.id, lane.is_ns_axis) == SIG_RED:
					waiting_red = true
			if not waiting_red:
				_v_stuck_timer[i] += dt
			else:
				_v_stuck_timer[i] = 0.0
		else:
			_v_stuck_timer[i] = maxf(0.0, _v_stuck_timer[i] - dt * 2.0)

		_v_speed[i] = next_spd
		_v_accel[i] = a_idm
		_v_blinker[i] = blinker_state

		var want_brake := 0.0
		if next_spd < 0.45 and (stopping_for_rule or best_gap < 6.0):
			want_brake = 1.0
		elif a_idm < -1.15:
			want_brake = clampf((-a_idm - 0.8) / 2.8, 0.35, 1.0)
		_v_brake[i] = lerpf(_v_brake[i], want_brake, clampf(dt * 11.0, 0.0, 1.0))

		# Smooth suspension pitch (nose dive on braking, mild squat on acceleration) & cornering roll
		var target_pitch := clampf(a_idm * 0.0085, -0.042, 0.024)
		_v_pitch[i] = lerpf(_v_pitch[i], target_pitch, clampf(dt * 7.5, 0.0, 1.0))
		var target_roll := 0.0
		if in_junc and turn_dir != 0:
			target_roll = float(turn_dir) * clampf(next_spd * 0.0075, 0.0, 0.052)
		elif absf(_v_lc_offset[i]) > 0.15:
			target_roll = clampf(-_v_lc_offset[i] * 0.015, -0.032, 0.032)
		_v_roll[i] = lerpf(_v_roll[i], target_roll, clampf(dt * 6.5, 0.0, 1.0))

		# 7. Advance Along Lane or Intersection Cubic Bezier
		var s_new := _v_s[i] + next_spd * dt
		if not in_junc:
			if s_new >= lane.total_length:
				var overflow := s_new - lane.total_length
				var next_lid := _v_next_lane_id[i]
				if next_lid < 0 or next_lid >= _road_graph.lanes.size() or next_lid == lid:
					_v_s[i] = fposmod(overflow, maxf(1.0, lane.total_length))
				else:
					_enter_junction(i, lane, _road_graph.lanes[next_lid], overflow)
			else:
				_v_s[i] = s_new
		else:
			var j_len := _v_junc_len[i]
			if s_new >= j_len:
				var overflow_l := s_new - j_len
				var next_lid := _v_next_lane_id[i]
				var next_l := _road_graph.lanes[next_lid]
				_v_in_junction[i] = 0
				_v_lane_id[i] = next_lid
				_v_s[i] = clampf(overflow_l, 0.0, maxf(0.1, next_l.total_length - 0.1))
				_v_bus_last_stop[i] = -1
				_turn_counter += 1
				var chosen_next := _pick_next_lane(next_l, vtype, i * 31 + _turn_counter)
				_v_next_lane_id[i] = chosen_next
				_v_turn_dir[i] = _compute_turn_direction(next_l, chosen_next)
			else:
				_v_s[i] = s_new

		# 8. Recompute World Position & Tangent (including smooth MOBIL lateral blend & parked EV avoidance)
		if _v_in_junction[i] == 1:
			var u := clampf(_v_s[i] / maxf(0.1, _v_junc_len[i]), 0.0, 1.0)
			var p0 := _v_junc_p0[i]
			var p1 := _v_junc_p1[i]
			var p2 := _v_junc_p2[i]
			var p3 := _v_junc_p3[i]
			_v_pos[i] = _eval_cubic_bezier(p0, p1, p2, p3, u)
			var deriv := _eval_cubic_bezier_deriv(p0, p1, p2, p3, u)
			if deriv.length_squared() > 0.0001:
				_v_dir[i] = deriv.normalized()
			_v_lat_shift[i] = lerpf(_v_lat_shift[i], 0.0, clampf(dt * 6.0, 0.0, 1.0))
			_v_lc_offset[i] = lerpf(_v_lc_offset[i], 0.0, clampf(dt * 6.0, 0.0, 1.0))
		else:
			var cur_lane := _road_graph.lanes[_v_lane_id[i]]
			var sm := _sample_lane(cur_lane, _v_s[i])
			var base_p: Vector3 = sm["pos"]
			var fwd_d: Vector3 = sm["dir"]
			_v_dir[i] = fwd_d
			var want_lat := _compute_parked_avoid_shift(base_p, fwd_d)
			var lat := lerpf(_v_lat_shift[i], want_lat, clampf(dt * 6.0, 0.0, 1.0))
			_v_lat_shift[i] = lat
			# Decay MOBIL lane-change lateral offset smoothly to 0
			var lc_off := _v_lc_offset[i]
			if absf(lc_off) > 0.005:
				var slide_rate := maxf(1.1, next_spd * 0.19) * dt
				if absf(lc_off) <= slide_rate:
					lc_off = 0.0
				else:
					lc_off -= signf(lc_off) * slide_rate
				_v_lc_offset[i] = lc_off
			# Left vector in XZ (toward road center for right-hand traffic)
			var left_xz := Vector2(fwd_d.z, -fwd_d.x)
			var l2 := left_xz.length()
			if l2 > 0.001:
				left_xz /= l2
			var total_lat := lat + lc_off
			_v_pos[i] = Vector3(base_p.x + left_xz.x * total_lat, base_p.y, base_p.z + left_xz.y * total_lat)


func _has_oncoming_left_conflict(self_idx: int, cur_lane: RoadGraph.LaneSegment, node_id: int) -> bool:
	var node_pos := _road_graph.nodes[node_id].pos
	var cur_p := _v_pos[self_idx]
	var cur_d := _v_dir[self_idx]
	var cx := int(floor(node_pos.x / CELL_SIZE))
	var cz := int(floor(node_pos.y / CELL_SIZE))
	for oz in range(-2, 3):
		for ox in range(-2, 3):
			var ck := (cx + ox + 512) * 2048 + (cz + oz + 512)
			if not _veh_grid.has(ck):
				continue
			for j_var in _veh_grid[ck]:
				var j: int = j_var
				if j == self_idx or _v_in_junction[j] == 1:
					continue
				var ol := _road_graph.lanes[_v_lane_id[j]]
				if ol.end_node_id != node_id or ol.edge_id == cur_lane.edge_id:
					continue
				var dj := _v_dir[j]
				var dot_opp := cur_d.x * dj.x + cur_d.z * dj.z
				if dot_opp > -0.55:
					continue
				var rem_opp := ol.total_length - _v_s[j]
				if rem_opp < 0.0 or rem_opp > 32.0:
					continue
				var spd_opp := maxf(2.5, _v_speed[j])
				var tta := rem_opp / spd_opp
				if tta < 2.6 and cur_p.distance_squared_to(_v_pos[j]) < 1600.0:
					return true
	return false


func _is_lane_entry_congested(next_lid: int, self_idx: int) -> bool:
	var nl := _road_graph.lanes[next_lid]
	if nl.points.is_empty():
		return false
	var p0 := nl.points[0]
	var cx := int(floor(p0.x / CELL_SIZE))
	var cz := int(floor(p0.z / CELL_SIZE))
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var ck := (cx + ox + 512) * 2048 + (cz + oz + 512)
			if not _veh_grid.has(ck):
				continue
			for j_var in _veh_grid[ck]:
				var j: int = j_var
				if j == self_idx or _v_in_junction[j] == 1:
					continue
				if _v_lane_id[j] == next_lid and _v_s[j] < 10.5 and _v_speed[j] < 1.8:
					return true
	return false


func _query_crosswalk_pedestrian_gap(cur_pos: Vector3, cur_dir: Vector3, half_len: float) -> float:
	var best_g := 1e6
	var cx := int(floor(cur_pos.x / CELL_SIZE))
	var cz := int(floor(cur_pos.z / CELL_SIZE))
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var ck := (cx + ox + 512) * 2048 + (cz + oz + 512)
			if not _ped_cross_grid.has(ck):
				continue
			for p2_var in _ped_cross_grid[ck]:
				var p2: Vector2 = p2_var
				var dx := p2.x - cur_pos.x
				var dz := p2.y - cur_pos.z
				var fwd_d := dx * cur_dir.x + dz * cur_dir.z
				if fwd_d < half_len * 0.5 or fwd_d > 19.0:
					continue
				var lat_d := absf(-dx * cur_dir.z + dz * cur_dir.x)
				if lat_d < 2.25:
					var g := maxf(0.25, fwd_d - half_len - 1.65)
					if g < best_g:
						best_g = g
	return best_g


func _try_mobil_lane_change(idx: int, from_lane: RoadGraph.LaneSegment, to_lane: RoadGraph.LaneSegment) -> bool:
	var frac := clampf(_v_s[idx] / maxf(1.0, from_lane.total_length), 0.05, 0.95)
	var target_s := frac * to_lane.total_length
	var sm := _sample_lane(to_lane, target_s)
	var target_p: Vector3 = sm["pos"]
	var fwd: Vector3 = sm["dir"]

	# Safety & politeness check against vehicles in target lane
	var cx := int(floor(target_p.x / CELL_SIZE))
	var cz := int(floor(target_p.z / CELL_SIZE))
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var ck := (cx + ox + 512) * 2048 + (cz + oz + 512)
			if not _veh_grid.has(ck):
				continue
			for j_var in _veh_grid[ck]:
				var j: int = j_var
				if j == idx:
					continue
				if _v_lane_id[j] != to_lane.id and _v_pos[j].distance_squared_to(target_p) > 25.0:
					continue
				var rel := _v_pos[j] - target_p
				var fwd_d := rel.x * fwd.x + rel.z * fwd.z
				var lat_d := absf(-rel.x * fwd.z + rel.z * fwd.x)
				if lat_d > 2.0:
					continue
				var min_front := _v_half_len[idx] + _v_half_len[j] + 5.2
				var min_back := _v_half_len[idx] + _v_half_len[j] + 6.5 + maxf(0.0, (_v_speed[j] - _v_speed[idx]) * 1.4)
				if fwd_d >= -min_back and fwd_d <= min_front:
					return false

	# Compute exact signed lateral offset from target_p back to current position so transition is seamless
	var delta_p := _v_pos[idx] - target_p
	var left_xz := Vector2(fwd.z, -fwd.x).normalized()
	var signed_lat := delta_p.x * left_xz.x + delta_p.z * left_xz.y

	_v_lane_id[idx] = to_lane.id
	_v_s[idx] = target_s
	_v_lc_offset[idx] = clampf(signed_lat, -3.4, 3.4)
	_v_lc_cooldown[idx] = 4.2
	# Keep next_lane_id valid from new lane
	if not to_lane.next_lane_ids.has(_v_next_lane_id[idx]):
		var new_next := _pick_next_lane(to_lane, _v_type[idx], idx * 17 + _turn_counter)
		_v_next_lane_id[idx] = new_next
		_v_turn_dir[idx] = _compute_turn_direction(to_lane, new_next)
	_lane_changes_total += 1
	return true


func _compute_parked_avoid_shift(pos: Vector3, fwd: Vector3) -> float:
	if _parked_grid.is_empty():
		return 0.0
	var cx := int(floor(pos.x / CELL_SIZE))
	var cz := int(floor(pos.z / CELL_SIZE))
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var ck := (cx + ox + 512) * 2048 + (cz + oz + 512)
			if not _parked_grid.has(ck):
				continue
			for p2_var in _parked_grid[ck]:
				var p2: Vector2 = p2_var
				var dx := p2.x - pos.x
				var dz := p2.y - pos.z
				if dx * dx + dz * dz < 22.0:
					var lat := -dx * fwd.z + dz * fwd.x
					if absf(lat) < 2.2:
						return 0.36
	return 0.0


func _enter_junction(idx: int, from_lane: RoadGraph.LaneSegment, to_lane: RoadGraph.LaneSegment, overflow: float) -> void:
	var n_from := from_lane.points.size()
	var p0 := from_lane.points[n_from - 1]
	var t0 := (p0 - from_lane.points[n_from - 2]).normalized()
	var p3 := to_lane.points[0]
	var t3 := (to_lane.points[1] - p3).normalized()

	var p1: Vector3
	var p2: Vector3
	if from_lane.edge_id == to_lane.edge_id:
		p1 = p0 + t0 * 3.8
		p2 = p3 - t3 * 3.8
	else:
		var chord := p0.distance_to(p3)
		var handle := clampf(chord * 0.44, 1.8, 12.5)
		p1 = p0 + t0 * handle
		p2 = p3 - t3 * handle

	p1.y = lerpf(p0.y, p3.y, 0.33)
	p2.y = lerpf(p0.y, p3.y, 0.67)

	var arc_len := 0.0
	var prev := p0
	for k in range(1, 7):
		var pt := _eval_cubic_bezier(p0, p1, p2, p3, float(k) / 6.0)
		arc_len += prev.distance_to(pt)
		prev = pt
	arc_len = maxf(1.0, arc_len)

	_v_in_junction[idx] = 1
	_v_junc_p0[idx] = p0
	_v_junc_p1[idx] = p1
	_v_junc_p2[idx] = p2
	_v_junc_p3[idx] = p3
	_v_junc_len[idx] = arc_len
	_v_s[idx] = clampf(overflow, 0.0, arc_len * 0.95)


func _sample_lane(lane: RoadGraph.LaneSegment, s: float) -> Dictionary:
	var pts := lane.points
	var cum := lane.cum_lengths
	var cnt := pts.size()
	if cnt < 2 or cum.size() != cnt:
		return {"pos": pts[0] if cnt > 0 else Vector3.ZERO, "dir": Vector3.FORWARD}

	var cs := clampf(s, 0.0, lane.total_length)
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
	var seg_len := maxf(0.0001, s1 - s0)
	var frac := clampf((cs - s0) / seg_len, 0.0, 1.0)
	var p := pts[lo].lerp(pts[lo + 1], frac)
	var d := pts[lo + 1] - pts[lo]
	if d.length_squared() < 0.00001:
		d = Vector3.FORWARD
	else:
		d = d.normalized()
	return {"pos": p, "dir": d}


func _build_renderers() -> void:
	var paint_shader := load(CAR_PAINT_SHADER_PATH) as Shader
	var body_mat := ShaderMaterial.new()
	body_mat.shader = paint_shader
	body_mat.set_shader_parameter("use_instance_custom", true)

	var ws := _plan.config.world_size
	var city_aabb := AABB(Vector3(-24.0, -24.0, -24.0), Vector3(ws + 48.0, 160.0, ws + 48.0))
	var type_names := [
		"TrafficSedans",
		"TrafficSUVs",
		"TrafficHatchbacks",
		"TrafficPickups",
		"TrafficVans",
		"TrafficBuses",
		"TrafficTaxis",
		"TrafficEmergency",
	]

	for t in range(VEH_TYPE_COUNT):
		var cap := maxi(1, _type_counts[t])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _cached_body_meshes[t]
		mm.instance_count = cap
		mm.visible_instance_count = 0

		var mmi := MultiMeshInstance3D.new()
		mmi.name = type_names[t]
		mmi.multimesh = mm
		mmi.material_override = body_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Per-instance VIS_RANGE culling against cam_pos happens in _upload_vehicle_multimeshes();
		# omitting visibility_range_end prevents Godot from culling the whole fleet by city-center distance.
		mmi.custom_aabb = city_aabb
		mmi.visible = false
		add_child(mmi)

		_body_mms.append(mm)
		_body_mmis.append(mmi)

	# Emissive headlight / taillight / brake / blinker / emergency strobe MultiMesh
	_lights_mat = ShaderMaterial.new()
	_lights_mat.shader = _cached_light_shader

	_lights_mm = MultiMesh.new()
	_lights_mm.transform_format = MultiMesh.TRANSFORM_3D
	_lights_mm.use_custom_data = true
	_lights_mm.mesh = _cached_light_mesh
	_lights_mm.instance_count = maxi(1, _veh_count)
	_lights_mm.visible_instance_count = 0

	_lights_mmi = MultiMeshInstance3D.new()
	_lights_mmi.name = "TrafficVehicleLights"
	_lights_mmi.multimesh = _lights_mm
	_lights_mmi.material_override = _lights_mat
	_lights_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lights_mmi.custom_aabb = city_aabb
	_lights_mmi.visible = false
	add_child(_lights_mmi)

	if _boat_count > 0 and _cached_boat_mesh != null:
		_boat_mm = MultiMesh.new()
		_boat_mm.transform_format = MultiMesh.TRANSFORM_3D
		_boat_mm.use_custom_data = true
		_boat_mm.mesh = _cached_boat_mesh
		_boat_mm.instance_count = _boat_count
		_boat_mm.visible_instance_count = 0

		_boat_mmi = MultiMeshInstance3D.new()
		_boat_mmi.name = "TrafficRiverBoats"
		_boat_mmi.multimesh = _boat_mm
		_boat_mmi.material_override = body_mat
		_boat_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_boat_mmi.custom_aabb = city_aabb
		_boat_mmi.visible = false
		add_child(_boat_mmi)


func _upload_vehicle_multimeshes(cam_pos: Vector3) -> void:
	var eff_vis := VIS_RANGE * vis_range_scale
	var vis_r2 := eff_vis * eff_vis
	var slots := [0, 0, 0, 0, 0, 0, 0, 0]
	var light_slot := 0

	for i in range(_veh_count):
		if _v_active[i] == 0:
			continue
		var pos := _v_pos[i]
		var dx := pos.x - cam_pos.x
		var dz := pos.z - cam_pos.z
		if dx * dx + dz * dz > vis_r2:
			continue

		var f := _v_dir[i].normalized()
		var r := Vector3.UP.cross(f)
		if r.length_squared() < 0.0001:
			r = Vector3.RIGHT
		else:
			r = r.normalized()
		var u := f.cross(r).normalized()
		var basis := Basis(r, u, f)
		# Apply subtle suspension pitch (braking dive) & cornering body roll
		var pitch := _v_pitch[i]
		var roll := _v_roll[i]
		if absf(pitch) > 0.001 or absf(roll) > 0.001:
			basis = basis * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.FORWARD, roll)

		var t := _v_type[i]
		var slot: int = slots[t]
		if slot < _body_mms[t].instance_count:
			_body_mms[t].set_instance_transform(slot, Transform3D(basis, pos))
			_body_mms[t].set_instance_custom_data(slot, _v_color[i])
			slots[t] = slot + 1

		if light_slot < _lights_mm.instance_count:
			var vw: float = TYPE_WIDTHS[t]
			var vl: float = TYPE_LENGTHS[t]
			var ly: float = TYPE_LIGHT_YS[t]
			var l_basis := Basis(basis.x * vw, basis.y, basis.z * vl)
			_lights_mm.set_instance_transform(light_slot, Transform3D(l_basis, pos + basis.y * ly))
			var sig_code := float(_v_blinker[i]) / 3.0 # 0.0=off, 0.33=left, 0.67=right, 1.0=hazard
			var roof_mode := 1.0 if t == VEH_EMERGENCY else (0.45 if t == VEH_TAXI else 0.0)
			_lights_mm.set_instance_custom_data(light_slot, Color(sig_code, roof_mode, float(i % 7) * 0.14, _v_brake[i]))
			light_slot += 1

	for t in range(VEH_TYPE_COUNT):
		var cnt: int = slots[t]
		_body_mms[t].visible_instance_count = cnt
		_body_mmis[t].visible = (cnt > 0)

	_lights_mm.visible_instance_count = light_slot
	_lights_mmi.visible = (light_slot > 0)


func _spawn_river_boats() -> void:
	var terrain := _plan.terrain
	if terrain == null or terrain.creek_polyline.size() < 4:
		return
	var ws := _plan.config.world_size
	var w_lvl := terrain.water_level
	for p2 in terrain.creek_polyline:
		if p2.y < 14.0 or p2.y > ws - 14.0:
			continue
		_river_pts.append(Vector3(p2.x, w_lvl, p2.y))
	if _river_pts.size() < 2:
		_river_pts.clear()
		return

	_river_cum.resize(_river_pts.size())
	_river_cum[0] = 0.0
	for i in range(1, _river_pts.size()):
		_river_cum[i] = _river_cum[i - 1] + _river_pts[i - 1].distance_to(_river_pts[i])
	_river_total_len = _river_cum[_river_pts.size() - 1]
	if _river_total_len < 60.0:
		_river_pts.clear()
		_river_cum.clear()
		_river_total_len = 0.0
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = _plan.config.world_seed + 8117
	var half_chan := maxf(2.5, terrain.creek_half_width * 0.36)
	_boat_count = TARGET_BOAT_COUNT
	_boat_s.resize(_boat_count)
	_boat_dir.resize(_boat_count)
	_boat_speed.resize(_boat_count)
	_boat_lat.resize(_boat_count)
	_boat_color.resize(_boat_count)
	for i in range(_boat_count):
		var dir_sign := 1 if (i % 2 == 0) else -1
		_boat_dir[i] = dir_sign
		_boat_s[i] = fposmod((float(i) + rng.randf_range(0.15, 0.85)) * (_river_total_len / float(_boat_count)), _river_total_len)
		_boat_speed[i] = rng.randf_range(4.8, 6.6)
		_boat_lat[i] = -float(dir_sign) * half_chan + rng.randf_range(-1.4, 1.4)
		_boat_color[i] = BOAT_PALETTE[rng.randi() % BOAT_PALETTE.size()]


func _simulate_river_boats(dt: float) -> void:
	if _river_total_len <= 1.0:
		return
	for i in range(_boat_count):
		_boat_s[i] = fposmod(_boat_s[i] + float(_boat_dir[i]) * _boat_speed[i] * dt, _river_total_len)


func _sample_river_pose(s: float) -> Dictionary:
	var n := _river_pts.size()
	var cs := clampf(s, 0.0, _river_total_len)
	var lo := 0
	var hi := n - 2
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if _river_cum[mid] <= cs:
			lo = mid
		else:
			hi = mid - 1
	var s0 := _river_cum[lo]
	var s1 := _river_cum[lo + 1]
	var frac := clampf((cs - s0) / maxf(0.0001, s1 - s0), 0.0, 1.0)
	var pos := _river_pts[lo].lerp(_river_pts[lo + 1], frac)
	var d := _river_pts[lo + 1] - _river_pts[lo]
	if d.length_squared() < 0.0001:
		d = Vector3(0.0, 0.0, 1.0)
	else:
		d = d.normalized()
	return {"pos": pos, "dir": d}


func _upload_river_boats(cam_pos: Vector3) -> void:
	if _boat_mm == null or _boat_mmi == null or _boat_count <= 0:
		return
	var eff_br := BOAT_VIS_RANGE * vis_range_scale
	var r2 := eff_br * eff_br
	var slot := 0
	for i in range(_boat_count):
		var pose := _sample_river_pose(_boat_s[i])
		var center: Vector3 = pose["pos"]
		var tang: Vector3 = pose["dir"]
		var right := Vector3.UP.cross(tang).normalized()
		var wpos := center + right * _boat_lat[i]
		var dx := wpos.x - cam_pos.x
		var dz := wpos.z - cam_pos.z
		if dx * dx + dz * dz > r2:
			continue
		var fwd := tang * float(_boat_dir[i])
		var br := Vector3.UP.cross(fwd).normalized()
		var bob := sin(_sim_time * 2.1 + float(i) * 1.37) * 0.045
		var xf := Transform3D(Basis(br, Vector3.UP, fwd), Vector3(wpos.x, wpos.y + bob, wpos.z))
		_boat_mm.set_instance_transform(slot, xf)
		_boat_mm.set_instance_custom_data(slot, _boat_color[i])
		slot += 1
	_boat_mm.visible_instance_count = slot
	_boat_mmi.visible = (slot > 0)


func _build_signal_lenses() -> void:
	var signal_nodes: Array[RoadGraph.RoadNode] = []
	for n in _road_graph.nodes:
		if n.has_traffic_signal:
			signal_nodes.append(n)
	if signal_nodes.is_empty():
		return

	var sig_xforms: Array[Transform3D] = []
	var node_ids: Array[int] = []
	var is_ns_list: Array[int] = []

	for pr in _plan.props:
		if String(pr.get("type", "")) != "traffic_signal":
			continue
		var p_pos: Vector3 = pr.get("pos", Vector3.ZERO)
		var p_yaw: float = float(pr.get("yaw", 0.0))
		var p_basis := Basis(Vector3.UP, p_yaw)
		var head_xf := Transform3D(p_basis, p_pos) * Transform3D(Basis.IDENTITY, Vector3(2.4, 5.19, 0.0))

		var best_nid := -1
		var best_d2 := INF
		var p2 := Vector2(p_pos.x, p_pos.z)
		for sn in signal_nodes:
			var d2 := p2.distance_squared_to(sn.pos)
			if d2 < best_d2:
				best_d2 = d2
				best_nid = sn.id
		if best_nid == -1:
			continue

		var is_ns := 1 if absf(p_basis.z.z) >= absf(p_basis.z.x) else 0
		sig_xforms.append(head_xf)
		node_ids.append(best_nid)
		is_ns_list.append(is_ns)

	if sig_xforms.is_empty():
		return

	_signals_mat = ShaderMaterial.new()
	_signals_mat.shader = _cached_signal_shader

	var cnt := sig_xforms.size()
	_signals_mm = MultiMesh.new()
	_signals_mm.transform_format = MultiMesh.TRANSFORM_3D
	_signals_mm.use_custom_data = true
	_signals_mm.mesh = _cached_signal_mesh
	_signals_mm.instance_count = cnt
	_signals_mm.visible_instance_count = cnt

	_sig_node_ids.resize(cnt)
	_sig_is_ns.resize(cnt)
	_sig_last_state.resize(cnt)
	_sig_last_state.fill(-1)

	for i in range(cnt):
		_signals_mm.set_instance_transform(i, sig_xforms[i])
		_sig_node_ids[i] = node_ids[i]
		_sig_is_ns[i] = is_ns_list[i]

	var ws := _plan.config.world_size
	_signals_mmi = MultiMeshInstance3D.new()
	_signals_mmi.name = "TrafficSignalLenses"
	_signals_mmi.multimesh = _signals_mm
	_signals_mmi.material_override = _signals_mat
	_signals_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_signals_mmi.custom_aabb = AABB(Vector3(-24.0, -24.0, -24.0), Vector3(ws + 48.0, 160.0, ws + 48.0))
	add_child(_signals_mmi)


func _update_signal_lenses() -> void:
	if _signals_mm == null:
		return
	for i in range(_sig_node_ids.size()):
		var sig := _get_node_axis_signal(_sig_node_ids[i], _sig_is_ns[i] == 1)
		if sig != _sig_last_state[i]:
			_sig_last_state[i] = sig
			var phase_val := 0.0 if sig == SIG_GREEN else (0.5 if sig == SIG_AMBER else 1.0)
			_signals_mm.set_instance_custom_data(i, Color(phase_val, 0.0, 0.0, 1.0))


static func _cell_key(x: float, z: float) -> int:
	return (int(floor(x / CELL_SIZE)) + 512) * 2048 + (int(floor(z / CELL_SIZE)) + 512)


static func _eval_cubic_bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var om := 1.0 - u
	var om2 := om * om
	var u2 := u * u
	return p0 * (om2 * om) + p1 * (3.0 * om2 * u) + p2 * (3.0 * om * u2) + p3 * (u2 * u)


static func _eval_cubic_bezier_deriv(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var om := 1.0 - u
	return (p1 - p0) * (3.0 * om * om) + (p2 - p1) * (6.0 * om * u) + (p3 - p2) * (3.0 * u * u)


static func _ensure_shared_assets() -> void:
	if _cached_body_meshes.is_empty():
		_cached_body_meshes = [
			_build_sedan_mesh(false, false),
			_build_suv_mesh(),
			_build_hatchback_mesh(),
			_build_pickup_mesh(),
			_build_van_mesh(),
			_build_bus_mesh(),
			_build_sedan_mesh(true, false),
			_build_sedan_mesh(false, true),
		]
	if _cached_boat_mesh == null:
		_cached_boat_mesh = _build_boat_mesh()
	if _cached_light_mesh == null:
		_cached_light_mesh = _build_light_cluster_mesh()
	if _cached_signal_mesh == null:
		_cached_signal_mesh = _build_signal_lens_mesh()
	if _cached_light_shader == null:
		_cached_light_shader = Shader.new()
		_cached_light_shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

global uniform float night_factor;
global uniform float weather_rain;
uniform float night_level = 0.0;

varying vec4 v_custom;
varying vec4 v_color;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_color = COLOR;
	// Collapse roof topper/lightbar quads to zero on standard vehicles
	bool is_roof_elem = (COLOR.b > 0.70 && COLOR.r > 0.25 && COLOR.g < 0.35);
	if (is_roof_elem && INSTANCE_CUSTOM.g < 0.20) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	float nf = max(night_factor, night_level);
	float rain_on = max(nf, weather_rain * 0.72);
	float sig_code = v_custom.r;
	float roof_mode = v_custom.g;
	float phase_seed = v_custom.b;
	float brake = clamp(v_custom.a, 0.0, 1.0);
	float blink = step(0.5, fract(TIME * 1.9 + phase_seed));

	bool is_head = (v_color.r > 0.75 && v_color.g < 0.25 && v_color.b < 0.25);
	bool is_tail = (v_color.g > 0.75 && v_color.r < 0.25 && v_color.b < 0.25);
	bool is_chmsl = (v_color.b > 0.75 && v_color.r < 0.25 && v_color.g < 0.25);
	bool is_lblink = (v_color.r > 0.75 && v_color.g > 0.75 && v_color.b < 0.25);
	bool is_rblink = (v_color.g > 0.75 && v_color.b > 0.75 && v_color.r < 0.25);
	bool is_roof_l = (v_color.r > 0.75 && v_color.b > 0.75 && v_color.g < 0.25);
	bool is_roof_r = (v_color.r > 0.35 && v_color.r < 0.65 && v_color.b > 0.75 && v_color.g < 0.25);

	if (is_head) {
		ALBEDO = vec3(0.96, 0.98, 1.0);
		EMISSION = vec3(0.95, 0.97, 1.0) * mix(0.45, 5.6, rain_on);
	} else if (is_tail) {
		ALBEDO = vec3(0.86, 0.08, 0.06);
		EMISSION = vec3(1.0, 0.10, 0.06) * (mix(0.28, 2.4, rain_on) + brake * mix(3.6, 5.2, nf));
	} else if (is_chmsl) {
		ALBEDO = vec3(0.42, 0.04, 0.04);
		EMISSION = vec3(1.0, 0.08, 0.05) * brake * 4.8;
	} else if (is_lblink) {
		float active_l = ((sig_code > 0.20 && sig_code < 0.50) || sig_code > 0.85) ? blink : 0.0;
		ALBEDO = mix(vec3(0.35, 0.20, 0.04), vec3(1.0, 0.65, 0.06), active_l);
		EMISSION = vec3(1.0, 0.58, 0.04) * active_l * mix(3.8, 5.4, nf);
	} else if (is_rblink) {
		float active_r = (sig_code > 0.52) ? blink : 0.0;
		ALBEDO = mix(vec3(0.35, 0.20, 0.04), vec3(1.0, 0.65, 0.06), active_r);
		EMISSION = vec3(1.0, 0.58, 0.04) * active_r * mix(3.8, 5.4, nf);
	} else if (is_roof_l || is_roof_r) {
		if (roof_mode > 0.75) {
			float strobe = step(0.5, fract(TIME * 4.6 + phase_seed));
			float on_l = is_roof_l ? strobe : (1.0 - strobe);
			vec3 scol = is_roof_l ? vec3(1.0, 0.10, 0.08) : vec3(0.10, 0.42, 1.0);
			ALBEDO = mix(vec3(0.14, 0.14, 0.18), scol, on_l);
			EMISSION = scol * on_l * mix(3.4, 6.2, nf);
		} else {
			// Illuminated Taxi roof sign
			ALBEDO = vec3(1.0, 0.82, 0.18);
			EMISSION = vec3(1.0, 0.76, 0.12) * mix(1.0, 3.8, nf);
		}
	} else {
		ALBEDO = vec3(0.15);
		EMISSION = vec3(0.0);
	}
	ROUGHNESS = 0.18;
	METALLIC = 0.0;
}
"""
	if _cached_signal_shader == null:
		_cached_signal_shader = Shader.new()
		_cached_signal_shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

global uniform float night_factor;
uniform float night_level = 0.0;

varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	float nf = max(night_factor, night_level);
	float phase = v_custom.r;
	vec2 d_r = vec2((UV.x - 0.5) * 0.28, (UV.y - 0.167) * 0.78);
	vec2 d_a = vec2((UV.x - 0.5) * 0.28, (UV.y - 0.500) * 0.78);
	vec2 d_g = vec2((UV.x - 0.5) * 0.28, (UV.y - 0.833) * 0.78);

	float m_r = 1.0 - smoothstep(0.082, 0.102, length(d_r));
	float m_a = 1.0 - smoothstep(0.082, 0.102, length(d_a));
	float m_g = 1.0 - smoothstep(0.082, 0.102, length(d_g));

	float on_g = 1.0 - step(0.25, phase);
	float on_r = step(0.75, phase);
	float on_a = (1.0 - on_g) * (1.0 - on_r);

	float glow_e = mix(3.0, 5.2, nf);
	vec3 col = vec3(0.03, 0.035, 0.04);
	vec3 em = vec3(0.0);

	col = mix(col, mix(vec3(0.14, 0.03, 0.03), vec3(1.0, 0.16, 0.12), on_r), m_r);
	em += vec3(1.0, 0.15, 0.10) * m_r * on_r * glow_e;

	col = mix(col, mix(vec3(0.14, 0.09, 0.02), vec3(1.0, 0.68, 0.10), on_a), m_a);
	em += vec3(1.0, 0.66, 0.08) * m_a * on_a * glow_e;

	col = mix(col, mix(vec3(0.02, 0.12, 0.05), vec3(0.14, 1.0, 0.40), on_g), m_g);
	em += vec3(0.14, 1.0, 0.38) * m_g * on_g * glow_e;

	ALBEDO = col;
	EMISSION = em;
	ROUGHNESS = 0.35;
	METALLIC = 0.05;
}
"""


static func _emit_cabin_greenhouse(
	st: SurfaceTool,
	center: Vector3,
	bot_size: Vector3,
	top_xz: Vector2,
	paint: Color,
	glass: Color,
	trim: Color,
	split_side_windows: bool = true,
	has_quarter_glass: bool = false
) -> void:
	## Builds a finished automotive cabin greenhouse with distinct A/B/C pillars,
	## proud front windshield & rear backlight glass, split front/rear door windows,
	## black window beltline trim, windshield wipers, and a roof shark-fin antenna.
	# 1. Main painted roof & A/C pillar shell
	_emit_tapered_box(st, center, bot_size, top_xz, paint)

	# 2. Dark lower window beltline weatherstrip molding around cabin base
	_emit_box(st, center + Vector3(0.0, -bot_size.y * 0.46, 0.0), Vector3(bot_size.x + 0.025, 0.045, bot_size.z + 0.015), trim)

	# 3. Proud raked Front Windshield (+Z) & Rear Backlight Window (-Z) framed by A/C pillars
	var ws_h := bot_size.y - 0.08
	var ws_bot := Vector3(maxf(0.4, bot_size.x - 0.22), ws_h, bot_size.z + 0.056)
	var ws_top := Vector2(maxf(0.35, top_xz.x - 0.18), top_xz.y + 0.056)
	_emit_tapered_box(st, center + Vector3(0.0, -0.008, 0.0), ws_bot, ws_top, glass)

	# Windshield wipers at base of front glass
	var wiper_y := center.y - bot_size.y * 0.40
	var wiper_z := center.z + bot_size.z * 0.5 + 0.036
	for wx_off: float in [-bot_size.x * 0.18, bot_size.x * 0.12]:
		_emit_box(st, Vector3(wx_off, wiper_y, wiper_z), Vector3(bot_size.x * 0.28, 0.024, 0.024), trim)

	# 4. Recessed/Framed Side Door Windows (+X / -X) separated by structural B-pillars
	var side_w0 := bot_size.x + 0.044
	var side_w1 := top_xz.x + 0.044
	var side_h := bot_size.y - 0.09
	if split_side_windows:
		# Center dark gloss B-pillar trim strip
		_emit_tapered_box(
			st,
			center + Vector3(0.0, -0.008, 0.02),
			Vector3(side_w0 + 0.014, side_h + 0.02, 0.12),
			Vector2(side_w1 + 0.014, 0.10),
			trim
		)
		# Front door window bay (+Z half of cabin)
		var f_z_bot := bot_size.z * 0.37
		var f_z_top := top_xz.y * 0.36
		var f_zc := center.z + bot_size.z * 0.20
		_emit_tapered_box(
			st,
			Vector3(center.x, center.y - 0.01, f_zc),
			Vector3(side_w0, side_h, f_z_bot),
			Vector2(side_w1, f_z_top),
			glass
		)
		# Rear door window bay (-Z half of cabin)
		var r_z_bot := bot_size.z * (0.26 if has_quarter_glass else 0.36)
		var r_z_top := top_xz.y * (0.25 if has_quarter_glass else 0.35)
		var r_zc := center.z - bot_size.z * (0.14 if has_quarter_glass else 0.20)
		_emit_tapered_box(
			st,
			Vector3(center.x, center.y - 0.01, r_zc),
			Vector3(side_w0, side_h, r_z_bot),
			Vector2(side_w1, r_z_top),
			glass
		)
		if has_quarter_glass:
			# SUV / wagon rear C-pillar & cargo quarter window
			var q_zc := center.z - bot_size.z * 0.36
			_emit_tapered_box(
				st,
				Vector3(center.x, center.y - 0.01, q_zc),
				Vector3(side_w0, side_h * 0.92, bot_size.z * 0.16),
				Vector2(side_w1, top_xz.y * 0.15),
				glass
			)
	else:
		# Single-bay cab side window (e.g. delivery van cab)
		_emit_tapered_box(
			st,
			center + Vector3(0.0, -0.01, 0.0),
			Vector3(side_w0, side_h, bot_size.z * 0.72),
			Vector2(side_w1, top_xz.y * 0.68),
			glass
		)


static func _emit_wheel_arches_and_doors(
	st: SurfaceTool,
	wheel_x: float,
	front_z: float,
	rear_z: float,
	wheel_r: float,
	door_y: float,
	paint: Color,
	trim: Color,
	alloy: Color,
	four_doors: bool = true
) -> void:
	## Emits 3D flared wheel-arch brows cleanly ABOVE and AROUND the tires (never clipping the wheel disc!),
	## inboard dark wheel-well housings, side rocker skirts, and pull door handles.
	var arch_l := wheel_r * 2.24
	var top_brow_y := wheel_r * 2.10
	for sx: float in [-1.0, 1.0]:
		var x_inboard := sx * (wheel_x - 0.13)
		var x_flare := sx * (wheel_x + 0.05)
		for wz: float in [front_z, rear_z]:
			# Inboard dark wheel-well backing strictly inside the tire plane
			_emit_box(st, Vector3(x_inboard, wheel_r * 1.02, wz), Vector3(0.12, wheel_r * 1.75, arch_l), trim)
			# Upper painted 3D fender flare brow + dark arch lip above the tire crown
			_emit_tapered_box(
				st,
				Vector3(x_flare, top_brow_y + 0.04, wz),
				Vector3(0.14, 0.11, arch_l + 0.10),
				Vector2(0.10, arch_l * 0.78),
				paint
			)
			_emit_box(st, Vector3(x_flare + sx * 0.005, top_brow_y - 0.01, wz), Vector3(0.13, 0.045, arch_l + 0.04), trim)
			# Front & rear wheel-arch leg moldings framing the tire without overlapping the rim
			for end_s: float in [-1.0, 1.0]:
				_emit_box(
					st,
					Vector3(x_flare, wheel_r * 1.15, wz + end_s * (wheel_r * 1.12)),
					Vector3(0.12, wheel_r * 1.10, 0.09),
					trim
				)
		# Sculpted lower side rocker skirt between front & rear wheel arches
		var skirt_len := maxf(0.4, (front_z - rear_z) - arch_l * 1.06)
		_emit_box(st, Vector3(x_flare, wheel_r * 0.54, (front_z + rear_z) * 0.5), Vector3(0.11, 0.12, skirt_len), trim)
		# Pull-style exterior door handles
		var x_handle := sx * (wheel_x + 0.10)
		_emit_box(st, Vector3(x_handle, door_y, (front_z + rear_z) * 0.5 + 0.16), Vector3(0.038, 0.040, 0.18), alloy)
		if four_doors:
			_emit_box(st, Vector3(x_handle, door_y + 0.01, rear_z + 0.44), Vector3(0.038, 0.040, 0.18), alloy)


static func _build_sedan_mesh(is_taxi: bool = false, is_emergency: bool = false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paint := Color(1.0, 0.0, 0.0, 1.0)
	var glass := Color(0.0, 1.0, 0.0, 1.0)
	var trim := Color(0.0, 0.0, 1.0, 1.0)
	var livery := Color(0.5, 0.5, 0.0, 1.0)
	var alloy := Color(0.5, 0.5, 1.0, 1.0)

	# Grounded underbody contact shadow skirt
	_emit_contact_shadow(st, 1.88, 4.44, trim)
	# Lower chassis pan & rocker sill
	_emit_box(st, Vector3(0.0, 0.28, 0.0), Vector3(1.76, 0.16, 4.32), trim)
	# Sculpted main body tub + waist beltline crease
	_emit_tapered_box(st, Vector3(0.0, 0.62, -0.04), Vector3(1.86, 0.48, 4.02), Vector2(1.76, 3.82), paint)
	# Contoured front hood with power dome + front bumper & intake grille
	_emit_tapered_box(st, Vector3(0.0, 0.60, 1.58), Vector3(1.80, 0.44, 1.22), Vector2(1.64, 1.00), paint)
	_emit_tapered_box(st, Vector3(0.0, 0.83, 1.46), Vector3(1.12, 0.06, 0.94), Vector2(0.92, 0.78), paint)
	_emit_box(st, Vector3(0.0, 0.34, 2.18), Vector3(1.74, 0.20, 0.18), trim)
	_emit_box(st, Vector3(0.0, 0.48, 2.21), Vector3(1.16, 0.20, 0.06), trim)
	_emit_box(st, Vector3(0.0, 0.52, 2.23), Vector3(1.10, 0.04, 0.05), alloy)
	_emit_box(st, Vector3(0.0, 0.45, 2.23), Vector3(1.06, 0.03, 0.05), alloy)
	_emit_box(st, Vector3(0.0, 0.34, 2.26), Vector3(0.42, 0.11, 0.03), alloy) # Front license plate
	for fx: float in [-0.68, 0.68]:
		_emit_box(st, Vector3(fx, 0.38, 2.19), Vector3(0.24, 0.10, 0.06), trim)

	# Rear trunk deck, lip spoiler, diffuser, license plate & dual chrome exhaust tips
	_emit_tapered_box(st, Vector3(0.0, 0.65, -1.78), Vector3(1.78, 0.44, 0.86), Vector2(1.62, 0.68), paint)
	_emit_box(st, Vector3(0.0, 0.88, -2.08), Vector3(1.48, 0.045, 0.11), trim)
	_emit_box(st, Vector3(0.0, 0.34, -2.18), Vector3(1.72, 0.20, 0.18), trim)
	_emit_box(st, Vector3(0.0, 0.54, -2.20), Vector3(0.44, 0.13, 0.04), alloy)
	for ex_x: float in [-0.56, 0.56]:
		_emit_box(st, Vector3(ex_x, 0.25, -2.24), Vector3(0.11, 0.07, 0.10), alloy)

	# Multi-pillar raked cabin greenhouse with proud windshield, rear glass & split door windows
	_emit_cabin_greenhouse(st, Vector3(0.0, 1.11, -0.20), Vector3(1.58, 0.52, 2.34), Vector2(1.30, 1.46), paint, glass, trim, true, false)
	# Roof shark-fin antenna
	_emit_tapered_box(st, Vector3(0.0, 1.40, -0.78), Vector3(0.05, 0.08, 0.16), Vector2(0.02, 0.06), trim)

	# Side mirrors on stalks + sculpted wheel arches & door handles
	for mx_s: float in [-1.0, 1.0]:
		_emit_box(st, Vector3(mx_s * 0.84, 0.93, 0.56), Vector3(0.12, 0.04, 0.05), trim)
		_emit_tapered_box(st, Vector3(mx_s * 0.95, 0.96, 0.54), Vector3(0.16, 0.11, 0.14), Vector2(0.13, 0.11), paint)
	_emit_wheel_arches_and_doors(st, 0.84, 1.38, -1.36, 0.33, 0.78, paint, trim, alloy, true)

	if is_taxi:
		_emit_box(st, Vector3(0.0, 0.66, -0.02), Vector3(1.88, 0.13, 2.15), livery)
		_emit_tapered_box(st, Vector3(0.0, 1.43, -0.10), Vector3(0.56, 0.15, 0.24), Vector2(0.46, 0.18), livery)
	elif is_emergency:
		# Police/Responder side door livery, push-bumper bullbar & aerodynamic roof lightbar
		_emit_box(st, Vector3(0.0, 0.66, -0.04), Vector3(1.88, 0.20, 2.15), livery)
		_emit_box(st, Vector3(0.0, 0.52, 2.27), Vector3(0.92, 0.36, 0.09), trim)
		for bx_p: float in [-0.38, 0.38]:
			_emit_box(st, Vector3(bx_p, 0.54, 2.30), Vector3(0.06, 0.42, 0.08), trim)
		_emit_box(st, Vector3(0.0, 1.41, -0.10), Vector3(1.12, 0.09, 0.24), trim)
	for wx: float in [-0.84, 0.84]:
		for wz: float in [-1.36, 1.38]:
			_emit_wheel(st, Vector3(wx, 0.33, wz), 0.33, 0.23, trim, alloy)
	return st.commit()


static func _build_suv_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paint := Color(1.0, 0.0, 0.0, 1.0)
	var glass := Color(0.0, 1.0, 0.0, 1.0)
	var trim := Color(0.0, 0.0, 1.0, 1.0)
	var alloy := Color(0.5, 0.5, 1.0, 1.0)

	# Grounded underbody contact shadow skirt + sculpted luxury crossover SUV
	_emit_contact_shadow(st, 2.02, 4.72, trim)
	_emit_box(st, Vector3(0.0, 0.34, 0.0), Vector3(1.90, 0.20, 4.62), trim)
	_emit_tapered_box(st, Vector3(0.0, 0.72, -0.04), Vector3(1.96, 0.58, 4.38), Vector2(1.86, 4.18), paint)
	_emit_tapered_box(st, Vector3(0.0, 0.74, 1.76), Vector3(1.88, 0.52, 1.12), Vector2(1.72, 0.90), paint)
	_emit_tapered_box(st, Vector3(0.0, 0.99, 1.66), Vector3(1.22, 0.06, 0.92), Vector2(1.04, 0.76), paint)
	# Front SUV skid-plate, grille bars & license plate
	_emit_box(st, Vector3(0.0, 0.38, 2.31), Vector3(1.82, 0.22, 0.16), trim)
	_emit_box(st, Vector3(0.0, 0.31, 2.36), Vector3(1.16, 0.10, 0.08), alloy)
	_emit_box(st, Vector3(0.0, 0.62, 2.32), Vector3(1.28, 0.28, 0.06), trim)
	for gy: float in [0.54, 0.62, 0.70]:
		_emit_box(st, Vector3(0.0, gy, 2.35), Vector3(1.20, 0.035, 0.04), alloy)
	_emit_box(st, Vector3(0.0, 0.42, 2.38), Vector3(0.42, 0.12, 0.03), alloy)
	# Rear tailgate, roof spoiler, skid diffuser & dual exhausts
	_emit_box(st, Vector3(0.0, 0.38, -2.28), Vector3(1.82, 0.22, 0.16), trim)
	_emit_box(st, Vector3(0.0, 0.31, -2.33), Vector3(1.18, 0.10, 0.08), alloy)
	_emit_box(st, Vector3(0.0, 0.68, -2.26), Vector3(0.44, 0.13, 0.04), alloy)
	for ex_x: float in [-0.62, 0.62]:
		_emit_box(st, Vector3(ex_x, 0.28, -2.35), Vector3(0.12, 0.08, 0.10), alloy)

	# Extended 3-window wagon greenhouse (front door + rear door + cargo quarter glass) + roof spoiler & rails
	_emit_cabin_greenhouse(st, Vector3(0.0, 1.31, -0.32), Vector3(1.70, 0.60, 2.94), Vector2(1.46, 2.28), paint, glass, trim, true, true)
	_emit_tapered_box(st, Vector3(0.0, 1.60, -1.52), Vector3(1.44, 0.07, 0.26), Vector2(1.36, 0.22), paint)
	_emit_tapered_box(st, Vector3(0.0, 1.64, -1.24), Vector3(0.05, 0.09, 0.18), Vector2(0.02, 0.06), trim)
	for rx: float in [-0.60, 0.60]:
		_emit_box(st, Vector3(rx, 1.66, -0.36), Vector3(0.06, 0.05, 2.06), alloy)
		for rz_p: float in [-1.24, -0.36, 0.52]:
			_emit_box(st, Vector3(rx, 1.62, rz_p), Vector3(0.05, 0.06, 0.08), trim)
	for mx_s: float in [-1.0, 1.0]:
		_emit_box(st, Vector3(mx_s * 0.90, 1.09, 0.64), Vector3(0.12, 0.04, 0.05), trim)
		_emit_tapered_box(st, Vector3(mx_s * 1.01, 1.13, 0.62), Vector3(0.18, 0.13, 0.15), Vector2(0.14, 0.12), paint)
	_emit_wheel_arches_and_doors(st, 0.88, 1.46, -1.45, 0.37, 0.88, paint, trim, alloy, true)

	for wx: float in [-0.88, 0.88]:
		for wz: float in [-1.45, 1.46]:
			_emit_wheel(st, Vector3(wx, 0.37, wz), 0.37, 0.25, trim, alloy)
	return st.commit()


static func _build_hatchback_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paint := Color(1.0, 0.0, 0.0, 1.0)
	var glass := Color(0.0, 1.0, 0.0, 1.0)
	var trim := Color(0.0, 0.0, 1.0, 1.0)
	var alloy := Color(0.5, 0.5, 1.0, 1.0)

	# Agile Euro/urban hot-hatch with sculpted bumpers, roof wing & split windows
	_emit_contact_shadow(st, 1.82, 3.96, trim)
	_emit_box(st, Vector3(0.0, 0.28, 0.0), Vector3(1.70, 0.16, 3.84), trim)
	_emit_tapered_box(st, Vector3(0.0, 0.61, -0.04), Vector3(1.78, 0.50, 3.70), Vector2(1.68, 3.48), paint)
	_emit_tapered_box(st, Vector3(0.0, 0.56, 1.54), Vector3(1.70, 0.38, 0.78), Vector2(1.52, 0.58), paint)
	_emit_box(st, Vector3(0.0, 0.33, 1.91), Vector3(1.64, 0.18, 0.14), trim)
	_emit_box(st, Vector3(0.0, 0.46, 1.93), Vector3(1.08, 0.16, 0.05), trim)
	_emit_box(st, Vector3(0.0, 0.48, 1.95), Vector3(1.02, 0.04, 0.04), alloy)
	_emit_box(st, Vector3(0.0, 0.34, 1.97), Vector3(0.40, 0.11, 0.03), alloy)
	_emit_box(st, Vector3(0.0, 0.33, -1.89), Vector3(1.64, 0.18, 0.14), trim)
	_emit_box(st, Vector3(0.0, 0.54, -1.91), Vector3(0.42, 0.12, 0.04), alloy)

	_emit_cabin_greenhouse(st, Vector3(0.0, 1.11, -0.32), Vector3(1.54, 0.52, 2.38), Vector2(1.28, 1.70), paint, glass, trim, true, false)
	_emit_tapered_box(st, Vector3(0.0, 1.37, -1.22), Vector3(1.26, 0.06, 0.24), Vector2(1.18, 0.20), trim)
	_emit_tapered_box(st, Vector3(0.0, 1.40, -0.96), Vector3(0.05, 0.08, 0.15), Vector2(0.02, 0.05), trim)
	for mx_s: float in [-1.0, 1.0]:
		_emit_box(st, Vector3(mx_s * 0.80, 0.93, 0.48), Vector3(0.11, 0.04, 0.05), trim)
		_emit_tapered_box(st, Vector3(mx_s * 0.91, 0.96, 0.46), Vector3(0.15, 0.10, 0.13), Vector2(0.12, 0.10), paint)
	_emit_wheel_arches_and_doors(st, 0.80, 1.22, -1.18, 0.31, 0.76, paint, trim, alloy, true)

	for wx: float in [-0.80, 0.80]:
		for wz: float in [-1.18, 1.22]:
			_emit_wheel(st, Vector3(wx, 0.31, wz), 0.31, 0.21, trim, alloy)
	return st.commit()


static func _build_pickup_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paint := Color(1.0, 0.0, 0.0, 1.0)
	var glass := Color(0.0, 1.0, 0.0, 1.0)
	var trim := Color(0.0, 0.0, 1.0, 1.0)
	var alloy := Color(0.5, 0.5, 1.0, 1.0)

	# Heavy-duty crew-cab pickup with bold chrome grille, step bars, split cab windows & detailed bed
	_emit_contact_shadow(st, 2.10, 5.38, trim)
	_emit_box(st, Vector3(0.0, 0.38, 0.0), Vector3(1.94, 0.22, 5.24), trim)
	# Front hood, heavy chrome bumper & twin-bar truck grille
	_emit_tapered_box(st, Vector3(0.0, 0.80, 1.72), Vector3(1.98, 0.62, 1.66), Vector2(1.86, 1.46), paint)
	_emit_tapered_box(st, Vector3(0.0, 1.12, 1.66), Vector3(1.30, 0.07, 1.22), Vector2(1.12, 1.04), paint)
	_emit_box(st, Vector3(0.0, 0.42, 2.58), Vector3(1.98, 0.24, 0.18), alloy)
	_emit_box(st, Vector3(0.0, 0.38, 2.68), Vector3(0.44, 0.12, 0.03), trim)
	_emit_box(st, Vector3(0.0, 0.78, 2.57), Vector3(1.48, 0.42, 0.07), trim)
	_emit_box(st, Vector3(0.0, 0.86, 2.61), Vector3(1.42, 0.07, 0.04), alloy)
	_emit_box(st, Vector3(0.0, 0.72, 2.61), Vector3(1.42, 0.07, 0.04), alloy)
	# Crew cab lower body + multi-pillar cab greenhouse with proud windshield, rear cab glass & B-pillars
	_emit_tapered_box(st, Vector3(0.0, 0.80, 0.34), Vector3(2.00, 0.62, 1.82), Vector2(1.92, 1.76), paint)
	_emit_cabin_greenhouse(st, Vector3(0.0, 1.39, 0.26), Vector3(1.80, 0.60, 1.74), Vector2(1.56, 1.36), paint, glass, trim, true, false)

	# Open recessed cargo bed (ribbed bed liner floor + wheel tubs + rails + rear bumper step)
	_emit_box(st, Vector3(0.0, 0.60, -1.56), Vector3(1.86, 0.14, 1.98), trim)
	for bx: float in [-0.92, 0.92]:
		_emit_tapered_box(st, Vector3(bx, 0.84, -1.56), Vector3(0.16, 0.58, 2.02), Vector2(0.14, 1.98), paint)
		_emit_box(st, Vector3(bx, 1.14, -1.56), Vector3(0.16, 0.04, 2.02), trim)
	_emit_tapered_box(st, Vector3(0.0, 0.84, -2.54), Vector3(1.96, 0.58, 0.15), Vector2(1.90, 0.13), paint)
	_emit_box(st, Vector3(0.0, 0.40, -2.60), Vector3(1.96, 0.22, 0.18), alloy)
	_emit_box(st, Vector3(0.0, 0.42, -2.70), Vector3(0.44, 0.12, 0.03), trim)

	# Wide tow mirrors on dual arms + wheel arches + cab step bars
	for mx_s: float in [-1.0, 1.0]:
		_emit_box(st, Vector3(mx_s * 0.94, 1.16, 0.86), Vector3(0.16, 0.05, 0.06), trim)
		_emit_box(st, Vector3(mx_s * 1.07, 1.20, 0.86), Vector3(0.16, 0.22, 0.12), trim)
		_emit_box(st, Vector3(mx_s * 0.98, 0.34, 0.32), Vector3(0.14, 0.06, 1.62), alloy)
	_emit_wheel_arches_and_doors(st, 0.90, 1.66, -1.62, 0.39, 0.94, paint, trim, alloy, true)

	for wx: float in [-0.90, 0.90]:
		for wz: float in [-1.62, 1.66]:
			_emit_wheel(st, Vector3(wx, 0.39, wz), 0.39, 0.26, trim, alloy)
	return st.commit()


static func _build_van_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paint := Color(1.0, 0.0, 0.0, 1.0)
	var glass := Color(0.0, 1.0, 0.0, 1.0)
	var trim := Color(0.0, 0.0, 1.0, 1.0)
	var livery := Color(0.5, 0.5, 0.0, 1.0)
	var alloy := Color(0.5, 0.5, 1.0, 1.0)

	# Modern high-roof commercial sprinter van with proud windshield, cab side windows & rear cargo doors
	_emit_contact_shadow(st, 2.10, 5.48, trim)
	_emit_box(st, Vector3(0.0, 0.36, 0.0), Vector3(2.00, 0.24, 5.38), trim)
	_emit_tapered_box(st, Vector3(0.0, 0.72, 2.06), Vector3(1.98, 0.64, 1.22), Vector2(1.84, 0.94), paint)
	_emit_box(st, Vector3(0.0, 0.38, 2.66), Vector3(1.94, 0.24, 0.16), trim)
	_emit_box(st, Vector3(0.0, 0.62, 2.66), Vector3(1.32, 0.28, 0.06), trim)
	_emit_box(st, Vector3(0.0, 0.64, 2.69), Vector3(1.24, 0.05, 0.04), alloy)
	_emit_box(st, Vector3(0.0, 0.38, 2.74), Vector3(0.42, 0.11, 0.03), alloy)
	# Cargo box body + fleet livery band + rear barn-door seam & windows
	_emit_tapered_box(st, Vector3(0.0, 1.44, -0.46), Vector3(2.02, 1.88, 4.26), Vector2(1.88, 4.14), paint)
	_emit_box(st, Vector3(0.0, 1.26, -0.46), Vector3(2.05, 0.28, 4.04), livery)
	_emit_box(st, Vector3(0.0, 0.56, -0.46), Vector3(2.05, 0.14, 4.12), trim)
	_emit_box(st, Vector3(0.0, 1.44, -2.58), Vector3(0.04, 1.72, 0.04), trim)
	for rwx: float in [-0.46, 0.46]:
		_emit_box(st, Vector3(rwx, 1.68, -2.57), Vector3(0.62, 0.54, 0.04), glass)
	# Forward cab greenhouse with proud raked windshield & side driver/passenger windows
	_emit_cabin_greenhouse(st, Vector3(0.0, 1.50, 1.74), Vector3(1.92, 0.96, 1.12), Vector2(1.72, 0.72), paint, glass, trim, false, false)

	for mx_s: float in [-1.0, 1.0]:
		_emit_box(st, Vector3(mx_s * 0.96, 1.28, 1.98), Vector3(0.14, 0.05, 0.05), trim)
		_emit_box(st, Vector3(mx_s * 1.06, 1.34, 1.98), Vector3(0.15, 0.24, 0.12), trim)
	_emit_wheel_arches_and_doors(st, 0.90, 1.66, -1.62, 0.37, 1.02, paint, trim, alloy, false)

	for wx: float in [-0.90, 0.90]:
		for wz: float in [-1.62, 1.66]:
			_emit_wheel(st, Vector3(wx, 0.37, wz), 0.37, 0.25, trim, alloy)
	return st.commit()


static func _build_bus_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paint := Color(1.0, 0.0, 0.0, 1.0)
	var glass := Color(0.0, 1.0, 0.0, 1.0)
	var trim := Color(0.0, 0.0, 1.0, 1.0)
	var livery := Color(0.5, 0.5, 0.0, 1.0)
	var alloy := Color(0.5, 0.5, 1.0, 1.0)

	# Modern low-floor electric transit bus with individual framed passenger window bays,
	# panoramic front windshield, glazed folding boarding doors, and rooftop battery pods.
	_emit_contact_shadow(st, 2.54, 10.26, trim)
	_emit_box(st, Vector3(0.0, 0.40, 0.0), Vector3(2.46, 0.28, 10.16), trim)
	# Solid painted lower & upper coach hull (eliminates hollow see-through artifacts!)
	_emit_tapered_box(st, Vector3(0.0, 1.62, 0.0), Vector3(2.44, 2.26, 10.12), Vector2(2.34, 9.96), paint)
	_emit_box(st, Vector3(0.0, 1.14, 0.0), Vector3(2.47, 0.26, 9.96), livery)
	_emit_box(st, Vector3(0.0, 0.62, 0.0), Vector3(2.47, 0.12, 10.04), trim)
	# Panoramic front driver windshield (+Z) & rear window (-Z)
	_emit_tapered_box(st, Vector3(0.0, 1.92, 4.98), Vector3(2.24, 1.16, 0.20), Vector2(2.14, 0.14), glass)
	_emit_box(st, Vector3(0.0, 2.62, 5.04), Vector3(1.88, 0.26, 0.08), trim)
	_emit_box(st, Vector3(0.0, 2.62, 5.07), Vector3(1.62, 0.16, 0.04), livery)
	_emit_box(st, Vector3(0.0, 2.02, -5.02), Vector3(2.04, 0.88, 0.12), glass)
	_emit_box(st, Vector3(0.0, 0.92, -5.06), Vector3(1.76, 0.48, 0.06), trim)

	# 6 distinct framed passenger window bays along left & right coach walls + dark window mullions
	_emit_box(st, Vector3(0.0, 1.98, -0.10), Vector3(2.45, 1.08, 9.20), trim)
	var bay_zs := [-3.90, -2.35, -0.80, 0.75, 2.30, 3.85]
	for bz in bay_zs:
		_emit_box(st, Vector3(0.0, 1.98, bz), Vector3(2.475, 0.96, 1.32), glass)
	# Right-side (-X in local bus frame) full-height glazed transit boarding doors (front & mid)
	for dz_door: float in [0.75, 3.85]:
		_emit_box(st, Vector3(-1.22, 1.44, dz_door), Vector3(0.06, 1.96, 1.24), trim)
		for leaf_off: float in [-0.28, 0.28]:
			_emit_box(st, Vector3(-1.235, 1.48, dz_door + leaf_off), Vector3(0.05, 1.76, 0.48), glass)

	# Extended transit mirrors on high forward arms + wheel arches + rooftop battery/HVAC pod
	for mx_s: float in [-1.0, 1.0]:
		_emit_box(st, Vector3(mx_s * 1.24, 2.18, 5.06), Vector3(0.24, 0.05, 0.22), trim)
		_emit_box(st, Vector3(mx_s * 1.34, 1.96, 5.14), Vector3(0.14, 0.38, 0.12), trim)
	_emit_tapered_box(st, Vector3(0.0, 2.88, -0.45), Vector3(1.72, 0.28, 5.80), Vector2(1.52, 5.20), livery)
	_emit_wheel_arches_and_doors(st, 1.08, 3.15, -3.15, 0.45, 1.10, paint, trim, alloy, false)

	for wx: float in [-1.08, 1.08]:
		for wz: float in [-3.15, 3.15]:
			_emit_wheel(st, Vector3(wx, 0.45, wz), 0.45, 0.31, trim, alloy)
	return st.commit()


static func _build_light_cluster_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var head_col := Color(1.0, 0.0, 0.0, 1.0)
	var tail_col := Color(0.0, 1.0, 0.0, 1.0)
	var brake_col := Color(0.0, 0.0, 1.0, 1.0)
	var lblink_col := Color(1.0, 1.0, 0.0, 1.0)
	var rblink_col := Color(0.0, 1.0, 1.0, 1.0)
	var roof_l_col := Color(1.0, 0.0, 1.0, 1.0)
	var roof_r_col := Color(0.5, 0.0, 1.0, 1.0)

	# Normalized X [-0.5..+0.5] width, Z [-0.5..+0.5] length, Y in meters above light_y
	for sx: float in [-0.33, 0.33]:
		# Front headlights (+Z)
		_emit_quad(st, Vector3(sx - 0.08, 0.05, 0.514), Vector3(sx + 0.08, 0.05, 0.514), Vector3(sx - 0.08, -0.04, 0.514), Vector3(sx + 0.08, -0.04, 0.514), Vector3(0, 0, 1), head_col)
		# Rear taillights & brake lights (-Z)
		_emit_quad(st, Vector3(sx + 0.085, 0.07, -0.514), Vector3(sx - 0.085, 0.07, -0.514), Vector3(sx + 0.085, -0.03, -0.514), Vector3(sx - 0.085, -0.03, -0.514), Vector3(0, 0, -1), tail_col)

	# High-mounted center brake bar (-Z)
	_emit_quad(st, Vector3(0.11, 0.22, -0.514), Vector3(-0.11, 0.22, -0.514), Vector3(0.11, 0.17, -0.514), Vector3(-0.11, 0.17, -0.514), Vector3(0, 0, -1), brake_col)

	# Left (+X in local car space with +Z fwd, wait: r = UP.cross(f) -> +X is LEFT!) & Right (-X) amber turn indicators
	# Wait: Vector3.UP.cross(Vector3(0, 0, 1)) = Vector3(1, 0, 0) = +X is LEFT when facing +Z!
	# Front & Rear LEFT turn blinkers (+X corner)
	_emit_quad(st, Vector3(0.41, 0.05, 0.516), Vector3(0.49, 0.05, 0.516), Vector3(0.41, -0.03, 0.516), Vector3(0.49, -0.03, 0.516), Vector3(0, 0, 1), lblink_col)
	_emit_quad(st, Vector3(0.49, 0.06, -0.516), Vector3(0.41, 0.06, -0.516), Vector3(0.49, -0.02, -0.516), Vector3(0.41, -0.02, -0.516), Vector3(0, 0, -1), lblink_col)
	# Front & Rear RIGHT turn blinkers (-X corner)
	_emit_quad(st, Vector3(-0.49, 0.05, 0.516), Vector3(-0.41, 0.05, 0.516), Vector3(-0.49, -0.03, 0.516), Vector3(-0.41, -0.03, 0.516), Vector3(0, 0, 1), rblink_col)
	_emit_quad(st, Vector3(-0.41, 0.06, -0.516), Vector3(-0.49, 0.06, -0.516), Vector3(-0.41, -0.02, -0.516), Vector3(-0.49, -0.02, -0.516), Vector3(0, 0, -1), rblink_col)

	# Roof emergency lightbar / Taxi beacon glowing bars (collapsed in vertex shader for regular vehicles)
	_emit_box(st, Vector3(0.14, 0.80, -0.02), Vector3(0.24, 0.11, 0.055), roof_l_col)
	_emit_box(st, Vector3(-0.14, 0.80, -0.02), Vector3(0.24, 0.11, 0.055), roof_r_col)
	return st.commit()


static func _build_signal_lens_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := 0.14
	var hh := 0.39
	_emit_quad_uv(st, Vector3(-hw, hh, 0.196), Vector3(hw, hh, 0.196), Vector3(-hw, -hh, 0.196), Vector3(hw, -hh, 0.196), Vector3(0, 0, 1))
	_emit_quad_uv(st, Vector3(hw, hh, -0.196), Vector3(-hw, hh, -0.196), Vector3(hw, -hh, -0.196), Vector3(-hw, -hh, -0.196), Vector3(0, 0, -1))
	return st.commit()


static func _emit_box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color) -> void:
	_emit_tapered_box(st, center, size, Vector2(size.x, size.z), col)


static func _emit_contact_shadow(st: SurfaceTool, width: float, length: float, _col: Color) -> void:
	## Pure matte non-specular underbody ambient-occlusion contact shadow quad at y = 0.024m.
	var shadow_col := Color(0.0, 0.0, 0.0, 1.0)
	var hw := width * 0.48
	var hl := length * 0.48
	var y := 0.024
	_emit_quad(
		st,
		Vector3(-hw, y, -hl),
		Vector3(hw, y, -hl),
		Vector3(-hw, y, hl),
		Vector3(hw, y, hl),
		Vector3.UP,
		shadow_col
	)


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

	# Analytical outward normals for all 6 faces (strictly outward: +Y, -Y, +Z, -Z, +X, -X)
	var h_full := maxf(0.001, bot_size.y)
	var n_front := Vector3(0.0, hz0 - hz1, h_full).normalized()
	var n_back := Vector3(0.0, hz0 - hz1, -h_full).normalized()
	var n_right := Vector3(h_full, hx0 - hx1, 0.0).normalized()
	var n_left := Vector3(-h_full, hx0 - hx1, 0.0).normalized()

	_emit_quad(st, t00, t10, t01, t11, Vector3.UP, col)
	_emit_quad(st, b01, b11, b00, b10, Vector3.DOWN, col)
	_emit_quad(st, t01, t11, b01, b11, n_front, col)
	_emit_quad(st, t10, t00, b10, b00, n_back, col)
	_emit_quad(st, t11, t10, b11, b10, n_right, col)
	_emit_quad(st, t00, t01, b00, b01, n_left, col)


static func _emit_wheel(st: SurfaceTool, center: Vector3, radius: float, width: float, tire_col: Color, hub_col: Color) -> void:
	# 12-sided deep-tread rubber tire + dark brake drum backing + 5-spoke sculpted 3D alloy rim & center cap
	const SEGS := 12
	var hw := width * 0.5
	var c_l := center + Vector3(-hw, 0.0, 0.0)
	var c_r := center + Vector3(hw, 0.0, 0.0)
	var rim_r := radius * 0.66
	var drum_r := radius * 0.56
	var c_dl := center + Vector3(-hw - 0.005, 0.0, 0.0)
	var c_dr := center + Vector3(hw + 0.005, 0.0, 0.0)
	var shadow_col := Color(0.0, 0.0, 0.0, 1.0)
	for i in range(SEGS):
		var a0 := float(i) * TAU / float(SEGS)
		var a1 := float(i + 1) * TAU / float(SEGS)
		var r0 := Vector3(0.0, cos(a0) * radius, sin(a0) * radius)
		var r1 := Vector3(0.0, cos(a1) * radius, sin(a1) * radius)
		var rm0 := Vector3(0.0, cos(a0) * rim_r, sin(a0) * rim_r)
		var rm1 := Vector3(0.0, cos(a1) * rim_r, sin(a1) * rim_r)
		var dr0 := Vector3(0.0, cos(a0) * drum_r, sin(a0) * drum_r)
		var dr1 := Vector3(0.0, cos(a1) * drum_r, sin(a1) * drum_r)
		var mid_a := (a0 + a1) * 0.5
		var tread_n := Vector3(0.0, cos(mid_a), sin(mid_a)).normalized()
		# Tire tread & sidewalls
		_emit_quad(st, c_l + r0, c_r + r0, c_l + r1, c_r + r1, tread_n, tire_col)
		_emit_quad(st, c_r + r0, c_r + r1, c_r + rm0, c_r + rm1, Vector3.RIGHT, tire_col)
		_emit_quad(st, c_l + r1, c_l + r0, c_l + rm1, c_l + rm0, Vector3.LEFT, tire_col)
		# Alloy outer rim lip ring
		_emit_quad(st, c_dr + rm0, c_dr + rm1, c_dr + dr0, c_dr + dr1, Vector3.RIGHT, hub_col)
		_emit_quad(st, c_dl + rm1, c_dl + rm0, c_dl + dr1, c_dl + dr0, Vector3.LEFT, hub_col)
		# Recessed dark brake rotor disc behind spokes
		_emit_tri(st, c_dr, c_dr + dr0, c_dr + dr1, Vector3.RIGHT, shadow_col)
		_emit_tri(st, c_dl, c_dl + dr1, c_dl + dr0, Vector3.LEFT, shadow_col)

	# 5 sculpted radial alloy spokes + machined center hub cap on outer face
	var is_right_side := center.x >= 0.0
	var out_x := (center.x + hw + 0.012) if is_right_side else (center.x - hw - 0.012)
	var out_n := Vector3.RIGHT if is_right_side else Vector3.LEFT
	var sp_w := radius * 0.13
	for sp_i in range(5):
		var sa := float(sp_i) * TAU / 5.0 + 0.25
		var dir_yz := Vector3(0.0, cos(sa), sin(sa))
		var perp_yz := Vector3(0.0, -sin(sa), cos(sa)) * sp_w
		var p_in0 := Vector3(out_x, center.y, center.z) + dir_yz * (radius * 0.12) - perp_yz
		var p_in1 := Vector3(out_x, center.y, center.z) + dir_yz * (radius * 0.12) + perp_yz
		var p_out0 := Vector3(out_x, center.y, center.z) + dir_yz * (drum_r * 1.02) - perp_yz * 0.78
		var p_out1 := Vector3(out_x, center.y, center.z) + dir_yz * (drum_r * 1.02) + perp_yz * 0.78
		_emit_quad(st, p_out0, p_out1, p_in0, p_in1, out_n, hub_col)
	_emit_box(st, Vector3(out_x, center.y, center.z), Vector3(0.018, radius * 0.30, radius * 0.30), hub_col)


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


static func _emit_quad_uv(st: SurfaceTool, tl: Vector3, tr: Vector3, bl: Vector3, br: Vector3, desired_n: Vector3) -> void:
	var n_test := (bl - tl).cross(tr - tl)
	var pts: Array[Vector3]
	var uvs: Array[Vector2]
	if n_test.dot(desired_n) >= 0.0:
		pts = [tl, tr, bl, tr, br, bl]
		uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	else:
		pts = [tl, bl, tr, tr, bl, br]
		uvs = [Vector2(0, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]
	var n := desired_n.normalized()
	for i in range(6):
		st.set_uv(uvs[i])
		st.set_normal(n)
		st.add_vertex(pts[i])


static func _emit_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, desired_n: Vector3, col: Color) -> void:
	var n_test := (c - a).cross(b - a)
	var pts := [a, b, c] if n_test.dot(desired_n) >= 0.0 else [a, c, b]
	var n := desired_n.normalized()
	for p in pts:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(p)


static func _build_boat_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paint := Color(1.0, 0.0, 0.0, 1.0)
	var glass := Color(0.0, 1.0, 0.0, 1.0)
	var trim := Color(0.0, 0.0, 1.0, 1.0)

	# Low-profile 11.4m river ferry/vessel (max height 1.30m above water for clean bridge clearance)
	_emit_tapered_box(st, Vector3(0.0, 0.14, -0.4), Vector3(3.45, 0.72, 9.6), Vector2(3.15, 8.8), trim)
	_emit_tapered_box(st, Vector3(0.0, 0.22, 4.9), Vector3(3.0, 0.62, 2.2), Vector2(0.85, 0.9), trim)
	_emit_tapered_box(st, Vector3(0.0, 0.76, -0.5), Vector3(2.85, 0.50, 6.2), Vector2(2.55, 5.4), paint)
	_emit_tapered_box(st, Vector3(0.0, 1.15, 0.35), Vector3(2.15, 0.30, 3.0), Vector2(1.85, 2.5), glass)
	return st.commit()
