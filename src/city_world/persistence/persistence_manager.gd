class_name PersistenceManager
extends RefCounted

## Separates deterministic procedural WorldSeed/CityConfig from ChangedWorldState
## (opened doors, player transform) so saved changes persist cleanly across reloads.

const DEFAULT_SAVE_PATH := "user://procedural_city_save.json"


static func save_state(
	config: CityConfig,
	doors_by_id: Dictionary,
	player_pos: Vector3,
	player_yaw: float,
	path: String = DEFAULT_SAVE_PATH,
	extra_opened_doors: Array[String] = [],
	atmosphere_state: Dictionary = {}
) -> bool:
	var open_map := {}
	for extra_id in extra_opened_doors:
		open_map[extra_id] = true
	for door_id in doors_by_id.keys():
		var door: InteractiveDoor = doors_by_id[door_id]
		if door != null:
			if door.is_open:
				open_map[door_id] = true
			else:
				open_map.erase(door_id)
	var opened_doors: Array[String] = []
	for k in open_map.keys():
		opened_doors.append(String(k))
	opened_doors.sort()

	var changed := {
		"opened_doors": opened_doors,
		"player_position": [player_pos.x, player_pos.y, player_pos.z],
		"player_yaw": player_yaw,
	}
	if not atmosphere_state.is_empty():
		changed["atmosphere"] = atmosphere_state

	var payload := {
		"version": 1,
		"world_seed": config.world_seed,
		"city_config": config.to_dict(),
		"changed_world_state": changed,
	}

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(payload, "  "))
	f.close()
	return true


static func load_state(path: String = DEFAULT_SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed
