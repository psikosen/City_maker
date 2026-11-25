class_name InteriorGenerator
extends RefCounted

## Deterministically synthesizes multi-floor explorable InteriorBlueprints strictly aligned
## with each BuildingBlueprint's footprint, vestibule entrance, floor heights, and window bays.

const SLAB_THICKNESS := 0.18
const PARTITION_THICKNESS := 0.14
const INTERIOR_DOOR_W := 1.20
const INTERIOR_DOOR_H := 2.25
const STAIR_MAX_PITCH_DEG := 32.0
const BFS_CELL := 0.25
const PLAYER_CLEAR_RAD := 0.32


static func generate(bp: BuildingBlueprint, world_seed: int) -> InteriorBlueprint:
	var ib := InteriorBlueprint.new()
	ib.building_id = bp.id
	ib.archetype = bp.archetype
	ib.seed_value = int(hash("%d_%s_interior_2028" % [world_seed, bp.id]))

	var rng := RandomNumberGenerator.new()
	rng.seed = ib.seed_value

	var hw := bp.width * 0.5
	var hd := bp.depth * 0.5
	var wt := bp.wall_thickness
	ib.inner_min = Vector2(-hw + wt, -hd + wt)
	ib.inner_max = Vector2(hw - wt, hd - wt)

	ib.window_openings = BuildingBuilder.get_facade_window_openings(bp)
	var total_wall_h := bp.get_total_wall_height()

	# 1. Compute flush corner switchback stair shaft across all multi-floor runs.
	var has_stairs := bp.floors >= 2
	var stair_rect := Rect2()
	var elev_rect := Rect2()
	var has_elev := false
	var stair_x_on_left := bp.stair_on_left
	if has_stairs:
		var inner_w := ib.inner_max.x - ib.inner_min.x
		var inner_d := ib.inner_max.y - ib.inner_min.y
		var eff_inner_w := inner_w
		var eff_inner_d := inner_d
		if bp.has_setback():
			var upper_tb := bp.get_tier_bounds_local(bp.setback_floor)
			eff_inner_w = minf(inner_w, (float(upper_tb["x1"]) - float(upper_tb["x0"])) - wt * 2.0)
			eff_inner_d = minf(inner_d, (float(upper_tb["z1"]) - float(upper_tb["z0"])) - wt * 2.0)
		var stair_w := clampf(eff_inner_w * 0.42, 2.55, 3.35)
		var sx0 := ib.inner_min.x if stair_x_on_left else (ib.inner_max.x - stair_w)
		var sz_back := ib.inner_min.y
		var max_fh := maxf(bp.ground_floor_height, bp.floor_height)
		var landing_d := clampf(eff_inner_d * 0.16, 1.15, 1.48)
		var desired_run := (max_fh * 0.5) / tan(deg_to_rad(STAIR_MAX_PITCH_DEG))
		var max_stair_d := maxf(3.0, eff_inner_d - 1.85)
		var run_len := clampf(desired_run, 2.0, maxf(2.0, max_stair_d - landing_d))
		var stair_d := minf(max_stair_d, landing_d + run_len)
		stair_rect = Rect2(sx0, sz_back, stair_w, stair_d)

		var elev_w := 2.04
		var elev_d := 2.04
		if (bp.floors >= 5 or (bp.archetype == "hospital" and bp.floors >= 4)) and eff_inner_w >= 8.0 and eff_inner_d >= 7.5 and (eff_inner_w - stair_w) >= 4.2:
			has_elev = true
			var ex0 := stair_rect.end.x if stair_x_on_left else (stair_rect.position.x - elev_w)
			elev_rect = Rect2(ex0, sz_back, elev_w, elev_d)
			var floor_ys := PackedFloat32Array()
			for fl_e in range(bp.floors):
				var fy_e := _floor_y(bp, fl_e)
				var fh_e := bp.ground_floor_height if fl_e == 0 else bp.floor_height
				if minf(fh_e, total_wall_h - fy_e) >= 2.1:
					floor_ys.append(fy_e)
			if floor_ys.size() >= 2:
				ib.elevator = {
					"enabled": true,
					"shaft_rect": elev_rect,
					"floor_ys": floor_ys,
					"door_width": 1.08,
					"door_height": 2.18,
					"shaft_height": total_wall_h,
				}
			else:
				has_elev = false

		for fl in range(bp.floors - 1):
			var y_lo := _floor_y(bp, fl)
			var fh := bp.ground_floor_height if fl == 0 else bp.floor_height
			var y_mid := y_lo + fh * 0.5
			var y_hi := y_lo + fh
			var mid_z := sz_back + landing_d
			var front_z := sz_back + stair_d
			var lane_w := stair_w * 0.39
			var x_f1 := sx0 + stair_w * 0.255
			var x_f2 := sx0 + stair_w * 0.745
			ib.stairs.append({
				"from_floor": fl,
				"to_floor": fl + 1,
				"shaft_rect": stair_rect,
				"flight1_p0": Vector3(x_f1, y_lo, front_z),
				"flight1_p1": Vector3(x_f1, y_mid, mid_z),
				"flight1_w": lane_w,
				"landing_pos": Vector3(sx0 + stair_w * 0.5, y_mid - SLAB_THICKNESS * 0.5, sz_back + landing_d * 0.5),
				"landing_size": Vector3(stair_w, SLAB_THICKNESS, landing_d),
				"flight2_p0": Vector3(x_f2, y_mid, mid_z),
				"flight2_p1": Vector3(x_f2, y_hi, front_z),
				"flight2_w": lane_w,
				"entry_pt_2d": Vector2(x_f1, front_z + 0.55),
				"exit_pt_2d": Vector2(x_f2, front_z + 0.55),
				"well_bridge_x0": x_f1 + lane_w * 0.5 - 0.03,
				"well_bridge_x1": x_f2 - lane_w * 0.5 + 0.03,
				"landing_guard_x": (stair_rect.end.x if stair_x_on_left else stair_rect.position.x),
				"landing_guard_z0": sz_back,
				"landing_guard_z1": mid_z,
			})

	# 2. Generate per-floor room programs, slabs (excluding stair void), partitions, doors, lights, props.
	var all_floors_ok := true
	var r_reach := 0
	var r_total := 0
	var typical_floor_template: Dictionary = {}

	for fl in range(bp.floors):
		var fy := _floor_y(bp, fl)
		var fh := bp.ground_floor_height if fl == 0 else bp.floor_height
		var usable_h := minf(fh, total_wall_h - fy)
		if usable_h < 2.1:
			continue

		if bp.has_setback() and fl == bp.setback_floor:
			typical_floor_template = {}

		var tier_b := bp.get_tier_bounds_local(fl)
		var f_inner_min := Vector2(float(tier_b["x0"]) + wt, float(tier_b["z0"]) + wt)
		var f_inner_max := Vector2(float(tier_b["x1"]) - wt, float(tier_b["z1"]) - wt)
		var full_inner_rect := Rect2(f_inner_min, f_inner_max - f_inner_min)

		# Reuse BFS-verified typical layout on identical middle tower stories within the same tier
		# to eliminate synchronous multi-floor BFS/SAT hitches while keeping full 3D/Jolt geometry.
		if bp.floors >= 5 and fl >= 3 and fl < bp.floors - 1 and not typical_floor_template.is_empty() and absf(usable_h - float(typical_floor_template["height"])) < 0.02:
			var cloned := _clone_typical_floor(typical_floor_template, fl, fy, bp.id)
			ib.floors.append(cloned)
			if bool(cloned.get("bfs_ok", false)):
				r_reach += int(cloned["rooms"].size())
			else:
				all_floors_ok = false
			r_total += int(cloned["rooms"].size())
			continue

		var entry_pt := Vector2(bp.door_local_x, f_inner_max.y - 0.65)
		if fl > 0 and fl - 1 < ib.stairs.size():
			entry_pt = Vector2(ib.stairs[fl - 1]["exit_pt_2d"])

		var stair_next_pt := Vector2.INF
		if fl < bp.floors - 1 and fl < ib.stairs.size():
			stair_next_pt = Vector2(ib.stairs[fl]["entry_pt_2d"])

		var floor_rects: Array[Rect2] = []
		if fl == 0:
			floor_rects = [full_inner_rect]
		else:
			floor_rects = _subtract_rect(full_inner_rect, stair_rect) if has_stairs else [full_inner_rect]
			if has_elev:
				var next_rects: Array[Rect2] = []
				for fr in floor_rects:
					next_rects.append_array(_subtract_rect(fr, elev_rect))
				floor_rects = next_rects

		var layout := _build_floor_layout(
			bp, fl, fy, usable_h, full_inner_rect, stair_rect, has_stairs,
			elev_rect, has_elev, entry_pt, stair_next_pt, f_inner_min, f_inner_max, ib.window_openings, rng
		)

		var stair_wall_end_z := float(layout.get("stair_wall_end_z", -INF))
		if has_stairs and fl < ib.stairs.size():
			var lg_z0 := clampf(maxf(stair_rect.position.y, stair_wall_end_z), stair_rect.position.y, ib.stairs[fl]["landing_guard_z1"])
			if has_elev:
				lg_z0 = minf(ib.stairs[fl]["landing_guard_z1"], maxf(lg_z0, elev_rect.end.y))
			ib.stairs[fl]["landing_guard_z0"] = lg_z0

		var guardrails: Array[Dictionary] = []
		if fl >= 1 and has_stairs:
			var side_rail_x := stair_rect.end.x if stair_x_on_left else stair_rect.position.x
			var rail_z0 := maxf(stair_rect.position.y, stair_wall_end_z)
			if has_elev:
				rail_z0 = maxf(rail_z0, elev_rect.end.y)
			var rail_z_len := stair_rect.end.y - rail_z0
			if rail_z_len >= 0.30:
				guardrails.append({
					"pos": Vector3(side_rail_x, fy + 0.48, rail_z0 + rail_z_len * 0.5),
					"size": Vector3(0.08, 0.96, rail_z_len),
				})
			if fl == bp.floors - 1:
				var half_w := stair_rect.size.x * 0.48
				var rail_cx := stair_rect.position.x + stair_rect.size.x * 0.24
				guardrails.append({
					"pos": Vector3(rail_cx, fy + 0.48, stair_rect.end.y),
					"size": Vector3(half_w, 0.96, 0.08),
				})

		var f_data := {
			"floor_index": fl,
			"base_y": fy,
			"height": usable_h,
			"slab_thickness": SLAB_THICKNESS,
			"entry_point": entry_pt,
			"floor_rects": floor_rects,
			"rooms": layout["rooms"],
			"partitions": layout["partitions"],
			"interior_doors": layout["interior_doors"],
			"furniture": layout["furniture"],
			"lights": layout["lights"],
			"guardrails": guardrails,
		}

		var nav_res := _validate_and_prune_floor_nav(f_data, f_inner_min, f_inner_max, stair_rect, has_stairs and fl > 0, stair_next_pt, elev_rect, has_elev)
		if not bool(nav_res["all_ok"]):
			all_floors_ok = false
		r_reach += int(nav_res["reachable_rooms"])
		r_total += int(nav_res["total_rooms"])
		f_data["bfs_ok"] = nav_res["all_ok"]

		if bp.floors >= 5 and (fl == 2 or (bp.has_setback() and fl == bp.setback_floor)):
			typical_floor_template = f_data

		ib.floors.append(f_data)

	ib.bfs_reachable = all_floors_ok and ib.floors.size() > 0
	ib.reachable_room_count = r_reach
	ib.total_room_count = r_total
	ib.wall_window_conflicts = _count_wall_window_conflicts(ib, bp)
	return ib


