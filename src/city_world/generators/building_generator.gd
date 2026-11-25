class_name BuildingGenerator
extends RefCounted

## Generates deterministic BuildingBlueprints fitted strictly inside parcels on the 1536x1536m map,
## including skyscrapers, commercial anchor stores, multi-family midrises, and venue-matched signage.

const SIGN_CATALOG := [
	{"name": "SOLAR ROAST", "tag": "SPECIALTY COFFEE & ROASTERY", "venue": "cafe", "accent": Color(0.76, 0.42, 0.14)},
	{"name": "METRO MARKET", "tag": "ORGANIC GROCERY & DELI", "venue": "grocery", "accent": Color(0.16, 0.56, 0.34)},
	{"name": "APEX CLINIC", "tag": "URGENT CARE & PHARMACY", "venue": "clinic", "accent": Color(0.14, 0.52, 0.72)},
	{"name": "AUSTIN QUANTUM", "tag": "COMPUTE & ROBOTICS HQ", "venue": "tech_office", "accent": Color(0.12, 0.44, 0.78)},
	{"name": "CIVIC CO-OP", "tag": "COMMUNITY COMMONS", "venue": "civic_hall", "accent": Color(0.18, 0.52, 0.58)},
	{"name": "GREENLINE EV", "tag": "MOBILITY & SUPERCHARGING", "venue": "ev_showroom", "accent": Color(0.10, 0.62, 0.50)},
	{"name": "BRICKHOUSE", "tag": "ARTISAN KITCHEN & BAR", "venue": "restaurant", "accent": Color(0.68, 0.24, 0.18)},
	{"name": "NEXUS LABS", "tag": "BIOTECH & CLOUD CENTER", "venue": "tech_office", "accent": Color(0.22, 0.38, 0.76)},
	{"name": "VERDANT CAFE", "tag": "BOTANICAL TEA & BAKERY", "venue": "cafe", "accent": Color(0.26, 0.54, 0.24)},
	{"name": "SOUTH BAY BANK", "tag": "PRIVATE WEALTH & TRUST", "venue": "bank", "accent": Color(0.14, 0.30, 0.56)},
	{"name": "URBAN GROCER", "tag": "24HR FRESH MARKET", "venue": "grocery", "accent": Color(0.20, 0.58, 0.32)},
	{"name": "TRANSIT HUB", "tag": "REGIONAL RAIL & MOBILITY", "venue": "ev_showroom", "accent": Color(0.18, 0.48, 0.74)},
	{"name": "HORIZON OPTICS", "tag": "EYEWEAR & STUDIO", "venue": "clinic", "accent": Color(0.56, 0.32, 0.64)},
	{"name": "IRONWOOD BOOKS", "tag": "INDEPENDENT BOOKSHOP", "venue": "bookstore", "accent": Color(0.58, 0.34, 0.20)},
	{"name": "VELOCITY GYM", "tag": "ATHLETIC PERFORMANCE", "venue": "gym", "accent": Color(0.78, 0.28, 0.18)},
	{"name": "BARTON SUPPLY", "tag": "DESIGN & HARDWARE CO.", "venue": "hardware", "accent": Color(0.72, 0.48, 0.14)},
	{"name": "CAPITAL TOWER", "tag": "COMMERCE PLAZA", "venue": "office", "accent": Color(0.16, 0.42, 0.68)},
	{"name": "LAMAR ACOUSTICS", "tag": "HI-FI & RECORDING", "venue": "music_studio", "accent": Color(0.22, 0.46, 0.62)},
	{"name": "ZILKER BICYCLE", "tag": "E-BIKES & REPAIR", "venue": "bike_shop", "accent": Color(0.14, 0.56, 0.48)},
	{"name": "CASCADIA MED", "tag": "DIAGNOSTIC IMAGING", "venue": "clinic", "accent": Color(0.14, 0.48, 0.70)},
	{"name": "OAKWOOD DENTAL", "tag": "FAMILY DENTISTRY", "venue": "clinic", "accent": Color(0.20, 0.54, 0.68)},
	{"name": "SYNTHESIS AI", "tag": "RESEARCH TOWER", "venue": "tech_office", "accent": Color(0.24, 0.40, 0.80)},
	{"name": "TEXAS BAKERY", "tag": "SOURDOUGH & PASTRY", "venue": "cafe", "accent": Color(0.74, 0.44, 0.18)},
	{"name": "LONESTAR FREIGHT", "tag": "CLEAN LOGISTICS HUB", "venue": "logistics", "accent": Color(0.64, 0.36, 0.16)},
	{"name": "CREEKSIDE ART", "tag": "GALLERY & ATELIER", "venue": "gallery", "accent": Color(0.62, 0.26, 0.38)},
	{"name": "PARADIGM TOWER", "tag": "DOWNTOWN EXECUTIVE", "venue": "office", "accent": Color(0.14, 0.38, 0.64)},
	{"name": "STARLIGHT CINEMA", "tag": "INDEPENDENT SCREEN", "venue": "cinema", "accent": Color(0.74, 0.22, 0.28)},
	{"name": "ATRIUM PLAZA", "tag": "FLAGSHIP RETAIL", "venue": "retail", "accent": Color(0.18, 0.50, 0.66)},
	{"name": "PUBLIC LIBRARY", "tag": "READING ROOMS & ARCHIVE", "venue": "library", "accent": Color(0.24, 0.44, 0.62)},
	{"name": "MAIN POST OFFICE", "tag": "PARCEL DISPATCH & BOXES", "venue": "post_office", "accent": Color(0.18, 0.36, 0.64)},
]

