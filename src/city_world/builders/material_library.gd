class_name MaterialLibrary
extends RefCounted

## Shared material library for 2028 grounded architecture, roads, terrain, and street props.

const SHADER_DIR := "res://src/city_world/shaders/"

const STYLE_MODES := {
	"historic_brick": 0,
	"contemporary_2028": 1,
	"suburban_siding": 2,
	"industrial_steel": 3,
}

var terrain_mat: Material
var water_mat: Material
var ocean_water_mat: Material
var asphalt_mat: Material
var sidewalk_mat: Material
var walkway_mat: Material
var boardwalk_wood_mat: Material
var marking_white_mat: Material
var marking_yellow_mat: Material
var bridge_concrete_mat: Material
var foundation_mat: Material
var limestone_mat: Material
var dark_metal_mat: Material
var light_metal_mat: Material
var gold_metal_mat: Material
var glass_dark_mat: Material
var glass_warm_mat: Material
var clear_glass_mat: Material
var stained_glass_mat: Material
var solar_panel_mat: Material
var roof_shingle_mat: Material
var roof_membrane_mat: Material
var wood_door_mat: Material
var vestibule_wall_mat: Material
var vestibule_floor_mat: Material
var interior_drywall_mat: Material
var interior_floor_wood_mat: Material
var interior_floor_tile_mat: Material
var interior_stair_mat: Material
var interior_furniture_wood_mat: Material
var interior_furniture_fabric_mat: Material
var interior_ceiling_light_mat: Material
var bark_mat: Material
var soil_mulch_mat: Material
var flora_blossom_mat: Material
var foliage_mat: Material
var grass_mat: Material
var ev_glow_mat: Material
var ev_headlight_mat: Material
var ev_taillight_mat: Material
var signal_green_mat: Material
var signal_amber_mat: Material
var lamp_glow_mat: Material
var bollard_glow_mat: Material
var police_blue_mat: Material
var emergency_red_mat: Material
var sign_panel_mat: Material
var aviation_beacon_mat: Material
var street_sign_green_mat: Material
var hydrant_red_mat: Material
var mailbox_blue_mat: Material
var billboard_display_mat: Material
var kiosk_display_mat: Material
var ada_tactile_mat: Material
var fountain_water_mat: Material
var wood_cedar_mat: Material
var court_teal_mat: Material
var court_clay_mat: Material
var umbrella_crimson_mat: Material
var medical_teal_mat: Material
var elevator_steel_mat: Material
var riprap_stone_mat: Material
var reed_mat: Material
var dumpster_green_mat: Material
var safety_yellow_mat: Material
var pallet_wood_mat: Material
var driveway_concrete_mat: Material
var chainlink_fence_mat: Material

var _wall_cache: Dictionary = {}
var _accent_cache: Dictionary = {}
var _decal_cache: Dictionary = {}
var _emissive_accents: Array[StandardMaterial3D] = []
var _car_mats: Array[Material] = []
var _shader_cache: Dictionary = {}
var _leaf_tex: ImageTexture = null


