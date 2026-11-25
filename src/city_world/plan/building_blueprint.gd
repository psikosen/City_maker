class_name BuildingBlueprint
extends RefCounted

## Authoritative blueprint for a single generated building.
## Visual meshes, collision shapes, entrances, and saved door states all derive from this data.

const COMMERCIAL_ARCHETYPES := [
	"mixed_use_midrise",
	"modern_office",
	"brick_shop",
	"civic_hall",
	"skyscraper_tower",
	"retail_anchor",
	"municipal_hall",
	"police_station",
	"fire_station",
	"hospital",
	"school",
]

const CIVIC_AND_CHURCH_ARCHETYPES := [
	"civic_hall",
	"municipal_hall",
	"police_station",
	"fire_station",
	"hospital",
	"school",
	"church",
]

static func is_commercial_archetype(arch: String) -> bool:
	return arch in COMMERCIAL_ARCHETYPES

static func is_civic_or_church(arch: String) -> bool:
	return arch in CIVIC_AND_CHURCH_ARCHETYPES

var id: String = ""
var parcel_id: String = ""
var block_id: int = -1
var chunk_coord: Vector2i = Vector2i.ZERO
var district_zone: String = "residential_hills"
var archetype: String = "house_pitched"
var style: String = "suburban_siding"

# World XZ transform: local +Z faces the street frontage.
var center: Vector2 = Vector2.ZERO
var yaw: float = 0.0
var width: float = 10.0
var depth: float = 10.0

# Elevations
var sidewalk_y: float = 0.0
var base_y: float = 0.16
var foundation_bottom_y: float = -1.0

# Vertical structure
var floors: int = 2
var floor_height: float = 3.1
var ground_floor_height: float = 3.4
var roof_type: String = "gable" # gable, hip, flat_parapet, shed_solar
var roof_height: float = 2.6

# Architectural variation
var wall_color: Color = Color(0.82, 0.80, 0.76)
var trim_color: Color = Color(0.24, 0.26, 0.29)
var accent_color: Color = Color(0.18, 0.45, 0.62)
var roof_color: Color = Color(0.25, 0.27, 0.30)
var has_solar_panels: bool = false
var has_awning: bool = false
var has_balconies: bool = false
var has_signage: bool = false
var sign_label: String = ""
var sign_tagline: String = ""
var sign_style: String = "lightbox"
var venue_type: String = ""
var has_blade_sign: bool = false
var has_crown_sign: bool = false
var has_helipad: bool = false
var is_landmark_tower: bool = false
var window_cols_front: int = 3
var window_cols_side: int = 3

# Corner dual-frontage, podium-tower setbacks, crowns & residential exterior trim
var secondary_front_face: String = "" # "", "left", "right"
var setback_floor: int = 0 # 0 = straight extrusion; >= 4 = upper floors step inward
var setback_inset_front: float = 0.0
var setback_inset_side: float = 0.0
var stair_on_left: bool = true
var crown_style: String = "flat" # "flat", "stepped", "fin_parapet", "chamfer_glass"
var has_porch: bool = false
var porch_depth: float = 0.0
var has_garage: bool = false
var garage_local_x: float = 0.0

# Authoritative entrance + physical vestibule
var door_id: String = ""
var door_local_x: float = 0.0
var door_width: float = 1.3
var door_height: float = 2.4
var wall_thickness: float = 0.35
var vestibule_width: float = 3.2
var vestibule_depth: float = 2.8
var approach_length: float = 1.4


func get_total_wall_height() -> float:
	if floors <= 1:
		return ground_floor_height
	return ground_floor_height + float(floors - 1) * floor_height


func get_roof_top_y() -> float:
	return base_y + get_total_wall_height() + roof_height


func has_setback() -> bool:
	return setback_floor >= 4 and setback_floor < floors and (setback_inset_front > 0.1 or setback_inset_side > 0.1)


func get_setback_y() -> float:
	if not has_setback():
		return get_total_wall_height()
	return ground_floor_height + float(setback_floor - 1) * floor_height


func get_tier_bounds_local(fl: int) -> Dictionary:
	var hw := width * 0.5
	var hd := depth * 0.5
	if not has_setback() or fl < setback_floor:
		return {"x0": -hw, "x1": hw, "z0": -hd, "z1": hd}
	var x0 := -hw if stair_on_left else (-hw + setback_inset_side)
	var x1 := (hw - setback_inset_side) if stair_on_left else hw
	var z0 := -hd
	var z1 := hd - setback_inset_front
	return {"x0": x0, "x1": x1, "z0": z0, "z1": z1}


