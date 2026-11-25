class_name PropBuilder
extends RefCounted

## Builds grounded 2028 street props (smart streetlights, traffic signals, transit shelters,
## EV charging stations, street/park trees, benches, and parked EVs) with simplified colliders.

static var _tree_canopy_mesh: ArrayMesh = null
static var _decal_fallback_cache: Dictionary = {}

static func create_chunk_batch() -> Dictionary:
	return {
		"minor": {},
		"major_noshadow": {},
		"major_shadow": {},
		"coastal": {},
		"_riprap": {},
		"_riprap_mat": null,
		"_shared_body": null,
	}


static func commit_chunk_batch(chunk_node: Node3D, batch: Dictionary) -> void:
	var shared_body: StaticBody3D = batch.get("_shared_body", null) as StaticBody3D
	if shared_body != null:
		if shared_body.get_child_count() > 0:
			chunk_node.add_child(shared_body)
		else:
			shared_body.free()
	const TIER_CFG := {
		"minor": [105.0, 14.0, false],
		"major_noshadow": [210.0, 22.0, false],
		"major_shadow": [285.0, 28.0, true],
		"coastal": [460.0, 40.0, true],
	}
	for tier in TIER_CFG.keys():
		var mat_map: Dictionary = batch.get(tier, {})
		var cfg: Array = TIER_CFG[tier]
		var vis_end := float(cfg[0])
		var margin := float(cfg[1])
		var cast_sh := bool(cfg[2])
		var idx := 0
		for mat_k in mat_map.keys():
			var st: SurfaceTool = mat_map[mat_k]
			var mesh := st.commit()
			if mesh == null or mesh.get_surface_count() == 0:
				continue
			idx += 1
			var mi := MeshInstance3D.new()
			mi.name = "Props_%s_%d" % [tier, idx]
			mi.mesh = mesh
			mi.material_override = mat_k as Material
			mi.visibility_range_end = vis_end
			mi.visibility_range_end_margin = margin
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_sh else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chunk_node.add_child(mi)

	var riprap_map: Dictionary = batch.get("_riprap", {})
	var riprap_mat: Material = batch.get("_riprap_mat", null) as Material
	if not riprap_map.is_empty() and riprap_mat != null:
		var r_cfg := [0.0, 0.0, 140.0, 14.0, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF]
		for var_k in riprap_map.keys():
			var items: Array = riprap_map[var_k]
			if items.is_empty():
				continue
			var bundle := FloraGenerator.get_flora_bundle("riprap", "riprap_boulder", int(var_k))
			var rock_m: ArrayMesh = bundle.get("riprap_mesh", null)
			if rock_m != null:
				_spawn_tree_mm(chunk_node, "FloraRiprap_%d" % int(var_k), rock_m, riprap_mat, items, r_cfg)


static func _classify_batch_tier(ptype: String) -> String:
	match ptype:
		"fire_hydrant", "mailbox", "trashcan", "bike_rack", "planter_box", "utility_box", "bench", "sidewalk_bench", "ev_charger", "path_bollard", "crosswalk_button", "a_frame_sign", "pallet_stack", "safety_bollard", "ac_condenser", "lot_fence":
			return "minor"
		"streetlight", "traffic_signal", "transit_shelter", "billboard", "park_gazebo":
			return "major_shadow"
		"beach_boardwalk_seg", "beach_pier", "lifeguard_tower", "beach_umbrella_set", "surfboard_rack", "beach_palm", "coral_reef_cluster", "underwater_kelp":
			return "coastal"
		_:
			return "major_noshadow"


static func _get_batch_st(parent: Node3D, mat: Material) -> SurfaceTool:
	var batch: Dictionary = parent.get_meta("_prop_batch")
	var tier := String(parent.get_meta("_prop_tier"))
	var tier_map: Dictionary = batch[tier]
	if tier_map.has(mat):
		return tier_map[mat]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	tier_map[mat] = st
	return st


static func build_prop(prop: Dictionary, mats: MaterialLibrary, chunk_batch: Dictionary = {}) -> Node3D:
	var ptype: String = prop.get("type", "")
	if ptype == "weather_decal":
		return _build_weather_decal(prop, mats)

	var pos: Vector3 = prop.get("pos", Vector3.ZERO)
	var yaw: float = float(prop.get("yaw", 0.0))
	var scale_v: float = float(prop.get("scale", 1.0))

	var root := Node3D.new()
	root.name = "Prop_%s" % ptype
	root.position = pos
	root.rotation.y = yaw
	if not chunk_batch.is_empty() and ptype != "street_tree" and ptype != "park_tree" and ptype != "riprap_cluster":
		root.set_meta("_prop_batch", chunk_batch)
		root.set_meta("_prop_tier", _classify_batch_tier(ptype))
		root.set_meta("_prop_xform", Transform3D(Basis(Vector3.UP, yaw), pos))

	match ptype:
		"streetlight":
			_build_streetlight(root, mats)
		"traffic_signal":
			_build_traffic_signal(root, mats)
		"street_sign":
			_build_street_sign(root, prop, mats)
		"transit_shelter":
			_build_transit_shelter(root, mats)
		"ev_charger":
			_build_ev_charger(root, mats)
		"street_tree", "park_tree":
			_build_procedural_tree(root, prop, scale_v, mats)
		"bench":
			_build_bench(root, mats)
		"sidewalk_bench":
			_build_sidewalk_bench(root, mats)
		"trashcan":
			_build_trashcan(root, int(prop.get("variant", 0)), mats)
		"fire_hydrant":
			_build_fire_hydrant(root, mats)
		"mailbox":
			_build_mailbox(root, mats)
		"utility_box":
			_build_utility_box(root, mats)
		"planter_box":
			_build_planter_box(root, mats)
		"bike_rack":
			_build_bike_rack(root, mats)
		"city_kiosk":
			_build_city_kiosk(root, prop, mats)
		"billboard":
			_build_billboard(root, prop, mats)
		"park_gazebo":
			_build_park_gazebo(root, mats)
		"park_fountain":
			_build_park_fountain(root, mats)
		"cafe_seating":
			_build_cafe_seating(root, int(prop.get("variant", 0)), mats)
		"a_frame_sign":
			_build_a_frame_sign(root, mats)
		"crosswalk_button":
			_build_crosswalk_button(root, mats)
		"parcel_locker":
			_build_parcel_locker(root, mats)
		"sport_court":
			_build_sport_court(root, mats)
		"path_bollard":
			_build_path_bollard(root, mats)
		"parked_ev":
			_build_parked_ev(root, int(prop.get("variant", 0)), mats)
		"riprap_cluster":
			_build_riprap_cluster(root, prop, mats, chunk_batch)
		"commercial_dumpster":
			_build_commercial_dumpster(root, mats)
		"pallet_stack":
			_build_pallet_stack(root, int(prop.get("variant", 0)), mats)
		"safety_bollard":
			_build_safety_bollard(root, mats)
		"ac_condenser":
			_build_ac_condenser(root, mats)
		"chainlink_fence":
			_build_chainlink_fence(root, prop, mats)
		"driveway_pad":
			_build_driveway_pad(root, prop, mats)
		"lot_fence":
			_build_lot_fence(root, prop, mats)
		"beach_boardwalk_seg":
			_build_beach_boardwalk_seg(root, prop, mats)
		"beach_pier":
			_build_beach_pier(root, prop, mats)
		"lifeguard_tower":
			_build_lifeguard_tower(root, int(prop.get("variant", 0)), mats)
		"beach_umbrella_set":
			_build_beach_umbrella_set(root, int(prop.get("variant", 0)), mats)
		"surfboard_rack":
			_build_surfboard_rack(root, int(prop.get("variant", 0)), mats)
		"beach_palm":
			_build_beach_palm(root, scale_v, int(prop.get("variant", 0)), mats)
		"coral_reef_cluster":
			_build_coral_reef_cluster(root, scale_v, int(prop.get("variant", 0)), mats)
		"underwater_kelp":
			_build_underwater_kelp(root, scale_v, int(prop.get("variant", 0)), mats)

	_apply_prop_lod_culling(root, ptype)
	return root


static func _apply_prop_lod_culling(root: Node3D, ptype: String) -> void:
	var vis_end := 190.0
	var disable_shadows := false
	match ptype:
		"fire_hydrant", "mailbox", "trashcan", "bike_rack", "planter_box", "utility_box", "path_bollard", "crosswalk_button", "a_frame_sign", "pallet_stack", "safety_bollard", "ac_condenser", "lot_fence":
			vis_end = 115.0
			disable_shadows = true
		"bench", "sidewalk_bench", "ev_charger", "parcel_locker":
			vis_end = 135.0
		"street_sign", "transit_shelter", "city_kiosk", "parked_ev", "cafe_seating", "commercial_dumpster", "chainlink_fence", "driveway_pad":
			vis_end = 195.0
		"streetlight", "traffic_signal", "billboard", "park_gazebo", "park_fountain", "sport_court":
			vis_end = 310.0
		"beach_boardwalk_seg", "beach_pier", "lifeguard_tower", "beach_umbrella_set", "surfboard_rack", "beach_palm", "coral_reef_cluster", "underwater_kelp":
			vis_end = 460.0
		_:
			return
	var margin := clampf(vis_end * 0.14, 12.0, 28.0)
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for ch in cur.get_children():
			stack.append(ch)
			if ch is GeometryInstance3D:
				var gi := ch as GeometryInstance3D
				gi.visibility_range_end = 92.0 if ch is Label3D else vis_end
				gi.visibility_range_end_margin = margin
				gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				if disable_shadows or ch is Label3D:
					gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func build_tree_collider(prop: Dictionary) -> Node3D:
	var pos: Vector3 = prop.get("pos", Vector3.ZERO)
	var yaw: float = float(prop.get("yaw", 0.0))
	var scale_v: float = float(prop.get("scale", 1.0))
	var species: String = prop.get("species", "cedar_elm")
	var variant: int = int(prop.get("variant", 0))
	var bundle := TreeGenerator.get_species_bundle(species, variant)
	var trunk_r: float = float(bundle["trunk_radius"]) * scale_v
	var trunk_h: float = float(bundle["trunk_height"]) * scale_v

	var root := Node3D.new()
	root.name = "TreeCollider_%s" % species
	root.position = pos
	root.rotation.y = yaw

	var body := StaticBody3D.new()
	body.set_meta("tree_species", species)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = maxf(0.14, trunk_r * 1.15)
	cyl.height = maxf(1.8, trunk_h + 0.3)
	cs.shape = cyl
	cs.position = Vector3(0.0, cyl.height * 0.5, 0.0)
	body.add_child(cs)
	root.add_child(body)
	return root


static func emit_street_tree_bed(pos: Vector3, yaw: float, scale_v: float, chunk_batch: Dictionary, mats: MaterialLibrary) -> void:
	## Emits a street-aligned granite-curbed tree pit + mulched soil bed + iron trim directly into chunk batching.
	if chunk_batch.is_empty():
		return
	var s_fit := clampf(scale_v, 0.88, 1.08)
	var half_x := clampf(0.64 * s_fit, 0.58, 0.70) # Across sidewalk: strictly inset inside curb & walkway
	var half_z := clampf(0.80 * s_fit, 0.72, 0.88) # Along road corridor
	var curb_w := 0.13
	var span_x := half_x * 2.0
	var inner_x := maxf(0.84, span_x - curb_w * 2.0)
	var inner_z := maxf(1.06, half_z * 2.0 - curb_w * 2.0)
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	var tier_map: Dictionary = chunk_batch["minor"]
	var curb_st := _get_batch_st_from_map(tier_map, mats.bridge_concrete_mat)
	var soil_st := _get_batch_st_from_map(tier_map, mats.soil_mulch_mat)
	var iron_st := _get_batch_st_from_map(tier_map, mats.dark_metal_mat)

	# 4 street-aligned granite planter curb borders (anchored -0.13m below sidewalk, flush +0.07m lip above)
	_emit_batch_box(curb_st, xf * Vector3(0.0, -0.03, half_z - curb_w * 0.5), xf.basis, Vector3(span_x, 0.20, curb_w))
	_emit_batch_box(curb_st, xf * Vector3(0.0, -0.03, -half_z + curb_w * 0.5), xf.basis, Vector3(span_x, 0.20, curb_w))
	_emit_batch_box(curb_st, xf * Vector3(-half_x + curb_w * 0.5, -0.03, 0.0), xf.basis, Vector3(curb_w, 0.20, inner_z))
	_emit_batch_box(curb_st, xf * Vector3(half_x - curb_w * 0.5, -0.03, 0.0), xf.basis, Vector3(curb_w, 0.20, inner_z))
	# Recessed dark organic bark-mulch planting bed + perimeter iron trim
	_emit_batch_box(soil_st, xf * Vector3(0.0, -0.025, 0.0), xf.basis, Vector3(inner_x + 0.02, 0.10, inner_z + 0.02))
	var rim_x := inner_x * 0.5 - 0.018
	var rim_z := inner_z * 0.5 - 0.018
	_emit_batch_box(iron_st, xf * Vector3(0.0, 0.052, rim_z), xf.basis, Vector3(inner_x, 0.032, 0.04))
	_emit_batch_box(iron_st, xf * Vector3(0.0, 0.052, -rim_z), xf.basis, Vector3(inner_x, 0.032, 0.04))
	_emit_batch_box(iron_st, xf * Vector3(-rim_x, 0.052, 0.0), xf.basis, Vector3(0.04, 0.032, inner_z))
	_emit_batch_box(iron_st, xf * Vector3(rim_x, 0.052, 0.0), xf.basis, Vector3(0.04, 0.032, inner_z))


static func build_chunk_flora_multimeshes(chunk_node: Node3D, buckets: Dictionary, mats: MaterialLibrary) -> void:
	for bucket_key in buckets.keys():
		var items: Array = buckets[bucket_key]
		if items.is_empty():
			continue
		var first: Dictionary = items[0]
		var kind: String = first["kind"]
		var sp: String = first["species"]
		var var_idx: int = int(first["variant"])
		var bundle := FloraGenerator.get_flora_bundle(kind, sp, var_idx)
		var is_bush := (kind == "bush")
		var is_reed := (sp == "cattail_reed" or kind == "reed")
		var r_cfg := [0.0, 0.0, 140.0 if is_reed else (118.0 if is_bush else 82.0), 14.0 if (is_reed or is_bush) else 10.0, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF]
		var bark_m: ArrayMesh = bundle.get("bark_mesh", null)
		if bark_m != null:
			_spawn_tree_mm(chunk_node, "FloraBark_%s" % bucket_key, bark_m, mats.bark_mat, items, r_cfg)
		var fol_m: ArrayMesh = bundle.get("foliage_mesh", null)
		if fol_m != null:
			_spawn_tree_mm(chunk_node, "FloraLeaves_%s" % bucket_key, fol_m, mats.foliage_mat, items, r_cfg)
		var reed_m: ArrayMesh = bundle.get("reed_mesh", null)
		if reed_m != null:
			_spawn_tree_mm(chunk_node, "FloraReed_%s" % bucket_key, reed_m, _mat_or(mats, "reed_mat", mats.foliage_mat), items, r_cfg)
		var blos_m: ArrayMesh = bundle.get("blossom_mesh", null)
		if blos_m != null:
			_spawn_tree_mm(chunk_node, "FloraBlossom_%s" % bucket_key, blos_m, mats.flora_blossom_mat, items, r_cfg)


static func _get_batch_st_from_map(tier_map: Dictionary, mat: Material) -> SurfaceTool:
	if tier_map.has(mat):
		return tier_map[mat]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	tier_map[mat] = st
	return st


