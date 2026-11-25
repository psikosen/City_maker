extends Node3D

const PerformanceControllerScript := preload("res://src/city_world/player/performance_controller.gd")

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun_light: DirectionalLight3D = $SunLight
@onready var city_world: CityWorld = $CityWorld
@onready var player: PlayerController = $PlayerController
@onready var hud: DebugHUD = $DebugHUD

var atmosphere: AtmosphereController = null
var performance: CanvasLayer = null

var _bench_active: bool = false
var _bench_target_samples: int = 240
var _bench_warmup_left: int = 18
var _bench_samples: PackedFloat64Array = PackedFloat64Array()
var _bench_t: float = 0.0
var _bench_center: Vector2 = Vector2.ZERO
var _bench_base_y: float = 12.0
var _bench_peak_interiors: int = 0
var _bench_peak_draws: int = 0


func _ready() -> void:
	atmosphere = get_node_or_null("AtmosphereController") as AtmosphereController
	if atmosphere == null:
		atmosphere = AtmosphereController.new()
		atmosphere.name = "AtmosphereController"
		add_child(atmosphere)

	player.city_world = city_world
	player.atmosphere = atmosphere
	hud.city_world = city_world
	hud.player = player
	hud.atmosphere = atmosphere
	player.status_message.connect(hud.show_status)

	var seed_override := _parse_seed_arg()
	if seed_override != -1:
		city_world.build_from_seed(seed_override)
	elif city_world.plan == null:
		city_world.build_from_seed(city_world.default_seed)

	atmosphere.setup(world_env, sun_light, city_world, player)

	performance = PerformanceControllerScript.new()
	performance.name = "PerformanceController"
	add_child(performance)
	hud.performance = performance
	performance.status_message.connect(hud.show_status)
	var is_auto_run := _has_flag("--benchmark") or OS.has_feature("movie") or DisplayServer.get_name().to_lower().contains("headless")
	performance.setup(city_world, atmosphere, player, not is_auto_run)

	var q_arg := _parse_str_arg("--quality=")
	if not q_arg.is_empty():
		performance.apply_preset(q_arg, false)
	var rs_arg := _parse_float_arg("--render-scale=", -1.0)
	if rs_arg > 0.0:
		performance.render_scale = clampf(rs_arg, 0.50, 1.00)
		performance.apply_all_settings(false)
	var fsr_arg := _parse_str_arg("--fsr2=").to_lower()
	if fsr_arg == "on" or fsr_arg == "1" or fsr_arg == "true":
		performance.upscaler_mode = 1
		performance.apply_all_settings(false)
	elif fsr_arg == "off" or fsr_arg == "0" or fsr_arg == "false":
		performance.upscaler_mode = 0
		performance.apply_all_settings(false)
	var vs_arg := _parse_str_arg("--vsync=").to_lower()
	if vs_arg == "off" or vs_arg == "0" or vs_arg == "false":
		performance.vsync_enabled = false
		performance.apply_all_settings(false)
	elif vs_arg == "on" or vs_arg == "1" or vs_arg == "true":
		performance.vsync_enabled = true
		performance.apply_all_settings(false)
	var af_arg := _parse_str_arg("--auto-fps=").to_lower()
	if af_arg == "on" or af_arg == "1" or af_arg == "true":
		var tf := int(_parse_float_arg("--target-fps=", 60.0))
		performance.target_fps = clampi(tf, 24, 120)
		performance.set_auto_fps_enabled(true, false)
	elif af_arg == "off" or af_arg == "0" or af_arg == "false":
		performance.set_auto_fps_enabled(false, false)
	if _parse_str_arg("--perf-menu=").to_lower() in ["on", "1", "true"]:
		performance.set_menu_open(true)

	var time_override := _parse_float_arg("--time=", -1.0)
	if time_override >= 0.0:
		atmosphere.set_time_of_day(time_override)
	var weather_override := _parse_str_arg("--weather=")
	if not weather_override.is_empty():
		atmosphere.set_weather(weather_override, true)
	city_world.city_rebuilt.connect(func(_p: CityPlan) -> void: atmosphere.step_simulation(0.0))

	var p := city_world.plan
	if p != null:
		var cam_mode := _parse_cam_arg()
		if _has_flag("--benchmark"):
			_bench_active = true
			_bench_target_samples = maxi(60, int(_parse_float_arg("--benchmark-frames=", 240.0)))
			var dt_b: Vector2 = p.district_centers.get("downtown_mixed", Vector2(p.config.world_size * 0.5, p.config.world_size * 0.5))
			_bench_center = dt_b
			_bench_base_y = p.terrain.sample_height(dt_b.x, dt_b.y)
			player.set_fly_mode(true)
			player.place_at(Vector3(dt_b.x, _bench_base_y + 18.0, dt_b.y + 42.0), 0.0, -0.18)
		elif cam_mode == "overview":
			player.set_fly_mode(true)
			var dt_c: Vector2 = p.district_centers.get("downtown_mixed", Vector2(p.config.world_size * 0.5, p.config.world_size * 0.5))
			var cam_pos := Vector3(clampf(dt_c.x - 310.0, 45.0, p.config.world_size - 45.0), 275.0, clampf(dt_c.y + 330.0, 45.0, p.config.world_size - 45.0))
			var dir_xz := Vector2(dt_c.x - cam_pos.x, dt_c.y - cam_pos.z)
			var look_yaw := atan2(-dir_xz.x, -dir_xz.y)
			player.place_at(cam_pos, look_yaw, -0.46)
		elif cam_mode == "bridge":
			player.set_fly_mode(true)
			var bridge_pos := _find_bridge_view(p)
			player.place_at(bridge_pos["pos"], bridge_pos["yaw"], -0.30)
		elif cam_mode == "street":
			var street_pose := _find_street_view(p)
			player.place_at(street_pose["pos"], street_pose["yaw"], float(street_pose.get("pitch", 0.04)))
		elif cam_mode == "traffic":
			player.set_fly_mode(true)
			var tr_pose := _find_traffic_junction_view(p, false)
			player.place_at(tr_pose["pos"], tr_pose["yaw"], float(tr_pose.get("pitch", -0.26)))
		elif cam_mode == "crosswalk":
			player.set_fly_mode(true)
			var cw_pose := _find_traffic_junction_view(p, true)
			player.place_at(cw_pose["pos"], cw_pose["yaw"], float(cw_pose.get("pitch", -0.06)))
		elif cam_mode == "interior":
			var int_pose := _find_interior_view(p)
			player.place_at(int_pose["pos"], int_pose["yaw"], -0.06)
		elif cam_mode == "stair":
			var st_pose := _find_stair_view(p)
			player.place_at(st_pose["pos"], st_pose["yaw"], 0.14)
		elif cam_mode == "park":
			player.set_fly_mode(true)
			var pk_pose := _find_park_view(p)
			player.place_at(pk_pose["pos"], pk_pose["yaw"], float(pk_pose.get("pitch", -0.22)))
		elif cam_mode == "creek":
			player.set_fly_mode(true)
			var ck_pose := _find_creek_view(p)
			player.place_at(ck_pose["pos"], ck_pose["yaw"], float(ck_pose.get("pitch", -0.10)))
		elif cam_mode == "beach":
			player.set_fly_mode(true)
			var bh_pose := _find_beach_view(p)
			player.place_at(bh_pose["pos"], bh_pose["yaw"], float(bh_pose.get("pitch", -0.18)))
		elif cam_mode == "beach_house":
			player.set_fly_mode(true)
			var bhs_pose := _find_beach_house_view(p)
			player.place_at(bhs_pose["pos"], bhs_pose["yaw"], float(bhs_pose.get("pitch", 0.04)))
		elif cam_mode == "pier":
			player.set_fly_mode(true)
			var pr_pose := _find_pier_view(p)
			player.place_at(pr_pose["pos"], pr_pose["yaw"], float(pr_pose.get("pitch", -0.12)))
		elif cam_mode == "underwater":
			player.set_fly_mode(true)
			var uw_pose := _find_underwater_view(p)
			player.place_at(uw_pose["pos"], uw_pose["yaw"], float(uw_pose.get("pitch", 0.06)))
		elif cam_mode == "car_close":
			player.set_fly_mode(true)
			var cc_pose := _find_car_close_view(p)
			player.place_at(cc_pose["pos"], cc_pose["yaw"], float(cc_pose.get("pitch", -0.12)))
		elif cam_mode in ["church", "city_hall", "police", "fire_station", "hospital", "school"]:
			player.set_fly_mode(true)
			var ext_arch := "municipal_hall" if cam_mode == "city_hall" else ("police_station" if cam_mode == "police" else cam_mode)
			var b_pose := _find_archetype_exterior_view(p, ext_arch)
			player.place_at(b_pose["pos"], b_pose["yaw"], float(b_pose.get("pitch", 0.08)))
		elif cam_mode == "footbridge":
			player.set_fly_mode(true)
			var fb_pose := _find_footbridge_view(p)
			player.place_at(fb_pose["pos"], fb_pose["yaw"], float(fb_pose.get("pitch", -0.14)))
		elif cam_mode == "fountain":
			player.set_fly_mode(true)
			var fn_pose := _find_prop_view(p, "park_fountain", Vector3(6.5, 2.8, 7.2), 1.35)
			player.place_at(fn_pose["pos"], fn_pose["yaw"], float(fn_pose.get("pitch", -0.16)))
		elif cam_mode == "sport_court":
			player.set_fly_mode(true)
			var sc_pose := _find_prop_view(p, "sport_court", Vector3(11.0, 6.2, 13.5), 1.2)
			player.place_at(sc_pose["pos"], sc_pose["yaw"], float(sc_pose.get("pitch", -0.26)))
		elif cam_mode == "cafe_street":
			player.set_fly_mode(true)
			var cs_pose := _find_prop_view(p, "cafe_seating", Vector3(4.5, 2.2, 5.2), 0.9)
			player.place_at(cs_pose["pos"], cs_pose["yaw"], float(cs_pose.get("pitch", -0.14)))
		elif cam_mode == "horizon":
			player.set_fly_mode(true)
			var hz_pose := _find_horizon_view(p)
			player.place_at(hz_pose["pos"], hz_pose["yaw"], float(hz_pose.get("pitch", -0.10)))
		elif cam_mode == "elevator":
			var el_pose := _find_elevator_view(p)
			player.place_at(el_pose["pos"], el_pose["yaw"], float(el_pose.get("pitch", -0.04)))
		elif cam_mode == "hospital_inside":
			var hi_pose := _find_venue_interior_view(p, "hospital")
			player.place_at(hi_pose["pos"], hi_pose["yaw"], float(hi_pose.get("pitch", -0.08)))
		elif cam_mode == "school_inside":
			var si_pose := _find_venue_interior_view(p, "school")
			player.place_at(si_pose["pos"], si_pose["yaw"], float(si_pose.get("pitch", -0.08)))
		elif cam_mode == "church_inside":
			var ci_pose := _find_venue_interior_view(p, "church")
			player.place_at(ci_pose["pos"], ci_pose["yaw"], float(ci_pose.get("pitch", -0.05)))
		elif cam_mode == "city_hall_inside":
			var chi_pose := _find_venue_interior_view(p, "city_hall")
			player.place_at(chi_pose["pos"], chi_pose["yaw"], float(chi_pose.get("pitch", -0.10)))
		elif cam_mode == "police_inside":
			var pi_pose := _find_venue_interior_view(p, "police_station")
			player.place_at(pi_pose["pos"], pi_pose["yaw"], float(pi_pose.get("pitch", -0.08)))
		elif cam_mode == "fire_inside":
			var fi_pose := _find_venue_interior_view(p, "fire_station")
			player.place_at(fi_pose["pos"], fi_pose["yaw"], float(fi_pose.get("pitch", -0.10)))
		elif cam_mode in ["gym", "cafe", "grocery", "bookstore", "clinic", "restaurant", "bank", "cinema", "gallery", "bike_shop", "ev_showroom", "hardware", "music_studio", "tech_office", "library", "post_office"]:
			var v_pose := _find_venue_interior_view(p, cam_mode)
			player.place_at(v_pose["pos"], v_pose["yaw"], float(v_pose.get("pitch", -0.10)))
		elif _parse_str_arg("--cam-pos=") != "":
			player.set_fly_mode(true)
			var ps := _parse_str_arg("--cam-pos=").split(",")
			var ls := _parse_str_arg("--cam-look=").split(",")
			var cpos := Vector3(float(ps[0]), float(ps[1]), float(ps[2])) if ps.size() >= 3 else p.spawn_position
			var lpos := Vector3(float(ls[0]), float(ls[1]), float(ls[2])) if ls.size() >= 3 else (cpos + Vector3(0, 0, -5))
			var dv := lpos - cpos
			var hdist := maxf(0.01, Vector2(dv.x, dv.z).length())
			player.place_at(cpos, atan2(-dv.x, -dv.z), clampf(atan2(dv.y, hdist), -1.2, 1.2))
		else:
			player.place_at(p.spawn_position, p.spawn_yaw)
		city_world.update_interior_streaming(player.global_position, 16)
		city_world._update_chunk_visibility(player.global_position, true)
		atmosphere.step_simulation(0.0)
		# Pre-sync scheduled NPCs & multi-lane traffic immediately to the launch hour/weather & camera position
		if city_world.crowd_manager != null and city_world.traffic_manager != null:
			var eff_precip := clampf(maxf(atmosphere.weather_rain, atmosphere.weather_snow * 0.90), 0.0, 1.0)
			var eff_traction := clampf(maxf(atmosphere.weather_wetness, maxf(atmosphere.weather_snow_depth * 0.92, atmosphere.weather_slush * 0.85)), 0.0, 1.0)
			for _warm in range(24):
				city_world.crowd_manager.step(0.04, player.global_position, atmosphere.night_factor, atmosphere.time_of_day_hour, eff_precip)
				city_world.traffic_manager.step(0.04, player.global_position, atmosphere.night_factor, atmosphere.time_of_day_hour, eff_precip, eff_traction)
		hud.show_status("Seed %d • %s %s (%s) • %d buildings" % [
			p.config.world_seed,
			atmosphere.get_time_string(),
			atmosphere.get_phase_name(),
			atmosphere.get_weather_label(),
			p.blueprints.size(),
		])


