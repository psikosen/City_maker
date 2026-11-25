class_name FurnitureGenerator
extends RefCounted

## Parametric interior furniture generator and OBB-clearance placement solver.
## Canonical convention before yaw:
##   size.x = width (local X), size.y = height (local Y), size.z = depth (local Z)
##   +Z is the functional FRONT; -Z is the BACK (flush against wall when wall-hugging).

const WALL_FLUSH_GAP := 0.05
const FREESTAND_PAD := 0.16
const DOOR_CLEAR_RAD := 1.28
const STAIR_APRON_PAD := 0.92
const FURNITURE_GAP := 0.06


static func get_rotated_xz_size(size: Vector3, yaw: float) -> Vector2:
	var c := absf(cos(yaw))
	var s := absf(sin(yaw))
	return Vector2(size.x * c + size.z * s, size.x * s + size.z * c)


static func get_front_dir_2d(yaw: float) -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


static func get_right_dir_2d(yaw: float) -> Vector2:
	return Vector2(cos(yaw), -sin(yaw))


static func obbs_overlap_2d(
	c1: Vector2, hx1: float, hz1: float, yaw1: float,
	c2: Vector2, hx2: float, hz2: float, yaw2: float,
	margin: float = 0.0
) -> bool:
	var d := c2 - c1
	var r1 := get_right_dir_2d(yaw1)
	var f1 := get_front_dir_2d(yaw1)
	var r2 := get_right_dir_2d(yaw2)
	var f2 := get_front_dir_2d(yaw2)

	var a1x := hx1 + margin
	var a1z := hz1 + margin
	var a2x := hx2 + margin
	var a2z := hz2 + margin

	for axis: Vector2 in [r1, f1, r2, f2]:
		var dist := absf(d.dot(axis))
		var p1 := a1x * absf(r1.dot(axis)) + a1z * absf(f1.dot(axis))
		var p2 := a2x * absf(r2.dot(axis)) + a2z * absf(f2.dot(axis))
		if dist >= p1 + p2 - 0.001:
			return false
	return true


static func populate_room(ctx: Dictionary, r: Rect2, rname: String, rid: String) -> void:
	if r.size.x < 2.2 or r.size.y < 2.2:
		return

	var bp: BuildingBlueprint = ctx["bp"]
	var fl: int = int(ctx["fl"])
	var rng: RandomNumberGenerator = ctx["rng"]
	var wall_prefs := _rank_walls_clear_of_doors(r, ctx)
	var venue := bp.venue_type
	var is_venue_active := venue != "" and venue != "residential" and (fl <= 1 or bp.floors <= 5 or venue in ["tech_office", "music_studio", "bank", "clinic", "hospital", "school", "office", "civic_hall", "city_hall", "police_station", "fire_station", "church", "library", "post_office"])

	if venue == "fire_station" and (fl >= 1 and ("Bunk" in rname or "Quarters" in rname)):
		_populate_fire_station_room(ctx, r, rid, true, wall_prefs)
		return
	if "Conference" in rname:
		_populate_conference_room(ctx, r, rid, wall_prefs, rng)
		return
	if "Living" in rname and not is_venue_active:
		_populate_living_room(ctx, r, rid, wall_prefs, rng)
		return
	if ("Kitchen" in rname or "Prep" in rname) and venue != "fire_station":
		if venue in ["restaurant", "cafe"]:
			_populate_commercial_kitchen(ctx, r, rid, wall_prefs, venue)
		else:
			_populate_kitchen_room(ctx, r, rid, wall_prefs, rng)
		return
	if "Bedroom" in rname and venue != "fire_station":
		_populate_bedroom_room(ctx, r, rid, wall_prefs, rng)
		return
	if "Stockroom" in rname or "Archive" in rname:
		if venue == "bookstore":
			_populate_bookstore_room(ctx, r, rid, wall_prefs, rng, true)
		else:
			_populate_stockroom(ctx, r, rid, wall_prefs, rng)
		return

	if is_venue_active:
		var is_secondary := ("Rear" in rname or "Exam" in rname or "Vault" in rname or "Holding" in rname or "Evidence" in rname or "Bunk" in rname or "Rack" in rname or "Locker" in rname or "Office" in rname or "Lab" in rname or "Suite" in rname or "Archive" in rname or "Sorting" in rname or "Chambers" in rname)
		if _populate_venue_room(ctx, r, rid, rname, venue, is_secondary, wall_prefs, rng):
			return

	if "Retail" in rname or "Showroom" in rname:
		_populate_retail_room(ctx, r, rid, wall_prefs, rng)
	elif "Lobby" in rname or "Reception" in rname or "Atrium" in rname or "Concourse" in rname:
		_populate_lobby_room(ctx, r, rid, wall_prefs, rng)
	elif "Office" in rname or "Workspace" in rname or "Study" in rname:
		_populate_office_room(ctx, r, rid, wall_prefs, rng)
	elif "Suite" in rname:
		_populate_bedroom_room(ctx, r, rid, wall_prefs, rng)
	else:
		_try_place_wall_item(ctx, r, rid, "trashcan_indoor", Vector3(0.36, 0.64, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.35, [0.15, 0.85, 0.5])


static func _populate_venue_room(
	ctx: Dictionary,
	r: Rect2,
	rid: String,
	rname: String,
	venue: String,
	is_secondary: bool,
	wall_prefs: Array[String],
	rng: RandomNumberGenerator
) -> bool:
	match venue:
		"gym":
			_populate_gym_room(ctx, r, rid, rname, is_secondary, wall_prefs)
			return true
		"cafe":
			_populate_cafe_room(ctx, r, rid, is_secondary, wall_prefs)
			return true
		"grocery":
			_populate_grocery_room(ctx, r, rid, is_secondary, wall_prefs)
			return true
		"bookstore":
			_populate_bookstore_room(ctx, r, rid, wall_prefs, rng, is_secondary)
			return true
		"clinic":
			_populate_clinic_room(ctx, r, rid, is_secondary, wall_prefs)
			return true
		"restaurant":
			_populate_restaurant_room(ctx, r, rid, is_secondary, wall_prefs)
			return true
		"bank":
			_populate_bank_room(ctx, r, rid, is_secondary, wall_prefs)
			return true
		"tech_office", "music_studio":
			_populate_tech_room(ctx, r, rid, venue, is_secondary, wall_prefs, rng)
			return true
		"gallery":
			_populate_gallery_room(ctx, r, rid, wall_prefs)
			return true
		"cinema":
			_populate_cinema_room(ctx, r, rid, wall_prefs)
			return true
		"bike_shop":
			_populate_bike_room(ctx, r, rid, wall_prefs)
			return true
		"hardware":
			_populate_hardware_room(ctx, r, rid, wall_prefs)
			return true
		"ev_showroom":
			_populate_ev_room(ctx, r, rid, wall_prefs)
			return true
		"church":
			_populate_church_room(ctx, r, rid, wall_prefs)
			return true
		"city_hall":
			_populate_city_hall_room(ctx, r, rid, is_secondary, wall_prefs)
			return true
		"police_station":
			_populate_police_room(ctx, r, rid, is_secondary, wall_prefs)
			return true
		"fire_station":
			_populate_fire_station_room(ctx, r, rid, is_secondary, wall_prefs)
			return true
		"library":
			_populate_library_room(ctx, r, rid, is_secondary, wall_prefs)
			return true
		"post_office":
			_populate_post_office_room(ctx, r, rid, is_secondary, wall_prefs)
			return true
		"hospital":
			_populate_hospital_room(ctx, r, rid, is_secondary, wall_prefs)
			return true
		"school":
			_populate_school_room(ctx, r, rid, is_secondary, wall_prefs)
			return true
	return false


static func _populate_gym_room(ctx: Dictionary, r: Rect2, rid: String, rname: String, is_secondary: bool, wall_prefs: Array[String]) -> void:
	var fl: int = int(ctx["fl"])
	var fy: float = float(ctx["fy"])
	if fl == 0 and not is_secondary and r.size.x >= 5.0:
		_try_place_wall_item(ctx, r, rid, "reception_counter", Vector3(clampf(r.size.x * 0.24, 1.45, 2.05), 1.02, 0.72), ["left", "right", "back"], 0.45, 0.65, [0.78, 0.22])

	if "Locker" in rname:
		_try_place_wall_item(ctx, r, rid, "locker_bank", Vector3(clampf(r.size.x * 0.60, 1.35, 2.25), 1.96, 0.50), wall_prefs, WALL_FLUSH_GAP, 0.60, [0.50, 0.25, 0.75])
		_try_place_wall_item(ctx, r, rid, "weight_bench", Vector3(0.76, 1.10, 1.42), wall_prefs, 0.10, 0.50, [0.75, 0.25, 0.50])
	elif is_secondary:
		# Free weights & squat rack room
		_try_place_wall_item(ctx, r, rid, "squat_rack", Vector3(1.58, 2.12, 1.34), ["back", "left", "right"], 0.08, 0.65, [0.35, 0.65, 0.50])
		_try_place_wall_item(ctx, r, rid, "dumbbell_rack", Vector3(minf(1.68, r.size.x * 0.58), 0.86, 0.56), ["left", "right", "back"], WALL_FLUSH_GAP, 0.55, [0.50, 0.28, 0.72])
		_try_place_wall_item(ctx, r, rid, "weight_bench", Vector3(0.76, 1.10, 1.42), ["right", "left", "back"], 0.14, 0.55, [0.50, 0.75, 0.25])
	else:
		# Cardio + Strength main floor: guaranteed treadmills, bikes, dumbbell rack, squat rack & bench
		for t_pos: float in [0.24, 0.50, 0.76]:
			_try_place_wall_item(ctx, r, rid, "treadmill", Vector3(0.88, 1.32, 1.98), ["left", "right", "back"], 0.10, 0.55, [t_pos])
		_try_place_wall_item(ctx, r, rid, "dumbbell_rack", Vector3(minf(1.68, r.size.x * 0.42), 0.86, 0.56), ["right", "back", "left"], WALL_FLUSH_GAP, 0.55, [0.50, 0.24, 0.76])
		_try_place_wall_item(ctx, r, rid, "squat_rack", Vector3(1.58, 2.12, 1.34), ["back", "right", "left"], 0.10, 0.65, [0.28, 0.72, 0.50])
		for b_frac: float in [0.36, 0.64]:
			var bx := lerpf(r.position.x + 1.2, r.end.x - 1.2, b_frac)
			var bz := r.get_center().y
			_try_place_item(ctx, r, rid, "exercise_bike", Vector3(bx, fy, bz), Vector3(0.62, 1.22, 1.16), 0.0, 0.45)
		if r.size.x >= 7.0 and r.size.y >= 4.2:
			_try_place_item(ctx, r, rid, "weight_bench", Vector3(r.get_center().x, fy, r.position.y + r.size.y * 0.66), Vector3(0.76, 1.10, 1.42), 0.0, 0.50)

	_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.16, 0.84, 0.45])


