class_name InteriorBlueprint
extends RefCounted

## Authoritative deterministic interior specification derived directly from
## a BuildingBlueprint's footprint, doors, floor heights, and exterior window bays.

var building_id: String = ""
var seed_value: int = 0
var archetype: String = ""
var inner_min: Vector2 = Vector2.ZERO
var inner_max: Vector2 = Vector2.ZERO

# Per-floor dicts: floor_index, base_y, height, slab_thickness, entry_point,
# floor_rects (excluding stair shafts), rooms, partitions, interior_doors, furniture, lights, guardrails.
var floors: Array[Dictionary] = []

# Vertically aligned switchback stair runs between floor fl and fl + 1.
var stairs: Array[Dictionary] = []

# Optional multi-floor passenger elevator spec for tall buildings and hospitals.
var elevator: Dictionary = {}

# Exterior window bays synced for cutaway shell rendering/collision when active.
var window_openings: Array[Dictionary] = []

# Verification telemetry populated by InteriorGenerator's 2D BFS & window clearance checks.
var bfs_reachable: bool = false
var reachable_room_count: int = 0
var total_room_count: int = 0
var wall_window_conflicts: int = 0


func get_interior_door_ids() -> Array[String]:
	var ids: Array[String] = []
	for f_data in floors:
		for d in f_data.get("interior_doors", []):
			if not bool(d.get("is_open_arch", false)):
				ids.append(String(d["door_id"]))
	return ids


func get_total_furniture_count() -> int:
	var n := 0
	for f_data in floors:
		n += f_data.get("furniture", []).size()
	return n
