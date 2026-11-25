class_name CityWorld
extends Node3D

## Orchestrates deterministic CityPlan generation, chunked 3D assembly,
## interactive door state, and separated persistence.

signal city_rebuilt(plan: CityPlan)

@export var default_seed: int = 202801
@export var auto_generate_on_ready: bool = true

const INTERIOR_EDGE_ACTIVATE_DIST := 18.0
const INTERIOR_EDGE_DEACTIVATE_DIST := 38.0
const BUILDING_GRID_CELL := 64.0
const TrafficManagerScript := preload("res://src/city_world/traffic/traffic_manager.gd")
const CrowdManagerScript := preload("res://src/city_world/traffic/crowd_manager.gd")

var config: CityConfig = null
var plan: CityPlan = null
var mats: MaterialLibrary = null
var chunk_roots: Dictionary = {} # Vector2i -> Node3D
var doors_by_id: Dictionary = {} # String -> InteractiveDoor
var buildings_by_id: Dictionary = {} # String -> {bp: BuildingBlueprint, node: Node3D}
var streetlight_heads: Array[Vector3] = []
var traffic_manager: Node3D = null
var crowd_manager: Node3D = null
const INTERIOR_CACHE_LIMIT := 24

# Performance & quality controls (configured by PerformanceController)
var chunk_cull_distance: float = 1150.0
var keep_skyline_chunks: bool = true
var enable_interior_probes: bool = false
var interior_stream_enabled: bool = true

var interior_blueprints: Dictionary = {} # String -> InteriorBlueprint
var _active_interiors: Dictionary = {} # String -> {group: Node3D, doors: Array[InteractiveDoor]}
var _cached_interiors: Dictionary = {} # String -> {group: Node3D, doors: Array[InteractiveDoor]}
var _cached_interior_order: Array[String] = []
var _pending_bp_tasks: Dictionary = {} # String -> {task_id: int, result: Array}
var _pending_floor_builds: Dictionary = {} # String -> {bp, ib, group, next_floor, total_floors}
var _opened_door_ids: Dictionary = {} # String -> bool
var _building_grid: Dictionary = {} # Vector2i -> Array[String]
var _chunk_centers: Dictionary = {} # Vector2i -> Vector2
var _chunk_has_tall: Dictionary = {} # Vector2i -> bool
var _visible_chunk_count: int = 0
var _last_chunk_cull_pos: Vector3 = Vector3(-99999.0, 0.0, -99999.0)
var _world_container: Node3D = null
var viewer_node: Node3D = null
var _atmosphere_node: Node = null
var _stream_timer: float = 0.0


func _ready() -> void:
	if mats == null:
		mats = MaterialLibrary.new()
	if auto_generate_on_ready:
		build_from_seed(default_seed)


func _exit_tree() -> void:
	_flush_pending_bp_tasks()
	_pending_floor_builds.clear()
	_clear_interior_cache(true)


func _flush_pending_bp_tasks() -> void:
	for b_id in _pending_bp_tasks.keys():
		var info: Dictionary = _pending_bp_tasks[b_id]
		var tid: int = int(info.get("task_id", -1))
		if tid >= 0:
			WorkerThreadPool.wait_for_task_completion(tid)
	_pending_bp_tasks.clear()


func _poll_pending_bp_tasks() -> void:
	if _pending_bp_tasks.is_empty():
		return
	var done_ids: Array[String] = []
	for b_id in _pending_bp_tasks.keys():
		var info: Dictionary = _pending_bp_tasks[b_id]
		var tid: int = int(info.get("task_id", -1))
		if tid < 0 or WorkerThreadPool.is_task_completed(tid):
			if tid >= 0:
				WorkerThreadPool.wait_for_task_completion(tid)
			var res_arr: Array = info.get("result", [])
			if not res_arr.is_empty() and res_arr[0] != null:
				interior_blueprints[b_id] = res_arr[0]
			done_ids.append(String(b_id))
	for b_id in done_ids:
		_pending_bp_tasks.erase(b_id)


func _queue_async_blueprint_prewarm(b_id: String, bp: BuildingBlueprint) -> void:
	if config == null or interior_blueprints.has(b_id) or _pending_bp_tasks.has(b_id):
		return
	if _pending_bp_tasks.size() >= 3:
		return
	var seed_v: int = config.world_seed
	var res_box: Array = []
	var tid := WorkerThreadPool.add_task(func() -> void:
		res_box.append(InteriorGenerator.generate(bp, seed_v))
	)
	_pending_bp_tasks[b_id] = {"task_id": tid, "result": res_box}


