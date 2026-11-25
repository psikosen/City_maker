extends SceneTree

## Headless automated validation suite for Milestone 1 (Section 8 acceptance checklist).
## Run with: godot --headless --path . -s res://src/city_world/tests/validate_city.gd

var _failures: Array[String] = []
var _checks_passed: int = 0


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	var seed_count := 100
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seed_count = maxi(1, int(arg.substr(8)))

	print("=== Procedural City 2028 • Milestone 9 Validation Suite (2304×2304m Metropolis) ===")
	print("Testing %d deterministic seeds + multi-lane IDM/MOBIL traffic + scheduled NPCs + architecture + interiors..." % seed_count)

	_test_tree_generator()
	_test_multi_seed_generation(seed_count)
	_test_interiors_plan(mini(8, seed_count))
	await _test_live_physics_and_doors()

	print("\n=== Validation Summary ===")
	print("Checks passed: %d" % _checks_passed)
	if _failures.is_empty():
		print("RESULT: ALL CHECKS PASSED")
		quit(0)
	else:
		print("RESULT: %d FAILURE(S):" % _failures.size())
		for f in _failures:
			printerr("  [FAIL] " + f)
		quit(1)


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_checks_passed += 1
	else:
		_failures.append(msg)


func _test_multi_seed_generation(seed_count: int) -> void:
	var cfg_a := CityConfig.new()
	cfg_a.world_seed = 202801
	var p_a1 := CityWorld.generate_plan_only(cfg_a)
	var p_a2 := CityWorld.generate_plan_only(cfg_a)
	_assert_true(p_a1.plan_hash == p_a2.plan_hash, "Determinism: same seed 202801 produced different hashes")

	var cfg_b := CityConfig.new()
	cfg_b.world_seed = 202802
	var p_b := CityWorld.generate_plan_only(cfg_b)
	_assert_true(p_a1.plan_hash != p_b.plan_hash, "Seed variance: different seeds produced identical hashes")

	var min_bld := 9999
	var max_bld := 0
	var total_bridges := 0
	var max_floors_seen := 0
	var max_width_seen := 0.0
	var total_ext_trashcans := 0

	for i in range(seed_count):
		var s := 202800 + i
		var cfg := CityConfig.new()
		cfg.world_seed = s
		var plan := CityWorld.generate_plan_only(cfg)

		# 0. Map & river expansion check (2304x2304m = 18x18 chunks, river half-width >= 20m)
		if absf(plan.config.world_size - 2304.0) > 0.01 or plan.config.get_chunks_per_axis() != 18 or plan.terrain.creek_half_width < 20.0:
			_failures.append("Seed %d: expected world_size=2304.0 (18x18 chunks, river_hw>=20), got %.1f (%dx%d, hw=%.1f)" % [s, plan.config.world_size, plan.config.get_chunks_per_axis(), plan.config.get_chunks_per_axis(), plan.terrain.creek_half_width])
			continue
		_checks_passed += 1

		# 1. Road connectivity & street naming
		if not plan.road_graph.is_graph_connected():
			_failures.append("Seed %d: road graph disconnected" % s)
			continue
		var named_edges := 0
		for re in plan.road_graph.edges:
			if re.street_name != "":
				named_edges += 1
		if named_edges < int(float(plan.road_graph.edges.size()) * 0.65):
			_failures.append("Seed %d: insufficient named road edges (%d/%d)" % [s, named_edges, plan.road_graph.edges.size()])
			continue
		_checks_passed += 1

		# 2. Bridge presence
		var bridge_count := 0
		for e in plan.road_graph.edges:
			if e.is_bridge:
				bridge_count += 1
		total_bridges += bridge_count
		if bridge_count < 2:
			_failures.append("Seed %d: expected >= 2 river bridges, got %d" % [s, bridge_count])
			continue
		_checks_passed += 1

		# 3. Building count target (340-580), landmark skyscrapers, signage & archetype diversity
		var b_count := plan.blueprints.size()
		min_bld = mini(min_bld, b_count)
		max_bld = maxi(max_bld, b_count)
		if b_count < cfg.target_min_buildings or b_count > cfg.target_max_buildings:
			_failures.append("Seed %d: building count %d outside [%d, %d]" % [s, b_count, cfg.target_min_buildings, cfg.target_max_buildings])
			continue
		_checks_passed += 1

		var signed_count := 0
		for bp_sz in plan.blueprints:
			max_floors_seen = maxi(max_floors_seen, bp_sz.floors)
			max_width_seen = maxf(max_width_seen, maxf(bp_sz.width, bp_sz.depth))
			if bp_sz.has_signage and bp_sz.sign_label != "":
				signed_count += 1
		if signed_count < 18:
			_failures.append("Seed %d: expected >= 18 commercial buildings with signage, got %d" % [s, signed_count])
			continue
		_checks_passed += 1

		var seed_bins := 0
		var seed_street_signs := 0
		var seed_hydrants := 0
		var seed_furniture := 0
		for pr_item in plan.props:
			var pt := String(pr_item.get("type", ""))
			if pt == "trashcan":
				seed_bins += 1
			elif pt == "street_sign":
				seed_street_signs += 1
			elif pt == "fire_hydrant":
				seed_hydrants += 1
			elif pt in ["planter_box", "sidewalk_bench", "bike_rack", "mailbox", "utility_box", "city_kiosk", "billboard"]:
				seed_furniture += 1
		if seed_bins < 12 or seed_street_signs < 6 or seed_hydrants < 6 or seed_furniture < 20:
			_failures.append("Seed %d: insufficient city infrastructure (bins=%d, street_signs=%d, hydrants=%d, furniture=%d)" % [s, seed_bins, seed_street_signs, seed_hydrants, seed_furniture])
			continue
		total_ext_trashcans += seed_bins
		_checks_passed += 1

		var archs := plan.get_building_count_by_archetype()
		if archs.size() < 8:
			_failures.append("Seed %d: expected >= 8 archetypes, got %d (%s)" % [s, archs.size(), str(archs)])
			continue
		if int(archs.get("municipal_hall", 0)) < 1 or int(archs.get("police_station", 0)) < 1 or int(archs.get("fire_station", 0)) < 1 or int(archs.get("church", 0)) < 2 or int(archs.get("hospital", 0)) < 1 or int(archs.get("school", 0)) < 1:
			_failures.append("Seed %d: missing guaranteed civic/church/hospital/school landmarks (%s)" % [s, str(archs)])
			continue
		_checks_passed += 1

		# 3b. Park walkway, footbridge & greenway connectivity check (Milestone 7 + 8)
		var greenway_count := 0
		var gazebo_plaza_count := 0
		var park_connector_count := 0
		var footbridge_count := 0
		for pw in plan.park_walkways:
			var pw_kind := String(pw.get("kind", ""))
			var pw_style := String(pw.get("style", ""))
			if pw_kind == "footbridge":
				footbridge_count += 1
			elif pw_style == "greenway":
				greenway_count += 1
			elif pw_kind == "plaza" and bool(pw.get("has_gazebo", false)):
				gazebo_plaza_count += 1
			elif pw_kind == "path":
				park_connector_count += 1
		if greenway_count < 2 or park_connector_count < 2 or gazebo_plaza_count < 1 or footbridge_count < 1:
			_failures.append("Seed %d: insufficient park walkways/plazas/footbridges (greenways=%d, paths=%d, plazas=%d, footbridges=%d)" % [s, greenway_count, park_connector_count, gazebo_plaza_count, footbridge_count])
			continue
		var fountain_props := 0
		var court_props := 0
		var pier_props := 0
		var lifeguard_props := 0
		var umbrella_props := 0
		var boardwalk_props := 0
		var palm_props := 0
		var coral_props := 0
		var kelp_props := 0
		for pr_s in plan.props:
			var pk_s := String(pr_s.get("type", ""))
			if pk_s == "park_fountain":
				fountain_props += 1
			elif pk_s == "sport_court":
				court_props += 1
			elif pk_s == "beach_pier":
				pier_props += 1
			elif pk_s == "lifeguard_tower":
				lifeguard_props += 1
			elif pk_s == "beach_umbrella_set":
				umbrella_props += 1
			elif pk_s == "beach_boardwalk_seg":
				boardwalk_props += 1
			elif pk_s == "beach_palm":
				palm_props += 1
			elif pk_s == "coral_reef_cluster":
				coral_props += 1
			elif pk_s == "underwater_kelp":
				kelp_props += 1
		if fountain_props < 1 or court_props < 1:
			_failures.append("Seed %d: expected >= 1 park_fountain (%d) and >= 1 sport_court (%d)" % [s, fountain_props, court_props])
			continue
		var beach_house_count := int(archs.get("beach_house", 0))
		if beach_house_count < 6 or pier_props < 1 or lifeguard_props < 1 or umbrella_props < 4 or boardwalk_props < 4 or palm_props < 8 or coral_props < 12 or kelp_props < 12:
			_failures.append("Seed %d: missing beachfront/underwater features (houses=%d, piers=%d, lifeguards=%d, umbrellas=%d, boardwalk=%d, palms=%d, coral=%d, kelp=%d)" % [s, beach_house_count, pier_props, lifeguard_props, umbrella_props, boardwalk_props, palm_props, coral_props, kelp_props])
			continue
		_checks_passed += 1

		# 4. Parcel map
		var parcel_map := {}
		for pr in plan.parcels:
			parcel_map[pr.id] = pr

		# 5. Building containment, road clearance, creek clearance, foundation coverage, non-overlap
		var seed_geom_ok := true
		for bi in range(b_count):
			var bp := plan.blueprints[bi]
			var parcel: ParcelData.Parcel = parcel_map.get(bp.parcel_id, null)
			if parcel == null:
				_failures.append("Seed %d: %s missing parcel %s" % [s, bp.id, bp.parcel_id])
				seed_geom_ok = false
				break

			var corners := bp.get_footprint_corners()
			for c in corners:
				if not ParcelData.point_in_convex_polygon(c, parcel.polygon, 0.05):
					_failures.append("Seed %d: %s corner outside parcel %s" % [s, bp.id, parcel.id])
					seed_geom_ok = false
					break
				if plan.road_graph.distance_to_road_corridor(c) < 0.35:
					_failures.append("Seed %d: %s encroaches road corridor" % [s, bp.id])
					seed_geom_ok = false
					break
				if plan.terrain.distance_to_creek(c) < plan.terrain.creek_half_width + 1.0:
					_failures.append("Seed %d: %s overlaps creek channel" % [s, bp.id])
					seed_geom_ok = false
					break
			if not seed_geom_ok:
				break

			var mm := plan.terrain.sample_min_max_in_obb(bp.center, Vector2(bp.width * 0.5, bp.depth * 0.5), bp.yaw)
			if bp.foundation_bottom_y > mm.x - 0.3:
				_failures.append("Seed %d: %s floating foundation (bottom=%.2f > min_terr=%.2f)" % [s, bp.id, bp.foundation_bottom_y, mm.x])
				seed_geom_ok = false
				break

			for bj in range(bi + 1, b_count):
				var other := plan.blueprints[bj]
				if ParcelData.obb_overlaps(bp.center, Vector2(bp.width * 0.5, bp.depth * 0.5), bp.yaw, other.center, Vector2(other.width * 0.5, other.depth * 0.5), other.yaw, 0.05):
					_failures.append("Seed %d: buildings %s and %s overlap" % [s, bp.id, other.id])
					seed_geom_ok = false
					break
			if not seed_geom_ok:
				break

		if seed_geom_ok:
			_checks_passed += 1

	_assert_true(max_floors_seen >= 11, "Expected skyscraper towers (>=11 floors) across seeds, got max=%d" % max_floors_seen)
	_assert_true(max_width_seen >= 22.0, "Expected larger buildings (>=22m span) across seeds, got max=%.1f" % max_width_seen)
	print("Multi-seed stats (%d seeds): buildings min=%d, max=%d, max_floors=%d, max_span=%.1fm, ext_trashcans=%d, total_bridges=%d" % [seed_count, min_bld, max_bld, max_floors_seen, max_width_seen, total_ext_trashcans, total_bridges])