static func build_chunk_tree_multimeshes(chunk_node: Node3D, buckets: Dictionary, mats: MaterialLibrary) -> void:
	const LOD_RANGES := [
		[0.0, 0.0, 28.0, 5.0, GeometryInstance3D.SHADOW_CASTING_SETTING_ON],
		[28.0, 5.0, 72.0, 10.0, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF],
		[72.0, 10.0, 195.0, 20.0, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF],
	]
	for bucket_key in buckets.keys():
		var items: Array = buckets[bucket_key]
		if items.is_empty():
			continue
		var first_item: Dictionary = items[0]
		var sp: String = first_item["species"]
		var var_idx: int = int(first_item["variant"])
		var bundle := TreeGenerator.get_species_bundle(sp, var_idx)
		var bark_lods: Array = bundle["bark_lods"]
		var foliage_lods: Array = bundle["foliage_lods"]

		for lod_idx in range(3):
			var r_cfg: Array = LOD_RANGES[lod_idx]
			_spawn_tree_mm(
				chunk_node,
				"TreesBark_%s_LOD%d" % [bucket_key, lod_idx],
				bark_lods[lod_idx],
				mats.bark_mat,
				items,
				r_cfg
			)
			_spawn_tree_mm(
				chunk_node,
				"TreesFoliage_%s_LOD%d" % [bucket_key, lod_idx],
				foliage_lods[lod_idx],
				mats.foliage_mat,
				items,
				r_cfg
			)


static func _spawn_tree_mm(
	parent: Node3D,
	node_name: String,
	mesh: ArrayMesh,
	mat: Material,
	items: Array,
	r_cfg: Array
) -> void:
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in range(items.size()):
		var item: Dictionary = items[i]
		mm.set_instance_transform(i, item["transform"])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.visibility_range_begin = float(r_cfg[0])
	mmi.visibility_range_begin_margin = float(r_cfg[1])
	mmi.visibility_range_end = float(r_cfg[2])
	mmi.visibility_range_end_margin = float(r_cfg[3])
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mmi.cast_shadow = int(r_cfg[4]) as GeometryInstance3D.ShadowCastingSetting
	parent.add_child(mmi)


static func _build_procedural_tree(root: Node3D, prop: Dictionary, scale_v: float, mats: MaterialLibrary) -> void:
	var species: String = prop.get("species", "cedar_elm")
	var variant: int = int(prop.get("variant", 0))
	var bundle := TreeGenerator.get_species_bundle(species, variant)
	var col_wrap := build_tree_collider(prop)
	col_wrap.position = Vector3.ZERO
	col_wrap.rotation = Vector3.ZERO
	root.add_child(col_wrap)

	var bark_mi := MeshInstance3D.new()
	bark_mi.mesh = bundle["bark_lods"][0]
	bark_mi.material_override = mats.bark_mat
	bark_mi.scale = Vector3.ONE * scale_v
	root.add_child(bark_mi)

	var fol_mi := MeshInstance3D.new()
	fol_mi.mesh = bundle["foliage_lods"][0]
	fol_mi.material_override = mats.foliage_mat
	fol_mi.scale = Vector3.ONE * scale_v
	root.add_child(fol_mi)


