class_name BuildingBuilder
extends RefCounted

## Builds physical collision shapes, visual architecture, interior entry vestibules,
## roofs/solar arrays, and interactive doors from an authoritative BuildingBlueprint.

static func build_building(bp: BuildingBlueprint, mats: MaterialLibrary) -> Dictionary:
	var root := Node3D.new()
	root.name = bp.id
	root.position = Vector3(bp.center.x, bp.base_y, bp.center.y)
	root.rotation.y = bp.yaw
	root.set_meta("blueprint", bp)

	var body := StaticBody3D.new()
	body.name = "BuildingBody"
	body.set_meta("blueprint", bp)
	root.add_child(body)

	var wall_mat := mats.get_wall_material(bp.wall_color, bp.style)
	var trim_mat := mats.get_wall_material(bp.trim_color, "contemporary_2028")
	var accent_mat := mats.get_accent_material(bp.accent_color, false)

	var wall_st := SurfaceTool.new()
	wall_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var roof_wall_st := SurfaceTool.new()
	roof_wall_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var foundation_st := SurfaceTool.new()
	foundation_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var vest_wall_st := SurfaceTool.new()
	vest_wall_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var vest_floor_st := SurfaceTool.new()
	vest_floor_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var roof_st := SurfaceTool.new()
	roof_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var trim_st := SurfaceTool.new()
	trim_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var ext_trim_st := SurfaceTool.new()
	ext_trim_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var glass_dark_st := SurfaceTool.new()
	glass_dark_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var glass_warm_st := SurfaceTool.new()
	glass_warm_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var solar_st := SurfaceTool.new()
	solar_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var detail_sts := {}
	for dk in ["dark_metal", "light_metal", "balcony_glass", "accent", "accent_glow", "beacon", "asphalt", "yellow_mark", "amber_sig", "stained_glass", "limestone", "gold", "police_blue", "emergency_red", "cedar", "medical_teal"]:
		var dst := SurfaceTool.new()
		dst.begin(Mesh.PRIMITIVE_TRIANGLES)
		detail_sts[dk] = dst

	var ext_root := Node3D.new()
	ext_root.name = "ExteriorModeRoot"
	root.add_child(ext_root)

	var ext_wall_body := StaticBody3D.new()
	ext_wall_body.name = "ExteriorWallBody"
	ext_wall_body.set_meta("building_id", bp.id)
	ext_root.add_child(ext_wall_body)

	# 1. Build authoritative colliders and matching solid structural boxes.
	var boxes := bp.get_collider_boxes_local()
	for b in boxes:
		var pos: Vector3 = b["pos"]
		var size: Vector3 = b["size"]
		var role: String = b["role"]

		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.position = pos

		if role == "foundation":
			body.add_child(cs)
			_emit_box(foundation_st, pos, size)
		elif role == "vestibule_floor":
			body.add_child(cs)
			_emit_box(vest_floor_st, pos, size)
		elif role == "roof_slab":
			body.add_child(cs)
			_emit_box(trim_st, pos, size)
		elif role == "vestibule_ceiling":
			ext_wall_body.add_child(cs)
			_emit_box(vest_wall_st, pos, size)
		else:
			ext_wall_body.add_child(cs)
			_emit_box(wall_st, pos, size)

	# 2. Build entrance approach ramp connecting sidewalk_y cleanly to base_y (local y = 0).
	_build_entrance_approach(bp, body, foundation_st, trim_st)

	# 3. Build vestibule interior lining & warm ceiling light strip (distant mode shell).
	_build_vestibule_details(bp, vest_wall_st, trim_st, ext_trim_st, glass_warm_st, root)

	# 4. Build architectural facade elements: windows, storefront, awning, balconies, signage, porches, setbacks.
	_build_facade_details(bp, body, roof_st, trim_st, foundation_st, glass_dark_st, glass_warm_st, detail_sts, mats, root)

	# 5. Build roof geometry + collider + solar panels + crown/helipad/beacons.
	_build_roof(bp, body, roof_st, roof_wall_st, trim_st, solar_st, detail_sts, glass_dark_st, glass_warm_st, mats, root)

	# 5b. Add exterior-only BoxOccluder3D hulls inside ExteriorModeRoot for >=3-floor & wide 2-floor buildings.
	if bp.floors >= 3 or (bp.floors >= 2 and bp.width >= 9.0 and bp.depth >= 9.0):
		_add_building_occluders(bp, ext_root)

	# Commit batched surfaces into MeshInstance3Ds with distance culling & selective shadow casters.
	# Tall towers (>=6 floors) stay visible out to 1050m to preserve a dramatic full-city skyline silhouette!
	var skyline_vis := 1050.0 if bp.floors >= 6 else 620.0
	var glass_vis := 720.0 if bp.floors >= 6 else 310.0
	var found_mi := _commit(foundation_st, "FoundationMesh", mats.foundation_mat, root, false, 560.0, 40.0)
	if found_mi != null:
		found_mi.set_layer_mask_value(2, true)
	var walls_mi := _commit(wall_st, "WallsMesh", wall_mat, ext_root, true, skyline_vis, 65.0)
	if walls_mi != null:
		walls_mi.set_instance_shader_parameter("wall_color", bp.wall_color)
	var roof_walls_mi := _commit(roof_wall_st, "RoofStructuresWallMesh", wall_mat, root, true, skyline_vis * 0.85, 45.0)
	if roof_walls_mi != null:
		roof_walls_mi.set_instance_shader_parameter("wall_color", bp.wall_color)
	_commit(vest_wall_st, "VestibuleWallsMesh", mats.vestibule_wall_mat, ext_root, false, 95.0, 14.0)
	_commit(vest_floor_st, "VestibuleFloorMesh", mats.vestibule_floor_mat, root, false, 95.0, 14.0)
	_commit(roof_st, "RoofMesh", mats.roof_shingle_mat if bp.roof_type == "gable" or bp.roof_type == "hip" else mats.roof_membrane_mat, root, true, skyline_vis, 65.0)
	var trim_mi := _commit(trim_st, "TrimMesh", trim_mat, root, false, 300.0, 28.0)
	if trim_mi != null:
		trim_mi.set_instance_shader_parameter("wall_color", bp.trim_color)
	var ext_trim_mi := _commit(ext_trim_st, "ExteriorTrimMesh", trim_mat, ext_root, false, 300.0, 28.0)
	if ext_trim_mi != null:
		ext_trim_mi.set_instance_shader_parameter("wall_color", bp.trim_color)
	_commit(glass_dark_st, "GlassDarkMesh", mats.glass_dark_mat, ext_root, false, glass_vis, 34.0)
	_commit(glass_warm_st, "GlassWarmMesh", mats.glass_warm_mat, ext_root, false, glass_vis, 34.0)
	_commit(detail_sts["stained_glass"], "StainedGlassMesh", mats.stained_glass_mat, ext_root, false, 320.0, 28.0)
	_commit(solar_st, "SolarPanelsMesh", mats.solar_panel_mat, root, false, 300.0, 28.0)
	_commit(detail_sts["dark_metal"], "DetailDarkMetalMesh", mats.dark_metal_mat, root, false, 360.0, 32.0)
	_commit(detail_sts["light_metal"], "DetailLightMetalMesh", mats.light_metal_mat, root, false, 320.0, 28.0)
	_commit(detail_sts["balcony_glass"], "BalconyGlassMesh", mats.clear_glass_mat, root, false, 400.0, 28.0)
	_commit(detail_sts["limestone"], "LimestoneArchitecturalMesh", mats.limestone_mat, root, true, 420.0, 36.0)
	_commit(detail_sts["gold"], "GoldFinialMesh", mats.gold_metal_mat, root, false, 480.0, 36.0)
	_commit(detail_sts["police_blue"], "PoliceBlueMesh", mats.police_blue_mat, root, false, 360.0, 32.0)
	_commit(detail_sts["emergency_red"], "EmergencyRedMesh", mats.emergency_red_mat, root, false, 360.0, 32.0)
	_commit(detail_sts["cedar"], "RooftopCedarMesh", mats.wood_cedar_mat, root, true, 480.0, 34.0)
	_commit(detail_sts["medical_teal"], "MedicalTealMesh", mats.medical_teal_mat, root, false, 320.0, 28.0)
	_commit(detail_sts["accent"], "DetailAccentMesh", accent_mat, root, false, 360.0, 26.0)
	_commit(detail_sts["accent_glow"], "SignAccentGlowMesh", mats.get_accent_material(bp.accent_color, true), root, false, 360.0, 32.0)
	_commit(detail_sts["beacon"], "AviationBeaconsMesh", mats.aviation_beacon_mat, root, false, 520.0, 40.0)
	_commit(detail_sts["asphalt"], "HelipadDeckMesh", mats.asphalt_mat, root, false, 420.0, 36.0)
	_commit(detail_sts["yellow_mark"], "HelipadMarkingsMesh", mats.marking_yellow_mat, root, false, 360.0, 32.0)
	_commit(detail_sts["amber_sig"], "HelipadLightsMesh", mats.signal_amber_mat, root, false, 360.0, 32.0)

	root.set_meta("wall_mat", wall_mat)
	root.set_meta("trim_mat", trim_mat)
	root.set_meta("exterior_root", ext_root)
	root.set_meta("exterior_wall_body", ext_wall_body)
	root.set_meta("interior_active", false)

	# 6. Instantiate hinged InteractiveDoor at the doorway.
	var door := InteractiveDoor.new()
	var is_commercial := BuildingBlueprint.is_commercial_archetype(bp.archetype)
	door.setup(bp.door_id, bp.id, bp.door_width, bp.door_height, is_commercial, mats)
	door.position = Vector3(bp.door_local_x - bp.door_width * 0.5, 0.0, bp.depth * 0.5 - bp.wall_thickness * 0.5)
	root.add_child(door)

	return {
		"node": root,
		"door": door,
	}


static func set_exterior_mode(building_root: Node3D, active_exterior: bool) -> void:
	if building_root == null:
		return
	var ext_root: Node3D = building_root.get_meta("exterior_root", null)
	if ext_root != null:
		ext_root.visible = active_exterior
	var ext_body: StaticBody3D = building_root.get_meta("exterior_wall_body", null)
	if ext_body != null:
		ext_body.collision_layer = 1 if active_exterior else 0
		ext_body.collision_mask = 1 if active_exterior else 0
		for child in ext_body.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = not active_exterior


static func get_facade_window_openings(bp: BuildingBlueprint) -> Array[Dictionary]:
	var openings: Array[Dictionary] = []
	var hw := bp.width * 0.5
	var hd := bp.depth * 0.5
	var wall_h := bp.get_total_wall_height()
	var d_x0 := bp.door_local_x - bp.door_width * 0.5
	var d_x1 := bp.door_local_x + bp.door_width * 0.5
	var h_hash: int = absi(bp.id.hash())

	if bp.archetype == "church":
		# Tall jewel-toned lancet stained-glass windows along side walls & chancel behind altar
		var n_lancets := clampi(int(floor((bp.depth - 4.2) / 3.4)), 2, 6)
		for s_i in range(n_lancets):
			var frac_s := (float(s_i) + 0.5) / float(n_lancets)
			var wz := lerpf(-hd + 2.0, hd - maxf(3.2, bp.vestibule_depth + 1.0), frac_s)
			for side_face in ["left", "right"]:
				openings.append({
					"face": side_face,
					"floor": 0,
					"u_center": wz,
					"y_center": 3.35,
					"width": 1.12,
					"height": 3.05,
					"warm": true,
					"stained_glass": true,
					"storefront_mullion": false,
				})
		# Chancel triple/wide altar reredos window high above altar table
		openings.append({
			"face": "back",
			"floor": 0,
			"u_center": 0.0,
			"y_center": 3.65,
			"width": minf(3.0, bp.width * 0.28),
			"height": 2.75,
			"warm": true,
			"stained_glass": true,
			"storefront_mullion": false,
		})
		# Flanking front facade tall chapel lancets
		if bp.width >= 9.6:
			for sx: float in [-1.0, 1.0]:
				var fx: float = sx * minf(hw - 1.55, d_x1 + 1.85)
				if absf(fx - bp.door_local_x) > bp.door_width * 0.8 + 0.85:
					openings.append({
						"face": "front",
						"floor": 0,
						"u_center": fx,
						"y_center": 3.15,
						"width": 0.92,
						"height": 2.45,
						"warm": true,
						"stained_glass": true,
						"storefront_mullion": false,
					})
		return openings

	var is_commercial := BuildingBlueprint.is_commercial_archetype(bp.archetype)
	if is_commercial and bp.archetype != "fire_station" and bp.archetype != "municipal_hall":
		var left_span := (d_x0 - 0.35) - (-hw + 0.5)
		_append_retail_bay_openings(openings, "front", -hw + 0.5, d_x0 - 0.35, bp.ground_floor_height, 0.44, h_hash, 1)
		_append_retail_bay_openings(openings, "front", d_x1 + 0.35, hw - 0.5, bp.ground_floor_height, 0.44, h_hash, 17)
		if bp.secondary_front_face in ["left", "right"]:
			var sec_z0 := -hd + 1.8
			var sec_z1 := hd - maxf(3.0, bp.vestibule_depth + 0.9)
			_append_retail_bay_openings(openings, bp.secondary_front_face, sec_z0, sec_z1, bp.ground_floor_height, 0.74, h_hash, 31)
	elif bp.archetype == "municipal_hall":
		# Classical symmetrical courthouse bays flanking the 4-column portico
		var port_half := clampf(bp.width * 0.48, bp.door_width + 3.2, bp.width - 2.0) * 0.5 + 0.45
		for sx in [-1.0, 1.0]:
			var bay_start := (-hw + 0.85) if sx < 0.0 else port_half
			var bay_end := (-port_half) if sx < 0.0 else (hw - 0.85)
			var span := bay_end - bay_start
			if span >= 1.25:
				var n_win := 2 if span >= 4.2 else 1
				for wi in range(n_win):
					var wx := lerpf(bay_start + 0.65, bay_end - 0.65, 0.5 if n_win == 1 else float(wi) / float(n_win - 1))
					openings.append({
						"face": "front",
						"floor": 0,
						"u_center": wx,
						"y_center": 2.35,
						"width": 1.35,
						"height": 2.45,
						"warm": true,
						"storefront_mullion": false,
					})
	elif bp.archetype == "fire_station":
		# Left watch-office storefront glass (right wing kept solid for fire engine bay doors)
		var office_span := (d_x0 - 0.25) - (-hw + 0.45)
		if office_span > 0.75:
			openings.append({
				"face": "front",
				"floor": 0,
				"u_center": (-hw + 0.45 + d_x0 - 0.25) * 0.5,
				"y_center": 1.80,
				"width": office_span,
				"height": 2.1,
				"warm": true,
				"storefront_mullion": false,
			})
		# High clerestory transom windows above side/back walls keep lower walls free for fire_truck & racks
		for s_i in range(bp.window_cols_side):
			var wz := lerpf(-hd + 1.6, hd - 1.6, (float(s_i) + 0.5) / float(bp.window_cols_side))
			for sf in ["left", "right"]:
				openings.append({
					"face": sf,
					"floor": 0,
					"u_center": wz,
					"y_center": 3.55,
					"width": 1.45,
					"height": 1.05,
					"warm": true,
					"storefront_mullion": false,
				})
	elif bp.archetype == "warehouse":
		var ribbon_w := maxf(2.0, bp.width - 2.0)
		openings.append({
			"face": "front",
			"floor": 0,
			"u_center": 0.0,
			"y_center": wall_h - 1.1,
			"width": ribbon_w,
			"height": 0.75,
			"warm": false,
			"storefront_mullion": false,
		})
		openings.append({
			"face": "back",
			"floor": 0,
			"u_center": 0.0,
			"y_center": wall_h - 1.1,
			"width": ribbon_w,
			"height": 0.75,
			"warm": false,
			"storefront_mullion": false,
		})
		return openings

	var start_floor := 0 if bp.archetype in ["house_pitched", "beach_house", "townhouse", "apartment_midrise"] else 1
	var win_h := 1.45 if bp.style != "contemporary_2028" else 1.85
	var win_w := 1.25 if bp.style != "contemporary_2028" else 1.75
	var bal_cols := _get_balcony_columns(bp)

	for fl in range(start_floor, bp.floors):
		var y_floor := 0.0 if fl == 0 else (bp.ground_floor_height + float(fl - 1) * bp.floor_height)
		var y_center := (1.55 if fl == 0 else y_floor + bp.floor_height * 0.52)
		if y_center + win_h * 0.5 + 0.05 > wall_h:
			continue
		var tb := bp.get_tier_bounds_local(fl)
		var tx0 := float(tb["x0"])
		var tx1 := float(tb["x1"])
		var tz0 := float(tb["z0"])
		var tz1 := float(tb["z1"])
		var tw_f := tx1 - tx0
		var td_s := tz1 - tz0
		var cols_front := clampi(int(floor((tw_f - 1.8) / 2.4)), 2, 12)
		var cols_side := clampi(int(floor((td_s - 1.8) / 2.6)), 2, 12)
		var has_fl_balconies := bp.has_balconies and fl >= 1 and (fl % 2 == 1) and not bal_cols.is_empty() and (not bp.has_setback() or fl < bp.setback_floor)
		for c_i in range(cols_front):
			var frac := (float(c_i) + 0.5) / float(cols_front)
			var wx := lerpf(tx0 + 1.2, tx1 - 1.2, frac)
			var warm: bool = ((h_hash + fl * 7 + c_i * 3) % 3) == 0
			var is_bal_door := has_fl_balconies and (c_i in bal_cols)
			var cur_y := y_center
			var cur_h := win_h
			if is_bal_door:
				var bal_h := minf(clampf(bp.floor_height - 0.72, 2.05, 2.38), wall_h - y_floor - 0.18)
				if bal_h >= 1.85:
					cur_h = bal_h
					cur_y = y_floor + bal_h * 0.5 + 0.08
				else:
					is_bal_door = false
			var hits_door := fl == 0 and absf(wx - bp.door_local_x) < bp.door_width * 0.9
			var hits_garage := fl == 0 and bp.has_garage and absf(wx - bp.garage_local_x) < 2.25
			if not hits_door and not hits_garage:
				openings.append({
					"face": "front",
					"floor": fl,
					"u_center": wx,
					"y_center": cur_y,
					"width": win_w,
					"height": cur_h,
					"warm": warm,
					"storefront_mullion": is_bal_door,
					"tier_x0": tx0, "tier_x1": tx1, "tier_z0": tz0, "tier_z1": tz1,
				})
			openings.append({
				"face": "back",
				"floor": fl,
				"u_center": wx,
				"y_center": y_center,
				"width": win_w,
				"height": win_h,
				"warm": false,
				"storefront_mullion": false,
				"tier_x0": tx0, "tier_x1": tx1, "tier_z0": tz0, "tier_z1": tz1,
			})
		for s_i in range(cols_side):
			var frac_s := (float(s_i) + 0.5) / float(cols_side)
			var wz := lerpf(tz0 + 1.3, tz1 - 1.3, frac_s)
			if bp.vestibule_depth > 0.0 and fl == 0 and wz > tz1 - bp.vestibule_depth - 0.5:
				continue
			openings.append({
				"face": "left",
				"floor": fl,
				"u_center": wz,
				"y_center": y_center,
				"width": win_w,
				"height": win_h,
				"warm": false,
				"storefront_mullion": false,
				"tier_x0": tx0, "tier_x1": tx1, "tier_z0": tz0, "tier_z1": tz1,
			})
			openings.append({
				"face": "right",
				"floor": fl,
				"u_center": wz,
				"y_center": y_center,
				"width": win_w,
				"height": win_h,
				"warm": false,
				"storefront_mullion": false,
				"tier_x0": tx0, "tier_x1": tx1, "tier_z0": tz0, "tier_z1": tz1,
			})
	return openings


static func _append_retail_bay_openings(
	openings: Array[Dictionary],
	face: String,
	u_start: float,
	u_end: float,
	ground_h: float,
	pier_gap: float,
	h_hash: int,
	seed_salt: int
) -> void:
	var span := u_end - u_start
	if span <= 1.0:
		return
	var n_bays := 1 if span < 4.4 else clampi(int(round(span / 3.6)), 1, 4)
	var gap := pier_gap if n_bays > 1 else 0.0
	var bay_w := (span - gap * float(n_bays - 1)) / float(n_bays)
	if bay_w < 1.35:
		n_bays = 1
		gap = 0.0
		bay_w = span
	var show_h := minf(2.26, maxf(1.6, ground_h - 1.15))
	var show_yc := 0.62 + show_h * 0.5
	var has_transom := ground_h >= 4.10
	for bi in range(n_bays):
		var uc := u_start + float(bi) * (bay_w + gap) + bay_w * 0.5
		var warm := ((h_hash + seed_salt + bi * 5) % 2) == 0
		openings.append({
			"face": face,
			"floor": 0,
			"u_center": uc,
			"y_center": show_yc,
			"width": bay_w,
			"height": show_h,
			"warm": warm,
			"storefront_mullion": bay_w > 2.2,
			"bay_role": "retail",
		})
		if has_transom:
			openings.append({
				"face": face,
				"floor": 0,
				"u_center": uc,
				"y_center": 3.28,
				"width": bay_w,
				"height": 0.52,
				"warm": true,
				"storefront_mullion": false,
				"bay_role": "transom",
			})


static func _build_entrance_approach(bp: BuildingBlueprint, body: StaticBody3D, foundation_st: SurfaceTool, trim_st: SurfaceTool) -> void:
	var hd := bp.depth * 0.5
	var local_sw_y := bp.sidewalk_y - bp.base_y # Negative (e.g. -0.18m)
	var ramp_w := bp.door_width + 0.9
	var ramp_len := bp.approach_length
	var x0 := bp.door_local_x - ramp_w * 0.5
	var x1 := bp.door_local_x + ramp_w * 0.5
	var z_top := hd + (bp.porch_depth if bp.has_porch else 0.0)
	var z_bot := hd + maxf(ramp_len, (bp.porch_depth + 0.55) if bp.has_porch else 0.55)
	var z_toe := z_bot + 0.85
	var y_toe := local_sw_y - 0.42
	var y_floor := local_sw_y - 0.58

	# Sloped convex ramp wedge from sidewalk up to threshold / porch edge y = 0.0
	var pts := PackedVector3Array([
		Vector3(x0, 0.0, z_top),
		Vector3(x1, 0.0, z_top),
		Vector3(x0, local_sw_y, z_bot),
		Vector3(x1, local_sw_y, z_bot),
		Vector3(x0, y_floor, z_top),
		Vector3(x1, y_floor, z_top),
		Vector3(x0, y_floor, z_bot),
		Vector3(x1, y_floor, z_bot),
	])
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)

	# Buried beveled apron toe wedge so local terrain dips never catch the ramp's outer lip.
	var toe_pts := PackedVector3Array([
		Vector3(x0, local_sw_y, z_bot - 0.04),
		Vector3(x1, local_sw_y, z_bot - 0.04),
		Vector3(x0, y_toe, z_toe),
		Vector3(x1, y_toe, z_toe),
		Vector3(x0, y_floor, z_bot - 0.04),
		Vector3(x1, y_floor, z_bot - 0.04),
		Vector3(x0, y_floor, z_toe),
		Vector3(x1, y_floor, z_toe),
	])
	var toe_shape := ConvexPolygonShape3D.new()
	toe_shape.points = toe_pts
	var toe_cs := CollisionShape3D.new()
	toe_cs.shape = toe_shape
	body.add_child(toe_cs)

	# Visual sloped porch ramp + side curb rails + buried apron toe
	var v_tl := Vector3(x0, 0.0, z_top)
	var v_tr := Vector3(x1, 0.0, z_top)
	var v_bl := Vector3(x0, local_sw_y, z_bot)
	var v_br := Vector3(x1, local_sw_y, z_bot)
	var v_fl := Vector3(x0, y_toe, z_toe)
	var v_fr := Vector3(x1, y_toe, z_toe)
	_emit_quad_auto(foundation_st, v_tl, v_tr, v_bl, v_br, Vector3(0.0, 0.98, 0.2).normalized())
	_emit_quad_auto(foundation_st, v_bl, v_br, v_fl, v_fr, Vector3(0.0, 0.90, 0.43).normalized())
	_emit_quad_auto(foundation_st, v_fl, v_fr, Vector3(x0, y_floor, z_toe), Vector3(x1, y_floor, z_toe), Vector3(0, 0, 1))
	_emit_quad_auto(foundation_st, v_tl, v_bl, Vector3(x0, y_floor, z_top), Vector3(x0, y_floor, z_bot), Vector3(-1, 0, 0))
	_emit_quad_auto(foundation_st, v_bl, v_fl, Vector3(x0, y_floor, z_bot), Vector3(x0, y_floor, z_toe), Vector3(-1, 0, 0))
	_emit_quad_auto(foundation_st, v_br, v_tr, Vector3(x1, y_floor, z_bot), Vector3(x1, y_floor, z_top), Vector3(1, 0, 0))
	_emit_quad_auto(foundation_st, v_fr, v_br, Vector3(x1, y_floor, z_toe), Vector3(x1, y_floor, z_bot), Vector3(1, 0, 0))

	# Threshold sill plate
	_emit_box(trim_st, Vector3(bp.door_local_x, 0.01, hd - bp.wall_thickness * 0.5), Vector3(bp.door_width + 0.25, 0.03, bp.wall_thickness + 0.08))


static func _build_vestibule_details(bp: BuildingBlueprint, vest_wall_st: SurfaceTool, trim_st: SurfaceTool, ext_trim_st: SurfaceTool, glass_warm_st: SurfaceTool, root: Node3D) -> void:
	var hw := bp.width * 0.5
	var hd := bp.depth * 0.5
	var d_x0 := bp.door_local_x - bp.door_width * 0.5
	var d_x1 := bp.door_local_x + bp.door_width * 0.5
	var v_half_w := bp.vestibule_width * 0.5
	var v_x0 := maxf(-hw + 0.35, minf(d_x0 - 0.55, bp.door_local_x - v_half_w))
	var v_x1 := minf(hw - 0.35, maxf(d_x1 + 0.55, bp.door_local_x + v_half_w))
	var v_z0 := hd - bp.vestibule_depth
	var front_inner_z := hd - bp.wall_thickness
	var ceil_y := minf(bp.ground_floor_height, bp.get_total_wall_height())
	var vw := v_x1 - v_x0
	var vd := front_inner_z - v_z0

	# Thin interior finish liners on left, right, and back of vestibule
	_emit_box(vest_wall_st, Vector3(v_x0 + 0.04, ceil_y * 0.5, (v_z0 + front_inner_z) * 0.5), Vector3(0.08, ceil_y, vd))
	_emit_box(vest_wall_st, Vector3(v_x1 - 0.04, ceil_y * 0.5, (v_z0 + front_inner_z) * 0.5), Vector3(0.08, ceil_y, vd))
	_emit_box(vest_wall_st, Vector3((v_x0 + v_x1) * 0.5, ceil_y * 0.5, v_z0 + 0.04), Vector3(vw, ceil_y, 0.08))

	# Inner stairwell/lobby partition door visual (exterior LOD shell only; hidden when real interior activates)
	_emit_box(ext_trim_st, Vector3(bp.door_local_x, 1.15, v_z0 + 0.10), Vector3(minf(1.2, vw - 0.6), 2.3, 0.08))

	# Warm ceiling light panel inside the vestibule
	_emit_box(glass_warm_st, Vector3(bp.door_local_x, ceil_y - 0.04, (v_z0 + front_inner_z) * 0.5), Vector3(minf(1.4, vw * 0.5), 0.05, minf(1.0, vd * 0.45)))

	# Door casing frame
	_emit_box(trim_st, Vector3(d_x0 - 0.05, bp.door_height * 0.5, hd - 0.06), Vector3(0.10, bp.door_height, bp.wall_thickness + 0.08))
	_emit_box(trim_st, Vector3(d_x1 + 0.05, bp.door_height * 0.5, hd - 0.06), Vector3(0.10, bp.door_height, bp.wall_thickness + 0.08))
	_emit_box(trim_st, Vector3(bp.door_local_x, bp.door_height + 0.06, hd - 0.06), Vector3(bp.door_width + 0.22, 0.12, bp.wall_thickness + 0.08))