static func _build_floor_layout(
	bp: BuildingBlueprint,
	fl: int,
	fy: float,
	fh: float,
	full_rect: Rect2,
	stair_rect: Rect2,
	has_stairs: bool,
	elev_rect: Rect2,
	has_elev: bool,
	entry_pt: Vector2,
	stair_next_pt: Vector2,
	inner_min: Vector2,
	inner_max: Vector2,
	window_openings: Array[Dictionary],
	rng: RandomNumberGenerator
) -> Dictionary:
	var rooms: Array[Dictionary] = []
	var partitions: Array[Dictionary] = []
	var doors: Array[Dictionary] = []
	var furniture: Array[Dictionary] = []
	var lights: Array[Vector3] = []
	var stair_wall_end_z := -INF

	var part_h := maxf(2.2, fh - 0.16)
	var x0 := full_rect.position.x
	var x1 := full_rect.end.x
	var z0 := full_rect.position.y
	var z1 := full_rect.end.y
	var w := full_rect.size.x
	var d := full_rect.size.y

	var floor_style := "tile" if ((BuildingBlueprint.is_commercial_archetype(bp.archetype) or bp.archetype in ["warehouse", "church"]) and fl == 0) else "wood"

	# Grand single-hall layouts for Sanctuary Nave (church), Ground-Floor Apparatus Bay (fire_station), and Civic Rotunda (municipal_hall).
	if bp.archetype == "church":
		var nave_room := {"id": "f0_nave", "name": "Main Sanctuary & Nave", "rect": full_rect, "floor_style": "tile", "center": _safe_center(full_rect, entry_pt)}
		rooms.append(nave_room)
		var church_ctx := {
			"bp": bp,
			"fl": fl,
			"fy": fy,
			"doors": doors,
			"window_openings": window_openings,
			"entry_pt": entry_pt,
			"stair_rect": stair_rect,
			"has_stairs": has_stairs,
			"stair_next_pt": stair_next_pt,
			"inner_min": inner_min,
			"inner_max": inner_max,
			"furniture": furniture,
			"rng": rng,
		}
		FurnitureGenerator.populate_room(church_ctx, full_rect, nave_room["name"], nave_room["id"])
		nave_room["center"] = _pick_clear_room_point(full_rect, furniture, entry_pt)
		for lz_f: float in [0.22, 0.50, 0.78]:
			lights.append(Vector3((x0 + x1) * 0.5, fy + fh - 0.16, lerpf(z0, z1, lz_f)))
		return {"rooms": rooms, "partitions": partitions, "interior_doors": doors, "furniture": furniture, "lights": lights, "stair_wall_end_z": stair_wall_end_z}

	if (bp.archetype == "fire_station" or bp.archetype == "municipal_hall") and fl == 0:
		var stair_on_l_hall := has_stairs and stair_rect.position.x < (x0 + x1) * 0.5
		if has_stairs and stair_rect.end.y - z0 >= 2.2:
			var back_spans_hall := _collect_floor_face_spans(window_openings, fy, fy + part_h, ["back"])
			var sw_x := stair_rect.end.x if stair_on_l_hall else stair_rect.position.x
			var sw_z0 := (z0 + 0.30) if _coord_hits_spans(sw_x, back_spans_hall, 0.20) else z0
			var sw_z1 := stair_rect.position.y + stair_rect.size.y * 0.65
			if sw_z1 - sw_z0 >= 0.55:
				_add_wall_segment(partitions, fy, part_h, Vector2(sw_x, sw_z0), Vector2(sw_x, sw_z1), "partition")
				stair_wall_end_z = sw_z1
		var hall_title := "Apparatus Bay & Watch Desk" if bp.archetype == "fire_station" else "Municipal Rotunda & Court Chamber"
		var hall_room := {"id": "f0_hall", "name": hall_title, "rect": full_rect, "floor_style": "tile", "center": _safe_center(full_rect, entry_pt)}
		rooms.append(hall_room)
		var hall_ctx := {
			"bp": bp,
			"fl": fl,
			"fy": fy,
			"doors": doors,
			"window_openings": window_openings,
			"entry_pt": entry_pt,
			"stair_rect": stair_rect,
			"has_stairs": has_stairs,
			"stair_next_pt": stair_next_pt,
			"inner_min": inner_min,
			"inner_max": inner_max,
			"furniture": furniture,
			"rng": rng,
		}
		FurnitureGenerator.populate_room(hall_ctx, full_rect, hall_room["name"], hall_room["id"])
		hall_room["center"] = _pick_clear_room_point(full_rect, furniture, entry_pt)
		for lz_h: float in [0.28, 0.72]:
			lights.append(Vector3((x0 + x1) * 0.5, fy + fh - 0.15, lerpf(z0, z1, lz_h)))
		return {"rooms": rooms, "partitions": partitions, "interior_doors": doors, "furniture": furniture, "lights": lights, "stair_wall_end_z": stair_wall_end_z}

	# Warehouse: wide open bay + corner supervisor office enclosure (low wall below clerestory).
	if bp.archetype == "warehouse":
		var off_w := clampf(w * 0.28, 3.0, 4.4)
		var off_d := clampf(d * 0.28, 3.0, 4.2)
		var off_x0 := x1 - off_w
		var off_z0 := z0
		var off_h := minf(2.85, part_h)
		var off_rect := Rect2(off_x0, off_z0, off_w, off_d)
		var bay_rect := full_rect
		var bay_name := "Cross-Training Gym Floor" if bp.venue_type == "gym" else ("Hardware Showroom Floor" if bp.venue_type == "hardware" else ("Wholesale Market Floor" if bp.venue_type == "grocery" else "Logistics Bay"))
		rooms.append({"id": "f0_bay", "name": bay_name, "rect": bay_rect, "floor_style": "tile", "center": Vector2(x0 + w * 0.35, (z0 + z1) * 0.5)})
		rooms.append({"id": "f0_office", "name": "Supervisor Office", "rect": off_rect, "floor_style": "wood", "center": off_rect.get_center()})
		# Partition left wall of office (with door) & front wall of office
		var door_z := off_z0 + off_d * 0.5
		_add_partition_with_door(
			partitions, doors, bp.id, "%s_f0_office" % bp.id, fy, off_h,
			Vector2(off_x0, off_z0), Vector2(off_x0, off_z0 + off_d),
			Vector2(off_x0, door_z), false, true, false
		)
		_add_wall_segment(partitions, fy, off_h, Vector2(off_x0, off_z0 + off_d), Vector2(x1, off_z0 + off_d), "partition")
		var wh_ctx := {
			"bp": bp,
			"fl": fl,
			"fy": fy,
			"doors": doors,
			"window_openings": window_openings,
			"entry_pt": entry_pt,
			"stair_rect": stair_rect,
			"has_stairs": has_stairs,
			"stair_next_pt": stair_next_pt,
			"inner_min": inner_min,
			"inner_max": inner_max,
			"furniture": furniture,
			"rng": rng,
		}
		FurnitureGenerator.populate_warehouse(wh_ctx, Rect2(x0, z0, maxf(2.4, off_x0 - x0 - 0.15), d), off_rect)
		for rm in rooms:
			rm["center"] = _pick_clear_room_point(rm["rect"], furniture, entry_pt)
		lights.append(Vector3((x0 + x1) * 0.5, fy + fh - 0.14, (z0 + z1) * 0.5))
		return {"rooms": rooms, "partitions": partitions, "interior_doors": doors, "furniture": furniture, "lights": lights, "stair_wall_end_z": stair_wall_end_z}

	# Collect exterior window spans specifically for this floor's Y range.
	var stair_on_left := has_stairs and stair_rect.position.x < (x0 + x1) * 0.5
	var side_faces := (["right"] if stair_on_left else ["left"]) if has_stairs else ["left", "right"]
	var side_z_spans := _collect_floor_face_spans(window_openings, fy, fy + part_h, side_faces)
	var back_x_spans := _collect_floor_face_spans(window_openings, fy, fy + part_h, ["back"])
	var front_x_spans := _collect_floor_face_spans(window_openings, fy, fy + part_h, ["front"])

	# Determine clear usable zone excluding stair shaft, snapped to piers clear of exterior windows.
	var hall_front_z := (stair_rect.end.y + 0.35) if has_stairs else (z1 - maxf(3.2, d * 0.56))
	var split_z_lo := maxf(z0 + 2.0, stair_rect.end.y + 0.15) if has_stairs else (z0 + 2.0)
	var split_z := _snap_coord(hall_front_z, split_z_lo, z1 - 1.85, side_z_spans, 0.22)
	if not is_nan(split_z) and _coord_hits_spans(split_z, side_z_spans, 0.20):
		split_z = NAN

	var core_right := elev_rect.end.x if (has_elev and stair_on_left) else stair_rect.end.x
	var core_left := elev_rect.position.x if (has_elev and not stair_on_left) else stair_rect.position.x
	var side_zone_x0 := core_right if stair_on_left else x0
	var side_zone_x1 := core_left if (has_stairs and not stair_on_left) else x1
	var side_zone_w := side_zone_x1 - side_zone_x0
	var rear_z1 := minf(split_z if not is_nan(split_z) else (stair_rect.end.y if has_stairs else (z0 + z1) * 0.5), z1 - 0.6)
	var has_rear_zone := side_zone_w >= 2.4 and rear_z1 - z0 >= 2.4

	# Compute rear X split BEFORE placing split_z doorway so split_x never T-bones a door.
	var split_x := NAN
	if has_rear_zone and side_zone_w >= 6.4:
		split_x = _snap_coord((side_zone_x0 + side_zone_x1) * 0.5, side_zone_x0 + 2.6, side_zone_x1 - 2.6, back_x_spans, 0.22)
		if not is_nan(split_x) and _coord_hits_spans(split_x, back_x_spans, 0.20):
			split_x = NAN

	var room_idx := 0
	var front_z0 := split_z if (has_rear_zone and not is_nan(split_z)) else (stair_rect.end.y if has_stairs else z0)
	var front_rect := Rect2(x0, front_z0, w, z1 - front_z0)
	var front_name := _pick_front_room_name(bp, fl)
	var front_room := {"id": "f%d_r%d" % [fl, room_idx], "name": front_name, "rect": front_rect, "floor_style": floor_style, "center": _safe_center(front_rect, entry_pt)}
	rooms.append(front_room)
	room_idx += 1

	# Partition between Front Lobby/Living and Rear/Stair Zone (leaving stair shaft & hall open).
	if has_rear_zone and not is_nan(split_z) and split_z > z0 + 1.8 and z1 - split_z > 2.2:
		var part_x0 := (stair_rect.end.x + 0.1 if stair_on_left else x0) if has_stairs else x0
		var part_x1 := (x1 if stair_on_left else stair_rect.position.x - 0.1) if has_stairs else x1
		if part_x1 - part_x0 >= (3.2 if has_stairs else 6.8):
			var door_cx := clampf(bp.door_local_x if not has_stairs else (part_x0 + part_x1) * 0.5, part_x0 + 0.9, part_x1 - 0.9)
			var can_emit_split_z := true
			if not is_nan(split_x):
				var left_ok := split_x - part_x0 >= 2.1
				var right_ok := part_x1 - split_x >= 2.1
				if left_ok and right_ok:
					var c_l := clampf((part_x0 + split_x) * 0.5, part_x0 + 0.85, split_x - 1.15)
					var c_r := clampf((split_x + part_x1) * 0.5, split_x + 1.15, part_x1 - 0.85)
					door_cx = c_l if absf(c_l - bp.door_local_x) <= absf(c_r - bp.door_local_x) else c_r
				elif right_ok:
					door_cx = clampf((split_x + part_x1) * 0.5, split_x + 1.15, part_x1 - 0.85)
				elif left_ok:
					door_cx = clampf((part_x0 + split_x) * 0.5, part_x0 + 0.85, split_x - 1.15)
				else:
					can_emit_split_z = false
			if can_emit_split_z:
				var is_commercial_door := BuildingBlueprint.is_commercial_archetype(bp.archetype)
				var is_home := bp.archetype == "house_pitched" or bp.archetype == "beach_house"
				var use_arch := (fl == 0 and is_home) if has_stairs else ((bp.archetype == "brick_shop" or is_home) and rng.randf() < 0.35)
				_add_partition_with_door(
					partitions, doors, bp.id, "%s_f%d_d%d" % [bp.id, fl, doors.size()], fy, part_h,
					Vector2(part_x0, split_z), Vector2(part_x1, split_z),
					Vector2(door_cx, split_z), use_arch, is_commercial_door, true
				)

	# Rear Zone beside stair shaft: create 1-2 private rooms snapped to clear X window piers.
	if has_rear_zone:
		if has_stairs and stair_rect.end.y - z0 >= 2.2:
			var stair_wall_x := stair_rect.end.x if stair_on_left else stair_rect.position.x
			var sw_z0 := maxf(z0, elev_rect.end.y) if has_elev else ((z0 + 0.30) if _coord_hits_spans(stair_wall_x, back_x_spans, 0.20) else z0)
			var sw_z1 := minf(rear_z1, stair_rect.end.y - 0.06) if not is_nan(split_z) else (stair_rect.position.y + stair_rect.size.y * 0.65)
			if sw_z1 - sw_z0 >= 0.55:
				_add_wall_segment(partitions, fy, part_h, Vector2(stair_wall_x, sw_z0), Vector2(stair_wall_x, sw_z1), "partition")
				stair_wall_end_z = sw_z1

		if not is_nan(split_x):
			var r1 := Rect2(side_zone_x0, z0, split_x - side_zone_x0, rear_z1 - z0)
			var r2 := Rect2(split_x, z0, side_zone_x1 - split_x, rear_z1 - z0)
			rooms.append({"id": "f%d_r%d" % [fl, room_idx], "name": _pick_rear_room_name(bp, fl, 0), "rect": r1, "floor_style": floor_style, "center": r1.get_center()})
			room_idx += 1
			rooms.append({"id": "f%d_r%d" % [fl, room_idx], "name": _pick_rear_room_name(bp, fl, 1), "rect": r2, "floor_style": floor_style, "center": r2.get_center()})
			room_idx += 1
			var d_z := clampf(z0 + (rear_z1 - z0) * 0.52, z0 + 0.9, rear_z1 - 0.9)
			_add_partition_with_door(
				partitions, doors, bp.id, "%s_f%d_d%d" % [bp.id, fl, doors.size()], fy, part_h,
				Vector2(split_x, z0), Vector2(split_x, rear_z1),
				Vector2(split_x, d_z), false, false, false
			)
		else:
			var r_rear := Rect2(side_zone_x0, z0, side_zone_w, rear_z1 - z0)
			rooms.append({"id": "f%d_r%d" % [fl, room_idx], "name": _pick_rear_room_name(bp, fl, 0), "rect": r_rear, "floor_style": floor_style, "center": r_rear.get_center()})
			room_idx += 1

	# Split oversized Front Showroom/Open Floor ONLY on upper floors (keeps ground floor airy & open through windows).
	if fl >= 1 and front_rect.size.x >= 7.6 and front_rect.size.y >= 3.2:
		var mid_x := _snap_coord((x0 + x1) * 0.5, x0 + 3.0, x1 - 3.0, front_x_spans, 0.22)
		if not is_nan(mid_x) and absf(mid_x - entry_pt.x) > 1.3 and not _coord_hits_spans(mid_x, front_x_spans, 0.20):
			var front_split_z := front_rect.position.y + 1.45  # Leave 1.45m open landing strip across front of stair!
			if z1 - front_split_z >= 2.2:
				var f_door_z := clampf((front_split_z + z1) * 0.5, front_split_z + 0.85, z1 - 0.85)
				_add_partition_with_door(
					partitions, doors, bp.id, "%s_f%d_d%d" % [bp.id, fl, doors.size()], fy, part_h,
					Vector2(mid_x, front_split_z), Vector2(mid_x, z1),
					Vector2(mid_x, f_door_z), false, false, false
				)
				var hall_rect := Rect2(x0, front_rect.position.y, w, front_split_z - front_rect.position.y)
				front_room["rect"] = hall_rect
				front_room["center"] = Vector2(clampf(entry_pt.x, x0 + 0.65, x1 - 0.65), front_rect.position.y + hall_rect.size.y * 0.5)
				var r_a := Rect2(x0, front_split_z, mid_x - x0, z1 - front_split_z)
				var r_b := Rect2(mid_x, front_split_z, x1 - mid_x, z1 - front_split_z)
				rooms.append({"id": "f%d_r%d" % [fl, room_idx], "name": _pick_upper_suite_name(bp, 0), "rect": r_a, "floor_style": floor_style, "center": r_a.get_center()})
				room_idx += 1
				rooms.append({"id": "f%d_r%d" % [fl, room_idx], "name": _pick_upper_suite_name(bp, 1), "rect": r_b, "floor_style": floor_style, "center": r_b.get_center()})
				room_idx += 1

	# Populate parametric, clearance-verified furniture & ceiling LED lights per room.
	var furn_ctx := {
		"bp": bp,
		"fl": fl,
		"fy": fy,
		"doors": doors,
		"window_openings": window_openings,
		"entry_pt": entry_pt,
		"stair_rect": stair_rect,
		"has_stairs": has_stairs,
		"elev_rect": elev_rect,
		"has_elev": has_elev,
		"stair_next_pt": stair_next_pt,
		"inner_min": inner_min,
		"inner_max": inner_max,
		"furniture": furniture,
		"rng": rng,
	}
	for r_dict in rooms:
		var r: Rect2 = r_dict["rect"]
		var rname: String = r_dict["name"]
		var rid: String = r_dict["id"]
		lights.append(Vector3(r.get_center().x, fy + fh - 0.15, r.get_center().y))
		FurnitureGenerator.populate_room(furn_ctx, r, rname, rid)
		r_dict["center"] = _pick_clear_room_point(r, furniture, entry_pt)

	return {
		"rooms": rooms,
		"partitions": partitions,
		"interior_doors": doors,
		"furniture": furniture,
		"lights": lights,
		"stair_wall_end_z": stair_wall_end_z,
	}


