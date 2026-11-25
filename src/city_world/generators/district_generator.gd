class_name DistrictGenerator
extends RefCounted

## Assigns cohesive neighborhood sub-zones across the procedural city area.

static func eval_creek_x(z: float, district_centers: Dictionary) -> float:
	var cx_base := float(district_centers.get("creek_x_base", 1450.0))
	var c_phase := float(district_centers.get("creek_phase", 0.0))
	var c_amp := float(district_centers.get("creek_amp", 75.0))
	return cx_base + sin(z * 0.010 + c_phase) * c_amp + cos(z * 0.005 - c_phase * 0.5) * 14.0


static func generate_district_centers(config: CityConfig, rng: RandomNumberGenerator) -> Dictionary:
	var s := config.world_size
	# Pick which side hosts the downtown/commercial spine vs residential hillside.
	var flip_x := rng.randf() < 0.5
	var flip_z := rng.randf() < 0.5

	var dx := (0.34 if flip_x else 0.44) * s
	var dz := (0.42 if flip_z else 0.48) * s
	var rx := (0.72 if flip_x else 0.20) * s
	var rz := (0.22 if flip_z else 0.78) * s
	var ix := (0.22 if flip_x else 0.24) * s
	var iz := (0.80 if flip_z else 0.20) * s
	var comm_offset := (0.11 * s) if not flip_z else (-0.11 * s)

	return {
		"downtown_mixed": Vector2(dx, dz),
		"commercial_corridor": Vector2(lerpf(dx, s * 0.55, 0.5), dz + comm_offset),
		"residential_hills": Vector2(rx, rz),
		"light_industrial": Vector2(ix, iz),
		"creek_x_base": s * 0.66 + rng.randf_range(-0.024 * s, 0.024 * s),
		"creek_phase": rng.randf_range(0.0, TAU),
		"creek_amp": rng.randf_range(maxf(28.0, 0.022 * s), maxf(48.0, 0.035 * s)),
	}


static func classify_block(block_center: Vector2, creek_x_at_z: float, creek_half_w: float, district_centers: Dictionary, world_size: float = 2304.0) -> String:
	if absf(block_center.x - creek_x_at_z) < creek_half_w + 34.0:
		return "civic_park"

	var zone_radius := maxf(120.0, world_size * 0.25)

	var d_downtown := block_center.distance_to(district_centers["downtown_mixed"])
	if d_downtown < zone_radius:
		return "downtown_mixed"

	var d_comm := block_center.distance_to(district_centers["commercial_corridor"])
	if d_comm < zone_radius:
		return "commercial_corridor"

	var d_ind := block_center.distance_to(district_centers["light_industrial"])
	if d_ind < zone_radius:
		return "light_industrial"

	return "residential_hills"


static func ensure_district_diversity(blocks: Array, district_centers: Dictionary) -> void:
	## Guarantees every core urban zone has representation among non-park blocks.
	var buildable: Array[ParcelData.CityBlock] = []
	var counts := {}
	for raw_blk in blocks:
		var blk: ParcelData.CityBlock = raw_blk
		if blk.district_zone == "civic_park":
			continue
		buildable.append(blk)
		counts[blk.district_zone] = int(counts.get(blk.district_zone, 0)) + 1

	if buildable.size() < 4:
		return

	var required: Array[String] = ["downtown_mixed", "commercial_corridor", "light_industrial", "residential_hills"]
	for zone in required:
		if int(counts.get(zone, 0)) > 0:
			continue
		var target_pt: Vector2 = district_centers[zone]
		var best_blk: ParcelData.CityBlock = null
		var best_d := INF
		for blk in buildable:
			if int(counts.get(blk.district_zone, 0)) <= 1 and blk.district_zone in required:
				continue
			var d: float = blk.center.distance_to(target_pt)
			if d < best_d:
				best_d = d
				best_blk = blk
		if best_blk == null:
			best_blk = buildable[0]
		counts[best_blk.district_zone] = maxi(0, int(counts.get(best_blk.district_zone, 1)) - 1)
		best_blk.district_zone = zone
		counts[zone] = int(counts.get(zone, 0)) + 1

	# Ensure every seed hosts dedicated urban/creekside parks while keeping buildable lot capacity intact.
	var park_count := 0
	var sized_park_count := 0
	var existing_parks: Array[Vector2] = []
	for raw_blk in blocks:
		var blk: ParcelData.CityBlock = raw_blk
		if blk.district_zone == "civic_park":
			park_count += 1
			existing_parks.append(blk.center)
			var area := absf(ParcelData.signed_area(blk.buildable_polygon))
			if area >= 1400.0 and area <= 85000.0:
				sized_park_count += 1

	var target_parks := 2 if blocks.size() <= 22 else (5 if blocks.size() >= 130 else 3)
	var target_sized := 1 if blocks.size() <= 22 else (3 if blocks.size() >= 130 else 2)

	while park_count < target_parks or sized_park_count < target_sized:
		var min_keep := 1 if sized_park_count == 0 else 2
		var best_blk: ParcelData.CityBlock = null
		var best_score := INF
		for blk in buildable:
			if blk.district_zone == "civic_park":
				continue
			if int(counts.get(blk.district_zone, 0)) <= min_keep and blk.district_zone in required:
				continue
			var area := absf(ParcelData.signed_area(blk.buildable_polygon))
			if area < 1400.0:
				continue
			var cx_at_z := eval_creek_x(blk.center.y, district_centers)
			var creek_d := absf(blk.center.x - cx_at_z)
			var size_penalty := 0.0
			if area < 2400.0 or area > 85000.0:
				size_penalty = 520.0
			elif area > 22000.0:
				size_penalty = 180.0 + (area - 22000.0) * 0.006
			var spread_penalty := 0.0
			for ep in existing_parks:
				if blk.center.distance_to(ep) < 160.0:
					spread_penalty += 180.0
			var score := creek_d + size_penalty + spread_penalty
			if score < best_score:
				best_score = score
				best_blk = blk
		if best_blk == null:
			break
		counts[best_blk.district_zone] = maxi(0, int(counts.get(best_blk.district_zone, 1)) - 1)
		best_blk.district_zone = "civic_park"
		park_count += 1
		var chosen_area := absf(ParcelData.signed_area(best_blk.buildable_polygon))
		if chosen_area >= 1400.0 and chosen_area <= 85000.0:
			sized_park_count += 1
		existing_parks.append(best_blk.center)