static func _build_streetlight(root: Node3D, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.14
	cyl.height = 5.5
	cs.shape = cyl
	cs.position = Vector3(0.0, 2.75, 0.0)
	body.add_child(cs)
	root.add_child(body)

	_add_cyl(root, 0.09, 5.4, Vector3(0, 2.7, 0), mats.dark_metal_mat)
	_add_box(root, Vector3(1.1, 0.10, 0.14), Vector3(0.55, 5.35, 0.0), mats.dark_metal_mat)
	_add_box(root, Vector3(0.48, 0.06, 0.24), Vector3(1.05, 5.28, 0.0), mats.lamp_glow_mat)


static func _build_traffic_signal(root: Node3D, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.16
	cyl.height = 5.8
	cs.shape = cyl
	cs.position = Vector3(0, 2.9, 0)
	body.add_child(cs)
	root.add_child(body)

	_add_cyl(root, 0.13, 5.8, Vector3(0, 2.9, 0), mats.dark_metal_mat)
	_add_box(root, Vector3(3.4, 0.16, 0.16), Vector3(1.6, 5.55, 0), mats.dark_metal_mat)
	# 3-aspect signal housing + dark louvered sun-visors framing TrafficManager's dynamic RGB lens quads
	_add_box(root, Vector3(0.38, 0.96, 0.36), Vector3(2.4, 5.19, 0), mats.dark_metal_mat)
	for vy: float in [5.52, 5.26, 5.00]:
		_add_box(root, Vector3(0.28, 0.04, 0.16), Vector3(2.4, vy, 0.24), mats.dark_metal_mat)
		_add_box(root, Vector3(0.28, 0.04, 0.16), Vector3(2.4, vy, -0.24), mats.dark_metal_mat)


static func _build_transit_shelter(root: Node3D, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	for px in [-1.5, 1.5]:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(0.16, 2.5, 0.16)
		cs.shape = b
		cs.position = Vector3(px, 1.25, -0.55)
		body.add_child(cs)
	var b_col := CollisionShape3D.new()
	var bb := BoxShape3D.new()
	bb.size = Vector3(3.2, 0.25, 1.2)
	b_col.shape = bb
	b_col.position = Vector3(0, 2.52, 0.0)
	body.add_child(b_col)
	root.add_child(body)

	for px in [-1.5, 1.5]:
		_add_box(root, Vector3(0.12, 2.5, 0.12), Vector3(px, 1.25, -0.55), mats.dark_metal_mat)
	_add_box(root, Vector3(3.1, 2.2, 0.06), Vector3(0, 1.2, -0.55), mats.glass_dark_mat)
	_add_box(root, Vector3(3.4, 0.12, 1.45), Vector3(0, 2.55, 0.05), mats.dark_metal_mat)
	# Rooftop solar panel + digital transit arrival board + illuminated route header
	_add_box(root, Vector3(2.9, 0.05, 1.1), Vector3(0, 2.64, 0.05), mats.solar_panel_mat)
	_add_box(root, Vector3(0.12, 1.35, 0.55), Vector3(1.52, 1.45, 0.0), mats.ev_glow_mat)
	_add_box(root, Vector3(1.8, 0.10, 0.45), Vector3(-0.2, 0.48, -0.25), mats.wood_door_mat)
	_add_box(root, Vector3(2.8, 0.24, 0.08), Vector3(0.0, 2.55, 0.78), mats.dark_metal_mat)
	var bus_lbl := Label3D.new()
	bus_lbl.text = "METRO RAPID // BUS"
	bus_lbl.font_size = 56
	bus_lbl.pixel_size = 0.0028
	bus_lbl.modulate = Color(0.75, 0.96, 1.0)
	bus_lbl.outline_size = 6
	bus_lbl.outline_modulate = Color(0.04, 0.06, 0.09)
	bus_lbl.position = Vector3(0.0, 2.55, 0.85)
	root.add_child(bus_lbl)


static func _build_ev_charger(root: Node3D, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.55, 1.85, 0.40)
	cs.shape = box
	cs.position = Vector3(0, 0.92, 0)
	body.add_child(cs)
	root.add_child(body)

	_add_box(root, Vector3(0.50, 1.80, 0.34), Vector3(0, 0.90, 0), mats.light_metal_mat)
	_add_box(root, Vector3(0.54, 0.14, 0.40), Vector3(0, 1.78, 0), mats.dark_metal_mat)
	_add_box(root, Vector3(0.28, 0.52, 0.36), Vector3(0, 1.25, 0), mats.ev_glow_mat)


static func _build_tree(root: Node3D, scale_v: float, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.24 * scale_v
	cyl.height = 2.6 * scale_v
	cs.shape = cyl
	cs.position = Vector3(0, 1.3 * scale_v, 0)
	body.add_child(cs)
	root.add_child(body)

	_add_cyl(root, 0.21 * scale_v, 2.75 * scale_v, Vector3(0, 1.37 * scale_v, 0), mats.bark_mat)

	# Upper primary forked branch stubs reaching into foliage lobes
	for br in [
		[Vector3(0.28, 2.52, 0.20), Vector3(0.45, 0.0, -0.52)],
		[Vector3(-0.26, 2.55, -0.20), Vector3(-0.42, 0.0, 0.48)],
	]:
		var b_mi := MeshInstance3D.new()
		var b_cm := CylinderMesh.new()
		b_cm.top_radius = 0.06 * scale_v
		b_cm.bottom_radius = 0.11 * scale_v
		b_cm.height = 0.95 * scale_v
		b_cm.radial_segments = 8
		b_mi.mesh = b_cm
		b_mi.material_override = mats.bark_mat
		b_mi.position = br[0] * scale_v
		b_mi.rotation = br[1]
		root.add_child(b_mi)

	var canopy := MeshInstance3D.new()
	canopy.mesh = _get_tree_canopy_mesh()
	canopy.material_override = mats.foliage_mat
	canopy.scale = Vector3.ONE * scale_v
	root.add_child(canopy)


static func _get_tree_canopy_mesh() -> ArrayMesh:
	if _tree_canopy_mesh != null:
		return _tree_canopy_mesh

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Distribute crossed alpha-cutout leaf cards across 3 crown lobes around (0, 2.95, 0)
	var lobes := [
		[Vector3(0.0, 3.32, 0.0), 1.08, 18],
		[Vector3(0.62, 2.74, 0.42), 0.74, 10],
		[Vector3(-0.58, 2.80, -0.42), 0.74, 10],
	]
	var golden_angle := 2.39996323
	for lobe_idx in range(lobes.size()):
		var l_center: Vector3 = lobes[lobe_idx][0]
		var l_rad: float = lobes[lobe_idx][1]
		var count: int = lobes[lobe_idx][2]
		for i in range(count):
			var t := (float(i) + 0.5) / float(count)
			var y_dir := 1.0 - 1.85 * t
			var ring_r := sqrt(maxf(0.05, 1.0 - y_dir * y_dir))
			var theta := golden_angle * float(i + lobe_idx * 7)
			var dir := Vector3(cos(theta) * ring_r, y_dir, sin(theta) * ring_r).normalized()
			var card_pos := l_center + dir * (l_rad * 0.74)
			var card_size := lerpf(0.76, 0.94, sin(theta * 3.0) * 0.5 + 0.5)
			var wind_w := clampf(card_pos.distance_to(Vector3(0.0, 2.5, 0.0)) / 1.85, 0.45, 1.0)
			var b1 := Basis(Vector3.UP, theta) * Basis(Vector3.RIGHT, 0.45 * dir.y)
			var b2 := Basis(Vector3.UP, theta + PI * 0.5) * Basis(Vector3.FORWARD, 0.52)
			_emit_foliage_card(st, card_pos, b1, card_size, wind_w)
			_emit_foliage_card(st, card_pos, b2, card_size * 0.94, wind_w)

	_tree_canopy_mesh = st.commit()
	return _tree_canopy_mesh


static func _emit_foliage_card(st: SurfaceTool, center: Vector3, basis: Basis, size: float, wind_weight: float) -> void:
	var hs := size * 0.5
	var right := basis.x * hs
	var up := basis.y * hs
	var n := basis.z.normalized()
	var tl := center - right + up
	var tr := center + right + up
	var bl := center - right - up
	var br := center + right - up
	var col := Color(wind_weight, 1.0, 0.0, 1.0)
	var pts := [tl, tr, bl, tr, br, bl]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in range(6):
		st.set_color(col)
		st.set_uv(uvs[i])
		st.set_normal(n)
		st.add_vertex(pts[i])


static func _build_bench(root: Node3D, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(1.8, 0.85, 0.65)
	cs.shape = b
	cs.position = Vector3(0, 0.42, 0)
	body.add_child(cs)
	root.add_child(body)

	_add_box(root, Vector3(1.75, 0.09, 0.52), Vector3(0, 0.46, 0), mats.wood_door_mat)
	_add_box(root, Vector3(1.75, 0.42, 0.08), Vector3(0, 0.72, -0.22), mats.wood_door_mat)
	for lx in [-0.72, 0.72]:
		_add_box(root, Vector3(0.08, 0.46, 0.48), Vector3(lx, 0.23, 0), mats.dark_metal_mat)


static func _build_trashcan(root: Node3D, variant: int, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	if variant == 0:
		# Twin-stream municipal waste + recycling kiosk
		var b := BoxShape3D.new()
		b.size = Vector3(0.92, 1.04, 0.48)
		cs.shape = b
		cs.position = Vector3(0.0, 0.52, 0.0)
		body.add_child(cs)
		root.add_child(body)

		var recycle_mat := mats.get_accent_material(Color(0.14, 0.46, 0.72))
		_add_box(root, Vector3(0.88, 0.06, 0.44), Vector3(0.0, 0.03, 0.0), mats.dark_metal_mat)
		_add_box(root, Vector3(0.39, 0.76, 0.40), Vector3(-0.22, 0.44, 0.0), mats.dark_metal_mat)
		_add_box(root, Vector3(0.39, 0.76, 0.40), Vector3(0.22, 0.44, 0.0), mats.dark_metal_mat)
		_add_box(root, Vector3(0.32, 0.14, 0.02), Vector3(-0.22, 0.62, 0.205), mats.light_metal_mat)
		_add_box(root, Vector3(0.32, 0.14, 0.02), Vector3(0.22, 0.62, 0.205), recycle_mat)
		_add_box(root, Vector3(0.92, 0.08, 0.46), Vector3(0.0, 0.99, 0.0), mats.light_metal_mat)
		for px: float in [-0.41, 0.0, 0.41]:
			_add_box(root, Vector3(0.05, 0.16, 0.36), Vector3(px, 0.89, 0.0), mats.dark_metal_mat)
		_add_box(root, Vector3(0.56, 0.03, 0.02), Vector3(0.0, 0.99, 0.235), mats.ev_glow_mat)
	else:
		# Cylindrical hooded municipal steel litter receptacle
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.28
		cyl.height = 1.02
		cs.shape = cyl
		cs.position = Vector3(0.0, 0.51, 0.0)
		body.add_child(cs)
		root.add_child(body)

		_add_cyl(root, 0.26, 0.06, Vector3(0.0, 0.03, 0.0), mats.dark_metal_mat)
		_add_cyl(root, 0.24, 0.72, Vector3(0.0, 0.42, 0.0), mats.dark_metal_mat)
		_add_cyl(root, 0.248, 0.08, Vector3(0.0, 0.72, 0.0), mats.get_accent_material(Color(0.18, 0.52, 0.32)))
		for ax: float in [-0.21, 0.21]:
			_add_box(root, Vector3(0.04, 0.20, 0.05), Vector3(ax, 0.84, 0.0), mats.light_metal_mat)
		_add_cyl(root, 0.26, 0.12, Vector3(0.0, 0.96, 0.0), mats.light_metal_mat)


static func _build_street_sign(root: Node3D, prop: Dictionary, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.09
	cyl.height = 3.1
	cs.shape = cyl
	cs.position = Vector3(0.0, 1.55, 0.0)
	body.add_child(cs)
	root.add_child(body)

	_add_cyl(root, 0.055, 3.15, Vector3(0.0, 1.575, 0.0), mats.light_metal_mat)
	_add_cyl(root, 0.075, 0.10, Vector3(0.0, 3.18, 0.0), mats.dark_metal_mat)

	var label_a: String = str(prop.get("label_a", "MAIN ST"))
	var label_b: String = str(prop.get("label_b", ""))
	_add_sign_blade(root, label_a, Vector3(0.0, 2.98, 0.0), 0.0, mats)
	if label_b != "":
		_add_sign_blade(root, label_b, Vector3(0.0, 2.70, 0.0), PI * 0.5, mats)


static func _add_sign_blade(root: Node3D, label_text: String, offset: Vector3, yaw: float, mats: MaterialLibrary) -> void:
	var holder := Node3D.new()
	holder.position = offset
	holder.rotation.y = yaw
	if root.has_meta("_prop_batch"):
		holder.set_meta("_prop_batch", root.get_meta("_prop_batch"))
		holder.set_meta("_prop_tier", root.get_meta("_prop_tier"))
		var parent_xf: Transform3D = root.get_meta("_prop_xform")
		holder.set_meta("_prop_xform", parent_xf * Transform3D(Basis(Vector3.UP, yaw), offset))
	root.add_child(holder)

	var blade_w := clampf(float(label_text.length()) * 0.115 + 0.35, 1.05, 1.85)
	_add_box(holder, Vector3(blade_w, 0.22, 0.045), Vector3.ZERO, mats.street_sign_green_mat)
	var px_sz := clampf((blade_w - 0.18) / maxf(float(label_text.length()) * 34.0, 1.0), 0.0018, 0.0032)
	for side_z in [0.042, -0.042]:
		var lbl := Label3D.new()
		lbl.text = label_text.to_upper()
		lbl.font_size = 56
		lbl.pixel_size = px_sz
		lbl.modulate = Color(0.98, 0.99, 1.0)
		lbl.outline_size = 6
		lbl.outline_modulate = Color(0.02, 0.10, 0.04)
		lbl.position = Vector3(0.0, 0.0, side_z)
		if side_z < 0.0:
			lbl.rotation.y = PI
		holder.add_child(lbl)


static func _build_fire_hydrant(root: Node3D, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.22
	cyl.height = 0.85
	cs.shape = cyl
	cs.position = Vector3(0.0, 0.425, 0.0)
	body.add_child(cs)
	root.add_child(body)

	_add_cyl(root, 0.18, 0.08, Vector3(0.0, 0.04, 0.0), mats.hydrant_red_mat)
	_add_cyl(root, 0.14, 0.56, Vector3(0.0, 0.36, 0.0), mats.hydrant_red_mat)
	_add_cyl(root, 0.17, 0.10, Vector3(0.0, 0.66, 0.0), mats.hydrant_red_mat)
	_add_cyl(root, 0.07, 0.10, Vector3(0.0, 0.76, 0.0), mats.light_metal_mat)
	for side_x in [-0.15, 0.15]:
		_add_box(root, Vector3(0.10, 0.12, 0.12), Vector3(side_x, 0.50, 0.0), mats.light_metal_mat)
	_add_box(root, Vector3(0.14, 0.14, 0.12), Vector3(0.0, 0.46, 0.15), mats.light_metal_mat)


static func _build_mailbox(root: Node3D, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.58, 1.15, 0.58)
	cs.shape = box
	cs.position = Vector3(0.0, 0.575, 0.0)
	body.add_child(cs)
	root.add_child(body)

	for lx in [-0.21, 0.21]:
		for lz in [-0.21, 0.21]:
			_add_box(root, Vector3(0.07, 0.16, 0.07), Vector3(lx, 0.08, lz), mats.dark_metal_mat)
	_add_box(root, Vector3(0.52, 0.76, 0.52), Vector3(0.0, 0.54, 0.0), mats.mailbox_blue_mat)
	_add_box(root, Vector3(0.54, 0.22, 0.54), Vector3(0.0, 1.00, 0.0), mats.mailbox_blue_mat)
	_add_box(root, Vector3(0.42, 0.14, 0.10), Vector3(0.0, 0.88, 0.27), mats.light_metal_mat)
	var lbl := Label3D.new()
	lbl.text = "US MAIL"
	lbl.font_size = 44
	lbl.pixel_size = 0.0024
	lbl.modulate = Color(0.96, 0.98, 1.0)
	lbl.position = Vector3(0.0, 0.62, 0.285)
	root.add_child(lbl)


static func _build_utility_box(root: Node3D, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.15, 1.25, 0.68)
	cs.shape = box
	cs.position = Vector3(0.0, 0.625, 0.0)
	body.add_child(cs)
	root.add_child(body)

	var util_mat := mats.get_accent_material(Color(0.24, 0.34, 0.28))
	_add_box(root, Vector3(1.18, 0.14, 0.70), Vector3(0.0, 0.07, 0.0), mats.bridge_concrete_mat)
	_add_box(root, Vector3(1.06, 1.08, 0.58), Vector3(0.0, 0.68, 0.0), util_mat)
	_add_box(root, Vector3(1.12, 0.07, 0.64), Vector3(0.0, 1.24, 0.0), mats.dark_metal_mat)
	for lx in [-0.26, 0.26]:
		_add_box(root, Vector3(0.36, 0.58, 0.03), Vector3(lx, 0.70, 0.295), mats.dark_metal_mat)


static func _build_sidewalk_bench(root: Node3D, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.90, 0.86, 0.64)
	cs.shape = box
	cs.position = Vector3(0.0, 0.43, 0.0)
	body.add_child(cs)
	root.add_child(body)

	for lx in [-0.82, 0.0, 0.82]:
		_add_box(root, Vector3(0.06, 0.46, 0.52), Vector3(lx, 0.23, 0.0), mats.dark_metal_mat)
		_add_box(root, Vector3(0.06, 0.24, 0.50), Vector3(lx, 0.58, 0.0), mats.dark_metal_mat)
	for sz in [-0.14, 0.0, 0.14]:
		_add_box(root, Vector3(1.86, 0.06, 0.11), Vector3(0.0, 0.46, sz), mats.wood_door_mat)
	for sy in [0.64, 0.79]:
		_add_box(root, Vector3(1.86, 0.11, 0.06), Vector3(0.0, sy, -0.24), mats.wood_door_mat)


static func _build_planter_box(root: Node3D, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.38, 0.90, 1.38)
	cs.shape = box
	cs.position = Vector3(0.0, 0.45, 0.0)
	body.add_child(cs)
	root.add_child(body)

	_add_box(root, Vector3(1.34, 0.56, 1.34), Vector3(0.0, 0.28, 0.0), mats.bridge_concrete_mat)
	_add_box(root, Vector3(1.42, 0.10, 1.42), Vector3(0.0, 0.56, 0.0), mats.sidewalk_mat)
	_add_box(root, Vector3(1.16, 0.12, 1.16), Vector3(0.0, 0.58, 0.0), mats.soil_mulch_mat)


static func _build_bike_rack(root: Node3D, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.80, 0.82, 0.65)
	cs.shape = box
	cs.position = Vector3(0.0, 0.41, 0.0)
	body.add_child(cs)
	root.add_child(body)

	_add_box(root, Vector3(1.75, 0.05, 0.56), Vector3(0.0, 0.025, 0.0), mats.dark_metal_mat)
	for hx in [-0.66, 0.0, 0.66]:
		for hz in [-0.22, 0.22]:
			_add_cyl(root, 0.032, 0.76, Vector3(hx, 0.40, hz), mats.light_metal_mat)
		_add_box(root, Vector3(0.06, 0.06, 0.50), Vector3(hx, 0.78, 0.0), mats.light_metal_mat)


static func _build_city_kiosk(root: Node3D, prop: Dictionary, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.06, 2.38, 0.30)
	cs.shape = box
	cs.position = Vector3(0.0, 1.19, 0.0)
	body.add_child(cs)
	root.add_child(body)

	_add_box(root, Vector3(1.04, 0.16, 0.34), Vector3(0.0, 0.08, 0.0), mats.dark_metal_mat)
	_add_box(root, Vector3(1.00, 2.22, 0.24), Vector3(0.0, 1.24, 0.0), mats.dark_metal_mat)
	_add_box(root, Vector3(0.84, 1.48, 0.27), Vector3(0.0, 1.32, 0.0), mats.kiosk_display_mat)

	var street_str: String = str(prop.get("label_a", "METRO CENTER"))
	for side_z in [0.165, -0.165]:
		var hdr := Label3D.new()
		hdr.text = "CITY MAP & TRANSIT"
		hdr.font_size = 56
		hdr.pixel_size = 0.0024
		hdr.modulate = Color(0.70, 0.98, 0.92)
		hdr.outline_size = 8
		hdr.outline_modulate = Color(0.03, 0.05, 0.08)
		hdr.position = Vector3(0.0, 1.92, side_z)
		if side_z < 0.0:
			hdr.rotation.y = PI
		root.add_child(hdr)

		var sub := Label3D.new()
		sub.text = street_str
		sub.font_size = 44
		sub.pixel_size = clampf(0.76 / maxf(float(street_str.length()) * 32.0, 1.0), 0.0016, 0.0024)
		sub.modulate = Color(0.96, 0.98, 1.0)
		sub.outline_size = 6
		sub.outline_modulate = Color(0.03, 0.05, 0.08)
		sub.position = Vector3(0.0, 1.68, side_z)
		if side_z < 0.0:
			sub.rotation.y = PI
		root.add_child(sub)


static func _build_billboard(root: Node3D, prop: Dictionary, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.28
	cyl.height = 5.2
	cs.shape = cyl
	cs.position = Vector3(0.0, 2.6, 0.0)
	body.add_child(cs)
	root.add_child(body)

	# Heavy steel pylon + concrete footing
	_add_cyl(root, 0.34, 0.30, Vector3(0.0, 0.15, 0.0), mats.bridge_concrete_mat)
	_add_cyl(root, 0.22, 4.9, Vector3(0.0, 2.45, 0.0), mats.dark_metal_mat)
	# Frame housing at y = 5.85m
	_add_box(root, Vector3(4.95, 2.55, 0.32), Vector3(0.0, 5.85, 0.0), mats.dark_metal_mat)
	_add_box(root, Vector3(4.65, 2.25, 0.36), Vector3(0.0, 5.85, 0.0), mats.billboard_display_mat)

	var headline: String = str(prop.get("label_a", "MERIDIAN FIBER"))
	var subline: String = str(prop.get("label_b", "10G SYMMETRIC METRO"))
	var h_px := clampf(4.2 / maxf(float(headline.length()) * 58.0, 1.0), 0.0048, 0.0072)
	var s_px := clampf(4.1 / maxf(float(subline.length()) * 36.0, 1.0), 0.0032, 0.0046)
	for side_z in [0.23, -0.23]:
		var lbl := Label3D.new()
		lbl.text = headline
		lbl.font_size = 96
		lbl.pixel_size = h_px
		lbl.modulate = Color(0.98, 0.99, 1.0)
		lbl.outline_size = 14
		lbl.outline_modulate = Color(0.03, 0.05, 0.09)
		lbl.position = Vector3(0.0, 6.18, side_z)
		if side_z < 0.0:
			lbl.rotation.y = PI
		root.add_child(lbl)

		var tag := Label3D.new()
		tag.text = subline
		tag.font_size = 64
		tag.pixel_size = s_px
		tag.modulate = Color(0.76, 0.95, 1.0)
		tag.outline_size = 10
		tag.outline_modulate = Color(0.03, 0.05, 0.09)
		tag.position = Vector3(0.0, 5.45, side_z)
		if side_z < 0.0:
			tag.rotation.y = PI
		root.add_child(tag)


static func _build_park_gazebo(root: Node3D, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var deck_cs := CollisionShape3D.new()
	var deck_b := BoxShape3D.new()
	deck_b.size = Vector3(4.2, 0.24, 4.2)
	deck_cs.shape = deck_b
	deck_cs.position = Vector3(0.0, 0.12, 0.0)
	body.add_child(deck_cs)
	for px in [-1.8, 1.8]:
		for pz in [-1.8, 1.8]:
			var post_cs := CollisionShape3D.new()
			var post_b := BoxShape3D.new()
			post_b.size = Vector3(0.22, 2.9, 0.22)
			post_cs.shape = post_b
			post_cs.position = Vector3(px, 1.45, pz)
			body.add_child(post_cs)
	root.add_child(body)

	# Raised stone deck + 4 timber columns (walkable open pavilion)
	_add_box(root, Vector3(4.2, 0.24, 4.2), Vector3(0.0, 0.12, 0.0), mats.bridge_concrete_mat)
	for px in [-1.8, 1.8]:
		for pz in [-1.8, 1.8]:
			_add_box(root, Vector3(0.18, 2.85, 0.18), Vector3(px, 1.54, pz), mats.wood_door_mat)
	# Perimeter eave beams + stepped pyramidal park roof + hanging lantern
	_add_box(root, Vector3(4.5, 0.20, 4.5), Vector3(0.0, 3.02, 0.0), mats.dark_metal_mat)
	_add_box(root, Vector3(3.3, 0.36, 3.3), Vector3(0.0, 3.30, 0.0), mats.roof_shingle_mat)
	_add_box(root, Vector3(1.8, 0.34, 1.8), Vector3(0.0, 3.65, 0.0), mats.roof_shingle_mat)
	_add_box(root, Vector3(0.32, 0.22, 0.32), Vector3(0.0, 2.80, 0.0), mats.lamp_glow_mat)
	# Two interior timber benches along opposite sides
	_add_box(root, Vector3(2.4, 0.08, 0.44), Vector3(0.0, 0.56, -1.45), mats.wood_door_mat)
	_add_box(root, Vector3(2.4, 0.08, 0.44), Vector3(0.0, 0.56, 1.45), mats.wood_door_mat)


static func _build_path_bollard(root: Node3D, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.14
	cyl.height = 0.92
	cs.shape = cyl
	cs.position = Vector3(0.0, 0.46, 0.0)
	body.add_child(cs)
	root.add_child(body)

	_add_cyl(root, 0.12, 0.08, Vector3(0.0, 0.04, 0.0), mats.bridge_concrete_mat)
	_add_cyl(root, 0.085, 0.66, Vector3(0.0, 0.40, 0.0), mats.dark_metal_mat)
	_add_cyl(root, 0.075, 0.15, Vector3(0.0, 0.78, 0.0), mats.bollard_glow_mat)
	_add_cyl(root, 0.11, 0.07, Vector3(0.0, 0.88, 0.0), mats.dark_metal_mat)


static func _add_box_xf(parent: Node3D, local_pos: Vector3, local_basis: Basis, size: Vector3, mat: Material) -> void:
	if parent.has_meta("_prop_batch"):
		var st := _get_batch_st(parent, mat)
		var xf: Transform3D = parent.get_meta("_prop_xform")
		_emit_batch_box(st, xf * local_pos, xf.basis * local_basis, size)
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = Transform3D(local_basis, local_pos)
	parent.add_child(mi)


static func _emit_fountain_quad(st: SurfaceTool, xf: Transform3D, tl: Vector3, tr: Vector3, bl: Vector3, br: Vector3, desired_n: Vector3, col: Color) -> void:
	var p_tl := xf * tl
	var p_tr := xf * tr
	var p_bl := xf * bl
	var p_br := xf * br
	var w_n := (xf.basis * desired_n).normalized()
	var n_test := (p_bl - p_tl).cross(p_tr - p_tl)
	var pts := [p_tl, p_tr, p_bl, p_tr, p_br, p_bl] if n_test.dot(w_n) >= 0.0 else [p_tl, p_bl, p_tr, p_tr, p_bl, p_br]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in range(6):
		st.set_color(col)
		st.set_uv(uvs[i])
		st.set_normal(w_n)
		st.add_vertex(pts[i])


static func _emit_fountain_disc(st: SurfaceTool, xf: Transform3D, radius: float, y: float, segs: int) -> void:
	var c := xf * Vector3(0.0, y, 0.0)
	var w_n := (xf.basis * Vector3.UP).normalized()
	for i in range(segs):
		var a0 := float(i) * TAU / float(segs)
		var a1 := float(i + 1) * TAU / float(segs)
		var p0 := xf * Vector3(cos(a0) * radius, y, sin(a0) * radius)
		var p1 := xf * Vector3(cos(a1) * radius, y, sin(a1) * radius)
		var n_test := (p0 - c).cross(p1 - c)
		var tri := [c, p0, p1] if n_test.dot(w_n) >= 0.0 else [c, p1, p0]
		for p in tri:
			st.set_color(Color.BLACK)
			st.set_uv(Vector2(0.5, 0.5))
			st.set_normal(w_n)
			st.add_vertex(p)


static func _build_park_fountain(root: Node3D, mats: MaterialLibrary) -> void:
	# Walk-proof basin rim and central multi-tier limestone spire colliders
	var body := StaticBody3D.new()
	var cs_basin := CollisionShape3D.new()
	var cyl_basin := CylinderShape3D.new()
	cyl_basin.radius = 2.68
	cyl_basin.height = 0.72
	cs_basin.shape = cyl_basin
	cs_basin.position = Vector3(0.0, 0.36, 0.0)
	body.add_child(cs_basin)
	var cs_core := CollisionShape3D.new()
	var cyl_core := CylinderShape3D.new()
	cyl_core.radius = 0.78
	cyl_core.height = 2.45
	cs_core.shape = cyl_core
	cs_core.position = Vector3(0.0, 1.25, 0.0)
	body.add_child(cs_core)
	root.add_child(body)

	# Stepped stone apron plinth + dark underwater pool liner
	_add_cyl(root, 3.05, 0.24, Vector3(0.0, 0.0, 0.0), mats.sidewalk_mat)
	_add_cyl(root, 2.46, 0.06, Vector3(0.0, 0.14, 0.0), mats.asphalt_mat)

	# 12-segment sculpted limestone outer basin coping wall
	const WALL_SEGS := 12
	for wi in range(WALL_SEGS):
		var ang := (float(wi) + 0.5) * TAU / float(WALL_SEGS)
		var pos := Vector3(cos(ang) * 2.52, 0.41, sin(ang) * 2.52)
		_add_box_xf(root, pos, Basis(Vector3.UP, -ang + PI * 0.5), Vector3(1.38, 0.58, 0.28), mats.limestone_mat)
		_add_box_xf(root, Vector3(cos(ang) * 2.54, 0.72, sin(ang) * 2.54), Basis(Vector3.UP, -ang + PI * 0.5), Vector3(1.42, 0.09, 0.34), mats.sidewalk_mat)

	# Two-tier sculpted limestone centerpiece spire + wide water-catching bowls
	_add_cyl(root, 0.68, 0.92, Vector3(0.0, 0.62, 0.0), mats.limestone_mat)
	_add_cyl(root, 1.38, 0.18, Vector3(0.0, 1.14, 0.0), mats.limestone_mat)
	_add_cyl(root, 1.32, 0.14, Vector3(0.0, 1.24, 0.0), mats.sidewalk_mat)
	_add_cyl(root, 0.36, 0.78, Vector3(0.0, 1.68, 0.0), mats.limestone_mat)
	_add_cyl(root, 0.76, 0.16, Vector3(0.0, 2.12, 0.0), mats.limestone_mat)
	_add_cyl(root, 0.14, 0.28, Vector3(0.0, 2.34, 0.0), mats.dark_metal_mat)

	# Animated basin water discs (COLOR.r = 0) and vertical jet/cascade plumes (COLOR.r = 1)
	var is_batched := root.has_meta("_prop_batch")
	var xf: Transform3D = root.get_meta("_prop_xform") if is_batched else Transform3D.IDENTITY
	var w_st: SurfaceTool
	if is_batched:
		w_st = _get_batch_st(root, mats.fountain_water_mat)
	else:
		w_st = SurfaceTool.new()
		w_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	_emit_fountain_disc(w_st, xf, 2.40, 0.56, 20)
	_emit_fountain_disc(w_st, xf, 1.22, 1.30, 14)
	_emit_fountain_disc(w_st, xf, 0.66, 2.20, 10)

	# Crossed top finial jet plume
	_emit_fountain_quad(w_st, xf, Vector3(-0.28, 3.45, 0.0), Vector3(0.28, 3.45, 0.0), Vector3(-0.14, 2.28, 0.0), Vector3(0.14, 2.28, 0.0), Vector3(0.0, 0.0, 1.0), Color.RED)
	_emit_fountain_quad(w_st, xf, Vector3(0.0, 3.45, -0.28), Vector3(0.0, 3.45, 0.28), Vector3(0.0, 2.28, -0.14), Vector3(0.0, 2.28, 0.14), Vector3(1.0, 0.0, 0.0), Color.RED)

	# 4 radial spilling water curtains between tiers
	for ci in range(4):
		var c_ang := float(ci) * PI * 0.5 + PI * 0.25
		var rad_dir := Vector3(cos(c_ang), 0.0, sin(c_ang))
		var tan_dir := Vector3(-sin(c_ang), 0.0, cos(c_ang))
		var t_hi := rad_dir * 0.66 + Vector3(0.0, 2.18, 0.0)
		var b_hi := rad_dir * 0.88 + Vector3(0.0, 1.28, 0.0)
		_emit_fountain_quad(w_st, xf, t_hi - tan_dir * 0.18, t_hi + tan_dir * 0.18, b_hi - tan_dir * 0.24, b_hi + tan_dir * 0.24, rad_dir, Color.RED)
		var t_lo := rad_dir * 1.28 + Vector3(0.0, 1.24, 0.0)
		var b_lo := rad_dir * 1.56 + Vector3(0.0, 0.54, 0.0)
		_emit_fountain_quad(w_st, xf, t_lo - tan_dir * 0.24, t_lo + tan_dir * 0.24, b_lo - tan_dir * 0.34, b_lo + tan_dir * 0.34, rad_dir, Color.RED)

	if not is_batched:
		var w_mesh := w_st.commit()
		if w_mesh != null and w_mesh.get_surface_count() > 0:
			var w_mi := MeshInstance3D.new()
			w_mi.mesh = w_mesh
			w_mi.material_override = mats.fountain_water_mat
			w_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(w_mi)


static func _build_cafe_seating(root: Node3D, variant: int, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.15, 0.96, 1.15)
	cs.shape = box
	cs.position = Vector3(0.0, 0.48, 0.0)
	body.add_child(cs)
	root.add_child(body)

	# Compact concrete cafe patio pad + cast-iron pedestal + warm cedar tabletop
	_add_box(root, Vector3(1.95, 0.08, 1.32), Vector3(0.0, -0.02, 0.0), mats.sidewalk_mat)
	_add_cyl(root, 0.28, 0.04, Vector3(0.0, 0.04, 0.0), mats.dark_metal_mat)
	_add_cyl(root, 0.045, 0.70, Vector3(0.0, 0.38, 0.0), mats.dark_metal_mat)
	_add_cyl(root, 0.46, 0.045, Vector3(0.0, 0.74, 0.0), mats.wood_cedar_mat)

	# Two facing cafe bistro chairs
	for cx: float in [-0.70, 0.70]:
		_add_box(root, Vector3(0.42, 0.05, 0.42), Vector3(cx, 0.45, 0.0), mats.wood_cedar_mat)
		_add_box(root, Vector3(0.05, 0.44, 0.40), Vector3(cx + signf(cx) * 0.20, 0.68, 0.0), mats.wood_cedar_mat)
		for lx in [-0.16, 0.16]:
			for lz in [-0.16, 0.16]:
				_add_box(root, Vector3(0.04, 0.44, 0.04), Vector3(cx + lx, 0.22, lz), mats.dark_metal_mat)

	# Tall hardwood market umbrella pole + stepped octagonal fabric canopy
	_add_cyl(root, 0.032, 2.38, Vector3(0.0, 1.24, 0.0), mats.wood_door_mat)
	var canopy_mat: Material = mats.umbrella_crimson_mat
	if variant % 3 == 1:
		canopy_mat = mats.medical_teal_mat
	elif variant % 3 == 2:
		canopy_mat = mats.mailbox_blue_mat
	_add_cyl(root, 1.18, 0.18, Vector3(0.0, 2.18, 0.0), canopy_mat)
	_add_cyl(root, 0.72, 0.14, Vector3(0.0, 2.32, 0.0), canopy_mat)
	_add_cyl(root, 0.12, 0.12, Vector3(0.0, 2.43, 0.0), mats.wood_door_mat)


static func _build_a_frame_sign(root: Node3D, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.58, 0.86, 0.44)
	cs.shape = box
	cs.position = Vector3(0.0, 0.43, 0.0)
	body.add_child(cs)
	root.add_child(body)

	var rot_f := Basis(Vector3.RIGHT, 0.20)
	var rot_b := Basis(Vector3.RIGHT, -0.20)
	_add_box_xf(root, Vector3(0.0, 0.44, 0.11), rot_f, Vector3(0.56, 0.86, 0.04), mats.wood_cedar_mat)
	_add_box_xf(root, Vector3(0.0, 0.46, 0.125), rot_f, Vector3(0.46, 0.66, 0.03), mats.asphalt_mat)
	_add_box_xf(root, Vector3(0.0, 0.64, 0.135), rot_f, Vector3(0.36, 0.05, 0.02), mats.marking_white_mat)
	_add_box_xf(root, Vector3(0.0, 0.44, -0.11), rot_b, Vector3(0.56, 0.86, 0.04), mats.wood_cedar_mat)
	_add_box_xf(root, Vector3(0.0, 0.46, -0.125), rot_b, Vector3(0.46, 0.66, 0.03), mats.asphalt_mat)
	_add_box_xf(root, Vector3(0.0, 0.64, -0.135), rot_b, Vector3(0.36, 0.05, 0.02), mats.marking_white_mat)


static func _build_crosswalk_button(root: Node3D, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.14
	cyl.height = 1.24
	cs.shape = cyl
	cs.position = Vector3(0.0, 0.62, 0.0)
	body.add_child(cs)
	root.add_child(body)

	_add_cyl(root, 0.11, 0.06, Vector3(0.0, 0.03, 0.0), mats.elevator_steel_mat)
	_add_cyl(root, 0.048, 1.18, Vector3(0.0, 0.62, 0.0), mats.dark_metal_mat)
	_add_box(root, Vector3(0.15, 0.24, 0.15), Vector3(0.0, 1.04, 0.04), mats.ada_tactile_mat)
	_add_box(root, Vector3(0.11, 0.16, 0.04), Vector3(0.0, 1.04, 0.11), mats.elevator_steel_mat)
	_add_cyl(root, 0.028, 0.03, Vector3(0.0, 1.03, 0.13), mats.elevator_steel_mat)
	_add_box(root, Vector3(0.16, 0.18, 0.03), Vector3(0.0, 1.26, 0.04), mats.elevator_steel_mat)


static func _build_parcel_locker(root: Node3D, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.42, 2.05, 0.64)
	cs.shape = box
	cs.position = Vector3(0.0, 1.02, 0.0)
	body.add_child(cs)
	root.add_child(body)

	# Plinth, brushed-steel locker bank cabinet, rain canopy hood, and glowing parcel terminal
	_add_box(root, Vector3(2.40, 0.10, 0.62), Vector3(0.0, 0.05, 0.0), mats.sidewalk_mat)
	_add_box(root, Vector3(2.36, 1.92, 0.56), Vector3(0.0, 1.04, 0.0), mats.elevator_steel_mat)
	_add_box(root, Vector3(2.48, 0.10, 0.76), Vector3(0.0, 2.02, 0.06), mats.dark_metal_mat)
	_add_box(root, Vector3(0.32, 0.52, 0.05), Vector3(0.0, 1.24, 0.28), mats.glass_dark_mat)
	_add_box(root, Vector3(0.36, 0.06, 0.06), Vector3(0.0, 1.54, 0.29), mats.bollard_glow_mat)
	for lx: float in [-0.78, -0.38, 0.38, 0.78]:
		_add_box(root, Vector3(0.025, 1.84, 0.03), Vector3(lx, 1.04, 0.28), mats.dark_metal_mat)
	for ly: float in [0.46, 0.92, 1.38, 1.72]:
		_add_box(root, Vector3(2.30, 0.025, 0.03), Vector3(0.0, ly, 0.28), mats.dark_metal_mat)


static func _build_sport_court(root: Node3D, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs_floor := CollisionShape3D.new()
	var box_floor := BoxShape3D.new()
	box_floor.size = Vector3(11.8, 0.20, 17.8)
	cs_floor.shape = box_floor
	cs_floor.position = Vector3(0.0, 0.06, 0.0)
	body.add_child(cs_floor)
	for gz: float in [-8.32, 8.32]:
		var cs_post := CollisionShape3D.new()
		var box_post := BoxShape3D.new()
		box_post.size = Vector3(0.28, 3.60, 0.28)
		cs_post.shape = box_post
		cs_post.position = Vector3(0.0, 1.80, gz)
		body.add_child(cs_post)
	root.add_child(body)

	# Concrete retaining plinth extending deeply into slope so no corner ever floats or gets buried
	_add_box(root, Vector3(11.8, 1.65, 17.8), Vector3(0.0, -0.665, 0.0), mats.bridge_concrete_mat)
	_add_box(root, Vector3(11.1, 0.04, 17.1), Vector3(0.0, 0.165, 0.0), mats.court_teal_mat)
	_add_box(root, Vector3(9.4, 0.04, 15.2), Vector3(0.0, 0.185, 0.0), mats.court_clay_mat)

	# Crisp white boundary lines, midcourt stripe, key boxes, and free-throw caps
	var line_y := 0.212
	_add_box(root, Vector3(9.44, 0.02, 0.10), Vector3(0.0, line_y, -7.56), mats.marking_white_mat)
	_add_box(root, Vector3(9.44, 0.02, 0.10), Vector3(0.0, line_y, 7.56), mats.marking_white_mat)
	_add_box(root, Vector3(0.10, 0.02, 15.20), Vector3(-4.67, line_y, 0.0), mats.marking_white_mat)
	_add_box(root, Vector3(0.10, 0.02, 15.20), Vector3(4.67, line_y, 0.0), mats.marking_white_mat)
	_add_box(root, Vector3(9.44, 0.02, 0.10), Vector3(0.0, line_y, 0.0), mats.marking_white_mat)
	_add_cyl(root, 1.35, 0.02, Vector3(0.0, line_y, 0.0), mats.court_teal_mat)
	_add_cyl(root, 1.44, 0.015, Vector3(0.0, line_y - 0.004, 0.0), mats.marking_white_mat)

	for side_z: float in [-1.0, 1.0]:
		var key_z: float = side_z * 5.80
		_add_box(root, Vector3(2.80, 0.03, 3.55), Vector3(0.0, 0.195, key_z), mats.court_teal_mat)
		_add_box(root, Vector3(2.90, 0.02, 0.09), Vector3(0.0, line_y, side_z * 4.02), mats.marking_white_mat)
		_add_box(root, Vector3(0.09, 0.02, 3.58), Vector3(-1.40, line_y, key_z), mats.marking_white_mat)
		_add_box(root, Vector3(0.09, 0.02, 3.58), Vector3(1.40, line_y, key_z), mats.marking_white_mat)

		# Heavy gooseneck basketball hoop stanchion + tempered glass backboard + rim/net
		var post_z: float = side_z * 8.32
		var board_z: float = side_z * 7.36
		var rim_z: float = side_z * 7.04
		_add_box(root, Vector3(0.20, 3.45, 0.20), Vector3(0.0, 1.82, post_z), mats.dark_metal_mat)
		_add_box(root, Vector3(0.16, 0.16, 1.05), Vector3(0.0, 3.42, (post_z + board_z) * 0.5), mats.dark_metal_mat)
		_add_box(root, Vector3(1.66, 1.06, 0.06), Vector3(0.0, 3.38, board_z), mats.clear_glass_mat)
		_add_box(root, Vector3(1.72, 0.07, 0.08), Vector3(0.0, 3.92, board_z), mats.marking_white_mat)
		_add_box(root, Vector3(1.72, 0.07, 0.08), Vector3(0.0, 2.84, board_z), mats.marking_white_mat)
		_add_box(root, Vector3(0.07, 1.08, 0.08), Vector3(-0.83, 3.38, board_z), mats.marking_white_mat)
		_add_box(root, Vector3(0.07, 1.08, 0.08), Vector3(0.83, 3.38, board_z), mats.marking_white_mat)
		_add_cyl(root, 0.26, 0.05, Vector3(0.0, 3.04, rim_z), mats.umbrella_crimson_mat)
		_add_cyl(root, 0.19, 0.34, Vector3(0.0, 2.84, rim_z), mats.marking_white_mat)

	# Player team bench along sideline
	for bz: float in [-2.6, 2.6]:
		_add_box(root, Vector3(0.46, 0.08, 2.20), Vector3(-5.32, 0.54, bz), mats.wood_cedar_mat)
		_add_box(root, Vector3(0.36, 0.38, 0.12), Vector3(-5.32, 0.32, bz - 0.85), mats.dark_metal_mat)
		_add_box(root, Vector3(0.36, 0.38, 0.12), Vector3(-5.32, 0.32, bz + 0.85), mats.dark_metal_mat)


static func _build_parked_ev(root: Node3D, variant: int, mats: MaterialLibrary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(1.85, 1.42, 4.35)
	cs.shape = b
	cs.position = Vector3(0, 0.78, 0)
	body.add_child(cs)
	root.add_child(body)

	var car_mat := mats.get_car_material(variant)
	var wheel_basis_local := Basis(Vector3.BACK, PI * 0.5)
	# Sculpted parked EV fastback sedan: lower chassis pan, tapered main body tub, sloped hood & rear deck
	_add_box(root, Vector3(1.74, 0.16, 4.30), Vector3(0.0, 0.28, 0.0), mats.dark_metal_mat)
	_add_tapered_box(root, Vector3(0.0, 0.61, -0.03), Vector3(1.86, 0.48, 4.02), Vector2(1.74, 3.80), car_mat)
	_add_tapered_box(root, Vector3(0.0, 0.59, 1.56), Vector3(1.78, 0.44, 1.22), Vector2(1.62, 0.98), car_mat)
	_add_tapered_box(root, Vector3(0.0, 0.82, 1.44), Vector3(1.10, 0.06, 0.92), Vector2(0.90, 0.76), car_mat)
	_add_tapered_box(root, Vector3(0.0, 0.64, -1.76), Vector3(1.76, 0.44, 0.86), Vector2(1.60, 0.66), car_mat)
	_add_box(root, Vector3(1.46, 0.045, 0.11), Vector3(0.0, 0.87, -2.06), mats.dark_metal_mat)

	# Sleek raked tapered fastback greenhouse with proud front windshield, rear backlight & split B-pillar door windows
	var cab_c := Vector3(0.0, 1.10, -0.20)
	_add_tapered_box(root, cab_c, Vector3(1.58, 0.52, 2.34), Vector2(1.30, 1.44), car_mat)
	_add_box(root, Vector3(1.60, 0.045, 2.35), cab_c + Vector3(0.0, -0.24, 0.0), mats.dark_metal_mat)
	# Raked front windshield & rear glass framed by painted A-pillars and C-pillars
	_add_tapered_box(root, cab_c + Vector3(0.0, -0.008, 0.0), Vector3(1.36, 0.44, 2.396), Vector2(1.12, 1.496), mats.glass_dark_mat)
	for wx_p: float in [-0.26, 0.18]:
		_add_box(root, Vector3(0.44, 0.024, 0.024), Vector3(wx_p, 0.89, 1.00), mats.dark_metal_mat)
	# Center dark gloss B-pillar + split front & rear side door windows
	_add_tapered_box(root, cab_c + Vector3(0.0, -0.008, 0.02), Vector3(1.638, 0.44, 0.12), Vector2(1.358, 0.10), mats.dark_metal_mat)
	_add_tapered_box(root, cab_c + Vector3(0.0, -0.008, 0.47), Vector3(1.624, 0.43, 0.86), Vector2(1.344, 0.52), mats.glass_dark_mat)
	_add_tapered_box(root, cab_c + Vector3(0.0, -0.008, -0.46), Vector3(1.624, 0.43, 0.84), Vector2(1.344, 0.50), mats.glass_dark_mat)
	# Roof shark-fin antenna
	_add_tapered_box(root, Vector3(0.0, 1.39, -0.78), Vector3(0.05, 0.08, 0.16), Vector2(0.02, 0.06), mats.dark_metal_mat)

	# Front grille fascia, chrome bars, bumpers, license plates, exhaust, side mirrors & over-tire wheel-arch brows
	_add_box(root, Vector3(1.72, 0.20, 0.18), Vector3(0.0, 0.34, 2.16), mats.dark_metal_mat)
	_add_box(root, Vector3(1.16, 0.20, 0.06), Vector3(0.0, 0.47, 2.19), mats.dark_metal_mat)
	_add_box(root, Vector3(1.10, 0.04, 0.05), Vector3(0.0, 0.51, 2.21), mats.light_metal_mat)
	_add_box(root, Vector3(1.06, 0.03, 0.05), Vector3(0.0, 0.44, 2.21), mats.light_metal_mat)
	_add_box(root, Vector3(0.42, 0.11, 0.03), Vector3(0.0, 0.34, 2.24), mats.marking_white_mat)
	_add_box(root, Vector3(1.70, 0.20, 0.18), Vector3(0.0, 0.34, -2.16), mats.dark_metal_mat)
	_add_box(root, Vector3(0.42, 0.12, 0.03), Vector3(0.0, 0.54, -2.18), mats.marking_white_mat)
	for ex_s: float in [-0.54, 0.54]:
		_add_box(root, Vector3(0.11, 0.07, 0.10), Vector3(ex_s, 0.25, -2.22), mats.light_metal_mat)
	for mx_s: float in [-1.0, 1.0]:
		_add_box(root, Vector3(0.12, 0.04, 0.05), Vector3(mx_s * 0.84, 0.93, 0.56), mats.dark_metal_mat)
		_add_tapered_box(root, Vector3(mx_s * 0.95, 0.96, 0.54), Vector3(0.16, 0.11, 0.14), Vector2(0.13, 0.11), car_mat)
		_add_box(root, Vector3(0.038, 0.040, 0.18), Vector3(mx_s * 0.94, 0.78, 0.16), mats.light_metal_mat)
		_add_box(root, Vector3(0.038, 0.040, 0.18), Vector3(mx_s * 0.94, 0.79, -0.82), mats.light_metal_mat)
		_add_box(root, Vector3(0.11, 0.12, 1.94), Vector3(mx_s * 0.89, 0.18, 0.0), mats.dark_metal_mat)
		for wz_a: float in [-1.35, 1.35]:
			_add_tapered_box(root, Vector3(mx_s * 0.89, 0.74, wz_a), Vector3(0.14, 0.10, 0.82), Vector2(0.10, 0.62), car_mat)
			_add_box(root, Vector3(0.13, 0.045, 0.78), Vector3(mx_s * 0.895, 0.69, wz_a), mats.dark_metal_mat)
	# Headlights & taillights
	for lx_s: float in [-0.56, 0.56]:
		_add_box(root, Vector3(0.36, 0.09, 0.06), Vector3(lx_s, 0.64, 2.13), mats.ev_headlight_mat)
		_add_box(root, Vector3(0.38, 0.10, 0.06), Vector3(lx_s, 0.69, -2.13), mats.ev_taillight_mat)
	_add_box(root, Vector3(1.48, 0.04, 0.05), Vector3(0.0, 0.65, 2.135), mats.ev_headlight_mat)
	_add_box(root, Vector3(1.50, 0.045, 0.05), Vector3(0.0, 0.70, -2.135), mats.ev_taillight_mat)

	# 4 unobstructed circular tires + recessed dark brake rotor + 5-spoke alloy wheel rims
	for wx: float in [-0.84, 0.84]:
		var s_out := 1.0 if wx > 0.0 else -1.0
		for wz: float in [-1.35, 1.35]:
			_add_cyl_xf(root, 0.33, 0.33, 0.23, Vector3(wx, 0.33, wz), wheel_basis_local, mats.dark_metal_mat, 12)
			_add_cyl_xf(root, 0.22, 0.22, 0.238, Vector3(wx + s_out * 0.006, 0.33, wz), wheel_basis_local, mats.light_metal_mat, 10)
			_add_cyl_xf(root, 0.17, 0.17, 0.242, Vector3(wx + s_out * 0.008, 0.33, wz), wheel_basis_local, mats.dark_metal_mat, 10)
			for sp_i in range(5):
				var sa := float(sp_i) * TAU / 5.0 + 0.25
				var sp_b := Basis(Vector3.RIGHT, sa)
				var sp_p := Vector3(wx + s_out * 0.125, 0.33 + cos(sa) * 0.10, wz + sin(sa) * 0.10)
				_add_box_xf(root, sp_p, sp_b, Vector3(0.016, 0.18, 0.042), mats.light_metal_mat)
			_add_cyl_xf(root, 0.055, 0.055, 0.25, Vector3(wx + s_out * 0.012, 0.33, wz), wheel_basis_local, mats.light_metal_mat, 8)


static func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	if parent.has_meta("_prop_batch"):
		var st := _get_batch_st(parent, mat)
		var xf: Transform3D = parent.get_meta("_prop_xform")
		_emit_batch_box(st, xf * pos, xf.basis, size)
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


static func _add_tapered_box(parent: Node3D, pos: Vector3, bot_size: Vector3, top_xz: Vector2, mat: Material) -> void:
	if parent.has_meta("_prop_batch"):
		var st := _get_batch_st(parent, mat)
		var xf: Transform3D = parent.get_meta("_prop_xform")
		_emit_batch_tapered_box(st, xf * pos, xf.basis, bot_size, top_xz)
		return
	var st_local := SurfaceTool.new()
	st_local.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_batch_tapered_box(st_local, Vector3.ZERO, Basis.IDENTITY, bot_size, top_xz)
	var mi := MeshInstance3D.new()
	mi.mesh = st_local.commit()
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


static func _emit_batch_tapered_box(st: SurfaceTool, center: Vector3, basis: Basis, bot_size: Vector3, top_xz: Vector2) -> void:
	var hx0 := basis.x * (bot_size.x * 0.5)
	var hz0 := basis.z * (bot_size.z * 0.5)
	var hx1 := basis.x * (top_xz.x * 0.5)
	var hz1 := basis.z * (top_xz.y * 0.5)
	var hy := basis.y * (bot_size.y * 0.5)
	var b00 := center - hx0 - hy - hz0
	var b10 := center + hx0 - hy - hz0
	var b01 := center - hx0 - hy + hz0
	var b11 := center + hx0 - hy + hz0
	var t00 := center - hx1 + hy - hz1
	var t10 := center + hx1 + hy - hz1
	var t01 := center - hx1 + hy + hz1
	var t11 := center + hx1 + hy + hz1
	var h_full := maxf(0.001, bot_size.y)
	var d_hz := (bot_size.z - top_xz.y) * 0.5
	var d_hx := (bot_size.x - top_xz.x) * 0.5
	var n_front := (basis * Vector3(0.0, d_hz, h_full)).normalized()
	var n_back := (basis * Vector3(0.0, d_hz, -h_full)).normalized()
	var n_right := (basis * Vector3(h_full, d_hx, 0.0)).normalized()
	var n_left := (basis * Vector3(-h_full, d_hx, 0.0)).normalized()
	_emit_batch_quad(st, t00, t10, t01, t11, basis.y)
	_emit_batch_quad(st, b01, b11, b00, b10, -basis.y)
	_emit_batch_quad(st, t01, t11, b01, b11, n_front)
	_emit_batch_quad(st, t10, t00, b10, b00, n_back)
	_emit_batch_quad(st, t11, t10, b11, b10, n_right)
	_emit_batch_quad(st, t00, t01, b00, b01, n_left)


static func _add_cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> void:
	if parent.has_meta("_prop_batch"):
		var st := _get_batch_st(parent, mat)
		var xf: Transform3D = parent.get_meta("_prop_xform")
		_emit_batch_cyl(st, xf * pos, xf.basis, radius * 0.85, radius, height, 8)
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.85
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


static func _emit_batch_box(st: SurfaceTool, center: Vector3, basis: Basis, size: Vector3) -> void:
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
	_emit_batch_quad(st, p010, p110, p011, p111, basis.y)
	_emit_batch_quad(st, p001, p101, p000, p100, -basis.y)
	_emit_batch_quad(st, p011, p111, p001, p101, basis.z)
	_emit_batch_quad(st, p110, p010, p100, p000, -basis.z)
	_emit_batch_quad(st, p111, p110, p101, p100, basis.x)
	_emit_batch_quad(st, p010, p011, p000, p001, -basis.x)


static func _emit_batch_cyl(st: SurfaceTool, center: Vector3, basis: Basis, top_r: float, bot_r: float, height: float, segs: int) -> void:
	var half_h := basis.y * (height * 0.5)
	var top_c := center + half_h
	var bot_c := center - half_h
	for i in range(segs):
		var a0 := float(i) * TAU / float(segs)
		var a1 := float(i + 1) * TAU / float(segs)
		var r0 := basis.x * cos(a0) + basis.z * sin(a0)
		var r1 := basis.x * cos(a1) + basis.z * sin(a1)
		var t0 := top_c + r0 * top_r
		var t1 := top_c + r1 * top_r
		var b0 := bot_c + r0 * bot_r
		var b1 := bot_c + r1 * bot_r
		var mid_a := (a0 + a1) * 0.5
		var n := (basis.x * cos(mid_a) + basis.z * sin(mid_a)).normalized()
		_emit_batch_quad(st, t0, t1, b0, b1, n)
		_emit_batch_tri(st, top_c, t1, t0, basis.y)
		_emit_batch_tri(st, bot_c, b0, b1, -basis.y)


static func _emit_batch_ellipsoid(st: SurfaceTool, center: Vector3, basis: Basis, rx: float, ry: float) -> void:
	const RINGS := 4
	const SEGS := 7
	for ri in range(RINGS):
		var v0 := -PI * 0.5 + PI * float(ri) / float(RINGS)
		var v1 := -PI * 0.5 + PI * float(ri + 1) / float(RINGS)
		for si in range(SEGS):
			var u0 := float(si) * TAU / float(SEGS)
			var u1 := float(si + 1) * TAU / float(SEGS)
			var pts: Array[Vector3] = []
			for uv in [[u0, v1], [u1, v1], [u0, v0], [u1, v0]]:
				var c_v := cos(float(uv[1]))
				var l := Vector3(cos(float(uv[0])) * c_v * rx, sin(float(uv[1])) * ry, sin(float(uv[0])) * c_v * rx)
				pts.append(center + basis * l)
			var mid_n: Vector3 = ((pts[0] + pts[1] + pts[2] + pts[3]) * 0.25 - center).normalized()
			_emit_batch_quad(st, pts[0], pts[1], pts[2], pts[3], mid_n)


static func _emit_batch_quad(st: SurfaceTool, tl: Vector3, tr: Vector3, bl: Vector3, br: Vector3, desired_n: Vector3) -> void:
	var n_test := (bl - tl).cross(tr - tl)
	var pts := [tl, tr, bl, tr, br, bl] if n_test.dot(desired_n) >= 0.0 else [tl, bl, tr, tr, bl, br]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var n := desired_n.normalized()
	for i in range(6):
		st.set_uv(uvs[i])
		st.set_normal(n)
		st.add_vertex(pts[i])


static func _emit_batch_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, desired_n: Vector3) -> void:
	var n_test := (c - a).cross(b - a)
	var pts := [a, b, c] if n_test.dot(desired_n) >= 0.0 else [a, c, b]
	var n := desired_n.normalized()
	for p in pts:
		st.set_normal(n)
		st.add_vertex(p)


static func _mat_or(mats: MaterialLibrary, prop_name: String, fallback: Material) -> Material:
	if mats != null:
		var v: Variant = mats.get(prop_name)
		if v is Material:
			return v as Material
	return fallback


static func _get_decal_textures(mats: MaterialLibrary, kind: String) -> Dictionary:
	if mats != null and mats.has_method("get_decal_textures"):
		var res: Variant = mats.call("get_decal_textures", kind)
		if res is Dictionary:
			return res as Dictionary
	if _decal_fallback_cache.has(kind):
		return _decal_fallback_cache[kind]
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.11, 0.10, 0.45))
	var tex := ImageTexture.create_from_image(img)
	var pair := {"albedo": tex, "orm": null}
	_decal_fallback_cache[kind] = pair
	return pair


static func _build_weather_decal(prop: Dictionary, mats: MaterialLibrary) -> Decal:
	var kind := String(prop.get("decal_kind", "alley_grime"))
	var texs := _get_decal_textures(mats, kind)
	var decal := Decal.new()
	decal.name = "Decal_%s" % kind
	decal.position = prop.get("pos", Vector3.ZERO)
	decal.rotation.y = float(prop.get("yaw", 0.0))
	decal.size = prop.get("size", Vector3(2.2, 0.75, 2.2))
	var alb: Variant = texs.get("albedo", null)
	if alb is Texture2D:
		decal.texture_albedo = alb as Texture2D
	var orm: Variant = texs.get("orm", null)
	if orm is Texture2D:
		decal.texture_orm = orm as Texture2D
	decal.cull_mask = 2
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 28.0
	decal.distance_fade_length = 12.0
	decal.upper_fade = 0.35
	decal.lower_fade = 0.35
	decal.normal_fade = 0.45
	decal.albedo_mix = float(prop.get("albedo_mix", 0.72))
	decal.modulate = prop.get("modulate", Color(1.0, 1.0, 1.0, 0.90))
	return decal


static func _build_riprap_cluster(root: Node3D, prop: Dictionary, mats: MaterialLibrary, chunk_batch: Dictionary) -> void:
	var pos: Vector3 = prop.get("pos", Vector3.ZERO)
	var yaw: float = float(prop.get("yaw", 0.0))
	var scale_v: float = float(prop.get("scale", 1.0))
	var base_var: int = posmod(int(prop.get("variant", 0)), FloraGenerator.VARIANT_COUNT)
	var slope_dir: Vector2 = prop.get("slope_dir", Vector2(1.0, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(prop.get("seed", hash(pos))) ^ 0x4B1D9E

	var riprap_mat := _mat_or(mats, "riprap_stone_mat", mats.bridge_concrete_mat)
	var count := 4
	for i in range(count):
		var ang := float(i) * (TAU / float(count)) + rng.randf_range(-0.35, 0.35)
		var dist := 0.0 if i == 0 else rng.randf_range(0.42, 1.05) * scale_v
		var off2 := Vector2(cos(ang), sin(ang)) * dist
		var slope_drop := off2.dot(slope_dir) * 0.24
		var b_pos := pos + Vector3(off2.x, -0.06 - slope_drop, off2.y)
		var b_scale := scale_v * (rng.randf_range(0.95, 1.30) if i == 0 else rng.randf_range(0.62, 1.02))
		var b_basis := Basis(Vector3.UP, yaw + rng.randf_range(0.0, TAU)) * Basis(Vector3.RIGHT, rng.randf_range(-0.18, 0.18))
		b_basis = b_basis.scaled(Vector3(b_scale, b_scale * rng.randf_range(0.78, 1.12), b_scale))
		var b_var := posmod(base_var + i, FloraGenerator.VARIANT_COUNT)

		if not chunk_batch.is_empty():
			chunk_batch["_riprap_mat"] = riprap_mat
			var rmap: Dictionary = chunk_batch["_riprap"]
			var list: Array = rmap.get(b_var, [])
			list.append({"transform": Transform3D(b_basis, b_pos)})
			rmap[b_var] = list
		else:
			var bundle := FloraGenerator.get_flora_bundle("riprap", "riprap_boulder", b_var)
			var rock_m: ArrayMesh = bundle.get("riprap_mesh", null)
			if rock_m != null:
				var mi := MeshInstance3D.new()
				mi.mesh = rock_m
				mi.material_override = riprap_mat
				mi.transform = Transform3D(b_basis, b_pos - pos)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.visibility_range_end = 140.0
				mi.visibility_range_end_margin = 14.0
				root.add_child(mi)


static func _add_chunk_collider(root: Node3D, shape: Shape3D, local_xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	if root.has_meta("_prop_batch"):
		var batch: Dictionary = root.get_meta("_prop_batch")
		var shared_body: StaticBody3D = batch.get("_shared_body", null) as StaticBody3D
		if shared_body == null:
			shared_body = StaticBody3D.new()
			shared_body.name = "ChunkPropColliders"
			batch["_shared_body"] = shared_body
		var xf: Transform3D = root.get_meta("_prop_xform")
		cs.transform = xf * local_xf
		shared_body.add_child(cs)
	else:
		var body := StaticBody3D.new()
		cs.transform = local_xf
		body.add_child(cs)
		root.add_child(body)


static func _build_commercial_dumpster(root: Node3D, mats: MaterialLibrary) -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(1.94, 1.24, 1.28)
	_add_chunk_collider(root, box, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.62, 0.0)))

	var green_mat := _mat_or(mats, "dumpster_green_mat", mats.get_accent_material(Color(0.14, 0.29, 0.20)))
	_add_box(root, Vector3(2.08, 0.08, 1.44), Vector3(0.0, 0.02, 0.0), mats.bridge_concrete_mat)
	for cx: float in [-0.74, 0.74]:
		for cz: float in [-0.46, 0.46]:
			_add_box(root, Vector3(0.10, 0.14, 0.10), Vector3(cx, 0.11, cz), mats.dark_metal_mat)
	_add_box(root, Vector3(1.82, 0.92, 1.16), Vector3(0.0, 0.62, 0.0), green_mat)
	_add_box(root, Vector3(1.88, 0.10, 1.22), Vector3(0.0, 1.06, 0.0), green_mat)
	for sx: float in [-0.95, 0.95]:
		_add_box(root, Vector3(0.10, 0.22, 0.56), Vector3(sx, 0.56, 0.0), mats.dark_metal_mat)
	for lx: float in [-0.44, 0.44]:
		_add_box_xf(root, Vector3(lx, 1.13, 0.02), Basis(Vector3.RIGHT, 0.08), Vector3(0.84, 0.06, 1.16), mats.dark_metal_mat)


static func _build_pallet_stack(root: Node3D, variant: int, mats: MaterialLibrary) -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(1.26, 0.96, 1.06)
	_add_chunk_collider(root, box, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.48, 0.0)))

	var pmat := _mat_or(mats, "pallet_wood_mat", mats.wood_cedar_mat)
	var layers := 2 if variant % 2 == 0 else 1
	for li in range(layers):
		var by := float(li) * 0.16
		for sx: float in [-0.48, 0.0, 0.48]:
			_add_box(root, Vector3(0.10, 0.10, 1.00), Vector3(sx, by + 0.05, 0.0), pmat)
		for sz: float in [-0.42, -0.21, 0.0, 0.21, 0.42]:
			_add_box(root, Vector3(1.20, 0.04, 0.13), Vector3(0.0, by + 0.12, sz), pmat)

	var top_y := float(layers) * 0.16
	_add_box(root, Vector3(0.56, 0.48, 0.46), Vector3(-0.26, top_y + 0.24, -0.14), mats.wood_door_mat)
	_add_box(root, Vector3(0.50, 0.42, 0.46), Vector3(0.28, top_y + 0.21, 0.12), pmat)
	_add_box(root, Vector3(0.46, 0.36, 0.40), Vector3(-0.18, top_y + 0.66, -0.10), pmat)
	_add_box(root, Vector3(0.58, 0.03, 0.48), Vector3(-0.26, top_y + 0.30, -0.14), mats.dark_metal_mat)


static func _build_safety_bollard(root: Node3D, mats: MaterialLibrary) -> void:
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.13
	cyl.height = 0.98
	_add_chunk_collider(root, cyl, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.49, 0.0)))

	var ymat := _mat_or(mats, "safety_yellow_mat", mats.ada_tactile_mat)
	_add_cyl(root, 0.16, 0.08, Vector3(0.0, 0.04, 0.0), mats.bridge_concrete_mat)
	_add_cyl(root, 0.10, 0.88, Vector3(0.0, 0.50, 0.0), ymat)
	_add_cyl(root, 0.104, 0.10, Vector3(0.0, 0.78, 0.0), mats.dark_metal_mat)
	_add_cyl(root, 0.085, 0.06, Vector3(0.0, 0.96, 0.0), ymat)


static func _build_ac_condenser(root: Node3D, mats: MaterialLibrary) -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(1.02, 0.88, 0.54)
	_add_chunk_collider(root, box, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.44, 0.0)))

	_add_box(root, Vector3(1.04, 0.10, 0.56), Vector3(0.0, 0.05, 0.0), mats.bridge_concrete_mat)
	_add_box(root, Vector3(0.92, 0.74, 0.44), Vector3(0.0, 0.47, 0.0), mats.light_metal_mat)
	_add_box(root, Vector3(0.76, 0.52, 0.46), Vector3(0.0, 0.47, 0.0), mats.dark_metal_mat)
	_add_cyl(root, 0.19, 0.06, Vector3(0.0, 0.86, 0.0), mats.dark_metal_mat)
	_add_box(root, Vector3(0.07, 0.07, 0.34), Vector3(0.32, 0.28, -0.34), mats.dark_metal_mat)


static func _build_chainlink_fence(root: Node3D, prop: Dictionary, mats: MaterialLibrary) -> void:
	var span := float(prop.get("length", 8.0))
	var dy := float(prop.get("dy", 0.0))
	var pitch := atan2(dy, maxf(0.1, span))
	var hyp := sqrt(span * span + dy * dy)
	var b_slope := Basis(Vector3.RIGHT, -pitch)
	var mid_y := dy * 0.5
	var h := 2.02

	var box := BoxShape3D.new()
	box.size = Vector3(0.14, h + 0.1, hyp)
	_add_chunk_collider(root, box, Transform3D(b_slope, Vector3(0.0, mid_y + h * 0.5, 0.0)))

	var fmat := _mat_or(mats, "chainlink_fence_mat", mats.light_metal_mat)
	for end_i in [[-span * 0.5, 0.0], [0.0, mid_y], [span * 0.5, dy]]:
		_add_box(root, Vector3(0.08, h + 0.14, 0.08), Vector3(0.0, float(end_i[1]) + h * 0.5 - 0.04, float(end_i[0])), mats.light_metal_mat)
	_add_box_xf(root, Vector3(0.0, mid_y + h - 0.06, 0.0), b_slope, Vector3(0.055, 0.055, hyp), mats.light_metal_mat)
	_add_box_xf(root, Vector3(0.0, mid_y + 0.14, 0.0), b_slope, Vector3(0.055, 0.055, hyp), mats.light_metal_mat)
	_add_box_xf(root, Vector3(0.0, mid_y + h * 0.52, 0.0), b_slope, Vector3(0.025, h - 0.26, hyp - 0.06), fmat)


static func _build_driveway_pad(root: Node3D, prop: Dictionary, mats: MaterialLibrary) -> void:
	## Ground-hugging sloped residential driveway apron (zero colliders so terrain physics stay smooth).
	var w := float(prop.get("width", 2.7))
	var length := float(prop.get("length", 4.5))
	var dy0 := float(prop.get("dy0", 0.0))
	var dy1 := float(prop.get("dy1", 0.0))
	var dy2 := float(prop.get("dy2", 0.0))
	var cmat := _mat_or(mats, "driveway_concrete_mat", mats.sidewalk_mat)

	var half_l := length * 0.5
	var segs := [[-half_l, 0.0, dy0, dy1], [0.0, half_l, dy1, dy2]]
	for sg in segs:
		var z0 := float(sg[0])
		var z1 := float(sg[1])
		var y0 := float(sg[2]) + 0.036
		var y1 := float(sg[3]) + 0.036
		var dz := z1 - z0
		var dy := y1 - y0
		var pitch := atan2(dy, maxf(0.1, dz))
		var hyp := sqrt(dz * dz + dy * dy)
		var b := Basis(Vector3.RIGHT, -pitch)
		var center := Vector3(0.0, (y0 + y1) * 0.5 - 0.11, (z0 + z1) * 0.5)
		_add_box_xf(root, center, b, Vector3(w, 0.22, hyp + 0.08), cmat)
		for cx: float in [-w * 0.5 - 0.04, w * 0.5 + 0.04]:
			_add_box_xf(root, center + Vector3(cx, 0.015, 0.0), b, Vector3(0.09, 0.24, hyp + 0.08), mats.bridge_concrete_mat)


static func _build_lot_fence(root: Node3D, prop: Dictionary, mats: MaterialLibrary) -> void:
	var span := float(prop.get("length", 8.0))
	var dy := float(prop.get("dy", 0.0))
	var style := String(prop.get("style", "cedar"))
	var pitch := atan2(dy, maxf(0.1, span))
	var hyp := sqrt(span * span + dy * dy)
	var b_slope := Basis(Vector3.RIGHT, -pitch)
	var mid_y := dy * 0.5
	var h := 1.62 if style == "cedar" else (1.12 if style == "iron" else 1.02)

	var box := BoxShape3D.new()
	box.size = Vector3(0.16, h + 0.10, hyp)
	_add_chunk_collider(root, box, Transform3D(b_slope, Vector3(0.0, mid_y + h * 0.5, 0.0)))

	var post_mat: Material = mats.wood_door_mat
	var panel_mat: Material = mats.wood_cedar_mat
	if style == "picket":
		post_mat = mats.marking_white_mat
		panel_mat = mats.marking_white_mat
	elif style == "iron":
		post_mat = mats.limestone_mat
		panel_mat = mats.dark_metal_mat

	var pw := 0.16 if style == "iron" else 0.11
	for end_i in [[-span * 0.5, 0.0], [0.0, mid_y], [span * 0.5, dy]]:
		_add_box(root, Vector3(pw, h + 0.14, pw), Vector3(0.0, float(end_i[1]) + h * 0.5 - 0.02, float(end_i[0])), post_mat)

	if style == "cedar":
		_add_box_xf(root, Vector3(0.0, mid_y + h * 0.5, 0.0), b_slope, Vector3(0.05, h - 0.08, hyp - 0.06), panel_mat)
		_add_box_xf(root, Vector3(0.0, mid_y + h - 0.08, 0.0), b_slope, Vector3(0.09, 0.07, hyp), post_mat)
		_add_box_xf(root, Vector3(0.0, mid_y + 0.24, 0.0), b_slope, Vector3(0.08, 0.07, hyp), post_mat)
	else:
		_add_box_xf(root, Vector3(0.0, mid_y + h - 0.10, 0.0), b_slope, Vector3(0.05, 0.06, hyp), panel_mat)
		_add_box_xf(root, Vector3(0.0, mid_y + h * 0.50, 0.0), b_slope, Vector3(0.04, 0.05, hyp), panel_mat)
		_add_box_xf(root, Vector3(0.0, mid_y + 0.20, 0.0), b_slope, Vector3(0.05, 0.06, hyp), panel_mat)
		_add_box_xf(root, Vector3(0.0, mid_y + h * 0.52, 0.0), b_slope, Vector3(0.025, h - 0.16, hyp - 0.10), post_mat if style == "picket" else panel_mat)


static func _add_cyl_xf(parent: Node3D, top_r: float, bot_r: float, height: float, pos: Vector3, basis: Basis, mat: Material, segs: int = 8) -> void:
	if parent.has_meta("_prop_batch"):
		var st := _get_batch_st(parent, mat)
		var xf: Transform3D = parent.get_meta("_prop_xform")
		_emit_batch_cyl(st, xf * pos, xf.basis * basis, top_r, bot_r, height, segs)
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = height
	cm.radial_segments = segs
	mi.mesh = cm
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	parent.add_child(mi)


static func _build_beach_boardwalk_seg(root: Node3D, prop: Dictionary, mats: MaterialLibrary) -> void:
	## Walkable raised cedar beach boardwalk segment smoothly following coastal dune elevation.
	var span := float(prop.get("length", 12.0))
	var w := float(prop.get("width", 3.8))
	var dy := float(prop.get("dy", 0.0))
	var has_lamp := bool(prop.get("has_lamp", false))
	var pitch := atan2(dy, maxf(0.1, span))
	var hyp := sqrt(span * span + dy * dy)
	var b_slope := Basis(Vector3.RIGHT, -pitch)
	var plank_mat := _mat_or(mats, "boardwalk_wood_mat", mats.wood_cedar_mat)

	# Walkable Jolt deck collider
	var deck_box := BoxShape3D.new()
	deck_box.size = Vector3(w, 0.22, hyp + 0.10)
	_add_chunk_collider(root, deck_box, Transform3D(b_slope, Vector3(0.0, -0.11, 0.0)))

	# Raised cedar plank deck + bevel side timber curbs + sand support pilings
	_add_box_xf(root, Vector3(0.0, -0.09, 0.0), b_slope, Vector3(w, 0.18, hyp + 0.08), plank_mat)
	for sx: float in [-w * 0.5 + 0.10, w * 0.5 - 0.10]:
		_add_box_xf(root, Vector3(sx, 0.05, 0.0), b_slope, Vector3(0.18, 0.14, hyp + 0.06), mats.wood_cedar_mat)
		_add_box_xf(root, Vector3(sx * 0.86, -0.26, 0.0), b_slope, Vector3(0.18, 0.20, hyp), mats.wood_door_mat)
		for sz_frac: float in [-0.36, 0.36]:
			var pz := sz_frac * span
			var py := sz_frac * dy
			_add_cyl_xf(root, 0.12, 0.13, 1.80, Vector3(sx * 0.86, py - 1.02, pz), Basis.IDENTITY, mats.wood_door_mat, 8)

	# Warm low coastal timber bollard light on the ocean-facing rim
	if has_lamp:
		var bx := -w * 0.5 + 0.12
		_add_box(root, Vector3(0.16, 0.92, 0.16), Vector3(bx, 0.46, 0.0), mats.wood_door_mat)
		_add_box(root, Vector3(0.20, 0.08, 0.20), Vector3(bx, 0.95, 0.0), mats.dark_metal_mat)
		_add_box(root, Vector3(0.13, 0.16, 0.13), Vector3(bx, 0.82, 0.0), mats.lamp_glow_mat)


static func _build_beach_pier(root: Node3D, prop: Dictionary, mats: MaterialLibrary) -> void:
	## Iconic walkable Ocean Fishing & Observation Pier jutting south across breaking surf waves,
	## complete with seabed timber pilings, X-bracing, railings, lantern posts, benches & T-head lookout pavilion.
	var pier_len := float(prop.get("length", 74.0))
	var w := float(prop.get("width", 5.4))
	var half_l := pier_len * 0.5
	var hw := w * 0.5
	var plank_mat := _mat_or(mats, "boardwalk_wood_mat", mats.wood_cedar_mat)
	var white_mat := mats.marking_white_mat
	var roof_mat := mats.get_accent_material(Color(0.14, 0.46, 0.56))

	# 1. Main pier walkable deck collider & plank surface
	var main_box := BoxShape3D.new()
	main_box.size = Vector3(w, 0.28, pier_len)
	_add_chunk_collider(root, main_box, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.14, 0.0)))
	_add_box(root, Vector3(w, 0.24, pier_len), Vector3(0.0, -0.12, 0.0), plank_mat)

	# Gentle beach-entry approach ramp at landward (-Z) start so player walks seamlessly onto the pier
	var ramp_len := 4.4
	var ramp_drop := clampf(float(prop.get("pos", Vector3.ZERO).y) - float(prop.get("start_ground_y", 2.0)), 0.25, 1.35)
	var ramp_pitch := atan2(ramp_drop, ramp_len)
	var ramp_hyp := sqrt(ramp_len * ramp_len + ramp_drop * ramp_drop)
	var ramp_b := Basis(Vector3.RIGHT, ramp_pitch)
	var ramp_c := Vector3(0.0, -ramp_drop * 0.5 - 0.10, -half_l - ramp_len * 0.5 + 0.15)
	var ramp_box := BoxShape3D.new()
	ramp_box.size = Vector3(w - 0.2, 0.24, ramp_hyp + 0.2)
	_add_chunk_collider(root, ramp_box, Transform3D(ramp_b, ramp_c))
	_add_box_xf(root, ramp_c, ramp_b, Vector3(w - 0.1, 0.22, ramp_hyp + 0.2), plank_mat)

	# 2. Wider T-head Ocean Observation Deck at seaward (+Z) end
	var head_w := w * 2.15
	var head_d := 9.6
	var head_cz := half_l + head_d * 0.5 - 0.2
	var head_box := BoxShape3D.new()
	head_box.size = Vector3(head_w, 0.28, head_d)
	_add_chunk_collider(root, head_box, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.14, head_cz)))
	_add_box(root, Vector3(head_w, 0.24, head_d), Vector3(0.0, -0.12, head_cz), plank_mat)

	# Under-deck longitudinal heavy timber stringers
	for sx_s: float in [-hw + 0.45, 0.0, hw - 0.45]:
		_add_box(root, Vector3(0.24, 0.34, pier_len + head_d * 0.9), Vector3(sx_s, -0.40, head_d * 0.45), mats.wood_door_mat)

	# 3. Heavy weathered seabed timber pilings & cross-bracing every 6.0m reaching deep into ocean floor
	var pil_h := 7.6
	var pil_cy := -0.35 - pil_h * 0.5
	var z_cur := -half_l + 2.0
	var bay_idx := 0
	while z_cur <= half_l - 1.5:
		_add_box(root, Vector3(w + 0.35, 0.26, 0.28), Vector3(0.0, -0.42, z_cur), mats.wood_door_mat)
		for sx_p: float in [-hw + 0.38, hw - 0.38]:
			_add_cyl_xf(root, 0.20, 0.23, pil_h, Vector3(sx_p, pil_cy, z_cur), Basis.IDENTITY, mats.wood_door_mat, 8)
		# Diagonal X-brace timbers beneath the deck span
		var diag_w := (w - 0.8) * 1.12
		var brace_y := -1.45
		_add_box_xf(root, Vector3(0.0, brace_y, z_cur), Basis(Vector3.FORWARD, 0.42), Vector3(diag_w, 0.14, 0.10), mats.wood_cedar_mat)
		_add_box_xf(root, Vector3(0.0, brace_y, z_cur), Basis(Vector3.FORWARD, -0.42), Vector3(diag_w, 0.14, 0.10), mats.wood_cedar_mat)

		# Side wooden railing posts + coastal pier lanterns every 2 bays (12m)
		for sx_r: float in [-hw + 0.14, hw - 0.14]:
			_add_box(root, Vector3(0.15, 1.12, 0.15), Vector3(sx_r, 0.56, z_cur), mats.wood_cedar_mat)
			if bay_idx % 2 == 1:
				var lx := sx_r + (0.04 if sx_r > 0.0 else -0.04)
				_add_cyl_xf(root, 0.06, 0.08, 2.75, Vector3(lx, 1.90, z_cur), Basis.IDENTITY, mats.dark_metal_mat, 8)
				_add_box(root, Vector3(0.32, 0.08, 0.32), Vector3(lx, 3.30, z_cur), mats.dark_metal_mat)
				_add_box(root, Vector3(0.22, 0.30, 0.22), Vector3(lx, 3.12, z_cur), mats.lamp_glow_mat)
		z_cur += 6.0
		bay_idx += 1

	# Continuous timber top & mid safety rails along both pier sides
	for sx_r: float in [-hw + 0.14, hw - 0.14]:
		_add_box(root, Vector3(0.14, 0.09, pier_len), Vector3(sx_r, 1.06, 0.0), mats.wood_cedar_mat)
		_add_box(root, Vector3(0.08, 0.07, pier_len), Vector3(sx_r, 0.58, 0.0), mats.wood_cedar_mat)
		_add_box(root, Vector3(0.18, 0.16, pier_len), Vector3(sx_r, 0.08, 0.0), mats.wood_door_mat)

	# 4. T-head pilings, wrap-around ocean lookout railing, coastal shade pavilion & viewing benches
	var head_hw := head_w * 0.5
	var head_z0 := head_cz - head_d * 0.5
	var head_z1 := head_cz + head_d * 0.5
	for hpx: float in [-head_hw + 0.45, -hw * 0.6, hw * 0.6, head_hw - 0.45]:
		for hpz: float in [head_z0 + 0.55, head_z1 - 0.55]:
			_add_cyl_xf(root, 0.21, 0.24, pil_h, Vector3(hpx, pil_cy, hpz), Basis.IDENTITY, mats.wood_door_mat, 8)
	# T-head railings (left, right, seaward front, and back wings)
	_add_box(root, Vector3(head_w, 0.10, 0.14), Vector3(0.0, 1.06, head_z1 - 0.14), mats.wood_cedar_mat)
	_add_box(root, Vector3(head_w, 0.07, 0.08), Vector3(0.0, 0.58, head_z1 - 0.14), mats.wood_cedar_mat)
	for sx_h: float in [-1.0, 1.0]:
		var rx_h := sx_h * (head_hw - 0.14)
		_add_box(root, Vector3(0.14, 0.10, head_d), Vector3(rx_h, 1.06, head_cz), mats.wood_cedar_mat)
		_add_box(root, Vector3(0.08, 0.07, head_d), Vector3(rx_h, 0.58, head_cz), mats.wood_cedar_mat)
		var wing_w := head_hw - hw
		var wing_cx := sx_h * (hw + wing_w * 0.5)
		_add_box(root, Vector3(wing_w, 0.10, 0.14), Vector3(wing_cx, 1.06, head_z0 + 0.14), mats.wood_cedar_mat)
		_add_box(root, Vector3(wing_w, 0.07, 0.08), Vector3(wing_cx, 0.58, head_z0 + 0.14), mats.wood_cedar_mat)
		# Corner pier observation lanterns at seaward corners
		_add_cyl_xf(root, 0.06, 0.08, 2.85, Vector3(rx_h, 1.95, head_z1 - 0.14), Basis.IDENTITY, mats.dark_metal_mat, 8)
		_add_box(root, Vector3(0.24, 0.32, 0.24), Vector3(rx_h, 3.22, head_z1 - 0.14), mats.lamp_glow_mat)
		# Wooden benches facing the ocean horizon
		var bx_b := sx_h * (head_hw - 2.2)
		_add_box(root, Vector3(2.1, 0.09, 0.55), Vector3(bx_b, 0.46, head_cz + 0.5), mats.wood_cedar_mat)
		_add_box(root, Vector3(2.1, 0.42, 0.08), Vector3(bx_b, 0.72, head_cz + 0.22), mats.wood_cedar_mat)
		for leg_dx: float in [-0.85, 0.85]:
			_add_box(root, Vector3(0.10, 0.46, 0.48), Vector3(bx_b + leg_dx, 0.23, head_cz + 0.5), mats.dark_metal_mat)

	# Coastal open-air shade pavilion on the pier T-head
	var pav_w := 5.6
	var pav_d := 4.4
	var pav_h := 3.25
	for pvx: float in [-pav_w * 0.45, pav_w * 0.45]:
		for pvz: float in [head_cz - pav_d * 0.42, head_cz + pav_d * 0.42]:
			_add_box(root, Vector3(0.20, pav_h, 0.20), Vector3(pvx, pav_h * 0.5, pvz), white_mat)
	_add_box(root, Vector3(pav_w + 0.6, 0.22, pav_d + 0.6), Vector3(0.0, pav_h + 0.06, head_cz), white_mat)
	_add_box_xf(root, Vector3(0.0, pav_h + 0.62, head_cz - pav_d * 0.26), Basis(Vector3.RIGHT, -0.34), Vector3(pav_w + 1.1, 0.12, pav_d * 0.68), roof_mat)
	_add_box_xf(root, Vector3(0.0, pav_h + 0.62, head_cz + pav_d * 0.26), Basis(Vector3.RIGHT, 0.34), Vector3(pav_w + 1.1, 0.12, pav_d * 0.68), roof_mat)


static func _build_lifeguard_tower(root: Node3D, variant: int, mats: MaterialLibrary) -> void:
	## Iconic coastal elevated lifeguard watchtower on splayed timber stilts with rescue buoy & ladder.
	var col_box := BoxShape3D.new()
	col_box.size = Vector3(2.8, 3.6, 2.8)
	_add_chunk_collider(root, col_box, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.8, 0.0)))

	var palette := [
		Color(0.14, 0.56, 0.62), # Coastal teal
		Color(0.86, 0.30, 0.22), # Classic rescue coral-red
		Color(0.18, 0.42, 0.68), # Ocean blue
	]
	var accent_mat := mats.get_accent_material(palette[posmod(variant, palette.size())])
	var white_mat := mats.marking_white_mat
	var deck_y := 2.35

	# 4 splayed timber stilts embedded deep into beach sand + diagonal X-bracing
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var stilt_b := Basis(Vector3.FORWARD, sx * 0.12) * Basis(Vector3.RIGHT, -sz * 0.12)
			_add_box_xf(root, Vector3(sx * 1.12, deck_y * 0.5 - 0.15, sz * 1.12), stilt_b, Vector3(0.18, deck_y + 0.65, 0.18), mats.wood_door_mat)
	for sz_b: float in [-1.08, 1.08]:
		_add_box_xf(root, Vector3(0.0, deck_y * 0.48, sz_b), Basis(Vector3.FORWARD, 0.66), Vector3(2.55, 0.11, 0.08), mats.wood_cedar_mat)
		_add_box_xf(root, Vector3(0.0, deck_y * 0.48, sz_b), Basis(Vector3.FORWARD, -0.66), Vector3(2.55, 0.11, 0.08), mats.wood_cedar_mat)

	# Wrap-around lookout catwalk deck + white safety railings
	_add_box(root, Vector3(3.15, 0.18, 3.35), Vector3(0.0, deck_y, 0.15), mats.wood_cedar_mat)
	for sx_r: float in [-1.48, 1.48]:
		_add_box(root, Vector3(0.08, 0.07, 3.25), Vector3(sx_r, deck_y + 0.96, 0.15), white_mat)
		_add_box(root, Vector3(0.06, 0.06, 3.25), Vector3(sx_r, deck_y + 0.52, 0.15), white_mat)
		_add_box(root, Vector3(0.10, 0.96, 0.10), Vector3(sx_r, deck_y + 0.48, 1.72), white_mat)
		_add_box(root, Vector3(0.10, 0.96, 0.10), Vector3(sx_r, deck_y + 0.48, -1.42), white_mat)
	_add_box(root, Vector3(3.04, 0.08, 0.08), Vector3(0.0, deck_y + 0.96, 1.72), white_mat)
	_add_box(root, Vector3(3.04, 0.06, 0.06), Vector3(0.0, deck_y + 0.52, 1.72), white_mat)

	# Watch booth cabin (lower siding + open wraparound panoramic ocean windows + sloped roof)
	var cab_h := 2.18
	_add_box(root, Vector3(2.05, 0.96, 2.05), Vector3(0.0, deck_y + 0.56, -0.15), white_mat)
	_add_box(root, Vector3(2.12, 0.24, 2.12), Vector3(0.0, deck_y + 0.98, -0.15), accent_mat)
	_add_box(root, Vector3(1.94, 0.98, 1.94), Vector3(0.0, deck_y + 1.56, -0.15), mats.glass_dark_mat)
	for cx: float in [-0.96, 0.96]:
		for cz: float in [-1.11, 0.81]:
			_add_box(root, Vector3(0.13, cab_h, 0.13), Vector3(cx, deck_y + cab_h * 0.5, cz), white_mat)
	# Sloped coastal roof overhang + hinged shade shutter propped open over the ocean window
	_add_box_xf(root, Vector3(0.0, deck_y + cab_h + 0.14, -0.05), Basis(Vector3.RIGHT, 0.18), Vector3(2.85, 0.14, 3.05), accent_mat)
	_add_box_xf(root, Vector3(0.0, deck_y + 1.94, 1.18), Basis(Vector3.RIGHT, -0.52), Vector3(1.86, 0.07, 0.85), white_mat)

	# Iconic red lifeguard rescue torpedo buoy mounted on ocean-side railing + front sand ladder
	_add_cyl_xf(root, 0.10, 0.10, 0.72, Vector3(0.88, deck_y + 0.66, 1.78), Basis(Vector3.FORWARD, 0.55), mats.emergency_red_mat, 8)
	var lad_b := Basis(Vector3.RIGHT, -0.34)
	for lx: float in [-0.32, 0.32]:
		_add_box_xf(root, Vector3(lx, deck_y * 0.5, 1.78), lad_b, Vector3(0.07, deck_y + 0.35, 0.09), mats.wood_cedar_mat)
	for ri in range(7):
		var frac := (float(ri) + 0.5) / 7.0
		_add_box(root, Vector3(0.68, 0.05, 0.08), Vector3(0.0, frac * deck_y, 2.22 - frac * 0.84), mats.wood_cedar_mat)