func _process(delta: float) -> void:
	if not _bench_active:
		return
	_bench_t += maxf(delta, 0.001)
	# Sweeping low-altitude downtown fly-through that crosses buildings to exercise streaming & GPU load.
	var ang := _bench_t * 0.52
	var radius := 58.0 + sin(_bench_t * 0.85) * 24.0
	var px := _bench_center.x + cos(ang) * radius
	var pz := _bench_center.y + sin(ang) * radius
	var py := _bench_base_y + 11.5 + sin(_bench_t * 1.1) * 7.5
	var next_px := _bench_center.x + cos(ang + 0.12) * radius
	var next_pz := _bench_center.y + sin(ang + 0.12) * radius
	var fwd := Vector2(next_px - px, next_pz - pz).normalized()
	player.place_at(Vector3(px, py, pz), atan2(-fwd.x, -fwd.y), -0.14)

	var active_int := city_world.get_active_interior_count()
	_bench_peak_interiors = maxi(_bench_peak_interiors, active_int)
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_bench_peak_draws = maxi(_bench_peak_draws, draws)

	if _bench_warmup_left > 0:
		_bench_warmup_left -= 1
		return
	var dt_ms := delta * 1000.0
	if dt_ms > 40.0:
		print("[BENCH_SPIKE] frame=%d ms=%.2f active_interiors=%d draws=%d" % [_bench_samples.size(), dt_ms, active_int, draws])
	_bench_samples.append(dt_ms)
	if _bench_samples.size() >= _bench_target_samples:
		_finish_benchmark()