static func _populate_cafe_room(ctx: Dictionary, r: Rect2, rid: String, is_secondary: bool, wall_prefs: Array[String]) -> void:
	var fy: float = float(ctx["fy"])
	if is_secondary:
		_try_place_wall_item(ctx, r, rid, "kitchen_counter", Vector3(clampf(r.size.x * 0.54, 1.50, 2.60), 0.94, 0.68), wall_prefs, WALL_FLUSH_GAP, 0.65, [0.50, 0.30, 0.70])
		_try_place_wall_item(ctx, r, rid, "bakery_rack", Vector3(1.28, 1.76, 0.50), wall_prefs, WALL_FLUSH_GAP, 0.55, [0.25, 0.75, 0.50])
		_try_place_wall_item(ctx, r, rid, "trashcan_indoor", Vector3(0.36, 0.64, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.35, [0.15, 0.85])
		return

	var bw := clampf(r.size.x * 0.36, 1.65, 2.50)
	var bar := _try_place_wall_item(ctx, r, rid, "espresso_bar", Vector3(bw, 1.22, 0.82), ["back", "left", "right"], 0.52, 0.72, [0.50, 0.30, 0.70])
	if bar.is_empty():
		_try_place_wall_item(ctx, r, rid, "espresso_bar", Vector3(minf(bw, 1.75), 1.22, 0.78), wall_prefs, WALL_FLUSH_GAP, 0.65, [0.50, 0.25, 0.75])
	_try_place_wall_item(ctx, r, rid, "bakery_rack", Vector3(minf(1.36, r.size.x * 0.36), 1.76, 0.50), ["left", "right", "back"], WALL_FLUSH_GAP, 0.55, [0.42, 0.70])

	var cols := 2 if r.size.x >= 5.5 else 1
	for ci in range(cols):
		var tx := lerpf(r.position.x + 1.5, r.end.x - 1.5, 0.5 if cols == 1 else (0.30 + 0.40 * float(ci)))
		var tz := r.position.y + r.size.y * 0.56
		var tbl := _try_place_item(ctx, r, rid, "cafe_table", Vector3(tx, fy, tz), Vector3(0.84, 0.75, 0.84), 0.0, 0.40)
		if not tbl.is_empty():
			_populate_table_chairs(ctx, r, rid, tbl, "dining_chair", Vector3(0.46, 0.88, 0.46), 1)
	_try_place_wall_item(ctx, r, rid, "plant_pot", Vector3(0.46, 1.18, 0.46), wall_prefs, 0.10, 0.25, [0.14, 0.86])
	_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.85, 0.15])


static func _populate_grocery_room(ctx: Dictionary, r: Rect2, rid: String, is_secondary: bool, wall_prefs: Array[String]) -> void:
	var fy: float = float(ctx["fy"])
	if is_secondary:
		_try_place_wall_item(ctx, r, rid, "cooler_case", Vector3(minf(1.95, r.size.x * 0.58), 2.04, 0.76), wall_prefs, WALL_FLUSH_GAP, 0.65, [0.50, 0.25, 0.75])
		_try_place_wall_item(ctx, r, rid, "warehouse_rack", Vector3(minf(1.85, r.size.x * 0.52), 2.10, 0.70), wall_prefs, WALL_FLUSH_GAP, 0.55, [0.25, 0.75])
		_try_place_wall_item(ctx, r, rid, "trashcan_indoor", Vector3(0.36, 0.64, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.35, [0.16, 0.84])
		return

	_try_place_wall_item(ctx, r, rid, "cooler_case", Vector3(clampf(r.size.x * 0.32, 1.65, 2.25), 2.04, 0.78), ["back", "left", "right"], WALL_FLUSH_GAP, 0.70, [0.28, 0.72, 0.50])
	_try_place_wall_item(ctx, r, rid, "cooler_case", Vector3(clampf(r.size.y * 0.36, 1.65, 2.20), 2.04, 0.78), ["left", "right", "back"], WALL_FLUSH_GAP, 0.70, [0.50, 0.28, 0.72])
	_try_place_wall_item(ctx, r, rid, "checkout_lane", Vector3(minf(2.10, r.size.x * 0.34), 1.00, 0.78), ["right", "front", "left"], 0.35, 0.65, [0.72, 0.28, 0.50])

	var aisle_w := clampf(r.size.x * 0.26, 1.55, 2.05)
	for ax_frac: float in [0.34, 0.66]:
		var gx := lerpf(r.position.x + 1.4, r.end.x - 1.4, ax_frac)
		var gz := r.get_center().y
		_try_place_item(ctx, r, rid, "grocery_gondola", Vector3(gx, fy, gz), Vector3(aisle_w, 1.62, 0.84), PI * 0.5 if r.size.y > r.size.x else 0.0, 0.55)
	_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.16, 0.84])


static func _populate_bookstore_room(ctx: Dictionary, r: Rect2, rid: String, wall_prefs: Array[String], _rng: RandomNumberGenerator, is_secondary: bool) -> void:
	var fy: float = float(ctx["fy"])
	if not is_secondary:
		_try_place_wall_item(ctx, r, rid, "reception_counter", Vector3(clampf(r.size.x * 0.26, 1.45, 2.05), 1.02, 0.72), ["left", "right", "back"], 0.45, 0.65, [0.78, 0.22])
	for s_side: String in ["left", "right", "back"]:
		_try_place_wall_item(ctx, r, rid, "bookstore_shelf", Vector3(clampf(minf(r.size.x, r.size.y) * 0.42, 1.35, 1.95), 2.10, 0.46), [s_side], WALL_FLUSH_GAP, 0.55, [0.35, 0.65, 0.50])
	if r.size.x >= 5.2 and r.size.y >= 3.6 and not is_secondary:
		var island := _try_place_item(ctx, r, rid, "bookstore_shelf", Vector3(r.get_center().x - 0.9, fy, r.get_center().y), Vector3(1.58, 1.42, 0.68), 0.0, 0.45)
		if island.is_empty():
			_try_place_item(ctx, r, rid, "cafe_table", Vector3(r.get_center().x, fy, r.get_center().y), Vector3(0.90, 0.76, 0.90), 0.0, 0.40)
		_try_place_wall_item(ctx, r, rid, "armchair", Vector3(0.84, 0.82, 0.84), wall_prefs, 0.12, 0.55, [0.22, 0.78])
	elif is_secondary:
		var dk := _try_place_wall_item(ctx, r, rid, "workstation_desk", Vector3(1.42, 0.76, 0.70), wall_prefs, WALL_FLUSH_GAP, 0.70, [0.50, 0.25, 0.75])
		if not dk.is_empty():
			_try_pair_chair(ctx, r, rid, dk, "office_chair")
	_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.16, 0.84])


static func _populate_clinic_room(ctx: Dictionary, r: Rect2, rid: String, is_secondary: bool, wall_prefs: Array[String]) -> void:
	if is_secondary:
		_try_place_wall_item(ctx, r, rid, "exam_table", Vector3(0.84, 0.88, 1.86), ["back", "left", "right"], 0.12, 0.65, [0.50, 0.30, 0.70])
		_try_place_wall_item(ctx, r, rid, "med_cabinet", Vector3(minf(1.45, r.size.x * 0.48), 1.96, 0.52), ["left", "right", "back"], WALL_FLUSH_GAP, 0.55, [0.50, 0.28, 0.72])
		var desk := _try_place_wall_item(ctx, r, rid, "workstation_desk", Vector3(1.32, 0.76, 0.68), wall_prefs, WALL_FLUSH_GAP, 0.65, [0.80, 0.20])
		if not desk.is_empty():
			_try_pair_chair(ctx, r, rid, desk, "office_chair")
		_try_place_wall_item(ctx, r, rid, "trashcan_indoor", Vector3(0.36, 0.64, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.35, [0.16, 0.84])
		return

	_try_place_wall_item(ctx, r, rid, "reception_counter", Vector3(clampf(r.size.x * 0.34, 1.65, 2.40), 1.04, 0.76), ["back", "left", "right"], 0.55, 0.72, [0.50, 0.70, 0.30])
	_try_place_wall_item(ctx, r, rid, "med_cabinet", Vector3(1.38, 1.96, 0.50), ["right", "left", "back"], WALL_FLUSH_GAP, 0.55, [0.30, 0.70])
	var sofa := _try_place_wall_item(ctx, r, rid, "sofa", Vector3(clampf(r.size.y * 0.38, 1.55, 2.05), 0.82, 0.84), ["left", "right"], WALL_FLUSH_GAP, 0.75, [0.50, 0.30, 0.70])
	if not sofa.is_empty():
		_try_pair_front_item(ctx, r, rid, sofa, "coffee_table", Vector3(1.02, 0.44, 0.56), 0.46, 0.0)
	_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.16, 0.84])


