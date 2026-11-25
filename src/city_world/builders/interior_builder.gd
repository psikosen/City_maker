class_name InteriorBuilder
extends RefCounted

## Materializes perforated exterior walls with clear glazing plus full multi-floor
## interior architecture, walkable switchback stairs, partitions, doors, lights,
## navigation meshes, and clearance-verified furniture from an InteriorBlueprint.


static func build_interior(
	bp: BuildingBlueprint,
	ib: InteriorBlueprint,
	wall_mat: Material,
	_trim_mat: Material,
	mats: MaterialLibrary,
	include_probe: bool = true
) -> Dictionary:
	var res := begin_interior_shell(bp, ib, wall_mat, _trim_mat, mats, include_probe, ib.floors.size())
	return {
		"node": res["node"],
		"doors": res["doors"],
		"elevators": res["elevators"],
	}


static func begin_interior_shell(
	bp: BuildingBlueprint,
	ib: InteriorBlueprint,
	wall_mat: Material,
	_trim_mat: Material,
	mats: MaterialLibrary,
	include_probe: bool = false,
	initial_floor_count: int = 2
) -> Dictionary:
	## Builds the perforated exterior shell, stairs, elevator, and ground/lower floors immediately
	## so tall skyscrapers become visually open and walkable in <10ms, while upper floors stream
	## cleanly via append_interior_floors() across subsequent frames without lag spikes.
	var group := Node3D.new()
	group.name = "ActiveInteriorGroup"

	var static_body := StaticBody3D.new()
	static_body.name = "ActiveInteriorBody"
	static_body.set_meta("building_id", bp.id)
	group.add_child(static_body)

	var ext_wall_st := SurfaceTool.new()
	ext_wall_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var clear_glass_st := SurfaceTool.new()
	clear_glass_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stained_glass_st := SurfaceTool.new()
	stained_glass_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stair_st := SurfaceTool.new()
	stair_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var drywall_st := SurfaceTool.new()
	drywall_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var metal_st := SurfaceTool.new()
	metal_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var light_metal_st := SurfaceTool.new()
	light_metal_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Perforated exterior perimeter shell with real window/door cutouts & clear/stained glazing.
	_build_perforated_shell(bp, ib, static_body, ext_wall_st, clear_glass_st, stained_glass_st)

	# 2. Switchback staircases across floor transitions.
	for st_idx in range(ib.stairs.size()):
		_build_stair_run(ib.stairs[st_idx], st_idx < ib.stairs.size() - 1, static_body, stair_st, metal_st, light_metal_st, clear_glass_st)

	# 2b. Structural elevator shaft walls, doorframe trim, and working InteractiveElevator cab.
	var elevators: Array[InteractiveElevator] = []
	if bool(ib.elevator.get("enabled", false)):
		_build_elevator_shaft_shell(bp, ib, static_body, drywall_st, metal_st)
		var elev := InteractiveElevator.new()
		elev.setup(bp, ib, mats)
		group.add_child(elev)
		elevators.append(elev)

	# 3. Commit shell/stair/elevator meshes
	var active_walls_mi := _commit(ext_wall_st, "ActiveWallsMesh", wall_mat, group, bp.floors <= 5)
	if active_walls_mi != null:
		active_walls_mi.set_instance_shader_parameter("wall_color", bp.wall_color)
	_commit(clear_glass_st, "ActiveGlassMesh", mats.clear_glass_mat, group, false)
	_commit(stained_glass_st, "ActiveStainedGlassMesh", mats.stained_glass_mat, group, false)
	_commit(drywall_st, "InteriorShaftDrywallMesh", mats.interior_drywall_mat, group, false)
	_commit(stair_st, "InteriorStairMesh", mats.interior_stair_mat, group, false)
	_commit(metal_st, "InteriorShaftMetalMesh", mats.dark_metal_mat, group, false)
	_commit(light_metal_st, "InteriorShaftLightMetalMesh", mats.light_metal_mat, group, false)

	# 4. Build initial batch of floors (lobby + lower floor(s)) immediately
	var total_fl := ib.floors.size()
	var end_fl := mini(total_fl, maxi(1, initial_floor_count))
	var interior_doors: Array[InteractiveDoor] = append_interior_floors(group, bp, ib, mats, 0, end_fl)

	if include_probe:
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

	return {
		"node": group,
		"doors": interior_doors,
		"elevators": elevators,
		"next_floor": end_fl,
		"total_floors": total_fl,
	}