func _step_pending_floor_builds(floors_per_tick: int = 2) -> void:
	if _pending_floor_builds.is_empty():
		return
	var b_id := String(_pending_floor_builds.keys()[0])
	if not _active_interiors.has(b_id):
		_pending_floor_builds.erase(b_id)
		return
	var job: Dictionary = _pending_floor_builds[b_id]
	var group: Node3D = job["group"]
	if group == null or not is_instance_valid(group):
		_pending_floor_builds.erase(b_id)
		return
	var bp: BuildingBlueprint = job["bp"]
	var ib: InteriorBlueprint = job["ib"]
	var start_fl: int = int(job["next_floor"])
	var total_fl: int = int(job["total_floors"])
	var end_fl := mini(total_fl, start_fl + maxi(1, floors_per_tick))
	var new_doors := InteriorBuilder.append_interior_floors(group, bp, ib, mats, start_fl, end_fl)
	var act: Dictionary = _active_interiors[b_id]
	var idoors: Array = act["doors"]
	for d in new_doors:
		idoors.append(d)
		_register_door(d)
	if end_fl >= total_fl:
		_pending_floor_builds.erase(b_id)
	else:
		job["next_floor"] = end_fl


func _clear_interior_cache(immediate: bool = false) -> void:
	for ck in _cached_interiors.keys():
		var cg: Node3D = _cached_interiors[ck]["group"]
		if cg != null and is_instance_valid(cg):
			if immediate:
				cg.free()
			else:
				cg.queue_free()
	_cached_interiors.clear()
	_cached_interior_order.clear()


func _process(delta: float) -> void:
	if plan == null or Engine.is_editor_hint():
		return
	if viewer_node == null and get_parent() != null:
		viewer_node = get_parent().get_node_or_null("PlayerController") as Node3D
	if _atmosphere_node == null and get_parent() != null:
		_atmosphere_node = get_parent().get_node_or_null("AtmosphereController")

	var viewer_pos := viewer_node.global_position if viewer_node != null else plan.spawn_position
	var nf := float(_atmosphere_node.get("night_factor")) if _atmosphere_node != null else 0.0
	var tod_h := float(_atmosphere_node.get("time_of_day_hour")) if _atmosphere_node != null else 10.5
	var w_rain := float(_atmosphere_node.get("weather_rain")) if _atmosphere_node != null else 0.0
	var w_snow := float(_atmosphere_node.get("weather_snow")) if _atmosphere_node != null else 0.0
	var w_snow_depth := float(_atmosphere_node.get("weather_snow_depth")) if _atmosphere_node != null else 0.0
	var w_wet := float(_atmosphere_node.get("weather_wetness")) if _atmosphere_node != null else 0.0
	var eff_precip := clampf(maxf(w_rain, w_snow * 0.85), 0.0, 1.0)
	var eff_traction := clampf(maxf(w_wet, w_snow_depth * 0.95), 0.0, 1.0)
	# Step CrowdManager first so live crosswalk pedestrian positions feed TrafficManager yielding on the same tick
	if crowd_manager != null and is_instance_valid(crowd_manager):
		crowd_manager.step(delta, viewer_pos, nf, tod_h, eff_precip)
	if traffic_manager != null and is_instance_valid(traffic_manager):
		traffic_manager.step(delta, viewer_pos, nf, tod_h, eff_precip, eff_traction)

	_poll_pending_bp_tasks()
	_step_pending_floor_builds(2)

	_stream_timer += delta
	if _stream_timer < 0.16:
		return
	_stream_timer = 0.0
	if viewer_node != null:
		_update_chunk_visibility(viewer_node.global_position, false)
		if interior_stream_enabled:
			var activated_now := _update_interior_streaming_count(viewer_node.global_position, 1, false)
			if activated_now == 0:
				_prewarm_nearby_interior_blueprint(viewer_node.global_position)


func build_from_seed(seed_value: int, p_config: CityConfig = null) -> CityPlan:
	if mats == null:
		mats = MaterialLibrary.new()
	config = p_config if p_config != null else CityConfig.new()
	config.world_seed = seed_value

	plan = generate_plan_only(config)
	rebuild_scene_from_plan(plan)
	city_rebuilt.emit(plan)
	return plan