static func _populate_restaurant_room(ctx: Dictionary, r: Rect2, rid: String, is_secondary: bool, wall_prefs: Array[String]) -> void:
	var fy: float = float(ctx["fy"])
	if is_secondary:
		_populate_commercial_kitchen(ctx, r, rid, wall_prefs, "restaurant")
		return
	_try_place_wall_item(ctx, r, rid, "dining_booth", Vector3(clampf(r.size.y * 0.36, 1.45, 1.85), 1.00, 0.70), ["left", "right", "back"], WALL_FLUSH_GAP, 0.70, [0.40, 0.65])
	_try_place_wall_item(ctx, r, rid, "dining_booth", Vector3(clampf(r.size.y * 0.36, 1.45, 1.85), 1.00, 0.70), ["right", "left", "back"], WALL_FLUSH_GAP, 0.70, [0.40, 0.65])
	_try_place_wall_item(ctx, r, rid, "reception_counter", Vector3(minf(1.45, r.size.x * 0.24), 1.02, 0.66), ["back", "right", "left"], 0.40, 0.65, [0.80, 0.20])
	var cols := 2 if r.size.x >= 5.6 else 1
	for ci in range(cols):
		var tx := lerpf(r.position.x + 1.6, r.end.x - 1.6, 0.5 if cols == 1 else (0.30 + 0.40 * float(ci)))
		var tbl := _try_place_item(ctx, r, rid, "dining_table", Vector3(tx, fy, r.get_center().y), Vector3(1.20, 0.76, 0.84), 0.0, 0.50)
		if not tbl.is_empty():
			_populate_table_chairs(ctx, r, rid, tbl, "dining_chair", Vector3(0.46, 0.88, 0.46), 2)
	_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.16, 0.84])


static func _populate_commercial_kitchen(ctx: Dictionary, r: Rect2, rid: String, wall_prefs: Array[String], venue: String) -> void:
	_try_place_wall_item(ctx, r, rid, "kitchen_pass", Vector3(clampf(r.size.x * 0.56, 1.55, 2.40), 1.36, 0.78), ["back", "left", "right"], WALL_FLUSH_GAP, 0.70, [0.50, 0.30, 0.70])
	_try_place_wall_item(ctx, r, rid, "cooler_case" if venue == "restaurant" else "bakery_rack", Vector3(minf(1.65, r.size.x * 0.44), 1.96, 0.70), ["left", "right", "back"], WALL_FLUSH_GAP, 0.55, [0.50, 0.25, 0.75])
	_try_place_wall_item(ctx, r, rid, "trashcan_indoor", Vector3(0.38, 0.68, 0.38), wall_prefs, WALL_FLUSH_GAP, 0.35, [0.16, 0.84])


static func _populate_bank_room(ctx: Dictionary, r: Rect2, rid: String, is_secondary: bool, wall_prefs: Array[String]) -> void:
	if is_secondary:
		_try_place_wall_item(ctx, r, rid, "safe_vault_cabinet", Vector3(1.36, 1.90, 0.74), ["back", "left", "right"], WALL_FLUSH_GAP, 0.75, [0.50, 0.30, 0.70])
		var desk := _try_place_wall_item(ctx, r, rid, "workstation_desk", Vector3(1.48, 0.76, 0.72), wall_prefs, WALL_FLUSH_GAP, 0.70, [0.30, 0.70])
		if not desk.is_empty():
			_try_pair_chair(ctx, r, rid, desk, "office_chair")
		_try_place_wall_item(ctx, r, rid, "trashcan_indoor", Vector3(0.36, 0.64, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.35, [0.85, 0.15])
		return

	_try_place_wall_item(ctx, r, rid, "teller_counter", Vector3(clampf(r.size.x * 0.42, 1.75, 2.55), 1.44, 0.80), ["back", "right", "left"], 0.62, 0.75, [0.50, 0.30, 0.70])
	_try_place_wall_item(ctx, r, rid, "atm_kiosk", Vector3(0.86, 1.84, 0.64), ["left", "right", "front"], WALL_FLUSH_GAP, 0.65, [0.35, 0.65, 0.50])
	_try_place_wall_item(ctx, r, rid, "atm_kiosk", Vector3(0.86, 1.84, 0.64), ["left", "right", "front"], WALL_FLUSH_GAP, 0.65, [0.65, 0.35])
	_try_place_wall_item(ctx, r, rid, "sofa", Vector3(1.75, 0.82, 0.84), ["right", "left"], WALL_FLUSH_GAP, 0.65, [0.50])
	_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.16, 0.84])


static func _populate_tech_room(ctx: Dictionary, r: Rect2, rid: String, venue: String, is_secondary: bool, wall_prefs: Array[String], rng: RandomNumberGenerator) -> void:
	_try_place_wall_item(ctx, r, rid, "studio_console", Vector3(clampf(r.size.x * 0.36, 1.65, 2.15), 1.04, 0.90), ["back", "left", "right"], WALL_FLUSH_GAP, 0.75, [0.50, 0.32, 0.68])
	for s_t: float in [0.22, 0.44, 0.68]:
		_try_place_wall_item(ctx, r, rid, "server_rack", Vector3(0.86, 2.08, 0.90), ["left", "right", "back"], WALL_FLUSH_GAP, 0.60, [s_t])
	if not is_secondary and venue == "tech_office":
		_try_place_wall_item(ctx, r, rid, "reception_counter", Vector3(1.75, 1.04, 0.74), ["right", "back", "left"], 0.45, 0.70, [0.70, 0.30])
	else:
		_populate_office_room(ctx, r, rid, wall_prefs, rng)
	_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.16, 0.84])


static func _populate_gallery_room(ctx: Dictionary, r: Rect2, rid: String, wall_prefs: Array[String]) -> void:
	var fy: float = float(ctx["fy"])
	_try_place_wall_item(ctx, r, rid, "reception_counter", Vector3(minf(1.85, r.size.x * 0.28), 1.02, 0.72), ["left", "right", "back"], 0.45, 0.65, [0.80, 0.20])
	for gx_f: float in [0.30, 0.50, 0.70]:
		var gx := lerpf(r.position.x + 1.2, r.end.x - 1.2, gx_f)
		var gz := lerpf(r.position.y + 1.2, r.end.y - 1.2, 0.38 if absf(gx_f - 0.50) > 0.05 else 0.62)
		_try_place_item(ctx, r, rid, "gallery_pedestal", Vector3(gx, fy, gz), Vector3(0.80, 1.56, 0.80), 0.0, 0.50)
	_try_place_wall_item(ctx, r, rid, "sofa", Vector3(1.70, 0.82, 0.80), wall_prefs, 0.14, 0.65, [0.50, 0.25])
	_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.86, 0.14])


static func _populate_cinema_room(ctx: Dictionary, r: Rect2, rid: String, wall_prefs: Array[String]) -> void:
	var fy: float = float(ctx["fy"])
	var scr_w := clampf(r.size.x * 0.52, 2.0, 3.2)
	_try_place_wall_item(ctx, r, rid, "cinema_screen", Vector3(scr_w, 1.95, 0.24), ["back", "left", "right"], WALL_FLUSH_GAP, 0.85, [0.50])
	for rz_f: float in [0.46, 0.68]:
		var sz_row := clampf(r.size.x * 0.48, 1.85, 2.45)
		_try_place_item(ctx, r, rid, "cinema_seats", Vector3(r.get_center().x, fy, r.position.y + r.size.y * rz_f), Vector3(sz_row, 0.98, 0.78), PI, 0.45)
	_try_place_wall_item(ctx, r, rid, "reception_counter", Vector3(1.65, 1.02, 0.70), ["left", "right"], 0.40, 0.60, [0.82, 0.22])
	_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.16, 0.84])


static func _populate_bike_room(ctx: Dictionary, r: Rect2, rid: String, wall_prefs: Array[String]) -> void:
	var fy: float = float(ctx["fy"])
	_try_place_wall_item(ctx, r, rid, "workbench", Vector3(clampf(r.size.x * 0.34, 1.55, 2.05), 1.48, 0.76), ["back", "left", "right"], WALL_FLUSH_GAP, 0.65, [0.30, 0.70, 0.50])
	_try_place_wall_item(ctx, r, rid, "reception_counter", Vector3(1.65, 1.02, 0.72), ["left", "right", "back"], 0.45, 0.65, [0.76, 0.24])
	for bx_f: float in [0.32, 0.68]:
		_try_place_item(ctx, r, rid, "bike_display_stand", Vector3(lerpf(r.position.x + 1.3, r.end.x - 1.3, bx_f), fy, r.get_center().y), Vector3(1.70, 1.24, 0.58), 0.0, 0.45)
	_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.16, 0.84])


static func _populate_hardware_room(ctx: Dictionary, r: Rect2, rid: String, wall_prefs: Array[String]) -> void:
	var fy: float = float(ctx["fy"])
	_try_place_wall_item(ctx, r, rid, "workbench", Vector3(clampf(r.size.x * 0.38, 1.60, 2.15), 1.48, 0.76), ["back", "left", "right"], WALL_FLUSH_GAP, 0.65, [0.50, 0.25, 0.75])
	_try_place_wall_item(ctx, r, rid, "reception_counter", Vector3(1.75, 1.02, 0.74), ["right", "left", "back"], 0.45, 0.65, [0.75, 0.25])
	_try_place_item(ctx, r, rid, "grocery_gondola", Vector3(r.get_center().x, fy, r.get_center().y), Vector3(clampf(r.size.x * 0.34, 1.55, 2.10), 1.62, 0.84), 0.0, 0.50)
	_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.16, 0.84])