static func append_interior_floors(
	group: Node3D,
	bp: BuildingBlueprint,
	ib: InteriorBlueprint,
	mats: MaterialLibrary,
	start_fl: int,
	end_fl: int
) -> Array[InteractiveDoor]:
	## Builds floors [start_fl, end_fl) into a self-contained child batch with its own StaticBody3D
	## so Jolt BVH updates remain tiny (<3ms) even for 24-floor skyscrapers.
	var new_doors: Array[InteractiveDoor] = []
	var clamped_end := mini(ib.floors.size(), end_fl)
	if start_fl >= clamped_end:
		return new_doors

	var batch_node := Node3D.new()
	batch_node.name = "FloorBatch_%d_%d" % [start_fl, clamped_end - 1]
	group.add_child(batch_node)

	var batch_body := StaticBody3D.new()
	batch_body.name = "FloorBatchBody_%d" % start_fl
	batch_body.set_meta("building_id", bp.id)
	batch_node.add_child(batch_body)

	var clear_glass_st := SurfaceTool.new()
	clear_glass_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tile_floor_st := SurfaceTool.new()
	tile_floor_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood_floor_st := SurfaceTool.new()
	wood_floor_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var drywall_st := SurfaceTool.new()
	drywall_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var metal_st := SurfaceTool.new()
	metal_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var furn_wood_st := SurfaceTool.new()
	furn_wood_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var furn_fabric_st := SurfaceTool.new()
	furn_fabric_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var light_metal_st := SurfaceTool.new()
	light_metal_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var foliage_st := SurfaceTool.new()
	foliage_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var recycle_st := SurfaceTool.new()
	recycle_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var light_st := SurfaceTool.new()
	light_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rubber_st := SurfaceTool.new()
	rubber_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var accent_st := SurfaceTool.new()
	accent_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var furn_limestone_st := SurfaceTool.new()
	furn_limestone_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var furn_gold_st := SurfaceTool.new()
	furn_gold_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var furn_pblue_st := SurfaceTool.new()
	furn_pblue_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var furn_red_st := SurfaceTool.new()
	furn_red_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var furn_sts := {
		"wood": furn_wood_st,
		"fabric": furn_fabric_st,
		"dark_metal": metal_st,
		"light_metal": light_metal_st,
		"foliage": foliage_st,
		"recycle": recycle_st,
		"light": light_st,
		"rubber": rubber_st,
		"accent": accent_st,
		"limestone": furn_limestone_st,
		"gold": furn_gold_st,
		"police_blue": furn_pblue_st,
		"emergency_red": furn_red_st,
	}

	var light_stride := maxi(2, int(round(float(bp.floors) / 3.0)))
	for idx_f in range(start_fl, clamped_end):
		var f_data: Dictionary = ib.floors[idx_f]
		var fl: int = int(f_data["floor_index"])
		var fy: float = float(f_data["base_y"])
		var fh: float = float(f_data["height"])
		var slab_h: float = float(f_data["slab_thickness"])
		var f_rects: Array = f_data["floor_rects"]

		if fl == 0:
			# Architectural finish surface over foundation (y = 0.0 collider stays continuous)
			var is_tile := BuildingBlueprint.is_commercial_archetype(bp.archetype) or bp.archetype == "warehouse"
			var target_st := tile_floor_st if is_tile else wood_floor_st
			_emit_box(target_st, Vector3(0.0, 0.008, 0.0), Vector3(bp.width - bp.wall_thickness * 2.0, 0.016, bp.depth - bp.wall_thickness * 2.0))
		else:
			for fr in f_rects:
				var r: Rect2 = fr
				var c := r.get_center()
				var slab_pos := Vector3(c.x, fy - slab_h * 0.5, c.y)
				var slab_sz := Vector3(r.size.x, slab_h, r.size.y)
				_add_box_collider(batch_body, slab_pos, slab_sz)
				_emit_box(wood_floor_st, Vector3(c.x, fy - 0.03, c.y), Vector3(r.size.x, 0.06, r.size.y))
				_emit_box(drywall_st, Vector3(c.x, fy - slab_h * 0.5 - 0.03, c.y), Vector3(r.size.x, maxf(0.06, slab_h - 0.06), r.size.y))

		if fl == ib.floors.size() - 1:
			# Clean plaster interior ceiling slab on top floor (hides exterior roof underside on 1-story buildings)
			var top_tb := bp.get_tier_bounds_local(fl)
			var top_w := (float(top_tb["x1"]) - float(top_tb["x0"])) - bp.wall_thickness * 2.0
			var top_d := (float(top_tb["z1"]) - float(top_tb["z0"])) - bp.wall_thickness * 2.0
			var top_cx := (float(top_tb["x0"]) + float(top_tb["x1"])) * 0.5
			var top_cz := (float(top_tb["z0"]) + float(top_tb["z1"])) * 0.5
			_emit_box(drywall_st, Vector3(top_cx, fy + fh - 0.04, top_cz), Vector3(top_w, 0.08, top_d))

		# Guardrails along open stair shaft edges on upper floors
		for gr in f_data.get("guardrails", []):
			var g_pos: Vector3 = gr["pos"]
			var g_sz: Vector3 = gr["size"]
			_add_box_collider(batch_body, g_pos, g_sz)
			_emit_box(metal_st, Vector3(g_pos.x, g_pos.y + g_sz.y * 0.45, g_pos.z), Vector3(g_sz.x + 0.02, 0.06, g_sz.z + 0.02))
			_emit_box(clear_glass_st, Vector3(g_pos.x, g_pos.y - 0.05, g_pos.z), Vector3(maxf(0.03, g_sz.x * 0.5), g_sz.y * 0.78, maxf(0.03, g_sz.z * 0.5)))

		# Interior drywall partitions
		for part in f_data.get("partitions", []):
			var p_pos: Vector3 = part["pos"]
			var p_sz: Vector3 = part["size"]
			_add_box_collider(batch_body, p_pos, p_sz)
			_emit_box(drywall_st, p_pos, p_sz)

		# Interior InteractiveDoors (open archways already leave doorway cut clear)
		for d_spec in f_data.get("interior_doors", []):
			if bool(d_spec.get("is_open_arch", false)):
				continue
			var idoor := InteractiveDoor.new()
			idoor.setup(
				String(d_spec["door_id"]),
				bp.id,
				float(d_spec["width"]),
				float(d_spec["height"]),
				bool(d_spec.get("commercial", false)),
				mats
			)
			idoor.position = d_spec["pos"]
			idoor.rotation.y = float(d_spec["yaw"])
			batch_node.add_child(idoor)
			new_doors.append(idoor)

		# Ceiling LED panels + capped lightweight shadowless interior OmniLight3D per active tower
		var light_pts: Array = f_data.get("lights", [])
		for l_pt in light_pts:
			var lp: Vector3 = l_pt
			_emit_box(light_st, lp, Vector3(1.1, 0.05, 0.36))
		var emit_floor_omni := bp.floors <= 5 or fl == 0 or fl == 1 or fl == bp.floors - 1 or (fl % light_stride == 0)
		if not light_pts.is_empty() and emit_floor_omni:
			var omni := OmniLight3D.new()
			omni.name = "InteriorLight_F%d" % fl
			omni.light_color = Color(1.0, 0.94, 0.84)
			omni.light_energy = 1.45
			omni.shadow_enabled = false
			omni.omni_range = clampf(maxf(bp.width, bp.depth) * 0.95, 11.0, 26.0)
			omni.omni_attenuation = 1.3
			omni.distance_fade_enabled = true
			omni.distance_fade_begin = 34.0
			omni.distance_fade_length = 12.0
			var mid_l: Vector3 = light_pts[0]
			omni.position = Vector3(0.0, fy + fh - 0.35, mid_l.z * 0.35)
			batch_node.add_child(omni)

		# Furniture props via parametric FurnitureBuilder
		for fn in f_data.get("furniture", []):
			FurnitureBuilder.build_item(fn, batch_body, furn_sts)

	_commit(clear_glass_st, "FloorGlassMesh", mats.clear_glass_mat, batch_node, false)
	_commit(tile_floor_st, "InteriorTileFloorMesh", mats.interior_floor_tile_mat, batch_node, false)
	_commit(wood_floor_st, "InteriorWoodFloorMesh", mats.interior_floor_wood_mat, batch_node, false)
	_commit(drywall_st, "InteriorDrywallMesh", mats.interior_drywall_mat, batch_node, false)
	_commit(metal_st, "InteriorMetalMesh", mats.dark_metal_mat, batch_node, false)
	_commit(light_metal_st, "InteriorLightMetalMesh", mats.light_metal_mat, batch_node, false)
	_commit(furn_wood_st, "InteriorFurnitureWoodMesh", mats.interior_furniture_wood_mat, batch_node, false)
	_commit(furn_fabric_st, "InteriorFurnitureFabricMesh", mats.interior_furniture_fabric_mat, batch_node, false)
	_commit(foliage_st, "InteriorPlantFoliageMesh", mats.get_accent_material(Color(0.18, 0.42, 0.22)), batch_node, false)
	_commit(recycle_st, "InteriorRecycleAccentMesh", mats.get_accent_material(Color(0.16, 0.48, 0.72)), batch_node, false)
	_commit(rubber_st, "InteriorRubberMesh", mats.get_accent_material(Color(0.09, 0.10, 0.12)), batch_node, false)
	_commit(accent_st, "InteriorBrandAccentMesh", mats.get_accent_material(bp.accent_color), batch_node, false)
	_commit(furn_limestone_st, "InteriorLimestoneMesh", mats.limestone_mat, batch_node, false)
	_commit(furn_gold_st, "InteriorGoldMesh", mats.gold_metal_mat, batch_node, false)
	_commit(furn_pblue_st, "InteriorPoliceBlueMesh", mats.police_blue_mat, batch_node, false)
	_commit(furn_red_st, "InteriorEmergencyRedMesh", mats.emergency_red_mat, batch_node, false)
	_commit(light_st, "InteriorLightPanelMesh", mats.interior_ceiling_light_mat, batch_node, false)

	return new_doors