static func generate_plan_only(cfg: CityConfig) -> CityPlan:
	var rng := RandomNumberGenerator.new()
	rng.seed = cfg.world_seed

	var out := CityPlan.new()
	out.config = cfg

	# Stage 1: Districts & natural terrain
	out.district_centers = DistrictGenerator.generate_district_centers(cfg, rng)
	out.terrain = TerrainGenerator.generate_base_terrain(cfg, out.district_centers)

	# Stage 2: Connected road graph, bridges & blocks
	var road_res := RoadGenerator.generate(cfg, out.terrain, out.district_centers, rng)
	out.road_graph = road_res["road_graph"]
	out.blocks = road_res["blocks"]

	# Stage 3: Grade terrain to road corridors & junctions
	TerrainGenerator.grade_terrain_to_roads(out.terrain, out.road_graph)

	# Stage 4: Parcels & zoning
	out.parcels = ParcelGenerator.generate(cfg, out.terrain, out.road_graph, out.blocks, rng)

	# Stage 5: Authoritative BuildingBlueprints + building-pad excavation
	out.blueprints = BuildingGenerator.generate(cfg, out.terrain, out.road_graph, out.parcels, rng)
	TerrainGenerator.grade_terrain_to_buildings(out.terrain, out.blueprints)

	# Stage 6: Connected Park Walkways, Plazas & Creekside Greenways + 2028 Street Props
	out.park_walkways = ParkWalkwayGenerator.generate(cfg, out.terrain, out.road_graph, out.parcels, out.blueprints, rng)
	out.props = EnvironmentGenerator.generate(cfg, out.terrain, out.road_graph, out.parcels, out.blueprints, rng, out.park_walkways)

	# Compute safe player spawn point near central downtown sidewalk
	out.spawn_position = _find_safe_spawn(out)
	out.spawn_yaw = 0.0
	out.compute_plan_hash()
	return out