static func _populate_ev_room(ctx: Dictionary, r: Rect2, rid: String, wall_prefs: Array[String]) -> void:
	_try_place_wall_item(ctx, r, rid, "ev_totem", Vector3(1.02, 2.02, 0.52), ["back", "left", "right"], 0.14, 0.65, [0.30, 0.70, 0.50])
	_try_place_wall_item(ctx, r, rid, "ev_totem", Vector3(1.02, 2.02, 0.52), ["left", "right", "back"], 0.14, 0.65, [0.50, 0.25])
	_populate_lobby_room(ctx, r, rid, wall_prefs, ctx["rng"])


static func _populate_church_room(ctx: Dictionary, r: Rect2, rid: String, wall_prefs: Array[String]) -> void:
	var bp: BuildingBlueprint = ctx["bp"]
	var fy: float = float(ctx["fy"])
	var cx := r.get_center().x
	# High chancel altar & speaker pulpit facing the nave (+Z)
	var altar_w := clampf(r.size.x * 0.22, 1.95, 2.65)
	_try_place_item(ctx, r, rid, "altar_table", Vector3(cx, fy, r.position.y + 1.05), Vector3(altar_w, 1.08, 0.98), 0.0, 0.65)
	var pulpit_x := clampf(cx - minf(2.4, r.size.x * 0.22), r.position.x + 1.15, cx - 1.55)
	_try_place_item(ctx, r, rid, "pulpit", Vector3(pulpit_x, fy, r.position.y + 1.68), Vector3(0.92, 1.32, 0.78), 0.0, 0.45)

	# Symmetrical nave church_pew banks flanking generous 2.1m central aisle aligned with doorway
	var aisle_x := clampf(bp.door_local_x, r.position.x + 2.4, r.end.x - 2.4)
	var aisle_hw := 1.05
	var left_col_w := (aisle_x - aisle_hw) - (r.position.x + 0.55)
	var right_col_w := (r.end.x - 0.55) - (aisle_x + aisle_hw)
	var pew_z0 := r.position.y + 3.45
	var pew_z1 := r.end.y - 2.85
	var n_rows := clampi(int(floor((pew_z1 - pew_z0) / 1.38)) + 1, 2, 10)
	for ri in range(n_rows):
		var pz := lerpf(pew_z0, pew_z1, 0.5 if n_rows == 1 else float(ri) / float(n_rows - 1))
		if left_col_w >= 1.75:
			var pw_l := clampf(left_col_w - 0.30, 1.75, 4.2)
			var px_l := (r.position.x + 0.55 + (aisle_x - aisle_hw)) * 0.5
			_try_place_item(ctx, r, rid, "church_pew", Vector3(px_l, fy, pz), Vector3(pw_l, 0.96, 0.74), PI, 0.30)
		if right_col_w >= 1.75:
			var pw_r := clampf(right_col_w - 0.30, 1.75, 4.2)
			var px_r := ((aisle_x + aisle_hw) + r.end.x - 0.55) * 0.5
			_try_place_item(ctx, r, rid, "church_pew", Vector3(px_r, fy, pz), Vector3(pw_r, 0.96, 0.74), PI, 0.30)

	_try_place_wall_item(ctx, r, rid, "plant_pot", Vector3(0.46, 1.18, 0.46), ["back", "left", "right"], 0.14, 0.25, [0.14, 0.86])
	_try_place_wall_item(ctx, r, rid, "trashcan_indoor", Vector3(0.36, 0.64, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.35, [0.15, 0.85])


static func _populate_city_hall_room(ctx: Dictionary, r: Rect2, rid: String, is_secondary: bool, wall_prefs: Array[String]) -> void:
	var fy: float = float(ctx["fy"])
	var fl: int = int(ctx["fl"])
	if fl == 0 and not is_secondary:
		var cx := r.get_center().x
		var stair_r: Rect2 = ctx.get("stair_rect", Rect2())
		var judge_zone_x0 := maxf(r.position.x + 0.6, (stair_r.end.x + 0.6) if (bool(ctx.get("has_stairs", false)) and stair_r.position.x < cx) else r.position.x + 0.6)
		var judge_zone_x1 := minf(r.end.x - 0.6, (stair_r.position.x - 0.6) if (bool(ctx.get("has_stairs", false)) and stair_r.position.x >= cx) else r.end.x - 0.6)
		var chamber_cx := (judge_zone_x0 + judge_zone_x1) * 0.5
		var chamber_w := judge_zone_x1 - judge_zone_x0
		# Raised Judge's Bench & Clerk Witness Pulpit
		var jb_w := clampf(chamber_w * 0.46, 2.5, 3.8)
		var bench := _try_place_item(ctx, r, rid, "judge_bench", Vector3(chamber_cx, fy, r.position.y + 1.35), Vector3(jb_w, 1.24, 1.22), 0.0, 0.70)
		if bench.is_empty():
			bench = _try_place_item(ctx, r, rid, "judge_bench", Vector3(cx, fy, r.position.y + 1.45), Vector3(2.8, 1.24, 1.20), 0.0, 0.60)
		_try_place_item(ctx, r, rid, "pulpit", Vector3(clampf(chamber_cx - jb_w * 0.5 - 0.9, r.position.x + 1.0, chamber_cx - 1.8), fy, r.position.y + 2.2), Vector3(0.92, 1.32, 0.78), 0.0, 0.45)

		# Spectator court_bench gallery rows facing judicial bench
		var gal_z0 := r.position.y + 4.35
		var gal_z1 := r.end.y - 3.35
		for gz_f: float in [0.22, 0.58]:
			var gz := lerpf(gal_z0, maxf(gal_z0 + 1.6, gal_z1), gz_f)
			var bw := clampf(r.size.x * 0.25, 1.85, 3.1)
			_try_place_item(ctx, r, rid, "court_bench", Vector3(r.position.x + r.size.x * 0.24, fy, gz), Vector3(bw, 0.96, 0.72), PI, 0.35)
			_try_place_item(ctx, r, rid, "court_bench", Vector3(r.position.x + r.size.x * 0.76, fy, gz), Vector3(bw, 0.96, 0.72), PI, 0.35)

		_try_place_wall_item(ctx, r, rid, "reception_counter", Vector3(clampf(r.size.x * 0.22, 1.65, 2.25), 1.02, 0.74), ["left", "right"], 0.40, 0.65, [0.76, 0.24])
		_try_place_wall_item(ctx, r, rid, "plant_pot", Vector3(0.46, 1.18, 0.46), wall_prefs, 0.14, 0.25, [0.14, 0.86])
		_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.84, 0.16])
	else:
		_populate_office_room(ctx, r, rid, wall_prefs, ctx["rng"])
		_try_place_wall_item(ctx, r, rid, "bookstore_shelf", Vector3(1.55, 1.98, 0.46), ["left", "right", "back"], WALL_FLUSH_GAP, 0.50, [0.50, 0.28])


static func _populate_police_room(ctx: Dictionary, r: Rect2, rid: String, is_secondary: bool, wall_prefs: Array[String]) -> void:
	if is_secondary:
		var cell_sz := Vector3(clampf(r.size.x * 0.46, 1.95, 2.55), 2.32, clampf(r.size.y * 0.42, 1.55, 1.95))
		var cell := _try_place_wall_item(ctx, r, rid, "holding_cell", cell_sz, ["left", "back", "right", "front"], WALL_FLUSH_GAP, 0.55, [0.35, 0.65, 0.50])
		if cell.is_empty():
			var fy: float = float(ctx["fy"])
			var c := r.get_center()
			_try_place_item(ctx, r, rid, "holding_cell", Vector3(c.x, fy, c.y), cell_sz, 0.0, 0.45)
		_try_place_wall_item(ctx, r, rid, "safe_vault_cabinet", Vector3(1.12, 1.98, 0.78), ["right", "back", "left"], WALL_FLUSH_GAP, 0.65, [0.50, 0.25])
		_try_place_wall_item(ctx, r, rid, "locker_bank", Vector3(clampf(r.size.x * 0.42, 1.35, 1.95), 1.96, 0.50), wall_prefs, WALL_FLUSH_GAP, 0.55, [0.72, 0.28])
		_try_place_wall_item(ctx, r, rid, "trashcan_indoor", Vector3(0.36, 0.64, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.35, [0.16, 0.84])
		return

	_try_place_wall_item(ctx, r, rid, "reception_counter", Vector3(clampf(r.size.x * 0.32, 1.75, 2.45), 1.04, 0.76), ["back", "right", "left"], 0.55, 0.75, [0.68, 0.32, 0.50])
	var desk := _try_place_wall_item(ctx, r, rid, "workstation_desk", Vector3(clampf(r.size.x * 0.28, 1.45, 1.85), 0.76, 0.74), ["left", "right", "back"], WALL_FLUSH_GAP, 0.75, [0.32, 0.68, 0.50])
	if not desk.is_empty():
		_try_pair_chair(ctx, r, rid, desk, "office_chair")
	_try_place_wall_item(ctx, r, rid, "sofa", Vector3(1.72, 0.82, 0.82), ["right", "left", "back"], WALL_FLUSH_GAP, 0.65, [0.68, 0.32])
	_try_place_wall_item(ctx, r, rid, "locker_bank", Vector3(1.55, 1.96, 0.50), wall_prefs, WALL_FLUSH_GAP, 0.55, [0.22, 0.78])
	_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.86, 0.14])