static func _pick_clear_room_point(r: Rect2, furniture: Array, fallback_ref: Vector2) -> Vector2:
	var c := r.get_center()
	if _is_point_clear_of_furniture(c, furniture):
		return c
	var best := c
	var best_score := INF
	for frac_y in [0.22, 0.50, 0.78, 0.35, 0.65]:
		for frac_x in [0.22, 0.50, 0.78, 0.35, 0.65]:
			var pt := Vector2(
				lerpf(r.position.x + 0.38, r.end.x - 0.38, frac_x),
				lerpf(r.position.y + 0.38, r.end.y - 0.38, frac_y)
			)
			if _is_point_clear_of_furniture(pt, furniture):
				var sc := pt.distance_to(fallback_ref) + pt.distance_to(c) * 0.5
				if sc < best_score:
					best_score = sc
					best = pt
	return best


static func _is_point_clear_of_furniture(pt: Vector2, furniture: Array) -> bool:
	for fn in furniture:
		var f_pos: Vector3 = fn["pos"]
		var f_sz: Vector3 = fn["size"]
		var f_yaw: float = float(fn.get("yaw", 0.0))
		if FurnitureGenerator.obbs_overlap_2d(pt, 0.28, 0.28, 0.0, Vector2(f_pos.x, f_pos.z), f_sz.x * 0.5, f_sz.z * 0.5, f_yaw, 0.05):
			return false
	return true