func rebuild_scene_from_plan(p_plan: CityPlan) -> void:
	if _world_container != null:
		_world_container.queue_free()
		remove_child(_world_container)
		_world_container = null

	_flush_pending_bp_tasks()
	_pending_floor_builds.clear()
	chunk_roots.clear()
	_chunk_centers.clear()
	_chunk_has_tall.clear()
	_visible_chunk_count = 0
	_last_chunk_cull_pos = Vector3(-99999.0, 0.0, -99999.0)
	doors_by_id.clear()
	buildings_by_id.clear()
	_building_grid.clear()
	interior_blueprints.clear()
	_active_interiors.clear()
	_clear_interior_cache(false)
	_opened_door_ids.clear()
	streetlight_heads.clear()
	traffic_manager = null
	crowd_manager = null

	_world_container = Node3D.new()
	_world_container.name = "GeneratedCityRoot"
	add_child(_world_container)

	var chunks_per_axis := p_plan.config.get_chunks_per_axis()
	var chunk_size := p_plan.config.chunk_size

	# Create N x N Chunk containers (128x128m each)
	var chunks_parent := Node3D.new()
	chunks_parent.name = "Chunks"
	_world_container.add_child(chunks_parent)

	for cz in range(chunks_per_axis):
		for cx in range(chunks_per_axis):
			var cc := Vector2i(cx, cz)
			var chunk_node := Node3D.new()
			chunk_node.name = "Chunk_%d_%d" % [cx, cz]
			chunks_parent.add_child(chunk_node)
			chunk_roots[cc] = chunk_node
			_chunk_centers[cc] = Vector2((float(cx) + 0.5) * chunk_size, (float(cz) + 0.5) * chunk_size)
			_chunk_has_tall[cc] = false

			var terrain_chunk := TerrainBuilder.build_terrain_chunk(p_plan.terrain, cx, cz, chunk_size, mats)
			chunk_node.add_child(terrain_chunk)

			var grass_mm := TerrainBuilder.build_chunk_grass(p_plan, cx, cz, chunk_size, mats)
			if grass_mm != null:
				chunk_node.add_child(grass_mm)

	# Creek water plane, coastal ocean surf plane & extended outer horizon terrain skirt
	var water := TerrainBuilder.build_creek_water(p_plan.terrain, mats)
	_world_container.add_child(water)
	if p_plan.terrain.beach_enabled:
		var ocean := TerrainBuilder.build_ocean_water(p_plan.terrain, mats)
		_world_container.add_child(ocean)
		var fish_schools := TerrainBuilder.build_underwater_fish_schools(p_plan)
		_world_container.add_child(fish_schools)
	var skirt := TerrainBuilder.build_horizon_skirt(p_plan.terrain, mats)
	_world_container.add_child(skirt)

	# Connected Road & Bridge Network (chunk-split for frustum culling + Decal Layer 2)
	var road_root := RoadBuilder.build_roads(p_plan.road_graph, p_plan.terrain, mats, p_plan.config.chunk_size)
	_world_container.add_child(road_root)

	# Terrain-conforming Park Walkways, Plazas & Creekside Greenways
	ParkWalkwayBuilder.build_walkways(p_plan.park_walkways, p_plan.terrain, p_plan.config, chunk_roots, mats)

	# Buildings placed inside their authoritative chunk container + 64m spatial hash for O(1) interior streaming
	for bp in p_plan.blueprints:
		var chunk_node: Node3D = chunk_roots.get(bp.chunk_coord, _world_container)
		var b_res := BuildingBuilder.build_building(bp, mats)
		var b_node: Node3D = b_res["node"]
		var door: InteractiveDoor = b_res["door"]
		chunk_node.add_child(b_node)
		buildings_by_id[bp.id] = {"bp": bp, "node": b_node}
		_index_building_in_grid(bp)
		if bp.floors >= 6 and _chunk_has_tall.has(bp.chunk_coord):
			_chunk_has_tall[bp.chunk_coord] = true
		_register_door(door)

	# Street props (batched per chunk) & chunked MultiMesh botanical tree/flora LODs placed inside their chunk container
	var tree_buckets: Dictionary = {}
	var flora_buckets: Dictionary = {}
	var prop_batches: Dictionary = {}
	for prop in p_plan.props:
		var cc: Vector2i = prop.get("chunk", Vector2i.ZERO)
		var chunk_node: Node3D = chunk_roots.get(cc, _world_container)
		var ptype: String = prop.get("type", "")
		if ptype == "street_tree" or ptype == "park_tree":
			var col_node := PropBuilder.build_tree_collider(prop)
			chunk_node.add_child(col_node)
			var sp: String = prop.get("species", "cedar_elm")
			var var_idx: int = int(prop.get("variant", 0))
			var scale_v: float = float(prop.get("scale", 1.0))
			var pos: Vector3 = prop.get("pos", Vector3.ZERO)
			var yaw: float = float(prop.get("yaw", 0.0))
			if ptype == "street_tree":
				if not prop_batches.has(cc):
					prop_batches[cc] = PropBuilder.create_chunk_batch()
				var bed_yaw: float = float(prop.get("bed_yaw", yaw))
				PropBuilder.emit_street_tree_bed(pos, bed_yaw, scale_v, prop_batches[cc], mats)
			var xform := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_v), pos)
			var c_map: Dictionary = tree_buckets.get(cc, {})
			var bucket_key := "%s_%d" % [sp, var_idx]
			var list: Array = c_map.get(bucket_key, [])
			list.append({"transform": xform, "species": sp, "variant": var_idx})
			c_map[bucket_key] = list
			tree_buckets[cc] = c_map
		elif ptype == "bush" or ptype == "flower_patch":
			var sp_f: String = prop.get("species", "boxwood" if ptype == "bush" else "bluebonnet")
			var var_f: int = int(prop.get("variant", 0))
			var scale_f: float = float(prop.get("scale", 1.0))
			var pos_f: Vector3 = prop.get("pos", Vector3.ZERO)
			var yaw_f: float = float(prop.get("yaw", 0.0))
			var xf_f := Transform3D(Basis(Vector3.UP, yaw_f).scaled(Vector3.ONE * scale_f), pos_f)
			var f_map: Dictionary = flora_buckets.get(cc, {})
			var f_key := "%s_%s_%d" % [ptype, sp_f, var_f]
			var flist: Array = f_map.get(f_key, [])
			flist.append({"transform": xf_f, "kind": ptype, "species": sp_f, "variant": var_f})
			f_map[f_key] = flist
			flora_buckets[cc] = f_map
		else:
			if not prop_batches.has(cc):
				prop_batches[cc] = PropBuilder.create_chunk_batch()
			var prop_node := PropBuilder.build_prop(prop, mats, prop_batches[cc])
			chunk_node.add_child(prop_node)
			if ptype == "planter_box":
				var pos_pb: Vector3 = prop.get("pos", Vector3.ZERO)
				var yaw_pb: float = float(prop.get("yaw", 0.0))
				var var_pb := posmod(int(round(pos_pb.x + pos_pb.z)), FloraGenerator.VARIANT_COUNT)
				var sp_pb := String(FloraGenerator.BUSH_SPECIES[posmod(int(round(pos_pb.x)), 2)])
				var xf_pb := Transform3D(Basis(Vector3.UP, yaw_pb).scaled(Vector3.ONE * 0.64), pos_pb + Vector3(0.0, 0.58, 0.0))
				var f_map_pb: Dictionary = flora_buckets.get(cc, {})
				var fk_pb := "bush_%s_%d" % [sp_pb, var_pb]
				var fl_pb: Array = f_map_pb.get(fk_pb, [])
				fl_pb.append({"transform": xf_pb, "kind": "bush", "species": sp_pb, "variant": var_pb})
				f_map_pb[fk_pb] = fl_pb
				var fl_sp := String(FloraGenerator.FLOWER_SPECIES[posmod(int(round(pos_pb.z)), FloraGenerator.FLOWER_SPECIES.size())])
				var fk_fl := "flower_patch_%s_%d" % [fl_sp, var_pb]
				var fl_fl: Array = f_map_pb.get(fk_fl, [])
				fl_fl.append({"transform": Transform3D(Basis(Vector3.UP, yaw_pb + 0.7).scaled(Vector3.ONE * 0.72), pos_pb + Vector3(0.16, 0.60, 0.14)), "kind": "flower_patch", "species": fl_sp, "variant": var_pb})
				f_map_pb[fk_fl] = fl_fl
				flora_buckets[cc] = f_map_pb
			elif ptype == "streetlight":
				var pos: Vector3 = prop.get("pos", Vector3.ZERO)
				var yaw: float = float(prop.get("yaw", 0.0))
				streetlight_heads.append(pos + (Basis(Vector3.UP, yaw) * Vector3(1.05, 5.10, 0.0)))

	for cc_p in prop_batches.keys():
		var chunk_node_p: Node3D = chunk_roots.get(cc_p, _world_container)
		PropBuilder.commit_chunk_batch(chunk_node_p, prop_batches[cc_p])

	for cc_key in tree_buckets.keys():
		var chunk_node: Node3D = chunk_roots.get(cc_key, _world_container)
		PropBuilder.build_chunk_tree_multimeshes(chunk_node, tree_buckets[cc_key], mats)

	for cc_fl in flora_buckets.keys():
		var chunk_node_fl: Node3D = chunk_roots.get(cc_fl, _world_container)
		PropBuilder.build_chunk_flora_multimeshes(chunk_node_fl, flora_buckets[cc_fl], mats)

	traffic_manager = TrafficManagerScript.new()
	traffic_manager.name = "TrafficManager"
	_world_container.add_child(traffic_manager)
	traffic_manager.setup(p_plan, mats)

	crowd_manager = CrowdManagerScript.new()
	crowd_manager.name = "CrowdManager"
	_world_container.add_child(crowd_manager)
	crowd_manager.set_traffic_manager(traffic_manager)
	crowd_manager.setup(p_plan, mats)

	var spawn_p := _find_safe_spawn(p_plan)
	_update_chunk_visibility(spawn_p, true)
	update_interior_streaming(spawn_p, 4)