func _init() -> void:
	terrain_mat = _make_shader_mat("terrain_triplanar.gdshader", {
		"water_level": 1.6,
		"detail_strength": 0.22,
	})

	water_mat = _make_shader_mat("creek_water.gdshader", {
		"shallow_color": Color(0.12, 0.46, 0.50),
		"deep_color": Color(0.03, 0.14, 0.22),
		"sky_reflect_color": Color(0.56, 0.74, 0.90),
		"flow_speed": 0.58,
	})

	ocean_water_mat = _make_shader_mat("ocean_water.gdshader", {
		"shallow_color": Color(0.04, 0.44, 0.48),
		"mid_color": Color(0.018, 0.20, 0.36),
		"deep_color": Color(0.008, 0.055, 0.14),
		"sky_reflect_color": Color(0.58, 0.77, 0.94),
	})

	asphalt_mat = _make_shader_mat("asphalt_road.gdshader", {
		"asphalt_base": Color(0.16, 0.17, 0.19),
	})

	sidewalk_mat = _make_shader_mat("concrete_scored.gdshader", {
		"base_color": Color(0.71, 0.71, 0.68),
		"joint_spacing": 1.8,
		"joint_strength": 0.28,
		"roughness_base": 0.86,
	})

	walkway_mat = _make_shader_mat("concrete_scored.gdshader", {
		"base_color": Color(0.76, 0.70, 0.61),
		"joint_spacing": 1.15,
		"joint_strength": 0.34,
		"roughness_base": 0.88,
	})

	boardwalk_wood_mat = _make_shader_mat("concrete_scored.gdshader", {
		"base_color": Color(0.62, 0.50, 0.37),
		"joint_spacing": 0.32,
		"joint_strength": 0.38,
		"roughness_base": 0.84,
	})

	limestone_mat = _make_shader_mat("concrete_scored.gdshader", {
		"base_color": Color(0.87, 0.85, 0.79),
		"joint_spacing": 2.2,
		"joint_strength": 0.22,
		"roughness_base": 0.78,
	})

	marking_white_mat = _make_standard_mat(Color(0.92, 0.92, 0.89), 0.75)
	marking_yellow_mat = _make_standard_mat(Color(0.90, 0.68, 0.18), 0.75)

	bridge_concrete_mat = _make_shader_mat("concrete_scored.gdshader", {
		"base_color": Color(0.58, 0.59, 0.60),
		"joint_spacing": 3.0,
		"joint_strength": 0.20,
		"roughness_base": 0.84,
	})

	foundation_mat = _make_shader_mat("concrete_scored.gdshader", {
		"base_color": Color(0.36, 0.37, 0.38),
		"joint_spacing": 2.4,
		"joint_strength": 0.18,
		"roughness_base": 0.90,
	})

	dark_metal_mat = _make_standard_mat(Color(0.18, 0.20, 0.23), 0.42, 0.65)
	light_metal_mat = _make_standard_mat(Color(0.72, 0.75, 0.78), 0.38, 0.55)
	gold_metal_mat = _make_standard_mat(Color(0.88, 0.74, 0.36), 0.28, 0.85)
	stained_glass_mat = _make_shader_mat("stained_glass.gdshader", {})

	glass_dark_mat = _make_shader_mat("architectural_glass.gdshader", {
		"glass_tint": Color(0.08, 0.14, 0.21),
		"interior_light_color": Color(0.78, 0.84, 0.90),
		"interior_glow": 0.14,
		"reflection_strength": 0.76,
	})

	glass_warm_mat = _make_shader_mat("architectural_glass.gdshader", {
		"glass_tint": Color(0.12, 0.16, 0.20),
		"interior_light_color": Color(0.95, 0.78, 0.50),
		"interior_glow": 0.55,
		"reflection_strength": 0.64,
	})

	solar_panel_mat = _make_shader_mat("solar_panel.gdshader", {
		"silicon_color": Color(0.06, 0.10, 0.22),
		"grid_color": Color(0.70, 0.76, 0.84),
	})

	roof_shingle_mat = _make_shader_mat("roof_shingle.gdshader", {
		"base_color": Color(0.27, 0.24, 0.22),
	})

	roof_membrane_mat = _make_shader_mat("concrete_scored.gdshader", {
		"base_color": Color(0.46, 0.47, 0.49),
		"joint_spacing": 3.2,
		"joint_strength": 0.16,
		"roughness_base": 0.86,
	})
	wood_door_mat = _make_standard_mat(Color(0.40, 0.24, 0.15), 0.68)
	vestibule_wall_mat = _make_standard_mat(Color(0.86, 0.84, 0.79), 0.82)
	vestibule_floor_mat = _make_standard_mat(Color(0.42, 0.40, 0.38), 0.65)
	clear_glass_mat = _make_clear_glass_mat()
	interior_drywall_mat = _make_standard_mat(Color(0.89, 0.87, 0.83), 0.88)
	interior_floor_wood_mat = _make_standard_mat(Color(0.54, 0.38, 0.25), 0.62)
	interior_floor_tile_mat = _make_standard_mat(Color(0.67, 0.68, 0.66), 0.44)
	interior_stair_mat = _make_standard_mat(Color(0.35, 0.30, 0.27), 0.70)
	interior_furniture_wood_mat = _make_standard_mat(Color(0.42, 0.28, 0.17), 0.58)
	interior_furniture_fabric_mat = _make_standard_mat(Color(0.27, 0.35, 0.43), 0.84)
	interior_ceiling_light_mat = _make_standard_mat(Color(0.98, 0.96, 0.90), 0.35, 0.0, Color(1.0, 0.95, 0.86), 1.5)
	bark_mat = _make_shader_mat("wood_bark.gdshader", {
		"bark_dark": Color(0.14, 0.10, 0.08),
		"bark_ridge": Color(0.34, 0.25, 0.18),
		"moss_tint": Color(0.18, 0.30, 0.15),
		"wind_strength": 0.07,
	})

	_leaf_tex = _build_leaf_cluster_texture()
	foliage_mat = _make_shader_mat("foliage_wind.gdshader", {
		"leaf_atlas": _leaf_tex,
		"leaf_dark": Color(0.11, 0.27, 0.10),
		"leaf_bright": Color(0.28, 0.50, 0.19),
		"canopy_center": Vector3(0.0, 2.95, 0.0),
		"spherical_blend": 0.84,
		"alpha_scissor": 0.42,
		"wind_strength": 0.07,
	})

	grass_mat = _make_shader_mat("grass_wind.gdshader", {
		"grass_base": Color(0.22, 0.36, 0.16),
		"grass_tip": Color(0.34, 0.49, 0.22),
		"grass_dry": Color(0.42, 0.46, 0.24),
		"wind_strength": 0.09,
	})
	soil_mulch_mat = _make_shader_mat("concrete_scored.gdshader", {
		"base_color": Color(0.18, 0.13, 0.09),
		"joint_spacing": 0.42,
		"joint_strength": 0.16,
		"roughness_base": 0.94,
	})
	flora_blossom_mat = _make_shader_mat("flora_blossom.gdshader", {})

	ev_glow_mat = _make_shader_mat("digital_display.gdshader", {
		"bg_color": Color(0.03, 0.05, 0.08),
		"glow_primary": Color(0.10, 0.90, 0.72),
		"glow_accent": Color(0.26, 0.65, 1.00),
	})
	signal_green_mat = _make_standard_mat(Color(0.15, 0.92, 0.36), 0.45, 0.0, Color(0.15, 0.92, 0.36), 1.5)
	signal_amber_mat = _make_standard_mat(Color(0.95, 0.65, 0.12), 0.45, 0.0, Color(0.95, 0.65, 0.12), 1.1)
	lamp_glow_mat = _make_standard_mat(Color(0.98, 0.94, 0.84), 0.38, 0.0, Color(1.0, 0.88, 0.66), 0.25)
	bollard_glow_mat = _make_standard_mat(Color(1.0, 0.92, 0.78), 0.35, 0.0, Color(1.0, 0.84, 0.52), 0.30)
	police_blue_mat = _make_standard_mat(Color(0.08, 0.24, 0.58), 0.36, 0.15, Color(0.16, 0.48, 1.00), 0.35)
	emergency_red_mat = _make_standard_mat(Color(0.78, 0.12, 0.12), 0.34, 0.18, Color(0.96, 0.18, 0.14), 0.30)
	ev_headlight_mat = _make_standard_mat(Color(0.94, 0.97, 1.00), 0.25, 0.0, Color(0.88, 0.94, 1.00), 0.35)
	ev_taillight_mat = _make_standard_mat(Color(0.85, 0.14, 0.12), 0.28, 0.0, Color(1.0, 0.18, 0.14), 0.30)
	sign_panel_mat = _make_standard_mat(Color(0.97, 0.98, 1.00), 0.28, 0.05, Color(0.95, 0.96, 1.00), 0.30)
	aviation_beacon_mat = _make_standard_mat(Color(0.92, 0.14, 0.12), 0.25, 0.10, Color(1.0, 0.16, 0.12), 1.6)
	street_sign_green_mat = _make_standard_mat(Color(0.08, 0.36, 0.20), 0.36, 0.08, Color(0.10, 0.42, 0.24), 0.06)
	hydrant_red_mat = _make_standard_mat(Color(0.76, 0.14, 0.12), 0.38, 0.16)
	mailbox_blue_mat = _make_standard_mat(Color(0.12, 0.28, 0.56), 0.42, 0.18)
	billboard_display_mat = _make_shader_mat("digital_display.gdshader", {
		"bg_color": Color(0.04, 0.07, 0.12),
		"glow_primary": Color(0.18, 0.78, 1.00),
		"glow_accent": Color(0.96, 0.48, 0.18),
	})
	kiosk_display_mat = _make_shader_mat("digital_display.gdshader", {
		"bg_color": Color(0.03, 0.06, 0.09),
		"glow_primary": Color(0.14, 0.88, 0.76),
		"glow_accent": Color(0.28, 0.68, 1.00),
	})
	ada_tactile_mat = _make_shader_mat("concrete_scored.gdshader", {
		"base_color": Color(0.92, 0.74, 0.14),
		"joint_spacing": 0.09,
		"joint_strength": 0.42,
		"roughness_base": 0.72,
	})
	fountain_water_mat = _make_shader_mat("fountain_water.gdshader", {
		"water_tint": Color(0.12, 0.50, 0.62),
		"foam_tint": Color(0.86, 0.95, 0.99),
	})
	wood_cedar_mat = _make_standard_mat(Color(0.46, 0.29, 0.17), 0.76)
	court_teal_mat = _make_standard_mat(Color(0.15, 0.39, 0.36), 0.78)
	court_clay_mat = _make_standard_mat(Color(0.62, 0.29, 0.20), 0.80)
	umbrella_crimson_mat = _make_standard_mat(Color(0.76, 0.20, 0.16), 0.84)
	medical_teal_mat = _make_standard_mat(Color(0.12, 0.54, 0.56), 0.52, 0.08)
	elevator_steel_mat = _make_standard_mat(Color(0.64, 0.67, 0.71), 0.30, 0.78)
	riprap_stone_mat = _make_shader_mat("concrete_scored.gdshader", {
		"base_color": Color(0.42, 0.41, 0.38),
		"joint_spacing": 0.48,
		"joint_strength": 0.24,
		"roughness_base": 0.90,
	})
	var reed_m := _make_standard_mat(Color(0.95, 0.98, 0.92), 0.78)
	reed_m.vertex_color_use_as_albedo = true
	reed_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	reed_m.backlight_enabled = true
	reed_m.backlight = Color(0.28, 0.36, 0.15)
	reed_mat = reed_m
	dumpster_green_mat = _make_standard_mat(Color(0.14, 0.29, 0.20), 0.56, 0.22)
	safety_yellow_mat = _make_standard_mat(Color(0.92, 0.72, 0.10), 0.42, 0.15)
	pallet_wood_mat = _make_standard_mat(Color(0.58, 0.43, 0.26), 0.86, 0.0)
	driveway_concrete_mat = _make_shader_mat("concrete_scored.gdshader", {
		"base_color": Color(0.62, 0.62, 0.60),
		"joint_spacing": 2.1,
		"joint_strength": 0.22,
		"roughness_base": 0.88,
	})
	chainlink_fence_mat = _make_standard_mat(Color(0.48, 0.52, 0.55), 0.48, 0.72)

	for c in [
		Color(0.84, 0.86, 0.89),
		Color(0.16, 0.24, 0.34),
		Color(0.55, 0.18, 0.18),
		Color(0.25, 0.34, 0.30),
	]:
		_car_mats.append(_make_shader_mat("car_paint.gdshader", {
			"facing_color": c,
			"glancing_color": c * Color(0.42, 0.48, 0.56),
		}))