func _test_live_physics_and_doors() -> void:
	var root := Node3D.new()
	get_root().add_child(root)

	var cw := CityWorld.new()
	cw.auto_generate_on_ready = false
	root.add_child(cw)

	var plan := cw.build_from_seed(202801)
	var player := PlayerController.new()
	player.city_world = cw
	root.add_child(player)

	# Allow Jolt physics world to register all static shapes.
	await physics_frame
	await physics_frame
	await physics_frame

	var space := root.get_world_3d().direct_space_state

	# 1. Dense world_size x world_size ground raycast sweep (every 8m across 1280m + exact chunk borders).
	var ws := plan.config.world_size
	var cs := plan.config.chunk_size
	var chunks_per_axis := plan.config.get_chunks_per_axis()
	_assert_true(cw.chunk_roots.size() == chunks_per_axis * chunks_per_axis, "Expected %d chunk_roots, got %d" % [chunks_per_axis * chunks_per_axis, cw.chunk_roots.size()])
	var missed_rays := 0
	var max_terrain_err := 0.0
	var step_sweep := 12.0 if ws >= 2000.0 else (8.0 if ws >= 900.0 else 4.0)
	var x := 4.0
	while x <= ws - 4.0:
		var z := 4.0
		while z <= ws - 4.0:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 120.0, z), Vector3(x, -30.0, z))
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				missed_rays += 1
			z += step_sweep
		x += step_sweep
	_assert_true(missed_rays == 0, "Ground physics sweep: %d rays hit empty void!" % missed_rays)

	# Exact chunk boundary seam check at x/z = i * chunk_size.
	var seam_misses := 0
	var borders: Array[float] = []
	for ci in range(1, chunks_per_axis):
		borders.append(float(ci) * cs)
	for border in borders:
		var s := 8.0
		while s <= ws - 8.0:
			for pt in [Vector2(border, s), Vector2(s, border)]:
				var q := PhysicsRayQueryParameters3D.create(Vector3(pt.x, 120.0, pt.y), Vector3(pt.x, -30.0, pt.y))
				var hit := space.intersect_ray(q)
				if hit.is_empty():
					seam_misses += 1
				else:
					var exp_h := plan.terrain.sample_height(pt.x, pt.y)
					if hit["position"].y < exp_h - 0.5:
						seam_misses += 1
					max_terrain_err = maxf(max_terrain_err, absf(hit["position"].y - exp_h))
			s += step_sweep
	_assert_true(seam_misses == 0, "Chunk boundary seam check: %d seam misses/drops!" % seam_misses)

	# 2. Road & Bridge surface physics alignment
	var road_misses := 0
	for e in plan.road_graph.edges:
		for t in [0.25, 0.5, 0.75]:
			var p3 := plan.road_graph.sample_edge_point_3d(e, t)
			var q := PhysicsRayQueryParameters3D.create(Vector3(p3.x, p3.y + 5.0, p3.z), Vector3(p3.x, p3.y - 5.0, p3.z))
			var hit := space.intersect_ray(q)
			if hit.is_empty() or absf(hit["position"].y - p3.y) > 0.25:
				road_misses += 1
	_assert_true(road_misses == 0, "Road/Bridge physics alignment: %d mismatches" % road_misses)

	# 2b. Milestone 5 city expansion, signage Label3D, skyscraper & urban amenities verification
	var prop_counts := {}
	for pr_d in plan.props:
		var pt_k := String(pr_d.get("type", ""))
		prop_counts[pt_k] = int(prop_counts.get(pt_k, 0)) + 1
	for req_prop in ["street_sign", "fire_hydrant", "planter_box", "sidewalk_bench", "bike_rack", "mailbox", "city_kiosk", "billboard", "path_bollard", "park_gazebo", "park_fountain", "sport_court", "cafe_seating", "a_frame_sign", "crosswalk_button", "parcel_locker", "bush", "flower_patch"]:
		_assert_true(int(prop_counts.get(req_prop, 0)) > 0, "Missing urban infrastructure prop type: %s" % req_prop)
	_assert_true(int(prop_counts.get("bush", 0)) >= 120, "Expected >= 120 procedural bushes across streets/parks/yards, got %d" % int(prop_counts.get("bush", 0)))
	_assert_true(int(prop_counts.get("flower_patch", 0)) >= 120, "Expected >= 120 procedural flower patches, got %d" % int(prop_counts.get("flower_patch", 0)))

	var arch_counts := plan.get_building_count_by_archetype()
	for req_arch in ["skyscraper_tower", "apartment_midrise", "retail_anchor", "municipal_hall", "police_station", "fire_station", "church", "hospital", "school"]:
		_assert_true(int(arch_counts.get(req_arch, 0)) > 0, "Seed 202801 missing required archetype: %s" % req_arch)
	_assert_true(int(arch_counts.get("church", 0)) >= 2, "Expected >= 2 churches in seed 202801, got %d" % int(arch_counts.get("church", 0)))

	var scene_label_count := 0
	var flora_mm_count := 0
	var balcony_glass_count := 0
	var has_horizon_skirt := false
	var stack: Array[Node] = [cw]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur.name == "HorizonTerrainSkirt" and cur is MeshInstance3D:
			has_horizon_skirt = true
		if cur is Label3D:
			scene_label_count += 1
		elif cur is MultiMeshInstance3D and cur.name.begins_with("Flora"):
			flora_mm_count += cur.multimesh.instance_count
		elif cur is MeshInstance3D and cur.name == "BalconyGlassMesh":
			balcony_glass_count += 1
		for ch in cur.get_children():
			stack.append(ch)
	_assert_true(has_horizon_skirt, "Missing HorizonTerrainSkirt seamless outer hill terrain")
	_assert_true(flora_mm_count >= 250, "Expected >= 250 instanced MultiMesh bush/flower nodes in live scene, got %d" % flora_mm_count)
	_assert_true(balcony_glass_count >= 10, "Expected >= 10 buildings with persistent BalconyGlassMesh balustrades, got %d" % balcony_glass_count)
	_assert_true(scene_label_count >= 40, "Expected >= 40 3D signage Label3D nodes across buildings/streets/billboards/kiosks, got %d" % scene_label_count)
	print("Milestone 5 scene check: archs=%s, street_signs=%d, hydrants=%d, planters=%d, kiosks=%d, billboards=%d, bushes=%d, flowers=%d, balcony_glass_blds=%d, Label3Ds=%d" % [
		str(arch_counts),
		int(prop_counts.get("street_sign", 0)),
		int(prop_counts.get("fire_hydrant", 0)),
		int(prop_counts.get("planter_box", 0)),
		int(prop_counts.get("city_kiosk", 0)),
		int(prop_counts.get("billboard", 0)),
		int(prop_counts.get("bush", 0)),
		int(prop_counts.get("flower_patch", 0)),
		balcony_glass_count,
		scene_label_count,
	])

	# 3. Real CharacterBody3D doorway test across every building archetype present!
	var tested_archs := {}
	var door_tests_run := 0
	for bp in plan.blueprints:
		if tested_archs.has(bp.archetype):
			continue
		tested_archs[bp.archetype] = true
		door_tests_run += 1

		var door: InteractiveDoor = cw.doors_by_id[bp.door_id]
		_assert_true(door != null and not door.is_open, "Door %s should exist and start closed" % bp.door_id)

		var app := bp.get_approach_world_pos()
		var vest := bp.get_vestibule_world_center()
		var start_pos := Vector3(app.x, bp.sidewalk_y + 0.12, app.z)
		var forward_dir := (Vector3(vest.x, 0.0, vest.z) - Vector3(app.x, 0.0, app.z)).normalized()

		# 3a. Closed door MUST block walking into vestibule.
		player.place_at(start_pos, atan2(-forward_dir.x, -forward_dir.z))
		for _f in range(30):
			player.velocity = Vector3(forward_dir.x * 4.5, -2.0, forward_dir.z * 4.5)
			player.move_and_slide()
		var dist_closed := Vector2(player.global_position.x - vest.x, player.global_position.z - vest.z).length()
		_assert_true(dist_closed > 1.2, "Closed door %s failed to block player (dist_to_vestibule=%.2f)" % [bp.door_id, dist_closed])

		# 3b. Open door and walk smoothly across ramp & threshold into physical vestibule!
		door.set_open(true, true)
		await physics_frame
		await physics_frame

		player.place_at(start_pos, atan2(-forward_dir.x, -forward_dir.z))
		for _f in range(95):
			var step_dir := Vector3(vest.x - player.global_position.x, 0.0, vest.z - player.global_position.z)
			if step_dir.length() > 0.15:
				step_dir = step_dir.normalized()
			else:
				step_dir = Vector3.ZERO
			player.velocity = Vector3(step_dir.x * 4.2, -3.0, step_dir.z * 4.2)
			# Emulate curb/threshold assist during automated walk
			var h_mot := Vector3(player.velocity.x, 0.0, player.velocity.z) * (1.0 / 60.0)
			if player.is_on_floor() and h_mot.length_squared() > 0.0001 and player.test_move(player.global_transform, h_mot):
				var up_tf := player.global_transform.translated(Vector3(0, 0.25, 0))
				if not player.test_move(up_tf, h_mot):
					player.global_position.y += 0.25
			player.move_and_slide()

		var dist_open := Vector2(player.global_position.x - vest.x, player.global_position.z - vest.z).length()
		_assert_true(dist_open < 0.65, "Open door %s (%s) prevented player entering vestibule (dist=%.2f)" % [bp.door_id, bp.archetype, dist_open])
		_assert_true(player.is_on_floor(), "Player not grounded on vestibule floor of %s" % bp.id)
		_assert_true(absf(player.global_position.y - bp.base_y) < 0.25, "Player y=%.2f mismatched base_y=%.2f inside %s" % [player.global_position.y, bp.base_y, bp.id])

		# Close door back so only persistence test doors stay open later.
		door.set_open(false, true)
		await physics_frame

	print("Doorway & vestibule walk-in tests run: %d" % door_tests_run)

	# 3c. Exterior wall pier blocking test (player cannot clip through solid walls)
	var wall_bp := plan.blueprints[0]
	var wall_outside := wall_bp.local_to_world_3d(Vector3(wall_bp.width * 0.35, 0.2, wall_bp.depth * 0.5 + 1.5))
	var wall_inside := wall_bp.local_to_world_3d(Vector3(wall_bp.width * 0.35, 0.2, 0.0))
	var wall_dir := (Vector3(wall_inside.x, 0.0, wall_inside.z) - Vector3(wall_outside.x, 0.0, wall_outside.z)).normalized()
	player.place_at(Vector3(wall_outside.x, wall_bp.sidewalk_y + 0.15, wall_outside.z), 0.0)
	for _f in range(45):
		player.velocity = Vector3(wall_dir.x * 5.0, -3.0, wall_dir.z * 5.0)
		player.move_and_slide()
	var dist_to_wall_core := Vector2(player.global_position.x - wall_inside.x, player.global_position.z - wall_inside.z).length()
	_assert_true(dist_to_wall_core > wall_bp.depth * 0.5 - 0.3, "Player penetrated solid exterior wall of %s!" % wall_bp.id)

	# 3d. Walk across chunk boundary & bridge along an arterial road edge
	var bridge_edge: RoadGraph.RoadEdge = null
	for e in plan.road_graph.edges:
		if e.is_bridge and e.road_class == "arterial":
			bridge_edge = e
			break
	if bridge_edge == null:
		for e in plan.road_graph.edges:
			if e.is_bridge:
				bridge_edge = e
				break
	if bridge_edge != null:
		var p_start := plan.road_graph.sample_edge_point_3d(bridge_edge, maxf(0.15, bridge_edge.bridge_start_t - 0.08))
		var p_end := plan.road_graph.sample_edge_point_3d(bridge_edge, minf(0.85, bridge_edge.bridge_end_t + 0.08))
		var walk_dir := (Vector3(p_end.x, 0.0, p_end.z) - Vector3(p_start.x, 0.0, p_start.z)).normalized()
		player.place_at(Vector3(p_start.x, p_start.y + 0.15, p_start.z), 0.0)
		var fell_below_bridge := false
		for _f in range(180):
			player.velocity = Vector3(walk_dir.x * 5.5, -3.5, walk_dir.z * 5.5)
			player.move_and_slide()
			if player.global_position.y < plan.terrain.water_level + 1.0:
				fell_below_bridge = true
				break
			if Vector2(player.global_position.x - p_end.x, player.global_position.z - p_end.z).length() < 1.5:
				break
		_assert_true(not fell_below_bridge and player.is_on_floor(), "Player fell or ungrounded while walking across creek bridge!")

	# 4. Persistence round-trip test (ChangedWorldState separated from WorldSeed)
	var test_save_path := "user://validate_milestone1_save.json"
	var opened_ids: Array[String] = [
		plan.blueprints[0].door_id,
		plan.blueprints[12].door_id,
		plan.blueprints[25].door_id,
	]
	for did in opened_ids:
		cw.doors_by_id[did].set_open(true, true)

	var saved_pos := Vector3(123.4, 8.5, 234.5)
	_assert_true(cw.save_to_disk(saved_pos, 1.25, test_save_path), "Persistence save failed")

	var orig_hash := plan.plan_hash
	cw.build_from_seed(999999)
	_assert_true(cw.plan.plan_hash != orig_hash, "Seed switch did not change plan")

	var loaded := cw.load_from_disk(test_save_path)
	_assert_true(not loaded.is_empty(), "Persistence load returned empty dictionary")
	_assert_true(cw.plan.plan_hash == orig_hash, "Reloaded plan hash mismatch")
	for did in opened_ids:
		_assert_true(cw.doors_by_id[did].is_open, "Persisted open door %s was not restored open" % did)
	_assert_true(not cw.doors_by_id[plan.blueprints[1].door_id].is_open, "Closed door unexpectedly marked open after reload")

	# 5. Milestone 2B: Streaming hysteresis + live multi-floor stair walkthrough + interior door persistence
	await _test_streaming_and_stair_walkthrough(cw, cw.plan, player)

	# 6. Milestone 3: 24h Day/Night cycle, weather state machine, indoor rain OBB exclusion & persistence
	await _test_atmosphere_and_weather(cw, cw.plan, player, root)

	# 7. Milestone 9: Multi-lane IDM/MOBIL traffic + scheduled NPC crowd & crosswalk interaction
	_test_traffic_and_npc_schedules(cw, cw.plan)

	# 8. Performance controls, quality presets, chunk culling & wet-only SSR gating
	_test_performance_controls(cw, cw.plan, player, root)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save_path))
	root.queue_free()