static func _build_beach_umbrella_set(root: Node3D, variant: int, mats: MaterialLibrary) -> void:
	## Colorful coastal beach umbrella paired with two cedar sun loungers & towels.
	var palette := [
		Color(0.84, 0.22, 0.18), # Coral red
		Color(0.10, 0.56, 0.64), # Turquoise teal
		Color(0.92, 0.72, 0.16), # Sunny gold
		Color(0.16, 0.34, 0.66), # Nautical blue
		Color(0.90, 0.44, 0.20), # Sunset tangerine
	]
	var canopy_mat := mats.get_accent_material(palette[posmod(variant, palette.size())])
	var stripe_mat := mats.marking_white_mat
	var towel_mat := mats.get_accent_material(palette[posmod(variant + 2, palette.size())])

	# Slightly tilted umbrella pole & octagonal striped conical sun canopy
	var tilt := Basis(Vector3.FORWARD, 0.10 if variant % 2 == 0 else -0.10)
	_add_cyl_xf(root, 0.032, 0.038, 2.35, Vector3(0.0, 1.12, 0.0), tilt, mats.wood_cedar_mat, 8)
	_add_cyl_xf(root, 0.05, 1.48, 0.44, tilt * Vector3(0.0, 2.18, 0.0), tilt, canopy_mat, 8)
	_add_cyl_xf(root, 0.055, 0.96, 0.28, tilt * Vector3(0.0, 2.26, 0.0), tilt, stripe_mat, 8)
	_add_cyl_xf(root, 0.06, 0.05, 0.12, tilt * Vector3(0.0, 2.44, 0.0), tilt, mats.wood_cedar_mat, 6)

	# Two cedar sun-lounger beach chairs flanking the umbrella, facing the ocean (+Z)
	for sx: float in [-1.05, 1.05]:
		var chair_b := Basis(Vector3.UP, -sx * 0.12)
		var base_p := Vector3(sx, 0.0, 0.22)
		_add_box_xf(root, base_p + Vector3(0.0, 0.30, 0.15), chair_b, Vector3(0.68, 0.07, 1.42), mats.wood_cedar_mat)
		_add_box_xf(root, base_p + Vector3(0.0, 0.35, 0.12), chair_b, Vector3(0.60, 0.05, 1.28), stripe_mat)
		# Reclined backrest
		var back_b := chair_b * Basis(Vector3.RIGHT, 0.56)
		_add_box_xf(root, base_p + chair_b * Vector3(0.0, 0.58, -0.68), back_b, Vector3(0.66, 0.07, 0.72), mats.wood_cedar_mat)
		_add_box_xf(root, base_p + chair_b * Vector3(0.0, 0.62, -0.65), back_b, Vector3(0.58, 0.05, 0.62), towel_mat)
		# Short legs
		for lz: float in [-0.42, 0.68]:
			_add_box_xf(root, base_p + chair_b * Vector3(0.0, 0.15, lz), chair_b, Vector3(0.62, 0.30, 0.06), mats.wood_door_mat)