func get_wall_material(_color: Color, style: String) -> Material:
	var mode: int = STYLE_MODES.get(style, 1)
	var key := str(mode)
	if _wall_cache.has(key):
		return _wall_cache[key]
	var m := _make_shader_mat("building_facade.gdshader", {
		"style_mode": mode,
	})
	_wall_cache[key] = m
	return m


func get_decal_textures(kind: String) -> Dictionary:
	var k := kind.to_lower().strip_edges()
	if not k in ["oil_stain", "drain_rust", "alley_grime", "sidewalk_crack"]:
		k = "alley_grime"
	if _decal_cache.has(k):
		return _decal_cache[k]
	var pair := _build_decal_texture_pair(k)
	_decal_cache[k] = pair
	return pair


func get_accent_material(color: Color, emissive: bool = false) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f_%.2f" % [str(emissive), color.r, color.g, color.b]
	if _accent_cache.has(key):
		return _accent_cache[key]
	var m := _make_standard_mat(color, 0.36 if emissive else 0.45, 0.06 if emissive else 0.0, color, 0.48 if emissive else 0.0)
	_accent_cache[key] = m
	if emissive:
		_emissive_accents.append(m)
	return m


func get_car_material(variant: int) -> Material:
	return _car_mats[posmod(variant, _car_mats.size())]