func _test_tree_generator() -> void:
	var species_list := ["oak", "austin_pecan", "cedar_elm", "planter_shrub", "weeping_willow"]
	for sp in species_list:
		var bundle := TreeGenerator.get_species_bundle(sp, 0)
		var b_lods: Array = bundle.get("bark_lods", [])
		var f_lods: Array = bundle.get("foliage_lods", [])
		_assert_true(b_lods.size() == 3 and f_lods.size() == 3, "Tree species %s did not build 3 LOD tiers" % sp)
		var v0 := (f_lods[0] as ArrayMesh).surface_get_array_len(0)
		var v1 := (f_lods[1] as ArrayMesh).surface_get_array_len(0)
		var v2 := (f_lods[2] as ArrayMesh).surface_get_array_len(0)
		_assert_true(v0 > 0 and v1 > 0 and v2 > 0, "Tree species %s generated empty foliage LOD mesh" % sp)
		_assert_true(v0 >= v1 and v1 >= v2, "Tree species %s LOD vertex counts did not decrease (%d -> %d -> %d)" % [sp, v0, v1, v2])
		_assert_true(float(bundle.get("trunk_radius", 0.0)) > 0.05 and float(bundle.get("trunk_height", 0.0)) > 0.5, "Tree species %s invalid trunk collider dimensions" % sp)