func local_to_world_2d(local_xz: Vector2) -> Vector2:
	var right := Vector2(cos(yaw), -sin(yaw))
	var forward := Vector2(sin(yaw), cos(yaw))
	return center + right * local_xz.x + forward * local_xz.y


func local_to_world_3d(local_xyz: Vector3) -> Vector3:
	var p2 := local_to_world_2d(Vector2(local_xyz.x, local_xyz.z))
	return Vector3(p2.x, base_y + local_xyz.y, p2.y)


func get_footprint_corners() -> PackedVector2Array:
	return ParcelData.get_obb_corners(center, Vector2(width * 0.5, depth * 0.5), yaw)


func get_door_world_pos() -> Vector3:
	return local_to_world_3d(Vector3(door_local_x, door_height * 0.5, depth * 0.5 - wall_thickness * 0.5))


func get_approach_world_pos() -> Vector3:
	return local_to_world_3d(Vector3(door_local_x, 0.1, depth * 0.5 + approach_length + 0.8))


func get_vestibule_world_center() -> Vector3:
	return local_to_world_3d(Vector3(door_local_x, 0.9, depth * 0.5 - vestibule_depth * 0.5))


func get_collider_boxes_local() -> Array[Dictionary]:
	## Returns authoritative local AABB box specs relative to (center.x, base_y, center.y).
	## Every wall, floor, foundation, and vestibule collider comes exclusively from this helper.
	var boxes: Array[Dictionary] = []
	var hw := width * 0.5
	var hd := depth * 0.5
	var wall_h := get_total_wall_height()
	var wt := wall_thickness

	# 1. Foundation plinth from foundation_bottom_y up to base_y (local y <= 0).
	var found_h := maxf(0.5, base_y - foundation_bottom_y)
	boxes.append({
		"role": "foundation",
		"pos": Vector3(0.0, -found_h * 0.5, 0.0),
		"size": Vector3(width, found_h, depth),
	})

	# 2. Doorway & vestibule bounds clamped safely inside footprint.
	var d_x0 := door_local_x - door_width * 0.5
	var d_x1 := door_local_x + door_width * 0.5
	var v_half_w := vestibule_width * 0.5
	var v_x0 := maxf(-hw + 0.35, minf(d_x0 - 0.55, door_local_x - v_half_w))
	var v_x1 := minf(hw - 0.35, maxf(d_x1 + 0.55, door_local_x + v_half_w))
	var v_z0 := hd - vestibule_depth
	var front_inner_z := hd - wt

	# 3. Vestibule floor (top flush at local y = 0.0).
	boxes.append({
		"role": "vestibule_floor",
		"pos": Vector3((v_x0 + v_x1) * 0.5, -0.15, (v_z0 + hd) * 0.5),
		"size": Vector3(v_x1 - v_x0, 0.30, hd - v_z0),
	})

	# 4. Vestibule ceiling (above ground floor height, below upper facade).
	var tier1_top := get_setback_y()
	var ceil_y := minf(ground_floor_height, tier1_top)
	boxes.append({
		"role": "vestibule_ceiling",
		"pos": Vector3((v_x0 + v_x1) * 0.5, ceil_y + 0.12, (v_z0 + front_inner_z) * 0.5),
		"size": Vector3(v_x1 - v_x0, 0.24, front_inner_z - v_z0),
	})

	# 5. Main solid mass behind the vestibule (from -hd to v_z0, up to tier1_top).
	if v_z0 > -hd + 0.1:
		var back_d := v_z0 - (-hd)
		boxes.append({
			"role": "core_back",
			"pos": Vector3(0.0, tier1_top * 0.5, -hd + back_d * 0.5),
			"size": Vector3(width, tier1_top, back_d),
		})

	# 6. Side solid masses flanking the vestibule (from v_z0 to front_inner_z).
	var flank_d := front_inner_z - v_z0
	if flank_d > 0.05:
		if v_x0 > -hw + 0.05:
			var lw := v_x0 - (-hw)
			boxes.append({
				"role": "flank_left",
				"pos": Vector3(-hw + lw * 0.5, tier1_top * 0.5, v_z0 + flank_d * 0.5),
				"size": Vector3(lw, tier1_top, flank_d),
			})
		if v_x1 < hw - 0.05:
			var rw := hw - v_x1
			boxes.append({
				"role": "flank_right",
				"pos": Vector3(v_x1 + rw * 0.5, tier1_top * 0.5, v_z0 + flank_d * 0.5),
				"size": Vector3(rw, tier1_top, flank_d),
			})

	# 7. Front wall piers & lintel around the open doorway (from front_inner_z to +hd).
	if d_x0 > -hw + 0.05:
		var p_lw := d_x0 - (-hw)
		boxes.append({
			"role": "front_pier_left",
			"pos": Vector3(-hw + p_lw * 0.5, tier1_top * 0.5, front_inner_z + wt * 0.5),
			"size": Vector3(p_lw, tier1_top, wt),
		})
	if d_x1 < hw - 0.05:
		var p_rw := hw - d_x1
		boxes.append({
			"role": "front_pier_right",
			"pos": Vector3(d_x1 + p_rw * 0.5, tier1_top * 0.5, front_inner_z + wt * 0.5),
			"size": Vector3(p_rw, tier1_top, wt),
		})
	var lintel_h := tier1_top - door_height
	if lintel_h > 0.05:
		boxes.append({
			"role": "front_lintel",
			"pos": Vector3(door_local_x, door_height + lintel_h * 0.5, front_inner_z + wt * 0.5),
			"size": Vector3(door_width, lintel_h, wt),
		})

	# 8. Upper mass above vestibule ceiling (up to tier1_top).
	var upper_h := tier1_top - (ceil_y + 0.24)
	if upper_h > 0.05 and flank_d > 0.05:
		boxes.append({
			"role": "upper_over_vestibule",
			"pos": Vector3((v_x0 + v_x1) * 0.5, ceil_y + 0.24 + upper_h * 0.5, v_z0 + flank_d * 0.5),
			"size": Vector3(v_x1 - v_x0, upper_h, flank_d),
		})

	# 8b. Stepped upper tower shaft above setback floor (if has_setback).
	var top_cx := 0.0
	var top_cz := 0.0
	var top_w := width
	var top_d := depth
	if has_setback():
		var tb := get_tier_bounds_local(setback_floor)
		var u_x0 := float(tb["x0"])
		var u_x1 := float(tb["x1"])
		var u_z0 := float(tb["z0"])
		var u_z1 := float(tb["z1"])
		top_w = u_x1 - u_x0
		top_d = u_z1 - u_z0
		top_cx = (u_x0 + u_x1) * 0.5
		top_cz = (u_z0 + u_z1) * 0.5
		var tower_h := wall_h - tier1_top
		if tower_h > 0.1:
			boxes.append({
				"role": "upper_tower",
				"pos": Vector3(top_cx, tier1_top + tower_h * 0.5, top_cz),
				"size": Vector3(top_w, tower_h, top_d),
			})

	# 9. Flat roof parapet slab (gable/hip roofs add a convex prism separately).
	if roof_type == "flat_parapet":
		boxes.append({
			"role": "roof_slab",
			"pos": Vector3(top_cx, wall_h + 0.22, top_cz),
			"size": Vector3(top_w + 0.2, 0.44, top_d + 0.2),
		})

	return boxes


