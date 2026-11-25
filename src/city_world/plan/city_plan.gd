class_name CityPlan
extends RefCounted

## Complete authoritative city plan generated deterministically from CityConfig.
var config: CityConfig = null
var terrain: TerrainData = null
var road_graph: RoadGraph = null
var blocks: Array = [] # Array[ParcelData.CityBlock]
var parcels: Array = [] # Array[ParcelData.Parcel]
var blueprints: Array[BuildingBlueprint] = []
var park_walkways: Array[Dictionary] = []
var props: Array[Dictionary] = []
var district_centers: Dictionary = {} # zone_name -> Vector2
var spawn_position: Vector3 = Vector3(768.0, 5.0, 768.0)
var spawn_yaw: float = 0.0
var plan_hash: String = ""


func compute_plan_hash() -> String:
	var parts := PackedStringArray()
	parts.append("SEED:%d" % config.world_seed)
	if terrain != null:
		parts.append("TERRAIN:" + terrain.compute_hash())
	if road_graph != null:
		parts.append("ROADS:" + road_graph.compute_hash())
	parts.append("PARCELS:%d" % parcels.size())
	for bp in blueprints:
		parts.append(JSON.stringify(bp.to_dict()))
	parts.append("WALKWAYS:%d" % park_walkways.size())
	for w in park_walkways:
		var wc: Vector2 = w.get("center", Vector2.ZERO)
		var pts: PackedVector2Array = w.get("points", PackedVector2Array())
		parts.append("W:%s,%.2f,%.2f,%d" % [w.get("style", ""), wc.x, wc.y, pts.size()])
	parts.append("PROPS:%d" % props.size())
	for p in props:
		var pos: Vector3 = p.get("pos", Vector3.ZERO)
		parts.append("P:%s,%.2f,%.2f,%.2f" % [p.get("type", ""), pos.x, pos.y, pos.z])
	plan_hash = "\n".join(parts).sha256_text().substr(0, 20)
	return plan_hash


func get_blueprint_by_id(bld_id: String) -> BuildingBlueprint:
	for bp in blueprints:
		if bp.id == bld_id:
			return bp
	return null


func get_building_count_by_archetype() -> Dictionary:
	var counts := {}
	for bp in blueprints:
		counts[bp.archetype] = int(counts.get(bp.archetype, 0)) + 1
	return counts