static func _build_facade_details(
	bp: BuildingBlueprint,
	body: StaticBody3D,
	roof_st: SurfaceTool,
	trim_st: SurfaceTool,
	foundation_st: SurfaceTool,
	glass_dark_st: SurfaceTool,
	glass_warm_st: SurfaceTool,
	detail_sts: Dictionary,
	_mats: MaterialLibrary,
	root: Node3D
) -> void:
	var hw := bp.width * 0.5
	var hd := bp.depth * 0.5
	var wall_h := bp.get_total_wall_height()
	var d_x0 := bp.door_local_x - bp.door_width * 0.5
	var d_x1 := bp.door_local_x + bp.door_width * 0.5

	# Storefront glazing / awning / signage / pilasters on ground floor & upper tower
	var is_commercial := BuildingBlueprint.is_commercial_archetype(bp.archetype)
	var openings := get_facade_window_openings(bp)
	for op in openings:
		var face: String = op["face"]
		var u_c := float(op["u_center"])
		var y_c := float(op["y_center"])
		var w := float(op["width"])
		var h := float(op["height"])
		var fl_idx := int(op.get("floor", 0))
		var tx0 := float(op.get("tier_x0", -hw))
		var tx1 := float(op.get("tier_x1", hw))
		var tz0 := float(op.get("tier_z0", -hd))
		var tz1 := float(op.get("tier_z1", hd))
		var is_sg := bool(op.get("stained_glass", false))
		var target_glass: SurfaceTool = detail_sts["stained_glass"] if is_sg else (glass_warm_st if bool(op.get("warm", false)) else glass_dark_st)
		var frame_st: SurfaceTool = detail_sts["limestone"] if is_sg else trim_st
		match face:
			"front":
				_emit_window_unit(target_glass, frame_st, Vector3(u_c, y_c, tz1 + 0.02), Vector2(w, h), 0.0, fl_idx, bp.floors)
				if bool(op.get("storefront_mullion", false)):
					_emit_box(trim_st, Vector3(u_c, y_c, tz1 + 0.04), Vector3(0.08, h, 0.06))
			"back":
				_emit_window_unit(target_glass, frame_st, Vector3(u_c, y_c, tz0 - 0.02), Vector2(w, h), PI, fl_idx, bp.floors)
			"left":
				_emit_window_unit(target_glass, frame_st, Vector3(tx0 - 0.02, y_c, u_c), Vector2(w, h), -PI * 0.5, fl_idx, bp.floors)
				if fl_idx == 0 and bool(op.get("storefront_mullion", false)):
					_emit_box(trim_st, Vector3(tx0 - 0.04, y_c, u_c), Vector3(0.06, h, 0.08))
			"right":
				_emit_window_unit(target_glass, frame_st, Vector3(tx1 + 0.02, y_c, u_c), Vector2(w, h), PI * 0.5, fl_idx, bp.floors)
				if fl_idx == 0 and bool(op.get("storefront_mullion", false)):
					_emit_box(trim_st, Vector3(tx1 + 0.04, y_c, u_c), Vector3(0.06, h, 0.08))

	# CGA ground-floor retail bay piers, bulkheads, transoms & portal surrounds
	if is_commercial and not (bp.archetype in ["fire_station", "municipal_hall", "hospital", "school"]):
		_emit_ground_retail_details(bp, openings, trim_st, detail_sts)

	# Structural corner pilasters, bay mullions & skyscraper spandrel bands (split across setback tiers)
	var has_sb := bp.has_setback()
	var tier1_top := bp.get_setback_y()
	var up_tb := bp.get_tier_bounds_local(bp.setback_floor) if has_sb else {"x0": -hw, "x1": hw, "z0": -hd, "z1": hd}
	var ux0 := float(up_tb["x0"])
	var ux1 := float(up_tb["x1"])
	var uz0 := float(up_tb["z0"])
	var uz1 := float(up_tb["z1"])
	var ucx := (ux0 + ux1) * 0.5
	var ucz := (uz0 + uz1) * 0.5
	var uw := ux1 - ux0
	var ud := uz1 - uz0

	if bp.floors >= 4 or BuildingBlueprint.is_civic_or_church(bp.archetype):
		var pil_w := 0.38 if bp.floors >= 8 else 0.28
		var pil_st: SurfaceTool = detail_sts["limestone"] if bp.archetype in ["church", "municipal_hall"] else trim_st
		for px: float in [-hw, hw]:
			for pz: float in [-hd, hd]:
				_emit_box(pil_st, Vector3(px, tier1_top * 0.5, pz), Vector3(pil_w, tier1_top, pil_w))
		if has_sb and wall_h - tier1_top > 0.3:
			var uh := wall_h - tier1_top
			for px: float in [ux0, ux1]:
				for pz: float in [uz0, uz1]:
					_emit_box(pil_st, Vector3(px, tier1_top + uh * 0.5, pz), Vector3(pil_w, uh, pil_w))

	if bp.floors >= 4:
		var low_upper_h := maxf(0.0, tier1_top - bp.ground_floor_height)
		if low_upper_h > 0.4:
			var low_yc := bp.ground_floor_height + low_upper_h * 0.5
			_emit_tier_mullions(trim_st, -hw, hw, -hd, hd, low_yc, low_upper_h)
		if has_sb and wall_h - tier1_top > 0.4:
			var hi_h := wall_h - tier1_top
			_emit_tier_mullions(trim_st, ux0, ux1, uz0, uz1, tier1_top + hi_h * 0.5, hi_h)
		# Architectural curtain-wall spandrel floor-slab bands & projecting brise-soleil fins on modern towers
		if bp.archetype in ["skyscraper_tower", "modern_office"] and bp.style == "contemporary_2028" and bp.floors >= 5:
			var sp_dm: SurfaceTool = detail_sts["dark_metal"]
			var sp_lm: SurfaceTool = detail_sts["light_metal"]
			for fl in range(1, bp.floors):
				var sp_y := bp.ground_floor_height + float(fl - 1) * bp.floor_height
				if sp_y < wall_h - 0.45:
					var sp_tb := bp.get_tier_bounds_local(fl)
					var sx0 := float(sp_tb["x0"])
					var sx1 := float(sp_tb["x1"])
					var sz0 := float(sp_tb["z0"])
					var sz1 := float(sp_tb["z1"])
					var is_major_band := (fl % 3 == 0)
					var band_st := trim_st if is_major_band else sp_dm
					var band_h := 0.24 if is_major_band else 0.16
					var band_pad := 0.16 if is_major_band else 0.09
					_emit_box(band_st, Vector3((sx0 + sx1) * 0.5, sp_y, (sz0 + sz1) * 0.5), Vector3((sx1 - sx0) + band_pad, band_h, (sz1 - sz0) + band_pad))
			# Deep vertical architectural sunshade fins on front/back faces of tall glass towers (>= 8 floors)
			if bp.floors >= 8 and low_upper_h > 1.5:
				var fin_yc := bp.ground_floor_height + low_upper_h * 0.5
				var fin_cols := clampi(int(floor((bp.width - 1.8) / 2.4)), 2, 12)
				var fin_step := (bp.width - 1.2) / float(fin_cols)
				for fi in range(1, fin_cols, 2):
					var fx := (-hw + 0.6) + float(fi) * fin_step
					_emit_box(sp_lm, Vector3(fx, fin_yc, hd + 0.13), Vector3(0.08, low_upper_h, 0.24))
					_emit_box(sp_lm, Vector3(fx, fin_yc, -hd - 0.13), Vector3(0.08, low_upper_h, 0.24))
		elif bp.floors >= 9:
			for fl in range(3, bp.floors, 3):
				var sp_y := bp.ground_floor_height + float(fl - 1) * bp.floor_height
				if sp_y < wall_h - 0.6:
					var sp_tb := bp.get_tier_bounds_local(fl)
					var sx0 := float(sp_tb["x0"])
					var sx1 := float(sp_tb["x1"])
					var sz0 := float(sp_tb["z0"])
					var sz1 := float(sp_tb["z1"])
					_emit_box(trim_st, Vector3((sx0 + sx1) * 0.5, sp_y, (sz0 + sz1) * 0.5), Vector3((sx1 - sx0) + 0.14, 0.15, (sz1 - sz0) + 0.14))

	# Heavy-to-light ground-floor architectural base water-table plinth + historic brick quoins, dentils, fire escapes & window AC units
	_emit_building_realism_details(bp, openings, wall_h, tier1_top, trim_st, detail_sts)

	if has_sb:
		_build_podium_terrace(bp, body, roof_st, trim_st, detail_sts, tier1_top, ux0, ux1, uz0, uz1)

	if is_commercial or bp.archetype == "church":
		var lime_st: SurfaceTool = detail_sts["limestone"]
		# Ground-floor cornice band separating retail/lobby base from upper floors
		if bp.floors >= 2:
			_emit_box(lime_st if bp.archetype == "municipal_hall" else trim_st, Vector3(0.0, bp.ground_floor_height, 0.0), Vector3(bp.width + 0.22, 0.22, bp.depth + 0.22))

		if bp.archetype == "municipal_hall":
			# Monumental neoclassical limestone colonnade portico + pediment + classical steps trim
			var col_h := bp.ground_floor_height - 0.30
			var port_w := clampf(bp.width * 0.48, bp.door_width + 3.2, bp.width - 2.0)
			var port_x0 := -port_w * 0.5
			var port_x1 := port_w * 0.5
			for ci in range(4):
				var cx := lerpf(port_x0 + 0.45, port_x1 - 0.45, float(ci) / 3.0)
				_emit_cylinder_st(lime_st, Vector3(cx, col_h * 0.5 + 0.12, hd + 1.05), 0.22, 0.26, col_h - 0.24, 12)
				_emit_box(lime_st, Vector3(cx, 0.10, hd + 1.05), Vector3(0.64, 0.20, 0.64))
				_emit_box(lime_st, Vector3(cx, col_h - 0.02, hd + 1.05), Vector3(0.68, 0.22, 0.68))
			var ent_y := bp.ground_floor_height - 0.02
			_emit_box(lime_st, Vector3(0.0, ent_y, hd + 0.66), Vector3(port_w + 0.36, 0.44, 1.38))
			var ped_h := 1.65
			var p_y0 := ent_y + 0.22
			var p_z0 := hd + 1.34
			var p_z1 := hd + 0.04
			_emit_tri(lime_st, Vector3(port_x0 - 0.25, p_y0, p_z0), Vector3(port_x1 + 0.25, p_y0, p_z0), Vector3(0.0, p_y0 + ped_h, p_z0), Vector3(0, 0, 1))
			_emit_quad_auto(lime_st, Vector3(port_x0 - 0.25, p_y0, p_z1), Vector3(0.0, p_y0 + ped_h, p_z1), Vector3(port_x0 - 0.25, p_y0, p_z0), Vector3(0.0, p_y0 + ped_h, p_z0), Vector3(-ped_h, port_w * 0.5, 0).normalized())
			_emit_quad_auto(lime_st, Vector3(0.0, p_y0 + ped_h, p_z1), Vector3(port_x1 + 0.25, p_y0, p_z1), Vector3(0.0, p_y0 + ped_h, p_z0), Vector3(port_x1 + 0.25, p_y0, p_z0), Vector3(ped_h, port_w * 0.5, 0).normalized())

		elif bp.archetype == "church":
			# Stone entrance vestibule portico + triangular gable pediment + stained-glass front rose window
			var port_w := bp.door_width + 2.2
			var port_h := 3.55
			for col_x in [bp.door_local_x - port_w * 0.44, bp.door_local_x + port_w * 0.44]:
				_emit_box(lime_st, Vector3(col_x, port_h * 0.5, hd + 0.52), Vector3(0.32, port_h, 0.32))
			_emit_box(lime_st, Vector3(bp.door_local_x, port_h + 0.14, hd + 0.42), Vector3(port_w + 0.28, 0.28, 0.92))
			_emit_tri(
				lime_st,
				Vector3(bp.door_local_x - port_w * 0.52, port_h + 0.28, hd + 0.88),
				Vector3(bp.door_local_x + port_w * 0.52, port_h + 0.28, hd + 0.88),
				Vector3(bp.door_local_x, port_h + 1.35, hd + 0.88),
				Vector3(0, 0, 1)
			)
			# Front gable stained-glass rose window with stone mullion ring
			var rose_y := wall_h + bp.roof_height * 0.44
			var rose_sz := clampf(bp.width * 0.18, 1.55, 2.35)
			_emit_box(lime_st, Vector3(0.0, rose_y, hd + 0.04), Vector3(rose_sz + 0.28, rose_sz + 0.28, 0.14))
			_emit_box(detail_sts["stained_glass"], Vector3(0.0, rose_y, hd + 0.09), Vector3(rose_sz, rose_sz, 0.08))
			_emit_box(lime_st, Vector3(0.0, rose_y, hd + 0.12), Vector3(rose_sz + 0.04, 0.10, 0.06))
			_emit_box(lime_st, Vector3(0.0, rose_y, hd + 0.12), Vector3(0.10, rose_sz + 0.04, 0.06))

		elif bp.archetype == "fire_station":
			# Emergency red apparatus bay doors across right wing (clear of personnel entrance!)
			var bay_start := maxf(d_x1 + 1.15, -hw + 4.35)
			var bay_end := hw - 0.65
			var bay_span := bay_end - bay_start
			if bay_span >= 2.6:
				var n_bays := 2 if bay_span >= 7.6 else 1
				var bay_step := bay_span / float(n_bays)
				var door_h := 3.85
				var red_st: SurfaceTool = detail_sts["emergency_red"]
				for bi in range(n_bays):
					var bx := bay_start + (float(bi) + 0.5) * bay_step
					var bw := clampf(bay_step - 0.58, 2.5, 4.1)
					_emit_box(lime_st, Vector3(bx, door_h * 0.5, hd + 0.03), Vector3(bw + 0.24, door_h + 0.14, 0.10))
					_emit_box(red_st, Vector3(bx, door_h * 0.5 - 0.06, hd + 0.07), Vector3(bw, door_h - 0.18, 0.06))
					_emit_box(glass_warm_st, Vector3(bx, 2.48, hd + 0.105), Vector3(bw - 0.38, 0.52, 0.03))
					_emit_box(red_st, Vector3(bx + bw * 0.5 + 0.22, door_h - 0.45, hd + 0.14), Vector3(0.18, 0.28, 0.14))
					_emit_box(detail_sts["amber_sig"], Vector3(bx - bw * 0.5 - 0.22, door_h - 0.45, hd + 0.14), Vector3(0.18, 0.28, 0.14))

		elif bp.archetype == "police_station":
			# Police blue precinct header stripe + illuminated precinct lanterns flanking doorway
			var pblue_st: SurfaceTool = detail_sts["police_blue"]
			_emit_box(pblue_st, Vector3(0.0, bp.ground_floor_height - 0.16, hd + 0.07), Vector3(bp.width - 0.5, 0.24, 0.12))
			for lx: float in [d_x0 - 0.42, d_x1 + 0.42]:
				if absf(lx) <= hw - 0.35:
					_emit_box(trim_st, Vector3(lx, 2.25, hd + 0.10), Vector3(0.24, 0.44, 0.18))
					_emit_box(pblue_st, Vector3(lx, 2.25, hd + 0.20), Vector3(0.18, 0.32, 0.06))

		elif bp.archetype == "hospital":
			# Monumental ER drive/pedestrian arrival canopy + glowing Red Medical Cross emblem
			var er_w := clampf(bp.door_width + 3.4, 4.6, bp.width - 1.6)
			var er_y := bp.ground_floor_height - 0.28
			var red_st: SurfaceTool = detail_sts["emergency_red"]
			var mteal_st: SurfaceTool = detail_sts["medical_teal"]
			_emit_box(lime_st, Vector3(bp.door_local_x, er_y, hd + 0.92), Vector3(er_w, 0.30, 1.84))
			_emit_box(red_st, Vector3(bp.door_local_x, er_y + 0.04, hd + 1.86), Vector3(er_w, 0.16, 0.08))
			_emit_box(mteal_st, Vector3(0.0, bp.ground_floor_height - 0.04, hd + 0.06), Vector3(bp.width - 0.6, 0.20, 0.10))
			for cx: float in [bp.door_local_x - er_w * 0.42, bp.door_local_x + er_w * 0.42]:
				if absf(cx) <= hw - 0.35:
					_emit_cylinder_st(detail_sts["light_metal"], Vector3(cx, er_y * 0.5, hd + 1.62), 0.14, 0.16, er_y, 10)
			# Upper facade glowing Red Cross medical badge
			var badge_y := minf(wall_h - 1.25, bp.ground_floor_height + bp.floor_height * 0.72)
			_emit_box(lime_st, Vector3(bp.door_local_x, badge_y, hd + 0.06), Vector3(1.55, 1.55, 0.12))
			_emit_box(red_st, Vector3(bp.door_local_x, badge_y, hd + 0.13), Vector3(0.32, 1.12, 0.08))
			_emit_box(red_st, Vector3(bp.door_local_x, badge_y, hd + 0.13), Vector3(1.12, 0.32, 0.08))

		elif bp.archetype == "school":
			# Collegiate limestone colonnade entry + academic facade clock tower ornament
			var sc_w := clampf(bp.door_width + 3.2, 4.4, bp.width - 1.8)
			var sc_h := bp.ground_floor_height - 0.25
			for col_x: float in [bp.door_local_x - sc_w * 0.42, bp.door_local_x + sc_w * 0.42]:
				if absf(col_x) <= hw - 0.35:
					_emit_box(lime_st, Vector3(col_x, sc_h * 0.5, hd + 0.76), Vector3(0.34, sc_h, 0.34))
			_emit_box(lime_st, Vector3(bp.door_local_x, sc_h + 0.14, hd + 0.52), Vector3(sc_w + 0.28, 0.30, 1.06))
			var clk_y := wall_h + 0.62
			_emit_box(lime_st, Vector3(bp.door_local_x, clk_y - 0.12, hd + 0.04), Vector3(2.25, 1.55, 0.22))
			_emit_box(lime_st, Vector3(bp.door_local_x, clk_y + 0.72, hd + 0.04), Vector3(1.45, 0.34, 0.22))
			_emit_box(detail_sts["dark_metal"], Vector3(bp.door_local_x, clk_y, hd + 0.16), Vector3(1.16, 1.16, 0.06))
			_emit_box(lime_st, Vector3(bp.door_local_x, clk_y, hd + 0.20), Vector3(0.96, 0.96, 0.04))
			_emit_box(detail_sts["dark_metal"], Vector3(bp.door_local_x, clk_y + 0.14, hd + 0.23), Vector3(0.07, 0.34, 0.04))
			_emit_box(detail_sts["dark_metal"], Vector3(bp.door_local_x + 0.13, clk_y, hd + 0.23), Vector3(0.28, 0.06, 0.04))

		var has_portico := bp.archetype in ["civic_hall", "skyscraper_tower"]
		if has_portico:
			var col_h := bp.ground_floor_height - 0.22
			for col_x in [d_x0 - 0.42, d_x1 + 0.42]:
				if absf(col_x) <= hw - 0.25:
					_emit_box(trim_st, Vector3(col_x, col_h * 0.5, hd + 0.58), Vector3(0.28, col_h, 0.28))
			var port_w := minf(bp.door_width + 2.1, bp.width - 0.8)
			_emit_box(trim_st, Vector3(bp.door_local_x, bp.ground_floor_height - 0.16, hd + 0.46), Vector3(port_w, 0.24, 0.96))

		if bp.has_awning and not has_portico and not BuildingBlueprint.is_civic_or_church(bp.archetype):
			var aw_left_w := (d_x0 - 0.35) - (-hw + 0.45)
			var aw_right_w := (hw - 0.45) - (d_x1 + 0.35)
			if bp.has_blade_sign:
				if bp.door_local_x >= 0.0:
					aw_left_w -= 1.05
				else:
					aw_right_w -= 1.05
			if aw_left_w >= 1.2:
				var aw_lx := (-hw + 0.45 + (1.05 if (bp.has_blade_sign and bp.door_local_x >= 0.0) else 0.0)) + aw_left_w * 0.5
				_emit_shop_canopy(detail_sts["accent"], detail_sts["dark_metal"], Vector3(aw_lx, bp.ground_floor_height - 0.56, hd + 0.54), aw_left_w, 0.0)
			if aw_right_w >= 1.2:
				var aw_rx := (d_x1 + 0.35) + aw_right_w * 0.5
				_emit_shop_canopy(detail_sts["accent"], detail_sts["dark_metal"], Vector3(aw_rx, bp.ground_floor_height - 0.56, hd + 0.54), aw_right_w, 0.0)
			if bp.secondary_front_face in ["left", "right"]:
				var sec_aw_len := (hd - maxf(3.0, bp.vestibule_depth + 0.9)) - (-hd + 1.8)
				if sec_aw_len >= 2.2:
					var sec_zc := (-hd + 1.8 + hd - maxf(3.0, bp.vestibule_depth + 0.9)) * 0.5
					var sec_x := (-hw - 0.54) if bp.secondary_front_face == "left" else (hw + 0.54)
					var sec_yaw := (-PI * 0.5) if bp.secondary_front_face == "left" else (PI * 0.5)
					_emit_shop_canopy(detail_sts["accent"], detail_sts["dark_metal"], Vector3(sec_x, bp.ground_floor_height - 0.56, sec_zc), sec_aw_len, sec_yaw)

		if bp.has_signage and bp.sign_label != "":
			var sign_w := clampf(bp.width - 1.0, 3.6, 8.8)
			var sign_x := 0.0
			var sign_y := bp.ground_floor_height - 0.04
			var sign_z := hd + 0.04
			if has_portico:
				sign_w = minf(bp.door_width + 2.2, bp.width - 1.0)
				sign_x = bp.door_local_x
				sign_y = bp.ground_floor_height - 0.14
				sign_z = hd + 0.94
			elif bp.archetype == "municipal_hall":
				sign_w = clampf(bp.width * 0.46, 4.2, 8.4)
				sign_x = 0.0
				sign_y = bp.ground_floor_height + 0.02
				sign_z = hd + 1.40
			elif bp.archetype in ["hospital", "school"]:
				sign_w = clampf(bp.door_width + 3.0, 4.2, bp.width - 1.2)
				sign_x = bp.door_local_x
				sign_y = bp.ground_floor_height - 0.18
				sign_z = hd + (1.88 if bp.archetype == "hospital" else 1.12)
			elif bp.archetype == "church":
				sign_w = minf(bp.door_width + 2.4, bp.width - 1.2)
				sign_x = bp.door_local_x
				sign_y = 3.68
				sign_z = hd + 0.94
			elif bp.archetype == "fire_station":
				sign_w = clampf(bp.width - 1.4, 4.8, 9.2)
				sign_x = 0.0
				sign_y = bp.ground_floor_height - 0.34
				sign_z = hd + 0.12
			var has_tag := bp.sign_tagline != "" and sign_w >= 4.2
			_emit_sign_plaque(
				root, detail_sts, bp, bp.sign_label, bp.sign_tagline,
				Vector3(sign_x, sign_y, sign_z), sign_w, 0.96 if has_tag else 0.80, 0.0
			)
			if bp.secondary_front_face in ["left", "right"] and bp.depth >= 12.0 and not (bp.archetype in ["fire_station", "municipal_hall", "hospital", "school", "church"]):
				var sec_sw := clampf(bp.depth * 0.42, 3.6, 7.6)
				var sec_sx := (-hw - 0.04) if bp.secondary_front_face == "left" else (hw + 0.04)
				var sec_syaw := (-PI * 0.5) if bp.secondary_front_face == "left" else (PI * 0.5)
				_emit_sign_plaque(root, detail_sts, bp, bp.sign_label, "", Vector3(sec_sx, bp.ground_floor_height - 0.04, -0.6), sec_sw, 0.78, sec_syaw)

		if bp.has_blade_sign and bp.sign_label != "":
			var blade_x := (-hw + 0.62) if bp.door_local_x >= 0.0 else (hw - 0.62)
			var blade_y := clampf(bp.ground_floor_height - 0.68, 2.75, 3.40)
			_emit_blade_sign(root, detail_sts, bp, Vector3(blade_x, blade_y, hd))

		if bp.has_crown_sign and bp.floors >= 7 and bp.sign_label != "":
			var crown_w := clampf(uw * 0.66, 5.4, 15.5)
			var crown_y := wall_h + 0.96
			_emit_sign_plaque(root, detail_sts, bp, bp.sign_label, "", Vector3(ucx, crown_y, uz1 + 0.04), crown_w, 1.24, 0.0)
			_emit_sign_plaque(root, detail_sts, bp, bp.sign_label, "", Vector3(ucx, crown_y, uz0 - 0.04), crown_w, 1.24, PI)
			if ud >= 14.0:
				var side_cw := clampf(ud * 0.60, 5.0, 13.5)
				_emit_sign_plaque(root, detail_sts, bp, bp.sign_label, "", Vector3(ux1 + 0.04, crown_y, ucz), side_cw, 1.24, PI * 0.5)
				_emit_sign_plaque(root, detail_sts, bp, bp.sign_label, "", Vector3(ux0 - 0.04, crown_y, ucz), side_cw, 1.24, -PI * 0.5)
	elif bp.archetype in ["house_pitched", "beach_house", "townhouse"]:
		_build_residential_porch_and_garage(bp, body, roof_st, trim_st, foundation_st, glass_warm_st, detail_sts)
		if bp.archetype == "beach_house":
			_emit_beach_house_ocean_deck(bp, body, trim_st, glass_warm_st, detail_sts)
	elif bp.archetype == "warehouse":
		# Multi-bay industrial loading bay shutters clear of personnel entrance
		var right_span := (hw - 0.75) - (d_x1 + 0.65)
		var left_span := (d_x0 - 0.65) - (-hw + 0.75)
		for bay_pair in [[d_x1 + 0.65, right_span], [-hw + 0.75, left_span]]:
			var x_start := float(bay_pair[0])
			var span := float(bay_pair[1])
			if span < 2.2:
				continue
			var n_shutters := 2 if span >= 7.2 else 1
			var sub_step := span / float(n_shutters)
			for si in range(n_shutters):
				var bw := clampf(sub_step - 0.65, 2.2, 4.2)
				var bx := x_start + (float(si) + 0.5) * sub_step
				_emit_box(trim_st, Vector3(bx, 2.05, hd + 0.03), Vector3(bw, 3.85, 0.08))
				_emit_box(trim_st, Vector3(bx, 4.04, hd + 0.06), Vector3(bw + 0.24, 0.16, 0.14))

	# Projecting architectural balconies aligned to apartment/midrise bays (deck + brackets + 3-sided steel/glass balustrade on root)
	var bal_cols := _get_balcony_columns(bp)
	if not bal_cols.is_empty():
		var win_w_b := 1.25 if bp.style != "contemporary_2028" else 1.75
		var bay_span := maxf(1.8, (bp.width - 2.4) / float(maxi(1, bp.window_cols_front)))
		var bw := clampf(win_w_b + 0.72, 1.85, bay_span - 0.16)
		var bd := 1.24
		var rail_h := 1.02
		var dm_st: SurfaceTool = detail_sts["dark_metal"]
		var lm_st: SurfaceTool = detail_sts["light_metal"]
		var bg_st: SurfaceTool = detail_sts["balcony_glass"]
		for fl in range(1, bp.floors):
			if fl % 2 != 1:
				continue
			if has_sb and fl >= bp.setback_floor:
				continue
			var y_floor := bp.ground_floor_height + float(fl - 1) * bp.floor_height
			if y_floor + 1.95 > wall_h:
				continue
			for c_i in bal_cols:
				var frac := (float(c_i) + 0.5) / float(bp.window_cols_front)
				var bx := lerpf(-hw + 1.2, hw - 1.2, frac)
				if absf(bx) + bw * 0.5 > hw - 0.18:
					continue
				# Structural concrete/steel deck slab + crisp metal front fascia
				_emit_box(trim_st, Vector3(bx, y_floor - 0.05, hd + bd * 0.5), Vector3(bw, 0.14, bd))
				_emit_box(lm_st, Vector3(bx, y_floor - 0.05, hd + bd + 0.015), Vector3(bw + 0.04, 0.12, 0.04))
				# Two cantilevered underside support corbels anchoring balcony to facade
				for br_s: float in [-0.34, 0.34]:
					_emit_box_basis(
						dm_st,
						Vector3(bx + bw * br_s, y_floor - 0.24, hd + bd * 0.36),
						Vector3(0.11, 0.10, bd * 0.68),
						Basis(Vector3.RIGHT, deg_to_rad(-24.0))
					)
				# 3-sided steel stanchion posts & continuous top handrail + lower shoe rail
				var z_front := hd + bd - 0.05
				var z_back := hd + 0.05
				var x_l := bx - bw * 0.5 + 0.04
				var x_r := bx + bw * 0.5 - 0.04
				for px: float in [x_l, bx, x_r]:
					_emit_box(dm_st, Vector3(px, y_floor + rail_h * 0.5 + 0.02, z_front), Vector3(0.055, rail_h, 0.055))
				for px_s: float in [x_l, x_r]:
					_emit_box(dm_st, Vector3(px_s, y_floor + rail_h * 0.5 + 0.02, z_back), Vector3(0.055, rail_h, 0.055))
					_emit_box(lm_st, Vector3(px_s, y_floor + rail_h + 0.03, hd + bd * 0.5), Vector3(0.065, 0.055, bd - 0.04))
					_emit_box(dm_st, Vector3(px_s, y_floor + 0.12, hd + bd * 0.5), Vector3(0.04, 0.04, bd - 0.08))
					_emit_box(bg_st, Vector3(px_s, y_floor + rail_h * 0.52, hd + bd * 0.5), Vector3(0.025, rail_h - 0.20, bd - 0.14))
				_emit_box(lm_st, Vector3(bx, y_floor + rail_h + 0.03, z_front), Vector3(bw + 0.02, 0.055, 0.068))
				_emit_box(dm_st, Vector3(bx, y_floor + 0.12, z_front), Vector3(bw - 0.06, 0.04, 0.04))
				# Tempered architectural glass front guardrail panels (on root, never hidden when interior loads)
				_emit_box(bg_st, Vector3(bx, y_floor + rail_h * 0.52, z_front), Vector3(bw - 0.12, rail_h - 0.20, 0.025))


static func _get_balcony_columns(bp: BuildingBlueprint) -> Array[int]:
	var n := bp.window_cols_front
	if not bp.has_balconies or n < 2:
		return []
	if n <= 4:
		return [0, n - 1]
	if n == 5:
		return [0, 2, 4]
	if n == 6:
		return [1, 4]
	if n == 7:
		return [0, 3, 6]
	return [0, 2, n - 3, n - 1]


static func _emit_sign_plaque(
	root: Node3D,
	detail_sts: Dictionary,
	bp: BuildingBlueprint,
	title: String,
	tagline: String,
	mount_pos: Vector3,
	sign_w: float,
	sign_h: float,
	yaw: float
) -> void:
	var b_rot := Basis(Vector3.UP, yaw)
	var dm_st: SurfaceTool = detail_sts["dark_metal"]
	var glow_st: SurfaceTool = detail_sts["accent_glow"]
	# Outer anodized housing & dark facepanel merged directly into building detail surfaces
	_emit_box_basis(dm_st, mount_pos + b_rot * Vector3(0.0, 0.0, 0.06), Vector3(sign_w, sign_h, 0.12), b_rot)
	_emit_box_basis(dm_st, mount_pos + b_rot * Vector3(0.0, 0.0, 0.14), Vector3(sign_w - 0.18, sign_h - 0.18, 0.04), b_rot)
	for strip_y: float in [-sign_h * 0.5 + 0.045, sign_h * 0.5 - 0.045]:
		_emit_box_basis(glow_st, mount_pos + b_rot * Vector3(0.0, strip_y, 0.165), Vector3(sign_w - 0.04, 0.065, 0.06), b_rot)

	var is_crown := sign_h >= 1.15
	var vis_end := 420.0 if is_crown else 105.0
	var margin := 40.0 if is_crown else 18.0

	var holder := Node3D.new()
	holder.position = mount_pos
	holder.rotation.y = yaw
	root.add_child(holder)

	# Primary brand text sits cleanly ahead of dark faceplate (zero z-fighting or bloom washout)
	var lbl := Label3D.new()
	lbl.text = title
	lbl.font_size = 96
	lbl.shaded = false
	lbl.pixel_size = clampf((sign_w - 0.50) / maxf(float(title.length()) * 58.0, 1.0), 0.0036, sign_h * 0.0070)
	lbl.modulate = Color(0.99, 0.99, 0.97)
	lbl.outline_size = 12
	lbl.outline_modulate = Color(0.03, 0.05, 0.08)
	var has_tag := tagline != "" and sign_w >= 4.2 and sign_h < 1.15
	lbl.position = Vector3(0.0, 0.16 if has_tag else 0.0, 0.21)
	lbl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lbl.visibility_range_end = vis_end
	lbl.visibility_range_end_margin = margin
	lbl.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	holder.add_child(lbl)

	if has_tag:
		var sub := Label3D.new()
		sub.text = tagline
		sub.font_size = 52
		sub.shaded = false
		sub.pixel_size = clampf((sign_w - 0.60) / maxf(float(tagline.length()) * 36.0, 1.0), 0.0022, 0.0036)
		sub.modulate = Color(0.84, 0.95, 1.0)
		sub.outline_size = 8
		sub.outline_modulate = Color(0.03, 0.05, 0.08)
		sub.position = Vector3(0.0, -0.22, 0.21)
		sub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sub.visibility_range_end = vis_end
		sub.visibility_range_end_margin = margin
		sub.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		holder.add_child(sub)


static func _emit_blade_sign(root: Node3D, detail_sts: Dictionary, bp: BuildingBlueprint, anchor: Vector3) -> void:
	var dm_st: SurfaceTool = detail_sts["dark_metal"]
	var glow_st: SurfaceTool = detail_sts["accent_glow"]
	_emit_box(dm_st, anchor + Vector3(0.0, 0.0, 0.46), Vector3(0.08, 0.08, 0.92))
	_emit_box(dm_st, anchor + Vector3(0.0, -0.04, 0.58), Vector3(0.11, 0.94, 0.82))
	for trim_y: float in [-0.46, 0.38]:
		_emit_box(glow_st, anchor + Vector3(0.0, trim_y, 0.58), Vector3(0.13, 0.055, 0.84))

	var holder := Node3D.new()
	holder.position = anchor
	root.add_child(holder)

	var short_txt := bp.sign_label
	var px_sz := clampf(0.72 / maxf(float(short_txt.length()) * 58.0, 1.0), 0.0011, 0.0032)
	for side: float in [1.0, -1.0]:
		var lbl := Label3D.new()
		lbl.text = short_txt
		lbl.font_size = 72
		lbl.shaded = false
		lbl.pixel_size = px_sz
		lbl.modulate = Color(0.99, 0.99, 0.97)
		lbl.outline_size = 10
		lbl.outline_modulate = Color(0.03, 0.05, 0.08)
		lbl.position = Vector3(side * 0.085, -0.04, 0.58)
		lbl.rotation.y = side * PI * 0.5
		lbl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lbl.visibility_range_end = 95.0
		lbl.visibility_range_end_margin = 16.0
		lbl.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		holder.add_child(lbl)