func to_dict() -> Dictionary:
	return {
		"id": id,
		"parcel_id": parcel_id,
		"block_id": block_id,
		"chunk": [chunk_coord.x, chunk_coord.y],
		"district_zone": district_zone,
		"archetype": archetype,
		"style": style,
		"center": [snappedf(center.x, 0.001), snappedf(center.y, 0.001)],
		"yaw": snappedf(yaw, 0.0001),
		"width": snappedf(width, 0.001),
		"depth": snappedf(depth, 0.001),
		"sidewalk_y": snappedf(sidewalk_y, 0.001),
		"base_y": snappedf(base_y, 0.001),
		"foundation_bottom_y": snappedf(foundation_bottom_y, 0.001),
		"floors": floors,
		"floor_height": floor_height,
		"ground_floor_height": ground_floor_height,
		"roof_type": roof_type,
		"roof_height": roof_height,
		"has_solar_panels": has_solar_panels,
		"sign_label": sign_label,
		"venue_type": venue_type,
		"has_crown_sign": has_crown_sign,
		"has_helipad": has_helipad,
		"secondary_front_face": secondary_front_face,
		"setback_floor": setback_floor,
		"crown_style": crown_style,
		"has_porch": has_porch,
		"has_garage": has_garage,
		"door_id": door_id,
		"door_local_x": snappedf(door_local_x, 0.001),
		"door_width": door_width,
		"door_height": door_height,
		"vestibule_width": vestibule_width,
		"vestibule_depth": vestibule_depth,
	}