func _register_door(door: InteractiveDoor) -> void:
	if door == null:
		return
	doors_by_id[door.door_id] = door
	if not door.door_toggled.is_connected(_on_door_toggled):
		door.door_toggled.connect(_on_door_toggled)
	if _opened_door_ids.has(door.door_id):
		door.set_open(true, true)


func _on_door_toggled(door_id: String, open_state: bool) -> void:
	if open_state:
		_opened_door_ids[door_id] = true
		var door: InteractiveDoor = doors_by_id.get(door_id, null)
		if door != null and not _active_interiors.has(door.building_id):
			ensure_interior_active(door.building_id)
	else:
		_opened_door_ids.erase(door_id)


func ensure_interior_active(building_id: String, immediate: bool = true) -> InteriorBlueprint:
	if _active_interiors.has(building_id):
		if immediate and _pending_floor_builds.has(building_id):
			var job: Dictionary = _pending_floor_builds[building_id]
			var rem: int = int(job["total_floors"]) - int(job["next_floor"])
			if rem > 0:
				var new_doors := InteriorBuilder.append_interior_floors(job["group"], job["bp"], job["ib"], mats, int(job["next_floor"]), int(job["total_floors"]))
				var idoors_existing: Array = _active_interiors[building_id]["doors"]
				for d in new_doors:
					idoors_existing.append(d)
					_register_door(d)
			_pending_floor_builds.erase(building_id)
		return interior_blueprints.get(building_id, null)
	if not buildings_by_id.has(building_id) or config == null:
		return null
	if mats == null:
		mats = MaterialLibrary.new()

	var entry: Dictionary = buildings_by_id[building_id]
	var bp: BuildingBlueprint = entry["bp"]
	var b_node: Node3D = entry["node"]
	var ib: InteriorBlueprint = interior_blueprints.get(building_id, null)
	if ib == null:
		if _pending_bp_tasks.has(building_id):
			var info: Dictionary = _pending_bp_tasks[building_id]
			var tid: int = int(info.get("task_id", -1))
			if not immediate and tid >= 0 and not WorkerThreadPool.is_task_completed(tid):
				return null
			if tid >= 0:
				WorkerThreadPool.wait_for_task_completion(tid)
			var res_arr: Array = info.get("result", [])
			if not res_arr.is_empty() and res_arr[0] != null:
				ib = res_arr[0]
				interior_blueprints[building_id] = ib
			_pending_bp_tasks.erase(building_id)
		if ib == null:
			if not immediate and bp.floors > 3:
				_queue_async_blueprint_prewarm(building_id, bp)
				return null
			ib = InteriorGenerator.generate(bp, config.world_seed)
			interior_blueprints[building_id] = ib

	var group: Node3D = null
	var idoors: Array = []
	var next_floor_pending := -1
	var total_floors := ib.floors.size()
	if _cached_interiors.has(building_id):
		var cached: Dictionary = _cached_interiors[building_id]
		group = cached["group"]
		idoors = cached["doors"]
		_cached_interiors.erase(building_id)
		_cached_interior_order.erase(building_id)
		var rprobe_existing := group.get_node_or_null("InteriorReflectionProbe") as ReflectionProbe
		if enable_interior_probes:
			if rprobe_existing == null:
				_attach_interior_probe(group, bp)
			else:
				rprobe_existing.visible = true
		elif rprobe_existing != null:
			rprobe_existing.visible = false
	else:
		var wall_mat: Material = b_node.get_meta("wall_mat", mats.get_wall_material(bp.wall_color, bp.style))
		var trim_mat: Material = b_node.get_meta("trim_mat", mats.dark_metal_mat)
		var init_floors := total_floors if (immediate or total_floors <= 3) else 2
		var built := InteriorBuilder.begin_interior_shell(bp, ib, wall_mat, trim_mat, mats, enable_interior_probes, init_floors)
		group = built["node"]
		idoors = built["doors"]
		var active_walls := group.get_node_or_null("ActiveWallsMesh") as MeshInstance3D
		if active_walls != null:
			active_walls.set_instance_shader_parameter("wall_color", bp.wall_color)
		if int(built["next_floor"]) < total_floors:
			next_floor_pending = int(built["next_floor"])

	BuildingBuilder.set_exterior_mode(b_node, false)
	b_node.add_child(group)
	b_node.set_meta("interior_active", true)

	_active_interiors[building_id] = {
		"group": group,
		"doors": idoors,
	}
	if next_floor_pending >= 0 and next_floor_pending < total_floors:
		_pending_floor_builds[building_id] = {
			"bp": bp,
			"ib": ib,
			"group": group,
			"next_floor": next_floor_pending,
			"total_floors": total_floors,
		}

	for d in idoors:
		_register_door(d as InteractiveDoor)
	return ib


