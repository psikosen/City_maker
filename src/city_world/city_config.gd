class_name CityConfig
extends Resource

## Configuration for deterministic city generation.
@export var world_seed: int = 202801
@export var world_size: float = 2304.0
@export var chunk_size: float = 128.0
@export var terrain_step: float = 1.0
@export var target_min_buildings: int = 640
@export var target_max_buildings: int = 960
@export var enable_props: bool = true


func get_chunks_per_axis() -> int:
	return maxi(1, int(round(world_size / chunk_size)))


func to_dict() -> Dictionary:
	return {
		"world_seed": world_seed,
		"world_size": world_size,
		"chunk_size": chunk_size,
		"terrain_step": terrain_step,
		"target_min_buildings": target_min_buildings,
		"target_max_buildings": target_max_buildings,
		"enable_props": enable_props,
	}


static func from_dict(data: Dictionary) -> CityConfig:
	var cfg := CityConfig.new()
	cfg.world_seed = int(data.get("world_seed", 202801))
	cfg.world_size = float(data.get("world_size", 2304.0))
	cfg.chunk_size = float(data.get("chunk_size", 128.0))
	cfg.terrain_step = float(data.get("terrain_step", 1.0))
	cfg.target_min_buildings = int(data.get("target_min_buildings", 640))
	cfg.target_max_buildings = int(data.get("target_max_buildings", 960))
	cfg.enable_props = bool(data.get("enable_props", true))
	return cfg