static func _build_roof(
	bp: BuildingBlueprint,
	body: StaticBody3D,
	roof_st: SurfaceTool,
	wall_st: SurfaceTool,
	trim_st: SurfaceTool,
	solar_st: SurfaceTool,
	detail_sts: Dictionary,
	glass_dark_st: SurfaceTool,
	glass_warm_st: SurfaceTool,
	_mats: MaterialLibrary,
	_root: Node3D
) -> void:
	var hw := bp.width * 0.5
	var hd := bp.depth * 0.5
	var wall_h := bp.get_total_wall_height()

	if bp.archetype == "church":
		_build_church_roof_and_steeple(bp, body, roof_st, wall_st, trim_st, detail_sts)
		return

	if bp.roof_type == "flat_parapet":
		var top_tb := bp.get_tier_bounds_local(bp.floors - 1)
		var rx0 := float(top_tb["x0"])
		var rx1 := float(top_tb["x1"])
		var rz0 := float(top_tb["z0"])
		var rz1 := float(top_tb["z1"])
		var r_w := rx1 - rx0
		var r_d := rz1 - rz0
		var r_hw := r_w * 0.5
		var r_hd := r_d * 0.5
		var rcx := (rx0 + rx1) * 0.5
		var rcz := (rz0 + rz1) * 0.5

		# Projecting roofline cornice trim + parapet walls + metal coping caps around top tier
		var p_st: SurfaceTool = detail_sts["limestone"] if bp.archetype == "municipal_hall" else trim_st
		_emit_box(p_st, Vector3(rcx, wall_h - 0.08, rcz), Vector3(r_w + 0.28, 0.16, r_d + 0.28))
		# Stepped masonry dentil cornice on historic brick flat-parapet buildings
		if bp.style == "historic_brick" and bp.archetype != "municipal_hall":
			var corn_st: SurfaceTool = detail_sts["limestone"]
			_emit_box(corn_st, Vector3(rcx, wall_h - 0.04, rcz), Vector3(r_w + 0.42, 0.14, r_d + 0.42))
			_emit_box(corn_st, Vector3(rcx, wall_h - 0.20, rcz), Vector3(r_w + 0.26, 0.12, r_d + 0.26))
			var n_dent_f := clampi(int(floor(r_w / 0.85)), 4, 24)
			for di in range(n_dent_f):
				var dx_d := lerpf(rx0 + 0.35, rx1 - 0.35, (float(di) + 0.5) / float(n_dent_f))
				_emit_box(corn_st, Vector3(dx_d, wall_h - 0.29, rz1 + 0.11), Vector3(0.22, 0.14, 0.16))
				_emit_box(corn_st, Vector3(dx_d, wall_h - 0.29, rz0 - 0.11), Vector3(0.22, 0.14, 0.16))
		var p_y := wall_h + 0.62
		var p_h := 0.42
		_emit_box(p_st, Vector3(rcx, p_y, rz1 - 0.05), Vector3(r_w + 0.2, p_h, 0.22))
		_emit_box(p_st, Vector3(rcx, p_y, rz0 + 0.05), Vector3(r_w + 0.2, p_h, 0.22))
		_emit_box(p_st, Vector3(rx0 + 0.05, p_y, rcz), Vector3(0.22, p_h, r_d))
		_emit_box(p_st, Vector3(rx1 - 0.05, p_y, rcz), Vector3(0.22, p_h, r_d))
		var cop_st: SurfaceTool = detail_sts["light_metal"]
		var cop_y := p_y + p_h * 0.5 + 0.025
		_emit_box(cop_st, Vector3(rcx, cop_y, rz1 - 0.05), Vector3(r_w + 0.24, 0.05, 0.26))
		_emit_box(cop_st, Vector3(rcx, cop_y, rz0 + 0.05), Vector3(r_w + 0.24, 0.05, 0.26))
		_emit_box(cop_st, Vector3(rx0 + 0.05, cop_y, rcz), Vector3(0.26, 0.05, r_d))
		_emit_box(cop_st, Vector3(rx1 - 0.05, cop_y, rcz), Vector3(0.26, 0.05, r_d))

		if bp.archetype == "municipal_hall":
			_build_municipal_dome(bp, wall_h + 0.44, roof_st, detail_sts)
			return
		if bp.archetype == "fire_station":
			# Classic firehouse hose-drying tower at back-left + emergency warning strobe & radio mast
			var tw_x := rx0 + 2.2
			var tw_z := rz0 + 2.2
			var tw_h := 4.4
			_emit_box(wall_st, Vector3(tw_x, wall_h + 0.44 + tw_h * 0.5, tw_z), Vector3(3.1, tw_h, 3.1))
			_emit_box(trim_st, Vector3(tw_x, wall_h + 0.44 + tw_h + 0.12, tw_z), Vector3(3.45, 0.24, 3.45))
			_emit_box(detail_sts["emergency_red"], Vector3(tw_x, wall_h + 0.44 + tw_h + 0.36, tw_z), Vector3(0.32, 0.32, 0.32))
			_emit_cylinder_st(detail_sts["dark_metal"], Vector3(rcx, wall_h + 2.4, rcz), 0.04, 0.08, 4.0, 8)
		if bp.archetype == "police_station":
			var pblue_st: SurfaceTool = detail_sts["police_blue"]
			_emit_cylinder_st(detail_sts["dark_metal"], Vector3(rcx + r_hw * 0.45, wall_h + 2.6, rcz - r_hd * 0.25), 0.04, 0.10, 4.4, 8)
			_emit_box(pblue_st, Vector3(rcx + r_hw * 0.45, wall_h + 4.95, rcz - r_hd * 0.25), Vector3(0.28, 0.28, 0.28))

		# Dense rooftop mechanical clusters (chillers, duct runs, access hatch, skylights)
		if not bp.has_helipad and r_w * r_d >= 64.0:
			_emit_rooftop_mechanicals(bp, wall_h, rcx, rcz, r_w, r_d, trim_st, detail_sts, glass_dark_st)
		else:
			_emit_box(trim_st, Vector3(rcx - r_hw * 0.32, wall_h + 0.78, rcz - r_hd * 0.25), Vector3(minf(2.2, r_w * 0.24), 0.72, minf(1.8, r_d * 0.24)))

		# Architectural mechanical penthouse on mid/high-rise buildings
		var pent_top := wall_h + 0.42
		var pent_w := 0.0
		var pent_d := 0.0
		var pent_z := rcz
		if bp.floors >= 5 and r_w >= 9.0 and r_d >= 8.0:
			pent_w = minf(r_w * 0.44, 9.5)
			pent_d = minf(r_d * 0.40, 8.2)
			var ph := 2.6 if bp.floors >= 9 else 1.85
			pent_z = (rcz - r_hd * 0.18) if bp.has_helipad else rcz
			_emit_box(roof_st, Vector3(rcx, wall_h + 0.42 + ph * 0.5, pent_z), Vector3(pent_w, ph, pent_d))
			_emit_box(trim_st, Vector3(rcx, wall_h + 0.42 + ph + 0.10, pent_z), Vector3(pent_w + 0.26, 0.20, pent_d + 0.26))
			pent_top = wall_h + 0.42 + ph + 0.20

		if bp.floors >= 7 and bp.crown_style != "flat":
			pent_top = _emit_sculpted_crown(bp, wall_h, pent_top, rcx, rcz, r_w, r_d, pent_w, pent_d, pent_z, roof_st, trim_st, glass_warm_st, detail_sts)

		# Communication spires + glowing red aviation beacons on landmark skyscrapers
		if bp.is_landmark_tower:
			var dm_st: SurfaceTool = detail_sts["dark_metal"]
			var bcn_st: SurfaceTool = detail_sts["beacon"]
			var spire_h := 8.5 if bp.floors >= 14 else 6.0
			for sx_off in [-minf(r_w * 0.12, 1.8), minf(r_w * 0.12, 1.8)]:
				_emit_cylinder_st(dm_st, Vector3(rcx + sx_off, pent_top + spire_h * 0.5, pent_z), 0.05, 0.16, spire_h, 8)
				_emit_box(bcn_st, Vector3(rcx + sx_off, pent_top + spire_h + 0.14, pent_z), Vector3(0.32, 0.32, 0.32))

			for cx in [rx0 + 0.28, rx1 - 0.28]:
				for cz in [rz0 + 0.28, rz1 - 0.28]:
					_emit_box(bcn_st, Vector3(cx, wall_h + 0.96, cz), Vector3(0.28, 0.28, 0.28))

		# Rooftop Helipad with bold 'H' markings + perimeter amber beacons
		if bp.has_helipad:
			var pad_sz := clampf(minf(r_w, r_d) * 0.36, 5.2, 8.0)
			var pad_z := rcz + r_hd * 0.24
			var pad_y := wall_h + 0.54
			_emit_cylinder_st(detail_sts["asphalt"], Vector3(rcx, pad_y, pad_z), pad_sz * 0.5, pad_sz * 0.52, 0.18, 16)

			var ring_y := pad_y + 0.105
			var y_st: SurfaceTool = detail_sts["yellow_mark"]
			for bar in [
				[Vector3(rcx - 0.75, ring_y, pad_z), Vector3(0.32, 0.03, 2.3)],
				[Vector3(rcx + 0.75, ring_y, pad_z), Vector3(0.32, 0.03, 2.3)],
				[Vector3(rcx, ring_y, pad_z), Vector3(1.5, 0.03, 0.32)],
			]:
				_emit_box(y_st, bar[0], bar[1])

			var amb_st: SurfaceTool = detail_sts["amber_sig"]
			for ang_i in range(6):
				var ang := float(ang_i) * TAU / 6.0
				var lx := rcx + cos(ang) * (pad_sz * 0.46)
				var lz := pad_z + sin(ang) * (pad_sz * 0.46)
				_emit_box(amb_st, Vector3(lx, ring_y + 0.05, lz), Vector3(0.22, 0.14, 0.22))

		if bp.has_solar_panels and r_w >= 6.5 and r_d >= 6.5 and not bp.has_helipad:
			_emit_solar_array_flat(solar_st, trim_st, Vector3(rcx + r_hw * 0.18, wall_h + 0.46, rcz + r_hd * 0.16), minf(r_w * 0.48, 7.2), minf(r_d * 0.42, 5.2))

		# Architectural rooftop landmarks: historic wooden water towers, telecom masts & louvered mechanical penthouses
		var dm_r: SurfaceTool = detail_sts["dark_metal"]
		if bp.archetype == "school":
			# School rooftop belfry lantern & brass cupola dome
			var lm_s: SurfaceTool = detail_sts["limestone"]
			_emit_box(lm_s, Vector3(rcx, wall_h + 1.45, rcz + r_hd * 0.10), Vector3(2.9, 2.05, 2.9))
			_emit_cylinder_st(detail_sts["gold"], Vector3(rcx, wall_h + 3.02, rcz + r_hd * 0.10), 0.08, 1.48, 1.25, 10)
			_emit_cylinder_st(dm_r, Vector3(rcx, wall_h + 3.85, rcz + r_hd * 0.10), 0.04, 0.05, 0.65, 6)
		elif not bp.has_helipad and bp.style == "historic_brick" and bp.floors >= 3 and r_w >= 10.0 and r_d >= 9.0:
			var wt_x := rcx + r_hw * 0.42
			var wt_z := rcz - r_hd * 0.36
			var wt_y0 := wall_h + 0.44
			for lx_s: float in [-0.72, 0.72]:
				for lz_s: float in [-0.72, 0.72]:
					_emit_box(dm_r, Vector3(wt_x + lx_s, wt_y0 + 0.90, wt_z + lz_s), Vector3(0.11, 1.80, 0.11))
			_emit_box(dm_r, Vector3(wt_x, wt_y0 + 1.84, wt_z), Vector3(1.85, 0.12, 1.85))
			_emit_cylinder_st(detail_sts["cedar"], Vector3(wt_x, wt_y0 + 2.95, wt_z), 0.92, 0.96, 2.10, 12)
			_emit_cylinder_st(dm_r, Vector3(wt_x, wt_y0 + 2.45, wt_z), 0.97, 0.97, 0.08, 12)
			_emit_cylinder_st(dm_r, Vector3(wt_x, wt_y0 + 3.45, wt_z), 0.96, 0.96, 0.08, 12)
			_emit_cylinder_st(roof_st, Vector3(wt_x, wt_y0 + 4.35, wt_z), 0.08, 1.06, 0.72, 12)
		elif bp.archetype == "modern_office" and bp.floors >= 7 and not bp.has_helipad:
			var mast_x := rcx - r_hw * 0.38
			var mast_z := rcz - r_hd * 0.35
			_emit_cylinder_st(detail_sts["light_metal"], Vector3(mast_x, wall_h + 2.35, mast_z), 0.06, 0.12, 3.8, 8)
			for dy: float in [3.2, 3.8]:
				for side_m: float in [-0.28, 0.28]:
					_emit_box(detail_sts["light_metal"], Vector3(mast_x + side_m, wall_h + dy, mast_z), Vector3(0.14, 0.42, 0.10))
		return

	if bp.roof_type == "shed_solar":
		var e := 0.35
		var y0 := wall_h
		var y1 := wall_h + bp.roof_height
		var pts := PackedVector3Array([
			Vector3(-hw - e, y0, hd + e),
			Vector3(hw + e, y0, hd + e),
			Vector3(-hw - e, y0, -hd - e),
			Vector3(hw + e, y0, -hd - e),
			Vector3(-hw - e, y1, -hd - e),
			Vector3(hw + e, y1, -hd - e),
		])
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)

		var fl := pts[0]
		var fr := pts[1]
		var bl := pts[2]
		var br := pts[3]
		var rl := pts[4]
		var rr := pts[5]
		# Sloped top face facing +Z/+Y
		_emit_quad_auto(roof_st, rl, rr, fl, fr, Vector3(0.0, bp.depth, bp.roof_height).normalized())
		_emit_quad_auto(roof_st, rr, rl, br, bl, Vector3(0, 0, -1))
		_emit_tri(roof_st, rl, fl, bl, Vector3(-1, 0, 0))
		_emit_tri(roof_st, rr, br, fr, Vector3(1, 0, 0))
		# Solar array flush above shed slope
		_emit_box_tilted(solar_st, Vector3(0.0, (y0 + y1) * 0.5 + 0.09, 0.0), Vector3(bp.width * 0.72, 0.08, bp.depth * 0.70), atan2(bp.roof_height, bp.depth))
		return

	# Gable or Hip roof
	var e := 0.35
	var x0 := -hw - e
	var x1 := hw + e
	var z0 := -hd - e
	var z1 := hd + e
	var y_base := wall_h
	var y_peak := wall_h + bp.roof_height

	var r_x0 := x0 if bp.roof_type == "gable" else lerpf(x0, 0.0, 0.42)
	var r_x1 := x1 if bp.roof_type == "gable" else lerpf(x1, 0.0, 0.42)

	var pts := PackedVector3Array([
		Vector3(x0, y_base, z1),
		Vector3(x1, y_base, z1),
		Vector3(x1, y_base, z0),
		Vector3(x0, y_base, z0),
		Vector3(r_x0, y_peak, 0.0),
		Vector3(r_x1, y_peak, 0.0),
	])
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)

	var f0 := pts[0]
	var f1 := pts[1]
	var b1 := pts[2]
	var b0 := pts[3]
	var r0 := pts[4]
	var r1 := pts[5]

	# Front slope (+Z), Back slope (-Z), Left (-X), Right (+X), Underside
	_emit_quad_auto(roof_st, r0, r1, f0, f1, Vector3(0.0, hd + e, bp.roof_height).normalized())
	_emit_quad_auto(roof_st, r1, r0, b1, b0, Vector3(0.0, hd + e, -bp.roof_height).normalized())
	if bp.roof_type == "gable":
		_emit_tri(roof_st, r0, f0, b0, Vector3(-1, 0, 0))
		_emit_tri(roof_st, r1, b1, f1, Vector3(1, 0, 0))
	else:
		_emit_tri(roof_st, r0, f0, b0, Vector3(-bp.roof_height, hw * 0.42, 0.0).normalized())
		_emit_tri(roof_st, r1, b1, f1, Vector3(bp.roof_height, hw * 0.42, 0.0).normalized())
	_emit_quad_auto(roof_st, f0, f1, b0, b1, Vector3(0, -1, 0))

	if bp.has_solar_panels:
		var slope_ang := atan2(bp.roof_height, hd + e)
		_emit_box_tilted(solar_st, Vector3(0.0, y_base + bp.roof_height * 0.52 + 0.08, (hd + e) * 0.48), Vector3(bp.width * 0.56, 0.07, (hd + e) * 0.58), slope_ang)

	if (bp.archetype == "house_pitched" or bp.archetype == "beach_house") and bp.width >= 8.0 and bp.depth >= 8.0:
		# Classic residential brick fireplace chimney stack rising cleanly above roof peak
		var ch_x := -hw * 0.42
		var ch_z := -hd * 0.22
		var ch_y0 := y_base - 0.2
		var ch_y1 := y_peak + 0.85
		_emit_box(wall_st, Vector3(ch_x, (ch_y0 + ch_y1) * 0.5, ch_z), Vector3(0.76, ch_y1 - ch_y0, 0.76))
		_emit_box(detail_sts["limestone"], Vector3(ch_x, ch_y1 + 0.08, ch_z), Vector3(0.92, 0.16, 0.92))
		# Eaves metal rain gutters along front/back fascia + corner vertical downspouts
		var gutter_st: SurfaceTool = detail_sts["dark_metal"]
		_emit_box(gutter_st, Vector3(0.0, y_base - 0.06, z1 + 0.05), Vector3(bp.width + e * 2.0 + 0.06, 0.10, 0.11))
		_emit_box(gutter_st, Vector3(0.0, y_base - 0.06, z0 - 0.05), Vector3(bp.width + e * 2.0 + 0.06, 0.10, 0.11))
		for ds_pair in [[Vector2(-hw - 0.05, hd - 0.08), z1], [Vector2(hw + 0.05, -hd + 0.08), z0]]:
			var dp2: Vector2 = ds_pair[0]
			var gz_end: float = ds_pair[1]
			_emit_box(gutter_st, Vector3(dp2.x, y_base * 0.5, dp2.y), Vector3(0.075, y_base, 0.075))
			_emit_box(gutter_st, Vector3(dp2.x, y_base - 0.10, (dp2.y + gz_end) * 0.5), Vector3(0.075, 0.075, absf(gz_end - dp2.y) + 0.08))
		# Gable attic louver vents on left/right gable end walls
		if bp.roof_type == "gable" and bp.roof_height >= 2.0:
			var vent_y := y_base + bp.roof_height * 0.48
			for sx_v: float in [-1.0, 1.0]:
				var vx := sx_v * (hw + e + 0.02)
				_emit_box(trim_st, Vector3(vx, vent_y, 0.0), Vector3(0.06, 0.72, 0.64))
				_emit_box(gutter_st, Vector3(vx + sx_v * 0.03, vent_y, 0.0), Vector3(0.04, 0.56, 0.48))
		# Central pitched roof dormer on larger 2-story homes (when clear of front solar panels)
		if bp.floors >= 2 and not bp.has_solar_panels and bp.width >= 10.8 and bp.roof_height >= 2.3:
			var dm_w := 1.65
			var dm_h := 1.25
			var dm_z := hd * 0.46
			var dm_y0 := y_base + bp.roof_height * 0.36
			var dm_d := hd * 0.44
			_emit_box(wall_st, Vector3(0.0, dm_y0 + dm_h * 0.42, dm_z - dm_d * 0.25), Vector3(dm_w, dm_h * 0.85, dm_d))
			_emit_box(trim_st, Vector3(0.0, dm_y0 + dm_h * 0.42, dm_z + dm_d * 0.25 + 0.03), Vector3(dm_w + 0.10, dm_h * 0.88, 0.08))
			_emit_window_unit(glass_warm_st, trim_st, Vector3(0.0, dm_y0 + dm_h * 0.44, dm_z + dm_d * 0.25 + 0.08), Vector2(0.92, 0.84), 0.0, bp.floors, bp.floors + 1)
			# Small pitched dormer gable roof cap
			var d_peak := dm_y0 + dm_h * 0.88 + 0.48
			var d_zf := dm_z + dm_d * 0.25 + 0.24
			var d_zb := dm_z - dm_d * 0.78
			var d_e := dm_w * 0.5 + 0.18
			_emit_quad_auto(roof_st, Vector3(0.0, d_peak, d_zb), Vector3(0.0, d_peak, d_zf), Vector3(-d_e, dm_y0 + dm_h * 0.84, d_zb), Vector3(-d_e, dm_y0 + dm_h * 0.84, d_zf), Vector3(-0.48, d_e, 0.0).normalized())
			_emit_quad_auto(roof_st, Vector3(0.0, d_peak, d_zf), Vector3(0.0, d_peak, d_zb), Vector3(d_e, dm_y0 + dm_h * 0.84, d_zf), Vector3(d_e, dm_y0 + dm_h * 0.84, d_zb), Vector3(0.48, d_e, 0.0).normalized())
			_emit_tri(trim_st, Vector3(-dm_w * 0.5, dm_y0 + dm_h * 0.84, d_zf - 0.14), Vector3(dm_w * 0.5, dm_y0 + dm_h * 0.84, d_zf - 0.14), Vector3(0.0, d_peak - 0.04, d_zf - 0.14), Vector3(0, 0, 1))


static func _build_church_roof_and_steeple(
	bp: BuildingBlueprint,
	body: StaticBody3D,
	roof_st: SurfaceTool,
	wall_st: SurfaceTool,
	trim_st: SurfaceTool,
	detail_sts: Dictionary
) -> void:
	var hw := bp.width * 0.5
	var hd := bp.depth * 0.5
	var wall_h := bp.get_total_wall_height()
	var e := 0.42
	var x0 := -hw - e
	var x1 := hw + e
	var z0 := -hd - e
	var z1 := hd + e
	var y_base := wall_h
	var y_peak := wall_h + bp.roof_height

	var r_f := Vector3(0.0, y_peak, z1)
	var r_b := Vector3(0.0, y_peak, z0)
	var f0 := Vector3(x0, y_base, z1)
	var f1 := Vector3(x1, y_base, z1)
	var b1 := Vector3(x1, y_base, z0)
	var b0 := Vector3(x0, y_base, z0)

	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([f0, f1, b1, b0, r_f, r_b])
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)

	var left_n := Vector3(-bp.roof_height, hw + e, 0.0).normalized()
	var right_n := Vector3(bp.roof_height, hw + e, 0.0).normalized()
	_emit_quad_auto(roof_st, r_b, r_f, b0, f0, left_n)
	_emit_quad_auto(roof_st, r_f, r_b, f1, b1, right_n)
	_emit_quad_auto(roof_st, f0, f1, b0, b1, Vector3(0, -1, 0))

	# Front & Back stone/brick gable walls closing the pitched nave cleanly
	_emit_tri(wall_st, Vector3(-hw, y_base, hd), Vector3(hw, y_base, hd), Vector3(0.0, y_peak, hd), Vector3(0, 0, 1))
	_emit_tri(wall_st, Vector3(hw, y_base, -hd), Vector3(-hw, y_base, -hd), Vector3(0.0, y_peak, -hd), Vector3(0, 0, -1))
	var lime_st: SurfaceTool = detail_sts["limestone"]
	_emit_quad_auto(lime_st, f0, Vector3(0.0, y_peak, z1), Vector3(-hw, y_base, z1 - 0.35), Vector3(0.0, y_peak - 0.25, z1 - 0.35), Vector3(0, 0, 1))
	_emit_quad_auto(lime_st, Vector3(0.0, y_peak, z1), f1, Vector3(0.0, y_peak - 0.25, z1 - 0.35), Vector3(hw, y_base, z1 - 0.35), Vector3(0, 0, 1))

	# Square Bell Tower / Steeple rising near front ridge + open belfry + spire + golden cross
	var stp_z := hd - 2.45
	var stp_w := clampf(bp.width * 0.24, 2.6, 3.6)
	var base_top := y_peak + 1.85
	_emit_box(lime_st, Vector3(0.0, (y_base + base_top) * 0.5, stp_z), Vector3(stp_w, base_top - y_base, stp_w))
	_emit_box(trim_st, Vector3(0.0, base_top + 0.14, stp_z), Vector3(stp_w + 0.36, 0.28, stp_w + 0.36))

	# Open louvered belfry columns with suspended bronze bell
	var bel_y0 := base_top + 0.28
	var bel_h := 2.45
	var col_r := stp_w * 0.36
	for cx in [-col_r, col_r]:
		for cz in [-col_r, col_r]:
			_emit_box(lime_st, Vector3(cx, bel_y0 + bel_h * 0.5, stp_z + cz), Vector3(0.32, bel_h, 0.32))
	var gold_st: SurfaceTool = detail_sts["gold"]
	_emit_cylinder_st(gold_st, Vector3(0.0, bel_y0 + bel_h * 0.56, stp_z), 0.22, 0.42, 0.72, 10)
	_emit_box(lime_st, Vector3(0.0, bel_y0 + bel_h + 0.16, stp_z), Vector3(stp_w + 0.24, 0.32, stp_w + 0.24))

	# Tapering 4-sided pyramid Spire + illuminated Golden Cross
	var sp_y0 := bel_y0 + bel_h + 0.32
	var sp_h := 5.6
	var sp_hr := stp_w * 0.46
	var tip := Vector3(0.0, sp_y0 + sp_h, stp_z)
	var c0 := Vector3(-sp_hr, sp_y0, stp_z + sp_hr)
	var c1 := Vector3(sp_hr, sp_y0, stp_z + sp_hr)
	var c2 := Vector3(sp_hr, sp_y0, stp_z - sp_hr)
	var c3 := Vector3(-sp_hr, sp_y0, stp_z - sp_hr)
	_emit_tri(roof_st, c0, c1, tip, Vector3(0.0, sp_hr, sp_h).normalized())
	_emit_tri(roof_st, c1, c2, tip, Vector3(sp_h, sp_hr, 0.0).normalized())
	_emit_tri(roof_st, c2, c3, tip, Vector3(0.0, sp_hr, -sp_h).normalized())
	_emit_tri(roof_st, c3, c0, tip, Vector3(-sp_h, sp_hr, 0.0).normalized())

	# Gold finial cross
	_emit_cylinder_st(gold_st, tip + Vector3(0.0, 0.18, 0.0), 0.14, 0.18, 0.26, 8)
	_emit_box(gold_st, tip + Vector3(0.0, 1.15, 0.0), Vector3(0.16, 1.90, 0.16))
	_emit_box(gold_st, tip + Vector3(0.0, 1.48, 0.0), Vector3(1.12, 0.16, 0.16))