func _test_interiors_plan(interior_seed_count: int) -> void:
	const VENUE_EXPECTED_KINDS := {
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
		"police_station": ["holding_cell", "safe_vault_cabinet"],
		"fire_station": ["fire_truck"],
		"library": ["bookstore_shelf"],
		"post_office": ["teller_counter", "locker_bank"],
		"hospital": ["hospital_bed", "exam_table", "med_cabinet"],
		"school": ["school_desk", "bookstore_shelf"],
	}
	var total_checked := 0
	var multi_floor_checked := 0
	var indoor_trash_total := 0
	var total_furniture_checked := 0
	var tall_buildings_checked := 0
	var elev_buildings_checked := 0
	var venue_buildings_checked := 0
	var venue_counts := {}
	for i in range(interior_seed_count):
		var s := 202800 + i
		var cfg := CityConfig.new()
		cfg.world_seed = s
		var p := CityWorld.generate_plan_only(cfg)
		for bp in p.blueprints:
			total_checked += 1
			if bp.has_signage:
				_assert_true(bp.venue_type != "", "Signed building %s (%s) missing venue_type" % [bp.id, bp.sign_label])
			if bp.floors >= 6:
				tall_buildings_checked += 1
			var ib := InteriorGenerator.generate(bp, s)
			if bool(ib.elevator.get("enabled", false)):
				elev_buildings_checked += 1
			var building_kinds := {}
			for fx in [0.0, 0.5, 1.0]:
				for fz in [0.0, 0.5, 1.0]:
					var lx := lerpf(ib.inner_min.x + 0.1, ib.inner_max.x - 0.1, fx)
					var lz := lerpf(ib.inner_min.y + 0.1, ib.inner_max.y - 0.1, fz)
					var wpt := bp.local_to_world_2d(Vector2(lx, lz))
					var th := p.terrain.sample_height(wpt.x, wpt.y)
					_assert_true(th <= bp.base_y - 0.16, "Terrain (%.2f) pokes into interior floor (%.2f) in seed %d %s" % [th, bp.base_y, s, bp.id])
			_assert_true(ib.bfs_reachable, "Interior BFS failed reachability for seed %d %s (%s)" % [s, bp.id, bp.archetype])
			_assert_true(ib.reachable_room_count == ib.total_room_count, "Interior missed rooms (%d/%d) in seed %d %s" % [ib.reachable_room_count, ib.total_room_count, s, bp.id])
			_assert_true(ib.wall_window_conflicts == 0, "Interior partition crossed %d window bay(s) in seed %d %s" % [ib.wall_window_conflicts, s, bp.id])
			if bp.floors >= 2:
				multi_floor_checked += 1
				_assert_true(ib.stairs.size() == bp.floors - 1, "Expected %d stairs in %s, got %d" % [bp.floors - 1, bp.id, ib.stairs.size()])
				var sr: Rect2 = ib.stairs[0]["shaft_rect"]
				var flush_side := absf(sr.position.x - ib.inner_min.x) < 0.02 or absf(sr.end.x - ib.inner_max.x) < 0.02
				var flush_back := absf(sr.position.y - ib.inner_min.y) < 0.02
				_assert_true(flush_side and flush_back, "Stair shaft in %s has perimeter wall gap slivers (%s)" % [bp.id, str(sr)])

			# Parametric FurnitureGenerator verification: bounds, zero OBB overlap, door clearance, indoor trashcans
			for f_data in ib.floors:
				var f_list: Array = f_data.get("furniture", [])
				var i_doors: Array = f_data.get("interior_doors", [])
				for fi in range(f_list.size()):
					total_furniture_checked += 1
					var item: Dictionary = f_list[fi]
					var kind := String(item["kind"])
					building_kinds[kind] = true
					if kind == "trashcan_indoor" or kind == "trashcan_recycle":
						indoor_trash_total += 1
					var pos: Vector3 = item["pos"]
					var sz: Vector3 = item["size"]
					var yaw := float(item.get("yaw", 0.0))
					var rot_xz := FurnitureGenerator.get_rotated_xz_size(sz, yaw)
					var p2 := Vector2(pos.x, pos.z)
					var in_x := p2.x - rot_xz.x * 0.5 >= ib.inner_min.x + 0.02 and p2.x + rot_xz.x * 0.5 <= ib.inner_max.x - 0.02
					var in_z := p2.y - rot_xz.y * 0.5 >= ib.inner_min.y + 0.02 and p2.y + rot_xz.y * 0.5 <= ib.inner_max.y - 0.02
					_assert_true(in_x and in_z, "Furniture %s in %s outside interior bounds" % [kind, bp.id])
					for dr in i_doors:
						var dp: Vector3 = dr["pos"]
						_assert_true(not FurnitureGenerator.obbs_overlap_2d(p2, sz.x * 0.5, sz.z * 0.5, yaw, Vector2(dp.x, dp.z), 0.55, 0.55, 0.0, 0.05), "Furniture %s overlaps door swing in %s" % [kind, bp.id])
					for fj in range(fi + 1, f_list.size()):
						var other: Dictionary = f_list[fj]
						var o_pos: Vector3 = other["pos"]
						var o_sz: Vector3 = other["size"]
						var o_yaw := float(other.get("yaw", 0.0))
						_assert_true(not FurnitureGenerator.obbs_overlap_2d(p2, sz.x * 0.5, sz.z * 0.5, yaw, Vector2(o_pos.x, o_pos.z), o_sz.x * 0.5, o_sz.z * 0.5, o_yaw, 0.04), "Furniture %s overlaps %s in %s" % [kind, String(other["kind"]), bp.id])

			if bp.has_signage and VENUE_EXPECTED_KINDS.has(bp.venue_type):
				venue_buildings_checked += 1
				venue_counts[bp.venue_type] = int(venue_counts.get(bp.venue_type, 0)) + 1
				var expected_arr: Array = VENUE_EXPECTED_KINDS[bp.venue_type]
				var matched := false
				for ek in expected_arr:
					if building_kinds.has(String(ek)):
						matched = true
						break
				_assert_true(matched, "Venue %s ('%s') in seed %d %s generated no matching domain equipment (kinds=%s)" % [bp.venue_type, bp.sign_label, s, bp.id, str(building_kinds.keys())])

	_assert_true(tall_buildings_checked > 0, "Expected taller buildings (>=6 floors) in interior test seeds")
	_assert_true(elev_buildings_checked > 0, "Expected elevator-equipped towers in interior test seeds")
	_assert_true(indoor_trash_total >= total_checked, "Expected consistent indoor trashcans across buildings (got %d for %d buildings)" % [indoor_trash_total, total_checked])
	_assert_true(venue_buildings_checked >= interior_seed_count * 12, "Expected >= %d venue-matched buildings across interior test seeds, got %d" % [interior_seed_count * 12, venue_buildings_checked])
	if interior_seed_count >= 4:
		for req_v in ["gym", "cafe", "grocery", "restaurant", "bank", "church", "city_hall", "police_station", "fire_station", "library", "post_office", "hospital", "school"]:
			_assert_true(int(venue_counts.get(req_v, 0)) > 0, "Expected at least one '%s' venue across %d seeds" % [req_v, interior_seed_count])
	print("Interior blueprint checks run: %d buildings (%d multi-floor, %d tall >=6fl, %d elevator-equipped, %d venue-matched), %d furniture items (%d indoor trashcans) across %d seeds" % [total_checked, multi_floor_checked, tall_buildings_checked, elev_buildings_checked, venue_buildings_checked, total_furniture_checked, indoor_trash_total, interior_seed_count])