func _finish_benchmark() -> void:
	_bench_active = false
	var arr: Array[float] = []
	var sum_ms := 0.0
	var max_ms := 0.0
	for ms in _bench_samples:
		arr.append(ms)
		sum_ms += ms
		max_ms = maxf(max_ms, ms)
	arr.sort()
	var n := arr.size()
	var avg_ms := sum_ms / maxf(1.0, float(n))
	var p95_ms := arr[mini(n - 1, int(float(n) * 0.95))]
	var avg_fps := 1000.0 / maxf(0.1, avg_ms)
	var p5_low_fps := 1000.0 / maxf(0.1, p95_ms)
	print("[BENCH] samples=%d avg_fps=%.2f p5_low_fps=%.2f avg_ms=%.2f p95_ms=%.2f max_ms=%.2f peak_active_interiors=%d peak_draw_calls=%d" % [
		n, avg_fps, p5_low_fps, avg_ms, p95_ms, max_ms, _bench_peak_interiors, _bench_peak_draws
	])
	get_tree().quit(0)


func _has_flag(flag_name: String) -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == flag_name or arg.begins_with(flag_name + "="):
			return true
	return false


func _parse_seed_arg() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			return int(arg.substr(7))
	return -1


func _parse_cam_arg() -> String:
	return _parse_str_arg("--cam=")