func deactivate_interior(building_id: String) -> void:
	if not _active_interiors.has(building_id):
		return
	var was_incomplete := _pending_floor_builds.has(building_id)
	_pending_floor_builds.erase(building_id)
	var act: Dictionary = _active_interiors[building_id]
	var group: Node3D = act["group"]
	var idoors: Array = act["doors"]
	for d in idoors:
		var door := d as InteractiveDoor
		if door != null:
			if door.is_open:
				_opened_door_ids[door.door_id] = true
			doors_by_id.erase(door.door_id)
	if group != null and is_instance_valid(group):
		if group.get_parent() != null:
			group.get_parent().remove_child(group)
		if was_incomplete:
			# Do not store partially streamed interiors in LRU cache
			group.queue_free()
		else:
			# Keep any ReflectionProbe attached to the detached cached group instead of calling synchronous rprobe.free()
			_cached_interiors[building_id] = {
				"group": group,
				"doors": idoors,
			}
			_cached_interior_order.append(building_id)
			while _cached_interior_order.size() > INTERIOR_CACHE_LIMIT:
				var evict_id: String = _cached_interior_order.pop_front()
				if _cached_interiors.has(evict_id):
					var ev_g: Node3D = _cached_interiors[evict_id]["group"]
					if ev_g != null and is_instance_valid(ev_g):
						ev_g.queue_free()
					_cached_interiors.erase(evict_id)
	_active_interiors.erase(building_id)

	if buildings_by_id.has(building_id):
		var b_node: Node3D = buildings_by_id[building_id]["node"]
		if b_node != null:
			BuildingBuilder.set_exterior_mode(b_node, true)
			b_node.set_meta("interior_active", false)


static func _footprint_edge_dist(bp: BuildingBlueprint, pt_xz: Vector2) -> float:
	var dx := pt_xz.x - bp.center.x
	var dz := pt_xz.y - bp.center.y
	var cy := cos(bp.yaw)
	var sy := sin(bp.yaw)
	var lx := absf(dx * cy - dz * sy) - bp.width * 0.5
	var lz := absf(dx * sy + dz * cy) - bp.depth * 0.5
	return Vector2(maxf(0.0, lx), maxf(0.0, lz)).length()