func _test_streaming_and_stair_walkthrough(cw: CityWorld, plan: CityPlan, player: PlayerController) -> void:
	# 5a. Chunk tree MultiMesh + trunk collider check
	var mm_count := 0
	var tree_col_count := 0
	for cc in cw.chunk_roots.keys():
		var c_node: Node3D = cw.chunk_roots[cc]
		for child in c_node.get_children():
			if child is MultiMeshInstance3D and String(child.name).begins_with("Trees"):
				mm_count += 1
			elif String(child.name).begins_with("TreeCollider_"):
				tree_col_count += 1
	_assert_true(mm_count > 0 and tree_col_count > 0, "Missing chunked Tree MultiMeshInstance3D (%d) or TreeCollider (%d)" % [mm_count, tree_col_count])

	# 5b. Streaming hysteresis check on a distant building
	var target_bp: BuildingBlueprint = plan.blueprints[plan.blueprints.size() - 1]
	cw.deactivate_interior(target_bp.id)
	var b_entry: Dictionary = cw.buildings_by_id[target_bp.id]
	var b_node: Node3D = b_entry["node"]
	_assert_true(not bool(b_node.get_meta("interior_active", true)), "Deactivated building should start in exterior mode")

	cw.update_interior_streaming(Vector3(target_bp.center.x, target_bp.base_y, target_bp.center.y), 16)
	_assert_true(bool(b_node.get_meta("interior_active", false)), "Building did not activate inside footprint")

	# Move 24m beyond outer edge (between 18m and 38m hysteresis band -> MUST stay active)
	var dir_out := target_bp.local_to_world_2d(Vector2(1.0, 0.0)) - target_bp.center
	var pt_mid := target_bp.center + dir_out * (target_bp.width * 0.5 + 24.0)
	cw.update_interior_streaming(Vector3(pt_mid.x, target_bp.base_y, pt_mid.y), 16)
	_assert_true(bool(b_node.get_meta("interior_active", false)), "Hysteresis failed: deactivated at 24m from edge (< 38m threshold)")

	# Move 48m beyond outer edge -> MUST deactivate back to exterior shell
	var pt_far := target_bp.center + dir_out * (target_bp.width * 0.5 + 48.0)
	cw.update_interior_streaming(Vector3(pt_far.x, target_bp.base_y, pt_far.y), 16)
	_assert_true(not bool(b_node.get_meta("interior_active", true)), "Building stayed active past 38m edge deactivation range")

	# 5c. Multi-floor physical stair climb walkthrough across distinct archetypes (including 2-flight vertical climb)
	var tested_multi := {}
	var tested_two_flights := false
	var multi_walkthroughs := 0
	var persisted_interior_door_id := ""
	var persisted_interior_bld_id := ""

	for bp in plan.blueprints:
		if bp.floors < 2 or tested_multi.has(bp.archetype):
			continue
		tested_multi[bp.archetype] = true
		multi_walkthroughs += 1

		var ib := cw.ensure_interior_active(bp.id)
		_assert_true(ib != null and ib.stairs.size() >= 1, "Failed to activate interior for %s" % bp.id)
		var f_door: InteractiveDoor = cw.doors_by_id[bp.door_id]
		f_door.set_open(true, true)
		var idoors := ib.get_interior_door_ids()
		for did in idoors:
			if cw.doors_by_id.has(did):
				cw.doors_by_id[did].set_open(true, true)
		if persisted_interior_door_id == "" and not idoors.is_empty():
			persisted_interior_door_id = idoors[0]
			persisted_interior_bld_id = bp.id

		await physics_frame
		await physics_frame
		await physics_frame

		var st0: Dictionary = ib.stairs[0]
		var entry_pt2: Vector2 = ib.floors[0]["entry_point"]
		var wp_list: Array[Vector3] = [
			bp.local_to_world_3d(Vector3(entry_pt2.x, 0.0, entry_pt2.y)),
		]
		wp_list.append_array(_bfs_floor_waypoints(entry_pt2, Vector2(st0["flight1_p0"].x, st0["flight1_p0"].z + 0.55), 0.0, ib.floors[0], bp, ib))
		wp_list.append_array([
			bp.local_to_world_3d(Vector3(st0["flight1_p0"].x, 0.0, st0["flight1_p0"].z + 0.55)),
			bp.local_to_world_3d(Vector3(st0["flight1_p1"].x, st0["flight1_p1"].y, st0["flight1_p1"].z - 0.35)),
			bp.local_to_world_3d(Vector3(st0["flight2_p0"].x, st0["flight2_p0"].y, st0["flight2_p0"].z - 0.35)),
			bp.local_to_world_3d(Vector3(st0["flight2_p1"].x, st0["flight2_p1"].y, st0["flight2_p1"].z + 0.65)),
		])
		var target_y := bp.base_y + bp.ground_floor_height
		var f1_cur := Vector2(st0["exit_pt_2d"])
		if ib.floors.size() >= 2 and not ib.floors[1]["rooms"].is_empty():
			var rm_c: Vector2 = ib.floors[1]["rooms"][0]["center"]
			var f1_y := float(ib.floors[1]["base_y"])
			wp_list.append_array(_bfs_floor_waypoints(f1_cur, rm_c, f1_y, ib.floors[1], bp, ib))
			f1_cur = rm_c

		if bp.floors >= 3 and ib.stairs.size() >= 2 and not tested_two_flights:
			tested_two_flights = true
			var st1: Dictionary = ib.stairs[1]
			var f1_y2 := float(ib.floors[1]["base_y"])
			var st1_in := Vector2(st1["flight1_p0"].x, st1["flight1_p0"].z + 0.55)
			wp_list.append_array(_bfs_floor_waypoints(f1_cur, st1_in, f1_y2, ib.floors[1], bp, ib))
			wp_list.append_array([
				bp.local_to_world_3d(Vector3(st1["flight1_p0"].x, f1_y2, st1["flight1_p0"].z + 0.55)),
				bp.local_to_world_3d(Vector3(st1["flight1_p1"].x, st1["flight1_p1"].y, st1["flight1_p1"].z - 0.35)),
				bp.local_to_world_3d(Vector3(st1["flight2_p0"].x, st1["flight2_p0"].y, st1["flight2_p0"].z - 0.35)),
				bp.local_to_world_3d(Vector3(st1["flight2_p1"].x, st1["flight2_p1"].y, st1["flight2_p1"].z + 0.65)),
			])
			target_y = bp.base_y + bp.ground_floor_height + bp.floor_height

		var app := bp.get_approach_world_pos()
		player.place_at(Vector3(app.x, bp.sidewalk_y + 0.12, app.z), 0.0)

		for wp in wp_list:
			for _f in range(280):
				var diff_xz := Vector3(wp.x - player.global_position.x, 0.0, wp.z - player.global_position.z)
				var d2 := diff_xz.length()
				if d2 < 0.25 and absf(player.global_position.y - wp.y) < 0.45:
					break
				var hdir := diff_xz.normalized() if d2 > 0.05 else Vector3.ZERO
				var y_vel := player.velocity.y - 24.0 * (1.0 / 60.0)
				if player.is_on_floor():
					y_vel = -0.5
				player.velocity = Vector3(hdir.x * 4.4, y_vel, hdir.z * 4.4)
				var h_mot := Vector3(player.velocity.x, 0.0, player.velocity.z) * (1.0 / 60.0)
				if player.is_on_floor() and h_mot.length_squared() > 0.0001 and player.test_move(player.global_transform, h_mot):
					var up_tf := player.global_transform.translated(Vector3(0, 0.25, 0))
					if not player.test_move(up_tf, h_mot):
						player.global_position.y += 0.25
				player.move_and_slide()

		var dy_target := absf(player.global_position.y - target_y)
		_assert_true(player.is_on_floor() and dy_target < 0.35, "Player failed to climb stairs in %s (%s): y=%.2f expected=%.2f" % [bp.id, bp.archetype, player.global_position.y, target_y])

	_assert_true(tested_two_flights, "Expected >= 1 multi-flight (Floor 0 -> Floor 2) stair walkthrough")
	_assert_true(multi_walkthroughs >= 2, "Expected >= 2 multi-floor archetype walkthroughs, ran %d" % multi_walkthroughs)
	print("Multi-floor stair walkthroughs passed: %d archetypes (incl. Floor 0->2 switchback)" % multi_walkthroughs)

	# 5d. Verify live InteractiveElevator Floor 0 -> Floor 2 -> Floor 0 cab ride
	var tested_elevator := false
	for el_bp in plan.blueprints:
		if el_bp.floors < 4:
			continue
		var el_ib := cw.ensure_interior_active(el_bp.id)
		if el_ib == null or not bool(el_ib.elevator.get("enabled", false)):
			continue
		await physics_frame
		await physics_frame
		var found_elev: InteractiveElevator = _find_elevator_for_building(cw, el_bp.id)
		if found_elev == null or found_elev.floor_ys.size() < 3:
			continue
		tested_elevator = true
		var srect: Rect2 = found_elev.shaft_rect
		var cab_start_w := el_bp.local_to_world_3d(Vector3(srect.get_center().x, float(found_elev.floor_ys[0]) + 0.08, srect.get_center().y))
		player.place_at(cab_start_w, 0.0)
		for _settle in range(8):
			await physics_frame
			player.velocity = Vector3(0.0, -0.5 if player.is_on_floor() else player.velocity.y - 24.0 * (1.0 / 60.0), 0.0)
			player.move_and_slide()
		_assert_true(player.is_on_floor(), "Player did not settle on Floor 0 elevator cab threshold in %s" % el_bp.id)

		found_elev.interact("call", 2)
		for _up_f in range(320):
			await physics_frame
			player.velocity = Vector3(0.0, -0.5 if player.is_on_floor() else player.velocity.y - 24.0 * (1.0 / 60.0), 0.0)
			player.move_and_slide()
			if not found_elev.is_moving and found_elev.current_floor == 2 and found_elev.door_open_frac >= 0.99:
				break
		var exp_y2 := el_bp.base_y + float(found_elev.floor_ys[2])
		_assert_true(found_elev.current_floor == 2 and absf(player.global_position.y - exp_y2) < 0.35, "Elevator ride up failed in %s: cab=%d player_y=%.2f expected=%.2f" % [el_bp.id, found_elev.current_floor, player.global_position.y, exp_y2])

		found_elev.interact("lobby", 0)
		for _dn_f in range(320):
			await physics_frame
			player.velocity = Vector3(0.0, -0.5 if player.is_on_floor() else player.velocity.y - 24.0 * (1.0 / 60.0), 0.0)
			player.move_and_slide()
			if not found_elev.is_moving and found_elev.current_floor == 0 and found_elev.door_open_frac >= 0.99:
				break
		var exp_y0 := el_bp.base_y + float(found_elev.floor_ys[0])
		_assert_true(found_elev.current_floor == 0 and absf(player.global_position.y - exp_y0) < 0.35, "Elevator ride down failed in %s: cab=%d player_y=%.2f expected=%.2f" % [el_bp.id, found_elev.current_floor, player.global_position.y, exp_y0])
		print("Live InteractiveElevator test passed in %s (%s): Floor 0 -> Floor 2 (%.2fm) -> Lobby" % [el_bp.id, el_bp.archetype, exp_y2])
		break
	_assert_true(tested_elevator, "Expected >= 1 live elevator cab ride verification in seed 202801")

	# 5e. Verify interior InteractiveDoor persistence across stream unload + reload!
	if persisted_interior_door_id != "":
		var int_save := "user://validate_interior_door_save.json"
		cw.deactivate_interior(persisted_interior_bld_id)
		_assert_true(cw.save_to_disk(Vector3(50.0, 5.0, 50.0), 0.0, int_save), "Interior door persistence save failed")
		cw.build_from_seed(888888)
		var l_int := cw.load_from_disk(int_save)
		_assert_true(not l_int.is_empty(), "Interior door persistence load returned empty")
		cw.ensure_interior_active(persisted_interior_bld_id)
		var restored_door: InteractiveDoor = cw.doors_by_id.get(persisted_interior_door_id, null)
		_assert_true(restored_door != null and restored_door.is_open, "Interior door %s open state lost across unload/reload" % persisted_interior_door_id)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(int_save))