static func _build_elevator_shaft_shell(
	bp: BuildingBlueprint,
	ib: InteriorBlueprint,
	body: StaticBody3D,
	wall_st: SurfaceTool,
	metal_st: SurfaceTool
) -> void:
	var er: Rect2 = ib.elevator["shaft_rect"]
	var wall_h := bp.get_total_wall_height()
	var cx := er.get_center().x
	var dw := float(ib.elevator.get("door_width", 1.08))
	var dh := float(ib.elevator.get("door_height", 2.18))
	var t := 0.12
	var door_x0 := cx - dw * 0.5
	var door_x1 := cx + dw * 0.5

	# Left, right, and rear full-height enclosed shaft walls + top cap
	_add_box_collider(body, Vector3(er.position.x + t * 0.5, wall_h * 0.5, er.get_center().y), Vector3(t, wall_h, er.size.y))
	_emit_box(wall_st, Vector3(er.position.x + t * 0.5, wall_h * 0.5, er.get_center().y), Vector3(t, wall_h, er.size.y))
	_add_box_collider(body, Vector3(er.end.x - t * 0.5, wall_h * 0.5, er.get_center().y), Vector3(t, wall_h, er.size.y))
	_emit_box(wall_st, Vector3(er.end.x - t * 0.5, wall_h * 0.5, er.get_center().y), Vector3(t, wall_h, er.size.y))
	_add_box_collider(body, Vector3(cx, wall_h * 0.5, er.position.y + t * 0.5), Vector3(er.size.x - t * 2.0, wall_h, t))
	_emit_box(wall_st, Vector3(cx, wall_h * 0.5, er.position.y + t * 0.5), Vector3(er.size.x - t * 2.0, wall_h, t))
	_emit_box(wall_st, Vector3(cx, wall_h - 0.06, er.get_center().y), Vector3(er.size.x, 0.12, er.size.y))

	# Front left & right continuous shaft return piers flanking doorways
	var front_z := er.end.y - t * 0.5
	var lw := maxf(0.08, door_x0 - (er.position.x + t))
	var rw := maxf(0.08, (er.end.x - t) - door_x1)
	_add_box_collider(body, Vector3(er.position.x + t + lw * 0.5, wall_h * 0.5, front_z), Vector3(lw, wall_h, t))
	_emit_box(wall_st, Vector3(er.position.x + t + lw * 0.5, wall_h * 0.5, front_z), Vector3(lw, wall_h, t))
	_add_box_collider(body, Vector3(door_x1 + rw * 0.5, wall_h * 0.5, front_z), Vector3(rw, wall_h, t))
	_emit_box(wall_st, Vector3(door_x1 + rw * 0.5, wall_h * 0.5, front_z), Vector3(rw, wall_h, t))

	# Per-floor doorway transom lintels & steel architectural jamb trim
	var f_ys: PackedFloat32Array = ib.elevator.get("floor_ys", PackedFloat32Array())
	for fi in range(f_ys.size()):
		var fy := float(f_ys[fi])
		var fh := bp.ground_floor_height if fi == 0 else bp.floor_height
		var top_y := minf(wall_h, fy + fh)
		var trans_h := top_y - (fy + dh)
		if trans_h > 0.06:
			_add_box_collider(body, Vector3(cx, fy + dh + trans_h * 0.5, front_z), Vector3(dw, trans_h, t))
			_emit_box(wall_st, Vector3(cx, fy + dh + trans_h * 0.5, front_z), Vector3(dw, trans_h, t))
		_emit_box(metal_st, Vector3(door_x0 - 0.03, fy + dh * 0.5, er.end.y + 0.005), Vector3(0.06, dh, 0.08))
		_emit_box(metal_st, Vector3(door_x1 + 0.03, fy + dh * 0.5, er.end.y + 0.005), Vector3(0.06, dh, 0.08))
		_emit_box(metal_st, Vector3(cx, fy + dh + 0.03, er.end.y + 0.005), Vector3(dw + 0.12, 0.06, 0.08))