func _parse_str_arg(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return ""


func _parse_float_arg(prefix: String, default_val: float) -> float:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return float(arg.substr(prefix.length()))
	return default_val


func _find_bridge_view(p: CityPlan) -> Dictionary:
	for e in p.road_graph.edges:
		if e.is_bridge:
			var mid := p.road_graph.sample_edge_point_3d(e, (e.bridge_start_t + e.bridge_end_t) * 0.5)
			return {"pos": mid + Vector3(-28.0, 16.0, 32.0), "yaw": -0.70}
	var hs := p.config.world_size * 0.5
	return {"pos": Vector3(hs, 45.0, hs), "yaw": 0.0}


func _find_street_view(p: CityPlan) -> Dictionary:
	var dt_c: Vector2 = p.district_centers.get("downtown_mixed", Vector2(p.config.world_size * 0.5, p.config.world_size * 0.5))
	var best_bp: BuildingBlueprint = null
	var best_bp_d := INF
	for bp in p.blueprints:
		if bp.has_signage and bp.sign_label != "" and bp.floors >= 3:
			var d := bp.center.distance_to(dt_c)
			var bonus := 0.0 if bp.archetype == "mixed_use_midrise" else 12.0
			if bp.has_blade_sign:
				bonus -= 8.0
			if d + bonus < best_bp_d:
				best_bp_d = d + bonus
				best_bp = bp
	if best_bp != null:
		var cam_xz := best_bp.local_to_world_2d(Vector2(-9.5, best_bp.depth * 0.5 + 9.0))
		var target_xz := best_bp.local_to_world_2d(Vector2(2.5, best_bp.depth * 0.15))
		var dir2 := (target_xz - cam_xz).normalized()
		var cam_y := maxf(best_bp.sidewalk_y, p.terrain.sample_height(cam_xz.x, cam_xz.y) + 0.15)
		return {"pos": Vector3(cam_xz.x, cam_y, cam_xz.y), "yaw": atan2(-dir2.x, -dir2.y), "pitch": 0.07}

	var best_bin: Dictionary = {}
	var best_d := INF
	for pr in p.props:
		if String(pr.get("type", "")) == "trashcan":
			var pos3: Vector3 = pr["pos"]
			var d := Vector2(pos3.x, pos3.z).distance_to(dt_c)
			if d < best_d:
				best_d = d
				best_bin = pr
	if not best_bin.is_empty():
		var bin_pos: Vector3 = best_bin["pos"]
		var to_dt := (dt_c - Vector2(bin_pos.x, bin_pos.z)).normalized()
		var cam_xz := Vector2(bin_pos.x, bin_pos.z) - to_dt * 5.2 + Vector2(-to_dt.y, to_dt.x) * 1.4
		var cam_y := p.terrain.sample_height(cam_xz.x, cam_xz.y) + 0.15
		return {"pos": Vector3(cam_xz.x, maxf(bin_pos.y, cam_y), cam_xz.y), "yaw": atan2(-to_dt.x, -to_dt.y), "pitch": -0.02}
	return {"pos": p.spawn_position, "yaw": 0.0, "pitch": 0.0}


func _find_interior_view(p: CityPlan) -> Dictionary:
	for bp in p.blueprints:
		if bp.door_id != "" and bp.floors >= 3 and bp.archetype in ["modern_office", "mixed_use_midrise", "skyscraper_tower", "apartment_midrise"]:
			var ib := InteriorGenerator.generate(bp, p.config.world_seed)
			var cam_local := Vector2(ib.inner_max.x - 1.1, ib.inner_max.y - 1.0)
			var target_local := Vector2(ib.inner_min.x + 2.8, ib.inner_min.y + 3.8)
			if not ib.stairs.is_empty():
				var f1_p0: Vector3 = ib.stairs[0]["flight1_p0"]
				target_local = Vector2(f1_p0.x + 1.5, f1_p0.z - 0.6)
			var dir_w := bp.local_to_world_2d(target_local) - bp.local_to_world_2d(cam_local)
			var yaw_w := atan2(-dir_w.x, -dir_w.y)
			var pos3 := bp.local_to_world_3d(Vector3(cam_local.x, 0.18, cam_local.y))
			return {"pos": pos3, "yaw": yaw_w}
	return {"pos": p.spawn_position, "yaw": 0.0}


func _find_stair_view(p: CityPlan) -> Dictionary:
	for bp in p.blueprints:
		if bp.door_id != "" and bp.floors >= 3 and bp.archetype in ["modern_office", "mixed_use_midrise", "skyscraper_tower", "apartment_midrise"]:
			var ib := InteriorGenerator.generate(bp, p.config.world_seed)
			if ib.stairs.is_empty():
				continue
			var st0: Dictionary = ib.stairs[0]
			var p0: Vector3 = st0["flight1_p0"]
			var lp: Vector3 = st0["landing_pos"]
			var cam_local := Vector2(lp.x + 0.5, minf(ib.inner_max.y - 0.9, p0.z + 2.35))
			var target_local := Vector2(lp.x, lp.z + 0.5)
			var dir_w := bp.local_to_world_2d(target_local) - bp.local_to_world_2d(cam_local)
			var yaw_w := atan2(-dir_w.x, -dir_w.y)
			var pos3 := bp.local_to_world_3d(Vector3(cam_local.x, 0.12, cam_local.y))
			return {"pos": pos3, "yaw": yaw_w}
	return {"pos": p.spawn_position, "yaw": 0.0}


func _find_venue_interior_view(p: CityPlan, venue: String) -> Dictionary:
	var domain_kinds := {
		"gym": ["treadmill", "squat_rack", "weight_bench", "dumbbell_rack", "exercise_bike", "locker_bank"],
		"cafe": ["espresso_bar", "cafe_table", "bakery_rack"],
		"grocery": ["checkout_lane", "grocery_gondola", "cooler_case"],
		"bookstore": ["bookstore_shelf"],
		"clinic": ["exam_table", "med_cabinet"],
		"restaurant": ["dining_booth", "kitchen_pass", "dining_table"],
		"bank": ["teller_counter", "atm_kiosk", "safe_vault_cabinet"],
		"tech_office": ["server_rack", "studio_console"],
		"music_studio": ["studio_console", "server_rack"],
		"gallery": ["gallery_pedestal"],
		"cinema": ["cinema_screen", "cinema_seats"],
		"bike_shop": ["bike_display_stand", "workbench"],
		"hardware": ["workbench", "grocery_gondola"],
		"ev_showroom": ["ev_totem"],
		"church": ["church_pew", "altar_table", "pulpit"],
		"city_hall": ["judge_bench", "court_bench", "pulpit"],
		"police_station": ["holding_cell", "safe_vault_cabinet", "workstation_desk"],
		"fire_station": ["fire_truck", "workbench"],
		"library": ["bookstore_shelf"],
		"post_office": ["teller_counter", "locker_bank"],
	}
	var target_kinds: Array = domain_kinds.get(venue, [])
	var best_bp: BuildingBlueprint = null
	var best_ib: InteriorBlueprint = null
	var best_score := -1
	for bp in p.blueprints:
		if bp.venue_type == venue and bp.door_id != "":
			var ib := InteriorGenerator.generate(bp, p.config.world_seed)
			if ib.floors.is_empty():
				continue
			for f_check in ib.floors:
				var score := 0
				for it in f_check.get("furniture", []):
					if String(it.get("kind", "")) in target_kinds:
						score += 1
				if score > best_score:
					best_score = score
					best_bp = bp
					best_ib = ib
	if best_bp != null and best_ib != null:
		# For church/city_hall/fire_station ground floor, place camera cleanly inside doorway aisle looking at main focal feature
		if venue in ["church", "city_hall", "fire_station"]:
			var fl0: Dictionary = best_ib.floors[0]
			var target_local := Vector2(0.0, best_ib.inner_min.y + 1.6)
			for it in fl0.get("furniture", []):
				var ik := String(it.get("kind", ""))
				if ik in ["altar_table", "judge_bench", "fire_truck"]:
					var ip: Vector3 = it["pos"]
					target_local = Vector2(ip.x, ip.z)
					break
			var cam_local := Vector2(best_bp.door_local_x, best_ib.inner_max.y - 1.05)
			if venue == "fire_station":
				cam_local = Vector2(best_ib.inner_min.x + 1.4, best_ib.inner_max.y - 1.15)
			var dir_w := best_bp.local_to_world_2d(target_local) - best_bp.local_to_world_2d(cam_local)
			return {"pos": best_bp.local_to_world_3d(Vector3(cam_local.x, 0.45, cam_local.y)), "yaw": atan2(-dir_w.x, -dir_w.y), "pitch": -0.06}

		# Pick best floor (prefer holding_cell floor for police_station so jails & vaults are prominently framed)
		var chosen_fl: Dictionary = best_ib.floors[0]
		var best_fl_score := -1
		for f_item in best_ib.floors:
			var sc := 0
			for it in f_item.get("furniture", []):
				var ik := String(it.get("kind", ""))
				if ik in target_kinds:
					sc += 10 if (venue == "police_station" and ik == "holding_cell") else 1
			if sc > best_fl_score:
				best_fl_score = sc
				chosen_fl = f_item
		var fy := float(chosen_fl.get("base_y", 0.0))
		if venue == "police_station":
			for it in chosen_fl.get("furniture", []):
				if String(it.get("kind", "")) == "holding_cell":
					var cp: Vector3 = it["pos"]
					var target_pt := Vector2(cp.x, cp.z)
					var cam_pt := Vector2(best_ib.inner_max.x - 1.0, best_ib.inner_max.y - 1.0)
					for rm in chosen_fl.get("rooms", []):
						var rr: Rect2 = rm["rect"]
						if rr.grow(0.4).has_point(target_pt):
							var c0 := Vector2(rr.position.x + 0.9, rr.position.y + 0.9)
							var c1 := Vector2(rr.end.x - 0.9, rr.end.y - 0.9)
							var c2 := Vector2(rr.position.x + 0.9, rr.end.y - 0.9)
							var c3 := Vector2(rr.end.x - 0.9, rr.position.y + 0.9)
							cam_pt = c0
							for cand_c in [c1, c2, c3]:
								if cand_c.distance_to(target_pt) > cam_pt.distance_to(target_pt):
									cam_pt = cand_c
							break
					var dir_p := best_bp.local_to_world_2d(target_pt) - best_bp.local_to_world_2d(cam_pt)
					return {"pos": best_bp.local_to_world_3d(Vector3(cam_pt.x, fy + 0.35, cam_pt.y)), "yaw": atan2(-dir_p.x, -dir_p.y), "pitch": -0.06}
		var target_sum := Vector2.ZERO
		var target_n := 0
		for it in chosen_fl.get("furniture", []):
			if String(it.get("kind", "")) in target_kinds:
				var ip: Vector3 = it["pos"]
				target_sum += Vector2(ip.x, ip.z)
				target_n += 1
		var target_local := target_sum / maxf(1.0, float(target_n)) if target_n > 0 else Vector2(0.0, 0.0)
		var cam_local := Vector2(best_ib.inner_max.x - 1.15, best_ib.inner_max.y - 1.15)
		if cam_local.distance_to(target_local) < 2.4:
			cam_local = Vector2(best_ib.inner_min.x + 1.15, best_ib.inner_max.y - 1.15)
		var dir_w := best_bp.local_to_world_2d(target_local) - best_bp.local_to_world_2d(cam_local)
		var yaw_w := atan2(-dir_w.x, -dir_w.y)
		var pos3 := best_bp.local_to_world_3d(Vector3(cam_local.x, fy + 0.30, cam_local.y))
		return {"pos": pos3, "yaw": yaw_w, "pitch": -0.10}
	return _find_interior_view(p)


func _find_park_view(p: CityPlan) -> Dictionary:
	var best_plaza: Vector2 = Vector2.ZERO
	var found_plaza := false
	for pw in p.park_walkways:
		if String(pw.get("kind", "")) == "plaza" and bool(pw.get("has_gazebo", false)):
			best_plaza = pw["center"]
			found_plaza = true
			break
	if not found_plaza:
		for pw in p.park_walkways:
			var pts: Array = pw.get("points", [])
			if pts.size() >= 2:
				best_plaza = pts[int(pts.size() / 2)]
				found_plaza = true
				break
	if found_plaza:
		var look_at := Vector3(best_plaza.x, p.terrain.sample_height(best_plaza.x, best_plaza.y) + 1.6, best_plaza.y)
		var cam_xz := best_plaza + Vector2(18.0, 22.0)
		var cam_y := maxf(look_at.y + 8.5, p.terrain.sample_height(cam_xz.x, cam_xz.y) + 7.5)
		var d := Vector2(look_at.x - cam_xz.x, look_at.z - cam_xz.y)
		return {"pos": Vector3(cam_xz.x, cam_y, cam_xz.y), "yaw": atan2(-d.x, -d.y), "pitch": -0.26}
	return _find_bridge_view(p)


func _find_creek_view(p: CityPlan) -> Dictionary:
	var poly := p.terrain.creek_polyline
	if poly.size() >= 6:
		var idx := clampi(int(float(poly.size()) * 0.56), 2, poly.size() - 4)
		var cpt := poly[idx]
		var ahead := poly[maxi(0, idx - 3)]
		var cam_xz := cpt + Vector2(-(p.terrain.creek_half_width + 6.0), 26.0)
		var d := ahead - cam_xz
		return {
			"pos": Vector3(cam_xz.x, p.terrain.water_level + 8.5, cam_xz.y),
			"yaw": atan2(-d.x, -d.y),
			"pitch": -0.06,
		}
	return _find_bridge_view(p)


func _find_archetype_exterior_view(p: CityPlan, arch: String) -> Dictionary:
	var best_fallback := {}
	var tree_xzs: Array[Vector2] = []
	for pr in p.props:
		if String(pr.get("type", "")) in ["street_tree", "park_tree", "tree"]:
			var tp: Vector3 = pr["pos"]
			tree_xzs.append(Vector2(tp.x, tp.z))
	var offsets := [
		Vector2(4.5, 16.5), Vector2(-4.5, 16.5),
		Vector2(6.0, 19.5), Vector2(-6.0, 19.5),
		Vector2(3.5, 13.5), Vector2(-3.5, 13.5),
		Vector2(0.0, 15.5), Vector2(0.0, 12.5),
		Vector2(7.5, 23.0), Vector2(-7.5, 23.0),
	]
	for bp in p.blueprints:
		if bp.archetype != arch:
			continue
		var front_face := bp.local_to_world_2d(Vector2(0.0, bp.depth * 0.5))
		var target_h := bp.base_y + bp.get_total_wall_height() * 0.56
		for off in offsets:
			var cam_xz := bp.local_to_world_2d(Vector2(off.x, bp.depth * 0.5 + off.y))
			var cam_h := maxf(bp.sidewalk_y + 2.4, p.terrain.sample_height(cam_xz.x, cam_xz.y) + 2.2)
			var ray_mid := cam_xz.lerp(front_face, 0.45)
			var clear := true
			for obp in p.blueprints:
				if ParcelData.obb_overlaps(cam_xz, Vector2(2.6, 2.6), 0.0, obp.center, Vector2(obp.width * 0.5, obp.depth * 0.5), obp.yaw, 0.0):
					clear = false
					break
				if obp != bp and ParcelData.obb_overlaps(ray_mid, Vector2(1.8, 1.8), 0.0, obp.center, Vector2(obp.width * 0.5, obp.depth * 0.5), obp.yaw, 0.0):
					clear = false
					break
			if clear:
				for txz in tree_xzs:
					if txz.distance_to(cam_xz) < 5.2 or Geometry2D.get_closest_point_to_segment(txz, cam_xz, front_face).distance_to(txz) < 3.6:
						clear = false
						break
			var d := front_face.distance_to(cam_xz)
			var pose := {"pos": Vector3(cam_xz.x, cam_h, cam_xz.y), "yaw": atan2(-(front_face.x - cam_xz.x), -(front_face.y - cam_xz.y)), "pitch": clampf(atan2(target_h - cam_h, maxf(1.0, d)), -0.15, 0.28)}
			if best_fallback.is_empty():
				best_fallback = pose
			if clear:
				return pose
	if not best_fallback.is_empty():
		return best_fallback
	return _find_street_view(p)


func _find_footbridge_view(p: CityPlan) -> Dictionary:
	for pw in p.park_walkways:
		if String(pw.get("kind", "")) == "footbridge":
			var pts: PackedVector2Array = pw.get("points", PackedVector2Array())
			if pts.size() >= 2:
				var mid := (pts[0] + pts[pts.size() - 1]) * 0.5
				var span := (pts[pts.size() - 1] - pts[0]).normalized()
				var side := Vector2(-span.y, span.x)
				var cam_xz := mid + side * 12.5 - span * 6.5
				var cam_h := maxf(p.terrain.water_level + 4.8, p.terrain.sample_height(cam_xz.x, cam_xz.y) + 3.2)
				var look_h := maxf(p.terrain.water_level + 1.8, p.terrain.sample_height(pts[0].x, pts[0].y) + 1.2)
				var dv := Vector2(mid.x - cam_xz.x, mid.y - cam_xz.y)
				return {"pos": Vector3(cam_xz.x, cam_h, cam_xz.y), "yaw": atan2(-dv.x, -dv.y), "pitch": atan2(look_h - cam_h, maxf(1.0, dv.length()))}
	return _find_creek_view(p)


func _find_prop_view(p: CityPlan, ptype: String, offset: Vector3, look_y_off: float) -> Dictionary:
	for pr in p.props:
		if String(pr.get("type", "")) == ptype:
			var tpos: Vector3 = pr["pos"]
			var cam_pos := tpos + offset
			var dv := Vector2(tpos.x - cam_pos.x, tpos.z - cam_pos.z)
			return {
				"pos": cam_pos,
				"yaw": atan2(-dv.x, -dv.y),
				"pitch": clampf(atan2((tpos.y + look_y_off) - cam_pos.y, maxf(1.0, dv.length())), -0.8, 0.4),
			}
	return _find_park_view(p)


func _find_horizon_view(p: CityPlan) -> Dictionary:
	var ws := p.config.world_size
	var cam_pos := Vector3(ws - 85.0, p.terrain.sample_height(ws - 85.0, ws * 0.5) + 42.0, ws * 0.5)
	var look_pt := Vector3(ws + 320.0, 12.0, ws * 0.5)
	var dv := Vector2(look_pt.x - cam_pos.x, look_pt.z - cam_pos.z)
	return {"pos": cam_pos, "yaw": atan2(-dv.x, -dv.y), "pitch": -0.09}


func _find_elevator_view(p: CityPlan) -> Dictionary:
	for bp in p.blueprints:
		if bp.floors >= 5 or bp.archetype == "hospital":
			var ib := InteriorGenerator.generate(bp, p.config.world_seed)
			if bool(ib.elevator.get("enabled", false)):
				var sr: Rect2 = ib.elevator["shaft_rect"]
				var look_pt := bp.local_to_world_3d(Vector3(sr.get_center().x, 1.35, sr.end.y))
				var cam_pt := bp.local_to_world_3d(Vector3(sr.get_center().x + 0.35, 1.55, sr.end.y + 2.25))
				var dv := Vector2(look_pt.x - cam_pt.x, look_pt.z - cam_pt.z)
				return {"pos": cam_pt, "yaw": atan2(-dv.x, -dv.y), "pitch": -0.05}
	return _find_interior_view(p)


func _find_traffic_junction_view(p: CityPlan, street_level: bool) -> Dictionary:
	var dt_c: Vector2 = p.district_centers.get("downtown_mixed", Vector2(p.config.world_size * 0.5, p.config.world_size * 0.5))
	var best_n: RoadGraph.RoadNode = null
	var best_score := -INF
	for n in p.road_graph.nodes:
		if not n.has_traffic_signal or n.incident_edge_ids.size() < 4:
			continue
		var art_cnt := 0
		for eid in n.incident_edge_ids:
			if p.road_graph.edges[eid].road_class == "arterial":
				art_cnt += 1
		var near_blds := 0
		var near_tall := 0
		for bp in p.blueprints:
			var d2 := bp.center.distance_squared_to(n.pos)
			if d2 < 90.0 * 90.0:
				near_blds += 1
				if bp.floors >= 5:
					near_tall += 1
		var sc := float(near_blds) * 18.0 + float(near_tall) * 32.0 + float(art_cnt) * 45.0 - n.pos.distance_to(dt_c) * 0.35
		if sc > best_score:
			best_score = sc
			best_n = n
	if best_n != null:
		var look_pt := Vector3(best_n.pos.x, best_n.elevation + (1.2 if street_level else 1.8), best_n.pos.y)
		var off := Vector3(13.5, 2.3, 14.5) if street_level else Vector3(24.0, 14.5, 28.0)
		var cam_pos := look_pt + off
		var dv := Vector2(look_pt.x - cam_pos.x, look_pt.z - cam_pos.z)
		return {
			"pos": cam_pos,
			"yaw": atan2(-dv.x, -dv.y),
			"pitch": clampf(atan2(look_pt.y - cam_pos.y, maxf(1.0, dv.length())), -0.85, 0.25),
		}
	return _find_street_view(p)


func _find_beach_view(p: CityPlan) -> Dictionary:
	## Panoramic coastal view framing turquoise ocean surf, wooden pier, golden sandy beach, umbrellas, boardwalk & pastel beach houses.
	var anchor_x := p.config.world_size * 0.36
	for pr in p.props:
		if String(pr.get("type", "")) == "beach_pier":
			anchor_x = float(Vector3(pr["pos"]).x)
			break
	var shore_z := p.terrain.get_beach_shore_z(anchor_x)
	var cam_pos := Vector3(anchor_x - 62.0, p.terrain.water_level + 17.5, shore_z + 24.0)
	var look_pt := Vector3(anchor_x + 28.0, p.terrain.water_level + 3.6, shore_z - 42.0)
	var dv := Vector2(look_pt.x - cam_pos.x, look_pt.z - cam_pos.z)
	return {
		"pos": cam_pos,
		"yaw": atan2(-dv.x, -dv.y),
		"pitch": clampf(atan2(look_pt.y - cam_pos.y, maxf(1.0, dv.length())), -0.65, 0.15),
	}


func _find_beach_house_view(p: CityPlan) -> Dictionary:
	## Close 3/4 coastal architectural view from the golden sandy beach showcasing elevated cedar decks, stilts, balconies & surf.
	var best_bp: BuildingBlueprint = null
	var best_score := -INF
	for bp in p.blueprints:
		if bp.archetype != "beach_house":
			continue
		var sc := float(bp.floors) * 18.0 + bp.width * 1.4 - absf(bp.center.x - p.config.world_size * 0.42) * 0.03
		if sc > best_score:
			best_score = sc
			best_bp = bp
	if best_bp != null:
		# Local -Z faces South toward beach & ocean; step south onto dry golden sand and look back up at the rear ocean deck!
		var cam_xz := best_bp.local_to_world_2d(Vector2(14.5, -best_bp.depth * 0.5 - 16.5))
		var target_xz := best_bp.local_to_world_2d(Vector2(-1.5, -best_bp.depth * 0.25))
		var cam_y := maxf(p.terrain.water_level + 2.6, p.terrain.sample_height(cam_xz.x, cam_xz.y) + 2.8)
		var look_y := best_bp.base_y + 3.4
		var dv := target_xz - cam_xz
		return {
			"pos": Vector3(cam_xz.x, cam_y, cam_xz.y),
			"yaw": atan2(-dv.x, -dv.y),
			"pitch": clampf(atan2(look_y - cam_y, maxf(1.0, dv.length())), -0.45, 0.35),
		}
	return _find_beach_view(p)


func _find_pier_view(p: CityPlan) -> Dictionary:
	## Oceanfront pier deck perspective looking diagonally across breaking surf rollers, pier pavilion, golden beach & beachfront homes.
	for pr in p.props:
		if String(pr.get("type", "")) == "beach_pier":
			var ppos: Vector3 = pr["pos"]
			var plen := float(pr.get("length", 74.0))
			var cam_pos := Vector3(ppos.x + 15.0, ppos.y + 4.8, ppos.z + plen * 0.46)
			var look_pt := Vector3(ppos.x - 16.0, ppos.y + 1.4, ppos.z - plen * 0.52)
			var dv := Vector2(look_pt.x - cam_pos.x, look_pt.z - cam_pos.z)
			return {
				"pos": cam_pos,
				"yaw": atan2(-dv.x, -dv.y),
				"pitch": clampf(atan2(look_pt.y - cam_pos.y, maxf(1.0, dv.length())), -0.55, 0.25),
			}
	return _find_beach_view(p)


func _find_underwater_view(p: CityPlan) -> Dictionary:
	## Submerged underwater reef view beside the ocean pier pilings framing coral reefs, swaying kelp, swimming fish schools, seabed caustics & Snell's window!
	var anchor_x := p.config.world_size * 0.36
	for pr in p.props:
		if String(pr.get("type", "")) == "beach_pier":
			anchor_x = float(Vector3(pr["pos"]).x)
			break
	var shore_z := p.terrain.get_beach_shore_z(anchor_x)
	var cam_x := anchor_x - 3.4
	var cam_z := minf(p.config.world_size - 22.0, shore_z + 40.0)
	var bed_y := p.terrain.sample_height(cam_x, cam_z)
	var wl := p.terrain.water_level
	# Remember PlayerController._head is at +1.62m above player.global_position
	var cam_lens_y := clampf(wl - 1.35, bed_y + 1.25, wl - 0.65)
	var look_pt := Vector3(anchor_x + 3.5, cam_lens_y - 0.15, cam_z - 15.0)
	var dv := Vector2(look_pt.x - cam_x, look_pt.z - cam_z)
	return {
		"pos": Vector3(cam_x, cam_lens_y - 1.62, cam_z),
		"yaw": atan2(-dv.x, -dv.y),
		"pitch": clampf(atan2(look_pt.y - cam_lens_y, maxf(1.0, dv.length())), -0.35, 0.35),
	}


func _find_car_close_view(p: CityPlan) -> Dictionary:
	## Close street-level automotive inspection view framing parked EVs and multi-lane moving traffic.
	for pr in p.props:
		if String(pr.get("type", "")) == "parked_ev":
			var cpos: Vector3 = pr["pos"]
			var cyaw := float(pr.get("yaw", 0.0))
			var fwd := Vector3(sin(cyaw), 0.0, cos(cyaw))
			var right := Vector3(cos(cyaw), 0.0, -sin(cyaw))
			var cam_lens := cpos + fwd * 3.8 + right * 2.7 + Vector3(0.0, 1.45, 0.0)
			var look_pt := cpos + Vector3(0.0, 0.78, 0.0)
			var dv := Vector2(look_pt.x - cam_lens.x, look_pt.z - cam_lens.z)
			return {
				"pos": cam_lens - Vector3(0.0, 1.62, 0.0),
				"yaw": atan2(-dv.x, -dv.y),
				"pitch": clampf(atan2(look_pt.y - cam_lens.y, maxf(0.5, dv.length())), -0.45, 0.25),
			}
	return _find_traffic_junction_view(p, true)