static func _validate_and_prune_floor_nav(
	f_data: Dictionary,
	inner_min: Vector2,
	inner_max: Vector2,
	stair_rect: Rect2,
	has_upper_guard: bool,
	stair_next_pt: Vector2,
	elev_rect: Rect2 = Rect2(),
	has_elev: bool = false
) -> Dictionary:
	var targets: Array[Vector2] = []
	for rm in f_data["rooms"]:
		targets.append(Vector2(rm["center"]))
	if stair_next_pt != Vector2.INF:
		targets.append(stair_next_pt)
	if has_elev:
		targets.append(Vector2(elev_rect.get_center().x, elev_rect.end.y + 0.65))

	var entry_pt: Vector2 = f_data["entry_point"]
	var furn: Array = f_data["furniture"]

	var pass_ok := _run_floor_bfs(entry_pt, targets, f_data["partitions"], furn, f_data["guardrails"], inner_min, inner_max, stair_rect, has_upper_guard, elev_rect, has_elev)
	if not bool(pass_ok["all_ok"]) and not furn.is_empty():
		# Drop obstructing furniture one by one from largest down if any tight building corridor gets pinched
		var kept: Array = []
		f_data["furniture"] = []
		for item in furn:
			var trial: Array = kept + [item]
			var chk := _run_floor_bfs(entry_pt, targets, f_data["partitions"], trial, f_data["guardrails"], inner_min, inner_max, stair_rect, has_upper_guard, elev_rect, has_elev)
			if int(chk["reached"]) >= targets.size():
				kept = trial
		f_data["furniture"] = kept
		pass_ok = _run_floor_bfs(entry_pt, targets, f_data["partitions"], kept, f_data["guardrails"], inner_min, inner_max, stair_rect, has_upper_guard, elev_rect, has_elev)

	var room_count: int = f_data["rooms"].size()
	var reachable_rooms := 0
	var hits: Array = pass_ok["hits"]
	for i in range(mini(room_count, hits.size())):
		if bool(hits[i]):
			reachable_rooms += 1

	return {
		"all_ok": bool(pass_ok["all_ok"]),
		"reachable_rooms": reachable_rooms,
		"total_rooms": room_count,
	}