func set_time_of_day_emissives(night_factor: float, rain: float) -> void:
	var street_e := lerpf(0.08, 4.4, maxf(night_factor, rain * 0.45))
	var vehicle_e := lerpf(0.25, 3.6, maxf(night_factor, rain * 0.70))
	var lamp_m := lamp_glow_mat as StandardMaterial3D
	if lamp_m != null:
		lamp_m.emission_energy_multiplier = street_e
	var bollard_m := bollard_glow_mat as StandardMaterial3D
	if bollard_m != null:
		bollard_m.emission_energy_multiplier = lerpf(0.12, 2.85, maxf(night_factor, rain * 0.45))
	var pol_m := police_blue_mat as StandardMaterial3D
	if pol_m != null:
		pol_m.emission_energy_multiplier = lerpf(0.25, 1.95, maxf(night_factor, rain * 0.40))
	var emg_m := emergency_red_mat as StandardMaterial3D
	if emg_m != null:
		emg_m.emission_energy_multiplier = lerpf(0.22, 1.80, maxf(night_factor, rain * 0.40))
	var head_m := ev_headlight_mat as StandardMaterial3D
	if head_m != null:
		head_m.emission_energy_multiplier = vehicle_e
	var tail_m := ev_taillight_mat as StandardMaterial3D
	if tail_m != null:
		tail_m.emission_energy_multiplier = vehicle_e * 0.9
	var ceil_m := interior_ceiling_light_mat as StandardMaterial3D
	if ceil_m != null:
		ceil_m.emission_energy_multiplier = lerpf(1.35, 2.25, night_factor)
	var sign_panel_m := sign_panel_mat as StandardMaterial3D
	if sign_panel_m != null:
		sign_panel_m.emission_energy_multiplier = lerpf(0.24, 1.55, maxf(night_factor, rain * 0.45))
	var beacon_m := aviation_beacon_mat as StandardMaterial3D
	if beacon_m != null:
		beacon_m.emission_energy_multiplier = lerpf(1.2, 4.2, night_factor)
	var ssign_m := street_sign_green_mat as StandardMaterial3D
	if ssign_m != null:
		ssign_m.emission_energy_multiplier = lerpf(0.04, 0.35, night_factor)
	var accent_sign_e := lerpf(0.30, 1.75, maxf(night_factor, rain * 0.45))
	for am in _emissive_accents:
		am.emission_energy_multiplier = accent_sign_e