static func _build_surfboard_rack(root: Node3D, variant: int, mats: MaterialLibrary) -> void:
	## Timber beach surfboard rack displaying 4 colorful angled coastal surfboards.
	var col_box := BoxShape3D.new()
	col_box.size = Vector3(2.2, 1.8, 0.9)
	_add_chunk_collider(root, col_box, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.9, 0.0)))

	# Timber rack frame
	_add_box(root, Vector3(2.20, 0.10, 0.86), Vector3(0.0, 0.05, 0.0), mats.wood_door_mat)
	for sx: float in [-1.02, 1.02]:
		_add_box(root, Vector3(0.10, 1.22, 0.10), Vector3(sx, 0.64, -0.22), mats.wood_cedar_mat)
	_add_box(root, Vector3(2.14, 0.09, 0.09), Vector3(0.0, 1.14, -0.22), mats.wood_cedar_mat)
	_add_box(root, Vector3(2.14, 0.09, 0.09), Vector3(0.0, 0.56, -0.22), mats.wood_cedar_mat)

	var board_cols := [
		Color(0.12, 0.66, 0.72),
		Color(0.92, 0.38, 0.24),
		Color(0.95, 0.78, 0.18),
		Color(0.94, 0.95, 0.97),
	]
	for bi in range(4):
		var bx := lerpf(-0.74, 0.74, float(bi) / 3.0)
		var bmat := mats.get_accent_material(board_cols[posmod(bi + variant, board_cols.size())])
		var bb := Basis(Vector3.RIGHT, -0.20) * Basis(Vector3.UP, 0.14 if bi % 2 == 0 else -0.14)
		_add_box_xf(root, Vector3(bx, 1.05, 0.02), bb, Vector3(0.36, 1.96, 0.065), bmat)
		_add_box_xf(root, Vector3(bx, 1.05, 0.058), bb, Vector3(0.07, 1.80, 0.015), mats.marking_white_mat)