static func _run_floor_bfs(
	start_pt: Vector2,
	targets: Array[Vector2],
	partitions: Array,
	furniture: Array,
	guardrails: Array,
	inner_min: Vector2,
	inner_max: Vector2,
	_stair_rect: Rect2,
	_has_upper_guard: bool,
	elev_rect: Rect2 = Rect2(),
	has_elev: bool = false
) -> Dictionary:
	var w_span := inner_max.x - inner_min.x
	var d_span := inner_max.y - inner_min.y
	var cell_sz := maxf(BFS_CELL, maxf(w_span, d_span) / 140.0)
	var gx := maxi(4, int(ceil(w_span / cell_sz)))
	var gz := maxi(4, int(ceil(d_span / cell_sz)))
	var blocked := PackedByteArray()
	blocked.resize(gx * gz)
	blocked.fill(0)

	if has_elev and elev_rect.size.x > 0.1 and elev_rect.size.y > 0.1:
		_mark_box_blocked(blocked, gx, gz, inner_min, cell_sz, elev_rect.get_center(), elev_rect.size, PLAYER_CLEAR_RAD * 0.65)

	for part in partitions:
		if String(part.get("role", "")) == "header":
			# Header lintel above doorway is high enough to walk underneath
			continue
		var pos: Vector3 = part["pos"]
		var sz: Vector3 = part["size"]
		_mark_box_blocked(blocked, gx, gz, inner_min, cell_sz, Vector2(pos.x, pos.z), Vector2(sz.x, sz.z), PLAYER_CLEAR_RAD * 0.72)

	for gr in guardrails:
		var pos_g: Vector3 = gr["pos"]
		var sz_g: Vector3 = gr["size"]
		_mark_box_blocked(blocked, gx, gz, inner_min, cell_sz, Vector2(pos_g.x, pos_g.z), Vector2(sz_g.x, sz_g.z), PLAYER_CLEAR_RAD * 0.6)

	for fn in furniture:
		var pos_f: Vector3 = fn["pos"]
		var sz_f: Vector3 = fn["size"]
		var rot_xz := FurnitureGenerator.get_rotated_xz_size(sz_f, float(fn.get("yaw", 0.0)))
		_mark_box_blocked(blocked, gx, gz, inner_min, cell_sz, Vector2(pos_f.x, pos_f.z), rot_xz, PLAYER_CLEAR_RAD * 0.52)

	var sx := clampi(int(floor((start_pt.x - inner_min.x) / cell_sz)), 0, gx - 1)
	var sz_i := clampi(int(floor((start_pt.y - inner_min.y) / cell_sz)), 0, gz - 1)
	blocked[sz_i * gx + sx] = 0

	var visited := PackedByteArray()
	visited.resize(gx * gz)
	visited.fill(0)
	var start_idx := sz_i * gx + sx
	var queue := PackedInt32Array()
	queue.resize(gx * gz)
	queue[0] = start_idx
	visited[start_idx] = 1
	var head := 0
	var tail := 1
	var max_x := gx - 1
	var max_z := gz - 1

	while head < tail:
		var cur := queue[head]
		head += 1
		var cx := cur % gx
		var cz := cur / gx
		if cx < max_x:
			var nidx := cur + 1
			if visited[nidx] == 0 and blocked[nidx] == 0:
				visited[nidx] = 1
				queue[tail] = nidx
				tail += 1
		if cx > 0:
			var nidx := cur - 1
			if visited[nidx] == 0 and blocked[nidx] == 0:
				visited[nidx] = 1
				queue[tail] = nidx
				tail += 1
		if cz < max_z:
			var nidx := cur + gx
			if visited[nidx] == 0 and blocked[nidx] == 0:
				visited[nidx] = 1
				queue[tail] = nidx
				tail += 1
		if cz > 0:
			var nidx := cur - gx
			if visited[nidx] == 0 and blocked[nidx] == 0:
				visited[nidx] = 1
				queue[tail] = nidx
				tail += 1

	var reached := 0
	var hits: Array[bool] = []
	for t in targets:
		var tx := clampi(int(floor((t.x - inner_min.x) / cell_sz)), 0, gx - 1)
		var tz := clampi(int(floor((t.y - inner_min.y) / cell_sz)), 0, gz - 1)
		# Accept within 1 cell neighborhood in case exact center aligns near wall
		var hit := false
		for oz in range(-1, 2):
			for ox in range(-1, 2):
				var cx := clampi(tx + ox, 0, gx - 1)
				var cz := clampi(tz + oz, 0, gz - 1)
				if visited[cz * gx + cx] != 0:
					hit = true
					break
			if hit:
				break
		hits.append(hit)
		if hit:
			reached += 1

	return {
		"all_ok": reached == targets.size(),
		"reached": reached,
		"hits": hits,
	}