static func _populate_hospital_room(ctx: Dictionary, r: Rect2, rid: String, is_secondary: bool, wall_prefs: Array[String]) -> void:
	var fy: float = float(ctx["fy"])
	var fl: int = int(ctx["fl"])
	if is_secondary or fl >= 1:
		# Inpatient surgical recovery ward & diagnostic beds + sterile medical supply cabinets
		var bed_sz := Vector3(1.06, 1.85, 2.12)
		var b1 := _try_place_wall_item(ctx, r, rid, "hospital_bed", bed_sz, ["left", "right", "back"], WALL_FLUSH_GAP, 0.55, [0.32, 0.68, 0.50])
		if r.size.x >= 5.0 and not b1.is_empty():
			_try_place_wall_item(ctx, r, rid, "hospital_bed", bed_sz, ["right", "left", "back"], WALL_FLUSH_GAP, 0.55, [0.68, 0.32, 0.50])
		_try_place_wall_item(ctx, r, rid, "med_cabinet", Vector3(1.36, 1.98, 0.52), ["back", "left", "right"], WALL_FLUSH_GAP, 0.55, [0.50, 0.24, 0.76])
		var ns := _try_place_wall_item(ctx, r, rid, "workstation_desk", Vector3(1.42, 0.76, 0.70), wall_prefs, WALL_FLUSH_GAP, 0.65, [0.24, 0.76, 0.50])
		if not ns.is_empty():
			_try_pair_chair(ctx, r, rid, ns, "office_chair")
		_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.14, 0.86])
		return

	# ER Ground Lobby: Triage & Intake Counter, Waiting Lounge, Exam Bed, Pharmacy Supply
	_try_place_wall_item(ctx, r, rid, "reception_counter", Vector3(clampf(r.size.x * 0.34, 1.85, 2.65), 1.04, 0.78), ["back", "right", "left"], 0.55, 0.75, [0.62, 0.38, 0.50])
	_try_place_wall_item(ctx, r, rid, "med_cabinet", Vector3(1.42, 1.98, 0.52), ["left", "right", "back"], WALL_FLUSH_GAP, 0.60, [0.30, 0.70])
	_try_place_wall_item(ctx, r, rid, "exam_table", Vector3(0.92, 0.92, 1.94), ["right", "left", "back"], 0.14, 0.55, [0.38, 0.65])
	var w_sofa := _try_place_wall_item(ctx, r, rid, "sofa", Vector3(1.88, 0.82, 0.84), wall_prefs, WALL_FLUSH_GAP, 0.75, [0.25, 0.75, 0.50])
	if not w_sofa.is_empty():
		_try_pair_front_item(ctx, r, rid, w_sofa, "coffee_table", Vector3(1.05, 0.44, 0.56), 0.46, 0.0)
	_try_place_wall_item(ctx, r, rid, "plant_pot", Vector3(0.46, 1.18, 0.46), wall_prefs, 0.10, 0.25, [0.12, 0.88])
	_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.85, 0.15])


static func _populate_school_room(ctx: Dictionary, r: Rect2, rid: String, is_secondary: bool, wall_prefs: Array[String]) -> void:
	var fy: float = float(ctx["fy"])
	var fl: int = int(ctx["fl"])
	if fl == 0 and not is_secondary:
		# Academic Atrium & Student Concourse: Reception/Office counter, Bookcases, Trophy Pedestals
		_try_place_wall_item(ctx, r, rid, "reception_counter", Vector3(clampf(r.size.x * 0.30, 1.75, 2.40), 1.02, 0.74), ["back", "left", "right"], 0.50, 0.72, [0.64, 0.36, 0.50])
		_try_place_wall_item(ctx, r, rid, "bookstore_shelf", Vector3(1.65, 2.04, 0.46), ["left", "right", "back"], WALL_FLUSH_GAP, 0.55, [0.35, 0.70])
		_try_place_item(ctx, r, rid, "gallery_pedestal", Vector3(r.position.x + r.size.x * 0.32, fy, r.position.y + r.size.y * 0.46), Vector3(0.80, 1.56, 0.80), 0.0, 0.45)
		_try_place_wall_item(ctx, r, rid, "sofa", Vector3(1.75, 0.82, 0.82), wall_prefs, WALL_FLUSH_GAP, 0.65, [0.24, 0.76])
		_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.84, 0.16])
		return

	# Lecture Hall / Classroom / Science Lab: Instructor lectern + student school_desk grid + bookshelves
	_try_place_item(ctx, r, rid, "pulpit", Vector3(r.get_center().x, fy, r.position.y + 1.05), Vector3(0.92, 1.32, 0.78), 0.0, 0.45)
	_try_place_wall_item(ctx, r, rid, "bookstore_shelf", Vector3(minf(1.65, r.size.x * 0.42), 2.02, 0.46), ["back", "left", "right"], WALL_FLUSH_GAP, 0.55, [0.22, 0.78])
	for rz_f: float in [0.44, 0.68]:
		for rx_f: float in [0.32, 0.66]:
			var dx := lerpf(r.position.x + 1.1, r.end.x - 1.1, rx_f)
			var dz := lerpf(r.position.y + 1.4, r.end.y - 1.0, rz_f)
			_try_place_item(ctx, r, rid, "school_desk", Vector3(dx, fy, dz), Vector3(0.76, 0.90, 0.92), PI, 0.35)
	_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.15, 0.85])


static func _populate_fire_station_room(ctx: Dictionary, r: Rect2, rid: String, is_secondary: bool, wall_prefs: Array[String]) -> void:
	var fl: int = int(ctx["fl"])
	var fy: float = float(ctx["fy"])
	if fl == 0 and not is_secondary:
		var bp: BuildingBlueprint = ctx["bp"]
		var stair_r: Rect2 = ctx.get("stair_rect", Rect2())
		var left_bound := maxf(stair_r.end.x if bool(ctx.get("has_stairs", false)) else r.position.x, bp.door_local_x + 1.5)
		var bay_x0 := minf(r.end.x - 3.6, left_bound + 0.55)
		var bay_w := r.end.x - bay_x0
		var bay_cx := bay_x0 + bay_w * 0.5
		var bay_cz := r.get_center().y + 0.35
		var truck_w := clampf(bay_w - 1.1, 2.05, 2.48)
		var truck_l := clampf(r.size.y - 3.0, 4.8, 6.2)
		var truck_sz := Vector3(truck_w, 2.68, truck_l)
		for dx_off: float in [0.0, -0.75, 0.75, -1.4, 1.4]:
			var placed_t := false
			for dz_off: float in [0.0, -0.55, 0.55, 1.0]:
				var candidate := Vector3(clampf(bay_cx + dx_off, bay_x0 + truck_w * 0.5 + 0.25, r.end.x - truck_w * 0.5 - 0.35), fy, clampf(bay_cz + dz_off, r.position.y + truck_l * 0.5 + 0.5, r.end.y - truck_l * 0.5 - 0.65))
				if not _try_place_item(ctx, r, rid, "fire_truck", candidate, truck_sz, 0.0, 0.45).is_empty():
					placed_t = true
					break
			if placed_t:
				break
		_try_place_wall_item(ctx, r, rid, "workbench", Vector3(clampf(bay_w * 0.36, 1.55, 2.15), 1.48, 0.74), ["right", "back"], WALL_FLUSH_GAP, 0.60, [0.30, 0.70, 0.50])
		_try_place_wall_item(ctx, r, rid, "locker_bank", Vector3(clampf(r.size.x * 0.24, 1.45, 2.05), 1.96, 0.50), ["left", "back"], WALL_FLUSH_GAP, 0.55, [0.76, 0.24, 0.50])
		var watch_desk := _try_place_wall_item(ctx, r, rid, "workstation_desk", Vector3(1.50, 0.76, 0.72), ["left", "front"], WALL_FLUSH_GAP, 0.70, [0.78, 0.22])
		if not watch_desk.is_empty():
			_try_pair_chair(ctx, r, rid, watch_desk, "office_chair")
		_try_place_wall_item(ctx, r, rid, "trashcan_indoor", Vector3(0.36, 0.64, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.35, [0.16, 0.84])
		return

	if is_secondary:
		var bed := _try_place_wall_item(ctx, r, rid, "queen_bed", Vector3(1.52, 0.86, 1.98), ["back", "right", "left"], WALL_FLUSH_GAP, 0.45, [0.50, 0.28, 0.72])
		if not bed.is_empty():
			_try_pair_side_item(ctx, r, rid, bed, "nightstand", Vector3(0.46, 0.56, 0.42), true)
		_try_place_wall_item(ctx, r, rid, "locker_bank", Vector3(1.45, 1.96, 0.50), wall_prefs, WALL_FLUSH_GAP, 0.55, [0.22, 0.78])
		_try_place_wall_item(ctx, r, rid, "trashcan_indoor", Vector3(0.36, 0.64, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.35, [0.85, 0.15])
	else:
		_populate_kitchen_room(ctx, r, rid, wall_prefs, ctx["rng"])
		_try_place_wall_item(ctx, r, rid, "sofa", Vector3(1.72, 0.82, 0.82), ["left", "right"], WALL_FLUSH_GAP, 0.75, [0.68, 0.32])


static func _populate_library_room(ctx: Dictionary, r: Rect2, rid: String, is_secondary: bool, wall_prefs: Array[String]) -> void:
	_populate_bookstore_room(ctx, r, rid, wall_prefs, ctx["rng"], is_secondary)
	if not is_secondary and r.size.x >= 5.5 and r.size.y >= 4.2:
		var fy: float = float(ctx["fy"])
		var c := r.get_center()
		var study := _try_place_item(ctx, r, rid, "dining_table", Vector3(c.x, fy, c.y + r.size.y * 0.14), Vector3(1.65, 0.76, 0.92), 0.0, 0.50)
		if not study.is_empty():
			_populate_table_chairs(ctx, r, rid, study, "dining_chair", Vector3(0.46, 0.88, 0.46), 2)


static func _populate_post_office_room(ctx: Dictionary, r: Rect2, rid: String, is_secondary: bool, wall_prefs: Array[String]) -> void:
	var fy: float = float(ctx["fy"])
	if is_secondary:
		var rack := _try_place_wall_item(ctx, r, rid, "warehouse_rack", Vector3(0.92, 2.15, clampf(r.size.y * 0.48, 1.65, 2.8)), ["left", "right", "back"], WALL_FLUSH_GAP, 0.55, [0.50, 0.30])
		if rack.is_empty():
			_try_place_wall_item(ctx, r, rid, "workbench", Vector3(clampf(r.size.x * 0.55, 1.45, 2.2), 1.48, 0.74), wall_prefs, WALL_FLUSH_GAP, 0.55)
		_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.16, 0.84])
		return
	_try_place_wall_item(ctx, r, rid, "teller_counter", Vector3(clampf(r.size.x * 0.42, 2.1, 3.2), 1.12, 0.80), ["back", "left", "right"], 0.68, 0.75, [0.50, 0.25, 0.75])
	_try_place_wall_item(ctx, r, rid, "locker_bank", Vector3(clampf(r.size.x * 0.38, 1.65, 2.45), 1.96, 0.50), ["left", "right", "back"], WALL_FLUSH_GAP, 0.60, [0.42, 0.65])
	_try_place_wall_item(ctx, r, rid, "atm_kiosk", Vector3(0.84, 1.56, 0.56), ["right", "left", "front"], 0.08, 0.65, [0.72, 0.28])
	_try_place_item(ctx, r, rid, "workbench", Vector3(r.get_center().x, fy, r.get_center().y + 0.6), Vector3(1.45, 1.44, 0.74), 0.0, 0.55)
	_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.86, 0.14])