static func _build_beach_palm(root: Node3D, scale_v: float, variant: int, mats: MaterialLibrary) -> void:
	## Sculpted curving coastal palm tree with ringed trunk, coconut cluster & arching frond crown.
	var s := clampf(scale_v, 0.78, 1.32)
	var col_cyl := CylinderShape3D.new()
	col_cyl.radius = 0.26 * s
	col_cyl.height = 4.2 * s
	_add_chunk_collider(root, col_cyl, Transform3D(Basis.IDENTITY, Vector3(0.0, 2.1 * s, 0.0)))

	var frond_dark := mats.get_accent_material(Color(0.16, 0.44, 0.18))
	var frond_bright := mats.get_accent_material(Color(0.24, 0.54, 0.22))
	var nut_mat := mats.wood_door_mat
	var lean_dir := float(variant) * 1.57
	var lean_amt := (0.14 + float(variant % 3) * 0.06) * s

	# 6 stacked subtly curving & tapering trunk segments
	var seg_h := 1.24 * s
	var cur := Vector3.ZERO
	var n_segs := 6
	for si in range(n_segs):
		var t0 := float(si) / float(n_segs)
		var t1 := float(si + 1) / float(n_segs)
		var next_p := Vector3(
			cos(lean_dir) * lean_amt * (t1 * t1) * 5.2,
			t1 * float(n_segs) * seg_h,
			sin(lean_dir) * lean_amt * (t1 * t1) * 5.2
		)
		var mid := (cur + next_p) * 0.5
		var up_v := (next_p - cur).normalized()
		var seg_len := cur.distance_to(next_p) + 0.10 * s
		var right_v := up_v.cross(Vector3.FORWARD)
		if right_v.length_squared() < 0.01:
			right_v = up_v.cross(Vector3.RIGHT)
		right_v = right_v.normalized()
		var fwd_v := right_v.cross(up_v).normalized()
		var seg_b := Basis(right_v, up_v, fwd_v)
		var r_bot := lerpf(0.28, 0.14, t0) * s
		var r_top := lerpf(0.26, 0.125, t1) * s
		_add_cyl_xf(root, r_top, r_bot, seg_len, mid, seg_b, mats.bark_mat, 7)
		cur = next_p

	# Cluster of coconuts nestled beneath the palm crown
	for ci in range(4):
		var ca := float(ci) * TAU * 0.25 + 0.4
		_add_cyl_xf(root, 0.09 * s, 0.11 * s, 0.24 * s, cur + Vector3(cos(ca) * 0.18 * s, -0.22 * s, sin(ca) * 0.18 * s), Basis.IDENTITY, nut_mat, 6)

	# 9 gracefully arching multi-segment palm fronds radiating from the crown
	var n_fronds := 9
	for fi in range(n_fronds):
		var fa := float(fi) * TAU / float(n_fronds) + float(variant) * 0.35
		var fmat := frond_bright if (fi % 2 == 0) else frond_dark
		var yaw_b := Basis(Vector3.UP, fa)
		var lift := 0.24 if (fi % 3 == 0) else -0.06
		# Inner rising petiole + mid arching blade + outer drooping frond tip
		var b1 := yaw_b * Basis(Vector3.RIGHT, -0.34 - lift)
		var p1 := cur + yaw_b * Vector3(0.0, 0.28 * s + lift * 0.4 * s, 0.72 * s)
		_add_box_xf(root, p1, b1, Vector3(0.56 * s, 0.06 * s, 1.55 * s), fmat)

		var b2 := yaw_b * Basis(Vector3.RIGHT, 0.14 - lift * 0.4)
		var p2 := cur + yaw_b * Vector3(0.0, 0.36 * s + lift * 0.55 * s, 2.02 * s)
		_add_box_xf(root, p2, b2, Vector3(0.74 * s, 0.05 * s, 1.48 * s), fmat)

		var b3 := yaw_b * Basis(Vector3.RIGHT, 0.68 - lift * 0.2)
		var p3 := cur + yaw_b * Vector3(0.0, -0.14 * s + lift * 0.35 * s, 3.04 * s)
		_add_box_xf(root, p3, b3, Vector3(0.46 * s, 0.04 * s, 1.18 * s), fmat)