func _test_atmosphere_and_weather(cw: CityWorld, plan: CityPlan, player: PlayerController, scene_root: Node3D) -> void:
	var w_env := WorldEnvironment.new()
	w_env.environment = Environment.new()
	scene_root.add_child(w_env)

	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	scene_root.add_child(sun)

	var atm := AtmosphereController.new()
	atm.name = "AtmosphereController"
	scene_root.add_child(atm)
	atm.setup(w_env, sun, cw, player)
	await physics_frame

	# 6a. Morning, Golden Hour, Dusk, Midnight solar/lunar arc & mutual shadow exclusivity
	atm.set_weather("clear", true)
	atm.set_time_of_day(10.5, true)
	_assert_true(atm.sun_elevation > 0.45 and atm.night_factor < 0.05, "10:30 morning failed expected high sun / low night factor (el=%.2f, nf=%.2f)" % [atm.sun_elevation, atm.night_factor])
	_assert_true(sun.shadow_enabled and atm.moon_light != null and not atm.moon_light.shadow_enabled, "Daytime shadow exclusivity failed (sun=%s, moon=%s)" % [sun.shadow_enabled, atm.moon_light.shadow_enabled])
	_assert_true(atm.get_active_streetlamp_count() == 0, "Streetlamps should be off at 10:30 AM (active=%d)" % atm.get_active_streetlamp_count())
	_assert_true(cw.mats.lamp_glow_mat.emission_energy_multiplier < 0.5, "Streetlamp emissive material unexpectedly bright in daylight")

	atm.set_time_of_day(18.2, true)
	_assert_true(atm.sun_elevation > 0.01 and atm.sun_elevation < 0.25 and sun.light_energy > 0.05, "18:12 Golden Hour failed low warm sun bounds (el=%.3f, energy=%.2f)" % [atm.sun_elevation, sun.light_energy])

	var spawn_ref := plan.blueprints[0].get_approach_world_pos()
	player.place_at(Vector3(spawn_ref.x, plan.blueprints[0].sidewalk_y + 0.1, spawn_ref.z), 0.0)
	atm.set_time_of_day(23.5, true)
	_assert_true(atm.sun_elevation < -0.35 and atm.night_factor > 0.90, "23:30 night failed deep night thresholds (el=%.2f, nf=%.2f)" % [atm.sun_elevation, atm.night_factor])
	_assert_true(not sun.shadow_enabled and atm.moon_light.shadow_enabled, "Nighttime shadow exclusivity failed (sun=%s, moon=%s)" % [sun.shadow_enabled, atm.moon_light.shadow_enabled])
	var night_lamps := atm.get_active_streetlamp_count()
	_assert_true(night_lamps > 0 and night_lamps <= AtmosphereController.STREETLIGHT_POOL_SIZE, "Expected 1..%d pooled night streetlamps, got %d" % [AtmosphereController.STREETLIGHT_POOL_SIZE, night_lamps])
	for spot in atm._lamp_spots:
		_assert_true(not spot.shadow_enabled, "Pooled streetlamp SpotLight3D must keep shadow_enabled=false for Forward+ budget")
	_assert_true(cw.mats.lamp_glow_mat.emission_energy_multiplier > 3.5 and cw.mats.ev_headlight_mat.emission_energy_multiplier > 2.5, "Nighttime emissive boost missing on streetlamps/EV headlights")
	_assert_true(cw.mats.sign_panel_mat.emission_energy_multiplier > 1.1 and cw.mats.aviation_beacon_mat.emission_energy_multiplier > 3.2, "Nighttime emissive boost missing on signage/aviation beacons")

	for preset in AtmosphereController.TIME_PRESETS:
		atm.set_time_of_day(float(preset["hour"]), true)
		_assert_true(not (sun.shadow_enabled and atm.moon_light.shadow_enabled), "Dual directional shadows active simultaneously at preset %s" % preset["name"])

	# 6b. Weather state machine: wetting during rain, drying on clear, lightning pulse
	atm.set_weather("clear", true)
	_assert_true(atm.weather_rain < 0.01 and atm.weather_wetness < 0.01 and atm.weather_puddles < 0.01, "Clear immediate reset left residual rain/wetness")
	atm.set_weather("rain", false)
	for _s in range(14):
		atm.step_simulation(0.5)
	_assert_true(atm.weather_rain > 0.55 and atm.weather_wetness > 0.45 and atm.weather_puddles > 0.18, "Rain wetting physics failed (rain=%.2f wet=%.2f pud=%.2f)" % [atm.weather_rain, atm.weather_wetness, atm.weather_puddles])

	atm.set_weather("clear", false)
	for _s in range(36):
		atm.step_simulation(0.5)
	_assert_true(atm.weather_rain < 0.04 and atm.weather_wetness < 0.35, "Drying physics failed after storm cleared (rain=%.2f wet=%.2f)" % [atm.weather_rain, atm.weather_wetness])

	atm.set_weather("thunderstorm", true)
	atm.trigger_lightning(1.0)
	_assert_true(atm.weather_lightning >= 0.90, "Lightning trigger failed to spike weather_lightning")
	atm.step_simulation(0.35)
	_assert_true(atm.weather_lightning < 0.25, "Lightning flash failed rapid decay (%.2f)" % atm.weather_lightning)

	# 6c. OBB indoor rain exclusion & grounded splash verification
	var test_bp := plan.blueprints[0]
	var indoor_pt := test_bp.local_to_world_3d(Vector3(0.0, 0.9, 0.0))
	var sidewalk_pt := test_bp.get_approach_world_pos() + Vector3(0.0, 0.9, 0.0)
	_assert_true(atm.is_point_sheltered(indoor_pt), "Interior building center incorrectly reported as unsheltered")
	_assert_true(not atm.is_point_sheltered(sidewalk_pt), "Open front sidewalk incorrectly reported as sheltered")

	player.place_at(Vector3(sidewalk_pt.x, test_bp.sidewalk_y + 0.1, sidewalk_pt.z), 0.0)
	atm.step_simulation(0.02)
	await physics_frame
	var gp_list := RenderingServer.global_shader_parameter_get_list()
	for g_name in [&"time_of_day_hour", &"night_factor", &"sun_elevation", &"weather_rain", &"weather_snow", &"weather_snow_depth", &"weather_slush", &"weather_wetness", &"weather_puddles", &"weather_cloud_cover", &"weather_lightning", &"wind_vector"]:
		_assert_true(gp_list.has(g_name), "Missing registered shader global %s in project.godot" % g_name)
	if DisplayServer.get_name() != "headless":
		var global_rain_val: Variant = RenderingServer.global_shader_parameter_get(&"weather_rain")
		_assert_true(global_rain_val != null and float(global_rain_val) > 0.85, "RenderingServer global shader param weather_rain not updated")
	_assert_true(atm.weather_rain > 0.85 and atm._rain_particles != null and atm._rain_particles.emitting, "Rain GPUParticles3D should be emitting during thunderstorm")
	_assert_true(atm._splash_mmi != null and atm._splash_mmi.multimesh.visible_instance_count >= 16, "Rain splash MultiMesh should activate outdoors during thunderstorm")

	# 6c2. Expanded 10-preset weather, snow piling accumulation & melt-to-slush/wetness physics + CoastalOceanWater & Underwater check
	_assert_true(AtmosphereController.WEATHER_ORDER.size() >= 10, "Expected >= 10 weather presets, got %d" % AtmosphereController.WEATHER_ORDER.size())
	_assert_true(cw.find_child("CoastalOceanWater", true, false) != null, "Missing coastal CoastalOceanWater mesh in live scene")
	var fish_mmi := cw.find_child("UnderwaterFishSchools", true, false) as MultiMeshInstance3D
	_assert_true(fish_mmi != null and fish_mmi.multimesh != null and fish_mmi.multimesh.instance_count >= 80, "Missing or underpopulated UnderwaterFishSchools MultiMesh")

	# Verify diving underwater engages submerged state, underwater medium fog & God-ray overlay, and surfacing restores dry air
	var uw_x := plan.config.world_size * 0.36
	var uw_z := plan.terrain.get_beach_shore_z(uw_x) + 38.0
	player.place_at(Vector3(uw_x, plan.terrain.water_level - 3.0, uw_z), 0.0)
	atm.step_simulation(0.02)
	_assert_true(player.camera_submerged and atm.is_camera_underwater and w_env.environment.fog_depth_end < 60.0, "Submerged underwater camera medium failed to activate")
	player.place_at(Vector3(sidewalk_pt.x, test_bp.sidewalk_y + 0.1, sidewalk_pt.z), 0.0)
	atm.step_simulation(0.02)
	_assert_true(not player.camera_submerged and not atm.is_camera_underwater and w_env.environment.fog_depth_end > 500.0, "Surfacing from underwater failed to restore dry air fog")
	atm.set_weather("fog", true)
	_assert_true(atm.weather_cloud_cover >= 0.65 and atm.weather_rain < 0.05 and atm.weather_snow < 0.05 and w_env.environment.fog_density > 0.002, "Fog preset unexpected values")
	atm.set_weather("drizzle", true)
	_assert_true(atm.weather_rain > 0.20 and atm.weather_rain < 0.50 and atm.weather_wetness > 0.40, "Drizzle preset unexpected values")
	atm.set_weather("sleet", true)
	_assert_true(atm.weather_rain > 0.30 and atm.weather_snow > 0.35 and atm.weather_slush > 0.55 and atm.weather_wetness > 0.55, "Sleet preset unexpected values")

	# Gradual snow accumulation from clear -> blizzard, then melting to slush & wetness on clear
	atm.set_weather("clear", true)
	_assert_true(atm.weather_snow_depth < 0.01 and atm.weather_slush < 0.01, "Clear immediate reset left residual snow/slush")
	atm.set_weather("blizzard", false)
	for _sn in range(42):
		atm.step_simulation(0.5)
	_assert_true(atm.weather_snow > 0.80 and atm.weather_snow_depth >= 0.70, "Blizzard snow piling failed (snow=%.2f depth=%.2f)" % [atm.weather_snow, atm.weather_snow_depth])
	_assert_true(atm._snow_particles != null and atm._snow_particles.emitting, "Snow GPUParticles3D should be emitting during blizzard")
	atm.set_weather("clear", false)
	var peak_melt_wet := 0.0
	var peak_melt_slush := 0.0
	for _ml in range(28):
		atm.step_simulation(0.5)
		peak_melt_wet = maxf(peak_melt_wet, atm.weather_wetness)
		peak_melt_slush = maxf(peak_melt_slush, atm.weather_slush)
	_assert_true(atm.weather_snow_depth < 0.55 and peak_melt_wet > 0.25 and peak_melt_slush > 0.20, "Snow melt-to-slush/wetness transition failed (depth=%.2f peak_wet=%.2f peak_slush=%.2f)" % [atm.weather_snow_depth, peak_melt_wet, peak_melt_slush])

	# 6d. Atmosphere + Weather (including snow accumulation) state persistence round-trip (F5 / F9)
	var atm_save := "user://validate_milestone3_atm_save.json"
	atm.set_time_of_day(22.75, true)
	atm.set_weather("snow", true)
	_assert_true(cw.save_to_disk(player.global_position, player._yaw, atm_save, atm.get_state_dict()), "Milestone 3 save_to_disk failed")

	atm.time_paused = false
	atm.set_time_of_day(11.0, false)
	atm.set_weather("clear", true)
	var reloaded := cw.load_from_disk(atm_save)
	_assert_true(not reloaded.is_empty() and reloaded.get("changed_world_state", {}).has("atmosphere"), "Reloaded JSON missing changed_world_state.atmosphere")
	atm.apply_state_dict(reloaded["changed_world_state"]["atmosphere"])
	_assert_true(absf(atm.time_of_day_hour - 22.75) < 0.02 and atm.time_paused, "Persisted time_of_day_hour/paused failed round-trip (h=%.2f paused=%s)" % [atm.time_of_day_hour, atm.time_paused])
	_assert_true(atm.weather_preset == "snow" and atm.weather_snow_depth > 0.65, "Persisted snow preset/depth failed round-trip (%s depth=%.2f)" % [atm.weather_preset, atm.weather_snow_depth])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(atm_save))

	print("Atmosphere & Weather validation passed (lamps=%d, presets=%d, melt_wet=%.2f, melt_slush=%.2f)" % [night_lamps, AtmosphereController.WEATHER_ORDER.size(), peak_melt_wet, peak_melt_slush])