static func _mark_box_blocked(
	blocked: PackedByteArray,
	gx: int,
	gz: int,
	inner_min: Vector2,
	cell_sz: float,
	center: Vector2,
	size_xz: Vector2,
	pad: float
) -> void:
	var x0 := center.x - size_xz.x * 0.5 - pad
	var x1 := center.x + size_xz.x * 0.5 + pad
	var z0 := center.y - size_xz.y * 0.5 - pad
	var z1 := center.y + size_xz.y * 0.5 + pad
	# Sample cell centers ((i + 0.5) * cell_sz) so doorway openings cannot straddle a boundary and close falsely.
	var ix0 := clampi(int(ceil((x0 - inner_min.x) / cell_sz - 0.5)), 0, gx - 1)
	var ix1 := clampi(int(floor((x1 - inner_min.x) / cell_sz - 0.5)), 0, gx - 1)
	var iz0 := clampi(int(ceil((z0 - inner_min.y) / cell_sz - 0.5)), 0, gz - 1)
	var iz1 := clampi(int(floor((z1 - inner_min.y) / cell_sz - 0.5)), 0, gz - 1)
	if ix1 < ix0 or iz1 < iz0:
		return
	for iz in range(iz0, iz1 + 1):
		for ix in range(ix0, ix1 + 1):
			blocked[iz * gx + ix] = 1


static func _add_wall_segment(partitions: Array, fy: float, part_h: float, a: Vector2, b: Vector2, role: String) -> void:
	var len_v := a.distance_to(b)
	if len_v < 0.08:
		return
	var mid := (a + b) * 0.5
	var along_x := absf(b.x - a.x) >= absf(b.y - a.y)
	var size := Vector3(len_v, part_h, PARTITION_THICKNESS) if along_x else Vector3(PARTITION_THICKNESS, part_h, len_v)
	partitions.append({
		"pos": Vector3(mid.x, fy + part_h * 0.5, mid.y),
		"size": size,
		"role": role,
	})


static func _add_partition_with_door(
	partitions: Array,
	doors: Array,
	bld_id: String,
	door_id: String,
	fy: float,
	part_h: float,
	a: Vector2,
	b: Vector2,
	door_center: Vector2,
	open_arch: bool,
	commercial_glass: bool,
	horizontal: bool
) -> void:
	var d_w := minf(INTERIOR_DOOR_W, a.distance_to(b) * 0.65)
	if d_w < 0.95:
		return
	var d_h := minf(INTERIOR_DOOR_H, part_h - 0.12)
	var dir := (b - a).normalized()
	var da := door_center - dir * (d_w * 0.5)
	var db := door_center + dir * (d_w * 0.5)
	_add_wall_segment(partitions, fy, part_h, a, da, "partition")
	_add_wall_segment(partitions, fy, part_h, db, b, "partition")

	# Header beam above interior doorway
	if part_h > d_h + 0.08:
		var hh := part_h - d_h
		var h_sz := Vector3(d_w, hh, PARTITION_THICKNESS) if horizontal else Vector3(PARTITION_THICKNESS, hh, d_w)
		partitions.append({
			"pos": Vector3(door_center.x, fy + d_h + hh * 0.5, door_center.y),
			"size": h_sz,
			"role": "header",
		})

	var door_yaw := 0.0 if horizontal else -PI * 0.5
	doors.append({
		"building_id": bld_id,
		"door_id": door_id,
		"pos": Vector3(da.x, fy, da.y),
		"yaw": door_yaw,
		"width": d_w,
		"height": d_h,
		"commercial": commercial_glass,
		"is_open_arch": open_arch,
	})


static func _collect_floor_face_spans(openings: Array[Dictionary], p_y0: float, p_y1: float, faces: Array) -> Array[Vector2]:
	var spans: Array[Vector2] = []
	for op in openings:
		if String(op["face"]) in faces:
			var w_y0 := float(op["y_center"]) - float(op["height"]) * 0.5
			var w_y1 := float(op["y_center"]) + float(op["height"]) * 0.5
			if p_y1 <= w_y0 or p_y0 >= w_y1:
				continue
			var uc := float(op["u_center"])
			var hw := float(op["width"]) * 0.5
			spans.append(Vector2(uc - hw, uc + hw))
	return spans