static func _build_municipal_dome(
	bp: BuildingBlueprint,
	roof_deck_y: float,
	roof_st: SurfaceTool,
	detail_sts: Dictionary
) -> void:
	var lime_st: SurfaceTool = detail_sts["limestone"]
	var gold_st: SurfaceTool = detail_sts["gold"]
	var pl_w := clampf(minf(bp.width, bp.depth) * 0.46, 5.2, 8.6)
	_emit_box(lime_st, Vector3(0.0, roof_deck_y + 0.55, 0.0), Vector3(pl_w, 1.10, pl_w))
	_emit_box(lime_st, Vector3(0.0, roof_deck_y + 1.22, 0.0), Vector3(pl_w + 0.40, 0.24, pl_w + 0.40))

	# Classical drum + colonnade piers around drum
	var drum_r := pl_w * 0.38
	var drum_y0 := roof_deck_y + 1.34
	var drum_h := 2.4
	_emit_cylinder_st(lime_st, Vector3(0.0, drum_y0 + drum_h * 0.5, 0.0), drum_r, drum_r, drum_h, 12)
	for ci in range(8):
		var a := float(ci) * TAU / 8.0
		_emit_cylinder_st(lime_st, Vector3(cos(a) * (drum_r + 0.22), drum_y0 + drum_h * 0.5, sin(a) * (drum_r + 0.22)), 0.14, 0.16, drum_h, 8)
	_emit_cylinder_st(lime_st, Vector3(0.0, drum_y0 + drum_h + 0.16, 0.0), drum_r + 0.36, drum_r + 0.32, 0.32, 12)

	# Stepped hemispherical metallic/copper-slate dome + cupola lantern + gold spire
	var dome_y0 := drum_y0 + drum_h + 0.32
	var tier_heights := [0.75, 0.72, 0.62, 0.44]
	var tier_r := [drum_r * 0.96, drum_r * 0.84, drum_r * 0.62, drum_r * 0.34]
	var cy := dome_y0
	for ti in range(tier_heights.size()):
		var r_bot: float = tier_r[ti]
		var r_top: float = tier_r[ti + 1] if ti + 1 < tier_heights.size() else 0.38
		var th: float = tier_heights[ti]
		_emit_cylinder_st(roof_st, Vector3(0.0, cy + th * 0.5, 0.0), r_top, r_bot, th, 12)
		cy += th

	# Glazed cupola lantern + gold finial mast
	_emit_cylinder_st(lime_st, Vector3(0.0, cy + 0.52, 0.0), 0.42, 0.48, 1.04, 10)
	_emit_cylinder_st(gold_st, Vector3(0.0, cy + 1.28, 0.0), 0.05, 0.46, 0.52, 10)
	_emit_cylinder_st(gold_st, Vector3(0.0, cy + 2.35, 0.0), 0.03, 0.05, 1.75, 8)
	_emit_box(detail_sts["accent"], Vector3(0.46, cy + 2.95, 0.0), Vector3(0.88, 0.52, 0.04))


static func _emit_solar_array_flat(solar_st: SurfaceTool, trim_st: SurfaceTool, center: Vector3, span_x: float, span_z: float) -> void:
	var rows := maxi(1, int(floor(span_z / 1.9)))
	for r in range(rows):
		var z_off := lerpf(-span_z * 0.4, span_z * 0.4, (float(r) + 0.5) / float(rows))
		var p := Vector3(center.x, center.y + 0.26, center.z + z_off)
		_emit_box(trim_st, Vector3(p.x, center.y + 0.12, p.z), Vector3(span_x * 0.9, 0.22, 0.35))
		_emit_box_tilted(solar_st, p, Vector3(span_x, 0.06, 1.35), deg_to_rad(18.0))


static func _emit_window_unit(glass_st: SurfaceTool, trim_st: SurfaceTool, center: Vector3, size_wh: Vector2, yaw: float, floor_idx: int = 0, total_floors: int = 1) -> void:
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var normal := Vector3(sin(yaw), 0.0, cos(yaw))
	var hw := size_wh.x * 0.5
	var hh := size_wh.y * 0.5
	var tl := center - right * hw + Vector3(0, hh, 0)
	var tr := center + right * hw + Vector3(0, hh, 0)
	var bl := center - right * hw - Vector3(0, hh, 0)
	var br := center + right * hw - Vector3(0, hh, 0)
	var cols := maxf(1.0, roundf(size_wh.x / 2.5))
	var rows := maxf(1.0, roundf(size_wh.y / 3.0))
	var seed_hash := fposmod(absf(center.x * 0.37 + center.y * 0.73 + center.z * 0.51), 0.94)
	var is_wide := 1.0 if size_wh.x >= 2.2 else 0.0
	var floor_norm := 0.0 if floor_idx == 0 else clampf(float(floor_idx) / maxf(1.0, float(total_floors - 1)), 0.05, 1.0)
	_emit_quad_auto(
		glass_st,
		tl,
		tr,
		bl,
		br,
		normal,
		Vector2(cols, rows),
		Color(seed_hash, is_wide, floor_norm, 1.0)
	)
	# Multi-plane CGA architectural window relief: deeper reveal jambs, projecting drip sill, stepped header lintel & casing
	var sill_center := center - Vector3(0, hh + 0.045, 0) + normal * 0.065
	_emit_box_oriented(trim_st, sill_center, Vector3(size_wh.x + 0.20, 0.095, 0.17), yaw)
	var sill_lip := center - Vector3(0, hh + 0.105, 0) + normal * 0.045
	_emit_box_oriented(trim_st, sill_lip, Vector3(size_wh.x + 0.10, 0.045, 0.11), yaw)
	var header_center := center + Vector3(0, hh + 0.065, 0) + normal * 0.075
	_emit_box_oriented(trim_st, header_center, Vector3(size_wh.x + 0.24, 0.125, 0.18), yaw)
	var header_cap := center + Vector3(0, hh + 0.135, 0) + normal * 0.090
	_emit_box_oriented(trim_st, header_cap, Vector3(size_wh.x + 0.30, 0.055, 0.21), yaw)
	for side_s: float in [-1.0, 1.0]:
		var jamb_center := center + right * (side_s * (hw + 0.045)) + normal * 0.045
		_emit_box_oriented(trim_st, jamb_center, Vector3(0.09, size_wh.y + 0.05, 0.13), yaw)


static func _emit_box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	_emit_box_oriented(st, center, size, 0.0)


static func _emit_box_tilted(st: SurfaceTool, center: Vector3, size: Vector3, pitch_x: float) -> void:
	var basis := Basis(Vector3.RIGHT, pitch_x)
	_emit_box_basis(st, center, size, basis)


static func _emit_box_oriented(st: SurfaceTool, center: Vector3, size: Vector3, yaw_y: float) -> void:
	_emit_box_basis(st, center, size, Basis(Vector3.UP, yaw_y))


static func _emit_box_basis(st: SurfaceTool, center: Vector3, size: Vector3, basis: Basis) -> void:
	var hx := basis.x * (size.x * 0.5)
	var hy := basis.y * (size.y * 0.5)
	var hz := basis.z * (size.z * 0.5)

	var p000 := center - hx - hy - hz
	var p100 := center + hx - hy - hz
	var p010 := center - hx + hy - hz
	var p110 := center + hx + hy - hz
	var p001 := center - hx - hy + hz
	var p101 := center + hx - hy + hz
	var p011 := center - hx + hy + hz
	var p111 := center + hx + hy + hz

	# +Y top, -Y bottom, +Z front, -Z back, +X right, -X left
	_emit_quad_auto(st, p010, p110, p011, p111, basis.y)
	_emit_quad_auto(st, p001, p101, p000, p100, -basis.y)
	_emit_quad_auto(st, p011, p111, p001, p101, basis.z)
	_emit_quad_auto(st, p110, p010, p100, p000, -basis.z)
	_emit_quad_auto(st, p111, p110, p101, p100, basis.x)
	_emit_quad_auto(st, p010, p011, p000, p001, -basis.x)


static func _emit_quad_auto(
		st: SurfaceTool,
		tl: Vector3,
		tr: Vector3,
		bl: Vector3,
		br: Vector3,
		desired_normal: Vector3,
		uv_scale: Vector2 = Vector2.ONE,
		v_color: Color = Color.WHITE) -> void:
	var n_test := (bl - tl).cross(tr - tl)
	var u0 := 0.001
	var v0 := 0.001
	var u1 := maxf(0.01, uv_scale.x - 0.001)
	var v1 := maxf(0.01, uv_scale.y - 0.001)
	var uv_tl := Vector2(u0, v0)
	var uv_tr := Vector2(u1, v0)
	var uv_bl := Vector2(u0, v1)
	var uv_br := Vector2(u1, v1)
	var pts: Array[Vector3]
	var uvs: Array[Vector2]
	if n_test.dot(desired_normal) >= 0.0:
		pts = [tl, tr, bl, tr, br, bl]
		uvs = [uv_tl, uv_tr, uv_bl, uv_tr, uv_br, uv_bl]
	else:
		pts = [tl, bl, tr, tr, bl, br]
		uvs = [uv_tl, uv_bl, uv_tr, uv_tr, uv_bl, uv_br]
	var n := desired_normal.normalized()
	for i in range(6):
		st.set_color(v_color)
		st.set_uv(uvs[i])
		st.set_normal(n)
		st.add_vertex(pts[i])


static func _emit_tri(
		st: SurfaceTool,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		desired_normal: Vector3,
		v_color: Color = Color.WHITE) -> void:
	var n_test := (c - a).cross(b - a)
	var verts: Array[Vector3] = [a, b, c]
	var uvs: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.5, 1.0)]
	if n_test.dot(desired_normal) < 0.0:
		verts = [a, c, b]
		uvs = [Vector2(0.0, 0.0), Vector2(0.5, 1.0), Vector2(1.0, 0.0)]
	var n := desired_normal.normalized()
	for i in range(3):
		st.set_color(v_color)
		st.set_uv(uvs[i])
		st.set_normal(n)
		st.add_vertex(verts[i])


static func _emit_cylinder_st(st: SurfaceTool, center: Vector3, top_r: float, bot_r: float, height: float, segs: int = 10) -> void:
	var y_top := center.y + height * 0.5
	var y_bot := center.y - height * 0.5
	for i in range(segs):
		var a0 := float(i) * TAU / float(segs)
		var a1 := float(i + 1) * TAU / float(segs)
		var c0 := cos(a0)
		var s0 := sin(a0)
		var c1 := cos(a1)
		var s1 := sin(a1)
		var t0 := Vector3(center.x + c0 * top_r, y_top, center.z + s0 * top_r)
		var t1 := Vector3(center.x + c1 * top_r, y_top, center.z + s1 * top_r)
		var b0 := Vector3(center.x + c0 * bot_r, y_bot, center.z + s0 * bot_r)
		var b1 := Vector3(center.x + c1 * bot_r, y_bot, center.z + s1 * bot_r)
		var mid_a := (a0 + a1) * 0.5
		_emit_quad_auto(st, t0, t1, b0, b1, Vector3(cos(mid_a), 0.0, sin(mid_a)))
		_emit_tri(st, Vector3(center.x, y_top, center.z), t1, t0, Vector3.UP)
		_emit_tri(st, Vector3(center.x, y_bot, center.z), b0, b1, Vector3.DOWN)


static func _emit_ground_retail_details(bp: BuildingBlueprint, openings: Array[Dictionary], trim_st: SurfaceTool, detail_sts: Dictionary) -> void:
	var hw := bp.width * 0.5
	var hd := bp.depth * 0.5
	var dm_st: SurfaceTool = detail_sts["dark_metal"]
	var d_x0 := bp.door_local_x - bp.door_width * 0.5
	var d_x1 := bp.door_local_x + bp.door_width * 0.5

	# Recessed doorway portal surround piers + overhead lighted fascia header
	for px: float in [d_x0 - 0.10, d_x1 + 0.10]:
		if absf(px) <= hw - 0.20:
			_emit_box(trim_st, Vector3(px, bp.door_height * 0.5 + 0.10, hd + 0.07), Vector3(0.18, bp.door_height + 0.24, 0.16))
	_emit_box(trim_st, Vector3(bp.door_local_x, bp.door_height + 0.24, hd + 0.09), Vector3(bp.door_width + 0.42, 0.24, 0.20))

	# Rhythmic retail bay bulkheads (kickplates), transom bars, and masonry bay piers
	for op in openings:
		if String(op.get("bay_role", "")) != "retail":
			continue
		var face := String(op["face"])
		var uc := float(op["u_center"])
		var bw := float(op["width"])
		var yb := float(op["y_center"]) - float(op["height"]) * 0.5
		var yt := float(op["y_center"]) + float(op["height"]) * 0.5
		var yaw := 0.0
		var pos_base := Vector3.ZERO
		if face == "front":
			yaw = 0.0
			pos_base = Vector3(uc, 0.0, hd + 0.03)
		elif face == "left":
			yaw = -PI * 0.5
			pos_base = Vector3(-hw - 0.03, 0.0, uc)
		elif face == "right":
			yaw = PI * 0.5
			pos_base = Vector3(hw + 0.03, 0.0, uc)
		else:
			continue
		# Solid stone/metal kickplate plinth below display glass + transom divider bar above
		_emit_box_oriented(trim_st, pos_base + Vector3(0.0, yb * 0.5, 0.0), Vector3(bw + 0.10, maxf(0.24, yb - 0.04), 0.10), yaw)
		_emit_box_oriented(dm_st, pos_base + Vector3(0.0, yt + 0.07, 0.0), Vector3(bw + 0.12, 0.09, 0.10), yaw)
		# Projecting flanking bay pilasters defining structural storefront rhythm
		var normal := Vector3(sin(yaw), 0.0, cos(yaw))
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		for s_side: float in [-1.0, 1.0]:
			var pier_p := pos_base + right * (s_side * (bw * 0.5 + 0.11)) + Vector3(0.0, bp.ground_floor_height * 0.5, 0.0) + normal * 0.03
			_emit_box_oriented(trim_st, pier_p, Vector3(0.20, bp.ground_floor_height, 0.14), yaw)


static func _emit_tier_mullions(trim_st: SurfaceTool, x0: float, x1: float, z0: float, z1: float, upper_yc: float, upper_h: float) -> void:
	var w := x1 - x0
	var d := z1 - z0
	var cols_f := clampi(int(floor((w - 1.8) / 2.4)), 2, 12)
	var cols_s := clampi(int(floor((d - 1.8) / 2.6)), 2, 12)
	if cols_f >= 3:
		var usable_f := w - 1.2
		var step_f := usable_f / float(cols_f)
		for ci in range(1, cols_f):
			var ux := (x0 + 0.6) + float(ci) * step_f
			_emit_box(trim_st, Vector3(ux, upper_yc, z1 + 0.04), Vector3(0.14, upper_h, 0.10))
			_emit_box(trim_st, Vector3(ux, upper_yc, z0 - 0.04), Vector3(0.14, upper_h, 0.10))
	if cols_s >= 3:
		var usable_s := d - 1.2
		var step_s := usable_s / float(cols_s)
		for ci in range(1, cols_s):
			var uz := (z0 + 0.6) + float(ci) * step_s
			_emit_box(trim_st, Vector3(x0 - 0.04, upper_yc, uz), Vector3(0.10, upper_h, 0.14))
			_emit_box(trim_st, Vector3(x1 + 0.04, upper_yc, uz), Vector3(0.10, upper_h, 0.14))


static func _build_podium_terrace(
	bp: BuildingBlueprint,
	body: StaticBody3D,
	roof_st: SurfaceTool,
	trim_st: SurfaceTool,
	detail_sts: Dictionary,
	tier1_top: float,
	ux0: float,
	ux1: float,
	uz0: float,
	uz1: float
) -> void:
	var hw := bp.width * 0.5
	var hd := bp.depth * 0.5
	var cedar_st: SurfaceTool = detail_sts["cedar"]
	var dm_st: SurfaceTool = detail_sts["dark_metal"]

	# Walkable exposed terrace strips strictly outside upper tower footprint (never blocking stair/elevator core)
	var front_d := hd - uz1
	if front_d > 0.25:
		var f_cz := (uz1 + hd) * 0.5
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(bp.width + 0.2, 0.22, front_d)
		cs.shape = b
		cs.position = Vector3(0.0, tier1_top - 0.11, f_cz)
		body.add_child(cs)
		_emit_box(roof_st, Vector3(0.0, tier1_top - 0.06, f_cz), Vector3(bp.width + 0.24, 0.14, front_d))
		_emit_box(trim_st, Vector3(0.0, tier1_top + 0.36, hd + 0.02), Vector3(bp.width + 0.24, 0.72, 0.20))
		_emit_box(dm_st, Vector3(0.0, tier1_top + 0.74, hd + 0.02), Vector3(bp.width + 0.28, 0.05, 0.24))
		if front_d >= 1.2 and bp.width >= 8.0:
			_emit_box(cedar_st, Vector3(0.0, tier1_top + 0.26, hd - 0.55), Vector3(bp.width * 0.56, 0.42, 0.58))

	if ux1 < hw - 0.25:
		var sw := hw - ux1
		var s_cx := (ux1 + hw) * 0.5
		var s_d := uz1 - (-hd)
		var s_cz := (-hd + uz1) * 0.5
		var cs_r := CollisionShape3D.new()
		var br := BoxShape3D.new()
		br.size = Vector3(sw, 0.22, s_d)
		cs_r.shape = br
		cs_r.position = Vector3(s_cx, tier1_top - 0.11, s_cz)
		body.add_child(cs_r)
		_emit_box(roof_st, Vector3(s_cx, tier1_top - 0.06, s_cz), Vector3(sw, 0.14, s_d))
		_emit_box(trim_st, Vector3(hw + 0.02, tier1_top + 0.36, 0.0), Vector3(0.20, 0.72, bp.depth + 0.24))
		_emit_box(trim_st, Vector3(s_cx, tier1_top + 0.36, -hd - 0.02), Vector3(sw, 0.72, 0.20))
	elif ux0 > -hw + 0.25:
		var sw := ux0 - (-hw)
		var s_cx := (-hw + ux0) * 0.5
		var s_d := uz1 - (-hd)
		var s_cz := (-hd + uz1) * 0.5
		var cs_l := CollisionShape3D.new()
		var bl := BoxShape3D.new()
		bl.size = Vector3(sw, 0.22, s_d)
		cs_l.shape = bl
		cs_l.position = Vector3(s_cx, tier1_top - 0.11, s_cz)
		body.add_child(cs_l)
		_emit_box(roof_st, Vector3(s_cx, tier1_top - 0.06, s_cz), Vector3(sw, 0.14, s_d))
		_emit_box(trim_st, Vector3(-hw - 0.02, tier1_top + 0.36, 0.0), Vector3(0.20, 0.72, bp.depth + 0.24))
		_emit_box(trim_st, Vector3(s_cx, tier1_top + 0.36, -hd - 0.02), Vector3(sw, 0.72, 0.20))