func update_interior_streaming(viewer_pos: Vector3, max_activations_per_tick: int = 2) -> void:
	_update_interior_streaming_count(viewer_pos, max_activations_per_tick, true)


func _update_interior_streaming_count(viewer_pos: Vector3, max_activations_per_tick: int, immediate: bool = true) -> int:
	var viewer_xz := Vector2(viewer_pos.x, viewer_pos.z)
	var to_deactivate: Array[String] = []
	for b_id in _active_interiors.keys():
		if not buildings_by_id.has(b_id):
			continue
		var bp: BuildingBlueprint = buildings_by_id[b_id]["bp"]
		if _footprint_edge_dist(bp, viewer_xz) > INTERIOR_EDGE_DEACTIVATE_DIST:
			to_deactivate.append(String(b_id))
	for b_id in to_deactivate:
		deactivate_interior(b_id)

	var candidates: Array[Dictionary] = []
	for b_id in _get_nearby_building_ids(viewer_xz, INTERIOR_EDGE_ACTIVATE_DIST + 22.0):
		if _active_interiors.has(b_id):
			continue
		var bp: BuildingBlueprint = buildings_by_id[b_id]["bp"]
		if viewer_pos.y > bp.get_roof_top_y() + 18.0:
			continue
		var edge_d := _footprint_edge_dist(bp, viewer_xz)
		if edge_d <= INTERIOR_EDGE_ACTIVATE_DIST:
			candidates.append({"id": String(b_id), "dist": edge_d})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))

	var activated := 0
	for c in candidates:
		if activated >= max_activations_per_tick:
			break
		var res := ensure_interior_active(c["id"], immediate)
		if res != null:
			activated += 1
	return activated


func _prewarm_nearby_interior_blueprint(viewer_pos: Vector3) -> void:
	if config == null or buildings_by_id.is_empty():
		return
	var viewer_xz := Vector2(viewer_pos.x, viewer_pos.z)
	var best_id := ""
	var best_d := 42.0
	for b_id in _get_nearby_building_ids(viewer_xz, 52.0):
		if interior_blueprints.has(b_id) or _active_interiors.has(b_id) or _pending_bp_tasks.has(b_id):
			continue
		var bp: BuildingBlueprint = buildings_by_id[b_id]["bp"]
		if viewer_pos.y > bp.get_roof_top_y() + 18.0:
			continue
		var edge_d := _footprint_edge_dist(bp, viewer_xz)
		if edge_d < best_d:
			best_d = edge_d
			best_id = String(b_id)
	if best_id != "":
		var bp_warm: BuildingBlueprint = buildings_by_id[best_id]["bp"]
		_queue_async_blueprint_prewarm(best_id, bp_warm)


func set_chunk_cull_distance(dist_m: float, keep_skyline: bool = true) -> void:
	chunk_cull_distance = clampf(dist_m, 320.0, 2600.0)
	keep_skyline_chunks = keep_skyline
	var ref_p := viewer_node.global_position if viewer_node != null else (plan.spawn_position if plan != null else Vector3.ZERO)
	_update_chunk_visibility(ref_p, true)


func get_visible_chunk_count() -> int:
	return _visible_chunk_count


func _update_chunk_visibility(viewer_pos: Vector3, force: bool) -> void:
	if chunk_roots.is_empty():
		_visible_chunk_count = 0
		return
	if not force and viewer_pos.distance_squared_to(_last_chunk_cull_pos) < 576.0: # 24m hysteresis
		return
	_last_chunk_cull_pos = viewer_pos
	var vx := viewer_pos.x
	var vz := viewer_pos.z
	# Add half-chunk diagonal pad (~92m) so edge chunks never pop early
	var eff_r := chunk_cull_distance + 92.0
	var eff_r2 := eff_r * eff_r
	var sky_r := maxf(eff_r, 1280.0)
	var sky_r2 := sky_r * sky_r
	var vis_cnt := 0
	for cc in chunk_roots.keys():
		var cnode: Node3D = chunk_roots[cc]
		if cnode == null:
			continue
		var ctr: Vector2 = _chunk_centers.get(cc, Vector2.ZERO)
		var dx := ctr.x - vx
		var dz := ctr.y - vz
		var d2 := dx * dx + dz * dz
		var show := d2 <= eff_r2
		if not show and keep_skyline_chunks and bool(_chunk_has_tall.get(cc, false)):
			show = d2 <= sky_r2
		if cnode.visible != show:
			cnode.visible = show
		if show:
			vis_cnt += 1
	_visible_chunk_count = vis_cnt