const CHURCH_CATALOG := [
	{"name": "ST. LUKE'S CHAPEL", "tag": "COMMUNITY PARISH", "accent": Color(0.76, 0.60, 0.24)},
	{"name": "GRACE CATHEDRAL", "tag": "HISTORIC SANCTUARY", "accent": Color(0.74, 0.58, 0.22)},
	{"name": "TRINITY PARISH", "tag": "NEIGHBORHOOD CHAPEL", "accent": Color(0.72, 0.56, 0.22)},
]

const WALL_PALETTES := {
	"historic_brick": [Color(0.58, 0.28, 0.22), Color(0.64, 0.42, 0.31), Color(0.50, 0.26, 0.21)],
	"contemporary_2028": [Color(0.80, 0.82, 0.84), Color(0.72, 0.76, 0.80), Color(0.86, 0.85, 0.81), Color(0.32, 0.36, 0.41)],
	"suburban_siding": [Color(0.87, 0.85, 0.79), Color(0.74, 0.80, 0.76), Color(0.78, 0.75, 0.68), Color(0.68, 0.74, 0.81)],
	"industrial_steel": [Color(0.62, 0.65, 0.68), Color(0.54, 0.56, 0.58), Color(0.70, 0.68, 0.64)],
}


static func generate(config: CityConfig, terrain: TerrainData, road_graph: RoadGraph, parcels: Array, rng: RandomNumberGenerator) -> Array[BuildingBlueprint]:
	var blueprints: Array[BuildingBlueprint] = []
	var bld_seq := 0

	# Shuffle parcel order deterministically so cap trimming stays balanced across districts.
	var candidate_indices: Array[int] = []
	for i in range(parcels.size()):
		if not parcels[i].is_park:
			candidate_indices.append(i)

	# Deterministic Fisher-Yates shuffle so all districts populate evenly under the building cap.
	for i in range(candidate_indices.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := candidate_indices[i]
		candidate_indices[i] = candidate_indices[j]
		candidate_indices[j] = tmp

	# Place guaranteed civic landmarks & neighborhood churches first on properly sized parcels.
	bld_seq = _place_reserved_civic_landmarks(
		candidate_indices, parcels, config, terrain, road_graph, blueprints, bld_seq, rng
	)

	# Guarantee scenic coastal beach houses along the south beachfront before general cap trimming!
	var beach_placed := 0
	for pidx in candidate_indices:
		if beach_placed >= 26:
			break
		var parcel_b: ParcelData.Parcel = parcels[pidx]
		if parcel_b.has_building or parcel_b.district_zone != "beachfront":
			continue
		var bp_b := _try_place_building_in_parcel(parcel_b, bld_seq, config, terrain, road_graph, blueprints, rng)
		if bp_b != null:
			parcel_b.has_building = true
			blueprints.append(bp_b)
			bld_seq += 1
			beach_placed += 1

	var cap_lo := mini(config.target_max_buildings - 6, config.target_min_buildings + 15)
	var cap_hi := maxi(cap_lo, config.target_max_buildings - 8)
	var target_cap := rng.randi_range(cap_lo, cap_hi)
	for pidx in candidate_indices:
		if blueprints.size() >= target_cap:
			break
		var parcel: ParcelData.Parcel = parcels[pidx]
		if parcel.has_building:
			continue
		var bp := _try_place_building_in_parcel(parcel, bld_seq, config, terrain, road_graph, blueprints, rng)
		if bp != null:
			parcel.has_building = true
			blueprints.append(bp)
			bld_seq += 1

	# If a rare seed yields fewer than target_min_buildings, attempt secondary infill on large residential/commercial lots.
	if blueprints.size() < config.target_min_buildings:
		for pidx in candidate_indices:
			if blueprints.size() >= config.target_min_buildings + 8:
				break
			var parcel: ParcelData.Parcel = parcels[pidx]
			if parcel.has_building:
				continue
			var bp := _try_place_building_in_parcel(parcel, bld_seq, config, terrain, road_graph, blueprints, rng, true)
			if bp != null:
				parcel.has_building = true
				blueprints.append(bp)
				bld_seq += 1

	return blueprints


static func _place_reserved_civic_landmarks(
	candidate_indices: Array[int],
	parcels: Array,
	config: CityConfig,
	terrain: TerrainData,
	road_graph: RoadGraph,
	blueprints: Array[BuildingBlueprint],
	bld_seq: int,
	rng: RandomNumberGenerator
) -> int:
	var reservations: Array[Dictionary] = [
		{
			"zones": ["downtown_mixed", "commercial_corridor"],
			"spec": {
				"archetype": "municipal_hall",
				"style": "historic_brick",
				"desired_w": 24.0,
				"desired_d": 18.5,
				"min_w": 15.0,
				"min_d": 12.0,
				"floors": rng.randi_range(2, 3),
				"floor_height": 4.0,
				"ground_floor_height": 5.2,
				"roof_type": "flat_parapet",
				"roof_height": 3.4,
				"has_solar": false,
				"has_awning": false,
				"has_balconies": false,
				"has_signage": true,
				"door_width": 2.0,
				"door_height": 2.85,
				"sign_name": "CITY HALL & COURT",
				"sign_tag": "MUNICIPAL CHAMBERS",
				"venue": "city_hall",
				"accent": Color(0.78, 0.64, 0.24),
				"wall_color": Color(0.86, 0.83, 0.76),
				"trim_color": Color(0.24, 0.25, 0.28),
				"roof_color": Color(0.28, 0.31, 0.34),
			},
		},
		{
			"zones": ["commercial_corridor", "downtown_mixed"],
			"spec": {
				"archetype": "police_station",
				"style": "contemporary_2028",
				"desired_w": 18.5,
				"desired_d": 15.0,
				"min_w": 12.0,
				"min_d": 10.5,
				"floors": 2,
				"floor_height": 3.5,
				"ground_floor_height": 4.3,
				"roof_type": "flat_parapet",
				"roof_height": 0.65,
				"has_solar": true,
				"has_awning": false,
				"has_balconies": false,
				"has_signage": true,
				"door_width": 1.75,
				"door_height": 2.75,
				"sign_name": "METRO POLICE HQ",
				"sign_tag": "PRECINCT ONE DISPATCH",
				"venue": "police_station",
				"accent": Color(0.12, 0.36, 0.84),
				"wall_color": Color(0.74, 0.77, 0.82),
				"trim_color": Color(0.18, 0.20, 0.24),
			},
		},
		{
			"zones": ["commercial_corridor", "residential_hills", "downtown_mixed"],
			"spec": {
				"archetype": "fire_station",
				"style": "historic_brick",
				"desired_w": 19.5,
				"desired_d": 16.0,
				"min_w": 13.0,
				"min_d": 11.5,
				"floors": 2,
				"floor_height": 3.5,
				"ground_floor_height": 4.9,
				"roof_type": "flat_parapet",
				"roof_height": 0.65,
				"has_solar": true,
				"has_awning": false,
				"has_balconies": false,
				"has_signage": true,
				"door_width": 1.35,
				"door_height": 2.55,
				"offcenter_left_door": true,
				"sign_name": "FIRE STATION NO. 1",
				"sign_tag": "ENGINE & LADDER CO.",
				"venue": "fire_station",
				"accent": Color(0.84, 0.14, 0.12),
				"wall_color": Color(0.60, 0.24, 0.19),
				"trim_color": Color(0.22, 0.23, 0.26),
			},
		},
		{
			"zones": ["residential_hills", "commercial_corridor"],
			"spec": _make_church_spec(0, rng),
		},
		{
			"zones": ["downtown_mixed", "commercial_corridor", "residential_hills"],
			"spec": _make_church_spec(1, rng),
		},
		{
			"zones": ["residential_hills", "commercial_corridor"],
			"spec": _make_church_spec(2, rng),
		},
		{
			"zones": ["commercial_corridor", "downtown_mixed", "residential_hills"],
			"spec": _make_church_spec(3, rng),
		},
		{
			"zones": ["commercial_corridor", "downtown_mixed"],
			"spec": {
				"archetype": "civic_hall",
				"style": "contemporary_2028",
				"desired_w": 19.0,
				"desired_d": 16.0,
				"min_w": 12.5,
				"min_d": 10.5,
				"floors": 2,
				"floor_height": 3.7,
				"ground_floor_height": 4.8,
				"roof_type": "shed_solar",
				"roof_height": 1.9,
				"has_solar": true,
				"has_awning": false,
				"has_balconies": false,
				"has_signage": true,
				"door_width": 1.85,
				"door_height": 2.75,
				"sign_name": "PUBLIC LIBRARY",
				"sign_tag": "READING ROOMS & ARCHIVE",
				"venue": "library",
				"accent": Color(0.24, 0.44, 0.62),
			},
		},
		{
			"zones": ["commercial_corridor", "downtown_mixed"],
			"spec": {
				"archetype": "brick_shop",
				"style": "historic_brick",
				"desired_w": 17.0,
				"desired_d": 14.0,
				"min_w": 11.5,
				"min_d": 10.0,
				"floors": 2,
				"floor_height": 3.4,
				"ground_floor_height": 4.2,
				"roof_type": "flat_parapet",
				"roof_height": 0.5,
				"has_solar": true,
				"has_awning": true,
				"has_balconies": false,
				"has_signage": true,
				"door_width": 1.65,
				"door_height": 2.65,
				"sign_name": "MAIN POST OFFICE",
				"sign_tag": "PARCEL DISPATCH & BOXES",
				"venue": "post_office",
				"accent": Color(0.18, 0.36, 0.64),
			},
		},
		{
			"zones": ["commercial_corridor", "downtown_mixed", "residential_hills"],
			"spec": {
				"archetype": "hospital",
				"style": "contemporary_2028",
				"desired_w": 24.0,
				"desired_d": 19.0,
				"min_w": 15.0,
				"min_d": 12.0,
				"floors": rng.randi_range(4, 5),
				"floor_height": 3.55,
				"ground_floor_height": 4.7,
				"roof_type": "flat_parapet",
				"roof_height": 0.70,
				"has_solar": false,
				"has_awning": true,
				"has_balconies": false,
				"has_signage": true,
				"door_width": 2.1,
				"door_height": 2.85,
				"sign_name": "MERCY GENERAL HOSPITAL",
				"sign_tag": "24H EMERGENCY & TRAUMA",
				"venue": "hospital",
				"accent": Color(0.84, 0.14, 0.16),
				"wall_color": Color(0.90, 0.92, 0.94),
				"trim_color": Color(0.18, 0.24, 0.30),
			},
		},
		{
			"zones": ["residential_hills", "commercial_corridor", "downtown_mixed"],
			"spec": {
				"archetype": "school",
				"style": "historic_brick",
				"desired_w": 22.0,
				"desired_d": 17.5,
				"min_w": 14.0,
				"min_d": 11.5,
				"floors": rng.randi_range(2, 3),
				"floor_height": 3.5,
				"ground_floor_height": 4.4,
				"roof_type": "flat_parapet",
				"roof_height": 0.65,
				"has_solar": true,
				"has_awning": false,
				"has_balconies": false,
				"has_signage": true,
				"door_width": 1.95,
				"door_height": 2.75,
				"sign_name": "CEDAR CREEK ACADEMY",
				"sign_tag": "PUBLIC HIGH SCHOOL & ARTS",
				"venue": "school",
				"accent": Color(0.16, 0.42, 0.72),
				"wall_color": Color(0.64, 0.32, 0.25),
				"trim_color": Color(0.86, 0.84, 0.78),
			},
		},
	]

	for res in reservations:
		var pref_zones: Array = res["zones"]
		var spec: Dictionary = res["spec"]
		var placed := false
		for relaxed_pass: bool in [false, true]:
			for target_zone in pref_zones:
				for pidx in candidate_indices:
					var parcel: ParcelData.Parcel = parcels[pidx]
					if parcel.has_building or parcel.district_zone != String(target_zone):
						continue
					var bp := _try_place_building_in_parcel(parcel, bld_seq, config, terrain, road_graph, blueprints, rng, relaxed_pass, spec)
					if bp != null:
						parcel.has_building = true
						blueprints.append(bp)
						bld_seq += 1
						placed = true
						break
				if placed:
					break
			if placed:
				break
	return bld_seq


static func _make_church_spec(variant_idx: int, rng: RandomNumberGenerator) -> Dictionary:
	var c_entry: Dictionary = CHURCH_CATALOG[posmod(variant_idx, CHURCH_CATALOG.size())]
	var is_stone := (variant_idx % 2 == 0)
	return {
		"archetype": "church",
		"style": "historic_brick",
		"desired_w": rng.randf_range(13.5, 16.5),
		"desired_d": rng.randf_range(18.5, 23.0),
		"min_w": 10.2,
		"min_d": 12.8,
		"floors": 1,
		"floor_height": 6.2,
		"ground_floor_height": 6.2,
		"roof_type": "gable",
		"roof_height": 4.2,
		"has_solar": false,
		"has_awning": false,
		"has_balconies": false,
		"has_signage": true,
		"door_width": 1.85,
		"door_height": 2.85,
		"sign_name": String(c_entry["name"]),
		"sign_tag": String(c_entry["tag"]),
		"venue": "church",
		"accent": c_entry["accent"],
		"wall_color": Color(0.84, 0.80, 0.72) if is_stone else Color(0.62, 0.30, 0.24),
		"trim_color": Color(0.90, 0.87, 0.80),
		"roof_color": Color(0.20, 0.22, 0.26),
	}


static func _try_place_building_in_parcel(
	parcel: ParcelData.Parcel,
	seq_id: int,
	config: CityConfig,
	terrain: TerrainData,
	road_graph: RoadGraph,
	existing: Array[BuildingBlueprint],
	rng: RandomNumberGenerator,
	relaxed: bool = false,
	forced_spec: Dictionary = {}
) -> BuildingBlueprint:
	var n := parcel.polygon.size()
	if n < 3:
		return null

	# Build per-edge setback array (frontage gets front_setback, others get side/rear).
	var setbacks := PackedFloat32Array()
	var front_mid := (parcel.frontage_p0 + parcel.frontage_p1) * 0.5
	for i in range(n):
		var a := parcel.polygon[i]
		var b := parcel.polygon[(i + 1) % n]
		var emid := (a + b) * 0.5
		if emid.distance_to(front_mid) < 1.5:
			setbacks.append(maxf(0.9, parcel.front_setback * (0.75 if relaxed else 1.0)))
		else:
			setbacks.append(maxf(0.8, parcel.side_setback * (0.75 if relaxed else 1.0)))

	var inset_poly := ParcelData.inset_convex_polygon_per_edge(parcel.polygon, setbacks)
	if inset_poly.size() < 3 or absf(ParcelData.signed_area(inset_poly)) < 48.0:
		return null

	var yaw := atan2(parcel.frontage_normal.x, parcel.frontage_normal.y)
	var right := Vector2(cos(yaw), -sin(yaw))
	var forward := Vector2(sin(yaw), cos(yaw))

	# Choose target dimensions based on district & archetype.
	var spec := forced_spec if not forced_spec.is_empty() else _pick_archetype_spec(parcel.district_zone, seq_id, rng)
	var desired_w: float = spec["desired_w"]
	var desired_d: float = spec["desired_d"]
	var min_w: float = float(spec.get("min_w", 5.5 if relaxed else 6.4))
	var min_d: float = float(spec.get("min_d", 5.5 if relaxed else 6.4))

	# Fit largest valid OBB aligned with frontage inside inset_poly.
	var rect := _fit_obb_in_convex_polygon(inset_poly, front_mid, right, forward, desired_w, desired_d, min_w, min_d)
	if not rect.get("valid", false) and relaxed and forced_spec.is_empty():
		var fb_zone := "residential_hills" if parcel.district_zone in ["residential_hills", "light_industrial"] else "commercial_corridor"
		spec = _pick_archetype_spec(fb_zone, seq_id + 97, rng)
		if String(spec.get("archetype", "")) == "church":
			spec = _pick_archetype_spec("residential_hills", seq_id + 13, rng)
		desired_w = minf(float(spec["desired_w"]), 11.0)
		desired_d = minf(float(spec["desired_d"]), 11.0)
		min_w = 5.4
		min_d = 5.4
		rect = _fit_obb_in_convex_polygon(inset_poly, front_mid, right, forward, desired_w, desired_d, min_w, min_d)
	if not rect.get("valid", false):
		return null

	var b_center: Vector2 = rect["center"]
	var b_w: float = rect["width"]
	var b_d: float = rect["depth"]

	# Verify all 4 footprint corners clear roads, creek, and inset parcel.
	var corners := ParcelData.get_obb_corners(b_center, Vector2(b_w * 0.5, b_d * 0.5), yaw)
	for c in corners:
		if not ParcelData.point_in_convex_polygon(c, parcel.polygon, -0.4):
			return null
		if road_graph.distance_to_road_corridor(c) < 0.5:
			return null
		if terrain.distance_to_creek(c) < terrain.creek_half_width + 2.0:
			return null

	# SAT non-overlap against all existing buildings (0.8m minimum air gap).
	for other in existing:
		if ParcelData.obb_overlaps(b_center, Vector2(b_w * 0.5, b_d * 0.5), yaw, other.center, Vector2(other.width * 0.5, other.depth * 0.5), other.yaw, 0.8):
			return null

	# Build authoritative BuildingBlueprint.
	var bp := BuildingBlueprint.new()
	bp.id = "bld_%04d" % seq_id
	bp.parcel_id = parcel.id
	bp.block_id = parcel.block_id
	bp.district_zone = parcel.district_zone
	bp.archetype = spec["archetype"]
	bp.style = spec["style"]
	bp.center = b_center
	bp.yaw = yaw
	bp.width = b_w
	bp.depth = b_d
	bp.chunk_coord = Vector2i(
		clampi(int(floor(b_center.x / config.chunk_size)), 0, config.get_chunks_per_axis() - 1),
		clampi(int(floor(b_center.y / config.chunk_size)), 0, config.get_chunks_per_axis() - 1)
	)

	# Elevations matched cleanly to frontage sidewalk & underlying hill slope.
	var door_front_pt := b_center + forward * (b_d * 0.5 + 1.8)
	var rq := road_graph.query_nearest_edge(door_front_pt)
	var app_terr_y := terrain.sample_height(door_front_pt.x, door_front_pt.y)
	var sidewalk_y := app_terr_y + 0.04
	if rq.get("valid", false) and not bool(rq.get("is_bridge", false)):
		var road_sw_y := float(rq["pos_3d"].y) + 0.15
		var road_edge_w := float(rq["half_road_w"]) + float(rq["sidewalk_w"])
		var r_dist := float(rq["dist"])
		if r_dist <= road_edge_w + 0.15:
			sidewalk_y = road_sw_y
		elif r_dist <= road_edge_w + 3.5:
			sidewalk_y = clampf(road_sw_y, app_terr_y - 0.12, app_terr_y + 0.15)

	var min_max := terrain.sample_min_max_in_obb(b_center, Vector2(b_w * 0.5, b_d * 0.5), yaw)
	bp.sidewalk_y = sidewalk_y
	bp.base_y = maxf(sidewalk_y + 0.18, minf(sidewalk_y + 0.58, (sidewalk_y + min_max.y) * 0.5))
	bp.foundation_bottom_y = minf(min_max.x, sidewalk_y) - 1.4

	bp.floors = spec["floors"]
	bp.floor_height = spec["floor_height"]
	bp.ground_floor_height = spec["ground_floor_height"]
	bp.roof_type = spec["roof_type"]
	bp.roof_height = spec["roof_height"]

	var palette: Array = WALL_PALETTES[bp.style]
	bp.wall_color = spec["wall_color"] if spec.has("wall_color") else palette[rng.randi() % palette.size()]
	bp.trim_color = spec["trim_color"] if spec.has("trim_color") else (Color(0.20, 0.22, 0.25) if bp.style != "suburban_siding" else Color(0.92, 0.91, 0.88))

	var sign_entry: Dictionary
	if spec.has("sign_name"):
		sign_entry = {
			"name": spec["sign_name"],
			"tag": spec.get("sign_tag", ""),
			"venue": spec["venue"],
			"accent": spec.get("accent", Color(0.72, 0.56, 0.22)),
		}
	else:
		var sign_idx := posmod(seq_id * 5 + rng.randi_range(0, SIGN_CATALOG.size() - 1), SIGN_CATALOG.size())
		sign_entry = SIGN_CATALOG[sign_idx]
		if bp.archetype == "warehouse":
			# Keep industrial warehouses matched to logistics/hardware/athletic/wholesale signage
			var wh_pool: Array[Dictionary] = []
			for item in SIGN_CATALOG:
				if String(item["venue"]) in ["logistics", "hardware", "gym", "grocery"]:
					wh_pool.append(item)
			sign_entry = wh_pool[posmod(seq_id, wh_pool.size())]
		elif String(sign_entry["venue"]) == "logistics":
			sign_entry = SIGN_CATALOG[posmod(sign_idx + 1, SIGN_CATALOG.size())]

	bp.accent_color = spec["accent_color"] if spec.has("accent_color") else (sign_entry["accent"] if spec["has_signage"] else (Color(0.14, 0.48, 0.68) if bp.style == "contemporary_2028" else Color(0.62, 0.34, 0.20)))
	bp.roof_color = spec["roof_color"] if spec.has("roof_color") else (Color(0.22, 0.24, 0.27) if bp.roof_type != "gable" else Color(0.28, 0.24, 0.22))

	bp.has_solar_panels = spec["has_solar"]
	bp.has_awning = spec["has_awning"]
	bp.has_balconies = spec["has_balconies"] and bp.floors >= 3 and b_w >= 8.5
	bp.has_signage = spec["has_signage"]
	bp.sign_label = String(sign_entry["name"]).to_upper()
	bp.sign_tagline = String(sign_entry["tag"])
	bp.venue_type = String(sign_entry["venue"]) if bp.has_signage else ("logistics" if bp.archetype == "warehouse" else "residential")
	bp.is_landmark_tower = bp.archetype == "skyscraper_tower" or (bp.floors >= 10)
	bp.has_blade_sign = bp.has_signage and bp.archetype in ["brick_shop", "mixed_use_midrise", "modern_office", "retail_anchor", "skyscraper_tower"] and b_w >= 9.0
	bp.sign_style = "crown" if (bp.has_signage and bp.floors >= 7 and b_w >= 13.0) else ("neon" if (bp.archetype in ["brick_shop", "retail_anchor"] and rng.randf() < 0.45) else "lightbox")
	bp.window_cols_front = clampi(int(floor((b_w - 1.8) / 2.4)), 2, 12)
	bp.window_cols_side = clampi(int(floor((b_d - 1.8) / 2.6)), 2, 12)

	# Corner-lot secondary street frontage (non-alley road adjacent to building left/right flank)
	if parcel.secondary_frontage_face != "" and BuildingBlueprint.is_commercial_archetype(bp.archetype) and not (bp.archetype in ["fire_station", "municipal_hall", "hospital", "school"]):
		var sec_sign := 1.0 if parcel.secondary_frontage_face == "right" else -1.0
		var sec_mid_w := bp.local_to_world_2d(Vector2(sec_sign * b_w * 0.5, 0.0))
		if road_graph.distance_to_road_corridor(sec_mid_w) <= 6.0:
			bp.secondary_front_face = parcel.secondary_frontage_face

	# Authoritative entrance + physical vestibule (+ residential porch/garage)
	bp.door_id = "door_%s" % bp.id
	bp.door_width = clampf(spec["door_width"], 1.15, b_w - 2.0)
	bp.door_height = spec["door_height"]
	if bool(spec.get("offcenter_left_door", false)):
		bp.door_local_x = clampf(-b_w * 0.5 + 2.2, -b_w * 0.5 + bp.door_width * 0.5 + 0.75, -b_w * 0.18)
	else:
		bp.door_local_x = 0.0

	if bp.archetype == "house_pitched" or bp.archetype == "beach_house":
		if bp.archetype == "house_pitched" and b_w >= 11.4 and b_d >= 9.0 and rng.randf() < 0.72:
			var cand_door_x := clampf(-b_w * 0.23, -b_w * 0.5 + bp.door_width * 0.5 + 1.05, -1.15)
			var cand_gar_x := clampf(b_w * 0.24, cand_door_x + bp.door_width * 0.5 + 2.25, b_w * 0.5 - 2.0)
			if cand_gar_x + 1.75 <= b_w * 0.5 - 0.35 and cand_gar_x - cand_door_x >= bp.door_width * 0.5 + 2.10:
				bp.has_garage = true
				bp.door_local_x = cand_door_x
				bp.garage_local_x = cand_gar_x
		if b_w >= 8.2 and parcel.front_setback >= 2.25:
			bp.has_porch = true
			bp.porch_depth = clampf(minf(1.28, parcel.front_setback - 1.18), 0.95, 1.28)

	bp.stair_on_left = true if bp.archetype == "fire_station" else (bp.door_local_x >= -0.4)

	# CGA Podium-to-Tower setbacks (step strictly inward on +Z and non-stair X side above setback_floor >= 4)
	if bp.archetype in ["skyscraper_tower", "modern_office", "mixed_use_midrise", "hospital"] and bp.roof_type == "flat_parapet" and bp.floors >= 7 and b_w >= 14.0 and b_d >= 13.0:
		if bp.archetype == "skyscraper_tower" or rng.randf() < 0.72:
			bp.setback_floor = clampi(int(round(float(bp.floors) * rng.randf_range(0.32, 0.44))), 4, bp.floors - 3)
			bp.setback_inset_front = clampf(b_d * rng.randf_range(0.11, 0.17), 1.4, minf(3.0, b_d - 9.6))
			if b_w >= 14.5 and rng.randf() < 0.65:
				bp.setback_inset_side = clampf(b_w * rng.randf_range(0.10, 0.16), 1.3, minf(2.7, b_w - 10.2))

	var top_tb := bp.get_tier_bounds_local(bp.floors - 1)
	var top_w := float(top_tb["x1"]) - float(top_tb["x0"])
	var top_d := float(top_tb["z1"]) - float(top_tb["z0"])
	bp.has_crown_sign = bp.has_signage and bp.floors >= 7 and top_w >= 11.5
	bp.has_helipad = (bp.archetype == "hospital" and top_w >= 13.5 and top_d >= 11.0) or (bp.floors >= 12 and bp.roof_type == "flat_parapet" and top_w >= 16.5 and top_d >= 15.0)
	if bp.archetype in ["skyscraper_tower", "modern_office"] and bp.floors >= 7 and bp.roof_type == "flat_parapet":
		if bp.has_helipad:
			bp.crown_style = "fin_parapet"
		else:
			var c_styles := ["stepped", "fin_parapet", "chamfer_glass"]
			bp.crown_style = c_styles[rng.randi() % c_styles.size()]

	bp.vestibule_width = clampf(bp.door_width + 1.8, 2.6, b_w - 1.0)
	bp.vestibule_depth = clampf(2.8, 2.2, b_d - 1.4)
	var dy_step := maxf(0.18, bp.base_y - bp.sidewalk_y)
	var min_app := (bp.porch_depth + 0.85) if bp.has_porch else 1.1
	bp.approach_length = clampf(maxf(dy_step * 4.2, min_app), min_app, maxf(min_app, parcel.front_setback - 0.15))

	return bp


static func _pick_archetype_spec(zone: String, seq_id: int, rng: RandomNumberGenerator) -> Dictionary:
	match zone:
		"downtown_mixed":
			var r := rng.randf()
			if r < 0.33:
				return {
					"archetype": "skyscraper_tower",
					"style": "contemporary_2028",
					"desired_w": rng.randf_range(20.0, 29.5),
					"desired_d": rng.randf_range(18.0, 26.0),
					"floors": rng.randi_range(12, 24),
					"floor_height": 3.55,
					"ground_floor_height": 5.2,
					"roof_type": "flat_parapet",
					"roof_height": 0.75,
					"has_solar": true,
					"has_awning": true,
					"has_balconies": false,
					"has_signage": true,
					"door_width": 2.0,
					"door_height": 2.85,
				}
			elif r < 0.65:
				return {
					"archetype": "mixed_use_midrise",
					"style": "contemporary_2028",
					"desired_w": rng.randf_range(16.5, 25.0),
					"desired_d": rng.randf_range(15.0, 22.5),
					"floors": rng.randi_range(6, 12),
					"floor_height": 3.4,
					"ground_floor_height": 4.5,
					"roof_type": "flat_parapet",
					"roof_height": 0.6,
					"has_solar": rng.randf() < 0.75,
					"has_awning": true,
					"has_balconies": true,
					"has_signage": true,
					"door_width": 1.75,
					"door_height": 2.7,
				}
			elif r < 0.90:
				return {
					"archetype": "modern_office",
					"style": "contemporary_2028",
					"desired_w": rng.randf_range(17.5, 27.0),
					"desired_d": rng.randf_range(16.0, 23.5),
					"floors": rng.randi_range(7, 15),
					"floor_height": 3.5,
					"ground_floor_height": 4.7,
					"roof_type": "flat_parapet",
					"roof_height": 0.6,
					"has_solar": true,
					"has_awning": true,
					"has_balconies": false,
					"has_signage": true,
					"door_width": 1.8,
					"door_height": 2.75,
				}
			else:
				return {
					"archetype": "brick_shop",
					"style": "historic_brick",
					"desired_w": rng.randf_range(13.5, 19.0),
					"desired_d": rng.randf_range(12.5, 17.5),
					"floors": rng.randi_range(2, 5),
					"floor_height": 3.3,
					"ground_floor_height": 4.1,
					"roof_type": "flat_parapet",
					"roof_height": 0.45,
					"has_solar": rng.randf() < 0.40,
					"has_awning": true,
					"has_balconies": false,
					"has_signage": true,
					"door_width": 1.6,
					"door_height": 2.6,
				}
		"commercial_corridor":
			var r2 := rng.randf()
			if r2 < 0.28:
				return {
					"archetype": "brick_shop",
					"style": "historic_brick",
					"desired_w": rng.randf_range(13.0, 18.5),
					"desired_d": rng.randf_range(12.0, 17.0),
					"floors": rng.randi_range(2, 4),
					"floor_height": 3.25,
					"ground_floor_height": 4.0,
					"roof_type": "flat_parapet",
					"roof_height": 0.45,
					"has_solar": rng.randf() < 0.45,
					"has_awning": true,
					"has_balconies": false,
					"has_signage": true,
					"door_width": 1.55,
					"door_height": 2.6,
				}
			elif r2 < 0.56:
				return {
					"archetype": "retail_anchor",
					"style": "contemporary_2028",
					"desired_w": rng.randf_range(20.0, 31.0),
					"desired_d": rng.randf_range(17.0, 25.0),
					"floors": rng.randi_range(2, 4),
					"floor_height": 3.8,
					"ground_floor_height": 5.0,
					"roof_type": "flat_parapet",
					"roof_height": 0.65,
					"has_solar": true,
					"has_awning": true,
					"has_balconies": false,
					"has_signage": true,
					"door_width": 2.1,
					"door_height": 2.8,
				}
			elif r2 < 0.84:
				return {
					"archetype": "mixed_use_midrise",
					"style": "contemporary_2028",
					"desired_w": rng.randf_range(15.5, 22.5),
					"desired_d": rng.randf_range(14.0, 20.0),
					"floors": rng.randi_range(4, 9),
					"floor_height": 3.35,
					"ground_floor_height": 4.2,
					"roof_type": "flat_parapet",
					"roof_height": 0.5,
					"has_solar": rng.randf() < 0.70,
					"has_awning": true,
					"has_balconies": true,
					"has_signage": true,
					"door_width": 1.65,
					"door_height": 2.65,
				}
			elif r2 < 0.94:
				return {
					"archetype": "modern_office",
					"style": "contemporary_2028",
					"desired_w": rng.randf_range(16.5, 24.0),
					"desired_d": rng.randf_range(15.0, 21.0),
					"floors": rng.randi_range(5, 11),
					"floor_height": 3.45,
					"ground_floor_height": 4.5,
					"roof_type": "flat_parapet",
					"roof_height": 0.55,
					"has_solar": true,
					"has_awning": true,
					"has_balconies": false,
					"has_signage": true,
					"door_width": 1.75,
					"door_height": 2.7,
				}
			else:
				return {
					"archetype": "civic_hall",
					"style": "contemporary_2028",
					"desired_w": rng.randf_range(18.0, 26.0),
					"desired_d": rng.randf_range(15.0, 22.0),
					"floors": rng.randi_range(2, 4),
					"floor_height": 3.7,
					"ground_floor_height": 5.1,
					"roof_type": "shed_solar",
					"roof_height": 2.1,
					"has_solar": true,
					"has_awning": true,
					"has_balconies": false,
					"has_signage": true,
					"door_width": 1.85,
					"door_height": 2.75,
				}
		"light_industrial":
			return {
				"archetype": "warehouse",
				"style": "industrial_steel",
				"desired_w": rng.randf_range(21.0, 33.0),
				"desired_d": rng.randf_range(18.0, 27.0),
				"floors": 1,
				"floor_height": 6.0,
				"ground_floor_height": rng.randf_range(6.8, 9.2),
				"roof_type": "flat_parapet" if rng.randf() < 0.5 else "shed_solar",
				"roof_height": 1.05,
				"has_solar": rng.randf() < 0.75,
				"has_awning": false,
				"has_balconies": false,
				"has_signage": rng.randf() < 0.65,
				"door_width": 1.55,
				"door_height": 2.55,
			}
		"beachfront":
			var coastal_pal := [
				Color(0.92, 0.91, 0.86), # Coastal whitewashed cream
				Color(0.70, 0.85, 0.83), # Seafoam sage
				Color(0.72, 0.82, 0.90), # Coastal powder blue
				Color(0.91, 0.77, 0.68), # Warm coral sand
				Color(0.89, 0.85, 0.72), # Sunlit buttercream
				Color(0.78, 0.82, 0.78), # Weathered driftwood grey-green
			]
			var c_col: Color = coastal_pal[posmod(seq_id * 5 + rng.randi_range(0, 5), coastal_pal.size())]
			return {
				"archetype": "beach_house",
				"style": "suburban_siding",
				"desired_w": rng.randf_range(11.5, 15.5),
				"desired_d": rng.randf_range(9.5, 12.2),
				"floors": 2 if rng.randf() < 0.78 else 1,
				"floor_height": 3.1,
				"ground_floor_height": 3.35,
				"roof_type": "gable" if rng.randf() < 0.65 else "hip",
				"roof_height": rng.randf_range(2.2, 3.0),
				"has_solar": rng.randf() < 0.55,
				"has_awning": false,
				"has_balconies": true,
				"has_signage": false,
				"door_width": 1.35,
				"door_height": 2.40,
				"wall_color": c_col,
				"trim_color": Color(0.94, 0.95, 0.96),
				"accent_color": Color(0.14, 0.52, 0.66),
			}
		_:
			# residential_hills
			var r3 := rng.randf()
			if r3 < 0.52:
				return {
					"archetype": "house_pitched",
					"style": "suburban_siding",
					"desired_w": rng.randf_range(10.0, 14.8),
					"desired_d": rng.randf_range(10.0, 14.5),
					"floors": rng.randi_range(1, 2),
					"floor_height": 3.1,
					"ground_floor_height": 3.25,
					"roof_type": "gable" if rng.randf() < 0.7 else "hip",
					"roof_height": rng.randf_range(2.4, 3.2),
					"has_solar": rng.randf() < 0.55,
					"has_awning": false,
					"has_balconies": false,
					"has_signage": false,
					"door_width": 1.3,
					"door_height": 2.38,
				}
			elif r3 < 0.80:
				return {
					"archetype": "townhouse",
					"style": "historic_brick" if rng.randf() < 0.45 else "suburban_siding",
					"desired_w": rng.randf_range(10.5, 14.5),
					"desired_d": rng.randf_range(12.0, 16.5),
					"floors": rng.randi_range(2, 4),
					"floor_height": 3.1,
					"ground_floor_height": 3.3,
					"roof_type": "gable" if rng.randf() < 0.5 else "flat_parapet",
					"roof_height": 1.9,
					"has_solar": rng.randf() < 0.6,
					"has_awning": false,
					"has_balconies": true,
					"has_signage": false,
					"door_width": 1.3,
					"door_height": 2.4,
				}
			elif r3 < 0.84:
				return _make_church_spec(seq_id, rng)
			else:
				return {
					"archetype": "apartment_midrise",
					"style": "historic_brick" if rng.randf() < 0.5 else "contemporary_2028",
					"desired_w": rng.randf_range(16.0, 24.0),
					"desired_d": rng.randf_range(14.0, 20.0),
					"floors": rng.randi_range(5, 9),
					"floor_height": 3.15,
					"ground_floor_height": 3.6,
					"roof_type": "flat_parapet",
					"roof_height": 0.5,
					"has_solar": true,
					"has_awning": true,
					"has_balconies": true,
					"has_signage": false,
					"door_width": 1.5,
					"door_height": 2.55,
				}


static func _fit_obb_in_convex_polygon(
	poly: PackedVector2Array,
	origin: Vector2,
	right: Vector2,
	forward: Vector2,
	desired_w: float,
	desired_d: float,
	min_w: float,
	min_d: float
) -> Dictionary:
	# Convert polygon to local (x = right, z = forward) around origin.
	var local_pts := PackedVector2Array()
	var max_z := -INF
	var min_z := INF
	for p in poly:
		var rel := p - origin
		var lx := rel.dot(right)
		var lz := rel.dot(forward)
		local_pts.append(Vector2(lx, lz))
		max_z = maxf(max_z, lz)
		min_z = minf(min_z, lz)

	var available_d := max_z - min_z
	if available_d < min_d:
		return {"valid": false}

	# Snap front edge near max_z (street-facing setback line) and try decreasing depths.
	var z_front := max_z - 0.15
	var target_d := minf(desired_d, available_d - 0.25)
	for step_i in range(6):
		var d := lerpf(target_d, min_d, float(step_i) / 5.0)
		if d < min_d:
			continue
		var z_back := z_front - d
		var span_front := _horizontal_span_at_z(local_pts, z_front)
		var span_back := _horizontal_span_at_z(local_pts, z_back)
		var span_mid := _horizontal_span_at_z(local_pts, (z_front + z_back) * 0.5)
		if span_front.x >= span_front.y or span_back.x >= span_back.y:
			continue
		var x_left := maxf(span_front.x, maxf(span_back.x, span_mid.x)) + 0.1
		var x_right := minf(span_front.y, minf(span_back.y, span_mid.y)) - 0.1
		var avail_w := x_right - x_left
		if avail_w >= min_w:
			var w := minf(desired_w, avail_w)
			var cx_local := (x_left + x_right) * 0.5
			var cz_local := (z_front + z_back) * 0.5
			var world_center := origin + right * cx_local + forward * cz_local
			return {
				"valid": true,
				"center": world_center,
				"width": w,
				"depth": d,
			}

	return {"valid": false}


static func _horizontal_span_at_z(poly: PackedVector2Array, z_val: float) -> Vector2:
	var min_x := INF
	var max_x := -INF
	var n := poly.size()
	for i in range(n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		if (a.y <= z_val and b.y >= z_val) or (b.y <= z_val and a.y >= z_val):
			if absf(b.y - a.y) < 0.0001:
				min_x = minf(min_x, minf(a.x, b.x))
				max_x = maxf(max_x, maxf(a.x, b.x))
			else:
				var t := (z_val - a.y) / (b.y - a.y)
				var ix := lerpf(a.x, b.x, t)
				min_x = minf(min_x, ix)
				max_x = maxf(max_x, ix)
	return Vector2(min_x, max_x)