static func _build_perforated_shell(
	bp: BuildingBlueprint,
	ib: InteriorBlueprint,
	body: StaticBody3D,
	wall_st: SurfaceTool,
	glass_st: SurfaceTool,
	stained_glass_st: SurfaceTool
) -> void:
	var hw := bp.width * 0.5
	var hd := bp.depth * 0.5
	var wt := bp.wall_thickness
	var wall_h := bp.get_total_wall_height()
	var has_sb := bp.has_setback()
	var tier1_top := bp.get_setback_y()

	var by_face_low := {"front": [], "back": [], "left": [], "right": []}
	var by_face_hi := {"front": [], "back": [], "left": [], "right": []}
	for op in ib.window_openings:
		var face: String = op["face"]
		var yc := float(op["y_center"])
		var entry := {
			"u_center": float(op["u_center"]),
			"y_center": yc,
			"width": float(op["width"]),
			"height": float(op["height"]),
			"is_door": false,
			"stained_glass": bool(op.get("stained_glass", false)),
		}
		if has_sb and yc >= tier1_top - 0.05:
			by_face_hi[face].append(entry)
		else:
			by_face_low[face].append(entry)
	# Ground floor entrance doorway hole on front (+Z)
	by_face_low["front"].append({
		"u_center": bp.door_local_x,
		"y_center": bp.door_height * 0.5,
		"width": bp.door_width,
		"height": bp.door_height,
		"is_door": true,
		"stained_glass": false,
	})

	# Simplified 6-box lower perimeter physics colliders (prevents ~1500+ Jolt shapes per skyscraper on stream-in).
	_add_box_collider(body, Vector3(0.0, tier1_top * 0.5, -hd + wt * 0.5), Vector3(bp.width, tier1_top, wt))
	_add_box_collider(body, Vector3(-hw + wt * 0.5, tier1_top * 0.5, 0.0), Vector3(wt, tier1_top, bp.depth - wt * 2.0))
	_add_box_collider(body, Vector3(hw - wt * 0.5, tier1_top * 0.5, 0.0), Vector3(wt, tier1_top, bp.depth - wt * 2.0))
	var d_x0 := bp.door_local_x - bp.door_width * 0.5
	var d_x1 := bp.door_local_x + bp.door_width * 0.5
	if d_x0 > -hw + 0.05:
		_add_box_collider(body, Vector3((-hw + d_x0) * 0.5, tier1_top * 0.5, hd - wt * 0.5), Vector3(d_x0 + hw, tier1_top, wt))
	if d_x1 < hw - 0.05:
		_add_box_collider(body, Vector3((d_x1 + hw) * 0.5, tier1_top * 0.5, hd - wt * 0.5), Vector3(hw - d_x1, tier1_top, wt))
	if tier1_top - bp.door_height > 0.05:
		_add_box_collider(body, Vector3(bp.door_local_x, (bp.door_height + tier1_top) * 0.5, hd - wt * 0.5), Vector3(bp.door_width, tier1_top - bp.door_height, wt))

	_emit_sliced_wall(wall_st, glass_st, stained_glass_st, "front", -hw, hw, 0.0, tier1_top, hd - wt * 0.5, wt, by_face_low["front"])
	_emit_sliced_wall(wall_st, glass_st, stained_glass_st, "back", -hw, hw, 0.0, tier1_top, -hd + wt * 0.5, wt, by_face_low["back"])
	_emit_sliced_wall(wall_st, glass_st, stained_glass_st, "left", -hd + wt, hd - wt, 0.0, tier1_top, -hw + wt * 0.5, wt, by_face_low["left"])
	_emit_sliced_wall(wall_st, glass_st, stained_glass_st, "right", -hd + wt, hd - wt, 0.0, tier1_top, hw - wt * 0.5, wt, by_face_low["right"])

	if has_sb and wall_h - tier1_top > 0.2:
		var tb := bp.get_tier_bounds_local(bp.setback_floor)
		var ux0 := float(tb["x0"])
		var ux1 := float(tb["x1"])
		var uz0 := float(tb["z0"])
		var uz1 := float(tb["z1"])
		var uw := ux1 - ux0
		var ud := uz1 - uz0
		var ucx := (ux0 + ux1) * 0.5
		var ucz := (uz0 + uz1) * 0.5
		var uh := wall_h - tier1_top
		var umy := tier1_top + uh * 0.5
		_add_box_collider(body, Vector3(ucx, umy, uz0 + wt * 0.5), Vector3(uw, uh, wt))
		_add_box_collider(body, Vector3(ucx, umy, uz1 - wt * 0.5), Vector3(uw, uh, wt))
		_add_box_collider(body, Vector3(ux0 + wt * 0.5, umy, ucz), Vector3(wt, uh, ud - wt * 2.0))
		_add_box_collider(body, Vector3(ux1 - wt * 0.5, umy, ucz), Vector3(wt, uh, ud - wt * 2.0))
		_emit_sliced_wall(wall_st, glass_st, stained_glass_st, "front", ux0, ux1, tier1_top, wall_h, uz1 - wt * 0.5, wt, by_face_hi["front"])
		_emit_sliced_wall(wall_st, glass_st, stained_glass_st, "back", ux0, ux1, tier1_top, wall_h, uz0 + wt * 0.5, wt, by_face_hi["back"])
		_emit_sliced_wall(wall_st, glass_st, stained_glass_st, "left", uz0 + wt, uz1 - wt, tier1_top, wall_h, ux0 + wt * 0.5, wt, by_face_hi["left"])
		_emit_sliced_wall(wall_st, glass_st, stained_glass_st, "right", uz0 + wt, uz1 - wt, tier1_top, wall_h, ux1 - wt * 0.5, wt, by_face_hi["right"])
		# Interior soffit closing the exposed podium setback roof overhang from below
		if hd - uz1 > 0.1:
			_emit_box(wall_st, Vector3(0.0, tier1_top - 0.06, (uz1 + hd) * 0.5), Vector3(bp.width - wt * 2.0, 0.12, hd - uz1))
		if ux1 < hw - 0.1:
			_emit_box(wall_st, Vector3((ux1 + hw) * 0.5, tier1_top - 0.06, (-hd + uz1) * 0.5), Vector3(hw - ux1, 0.12, uz1 - (-hd)))
		if ux0 > -hw + 0.1:
			_emit_box(wall_st, Vector3((-hw + ux0) * 0.5, tier1_top - 0.06, (-hd + uz1) * 0.5), Vector3(ux0 - (-hw), 0.12, uz1 - (-hd)))