static func _collect_face_spans(openings: Array[Dictionary], faces: Array) -> Array[Vector2]:
	var spans: Array[Vector2] = []
	for op in openings:
		if String(op["face"]) in faces:
			var uc := float(op["u_center"])
			var hw := float(op["width"]) * 0.5
			spans.append(Vector2(uc - hw, uc + hw))
	return spans


static func _coord_hits_spans(val: float, spans: Array[Vector2], margin: float) -> bool:
	for s in spans:
		if val >= s.x - margin and val <= s.y + margin:
			return true
	return false


static func _snap_coord(target: float, lo: float, hi: float, spans: Array[Vector2], margin: float) -> float:
	if hi <= lo:
		return NAN
	var clamped := clampf(target, lo, hi)
	if not _coord_hits_spans(clamped, spans, margin):
		return clamped
	var best := NAN
	var best_dist := INF
	var step := 0.18
	var steps := int(ceil((hi - lo) / step))
	for i in range(steps + 1):
		var c := clampf(lo + float(i) * step, lo, hi)
		if not _coord_hits_spans(c, spans, margin):
			var dist := absf(c - clamped)
			if dist < best_dist:
				best_dist = dist
				best = c
	return best


static func _count_wall_window_conflicts(ib: InteriorBlueprint, bp: BuildingBlueprint) -> int:
	if bp.archetype == "warehouse":
		return 0  # Office partitions stop at 2.85m, below clerestory windows
	var tol := bp.wall_thickness + 0.15
	var conflicts := 0
	for f_data in ib.floors:
		for part in f_data["partitions"]:
			var pos: Vector3 = part["pos"]
			var sz: Vector3 = part["size"]
			var p_y0 := pos.y - sz.y * 0.5
			var p_y1 := pos.y + sz.y * 0.5
			var p_x0 := pos.x - sz.x * 0.5
			var p_x1 := pos.x + sz.x * 0.5
			var p_z0 := pos.z - sz.z * 0.5
			var p_z1 := pos.z + sz.z * 0.5
			for op in ib.window_openings:
				var face: String = op["face"]
				var w_y0 := float(op["y_center"]) - float(op["height"]) * 0.5
				var w_y1 := float(op["y_center"]) + float(op["height"]) * 0.5
				if p_y1 <= w_y0 or p_y0 >= w_y1:
					continue
				var tb := bp.get_tier_bounds_local(int(op.get("floor", 0)))
				var u0 := float(op["u_center"]) - float(op["width"]) * 0.5
				var u1 := float(op["u_center"]) + float(op["width"]) * 0.5
				if face == "front" and p_z1 >= float(tb["z1"]) - tol and p_x1 > u0 and p_x0 < u1:
					conflicts += 1
				elif face == "back" and p_z0 <= float(tb["z0"]) + tol and p_x1 > u0 and p_x0 < u1:
					conflicts += 1
				elif face == "left" and p_x0 <= float(tb["x0"]) + tol and p_z1 > u0 and p_z0 < u1:
					conflicts += 1
				elif face == "right" and p_x1 >= float(tb["x1"]) - tol and p_z1 > u0 and p_z0 < u1:
					conflicts += 1
	return conflicts


static func _subtract_rect(outer: Rect2, hole: Rect2) -> Array[Rect2]:
	var inter := outer.intersection(hole)
	if inter.size.x <= 0.01 or inter.size.y <= 0.01:
		return [outer]
	var out: Array[Rect2] = []
	var top_h := inter.position.y - outer.position.y
	if top_h > 0.05:
		out.append(Rect2(outer.position.x, outer.position.y, outer.size.x, top_h))
	var bot_y := inter.end.y
	var bot_h := outer.end.y - bot_y
	if bot_h > 0.05:
		out.append(Rect2(outer.position.x, bot_y, outer.size.x, bot_h))
	var left_w := inter.position.x - outer.position.x
	if left_w > 0.05:
		out.append(Rect2(outer.position.x, inter.position.y, left_w, inter.size.y))
	var right_x := inter.end.x
	var right_w := outer.end.x - right_x
	if right_w > 0.05:
		out.append(Rect2(right_x, inter.position.y, right_w, inter.size.y))
	return out


static func _safe_center(r: Rect2, fallback: Vector2) -> Vector2:
	var c := r.get_center()
	return c if r.size.x > 0.5 and r.size.y > 0.5 else fallback


static func _floor_y(bp: BuildingBlueprint, fl: int) -> float:
	if fl <= 0:
		return 0.0
	return bp.ground_floor_height + float(fl - 1) * bp.floor_height


static func _clone_typical_floor(tmpl: Dictionary, fl: int, fy: float, bld_id: String) -> Dictionary:
	var dy := fy - float(tmpl["base_y"])
	var dy_v := Vector3(0.0, dy, 0.0)

	var rooms: Array[Dictionary] = []
	for rm in tmpl["rooms"]:
		var r_copy: Dictionary = rm.duplicate()
		var old_id := String(r_copy["id"])
		var suffix_pos := old_id.find("_")
		var suffix := old_id.substr(suffix_pos) if suffix_pos >= 0 else ""
		r_copy["id"] = "f%d%s" % [fl, suffix]
		rooms.append(r_copy)

	var partitions: Array[Dictionary] = []
	for part in tmpl["partitions"]:
		var p_copy: Dictionary = part.duplicate()
		p_copy["pos"] = Vector3(part["pos"]) + dy_v
		partitions.append(p_copy)

	var doors: Array[Dictionary] = []
	var d_src: Array = tmpl["interior_doors"]
	for di in range(d_src.size()):
		var d_copy: Dictionary = d_src[di].duplicate()
		d_copy["door_id"] = "%s_f%d_d%d" % [bld_id, fl, di]
		d_copy["pos"] = Vector3(d_src[di]["pos"]) + dy_v
		doors.append(d_copy)

	var furniture: Array[Dictionary] = []
	for fn in tmpl["furniture"]:
		var f_copy: Dictionary = fn.duplicate()
		var old_rid := String(f_copy.get("room_id", ""))
		var sp := old_rid.find("_")
		var suf := old_rid.substr(sp) if sp >= 0 else ""
		f_copy["room_id"] = "f%d%s" % [fl, suf]
		f_copy["pos"] = Vector3(fn["pos"]) + dy_v
		furniture.append(f_copy)

	var lights: Array[Vector3] = []
	for l_pt in tmpl["lights"]:
		lights.append(Vector3(l_pt) + dy_v)

	var guardrails: Array[Dictionary] = []
	for gr in tmpl["guardrails"]:
		var g_copy: Dictionary = gr.duplicate()
		g_copy["pos"] = Vector3(gr["pos"]) + dy_v
		guardrails.append(g_copy)

	return {
		"floor_index": fl,
		"base_y": fy,
		"height": tmpl["height"],
		"slab_thickness": tmpl["slab_thickness"],
		"entry_point": tmpl["entry_point"],
		"floor_rects": tmpl["floor_rects"],
		"rooms": rooms,
		"partitions": partitions,
		"interior_doors": doors,
		"furniture": furniture,
		"lights": lights,
		"guardrails": guardrails,
		"bfs_ok": tmpl.get("bfs_ok", true),
	}