func _test_traffic_and_npc_schedules(cw: CityWorld, plan: CityPlan) -> void:
	# 7a. Multi-lane 4-lane arterial lane graph verification
	var dual_lanes := 0
	var linked_adj := 0
	for lane in plan.road_graph.lanes:
		if lane.lane_count == 2:
			dual_lanes += 1
			if lane.adjacent_lane_id >= 0 and lane.adjacent_lane_id < plan.road_graph.lanes.size():
				var adj := plan.road_graph.lanes[lane.adjacent_lane_id]
				if adj.adjacent_lane_id == lane.id and adj.edge_id == lane.edge_id:
					linked_adj += 1
	_assert_true(dual_lanes >= 16, "Expected >= 16 dual-lane arterial segments, got %d" % dual_lanes)
	_assert_true(linked_adj == dual_lanes, "Expected all dual-lane arterial segments to have symmetric adjacent_lane_id (%d/%d)" % [linked_adj, dual_lanes])

	# 7b. TrafficManager IDM/MOBIL multi-type fleet & diurnal demand scaling
	var tm: Node3D = cw.traffic_manager
	var cm: Node3D = cw.crowd_manager
	_assert_true(tm != null and cm != null, "TrafficManager or CrowdManager missing from CityWorld")
	if tm == null or cm == null:
		return

	_assert_true(tm.get_vehicle_count() >= 300, "Expected >= 300 pooled procedural vehicles, got %d" % tm.get_vehicle_count())
	var ref_cam := plan.spawn_position

	# Test 03:00 Night Quiet vs 08:10 Morning Rush demand scaling
	tm.step(0.05, ref_cam, 1.0, 3.0, 0.0, 0.0)
	for _nt in range(8):
		tm.step(0.04, ref_cam, 1.0, 3.0, 0.0, 0.0)
	var night_stats: Dictionary = tm.get_traffic_stats()

	tm.step(0.05, ref_cam, 0.0, 8.1, 0.0, 0.0)
	for _rt in range(60):
		cm.step(0.04, ref_cam, 0.0, 8.1, 0.0)
		tm.step(0.04, ref_cam, 0.0, 8.1, 0.0, 0.0)
	var rush_stats: Dictionary = tm.get_traffic_stats()
	_assert_true(int(rush_stats["active"]) > int(night_stats["active"]) + 80, "Diurnal traffic demand did not scale between 03:00 (%d) and 08:10 rush (%d)" % [int(night_stats["active"]), int(rush_stats["active"])])
	_assert_true(int(rush_stats["moving"]) >= 40, "Expected >= 40 moving IDM vehicles during morning rush, got %d" % int(rush_stats["moving"]))
	_assert_true(int(rush_stats["buses"]) >= 4, "Expected >= 4 active city transit buses during rush hour, got %d" % int(rush_stats["buses"]))

	# Verify finite non-NaN vehicle positions within map bounds
	var bad_veh := 0
	for vi in range(tm.get_vehicle_count()):
		var vp: Vector3 = tm._v_pos[vi]
		if not vp.is_finite() or vp.x < -10.0 or vp.x > plan.config.world_size + 10.0 or vp.z < -10.0 or vp.z > plan.config.world_size + 10.0:
			bad_veh += 1
	_assert_true(bad_veh == 0, "TrafficManager had %d out-of-bounds or NaN vehicles" % bad_veh)

	# 7c. NPCScheduler PedestrianGraph + 24h Citizen Daily Schedules + Rain Umbrellas
	_assert_true(cm.scheduler != null and cm.scheduler.nodes.size() >= 120 and cm.scheduler.edges.size() >= 160, "PedestrianGraph too small (nodes=%d, edges=%d)" % [cm.scheduler.nodes.size() if cm.scheduler != null else 0, cm.scheduler.edges.size() if cm.scheduler != null else 0])
	_assert_true(cm.scheduler.get_crosswalk_edge_count() >= 20, "Expected >= 20 connected pedestrian crosswalk edges, got %d" % cm.scheduler.get_crosswalk_edge_count())
	_assert_true(cm.get_pedestrian_count() >= 500, "Expected >= 500 scheduled procedural citizens, got %d" % cm.get_pedestrian_count())

	# 03:00 AM -> majority of citizens indoors sleeping
	cm.step(0.04, ref_cam, 1.0, 3.0, 0.0)
	var c_night: Dictionary = cm.get_crowd_stats()
	_assert_true(int(c_night["indoors"]) > int(c_night["outdoor"]) * 2, "At 03:00 AM most citizens should be indoors sleeping (indoors=%d, outdoor=%d)" % [int(c_night["indoors"]), int(c_night["outdoor"])])

	# 07:45 AM Morning Commute -> surge of outdoor walkers/bus commuters!
	cm.step(0.04, ref_cam, 0.0, 7.75, 0.0)
	for _mc in range(25):
		cm.step(0.04, ref_cam, 0.0, 7.75, 0.0)
		tm.step(0.04, ref_cam, 0.0, 7.75, 0.0, 0.0)
	var c_morn: Dictionary = cm.get_crowd_stats()
	_assert_true(int(c_morn["outdoor"]) > int(c_night["outdoor"]) + 100, "Morning commute at 07:45 did not mobilize outdoor citizens (morn=%d vs night=%d)" % [int(c_morn["outdoor"]), int(c_night["outdoor"])])

	# 12:30 PM Lunch Peak with Rain -> active lunch crowds + umbrellas deployed!
	cm.step(0.04, ref_cam, 0.0, 12.5, 0.80)
	for _lc in range(15):
		cm.step(0.04, ref_cam, 0.0, 12.5, 0.80)
	var c_lunch_rain: Dictionary = cm.get_crowd_stats()
	_assert_true(int(c_lunch_rain["outdoor"]) >= 120, "Expected >= 120 active outdoor citizens at 12:30 lunch rush, got %d" % int(c_lunch_rain["outdoor"]))
	_assert_true(int(c_lunch_rain["umbrellas"]) >= 50, "Expected >= 50 rain umbrellas deployed during rain (got %d)" % int(c_lunch_rain["umbrellas"]))

	# Verify city-wide dynamic MultiMeshInstance3D nodes do NOT use visibility_range_end (which culls by city center!)
	for mgr_node in [tm, cm]:
		for ch in mgr_node.get_children():
			if ch is MultiMeshInstance3D:
				_assert_true((ch as MultiMeshInstance3D).visibility_range_end == 0.0, "City-wide MultiMesh %s/%s must not use visibility_range_end (would cull outer districts)" % [mgr_node.name, ch.name])

	# Verify no outdoor citizen is placed inside creek water or non-finite coordinates
	var bad_peds := 0
	for pi in range(cm.get_pedestrian_count()):
		if cm._p_state[pi] == 0: # STATE_INDOORS
			continue
		var pp: Vector3 = cm._p_pos[pi]
		if not pp.is_finite() or pp.y < plan.terrain.water_level + 0.15:
			bad_peds += 1
	_assert_true(bad_peds == 0, "CrowdManager had %d outdoor citizens below water level or NaN" % bad_peds)

	print("Traffic & Scheduled NPC validation passed: dual_lanes=%d, rush_cars=%d (night=%d, LC=%d), ped_graph=%dN/%dE/%dCW, npc_outdoor(night=%d, morn=%d, lunch_rain=%d, umbrellas=%d)" % [
		dual_lanes,
		int(rush_stats["active"]),
		int(night_stats["active"]),
		int(rush_stats["lane_changes"]),
		cm.scheduler.nodes.size(),
		cm.scheduler.edges.size(),
		cm.scheduler.get_crosswalk_edge_count(),
		int(c_night["outdoor"]),
		int(c_morn["outdoor"]),
		int(c_lunch_rain["outdoor"]),
		int(c_lunch_rain["umbrellas"]),
	])