static func _emit_sliced_wall(
	wall_st: SurfaceTool,
	glass_st: SurfaceTool,
	stained_glass_st: SurfaceTool,
	face: String,
	u_min: float,
	u_max: float,
	y_min: float,
	y_max: float,
	fixed_coord: float,
	thickness: float,
	holes: Array
) -> void:
	var y_cuts: Array[float] = [y_min, y_max]
	for h in holes:
		var hy0 := clampf(float(h["y_center"]) - float(h["height"]) * 0.5, y_min, y_max)
		var hy1 := clampf(float(h["y_center"]) + float(h["height"]) * 0.5, y_min, y_max)
		if hy1 - hy0 > 0.02:
			_append_unique_float(y_cuts, hy0)
			_append_unique_float(y_cuts, hy1)
	y_cuts.sort()

	var is_z_wall := (face == "front" or face == "back")
	for yi in range(y_cuts.size() - 1):
		var ya := y_cuts[yi]
		var yb := y_cuts[yi + 1]
		var band_h := yb - ya
		if band_h < 0.02:
			continue
		var y_mid := (ya + yb) * 0.5

		var spans: Array[Dictionary] = []
		for h in holes:
			var hy0 := float(h["y_center"]) - float(h["height"]) * 0.5
			var hy1 := float(h["y_center"]) + float(h["height"]) * 0.5
			if y_mid >= hy0 and y_mid <= hy1:
				var hu0 := clampf(float(h["u_center"]) - float(h["width"]) * 0.5, u_min, u_max)
				var hu1 := clampf(float(h["u_center"]) + float(h["width"]) * 0.5, u_min, u_max)
				if hu1 - hu0 > 0.02:
					spans.append({"u0": hu0, "u1": hu1, "is_door": bool(h["is_door"]), "stained_glass": bool(h.get("stained_glass", false))})

		spans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["u0"]) < float(b["u0"]))

		var cursor := u_min
		for sp in spans:
			var u0: float = float(sp["u0"])
			var u1: float = float(sp["u1"])
			if u0 > cursor + 0.02:
				_emit_wall_piece(wall_st, is_z_wall, cursor, u0, y_mid, band_h, fixed_coord, thickness)
			var glass_start := maxf(cursor, u0)
			if u1 > glass_start + 0.02 and not bool(sp["is_door"]):
				var tgt_glass := stained_glass_st if bool(sp.get("stained_glass", false)) else glass_st
				_emit_glass_piece(tgt_glass, is_z_wall, glass_start, u1, y_mid, band_h, fixed_coord)
			cursor = maxf(cursor, u1)

		if u_max > cursor + 0.02:
			_emit_wall_piece(wall_st, is_z_wall, cursor, u_max, y_mid, band_h, fixed_coord, thickness)