static func populate_warehouse(ctx: Dictionary, bay_rect: Rect2, office_rect: Rect2) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var fy: float = ctx["fy"]
	var off_prefs := _rank_walls_clear_of_doors(office_rect, ctx)
	var desk_item := _try_place_wall_item(ctx, office_rect, "f0_office", "workstation_desk", Vector3(1.50, 0.76, 0.72), off_prefs, WALL_FLUSH_GAP, 0.75)
	if not desk_item.is_empty():
		_try_pair_chair(ctx, office_rect, "f0_office", desk_item, "office_chair")
		_try_pair_side_item(ctx, office_rect, "f0_office", desk_item, "trashcan_indoor", Vector3(0.36, 0.64, 0.36))
	else:
		_try_place_wall_item(ctx, office_rect, "f0_office", "trashcan_indoor", Vector3(0.36, 0.64, 0.36), off_prefs, WALL_FLUSH_GAP, 0.35, [0.2, 0.8])

	# Place heavy storage racks clear of central truck/door lane and supervisor office,
	# or populate venue-specific warehouse interiors (e.g., crossfit gym / wholesale grocer / hardware).
	var bp: BuildingBlueprint = ctx["bp"]
	if bp.venue_type in ["gym", "grocery", "hardware"]:
		populate_room(ctx, bay_rect, "Main Showroom", "f0_bay")
		return
	var rack_d := clampf(bay_rect.size.y * 0.42, 2.2, 4.8)
	var rack_cols := maxi(1, int(floor((bay_rect.size.x - 4.6) / 3.2)))
	for ri in range(rack_cols):
		var rx := bay_rect.position.x + 1.15 + float(ri) * 2.85
		if absf(rx - bp.door_local_x) < 2.0:
			continue
		var rack_sz := Vector3(0.92, 2.55, rack_d)
		var rz := bay_rect.position.y + rack_d * 0.5 + 1.25
		if rng.randf() < 0.35 and bay_rect.size.y > rack_d + 4.2:
			rz = bay_rect.get_center().y
		_try_place_item(ctx, bay_rect, "f0_bay", "warehouse_rack", Vector3(rx, fy, rz), rack_sz, 0.0, 0.45)

	var bay_prefs := _rank_walls_clear_of_doors(bay_rect, ctx)
	_try_place_wall_item(ctx, bay_rect, "f0_bay", "trashcan_recycle", Vector3(0.54, 0.68, 0.36), bay_prefs, WALL_FLUSH_GAP, 0.40, [0.16, 0.84, 0.30, 0.70])
	_try_place_wall_item(ctx, bay_rect, "f0_bay", "trashcan_indoor", Vector3(0.36, 0.64, 0.36), ["left", "right", "back"], WALL_FLUSH_GAP, 0.35, [0.85, 0.15])


static func _populate_retail_room(ctx: Dictionary, r: Rect2, rid: String, wall_prefs: Array[String], rng: RandomNumberGenerator) -> void:
	var cw := clampf(r.size.x * 0.34, 1.55, 2.45)
	var counter := _try_place_wall_item(ctx, r, rid, "reception_counter", Vector3(cw, 1.02, 0.74), ["back", "right", "left"], 0.62, 0.72, [0.72, 0.28, 0.50])
	if counter.is_empty():
		_try_place_wall_item(ctx, r, rid, "reception_counter", Vector3(minf(cw, 1.85), 1.02, 0.70), wall_prefs, WALL_FLUSH_GAP, 0.70)

	var rack_len := clampf(minf(r.size.x, r.size.y) * 0.38, 1.45, 2.35)
	_try_place_wall_item(ctx, r, rid, "retail_rack", Vector3(rack_len, 1.62, 0.62), ["left", "right", "back"], WALL_FLUSH_GAP, 0.65, [0.45, 0.65, 0.25])
	if r.size.x >= 7.0 and r.size.y >= 4.2:
		_try_place_wall_item(ctx, r, rid, "retail_rack", Vector3(rack_len, 1.62, 0.62), ["right", "left", "back"], WALL_FLUSH_GAP, 0.65, [0.55, 0.30])
	if rng.randf() < 0.75:
		_try_place_wall_item(ctx, r, rid, "plant_pot", Vector3(0.46, 1.18, 0.46), wall_prefs, 0.10, 0.20, [0.14, 0.86])
	_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.45, [0.18, 0.82, 0.35, 0.65])