static func _pick_front_room_name(bp: BuildingBlueprint, fl: int) -> String:
	var arch := bp.archetype
	var venue := bp.venue_type
	var venue_active := venue != "" and venue != "residential" and (fl <= 1 or bp.floors <= 5 or venue in ["tech_office", "music_studio", "bank", "clinic", "hospital", "school", "office", "civic_hall", "city_hall", "police_station", "fire_station", "church", "library", "post_office"])
	if venue_active:
		match venue:
			"hospital":
				return "Emergency Triage & Admitting" if fl == 0 else "Inpatient Nursing Wing"
			"school":
				return "Academic Atrium & Honors Hall" if fl == 0 else "Lecture Hall & Classrooms"
			"church":
				return "Main Sanctuary & Nave"
			"city_hall":
				return "Municipal Rotunda & Court Chamber" if fl == 0 else "Council & Judicial Offices"
			"police_station":
				return "Precinct Lobby & Dispatch" if fl == 0 else "Detective Squad Room"
			"fire_station":
				return "Apparatus Bay & Watch Desk" if fl == 0 else "Firehouse Crew Lounge"
			"library":
				return "Public Library Reading Hall"
			"post_office":
				return "Postal Service Lobby & P.O. Boxes"
			"gym":
				return "Gym Cardio & Turf Floor" if fl == 0 else "Cardio & Strength Studio"
			"cafe":
				return "Roastery & Espresso Bar" if fl == 0 else "Cafe Mezzanine Lounge"
			"grocery":
				return "Market Produce & Aisles"
			"bookstore":
				return "Bookshop Showroom & Reading"
			"clinic":
				return "Clinic Reception & Waiting" if fl == 0 else "Diagnostic Reception"
			"restaurant":
				return "Dining Hall & Host Stand"
			"bank":
				return "Banking Hall & Teller Row"
			"tech_office":
				return "Tech Innovation Lobby" if fl == 0 else "Engineering & Compute Floor"
			"music_studio":
				return "Acoustics Showroom & Console"
			"gallery":
				return "Exhibition Art Gallery"
			"cinema":
				return "Screening Hall & Concessions"
			"bike_shop":
				return "Bicycle Showroom & Repair"
			"ev_showroom":
				return "EV Mobility Concourse"
			"hardware":
				return "Hardware & Workshop Floor"
	if fl == 0:
		match arch:
			"brick_shop", "mixed_use_midrise", "retail_anchor":
				return "Retail Showroom"
			"skyscraper_tower":
				return "Tower Atrium Lobby"
			"modern_office", "civic_hall":
				return "Main Lobby & Reception"
			"apartment_midrise":
				return "Apartment Lobby"
			_:
				return "Living Room"
	match arch:
		"modern_office", "civic_hall", "skyscraper_tower":
			return "Open Workspace"
		_:
			return "Upper Hall & Living"


static func _pick_rear_room_name(bp: BuildingBlueprint, fl: int, slot: int) -> String:
	var arch := bp.archetype
	var venue := bp.venue_type
	var venue_active := venue != "" and venue != "residential" and (fl <= 1 or bp.floors <= 5 or venue in ["tech_office", "music_studio", "bank", "clinic", "hospital", "school", "office", "civic_hall", "city_hall", "police_station", "fire_station", "church", "library", "post_office"])
	if venue_active:
		match venue:
			"hospital":
				return "Inpatient Recovery Suite" if slot == 0 else "Diagnostic & Imaging Room"
			"school":
				return "STEM Classroom Wing" if slot == 0 else "Academic Library & Study"
			"city_hall":
				return "Judicial Chambers & Law Library" if slot == 0 else "Mayor & Clerk Office"
			"police_station":
				return "Holding Cell & Evidence Room" if (fl == 0 and slot == 0) else ("Chief & Sergeants Office" if slot == 1 else "Briefing & Evidence Suite")
			"fire_station":
				return "Crew Bunk Quarters" if slot == 0 else "Chief & Operations Office"
			"library":
				return "Stacks & Reference Wing" if slot == 0 else "Quiet Study Archive"
			"post_office":
				return "Parcel Sorting Bay" if slot == 0 else "Postmaster Office"
			"gym":
				return "Weightlifting & Rack Zone" if slot == 0 else "Locker & Gear Room"
			"cafe":
				return "Kitchen & Pastry Prep" if slot == 0 else "Roastery Stockroom"
			"grocery":
				return "Cold Storage & Prep" if slot == 0 else "Market Stockroom"
			"bookstore":
				return "Archive & Rare Books" if slot == 0 else "Curator Office"
			"clinic":
				return "Exam Suite & Lab" if slot == 0 else "Pharmacy & Med Prep"
			"restaurant":
				return "Commercial Kitchen" if slot == 0 else "Prep & Pantry"
			"bank":
				return "Vault & Security Room" if slot == 0 else "Wealth Advisory Office"
			"tech_office", "music_studio":
				return "Compute & Server Lab" if slot == 0 else "Conference Room"
			"cinema":
				return "Screening Theater Room" if slot == 0 else "Projection & Office"
			"gallery":
				return "Sculpture Atelier" if slot == 0 else "Curator Office"
	if fl == 0:
		if arch in ["brick_shop", "mixed_use_midrise", "retail_anchor"]:
			return "Back Stockroom" if slot == 0 else "Office & Utility"
		if arch in ["modern_office", "civic_hall", "skyscraper_tower"]:
			return "Conference Room" if slot == 0 else "Private Office"
		return "Kitchen & Dining" if slot == 0 else "Study & Bath"
	if arch in ["modern_office", "civic_hall", "skyscraper_tower"]:
		return "Conference Room" if slot == 0 else "Executive Office"
	return "Primary Bedroom" if slot == 0 else "Second Bedroom"


static func _pick_upper_suite_name(bp: BuildingBlueprint, slot: int) -> String:
	var venue := bp.venue_type
	if venue == "hospital":
		return "Patient Care Suite A" if slot == 0 else "Patient Care Suite B"
	if venue == "school":
		return "Classroom Suite A" if slot == 0 else "Seminar Suite B"
	if venue == "fire_station":
		return "Crew Bunk Quarters" if slot == 0 else "Chief & Dispatch Office"
	if venue == "gym" and bp.floors <= 5:
		return "Strength Suite A" if slot == 0 else "Locker Suite B"
	if venue in ["tech_office", "music_studio", "clinic", "bank", "office", "city_hall", "police_station", "library", "post_office"] or bp.archetype in ["modern_office", "civic_hall", "municipal_hall", "police_station", "skyscraper_tower"]:
		return "Workspace Suite A" if slot == 0 else "Workspace Suite B"
	return "Front Living Suite" if slot == 0 else "Front Bedroom"