func _index_building_in_grid(bp: BuildingBlueprint) -> void:
	var pad := maxf(bp.width, bp.depth) * 0.72 + 4.0
	var cx0 := int(floor((bp.center.x - pad) / BUILDING_GRID_CELL))
	var cx1 := int(floor((bp.center.x + pad) / BUILDING_GRID_CELL))
	var cz0 := int(floor((bp.center.y - pad) / BUILDING_GRID_CELL))
	var cz1 := int(floor((bp.center.y + pad) / BUILDING_GRID_CELL))
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var key := Vector2i(cx, cz)
			var arr: Array
			if _building_grid.has(key):
				arr = _building_grid[key]
			else:
				arr = []
				_building_grid[key] = arr
			arr.append(bp.id)


func _get_nearby_building_ids(pos_xz: Vector2, radius: float) -> Array[String]:
	var out: Array[String] = []
	if _building_grid.is_empty():
		return out
	var seen := {}
	var r_cells := maxi(1, int(ceil(radius / BUILDING_GRID_CELL)))
	var cx0 := int(floor(pos_xz.x / BUILDING_GRID_CELL))
	var cz0 := int(floor(pos_xz.y / BUILDING_GRID_CELL))
	for oz in range(-r_cells, r_cells + 1):
		for ox in range(-r_cells, r_cells + 1):
			var key := Vector2i(cx0 + ox, cz0 + oz)
			if not _building_grid.has(key):
				continue
			for b_id in _building_grid[key]:
				if not seen.has(b_id):
					seen[b_id] = true
					out.append(String(b_id))
	return out


func _attach_interior_probe(group: Node3D, bp: BuildingBlueprint) -> void:
	var wall_h := bp.get_total_wall_height()
	var rprobe := ReflectionProbe.new()
	rprobe.name = "InteriorReflectionProbe"
	rprobe.interior = true
	rprobe.box_projection = true
	rprobe.update_mode = ReflectionProbe.UPDATE_ONCE
	rprobe.size = Vector3(bp.width + 0.6, wall_h + 0.6, bp.depth + 0.6)
	rprobe.position = Vector3(0.0, wall_h * 0.5, 0.0)
	rprobe.max_distance = maxf(bp.width, bp.depth) + 8.0
	rprobe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	rprobe.ambient_color = Color(0.96, 0.92, 0.85)
	rprobe.ambient_color_energy = 0.22
	group.add_child(rprobe)


func get_active_interior_count() -> int:
	return _active_interiors.size()


func get_opened_door_ids() -> Array[String]:
	var ids: Array[String] = []
	for k in _opened_door_ids.keys():
		ids.append(String(k))
	ids.sort()
	return ids


func apply_changed_world_state(state: Dictionary, instant: bool = true) -> void:
	var changed: Dictionary = state.get("changed_world_state", {})
	var opened_list: Array = changed.get("opened_doors", [])
	_opened_door_ids.clear()
	for d_id in opened_list:
		_opened_door_ids[str(d_id)] = true

	for door_id in doors_by_id.keys():
		var door: InteractiveDoor = doors_by_id[door_id]
		if door != null:
			door.set_open(_opened_door_ids.has(door_id), instant)


func save_to_disk(player_pos: Vector3, player_yaw: float, path: String = PersistenceManager.DEFAULT_SAVE_PATH, atmosphere_state: Dictionary = {}) -> bool:
	if config == null:
		return false
	return PersistenceManager.save_state(config, doors_by_id, player_pos, player_yaw, path, get_opened_door_ids(), atmosphere_state)


func load_from_disk(path: String = PersistenceManager.DEFAULT_SAVE_PATH) -> Dictionary:
	var data := PersistenceManager.load_state(path)
	if data.is_empty():
		return {}
	var cfg := CityConfig.from_dict(data.get("city_config", {}))
	build_from_seed(cfg.world_seed, cfg)
	apply_changed_world_state(data, true)
	return data


static func _find_safe_spawn(p_plan: CityPlan) -> Vector3:
	# Prefer spawning in front of the first downtown/commercial building's entrance approach!
	for bp in p_plan.blueprints:
		if bp.district_zone == "downtown_mixed" or bp.district_zone == "commercial_corridor":
			var p := bp.get_approach_world_pos()
			return Vector3(p.x, bp.sidewalk_y + 0.02, p.z)
	if not p_plan.blueprints.is_empty():
		var bp0 := p_plan.blueprints[0]
		var p0 := bp0.get_approach_world_pos()
		return Vector3(p0.x, bp0.sidewalk_y + 0.02, p0.z)
	var cx := p_plan.config.world_size * 0.5
	var cz := p_plan.config.world_size * 0.5
	return Vector3(cx, p_plan.terrain.sample_height(cx, cz) + 0.5, cz)