func _test_performance_controls(cw: CityWorld, plan: CityPlan, player: PlayerController, root: Node3D) -> void:
	var PerfScript := preload("res://src/city_world/player/performance_controller.gd")
	var wenv := WorldEnvironment.new()
	var sun := DirectionalLight3D.new()
	var atm := AtmosphereController.new()
	root.add_child(wenv)
	root.add_child(sun)
	root.add_child(atm)
	atm.setup(wenv, sun, cw, player)

	var perf: CanvasLayer = PerfScript.new()
	root.add_child(perf)
	perf.setup(cw, atm, player, false)

	# Verify High preset wet-only SSR gating: OFF on clear dry day, ON during rain
	perf.apply_preset("high", false)
	atm.set_weather("clear", true)
	_assert_true(wenv.environment != null and not wenv.environment.ssr_enabled, "High preset wet-only SSR should stay OFF on dry clear day")
	atm.set_weather("rain", true)
	_assert_true(wenv.environment != null and wenv.environment.ssr_enabled, "High preset wet-only SSR should turn ON during rain")

	var high_chunks := cw.get_visible_chunk_count()
	var tm: Node3D = cw.traffic_manager
	var cm: Node3D = cw.crowd_manager
	tm.step(0.04, plan.spawn_position, 0.0, 8.1, 0.0, 0.0)
	cm.step(0.04, plan.spawn_position, 0.0, 8.1, 0.0)
	var high_cars := int(tm.get_traffic_stats()["active"])
	var high_peds := int(cm.get_crowd_stats()["outdoor"])

	# Verify Low preset aggressively reduces chunks, shadows, SSAO/SSR, and traffic/crowd load
	perf.apply_preset("low", false)
	var low_chunks := cw.get_visible_chunk_count()
	_assert_true(low_chunks < high_chunks and low_chunks > 0, "Low preset chunk distance culling did not trim visible chunks (%d vs high=%d)" % [low_chunks, high_chunks])
	_assert_true(not wenv.environment.ssao_enabled and not wenv.environment.ssr_enabled and not wenv.environment.glow_enabled, "Low preset must disable SSAO, SSR, and Glow")
	tm.step(0.04, plan.spawn_position, 0.0, 8.1, 0.0, 0.0)
	cm.step(0.04, plan.spawn_position, 0.0, 8.1, 0.0)
	var low_cars := int(tm.get_traffic_stats()["active"])
	var low_peds := int(cm.get_crowd_stats()["outdoor"])
	_assert_true(low_cars < high_cars, "Low preset did not scale down active traffic (%d vs high=%d)" % [low_cars, high_cars])
	_assert_true(low_peds < high_peds, "Low preset did not scale down outdoor NPC crowd (%d vs high=%d)" % [low_peds, high_peds])

	# Verify Ultra preset enables full range + interior probes cleanly
	perf.apply_preset("ultra", false)
	_assert_true(cw.enable_interior_probes and wenv.environment.ssr_enabled, "Ultra preset did not enable interior probes & always-on SSR")
	_assert_true(perf.get_hud_summary().contains("Perf: Ultra"), "PerformanceController HUD summary missing active preset label")

	perf.queue_free()
	atm.queue_free()
	sun.queue_free()
	wenv.queue_free()
	print("Performance & Lag Control validation passed: chunks(low=%d, high=%d/%d), cars(low=%d, high=%d), npcs(low=%d, high=%d)" % [
		low_chunks, high_chunks, cw.chunk_roots.size(), low_cars, high_cars, low_peds, high_peds
	])


func _find_elevator_for_building(root: Node, bld_id: String) -> InteractiveElevator:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is InteractiveElevator and (cur as InteractiveElevator).building_id == bld_id:
			return cur as InteractiveElevator
		for ch in cur.get_children():
			stack.append(ch)
	return null


func _bfs_floor_waypoints(start2: Vector2, goal2: Vector2, y_lvl: float, f_data: Dictionary, bp: BuildingBlueprint, ib: InteriorBlueprint) -> Array[Vector3]:
	var w_span := ib.inner_max.x - ib.inner_min.x
	var d_span := ib.inner_max.y - ib.inner_min.y
	var cell_sz := maxf(0.25, maxf(w_span, d_span) / 140.0)
	var gx := maxi(4, int(ceil(w_span / cell_sz)))
	var gz := maxi(4, int(ceil(d_span / cell_sz)))
	var blocked := PackedByteArray()
	blocked.resize(gx * gz)
	blocked.fill(0)

	if bool(ib.elevator.get("enabled", false)):
		var er: Rect2 = ib.elevator["shaft_rect"]
		InteriorGenerator._mark_box_blocked(blocked, gx, gz, ib.inner_min, cell_sz, er.get_center(), er.size, 0.34)
	for part in f_data.get("partitions", []):
		if String(part.get("role", "")) == "header":
			continue
		var pos_p: Vector3 = part["pos"]
		var sz_p: Vector3 = part["size"]
		InteriorGenerator._mark_box_blocked(blocked, gx, gz, ib.inner_min, cell_sz, Vector2(pos_p.x, pos_p.z), Vector2(sz_p.x, sz_p.z), 0.34)
	for gr in f_data.get("guardrails", []):
		var pos_g: Vector3 = gr["pos"]
		var sz_g: Vector3 = gr["size"]
		InteriorGenerator._mark_box_blocked(blocked, gx, gz, ib.inner_min, cell_sz, Vector2(pos_g.x, pos_g.z), Vector2(sz_g.x, sz_g.z), 0.32)
	for fn in f_data.get("furniture", []):
		var pos_f: Vector3 = fn["pos"]
		var sz_f: Vector3 = fn["size"]
		var rot_xz := FurnitureGenerator.get_rotated_xz_size(sz_f, float(fn.get("yaw", 0.0)))
		InteriorGenerator._mark_box_blocked(blocked, gx, gz, ib.inner_min, cell_sz, Vector2(pos_f.x, pos_f.z), rot_xz, 0.34)

	var sx := clampi(int(floor((start2.x - ib.inner_min.x) / cell_sz)), 0, gx - 1)
	var sz_i := clampi(int(floor((start2.y - ib.inner_min.y) / cell_sz)), 0, gz - 1)
	var tx := clampi(int(floor((goal2.x - ib.inner_min.x) / cell_sz)), 0, gx - 1)
	var tz := clampi(int(floor((goal2.y - ib.inner_min.y) / cell_sz)), 0, gz - 1)
	var s_idx := sz_i * gx + sx
	var t_idx := tz * gx + tx
	blocked[s_idx] = 0
	blocked[t_idx] = 0

	var parent := PackedInt32Array()
	parent.resize(gx * gz)
	parent.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(gx * gz)
	queue[0] = s_idx
	parent[s_idx] = s_idx
	var head := 0
	var tail := 1
	var found := (s_idx == t_idx)
	while head < tail and not found:
		var cur := queue[head]
		head += 1
		var cx := cur % gx
		var cz := cur / gx
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := cx + step.x
			var nz := cz + step.y
			if nx < 0 or nx >= gx or nz < 0 or nz >= gz:
				continue
			var nidx := nz * gx + nx
			if blocked[nidx] != 0 or parent[nidx] != -1:
				continue
			parent[nidx] = cur
			if nidx == t_idx:
				found = true
				break
			queue[tail] = nidx
			tail += 1

	if not found:
		return [bp.local_to_world_3d(Vector3(goal2.x, y_lvl, goal2.y))]
	var rev: Array[int] = []
	var c := t_idx
	while c != s_idx:
		rev.append(c)
		c = parent[c]
	rev.reverse()
	var out: Array[Vector3] = []
	var prev_dir := Vector2i.ZERO
	var prev_cell := Vector2i(sx, sz_i)
	for i in range(rev.size()):
		var ci := rev[i]
		var cc := Vector2i(ci % gx, ci / gx)
		var dir := cc - prev_cell
		if i > 0 and dir != prev_dir:
			var turn_pt := Vector2(ib.inner_min.x + (float(prev_cell.x) + 0.5) * cell_sz, ib.inner_min.y + (float(prev_cell.y) + 0.5) * cell_sz)
			out.append(bp.local_to_world_3d(Vector3(turn_pt.x, y_lvl, turn_pt.y)))
		prev_dir = dir
		prev_cell = cc
	out.append(bp.local_to_world_3d(Vector3(goal2.x, y_lvl, goal2.y)))
	return out