static func _emit_wall_piece(
	wall_st: SurfaceTool,
	is_z_wall: bool,
	ua: float,
	ub: float,
	y_mid: float,
	band_h: float,
	fixed_coord: float,
	thickness: float
) -> void:
	var u_mid := (ua + ub) * 0.5
	var u_len := ub - ua
	var pos := Vector3(u_mid, y_mid, fixed_coord) if is_z_wall else Vector3(fixed_coord, y_mid, u_mid)
	var size := Vector3(u_len, band_h, thickness) if is_z_wall else Vector3(thickness, band_h, u_len)
	_emit_box(wall_st, pos, size)


static func _emit_glass_piece(
	glass_st: SurfaceTool,
	is_z_wall: bool,
	ua: float,
	ub: float,
	y_mid: float,
	band_h: float,
	fixed_coord: float
) -> void:
	var u_mid := (ua + ub) * 0.5
	var u_len := ub - ua
	var pos := Vector3(u_mid, y_mid, fixed_coord) if is_z_wall else Vector3(fixed_coord, y_mid, u_mid)
	var size := Vector3(u_len, band_h, 0.03) if is_z_wall else Vector3(0.03, band_h, u_len)
	_emit_box(glass_st, pos, size)


static func _build_stair_run(
	st_data: Dictionary,
	has_upper_stair: bool,
	body: StaticBody3D,
	stair_st: SurfaceTool,
	metal_st: SurfaceTool,
	light_metal_st: SurfaceTool,
	glass_st: SurfaceTool
) -> void:
	_build_flight(st_data["flight1_p0"], st_data["flight1_p1"], float(st_data["flight1_w"]), body, stair_st, metal_st, light_metal_st)
	var l_pos: Vector3 = st_data["landing_pos"]
	var l_sz: Vector3 = st_data["landing_size"]
	_add_box_collider(body, l_pos, l_sz)
	_emit_box(stair_st, l_pos, l_sz)
	_emit_box(light_metal_st, Vector3(l_pos.x, l_pos.y + l_sz.y * 0.5 - 0.015, l_pos.z + l_sz.z * 0.5 - 0.03), Vector3(l_sz.x, 0.03, 0.06))

	# Mid-landing open inner guardrail when not bounded by a full drywall partition wall
	var lg_z0 := float(st_data.get("landing_guard_z0", 0.0))
	var lg_z1 := float(st_data.get("landing_guard_z1", 0.0))
	var lg_len := lg_z1 - lg_z0
	if lg_len >= 0.35:
		var lg_x := float(st_data.get("landing_guard_x", l_pos.x))
		var lg_top_y := l_pos.y + l_sz.y * 0.5
		var lg_c := Vector3(lg_x, lg_top_y + 0.46, lg_z0 + lg_len * 0.5)
		_add_box_collider(body, lg_c, Vector3(0.08, 0.92, lg_len))
		_emit_box(light_metal_st, Vector3(lg_x, lg_top_y + 0.90, lg_c.z), Vector3(0.06, 0.05, lg_len))
		_emit_box(glass_st, Vector3(lg_x, lg_top_y + 0.44, lg_c.z), Vector3(0.025, 0.78, lg_len))
		for pz: float in [lg_z0 + 0.04, lg_z1 - 0.04]:
			_emit_box(metal_st, Vector3(lg_x, lg_top_y + 0.45, pz), Vector3(0.055, 0.90, 0.055))

	_build_flight(st_data["flight2_p0"], st_data["flight2_p1"], float(st_data["flight2_w"]), body, stair_st, metal_st, light_metal_st)

	# Continuous horizontal divider rail spanning center stairwell rim between flights
	var f2_p1: Vector3 = st_data["flight2_p1"]
	var wb_x0 := float(st_data.get("well_bridge_x0", 0.0))
	var wb_x1 := float(st_data.get("well_bridge_x1", 0.0))
	if wb_x1 - wb_x0 >= 0.08:
		var wb_cx := (wb_x0 + wb_x1) * 0.5
		var wb_len := (wb_x1 - wb_x0) + 0.02
		_emit_box(light_metal_st, Vector3(wb_cx, f2_p1.y + 0.90, f2_p1.z), Vector3(wb_len, 0.056, 0.052))
		_emit_box(metal_st, Vector3(wb_cx, f2_p1.y + 0.48, f2_p1.z), Vector3(wb_len, 0.032, 0.032))
		if not has_upper_stair:
			var f1_p0: Vector3 = st_data["flight1_p0"]
			_emit_box(metal_st, Vector3(wb_x0, f2_p1.y + 0.44, f1_p0.z), Vector3(0.050, 0.98, 0.050))