static func _build_coral_reef_cluster(root: Node3D, scale_v: float, variant: int, mats: MaterialLibrary) -> void:
	## Sculpted underwater coral reef outcrop with subsea limestone boulders, branching staghorn coral,
	## fluted tube sponges, brain coral domes, and glowing bioluminescent sea anemones.
	var s := clampf(scale_v, 0.65, 1.45)
	var rock_mat := _mat_or(mats, "riprap_stone_mat", mats.bridge_concrete_mat)
	var coral_palette := [
		Color(0.92, 0.32, 0.44), # Reef coral pink
		Color(0.14, 0.78, 0.82), # Lagoon cyan-turquoise
		Color(0.95, 0.68, 0.16), # Golden sponge coral
		Color(0.62, 0.30, 0.86), # Amethyst sea fan violet
		Color(0.94, 0.44, 0.18), # Fire coral tangerine
	]
	var c_mat1 := mats.get_accent_material(coral_palette[posmod(variant, coral_palette.size())])
	var c_mat2 := mats.get_accent_material(coral_palette[posmod(variant + 2, coral_palette.size())])
	var c_mat3 := mats.get_accent_material(coral_palette[posmod(variant + 3, coral_palette.size())])

	# 1. Subsea reef rock base & ledges
	_add_cyl_xf(root, 0.95 * s, 1.35 * s, 0.46 * s, Vector3(0.0, 0.16 * s, 0.0), Basis.IDENTITY, rock_mat, 7)
	_add_cyl_xf(root, 0.62 * s, 0.88 * s, 0.54 * s, Vector3(0.55 * s, 0.22 * s, -0.35 * s), Basis(Vector3.RIGHT, 0.16), rock_mat, 6)
	_add_cyl_xf(root, 0.52 * s, 0.78 * s, 0.42 * s, Vector3(-0.62 * s, 0.18 * s, 0.42 * s), Basis(Vector3.FORWARD, -0.18), rock_mat, 6)

	# 2. Branching Staghorn Coral antlers & fluted tube coral clusters
	for bi in range(6):
		var ang := float(bi) * TAU / 6.0 + float(variant) * 0.4
		var rad := (0.28 + float(bi % 3) * 0.24) * s
		var bx := cos(ang) * rad
		var bz := sin(ang) * rad
		var h_branch := (0.58 + float(bi % 3) * 0.22) * s
		var tilt_b := Basis(Vector3.UP, ang) * Basis(Vector3.RIGHT, 0.26 + float(bi % 2) * 0.16)
		var b_mat := c_mat1 if (bi % 2 == 0) else c_mat2
		_add_cyl_xf(root, 0.065 * s, 0.11 * s, h_branch, Vector3(bx, 0.34 * s + h_branch * 0.42, bz), tilt_b, b_mat, 6)
		# Upper forked coral tine + glowing bioluminescent polyp tip
		var fork_b := tilt_b * Basis(Vector3.FORWARD, 0.42 if bi % 2 == 0 else -0.42)
		var fork_p := Vector3(bx, 0.34 * s + h_branch * 0.72, bz) + fork_b * Vector3(0.0, h_branch * 0.36, 0.0)
		_add_cyl_xf(root, 0.045 * s, 0.07 * s, h_branch * 0.62, fork_p, fork_b, b_mat, 6)
		_add_box(root, Vector3(0.11 * s, 0.11 * s, 0.11 * s), fork_p + fork_b * Vector3(0.0, h_branch * 0.32, 0.0), mats.ev_glow_mat if bi % 2 == 0 else mats.lamp_glow_mat)

	# 3. Dome-shaped Brain Coral & planar Sea Fan blades
	_add_cyl_xf(root, 0.28 * s, 0.46 * s, 0.36 * s, Vector3(-0.28 * s, 0.42 * s, -0.22 * s), Basis.IDENTITY, c_mat3, 8)
	var fan_b := Basis(Vector3.UP, float(variant) * 0.9) * Basis(Vector3.RIGHT, 0.22)
	_add_box_xf(root, Vector3(0.32 * s, 0.68 * s, 0.28 * s), fan_b, Vector3(0.78 * s, 0.68 * s, 0.05 * s), c_mat2)