static func _emit_shop_canopy(accent_st: SurfaceTool, dm_st: SurfaceTool, center: Vector3, span_w: float, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(10.0))
	_emit_box_basis(accent_st, center, Vector3(span_w, 0.12, 1.06), b)
	var front_lip := center + Basis(Vector3.UP, yaw) * Vector3(0.0, -0.09, 0.50)
	_emit_box_oriented(dm_st, front_lip, Vector3(span_w + 0.04, 0.07, 0.06), yaw)
	for side_s: float in [-0.42, 0.42]:
		var rod_off := Basis(Vector3.UP, yaw) * Vector3(span_w * side_s, 0.22, 0.0)
		_emit_box_basis(dm_st, center + rod_off, Vector3(0.04, 0.04, 0.96), Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(-28.0)))


static func _build_residential_porch_and_garage(
	bp: BuildingBlueprint,
	body: StaticBody3D,
	roof_st: SurfaceTool,
	trim_st: SurfaceTool,
	foundation_st: SurfaceTool,
	glass_warm_st: SurfaceTool,
	detail_sts: Dictionary
) -> void:
	var hw := bp.width * 0.5
	var hd := bp.depth * 0.5
	var dm_st: SurfaceTool = detail_sts["dark_metal"]
	var lm_st: SurfaceTool = detail_sts["light_metal"]
	var local_sw_y := bp.sidewalk_y - bp.base_y

	if bp.archetype == "townhouse":
		var ramp_w := bp.door_width + 0.9
		for s_side: float in [-1.0, 1.0]:
			var rx := bp.door_local_x + s_side * (ramp_w * 0.48)
			_emit_box(dm_st, Vector3(rx, 0.45, hd + 0.08), Vector3(0.05, 0.90, 0.05))
			_emit_box(dm_st, Vector3(rx, local_sw_y + 0.45, hd + bp.approach_length - 0.08), Vector3(0.05, 0.90, 0.05))
			_emit_box_basis(dm_st, Vector3(rx, 0.88 + local_sw_y * 0.5, hd + bp.approach_length * 0.5), Vector3(0.05, 0.05, bp.approach_length), Basis(Vector3.RIGHT, atan2(-local_sw_y, bp.approach_length)))
		_emit_box(trim_st, Vector3(bp.door_local_x, bp.door_height + 0.24, hd + 0.42), Vector3(bp.door_width + 0.72, 0.14, 0.84))
		_emit_box(glass_warm_st, Vector3(bp.door_local_x + bp.door_width * 0.5 + 0.26, 2.05, hd + 0.08), Vector3(0.14, 0.24, 0.12))
		return

	if bp.has_porch and bp.porch_depth > 0.4:
		var max_right_hw := (bp.garage_local_x - 1.85 - bp.door_local_x) if bp.has_garage else (hw - 0.25 - bp.door_local_x)
		var max_left_hw := bp.door_local_x - (-hw + 0.25)
		var porch_hw := clampf(bp.door_width * 0.5 + 1.25, bp.door_width * 0.5 + 0.65, minf(max_left_hw, max_right_hw))
		var porch_w := porch_hw * 2.0
		var p_cz := hd + bp.porch_depth * 0.5
		var y_floor := local_sw_y - 0.58
		var deck_cs := CollisionShape3D.new()
		var deck_b := BoxShape3D.new()
		deck_b.size = Vector3(porch_w, 0.20, bp.porch_depth)
		deck_cs.shape = deck_b
		deck_cs.position = Vector3(bp.door_local_x, -0.10, p_cz)
		body.add_child(deck_cs)
		_emit_box(trim_st, Vector3(bp.door_local_x, -0.05, p_cz), Vector3(porch_w, 0.10, bp.porch_depth))
		_emit_box(foundation_st, Vector3(bp.door_local_x, (y_floor - 0.10) * 0.5, p_cz), Vector3(porch_w - 0.06, maxf(0.12, -0.10 - y_floor), bp.porch_depth - 0.04))

		var post_h := 2.68
		var post_z := hd + bp.porch_depth - 0.14
		for s_side: float in [-1.0, 1.0]:
			var px := bp.door_local_x + s_side * (porch_hw - 0.12)
			var p_cs := CollisionShape3D.new()
			var p_b := BoxShape3D.new()
			p_b.size = Vector3(0.20, post_h, 0.20)
			p_cs.shape = p_b
			p_cs.position = Vector3(px, post_h * 0.5, post_z)
			body.add_child(p_cs)
			_emit_box(trim_st, Vector3(px, post_h * 0.5, post_z), Vector3(0.16, post_h, 0.16))
			_emit_box(trim_st, Vector3(px, 0.88, hd + bp.porch_depth * 0.5), Vector3(0.08, 0.07, bp.porch_depth - 0.16))
			_emit_box(trim_st, Vector3(px, 0.45, hd + bp.porch_depth * 0.5), Vector3(0.05, 0.78, bp.porch_depth - 0.24))
			var entry_edge_x := bp.door_local_x + s_side * (bp.door_width * 0.5 + 0.45)
			var rail_w := absf(px - entry_edge_x)
			if rail_w >= 0.35:
				_emit_box(trim_st, Vector3((px + entry_edge_x) * 0.5, 0.88, post_z), Vector3(rail_w, 0.07, 0.08))
				_emit_box(trim_st, Vector3((px + entry_edge_x) * 0.5, 0.45, post_z), Vector3(rail_w - 0.06, 0.78, 0.05))
		_emit_box_basis(roof_st, Vector3(bp.door_local_x, post_h + 0.18, p_cz + 0.05), Vector3(porch_w + 0.36, 0.12, bp.porch_depth + 0.28), Basis(Vector3.RIGHT, deg_to_rad(14.0)))
		_emit_box(trim_st, Vector3(bp.door_local_x, post_h + 0.04, post_z), Vector3(porch_w + 0.24, 0.16, 0.12))
		_emit_box(glass_warm_st, Vector3(bp.door_local_x + bp.door_width * 0.5 + 0.28, 2.02, hd + 0.08), Vector3(0.14, 0.24, 0.12))

	if bp.has_garage:
		var gw := 3.05
		var gh := 2.22
		var gx := bp.garage_local_x
		_emit_box(trim_st, Vector3(gx, gh * 0.5 + 0.04, hd + 0.04), Vector3(gw + 0.28, gh + 0.12, 0.10))
		_emit_box(lm_st, Vector3(gx, gh * 0.5, hd + 0.07), Vector3(gw, gh - 0.06, 0.06))
		for rib_y: float in [0.55, 1.10, 1.65]:
			_emit_box(dm_st, Vector3(gx, rib_y, hd + 0.105), Vector3(gw - 0.08, 0.035, 0.02))
		for lx_off: float in [-0.95, -0.32, 0.32, 0.95]:
			_emit_box(glass_warm_st, Vector3(gx + lx_off, 1.92, hd + 0.108), Vector3(0.46, 0.24, 0.02))
		for s_c: float in [-1.0, 1.0]:
			_emit_box(glass_warm_st, Vector3(gx + s_c * (gw * 0.5 + 0.22), 1.98, hd + 0.08), Vector3(0.13, 0.22, 0.10))


static func _emit_beach_house_ocean_deck(
	bp: BuildingBlueprint,
	body: StaticBody3D,
	trim_st: SurfaceTool,
	glass_warm_st: SurfaceTool,
	detail_sts: Dictionary
) -> void:
	## Iconic coastal oceanfront architecture on the rear (-Z) ocean-facing elevation:
	## elevated cedar sun deck, heavy timber stilt pilings & X-bracing down into dune sand,
	## white timber + glass balustrade, slatted cedar pergola, 2nd-floor ocean balcony, and beach stairs.
	var hw := bp.width * 0.5
	var hd := bp.depth * 0.5
	var cedar_st: SurfaceTool = detail_sts["cedar"]
	var glass_st: SurfaceTool = detail_sts["balcony_glass"]
	var dm_st: SurfaceTool = detail_sts["dark_metal"]

	var deck_w := maxf(4.6, bp.width - 0.16)
	var deck_hw := deck_w * 0.5
	var deck_d := 3.10
	var deck_cz := -hd - deck_d * 0.5
	var deck_z_outer := -hd - deck_d

	# Walkable Jolt deck collider + thick cedar plank slab & perimeter fascia joists
	var deck_cs := CollisionShape3D.new()
	var deck_box := BoxShape3D.new()
	deck_box.size = Vector3(deck_w, 0.24, deck_d)
	deck_cs.shape = deck_box
	deck_cs.position = Vector3(0.0, -0.12, deck_cz)
	body.add_child(deck_cs)
	_emit_box(cedar_st, Vector3(0.0, -0.10, deck_cz), Vector3(deck_w, 0.20, deck_d))
	_emit_box(trim_st, Vector3(0.0, -0.13, deck_z_outer - 0.03), Vector3(deck_w + 0.08, 0.24, 0.08))
	for sx_f: float in [-1.0, 1.0]:
		_emit_box(trim_st, Vector3(sx_f * (deck_hw + 0.03), -0.13, deck_cz), Vector3(0.08, 0.24, deck_d + 0.06))

	# Heavy coastal timber stilt pilings embedded deep into sloping dune sand + cross-beams & X-bracing
	var pil_bot := minf(-1.65, bp.foundation_bottom_y - bp.base_y - 0.85)
	var pil_top := -0.18
	var pil_h := maxf(1.2, pil_top - pil_bot)
	var pil_cy := (pil_top + pil_bot) * 0.5
	var n_bays := maxi(2, int(round(deck_w / 3.2)))
	var pil_xs: Array[float] = []
	for bi in range(n_bays + 1):
		var px := lerpf(-deck_hw + 0.28, deck_hw - 0.28, float(bi) / float(n_bays))
		pil_xs.append(px)
		for pz: float in [deck_z_outer + 0.24, -hd - 0.36]:
			_emit_box(cedar_st, Vector3(px, pil_cy, pz), Vector3(0.24, pil_h, 0.24))
		# Transverse support joist beam under deck
		_emit_box(cedar_st, Vector3(px, -0.30, deck_cz), Vector3(0.18, 0.22, deck_d - 0.16))
	# Longitudinal front girder + diagonal X-brace struts between adjacent outer pilings
	_emit_box(cedar_st, Vector3(0.0, -0.34, deck_z_outer + 0.24), Vector3(deck_w - 0.24, 0.24, 0.20))
	var brace_h := minf(1.35, pil_h * 0.72)
	var brace_cy := pil_top - brace_h * 0.5 - 0.12
	for bi in range(pil_xs.size() - 1):
		var span_x := pil_xs[bi + 1] - pil_xs[bi]
		var mid_x := (pil_xs[bi] + pil_xs[bi + 1]) * 0.5
		var diag_len := sqrt(span_x * span_x + brace_h * brace_h) * 0.92
		var ang := atan2(brace_h, span_x)
		_emit_box_basis(cedar_st, Vector3(mid_x, brace_cy, deck_z_outer + 0.24), Vector3(diag_len, 0.10, 0.08), Basis(Vector3.FORWARD, ang))
		_emit_box_basis(cedar_st, Vector3(mid_x, brace_cy, deck_z_outer + 0.24), Vector3(diag_len, 0.10, 0.08), Basis(Vector3.FORWARD, -ang))

	# Coastal white timber + ocean-view glass deck railings (leaving 1.50m center stair opening on -Z edge)
	var rail_h := 1.02
	var stair_hw := 0.78
	for sx_s: float in [-1.0, 1.0]:
		var rx := sx_s * (deck_hw - 0.08)
		_emit_box(trim_st, Vector3(rx, rail_h, deck_cz), Vector3(0.09, 0.08, deck_d - 0.10))
		_emit_box(trim_st, Vector3(rx, 0.12, deck_cz), Vector3(0.07, 0.07, deck_d - 0.14))
		_emit_box(glass_st, Vector3(rx, rail_h * 0.54, deck_cz), Vector3(0.025, rail_h - 0.24, deck_d - 0.28))
		_emit_box(trim_st, Vector3(rx, rail_h * 0.5, deck_z_outer + 0.08), Vector3(0.14, rail_h + 0.08, 0.14))
		_emit_box(trim_st, Vector3(rx, rail_h * 0.5, -hd - 0.10), Vector3(0.14, rail_h + 0.08, 0.14))
		# Outer (-Z) flanking segments on either side of beach stair opening
		var seg_x0 := minf(sx_s * (deck_hw - 0.08), sx_s * stair_hw)
		var seg_x1 := maxf(sx_s * (deck_hw - 0.08), sx_s * stair_hw)
		var seg_w := seg_x1 - seg_x0
		if seg_w >= 0.45:
			var seg_cx := (seg_x0 + seg_x1) * 0.5
			_emit_box(trim_st, Vector3(seg_cx, rail_h, deck_z_outer + 0.08), Vector3(seg_w, 0.08, 0.09))
			_emit_box(trim_st, Vector3(seg_cx, 0.12, deck_z_outer + 0.08), Vector3(seg_w, 0.07, 0.07))
			_emit_box(glass_st, Vector3(seg_cx, rail_h * 0.54, deck_z_outer + 0.08), Vector3(seg_w - 0.16, rail_h - 0.24, 0.025))
			_emit_box(trim_st, Vector3(sx_s * stair_hw, rail_h * 0.5, deck_z_outer + 0.08), Vector3(0.14, rail_h + 0.08, 0.14))

	# Overhead coastal slatted cedar pergola sunshade (on 1-story or ground deck outer band)
	var perg_y := bp.ground_floor_height - 0.06
	var perg_w := deck_w - 0.12
	for px in pil_xs:
		_emit_box(trim_st, Vector3(px, perg_y * 0.5, deck_z_outer + 0.18), Vector3(0.17, perg_y, 0.17))
	_emit_box(trim_st, Vector3(0.0, perg_y, deck_z_outer + 0.18), Vector3(perg_w + 0.24, 0.22, 0.20))
	for sx_p: float in [-1.0, 1.0]:
		_emit_box(trim_st, Vector3(sx_p * (perg_w * 0.5 - 0.12), perg_y, deck_cz), Vector3(0.18, 0.20, deck_d + 0.16))
	var n_slats := clampi(int(round(perg_w / 0.52)), 8, 22)
	for si in range(n_slats):
		var sx_sl := lerpf(-perg_w * 0.47, perg_w * 0.47, float(si) / float(maxi(1, n_slats - 1)))
		_emit_box(cedar_st, Vector3(sx_sl, perg_y + 0.14, deck_cz - 0.05), Vector3(0.08, 0.11, deck_d + 0.26))

	# Warm exterior coastal deck lanterns flanking rear ocean facade
	for lx_s: float in [-1.0, 1.0]:
		var lx := lx_s * minf(deck_hw - 0.65, 2.2)
		_emit_box(dm_st, Vector3(lx, 2.15, -hd - 0.08), Vector3(0.16, 0.30, 0.14))
		_emit_box(glass_warm_st, Vector3(lx, 2.15, -hd - 0.14), Vector3(0.12, 0.20, 0.06))

	# Second-floor ocean-view balcony above rear deck on 2+ story beach houses
	if bp.floors >= 2:
		var b2_y := bp.ground_floor_height
		var b2_w := clampf(deck_w * 0.78, 4.4, deck_w - 0.4)
		var b2_hw := b2_w * 0.5
		var b2_d := 2.05
		var b2_cz := -hd - b2_d * 0.5
		var b2_z_out := -hd - b2_d
		_emit_box(cedar_st, Vector3(0.0, b2_y + 0.12, b2_cz), Vector3(b2_w, 0.18, b2_d))
		_emit_box(trim_st, Vector3(0.0, b2_y + 0.11, b2_z_out - 0.03), Vector3(b2_w + 0.06, 0.22, 0.07))
		_emit_box(trim_st, Vector3(0.0, b2_y + 0.20 + rail_h, b2_z_out + 0.07), Vector3(b2_w, 0.08, 0.09))
		_emit_box(glass_st, Vector3(0.0, b2_y + 0.20 + rail_h * 0.52, b2_z_out + 0.07), Vector3(b2_w - 0.20, rail_h - 0.20, 0.025))
		for sx_2: float in [-1.0, 1.0]:
			var rx2 := sx_2 * (b2_hw - 0.07)
			_emit_box(trim_st, Vector3(rx2, b2_y + 0.20 + rail_h, b2_cz), Vector3(0.09, 0.08, b2_d - 0.08))
			_emit_box(glass_st, Vector3(rx2, b2_y + 0.20 + rail_h * 0.52, b2_cz), Vector3(0.025, rail_h - 0.20, b2_d - 0.22))
			_emit_box(trim_st, Vector3(rx2, b2_y + 0.20 + rail_h * 0.5, b2_z_out + 0.07), Vector3(0.13, rail_h + 0.06, 0.13))

	# Rear wooden beach stairs descending from the ocean deck directly down toward the golden sand
	var stair_w := stair_hw * 2.0 - 0.10
	var stair_drop := clampf(absf(bp.base_y - bp.sidewalk_y) + 0.95, 0.95, 1.95)
	var n_steps := clampi(int(round(stair_drop / 0.22)), 4, 9)
	var tread_d := 0.30
	for sti in range(n_steps):
		var frac := float(sti + 1) / float(n_steps)
		var sy := -frac * stair_drop
		var sz := deck_z_outer - (float(sti) + 0.5) * tread_d
		_emit_box(cedar_st, Vector3(0.0, sy, sz), Vector3(stair_w, 0.07, tread_d + 0.03))
	var stair_len := float(n_steps) * tread_d
	var stair_slope := atan2(stair_drop, stair_len)
	var diag_s := sqrt(stair_len * stair_len + stair_drop * stair_drop)
	for sx_st: float in [-1.0, 1.0]:
		var str_x := sx_st * (stair_hw - 0.04)
		_emit_box_basis(cedar_st, Vector3(str_x, -stair_drop * 0.5 - 0.06, deck_z_outer - stair_len * 0.5), Vector3(0.10, 0.22, diag_s + 0.16), Basis(Vector3.RIGHT, -stair_slope))
		_emit_box_basis(trim_st, Vector3(str_x, rail_h - stair_drop * 0.5, deck_z_outer - stair_len * 0.5), Vector3(0.08, 0.07, diag_s + 0.16), Basis(Vector3.RIGHT, -stair_slope))
		_emit_box(trim_st, Vector3(str_x, -stair_drop + rail_h * 0.5, deck_z_outer - stair_len), Vector3(0.12, rail_h + 0.20, 0.12))