static func _build_leaf_cluster_texture() -> ImageTexture:
	const SZ := 128
	var img := Image.create_empty(SZ, SZ, false, Image.FORMAT_RGBA8)
	# Deterministic botanical sprig of pointed broadleaf ovals (center x, y, length, width, angle)
	var leaves := [
		[0.50, 0.14, 0.11, 0.055, 0.0, 1.00],
		[0.37, 0.20, 0.10, 0.050, -0.62, 0.94],
		[0.63, 0.20, 0.10, 0.050, 0.62, 0.95],
		[0.24, 0.30, 0.11, 0.055, -0.95, 0.88],
		[0.76, 0.30, 0.11, 0.055, 0.95, 0.90],
		[0.44, 0.29, 0.10, 0.052, -0.25, 1.04],
		[0.57, 0.29, 0.10, 0.052, 0.25, 1.02],
		[0.18, 0.45, 0.11, 0.056, -1.25, 0.84],
		[0.82, 0.45, 0.11, 0.056, 1.25, 0.86],
		[0.33, 0.42, 0.11, 0.054, -0.70, 0.92],
		[0.67, 0.42, 0.11, 0.054, 0.70, 0.93],
		[0.50, 0.44, 0.10, 0.055, 0.05, 1.00],
		[0.22, 0.60, 0.11, 0.055, -1.10, 0.84],
		[0.78, 0.60, 0.11, 0.055, 1.10, 0.85],
		[0.39, 0.56, 0.10, 0.052, -0.42, 0.96],
		[0.61, 0.56, 0.10, 0.052, 0.42, 0.97],
		[0.30, 0.72, 0.11, 0.054, -0.85, 0.82],
		[0.70, 0.72, 0.11, 0.054, 0.85, 0.84],
		[0.48, 0.68, 0.10, 0.054, -0.15, 0.95],
		[0.54, 0.78, 0.10, 0.050, 0.35, 0.88],
		[0.40, 0.83, 0.09, 0.048, -0.58, 0.80],
		[0.63, 0.84, 0.09, 0.048, 0.72, 0.82],
	]
	for py in range(SZ):
		var v := (float(py) + 0.5) / float(SZ)
		for px in range(SZ):
			var u := (float(px) + 0.5) / float(SZ)
			var best_a := 0.0
			var best_shade := 0.9
			for ld in leaves:
				var dx := u - float(ld[0])
				var dy := v - float(ld[1])
				var ang := float(ld[4])
				var ca := cos(ang)
				var sa := sin(ang)
				var lx := dx * ca + dy * sa
				var ly := -dx * sa + dy * ca
				# Taper width slightly toward tip to form almond leaf shape
				var norm_y := ly / float(ld[2])
				var taper := maxf(0.25, 1.0 - maxf(0.0, -norm_y) * 0.45)
				var dist := sqrt((lx / (float(ld[3]) * taper)) * (lx / (float(ld[3]) * taper)) + norm_y * norm_y)
				if dist < 1.08:
					var edge_a := clampf((1.05 - dist) / 0.16, 0.0, 1.0)
					if edge_a > best_a:
						best_a = edge_a
						var vein := 1.0 - 0.12 * exp(-absf(lx) * 55.0)
						best_shade = float(ld[5]) * vein
			# Stem line connecting cluster base
			if v > 0.25 and v < 0.92 and absf(u - 0.5) < 0.018:
				best_a = maxf(best_a, 1.0)
				best_shade = minf(best_shade, 0.62)
			var g_var := best_shade
			img.set_pixel(px, py, Color(g_var * 0.90, g_var, g_var * 0.86, best_a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _load_shader(shader_name: String) -> Shader:
	if _shader_cache.has(shader_name):
		return _shader_cache[shader_name]
	var shader: Shader = load(SHADER_DIR + shader_name)
	_shader_cache[shader_name] = shader
	return shader


func _make_shader_mat(shader_name: String, params: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _load_shader(shader_name)
	for param_name in params.keys():
		mat.set_shader_parameter(param_name, params[param_name])
	return mat


func _make_clear_glass_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.82, 0.91, 0.97, 0.22)
	mat.roughness = 0.08
	mat.metallic = 0.08
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _make_standard_mat(
		color: Color,
		roughness: float,
		metallic: float = 0.0,
		emission: Color = Color.BLACK,
		emission_energy: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	return mat


static func _decal_hash(x: int, y: int, seed_v: int) -> float:
	var n := (x * 374761393 + y * 668265263 + seed_v * 1442695041) & 0x7fffffff
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xFFFF) / 65535.0


static func _decal_noise(u: float, v: float, freq: float, seed_v: int) -> float:
	var x := u * freq
	var y := v * freq
	var ix := int(floor(x))
	var iy := int(floor(y))
	var fx := x - float(ix)
	var fy := y - float(iy)
	var sx := fx * fx * (3.0 - 2.0 * fx)
	var sy := fy * fy * (3.0 - 2.0 * fy)
	var a := _decal_hash(ix, iy, seed_v)
	var b := _decal_hash(ix + 1, iy, seed_v)
	var c := _decal_hash(ix, iy + 1, seed_v)
	var d := _decal_hash(ix + 1, iy + 1, seed_v)
	return lerpf(lerpf(a, b, sx), lerpf(c, d, sx), sy)


static func _build_decal_texture_pair(kind: String) -> Dictionary:
	const SZ := 64
	var alb_img := Image.create_empty(SZ, SZ, false, Image.FORMAT_RGBA8)
	var orm_img := Image.create_empty(SZ, SZ, false, Image.FORMAT_RGB8)
	var seed_v := 101
	if kind == "drain_rust":
		seed_v = 203
	elif kind == "alley_grime":
		seed_v = 307
	elif kind == "sidewalk_crack":
		seed_v = 409

	for py in range(SZ):
		var v := (float(py) + 0.5) / float(SZ)
		for px in range(SZ):
			var u := (float(px) + 0.5) / float(SZ)
			var dx := (u - 0.5) * 2.0
			var dy := (v - 0.5) * 2.0
			var r := sqrt(dx * dx + dy * dy)
			var edge := clampf(1.0 - maxf(0.0, (r - 0.42) / 0.52), 0.0, 1.0)
			edge = edge * edge * (3.0 - 2.0 * edge)

			var n0 := _decal_noise(u, v, 5.5, seed_v)
			var n1 := _decal_noise(u, v, 13.0, seed_v + 17)
			var fbm := n0 * 0.65 + n1 * 0.35

			var col := Color(0.08, 0.08, 0.09, 0.0)
			var ao := 1.0
			var rough := 0.85
			var metal := 0.0

			if kind == "oil_stain":
				var mask := clampf((fbm - 0.34) / 0.42, 0.0, 1.0) * edge
				col = Color(0.05, 0.055, 0.07, mask * 0.78)
				ao = lerpf(1.0, 0.58, mask)
				rough = lerpf(0.88, 0.14, mask)
				metal = mask * 0.12
			elif kind == "drain_rust":
				var ring := exp(-absf(r - 0.42) * 5.2)
				var streak := _decal_noise(u * 1.6, v * 0.65, 8.0, seed_v + 31)
				var mask := clampf((ring * 0.65 + fbm * 0.55 - 0.32) / 0.5, 0.0, 1.0) * edge
				col = Color(0.24 + streak * 0.12, 0.13 + streak * 0.04, 0.07, mask * 0.76)
				ao = lerpf(1.0, 0.46, mask)
				rough = lerpf(0.90, 0.40, mask)
			elif kind == "alley_grime":
				var mask := clampf((fbm - 0.30) / 0.48, 0.0, 1.0) * edge
				col = Color(0.09, 0.085, 0.075, mask * 0.80)
				ao = lerpf(1.0, 0.42, mask)
				rough = lerpf(0.88, 0.36, mask)
			else: # sidewalk_crack
				var warp := (n0 - 0.5) * 0.24
				var d_main := absf(dy - warp)
				var d_branch := absf(dx * 0.55 - dy + 0.18 + (n1 - 0.5) * 0.18)
				var crack_line := clampf(1.0 - minf(d_main, d_branch) / 0.055, 0.0, 1.0) * edge
				var stain := clampf((fbm - 0.48) / 0.4, 0.0, 1.0) * edge * 0.35
				var mask := clampf(crack_line * 0.85 + stain, 0.0, 0.90)
				col = Color(0.11, 0.11, 0.10, mask)
				ao = lerpf(1.0, 0.32, crack_line)
				rough = lerpf(0.84, 0.96, mask)

			alb_img.set_pixel(px, py, col)
			orm_img.set_pixel(px, py, Color(ao, rough, metal, 1.0))

	alb_img.generate_mipmaps()
	orm_img.generate_mipmaps()
	return {
		"albedo": ImageTexture.create_from_image(alb_img),
		"orm": ImageTexture.create_from_image(orm_img),
	}