static func _populate_lobby_room(ctx: Dictionary, r: Rect2, rid: String, wall_prefs: Array[String], _rng: RandomNumberGenerator) -> void:
	var cw := clampf(r.size.x * 0.32, 1.65, 2.50)
	var counter := _try_place_wall_item(ctx, r, rid, "reception_counter", Vector3(cw, 1.04, 0.76), ["back", "right", "left"], 0.55, 0.75, [0.68, 0.32, 0.50])
	if not counter.is_empty():
		_try_pair_side_item(ctx, r, rid, counter, "trashcan_recycle", Vector3(0.54, 0.68, 0.36))
	else:
		_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.45, [0.20, 0.80])

	var sofa := _try_place_wall_item(ctx, r, rid, "sofa", Vector3(clampf(r.size.y * 0.38, 1.55, 2.10), 0.82, 0.84), ["left", "right", "front", "back"], WALL_FLUSH_GAP, 0.85, [0.50, 0.32, 0.68])
	if not sofa.is_empty():
		_try_pair_front_item(ctx, r, rid, sofa, "coffee_table", Vector3(1.08, 0.44, 0.58), 0.46, 0.0)
	_try_place_wall_item(ctx, r, rid, "plant_pot", Vector3(0.46, 1.18, 0.46), wall_prefs, 0.10, 0.25, [0.12, 0.88, 0.28])
	_try_place_wall_item(ctx, r, rid, "trashcan_indoor", Vector3(0.36, 0.64, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.35, [0.86, 0.14, 0.72])


static func _populate_living_room(ctx: Dictionary, r: Rect2, rid: String, wall_prefs: Array[String], rng: RandomNumberGenerator) -> void:
	var sofa_w := clampf(minf(r.size.x, r.size.y) * 0.46, 1.55, 2.15)
	var sofa := _try_place_wall_item(ctx, r, rid, "sofa", Vector3(sofa_w, 0.82, 0.84), ["right", "left", "back"], WALL_FLUSH_GAP, 0.90, [0.50, 0.34, 0.66])
	if not sofa.is_empty():
		_try_pair_front_item(ctx, r, rid, sofa, "coffee_table", Vector3(clampf(sofa_w * 0.56, 0.85, 1.18), 0.44, 0.56), 0.46, 0.0)
		_try_pair_side_item(ctx, r, rid, sofa, "plant_pot", Vector3(0.44, 1.14, 0.44))

	if r.size.x >= 5.2:
		_try_place_wall_item(ctx, r, rid, "armchair", Vector3(0.82, 0.82, 0.82), ["back", "left", "right"], 0.14, 0.65, [0.28, 0.72])
	if rng.randf() < 0.70:
		_try_place_wall_item(ctx, r, rid, "bookshelf", Vector3(1.32, 1.84, 0.40), ["left", "right", "back"], WALL_FLUSH_GAP, 0.55, [0.25, 0.75, 0.50])
	_try_place_wall_item(ctx, r, rid, "trashcan_indoor", Vector3(0.36, 0.64, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.35, [0.14, 0.86, 0.35])


static func _populate_kitchen_room(ctx: Dictionary, r: Rect2, rid: String, wall_prefs: Array[String], _rng: RandomNumberGenerator) -> void:
	var kc_w := clampf(maxf(r.size.x, r.size.y) * 0.54, 1.85, 3.05)
	var kc := _try_place_wall_item(ctx, r, rid, "kitchen_counter", Vector3(kc_w, 0.92, 0.68), ["back", "left", "right"], WALL_FLUSH_GAP, 0.80, [0.50, 0.30, 0.70])
	if not kc.is_empty():
		_try_pair_side_item(ctx, r, rid, kc, "trashcan_recycle", Vector3(0.52, 0.68, 0.36))
	else:
		_try_place_wall_item(ctx, r, rid, "trashcan_indoor", Vector3(0.36, 0.64, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.35, [0.16, 0.84])

	var fy: float = ctx["fy"]
	var center := r.get_center()
	if r.size.x >= 3.8 and r.size.y >= 3.8:
		var dt_sz := Vector3(clampf(r.size.x * 0.34, 1.15, 1.65), 0.76, 0.86)
		var table := _try_place_item(ctx, r, rid, "dining_table", Vector3(center.x, fy, center.y), dt_sz, 0.0, 0.55)
		if not table.is_empty():
			_populate_table_chairs(ctx, r, rid, table, "dining_chair", Vector3(0.46, 0.88, 0.46), 2)
	_try_place_wall_item(ctx, r, rid, "trashcan_indoor", Vector3(0.36, 0.64, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.35, [0.85, 0.15])


static func _populate_bedroom_room(ctx: Dictionary, r: Rect2, rid: String, wall_prefs: Array[String], _rng: RandomNumberGenerator) -> void:
	var bed_sz := Vector3(1.56, 0.86, 2.02)
	var bed := _try_place_wall_item(ctx, r, rid, "queen_bed", bed_sz, ["back", "right", "left", "front"], WALL_FLUSH_GAP, 0.45, [0.50, 0.68, 0.32])
	if not bed.is_empty():
		_try_pair_side_item(ctx, r, rid, bed, "nightstand", Vector3(0.46, 0.56, 0.42), true)

	var desk := _try_place_wall_item(ctx, r, rid, "workstation_desk", Vector3(minf(1.36, r.size.x * 0.42), 0.76, 0.68), wall_prefs, WALL_FLUSH_GAP, 0.75, [0.28, 0.72, 0.50])
	if not desk.is_empty():
		_try_pair_chair(ctx, r, rid, desk, "office_chair")
		_try_pair_side_item(ctx, r, rid, desk, "trashcan_indoor", Vector3(0.34, 0.60, 0.34))
	else:
		_try_place_wall_item(ctx, r, rid, "trashcan_indoor", Vector3(0.36, 0.64, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.35, [0.15, 0.85])


static func _populate_conference_room(ctx: Dictionary, r: Rect2, rid: String, wall_prefs: Array[String], _rng: RandomNumberGenerator) -> void:
	var fy: float = ctx["fy"]
	var long_x := r.size.x >= r.size.y
	var yaw := 0.0 if long_x else PI * 0.5
	var len_u := clampf(maxf(r.size.x, r.size.y) * 0.52, 1.85, 3.10)
	var wid_v := clampf(minf(r.size.x, r.size.y) * 0.32, 0.95, 1.25)
	var t_sz := Vector3(len_u, 0.76, wid_v)
	var c := r.get_center()
	var table := _try_place_item(ctx, r, rid, "conference_table", Vector3(c.x, fy, c.y), t_sz, yaw, 0.55)
	if not table.is_empty():
		_populate_table_chairs(ctx, r, rid, table, "office_chair", Vector3(0.54, 0.92, 0.54), 3)
	_try_place_wall_item(ctx, r, rid, "plant_pot", Vector3(0.46, 1.18, 0.46), wall_prefs, 0.10, 0.25, [0.14, 0.86])
	_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.85, 0.15])


static func _populate_office_room(ctx: Dictionary, r: Rect2, rid: String, wall_prefs: Array[String], rng: RandomNumberGenerator) -> void:
	var dw := clampf(maxf(r.size.x, r.size.y) * 0.32, 1.35, 1.78)
	var desk_sz := Vector3(dw, 0.76, 0.74)
	var desk1 := _try_place_wall_item(ctx, r, rid, "workstation_desk", desk_sz, wall_prefs, WALL_FLUSH_GAP, 0.75, [0.35, 0.65, 0.50])
	if not desk1.is_empty():
		_try_pair_chair(ctx, r, rid, desk1, "office_chair")
		_try_pair_side_item(ctx, r, rid, desk1, "trashcan_indoor", Vector3(0.36, 0.64, 0.36))

	# Large open workspaces hold a second workstation desk + chair + bookshelf
	if r.size.x >= 5.8 and r.size.y >= 3.8:
		var desk2 := _try_place_wall_item(ctx, r, rid, "workstation_desk", desk_sz, wall_prefs, WALL_FLUSH_GAP, 0.75, [0.76, 0.24, 0.50])
		if not desk2.is_empty():
			_try_pair_chair(ctx, r, rid, desk2, "office_chair")
	if rng.randf() < 0.75:
		_try_place_wall_item(ctx, r, rid, "bookshelf", Vector3(1.36, 1.85, 0.42), wall_prefs, WALL_FLUSH_GAP, 0.55, [0.18, 0.82, 0.50])
	_try_place_wall_item(ctx, r, rid, "trashcan_recycle", Vector3(0.54, 0.68, 0.36), wall_prefs, WALL_FLUSH_GAP, 0.40, [0.86, 0.14, 0.25, 0.75])
	if rng.randf() < 0.55:
		_try_place_wall_item(ctx, r, rid, "plant_pot", Vector3(0.46, 1.18, 0.46), wall_prefs, 0.10, 0.25, [0.12, 0.88])


static func _populate_stockroom(ctx: Dictionary, r: Rect2, rid: String, wall_prefs: Array[String], _rng: RandomNumberGenerator) -> void:
	var shelf_w := clampf(minf(r.size.x, r.size.y) * 0.60, 1.25, 2.20)
	_try_place_wall_item(ctx, r, rid, "bookshelf", Vector3(shelf_w, 2.00, 0.56), ["left", "back", "right"], WALL_FLUSH_GAP, 0.55, [0.50, 0.28, 0.72])
	_try_place_wall_item(ctx, r, rid, "trashcan_indoor", Vector3(0.38, 0.68, 0.38), wall_prefs, WALL_FLUSH_GAP, 0.35, [0.82, 0.18])


static func _populate_table_chairs(ctx: Dictionary, r: Rect2, rid: String, table: Dictionary, chair_kind: String, chair_sz: Vector3, max_per_side: int) -> void:
	var fy: float = ctx["fy"]
	var t_pos: Vector3 = table["pos"]
	var t_sz: Vector3 = table["size"]
	var t_yaw: float = float(table["yaw"])
	var right := get_right_dir_2d(t_yaw)
	var front := get_front_dir_2d(t_yaw)
	var t_c := Vector2(t_pos.x, t_pos.z)

	var slots := mini(max_per_side, maxi(1, int(floor((t_sz.x - 0.15) / (chair_sz.x + 0.20)))))
	var offset_fb := t_sz.z * 0.5 + chair_sz.z * 0.5 + 0.16
	for s_i in range(slots):
		var frac := 0.5 if slots == 1 else float(s_i) / float(slots - 1)
		var u := lerpf(-t_sz.x * 0.34, t_sz.x * 0.34, frac)
		var p_front := t_c + right * u + front * offset_fb
		_try_place_item(ctx, r, rid, chair_kind, Vector3(p_front.x, fy, p_front.y), chair_sz, t_yaw + PI, 0.30)
		var p_back := t_c + right * u - front * offset_fb
		_try_place_item(ctx, r, rid, chair_kind, Vector3(p_back.x, fy, p_back.y), chair_sz, t_yaw, 0.30)


static func _try_pair_chair(ctx: Dictionary, r: Rect2, rid: String, desk: Dictionary, chair_kind: String) -> Dictionary:
	var c_sz := Vector3(0.56, 0.94, 0.56)
	var d_pos: Vector3 = desk["pos"]
	var d_sz: Vector3 = desk["size"]
	var d_yaw: float = float(desk["yaw"])
	var front := get_front_dir_2d(d_yaw)
	var p2 := Vector2(d_pos.x, d_pos.z) + front * (d_sz.z * 0.5 + c_sz.z * 0.5 + 0.14)
	return _try_place_item(ctx, r, rid, chair_kind, Vector3(p2.x, d_pos.y, p2.y), c_sz, d_yaw + PI, 0.25)


static func _try_pair_front_item(ctx: Dictionary, r: Rect2, rid: String, anchor: Dictionary, kind: String, sz: Vector3, gap: float, extra_yaw: float) -> Dictionary:
	var a_pos: Vector3 = anchor["pos"]
	var a_sz: Vector3 = anchor["size"]
	var a_yaw: float = float(anchor["yaw"])
	var front := get_front_dir_2d(a_yaw)
	var p2 := Vector2(a_pos.x, a_pos.z) + front * (a_sz.z * 0.5 + sz.z * 0.5 + gap)
	return _try_place_item(ctx, r, rid, kind, Vector3(p2.x, a_pos.y, p2.y), sz, a_yaw + extra_yaw, 0.25)


static func _try_pair_side_item(ctx: Dictionary, r: Rect2, rid: String, anchor: Dictionary, kind: String, sz: Vector3, align_back_edge: bool = false) -> Dictionary:
	var a_pos: Vector3 = anchor["pos"]
	var a_sz: Vector3 = anchor["size"]
	var a_yaw: float = float(anchor["yaw"])
	var right := get_right_dir_2d(a_yaw)
	var front := get_front_dir_2d(a_yaw)
	var z_shift := -(a_sz.z - sz.z) * 0.5 if align_back_edge else 0.0
	for side_s: float in [1.0, -1.0]:
		var lat := right * (side_s * (a_sz.x * 0.5 + sz.x * 0.5 + 0.14))
		var p2 := Vector2(a_pos.x, a_pos.z) + lat + front * z_shift
		var res := _try_place_item(ctx, r, rid, kind, Vector3(p2.x, a_pos.y, p2.y), sz, a_yaw, 0.22)
		if not res.is_empty():
			return res
	return {}


static func _rank_walls_clear_of_doors(r: Rect2, ctx: Dictionary) -> Array[String]:
	var walls: Array[String] = ["back", "right", "left", "front"]
	var scores := {"back": 0.0, "right": 0.0, "left": 0.0, "front": 0.0}
	var doors: Array = ctx["doors"]
	for d in doors:
		var dp: Vector3 = d["pos"]
		var d2 := Vector2(dp.x, dp.z)
		if absf(d2.y - r.position.y) < 0.45:
			scores["back"] += 10.0
		if absf(d2.y - r.end.y) < 0.45:
			scores["front"] += 10.0
		if absf(d2.x - r.position.x) < 0.45:
			scores["left"] += 10.0
		if absf(d2.x - r.end.x) < 0.45:
			scores["right"] += 10.0

	if int(ctx["fl"]) == 0:
		scores["front"] += 4.0

	walls.sort_custom(func(a: String, b: String) -> bool:
		return float(scores[a]) < float(scores[b])
	)
	return walls


static func _try_place_wall_item(
	ctx: Dictionary,
	r: Rect2,
	rid: String,
	kind: String,
	sz: Vector3,
	wall_order: Array[String],
	wall_gap: float = WALL_FLUSH_GAP,
	front_clear: float = 0.65,
	t_candidates: Array[float] = [0.50, 0.30, 0.70, 0.18, 0.82]
) -> Dictionary:
	var fy: float = ctx["fy"]
	for side in wall_order:
		var yaw := 0.0
		var span_lo := 0.0
		var span_hi := 0.0
		var fixed_coord := 0.0
		var is_z_wall := true

		match side:
			"back":
				yaw = 0.0
				is_z_wall = true
				fixed_coord = r.position.y + sz.z * 0.5 + wall_gap
				span_lo = r.position.x + sz.x * 0.5 + 0.12
				span_hi = r.end.x - sz.x * 0.5 - 0.12
			"front":
				yaw = PI
				is_z_wall = true
				fixed_coord = r.end.y - sz.z * 0.5 - wall_gap
				span_lo = r.position.x + sz.x * 0.5 + 0.12
				span_hi = r.end.x - sz.x * 0.5 - 0.12
			"left":
				yaw = PI * 0.5
				is_z_wall = false
				fixed_coord = r.position.x + sz.z * 0.5 + wall_gap
				span_lo = r.position.y + sz.x * 0.5 + 0.12
				span_hi = r.end.y - sz.x * 0.5 - 0.12
			"right":
				yaw = -PI * 0.5
				is_z_wall = false
				fixed_coord = r.end.x - sz.z * 0.5 - wall_gap
				span_lo = r.position.y + sz.x * 0.5 + 0.12
				span_hi = r.end.y - sz.x * 0.5 - 0.12

		if span_hi < span_lo:
			continue
		for t in t_candidates:
			var u := lerpf(span_lo, span_hi, clampf(t, 0.0, 1.0))
			var pos3 := Vector3(u, fy, fixed_coord) if is_z_wall else Vector3(fixed_coord, fy, u)
			var placed := _try_place_item(ctx, r, rid, kind, pos3, sz, yaw, front_clear)
			if not placed.is_empty():
				return placed
	return {}


static func _try_place_item(
	ctx: Dictionary,
	r: Rect2,
	rid: String,
	kind: String,
	pos: Vector3,
	sz: Vector3,
	yaw: float,
	front_clear: float
) -> Dictionary:
	var bp: BuildingBlueprint = ctx["bp"]
	var fl: int = ctx["fl"]
	var fy: float = ctx["fy"]
	var rot_xz := get_rotated_xz_size(sz, yaw)
	var hx := rot_xz.x * 0.5
	var hz := rot_xz.y * 0.5
	var p2 := Vector2(pos.x, pos.z)

	# 1. Strict room containment (at least 0.04m from walls)
	if p2.x - hx < r.position.x + 0.03 or p2.x + hx > r.end.x - 0.03:
		return {}
	if p2.y - hz < r.position.y + 0.03 or p2.y + hz > r.end.y - 0.03:
		return {}

	# Ensure functional front remains usable inside room
	var f_dir := get_front_dir_2d(yaw)
	var usable_pt := p2 + f_dir * (sz.z * 0.5 + front_clear * 0.65)
	if usable_pt.x < r.position.x + 0.12 or usable_pt.x > r.end.x - 0.12:
		return {}
	if usable_pt.y < r.position.y + 0.12 or usable_pt.y > r.end.y - 0.12:
		return {}

	# 2. Entry point & upper stair exit clearance
	var entry_pt: Vector2 = ctx["entry_pt"]
	if obbs_overlap_2d(p2, sz.x * 0.5, sz.z * 0.5, yaw, entry_pt, 0.72, 0.72, 0.0, 0.32):
		return {}
	var stair_next: Vector2 = ctx.get("stair_next_pt", Vector2.INF)
	if stair_next != Vector2.INF:
		if obbs_overlap_2d(p2, sz.x * 0.5, sz.z * 0.5, yaw, stair_next, 0.72, 0.72, 0.0, 0.30):
			return {}

	# 3. Ground floor main exterior vestibule doorway clearance
	if fl == 0:
		var ext_door := Vector2(bp.door_local_x, bp.depth * 0.5 - bp.wall_thickness)
		if obbs_overlap_2d(p2, sz.x * 0.5, sz.z * 0.5, yaw, ext_door, bp.door_width * 0.65, 1.35, 0.0, 0.45):
			return {}

	# 4. Stair & elevator shaft apron exclusion
	if bool(ctx["has_stairs"]):
		var st_r: Rect2 = ctx["stair_rect"]
		var st_pad := st_r.grow(STAIR_APRON_PAD)
		var item_rect := Rect2(p2.x - hx, p2.y - hz, rot_xz.x, rot_xz.y)
		if item_rect.intersects(st_pad):
			return {}
	if bool(ctx.get("has_elev", false)):
		var el_r: Rect2 = ctx["elev_rect"]
		var el_pad := Rect2(el_r.position.x - 0.35, el_r.position.y - 0.25, el_r.size.x + 0.70, el_r.size.y + 1.25)
		var item_rect_e := Rect2(p2.x - hx, p2.y - hz, rot_xz.x, rot_xz.y)
		if item_rect_e.intersects(el_pad):
			return {}

	# 5. Interior door swing & passage zone exclusion
	for d in ctx["doors"]:
		var d_pos: Vector3 = d["pos"]
		var d2 := Vector2(d_pos.x, d_pos.z)
		if obbs_overlap_2d(p2, sz.x * 0.5, sz.z * 0.5, yaw, d2, DOOR_CLEAR_RAD * 0.65, DOOR_CLEAR_RAD * 0.65, 0.0, 0.18):
			return {}

	# 6. Exterior window sill height guard (never stand tall shelves/racks across low windows)
	var item_top := fy + sz.y
	if sz.y > 0.96:
		var inner_min: Vector2 = ctx["inner_min"]
		var inner_max: Vector2 = ctx["inner_max"]
		for wo in ctx["window_openings"]:
			var win_bot := float(wo["y_center"]) - float(wo["height"]) * 0.5
			var win_top := float(wo["y_center"]) + float(wo["height"]) * 0.5
			if item_top <= win_bot + 0.05 or fy >= win_top:
				continue
			var face: String = String(wo["face"])
			var u0 := float(wo["u_center"]) - float(wo["width"]) * 0.5 - 0.14
			var u1 := float(wo["u_center"]) + float(wo["width"]) * 0.5 + 0.14
			match face:
				"front":
					if p2.y + hz > inner_max.y - 0.72 and p2.x + hx > u0 and p2.x - hx < u1:
						return {}
				"back":
					if p2.y - hz < inner_min.y + 0.72 and p2.x + hx > u0 and p2.x - hx < u1:
						return {}
				"left":
					if p2.x - hx < inner_min.x + 0.72 and p2.y + hz > u0 and p2.y - hz < u1:
						return {}
				"right":
					if p2.x + hx > inner_max.x - 0.72 and p2.y + hz > u0 and p2.y - hz < u1:
						return {}

	# 7. Strict 2D OBB non-overlap against every already-placed furniture item on this floor
	var placed: Array = ctx["furniture"]
	for other in placed:
		var o_pos: Vector3 = other["pos"]
		var o_sz: Vector3 = other["size"]
		var o_yaw: float = float(other["yaw"])
		if obbs_overlap_2d(p2, sz.x * 0.5, sz.z * 0.5, yaw, Vector2(o_pos.x, o_pos.z), o_sz.x * 0.5, o_sz.z * 0.5, o_yaw, FURNITURE_GAP):
			return {}

	var item := {
		"kind": kind,
		"pos": pos,
		"size": sz,
		"yaw": yaw,
		"room_id": rid,
		"collider": true,
	}
	placed.append(item)
	return item