static func _emit_rooftop_mechanicals(
	bp: BuildingBlueprint,
	wall_h: float,
	rcx: float,
	rcz: float,
	r_w: float,
	r_d: float,
	trim_st: SurfaceTool,
	detail_sts: Dictionary,
	glass_dark_st: SurfaceTool
) -> void:
	var dm_st: SurfaceTool = detail_sts["dark_metal"]
	var lm_st: SurfaceTool = detail_sts["light_metal"]
	var y_deck := wall_h + 0.44
	var mx := rcx - r_w * 0.22
	var mz := rcz - r_d * 0.20

	# Equipment dunnage frame + twin/triple commercial chiller units with circular fan cowls
	var n_units := 3 if r_w >= 16.0 else 2
	var rack_w := minf(r_w * 0.42, float(n_units) * 1.55 + 0.4)
	_emit_box(dm_st, Vector3(mx, y_deck + 0.08, mz), Vector3(rack_w, 0.14, 1.95))
	for ui in range(n_units):
		var ux := mx - rack_w * 0.5 + (float(ui) + 0.5) * (rack_w / float(n_units))
		_emit_box(trim_st, Vector3(ux, y_deck + 0.58, mz), Vector3(1.18, 0.86, 1.55))
		_emit_cylinder_st(dm_st, Vector3(ux, y_deck + 1.06, mz), 0.42, 0.46, 0.14, 10)
	# Galvanized HVAC supply/return duct run + roof access bulkhead hatch
	_emit_box(lm_st, Vector3(mx + rack_w * 0.35, y_deck + 0.30, mz + 1.45), Vector3(0.52, 0.42, minf(3.2, r_d * 0.28)))
	_emit_box_basis(trim_st, Vector3(rcx + r_w * 0.26, y_deck + 0.32, rcz - r_d * 0.26), Vector3(1.25, 0.48, 1.35), Basis(Vector3.RIGHT, deg_to_rad(-12.0)))

	# Louvered architectural rooftop mechanical screen wall + vertical exhaust flues on mid/high-rises
	if bp.floors >= 5 and r_w >= 11.0 and r_d >= 9.0:
		var scr_w := rack_w + 0.85
		var scr_d := 2.65
		var scr_h := 1.42
		for rail_y: float in [0.36, 0.76, 1.16]:
			_emit_box(dm_st, Vector3(mx, y_deck + rail_y, mz + scr_d * 0.5), Vector3(scr_w, 0.16, 0.08))
			_emit_box(dm_st, Vector3(mx, y_deck + rail_y, mz - scr_d * 0.5), Vector3(scr_w, 0.16, 0.08))
			_emit_box(dm_st, Vector3(mx - scr_w * 0.5, y_deck + rail_y, mz), Vector3(0.08, 0.16, scr_d))
			_emit_box(dm_st, Vector3(mx + scr_w * 0.5, y_deck + rail_y, mz), Vector3(0.08, 0.16, scr_d))
		for post_x: float in [-scr_w * 0.5, 0.0, scr_w * 0.5]:
			for post_z: float in [-scr_d * 0.5, scr_d * 0.5]:
				_emit_box(lm_st, Vector3(mx + post_x, y_deck + scr_h * 0.5, mz + post_z), Vector3(0.11, scr_h, 0.11))
		_emit_cylinder_st(lm_st, Vector3(mx + scr_w * 0.36, y_deck + 1.15, mz - scr_d * 0.25), 0.18, 0.20, 2.2, 8)
		_emit_cylinder_st(dm_st, Vector3(mx + scr_w * 0.36, y_deck + 2.30, mz - scr_d * 0.25), 0.26, 0.20, 0.16, 8)

	if bp.archetype in ["warehouse", "retail_anchor"] and r_w >= 12.0 and r_d >= 10.0:
		for sx: float in [-r_w * 0.24, r_w * 0.24]:
			_emit_box(dm_st, Vector3(rcx + sx, y_deck + 0.18, rcz + r_d * 0.18), Vector3(2.4, 0.24, 1.6))
			_emit_box(glass_dark_st, Vector3(rcx + sx, y_deck + 0.34, rcz + r_d * 0.18), Vector3(2.15, 0.12, 1.35))


static func _emit_building_realism_details(
	bp: BuildingBlueprint,
	openings: Array[Dictionary],
	wall_h: float,
	tier1_top: float,
	trim_st: SurfaceTool,
	detail_sts: Dictionary
) -> void:
	var hw := bp.width * 0.5
	var hd := bp.depth * 0.5
	var dm_st: SurfaceTool = detail_sts["dark_metal"]
	var lm_st: SurfaceTool = detail_sts["light_metal"]
	var lime_st: SurfaceTool = detail_sts["limestone"]
	var h_hash: int = absi(bp.id.hash())

	# 1. Heavy-to-light ground-floor architectural water-table plinth belt along side/rear walls
	if bp.archetype != "warehouse":
		var plinth_st := lime_st if (bp.style == "historic_brick" or bp.archetype in ["church", "municipal_hall", "school"]) else trim_st
		var ph := 0.38 if bp.floors >= 2 else 0.30
		_emit_box(plinth_st, Vector3(0.0, ph * 0.5, -hd - 0.03), Vector3(bp.width + 0.14, ph, 0.08))
		_emit_box(plinth_st, Vector3(-hw - 0.03, ph * 0.5, 0.0), Vector3(0.08, ph, bp.depth + 0.14))
		_emit_box(plinth_st, Vector3(hw + 0.03, ph * 0.5, 0.0), Vector3(0.08, ph, bp.depth + 0.14))

	# 2. Historic brick masonry corner limestone quoins + rear zig-zag black iron fire escapes
	if bp.style == "historic_brick" and not (bp.archetype in ["church", "municipal_hall", "fire_station"]):
		if bp.floors >= 2:
			var q_step := 0.72
			var q_y := 0.56
			var q_idx := 0
			while q_y < tier1_top - 0.55:
				var q_long := 0.42 if (q_idx % 2 == 0) else 0.24
				var q_short := 0.24 if (q_idx % 2 == 0) else 0.42
				for sx_q: float in [-1.0, 1.0]:
					for sz_q: float in [-1.0, 1.0]:
						_emit_box(lime_st, Vector3(sx_q * (hw - q_long * 0.42), q_y, sz_q * (hd + 0.025)), Vector3(q_long, 0.32, 0.06))
						_emit_box(lime_st, Vector3(sx_q * (hw + 0.025), q_y, sz_q * (hd - q_short * 0.42)), Vector3(0.06, 0.32, q_short))
				q_y += q_step
				q_idx += 1

		# Authentic zig-zag exterior iron fire escape mounted on rear facade strictly above ground floor (zero sidewalk/door obstruction)
		if bp.floors >= 3 and bp.floors <= 9 and bp.width >= 9.0 and (h_hash % 3 != 0):
			var fe_w := minf(3.2, bp.width * 0.30)
			var fe_d := 0.76
			var fe_x := clampf(-hw * 0.32 if (h_hash % 2 == 0) else hw * 0.32, -hw + fe_w * 0.5 + 0.65, hw - fe_w * 0.5 - 0.65)
			var fe_z := -hd - fe_d * 0.5
			var top_fl := mini(bp.floors - 1, bp.setback_floor - 1 if bp.has_setback() else bp.floors - 1)
			for fl in range(1, top_fl + 1):
				var fy := bp.ground_floor_height + float(fl - 1) * bp.floor_height
				if fy + 1.15 > tier1_top:
					break
				# Grated balcony deck + structural wall brackets
				_emit_box(dm_st, Vector3(fe_x, fy + 0.04, fe_z), Vector3(fe_w, 0.08, fe_d))
				for br_x: float in [-fe_w * 0.42, fe_w * 0.42]:
					_emit_box_basis(dm_st, Vector3(fe_x + br_x, fy - 0.26, -hd - fe_d * 0.34), Vector3(0.06, 0.06, fe_d * 0.78), Basis(Vector3.RIGHT, deg_to_rad(32.0)))
				# Top/mid safety railings & corner stanchions
				var rail_z := -hd - fe_d + 0.03
				_emit_box(dm_st, Vector3(fe_x, fy + 0.96, rail_z), Vector3(fe_w, 0.05, 0.05))
				_emit_box(dm_st, Vector3(fe_x, fy + 0.50, rail_z), Vector3(fe_w, 0.035, 0.035))
				for st_x: float in [-fe_w * 0.48, -fe_w * 0.16, fe_w * 0.16, fe_w * 0.48]:
					_emit_box(dm_st, Vector3(fe_x + st_x, fy + 0.48, rail_z), Vector3(0.04, 0.94, 0.04))
				for side_x: float in [-fe_w * 0.48, fe_w * 0.48]:
					_emit_box(dm_st, Vector3(fe_x + side_x, fy + 0.96, fe_z), Vector3(0.05, 0.05, fe_d))
					_emit_box(dm_st, Vector3(fe_x + side_x, fy + 0.50, fe_z), Vector3(0.035, 0.035, fe_d))
				# Alternating diagonal stair stringer to next floor
				if fl < top_fl:
					var next_fy := bp.ground_floor_height + float(fl) * bp.floor_height
					if next_fy + 1.15 <= tier1_top:
						var rise := next_fy - fy
						var run := fe_w * 0.64
						var diag_len := sqrt(rise * rise + run * run)
						var slope_ang := atan2(rise, run) * (1.0 if fl % 2 == 1 else -1.0)
						_emit_box_basis(dm_st, Vector3(fe_x, fy + rise * 0.5, -hd - fe_d * 0.58), Vector3(diag_len, 0.12, 0.40), Basis(Vector3.BACK, slope_ang))
			# Retracted vertical drop ladder hanging cleanly below floor 1 (stops > 2.2m above ground)
			var y_f1 := bp.ground_floor_height
			var lad_h := minf(1.35, maxf(0.45, y_f1 - 2.35))
			for lx_off: float in [-0.18, 0.18]:
				_emit_box(dm_st, Vector3(fe_x + fe_w * 0.30 + lx_off, y_f1 - lad_h * 0.5 + 0.25, -hd - fe_d + 0.08), Vector3(0.035, lad_h + 0.5, 0.035))

	# 3. Stochastic exterior window AC units (under ~18% of upper side/back windows on brick/apartment buildings)
	if bp.archetype in ["brick_shop", "townhouse", "apartment_midrise"]:
		for oi in range(openings.size()):
			var op := openings[oi]
			var fl_i := int(op.get("floor", 0))
			var face := String(op["face"])
			if fl_i < 1 or face == "front":
				continue
			if ((h_hash + oi * 17 + fl_i * 7) % 11) != 0:
				continue
			var uc := float(op["u_center"])
			var yc := float(op["y_center"]) - float(op["height"]) * 0.5 + 0.18
			var tx0 := float(op.get("tier_x0", -hw))
			var tx1 := float(op.get("tier_x1", hw))
			var tz0 := float(op.get("tier_z0", -hd))
			var ac_pos := Vector3.ZERO
			var ac_yaw := 0.0
			if face == "back":
				ac_pos = Vector3(uc, yc, tz0 - 0.18)
				ac_yaw = PI
			elif face == "left":
				ac_pos = Vector3(tx0 - 0.18, yc, uc)
				ac_yaw = -PI * 0.5
			elif face == "right":
				ac_pos = Vector3(tx1 + 0.18, yc, uc)
				ac_yaw = PI * 0.5
			else:
				continue
			_emit_box_oriented(lm_st, ac_pos, Vector3(0.56, 0.36, 0.34), ac_yaw)
			var norm_ac := Vector3(sin(ac_yaw), 0.0, cos(ac_yaw))
			_emit_box_oriented(dm_st, ac_pos + norm_ac * 0.17, Vector3(0.46, 0.26, 0.03), ac_yaw)

	# 4. Paired decorative window shutters on suburban_siding pitched houses & coastal beach houses
	if (bp.archetype == "house_pitched" or bp.archetype == "beach_house") and bp.style == "suburban_siding":
		var shut_st: SurfaceTool = detail_sts["accent"]
		for op in openings:
			var f_name := String(op["face"])
			if f_name != "front" and not (bp.archetype == "beach_house" and f_name == "back"):
				continue
			var uc := float(op["u_center"])
			var yc := float(op["y_center"])
			var w := float(op["width"])
			var h := float(op["height"])
			var shut_w := 0.30
			var z_sh := (hd + 0.035) if f_name == "front" else (-hd - 0.035)
			for side_s: float in [-1.0, 1.0]:
				var sx_sh := uc + side_s * (w * 0.5 + shut_w * 0.5 + 0.10)
				if absf(sx_sh) > hw - 0.24:
					continue
				if f_name == "front" and int(op.get("floor", 0)) == 0 and absf(sx_sh - bp.door_local_x) < bp.door_width * 0.5 + 0.28:
					continue
				if f_name == "front" and int(op.get("floor", 0)) == 0 and bp.has_garage and absf(sx_sh - bp.garage_local_x) < 1.85:
					continue
				_emit_box(shut_st, Vector3(sx_sh, yc, z_sh), Vector3(shut_w, h + 0.04, 0.05))


static func _emit_sculpted_crown(
	bp: BuildingBlueprint,
	wall_h: float,
	pent_top: float,
	rcx: float,
	rcz: float,
	r_w: float,
	r_d: float,
	pent_w: float,
	pent_d: float,
	pent_z: float,
	roof_st: SurfaceTool,
	trim_st: SurfaceTool,
	glass_warm_st: SurfaceTool,
	detail_sts: Dictionary
) -> float:
	var dm_st: SurfaceTool = detail_sts["dark_metal"]
	var lm_st: SurfaceTool = detail_sts["light_metal"]
	var glow_st: SurfaceTool = detail_sts["accent_glow"]

	if bp.crown_style == "fin_parapet":
		var fin_h := 1.45 if bp.floors >= 11 else 1.05
		var fy := wall_h + 0.84 + fin_h * 0.5
		var n_fx := maxi(3, int(floor(r_w / 3.0)))
		for fi in range(n_fx):
			var fx := rcx - (r_w * 0.44) + (float(fi) / float(maxi(1, n_fx - 1))) * (r_w * 0.88)
			_emit_box(lm_st, Vector3(fx, fy, rcz + r_d * 0.5 - 0.06), Vector3(0.22, fin_h, 0.28))
			_emit_box(lm_st, Vector3(fx, fy, rcz - r_d * 0.5 + 0.06), Vector3(0.22, fin_h, 0.28))
		_emit_box(glow_st, Vector3(rcx, wall_h + 0.84 + fin_h + 0.06, rcz + r_d * 0.5 - 0.04), Vector3(r_w * 0.92, 0.10, 0.12))
		_emit_box(glow_st, Vector3(rcx, wall_h + 0.84 + fin_h + 0.06, rcz - r_d * 0.5 + 0.04), Vector3(r_w * 0.92, 0.10, 0.12))
		return pent_top

	if pent_w < 3.0 or pent_d < 3.0:
		return pent_top

	if bp.crown_style == "stepped":
		var cap_w := pent_w * 0.66
		var cap_d := pent_d * 0.66
		var cap_h := 1.55
		_emit_box(roof_st, Vector3(rcx, pent_top + cap_h * 0.5, pent_z), Vector3(cap_w, cap_h, cap_d))
		_emit_box(trim_st, Vector3(rcx, pent_top + cap_h + 0.09, pent_z), Vector3(cap_w + 0.28, 0.18, cap_d + 0.28))
		_emit_box(glow_st, Vector3(rcx, pent_top + cap_h - 0.14, pent_z + cap_d * 0.5 + 0.04), Vector3(cap_w * 0.86, 0.09, 0.08))
		return pent_top + cap_h + 0.18

	# "chamfer_glass": glazed lantern crown above mechanical penthouse
	var lw := pent_w * 0.72
	var ld := pent_d * 0.72
	var lh := 1.85
	_emit_box(glass_warm_st, Vector3(rcx, pent_top + lh * 0.5, pent_z), Vector3(lw, lh, ld))
	_emit_box(dm_st, Vector3(rcx, pent_top + lh + 0.10, pent_z), Vector3(lw + 0.26, 0.20, ld + 0.26))
	for sx: float in [-lw * 0.5, 0.0, lw * 0.5]:
		for sz: float in [-ld * 0.5, ld * 0.5]:
			_emit_box(dm_st, Vector3(rcx + sx, pent_top + lh * 0.5, pent_z + sz), Vector3(0.12, lh, 0.12))
	return pent_top + lh + 0.20


static func _add_building_occluders(bp: BuildingBlueprint, ext_root: Node3D) -> void:
	var tier1_h := bp.get_setback_y()
	var occ_podium := OccluderInstance3D.new()
	occ_podium.name = "BuildingOccluder_Podium"
	var box_p := BoxOccluder3D.new()
	box_p.size = Vector3(maxf(1.2, bp.width - 1.1), maxf(2.0, tier1_h - 0.9), maxf(1.2, bp.depth - 1.1))
	occ_podium.occluder = box_p
	occ_podium.position = Vector3(0.0, tier1_h * 0.5, 0.0)
	ext_root.add_child(occ_podium)

	if bp.has_setback():
		var tb := bp.get_tier_bounds_local(bp.setback_floor)
		var uw := float(tb["x1"]) - float(tb["x0"])
		var ud := float(tb["z1"]) - float(tb["z0"])
		var ucx := (float(tb["x0"]) + float(tb["x1"])) * 0.5
		var ucz := (float(tb["z0"]) + float(tb["z1"])) * 0.5
		var uh := bp.get_total_wall_height() - tier1_h
		if uh >= 2.5:
			var occ_up := OccluderInstance3D.new()
			occ_up.name = "BuildingOccluder_Tower"
			var box_u := BoxOccluder3D.new()
			box_u.size = Vector3(maxf(1.2, uw - 1.1), uh - 0.7, maxf(1.2, ud - 1.1))
			occ_up.occluder = box_u
			occ_up.position = Vector3(ucx, tier1_h + uh * 0.5, ucz)
			ext_root.add_child(occ_up)


static func _commit(
	st: SurfaceTool,
	node_name: String,
	mat: Material,
	parent: Node3D,
	cast_shadows: bool = true,
	vis_end: float = 0.0,
	vis_margin: float = 20.0
) -> MeshInstance3D:
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	if not cast_shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		mi.visibility_range_end = vis_end
		mi.visibility_range_end_margin = vis_margin
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mi)
	return mi