static func _build_underwater_kelp(root: Node3D, scale_v: float, variant: int, mats: MaterialLibrary) -> void:
	## Tall multi-stalk underwater kelp & seaweed cluster with alternating leafy kelp blades.
	var s := clampf(scale_v, 0.40, 1.40)
	var kelp_dark := mats.get_accent_material(Color(0.10, 0.38, 0.20))
	var kelp_light := mats.get_accent_material(Color(0.18, 0.52, 0.26))
	var rock_mat := _mat_or(mats, "riprap_stone_mat", mats.bridge_concrete_mat)

	# Small holdfast anchor rock at base
	_add_cyl_xf(root, 0.28 * s, 0.44 * s, 0.22 * s, Vector3(0.0, 0.08 * s, 0.0), Basis.IDENTITY, rock_mat, 6)

	var stalk_offsets := [
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.42 * s, 0.0, 0.28 * s),
		Vector3(-0.38 * s, 0.0, 0.34 * s),
		Vector3(0.18 * s, 0.0, -0.44 * s),
	]
	for st_i in range(stalk_offsets.size()):
		var base_off: Vector3 = stalk_offsets[st_i]
		var stalk_h := (2.1 - float(st_i) * 0.24) * s
		var n_segs := 4
		var seg_h := stalk_h / float(n_segs)
		var cur := base_off + Vector3(0.0, 0.12 * s, 0.0)
		var kmat := kelp_light if (st_i % 2 == 0) else kelp_dark
		for si in range(n_segs):
			var t1 := float(si + 1) / float(n_segs)
			var sway_x := sin(float(variant + st_i) * 1.7 + t1 * 2.6) * 0.26 * s
			var sway_z := cos(float(variant * 2 + st_i) * 1.3 + t1 * 2.2) * 0.24 * s
			var next_p := base_off + Vector3(sway_x, 0.12 * s + t1 * stalk_h, sway_z)
			var mid := (cur + next_p) * 0.5
			var seg_b := Basis(Vector3.UP, float(si + st_i) * 1.1) * Basis(Vector3.RIGHT, (next_p.z - cur.z) / maxf(0.1, seg_h))
			_add_cyl_xf(root, 0.035 * s, 0.055 * s, seg_h + 0.05 * s, mid, seg_b, kmat, 6)
			# Pair of ribboned kelp blades branching off each segment
			for side_s: float in [-1.0, 1.0]:
				var blade_b := Basis(Vector3.UP, float(si) * 1.35 + side_s * 1.1 + float(st_i)) * Basis(Vector3.RIGHT, 0.38)
				var blade_p := mid + blade_b * Vector3(0.0, 0.04 * s, 0.28 * s)
				_add_box_xf(root, blade_p, blade_b, Vector3(0.16 * s, 0.025 * s, 0.58 * s), kelp_light if si % 2 == 0 else kelp_dark)
			cur = next_p