static func _build_flight(
	p0: Vector3,
	p1: Vector3,
	width: float,
	body: StaticBody3D,
	stair_st: SurfaceTool,
	metal_st: SurfaceTool,
	light_metal_st: SurfaceTool
) -> void:
	var dir := (p1 - p0).normalized()
	var flight_len := p0.distance_to(p1)
	var bx := Vector3.UP.cross(dir).normalized()
	if bx.length_squared() < 0.001:
		bx = Vector3.RIGHT
	var by := dir.cross(bx).normalized()
	var ramp_basis := Basis(bx, by, dir)
	var ramp_thick := 0.20
	var ramp_center := (p0 + p1) * 0.5 - by * (ramp_thick * 0.5)

	# Smooth sloped ramp collider guarantees frictionless PlayerController walking up/down.
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, ramp_thick, flight_len)
	cs.shape = box
	cs.transform = Transform3D(ramp_basis, ramp_center)
	body.add_child(cs)

	# Continuous structural soffit beam trimmed strictly inside step ends (zero floor/slab protrusion).
	var beam_p0 := p0.lerp(p1, 0.065)
	var beam_p1 := p0.lerp(p1, 0.935)
	var beam_mid := (beam_p0 + beam_p1) * 0.5
	var beam_len := beam_p0.distance_to(beam_p1)
	_emit_box_basis(stair_st, beam_mid - by * 0.11, Vector3(width - 0.06, 0.18, beam_len), ramp_basis)

	# Architectural stepped treads & risers flush at the walk plane.
	var horiz_run := Vector2(p1.x - p0.x, p1.z - p0.z).length()
	var vert_rise := p1.y - p0.y
	var step_count := clampi(int(round(absf(vert_rise) / 0.175)), 7, 13)
	var step_d := horiz_run / float(step_count)
	var step_h := absf(vert_rise) / float(step_count)
	var dir_xz := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z).normalized()
	var stair_yaw := atan2(dir_xz.x, dir_xz.z)

	for si in range(step_count):
		var uc := (float(si) + 0.5) / float(step_count)
		var pt := p0.lerp(p1, uc)
		var y_top := minf(p1.y - 0.004, p0.y + vert_rise * ((float(si) + 0.55) / float(step_count)))
		var riser_h := step_h * 1.15 + 0.03
		var tread_center := Vector3(pt.x, y_top - riser_h * 0.5, pt.z)
		_emit_box_oriented(stair_st, tread_center, Vector3(width - 0.08, riser_h, step_d + 0.015), stair_yaw)
		var nosing_pt := Vector3(pt.x, y_top - 0.01, pt.z) - dir_xz * (step_d * 0.42)
		_emit_box_oriented(light_metal_st, nosing_pt, Vector3(width - 0.08, 0.022, 0.045), stair_yaw)

	# Trimmed side stringers, exact terminal/mid newel posts, and strictly bounded handrails.
	var stringer_mid := beam_mid - by * 0.085
	var rail_top_off := Vector3.UP * 0.90
	var rail_mid_off := Vector3.UP * 0.48
	var q_start := p0.lerp(p1, 0.004)
	var q_end := p0.lerp(p1, 0.996)
	var q_rail_mid := (q_start + q_end) * 0.5
	var rail_len := q_start.distance_to(q_end)
	for side_s: float in [-1.0, 1.0]:
		var lat := bx * (side_s * (width * 0.5 - 0.03))
		_emit_box_basis(metal_st, stringer_mid + lat, Vector3(0.052, 0.16, beam_len), ramp_basis)
		for post_t: float in [0.0, 0.50, 1.0]:
			var post_base := p0.lerp(p1, post_t) + lat - Vector3.UP * 0.05
			_emit_box_oriented(metal_st, post_base + Vector3.UP * 0.49, Vector3(0.050, 0.98, 0.050), stair_yaw)
		_emit_box_basis(light_metal_st, q_rail_mid + lat + rail_top_off, Vector3(0.052, 0.056, rail_len), ramp_basis)
		_emit_box_basis(metal_st, q_rail_mid + lat + rail_mid_off, Vector3(0.028, 0.028, rail_len), ramp_basis)


static func _add_box_collider(body: StaticBody3D, pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	body.add_child(cs)


static func _append_unique_float(arr: Array[float], v: float) -> void:
	for e in arr:
		if absf(e - v) < 0.02:
			return
	arr.append(v)


static func _emit_box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	_emit_box_basis(st, center, size, Basis.IDENTITY)


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
	desired_normal: Vector3
) -> void:
	var n_test := (bl - tl).cross(tr - tl)
	var pts: Array[Vector3]
	var uvs: Array[Vector2]
	if n_test.dot(desired_normal) >= 0.0:
		pts = [tl, tr, bl, tr, br, bl]
		uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	else:
		pts = [tl, bl, tr, tr, bl, br]
		uvs = [Vector2(0, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]
	var n := desired_normal.normalized()
	for i in range(6):
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])


static func _commit(st: SurfaceTool, node_name: String, mat: Material, parent: Node3D, cast_shadows: bool = true) -> MeshInstance3D:
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	if not cast_shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
