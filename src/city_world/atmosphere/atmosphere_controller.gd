class_name AtmosphereController
extends Node3D

## Milestone 3 Atmosphere, 24-Hour Day/Night Cycle & Weather Controller.
## Syncs global shader parameters, sky scattering, directional Sun/Moon orbits,
## pooled shadowless night streetlamps, OBB-excluded GPU rain, and surface wetness.

const SKY_SHADER_PATH := "res://src/city_world/shaders/sky_atmosphere.gdshader"
const RAIN_PARTICLE_SHADER_PATH := "res://src/city_world/shaders/rain_particles.gdshader"
const RAIN_STREAK_SHADER_PATH := "res://src/city_world/shaders/rain_streak.gdshader"
const RAIN_SPLASH_SHADER_PATH := "res://src/city_world/shaders/rain_splash.gdshader"
const SNOW_PARTICLE_SHADER_PATH := "res://src/city_world/shaders/snow_particles.gdshader"
const SNOW_FLAKE_SHADER_PATH := "res://src/city_world/shaders/snow_flake.gdshader"

const STREETLIGHT_POOL_SIZE := 18
const RAIN_PARTICLE_COUNT := 2600
const SNOW_PARTICLE_COUNT := 2400
const SPLASH_COUNT := 220

const TIME_PRESETS: Array[Dictionary] = [
	{"name": "Morning", "hour": 10.5},
	{"name": "Golden Hour", "hour": 18.2},
	{"name": "Dusk", "hour": 19.6},
	{"name": "Night", "hour": 23.2},
	{"name": "Dawn", "hour": 6.1},
]

const WEATHER_ORDER: Array[String] = [
	"clear",
	"partly_cloudy",
	"fog",
	"overcast",
	"drizzle",
	"rain",
	"thunderstorm",
	"sleet",
	"snow",
	"blizzard",
]

const WEATHER_PARAMS: Dictionary = {
	"clear": {"label": "Clear", "cloud": 0.10, "rain": 0.0, "snow": 0.0, "wind": 0.65, "angle_deg": 28.0, "fog_mult": 0.70, "fog_boost": 0.0},
	"partly_cloudy": {"label": "Partly Cloudy", "cloud": 0.42, "rain": 0.0, "snow": 0.0, "wind": 0.95, "angle_deg": 32.0, "fog_mult": 0.92, "fog_boost": 0.0},
	"fog": {"label": "Coastal Fog", "cloud": 0.68, "rain": 0.0, "snow": 0.0, "wind": 0.45, "angle_deg": 22.0, "fog_mult": 8.5, "fog_boost": 0.92},
	"overcast": {"label": "Overcast", "cloud": 0.78, "rain": 0.0, "snow": 0.0, "wind": 1.35, "angle_deg": 40.0, "fog_mult": 2.30, "fog_boost": 0.15},
	"drizzle": {"label": "Light Drizzle", "cloud": 0.84, "rain": 0.34, "snow": 0.0, "wind": 1.25, "angle_deg": 42.0, "fog_mult": 3.4, "fog_boost": 0.32},
	"rain": {"label": "Rain", "cloud": 0.90, "rain": 0.78, "snow": 0.0, "wind": 1.95, "angle_deg": 48.0, "fog_mult": 4.2, "fog_boost": 0.28},
	"thunderstorm": {"label": "Thunderstorm", "cloud": 0.97, "rain": 1.0, "snow": 0.0, "wind": 2.85, "angle_deg": 56.0, "fog_mult": 6.0, "fog_boost": 0.40},
	"sleet": {"label": "Freezing Sleet", "cloud": 0.92, "rain": 0.42, "snow": 0.48, "wind": 2.05, "angle_deg": 52.0, "fog_mult": 5.2, "fog_boost": 0.42},
	"snow": {"label": "Snowfall", "cloud": 0.88, "rain": 0.0, "snow": 0.76, "wind": 1.45, "angle_deg": 38.0, "fog_mult": 4.8, "fog_boost": 0.45},
	"blizzard": {"label": "Blizzard", "cloud": 0.98, "rain": 0.0, "snow": 1.0, "wind": 3.10, "angle_deg": 62.0, "fog_mult": 8.8, "fog_boost": 0.88},
}

@export var time_of_day_hour: float = 10.5
@export var time_scale: float = 0.035 # Game hours per real second (~11.4m full 24h cycle)
@export var time_paused: bool = false

var weather_preset: String = "partly_cloudy"
var weather_cloud_cover: float = 0.42
var weather_rain: float = 0.0
var weather_wetness: float = 0.0
var weather_puddles: float = 0.0
var weather_lightning: float = 0.0
var weather_snow: float = 0.0
var weather_snow_depth: float = 0.0
var weather_slush: float = 0.0
var wind_vector: Vector2 = Vector2(0.81, 0.50)
var night_factor: float = 0.0
var sun_elevation: float = 0.65
var sun_direction: Vector3 = Vector3(0.42, 0.72, -0.34)

var world_env: WorldEnvironment = null
var sun_light: DirectionalLight3D = null
var moon_light: DirectionalLight3D = null
var city_world: CityWorld = null
var camera_target: Node3D = null

var _sky_mat: ShaderMaterial = null
var _rain_particles: GPUParticles3D = null
var _rain_process_mat: ShaderMaterial = null
var _snow_particles: GPUParticles3D = null
var _snow_process_mat: ShaderMaterial = null
var _splash_mmi: MultiMeshInstance3D = null
var _splash_phases: PackedFloat32Array = PackedFloat32Array()
var _splash_offsets: Array[Vector2] = []
var _splash_cursor: int = 0
var _splash_snap_pending: bool = true

var _lamp_pool: Node3D = null
var _lamp_spots: Array[SpotLight3D] = []
var _lamp_update_timer: float = 0.0
var _last_cam_pos: Vector3 = Vector3(768.0, 2.0, 768.0)

var _probe_root: Node3D = null
var _probes: Array[ReflectionProbe] = []
var _probe_dirty_queue: Array[int] = []
var _probe_refresh_active_idx: int = -1
var _probe_refresh_cooldown: float = 0.0
var _last_probe_nf: float = -1.0
var _last_probe_cc: float = -1.0

var is_camera_underwater: bool = false
var underwater_depth: float = 0.0
var _underwater_layer: CanvasLayer = null
var _underwater_rect: ColorRect = null
var _underwater_mat: ShaderMaterial = null

# Quality & performance controls (managed by PerformanceController)
var shadow_tier: int = 3 # 0=Off, 1=Low(65m 1-split), 2=Med(115m 2-split), 3=High(175m 4-split), 4=Ultra(230m 4-split)
var ssao_enabled_cfg: bool = true
var ssr_mode: int = 1 # 0=Off, 1=Wet Only, 2=Always
var glow_enabled_cfg: bool = true
var probe_tier: int = 2 # 0=Off, 1=1 Center Probe, 2=3x3 Grid
var rain_particle_budget: int = RAIN_PARTICLE_COUNT
var splash_ray_budget: int = 10
var lamp_pool_budget: int = STREETLIGHT_POOL_SIZE

var _last_emissive_nf: float = -9.0
var _last_emissive_rain: float = -9.0
var _last_rain_obb_pos: Vector3 = Vector3(-99999.0, 0.0, -99999.0)
var _lamp_grid: Dictionary = {} # Vector2i -> Array[Vector3]
var _lamp_grid_hash: String = ""

var _elapsed: float = 0.0
var _lightning_countdown: float = 4.2
var _lightning_env: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _bp_grid: Dictionary = {}
var _bp_grid_hash: String = ""
const _BP_CELL_SIZE := 64.0


func _ready() -> void:
	_rng.seed = 202803
	if world_env != null and sun_light != null:
		setup(world_env, sun_light, city_world, camera_target)


func setup(p_world_env: WorldEnvironment, p_sun: DirectionalLight3D, p_city_world: CityWorld = null, p_target: Node3D = null) -> void:
	world_env = p_world_env
	sun_light = p_sun
	city_world = p_city_world
	camera_target = p_target

	_configure_environment()
	_configure_celestial_lights()
	_build_streetlight_pool()
	_build_reflection_probes()
	_build_rain_system()
	_build_snow_system()
	_build_splash_system()
	_build_underwater_overlay()
	if city_world != null and not city_world.city_rebuilt.is_connected(_on_city_rebuilt_probes):
		city_world.city_rebuilt.connect(_on_city_rebuilt_probes)

	set_weather(weather_preset, true)
	step_simulation(0.0)


func step_simulation(delta: float) -> void:
	_elapsed += maxf(delta, 0.0)
	if not time_paused and delta > 0.0:
		time_of_day_hour = fposmod(time_of_day_hour + delta * time_scale, 24.0)

	_update_weather(delta)
	_update_celestial_lighting()
	_sync_shader_globals()

	var cam_pos := _resolve_viewer_position()
	var jumped := cam_pos.distance_squared_to(_last_cam_pos) > 144.0
	_last_cam_pos = cam_pos

	_update_rain_volume(cam_pos, jumped)
	if jumped or _splash_snap_pending:
		_update_splash_rings(cam_pos, true)
		_splash_snap_pending = false
	else:
		_update_splash_rings(cam_pos, false)

	_lamp_update_timer += maxf(delta, 0.0)
	if jumped or _lamp_update_timer >= 0.14 or delta == 0.0:
		_lamp_update_timer = 0.0
		_update_streetlight_pool(cam_pos)
	_update_reflection_probes(delta)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or world_env == null:
		return
	step_simulation(delta)


func set_time_of_day(hour: float, pause_clock: bool = false) -> void:
	time_of_day_hour = fposmod(hour, 24.0)
	if pause_clock:
		time_paused = true
	if world_env != null:
		step_simulation(0.0)


func set_weather(preset: String, immediate: bool = false) -> void:
	var key := preset.to_lower().strip_edges()
	if not WEATHER_PARAMS.has(key):
		key = "partly_cloudy"
	weather_preset = key
	if immediate:
		var cfg: Dictionary = WEATHER_PARAMS[key]
		weather_cloud_cover = float(cfg["cloud"])
		weather_rain = float(cfg["rain"])
		weather_snow = float(cfg.get("snow", 0.0))
		var ang := deg_to_rad(float(cfg["angle_deg"]))
		wind_vector = Vector2(cos(ang), sin(ang)) * float(cfg["wind"])
		if key == "blizzard":
			weather_snow_depth = 1.0
			weather_slush = 0.08
			weather_wetness = 0.16
			weather_puddles = 0.04
		elif key == "snow":
			weather_snow_depth = 0.78
			weather_slush = 0.14
			weather_wetness = 0.22
			weather_puddles = 0.08
		elif key == "sleet":
			weather_snow_depth = 0.36
			weather_slush = 0.78
			weather_wetness = 0.78
			weather_puddles = 0.44
		elif key == "thunderstorm":
			weather_snow_depth = 0.0
			weather_slush = 0.0
			weather_wetness = 0.88
			weather_puddles = 0.76
		elif key == "rain":
			weather_snow_depth = 0.0
			weather_slush = 0.0
			weather_wetness = 0.72
			weather_puddles = 0.52
		elif key == "drizzle":
			weather_snow_depth = 0.0
			weather_slush = 0.0
			weather_wetness = 0.56
			weather_puddles = 0.28
		elif key == "fog":
			weather_snow_depth = 0.0
			weather_slush = 0.0
			weather_wetness = 0.24
			weather_puddles = 0.06
		else:
			weather_snow_depth = 0.0
			weather_slush = 0.0
			weather_wetness = 0.0
			weather_puddles = 0.0
		weather_lightning = 0.0
		_lightning_env = 0.0
		_splash_snap_pending = true
	if world_env != null:
		step_simulation(0.0)


func cycle_time_preset() -> String:
	var best_idx := 0
	var best_diff := 99.0
	for i in TIME_PRESETS.size():
		var h: float = float(TIME_PRESETS[i]["hour"])
		var diff: float = absf(fposmod(time_of_day_hour - h + 12.0, 24.0) - 12.0)
		if diff < best_diff:
			best_diff = diff
			best_idx = i
	var next_idx := (best_idx + 1) % TIME_PRESETS.size()
	var target: Dictionary = TIME_PRESETS[next_idx]
	set_time_of_day(float(target["hour"]))
	return "%s (%s)" % [target["name"], get_time_string()]


func cycle_weather() -> String:
	var idx := WEATHER_ORDER.find(weather_preset)
	var next_idx := (idx + 1) % WEATHER_ORDER.size() if idx >= 0 else 0
	var next_key := WEATHER_ORDER[next_idx]
	set_weather(next_key, false)
	return get_weather_label()


func toggle_paused() -> bool:
	time_paused = not time_paused
	return time_paused


func trigger_lightning(strength: float = 1.0) -> void:
	_lightning_env = clampf(strength, 0.2, 1.35)
	weather_lightning = _lightning_env
	_sync_shader_globals()


func get_time_string() -> String:
	var total_mins := int(round(fposmod(time_of_day_hour, 24.0) * 60.0)) % 1440
	var hh := total_mins / 60
	var mm := total_mins % 60
	return "%02d:%02d" % [hh, mm]


func get_phase_name() -> String:
	if time_of_day_hour >= 5.2 and time_of_day_hour < 7.2:
		return "Dawn"
	if time_of_day_hour >= 7.2 and time_of_day_hour < 16.8:
		return "Day"
	if time_of_day_hour >= 16.8 and time_of_day_hour < 18.9:
		return "Golden Hour"
	if time_of_day_hour >= 18.9 and time_of_day_hour < 20.5:
		return "Dusk"
	return "Night"


func get_weather_label() -> String:
	var cfg: Dictionary = WEATHER_PARAMS.get(weather_preset, WEATHER_PARAMS["partly_cloudy"])
	return String(cfg.get("label", weather_preset.capitalize()))


func get_active_streetlamp_count() -> int:
	var c := 0
	for s in _lamp_spots:
		if s.visible and s.light_energy > 0.02:
			c += 1
	return c


func is_point_sheltered(world_pos: Vector3) -> bool:
	return _is_pos_in_building_obb(world_pos, 0.35, 0.14)


func _get_nearby_blueprints(pos: Vector3) -> Array:
	if city_world == null or city_world.plan == null:
		return []
	var h := city_world.plan.plan_hash
	if h != _bp_grid_hash:
		_bp_grid.clear()
		_bp_grid_hash = h
		for bp in city_world.plan.blueprints:
			var r_pad := maxf(bp.width, bp.depth) * 0.72 + 1.0
			var cx0 := int(floor((bp.center.x - r_pad) / _BP_CELL_SIZE))
			var cx1 := int(floor((bp.center.x + r_pad) / _BP_CELL_SIZE))
			var cz0 := int(floor((bp.center.y - r_pad) / _BP_CELL_SIZE))
			var cz1 := int(floor((bp.center.y + r_pad) / _BP_CELL_SIZE))
			for cz in range(cz0, cz1 + 1):
				for cx in range(cx0, cx1 + 1):
					var key := Vector2i(cx, cz)
					if not _bp_grid.has(key):
						_bp_grid[key] = []
					_bp_grid[key].append(bp)
	var cc := Vector2i(int(floor(pos.x / _BP_CELL_SIZE)), int(floor(pos.z / _BP_CELL_SIZE)))
	return _bp_grid.get(cc, [])


func _is_pos_in_building_obb(pos: Vector3, top_margin: float, xz_margin: float) -> bool:
	for bp_v in _get_nearby_blueprints(pos):
		var bp: BuildingBlueprint = bp_v
		var roof_y: float = bp.base_y + bp.get_total_wall_height()
		if pos.y < bp.base_y - 0.1 or pos.y > roof_y + top_margin:
			continue
		var dx: float = pos.x - bp.center.x
		var dz: float = pos.z - bp.center.y
		var cy: float = cos(bp.yaw)
		var sy: float = sin(bp.yaw)
		var lx: float = absf(dx * cy - dz * sy)
		var lz: float = absf(dx * sy + dz * cy)
		if lx < bp.width * 0.5 + xz_margin and lz < bp.depth * 0.5 + xz_margin:
			return true
	return false


func get_state_dict() -> Dictionary:
	return {
		"time_of_day_hour": snapped(time_of_day_hour, 0.001),
		"time_paused": time_paused,
		"weather_preset": weather_preset,
		"weather_cloud_cover": snapped(weather_cloud_cover, 0.001),
		"weather_rain": snapped(weather_rain, 0.001),
		"weather_snow": snapped(weather_snow, 0.001),
		"weather_snow_depth": snapped(weather_snow_depth, 0.001),
		"weather_slush": snapped(weather_slush, 0.001),
		"weather_wetness": snapped(weather_wetness, 0.001),
		"weather_puddles": snapped(weather_puddles, 0.001),
	}


func apply_state_dict(state: Dictionary) -> void:
	if state.is_empty():
		return
	time_of_day_hour = fposmod(float(state.get("time_of_day_hour", time_of_day_hour)), 24.0)
	time_paused = bool(state.get("time_paused", time_paused))
	var preset := String(state.get("weather_preset", weather_preset))
	if WEATHER_PARAMS.has(preset):
		weather_preset = preset
	weather_cloud_cover = clampf(float(state.get("weather_cloud_cover", weather_cloud_cover)), 0.0, 1.0)
	weather_rain = clampf(float(state.get("weather_rain", weather_rain)), 0.0, 1.0)
	weather_snow = clampf(float(state.get("weather_snow", weather_snow)), 0.0, 1.0)
	weather_snow_depth = clampf(float(state.get("weather_snow_depth", weather_snow_depth)), 0.0, 1.0)
	weather_slush = clampf(float(state.get("weather_slush", weather_slush)), 0.0, 1.0)
	weather_wetness = clampf(float(state.get("weather_wetness", weather_wetness)), 0.0, 1.0)
	weather_puddles = clampf(float(state.get("weather_puddles", weather_puddles)), 0.0, 1.0)
	_splash_snap_pending = true
	if world_env != null:
		step_simulation(0.0)


func _configure_environment() -> void:
	if world_env == null:
		return
	if world_env.environment == null:
		world_env.environment = Environment.new()
	var env := world_env.environment
	env.background_mode = Environment.BG_SKY
	if env.sky == null:
		env.sky = Sky.new()
	env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky.radiance_size = Sky.RADIANCE_SIZE_128

	var sky_shader := load(SKY_SHADER_PATH) as Shader
	if sky_shader != null:
		_sky_mat = ShaderMaterial.new()
		_sky_mat.shader = sky_shader
		env.sky.sky_material = _sky_mat

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_agx_white = 8.5
	env.tonemap_agx_contrast = 1.28
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.01
	env.adjustment_contrast = 1.07
	env.adjustment_saturation = 1.08
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 75.0
	env.fog_depth_end = 950.0
	env.fog_depth_curve = 1.25
	env.glow_enabled = glow_enabled_cfg
	env.glow_normalized = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 1.05
	env.glow_hdr_scale = 1.6
	env.ssao_enabled = ssao_enabled_cfg
	env.ssao_radius = 1.15
	env.ssao_intensity = 0.96
	env.ssao_power = 1.48
	env.ssao_detail = 0.55
	env.ssao_horizon = 0.12
	env.ssil_enabled = false
	env.ssr_enabled = false
	env.ssr_max_steps = 8
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.25

	var cam_attr := world_env.camera_attributes as CameraAttributesPractical
	if cam_attr == null:
		cam_attr = CameraAttributesPractical.new()
		world_env.camera_attributes = cam_attr
	cam_attr.auto_exposure_enabled = true
	cam_attr.auto_exposure_scale = 0.28
	cam_attr.auto_exposure_speed = 2.0
	cam_attr.auto_exposure_min_sensitivity = 85.0
	cam_attr.auto_exposure_max_sensitivity = 220.0


func _configure_celestial_lights() -> void:
	if sun_light != null:
		sun_light.visible = true
		sun_light.shadow_bias = 0.015
		sun_light.shadow_normal_bias = 1.2
		sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun_light.directional_shadow_split_1 = 0.06
		sun_light.directional_shadow_split_2 = 0.18
		sun_light.directional_shadow_split_3 = 0.48
		sun_light.directional_shadow_blend_splits = true
		sun_light.directional_shadow_max_distance = 175.0
		sun_light.directional_shadow_fade_start = 0.84
		sun_light.directional_shadow_pancake_size = 24.0

	if moon_light == null and sun_light != null:
		var parent := sun_light.get_parent()
		if parent != null:
			moon_light = parent.get_node_or_null("MoonLight") as DirectionalLight3D
			if moon_light == null:
				moon_light = DirectionalLight3D.new()
				moon_light.name = "MoonLight"
				parent.add_child(moon_light)
				# Keep MoonLight strictly after SunLight so SunLight remains LIGHT0
				var sun_idx := sun_light.get_index()
				parent.move_child(moon_light, sun_idx + 1)

	if moon_light != null:
		moon_light.visible = true
		moon_light.light_color = Color(0.58, 0.72, 1.0)
		moon_light.shadow_enabled = false
		moon_light.shadow_bias = 0.02
		moon_light.shadow_normal_bias = 1.2
		moon_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		moon_light.directional_shadow_max_distance = 135.0
		moon_light.directional_shadow_fade_start = 0.82


func _build_streetlight_pool() -> void:
	if _lamp_pool != null:
		return
	_lamp_pool = Node3D.new()
	_lamp_pool.name = "NightStreetlightPool"
	add_child(_lamp_pool)
	for i in STREETLIGHT_POOL_SIZE:
		var spot := SpotLight3D.new()
		spot.name = "PoolSpot_%d" % i
		spot.shadow_enabled = false # Shadowless pool avoids Forward+ cluster budget overload
		spot.light_color = Color(1.0, 0.76, 0.46)
		spot.light_energy = 0.0
		spot.spot_range = 24.0
		spot.spot_attenuation = 1.35
		spot.spot_angle = 68.0
		spot.spot_angle_attenuation = 0.45
		spot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		spot.visible = false
		_lamp_pool.add_child(spot)
		_lamp_spots.append(spot)


func _build_rain_system() -> void:
	if _rain_particles != null:
		return
	var p_shader := load(RAIN_PARTICLE_SHADER_PATH) as Shader
	var s_shader := load(RAIN_STREAK_SHADER_PATH) as Shader
	if p_shader == null or s_shader == null:
		return

	_rain_process_mat = ShaderMaterial.new()
	_rain_process_mat.shader = p_shader

	var streak_mat := ShaderMaterial.new()
	streak_mat.shader = s_shader

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = streak_mat

	_rain_particles = GPUParticles3D.new()
	_rain_particles.name = "CityRainParticles"
	_rain_particles.amount = RAIN_PARTICLE_COUNT
	_rain_particles.lifetime = 1.6
	_rain_particles.preprocess = 0.8
	_rain_particles.fixed_fps = 60
	_rain_particles.local_coords = false
	_rain_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_particles.custom_aabb = AABB(Vector3(-64.0, -32.0, -64.0), Vector3(128.0, 64.0, 128.0))
	_rain_particles.process_material = _rain_process_mat
	_rain_particles.draw_pass_1 = quad
	_rain_particles.emitting = false
	_rain_particles.visible = false
	add_child(_rain_particles)


func _build_snow_system() -> void:
	if _snow_particles != null:
		return
	var p_shader := load(SNOW_PARTICLE_SHADER_PATH) as Shader
	var f_shader := load(SNOW_FLAKE_SHADER_PATH) as Shader
	if p_shader == null or f_shader == null:
		return

	_snow_process_mat = ShaderMaterial.new()
	_snow_process_mat.shader = p_shader

	var flake_mat := ShaderMaterial.new()
	flake_mat.shader = f_shader

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = flake_mat

	_snow_particles = GPUParticles3D.new()
	_snow_particles.name = "CitySnowParticles"
	_snow_particles.amount = SNOW_PARTICLE_COUNT
	_snow_particles.lifetime = 3.2
	_snow_particles.preprocess = 1.4
	_snow_particles.fixed_fps = 60
	_snow_particles.local_coords = false
	_snow_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_snow_particles.custom_aabb = AABB(Vector3(-64.0, -32.0, -64.0), Vector3(128.0, 64.0, 128.0))
	_snow_particles.process_material = _snow_process_mat
	_snow_particles.draw_pass_1 = quad
	_snow_particles.emitting = false
	_snow_particles.visible = false
	add_child(_snow_particles)


func _build_splash_system() -> void:
	if _splash_mmi != null:
		return
	var splash_shader := load(RAIN_SPLASH_SHADER_PATH) as Shader
	if splash_shader == null:
		return
	var splash_mat := ShaderMaterial.new()
	splash_mat.shader = splash_shader

	var plane := PlaneMesh.new()
	plane.size = Vector2(0.42, 0.42)
	plane.material = splash_mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = plane
	mm.instance_count = SPLASH_COUNT
	mm.visible_instance_count = 0

	_splash_mmi = MultiMeshInstance3D.new()
	_splash_mmi.name = "CityRainSplashes"
	_splash_mmi.multimesh = mm
	_splash_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_splash_mmi.extra_cull_margin = 40.0
	_splash_mmi.visible = false
	add_child(_splash_mmi)

	_splash_phases.resize(SPLASH_COUNT)
	_splash_offsets.resize(SPLASH_COUNT)
	for i in SPLASH_COUNT:
		_splash_phases[i] = _rng.randf()
		var r := sqrt(_rng.randf()) * 21.0 + 0.9
		var a := _rng.randf() * TAU
		_splash_offsets[i] = Vector2(cos(a) * r, sin(a) * r)


func _update_weather(delta: float) -> void:
	var cfg: Dictionary = WEATHER_PARAMS.get(weather_preset, WEATHER_PARAMS["partly_cloudy"])
	var target_cloud := float(cfg["cloud"])
	var target_rain := float(cfg["rain"])
	var target_snow := float(cfg.get("snow", 0.0))
	var base_wind := float(cfg["wind"])
	var ang := deg_to_rad(float(cfg["angle_deg"]))
	var gust := 0.25 * sin(_elapsed * 0.68) + 0.14 * sin(_elapsed * 1.73 + 1.1)
	var target_wind := Vector2(cos(ang), sin(ang)) * maxf(0.2, base_wind + gust * clampf(base_wind * 0.45, 0.2, 1.0))

	if delta > 0.0:
		var rate := clampf(delta * 0.48, 0.0, 1.0)
		weather_cloud_cover = lerpf(weather_cloud_cover, target_cloud, rate)
		weather_rain = lerpf(weather_rain, target_rain, clampf(delta * 0.65, 0.0, 1.0))
		weather_snow = lerpf(weather_snow, target_snow, clampf(delta * 0.65, 0.0, 1.0))
		wind_vector = wind_vector.lerp(target_wind, clampf(delta * 0.85, 0.0, 1.0))

		# Real snow piling accumulation & melt-to-slush/wetness physics
		var is_sleet := (weather_rain > 0.08 and weather_snow > 0.08)
		if weather_snow > 0.08:
			var max_pile := 0.45 if is_sleet else 1.0
			var pile_rate := 0.045 if is_sleet else 0.095
			weather_snow_depth = minf(max_pile, weather_snow_depth + delta * pile_rate * weather_snow)
			var target_slush := 0.80 if is_sleet else 0.10
			weather_slush = lerpf(weather_slush, target_slush, clampf(delta * 0.45, 0.0, 1.0))
		elif weather_snow_depth > 0.005:
			# Thawing snow melts into slush, wet glistening roads, and meltwater puddles!
			var melt_rate := 0.055 + 0.085 * weather_rain + 0.035 * maxf(0.0, sun_elevation)
			var melted := minf(weather_snow_depth, delta * melt_rate)
			weather_snow_depth = maxf(0.0, weather_snow_depth - melted)
			weather_slush = lerpf(weather_slush, clampf(weather_snow_depth * 1.6, 0.0, 0.85), clampf(delta * 0.65, 0.0, 1.0))
			weather_wetness = clampf(weather_wetness + melted * 1.45, 0.0, 0.92)
			weather_puddles = clampf(weather_puddles + melted * 0.85, 0.0, 0.68)
		else:
			weather_slush = maxf(0.0, weather_slush - delta * 0.18)

		if weather_rain > 0.08:
			weather_wetness = clampf(weather_wetness + delta * 0.18 * weather_rain, 0.0, 1.0)
			weather_puddles = clampf(weather_puddles + delta * 0.11 * maxf(weather_rain - 0.15, 0.0), 0.0, 1.0)
		elif weather_preset == "fog":
			weather_wetness = lerpf(weather_wetness, 0.24, clampf(delta * 0.25, 0.0, 1.0))
			weather_puddles = maxf(0.0, weather_puddles - delta * 0.025)
		elif weather_snow <= 0.08 and weather_snow_depth <= 0.005:
			weather_wetness = maxf(0.0, weather_wetness - delta * 0.045)
			weather_puddles = maxf(0.0, weather_puddles - delta * 0.025)

		if weather_preset == "thunderstorm":
			_lightning_countdown -= delta
			if _lightning_countdown <= 0.0:
				_lightning_env = _rng.randf_range(0.85, 1.25)
				_lightning_countdown = _rng.randf_range(3.6, 8.8)
		else:
			_lightning_countdown = minf(_lightning_countdown, 3.8)

		_lightning_env = maxf(0.0, _lightning_env - delta * 3.1)
		weather_lightning = _lightning_env


func _update_celestial_lighting() -> void:
	# Shifted sinusoidal day arc (~13.4h daylight): 6:00 Dawn, 12:00 High Sun, 18:12 Golden Hour, 23:12 Midnight
	var a := (time_of_day_hour - 6.0) / 24.0 * TAU
	var sun_dir := Vector3(cos(a), sin(a) * 0.85 + 0.11, -0.34).normalized()
	sun_direction = sun_dir
	sun_elevation = sun_dir.y
	night_factor = clampf(1.0 - _smoothstep(-0.18, 0.16, sun_elevation), 0.0, 1.0)

	var moon_dir := Vector3(-sun_dir.x, -sun_dir.y + 0.08, 0.34).normalized()
	var overcast_atten := 1.0 - 0.68 * _smoothstep(0.32, 0.96, weather_cloud_cover)
	var rain_atten := 1.0 - 0.32 * weather_rain

	if sun_light != null:
		var up_ref := Vector3.FORWARD if absf(sun_dir.y) > 0.985 else Vector3.UP
		sun_light.look_at_from_position(Vector3.ZERO, -sun_dir, up_ref)
		var sun_above := sun_elevation > 0.008
		sun_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY if sun_above else DirectionalLight3D.SKY_MODE_SKY_ONLY
		var sun_e := lerpf(0.0, 2.75, _smoothstep(-0.02, 0.30, sun_elevation)) * overcast_atten * rain_atten
		if sun_above and weather_lightning > 0.01:
			sun_e += weather_lightning * 1.9
		sun_light.light_energy = sun_e
		var warm_sun := Color(1.0, 0.50, 0.22).lerp(Color(1.0, 0.96, 0.90), _smoothstep(-0.01, 0.28, sun_elevation))
		sun_light.light_color = warm_sun.lerp(Color(0.74, 0.79, 0.88), weather_cloud_cover * 0.55)
		sun_light.shadow_enabled = (shadow_tier > 0) and sun_above and weather_cloud_cover < 0.92

	if moon_light != null:
		var m_up_ref := Vector3.FORWARD if absf(moon_dir.y) > 0.985 else Vector3.UP
		moon_light.look_at_from_position(Vector3.ZERO, -moon_dir, m_up_ref)
		var moon_above := (sun_elevation <= 0.008) and (moon_dir.y > 0.04)
		moon_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY if moon_above else DirectionalLight3D.SKY_MODE_SKY_ONLY
		var moon_e := lerpf(0.0, 0.34, night_factor) * (1.0 - 0.65 * weather_cloud_cover) * _smoothstep(-0.03, 0.16, moon_dir.y)
		if moon_above and weather_lightning > 0.01:
			moon_e += weather_lightning * 2.4
		moon_light.light_energy = moon_e
		moon_light.light_color = Color(0.58, 0.72, 1.0).lerp(Color(0.84, 0.90, 1.0), clampf(weather_lightning, 0.0, 1.0))
		moon_light.shadow_enabled = (shadow_tier >= 2) and moon_above and weather_cloud_cover < 0.85

	if world_env != null and world_env.environment != null:
		var env := world_env.environment
		var cfg: Dictionary = WEATHER_PARAMS.get(weather_preset, WEATHER_PARAMS["partly_cloudy"])
		var target_fog_mult := float(cfg["fog_mult"])
		var fog_boost := float(cfg.get("fog_boost", 0.0))
		var weather_blend := clampf(maxf(maxf(_smoothstep(0.32, 0.95, weather_cloud_cover), maxf(weather_rain, weather_snow)), fog_boost), 0.0, 1.0)
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_depth_begin = lerpf(85.0, 18.0, weather_blend)
		env.fog_depth_end = lerpf(980.0, 195.0 if fog_boost > 0.7 else 320.0, weather_blend)
		env.fog_depth_curve = 1.25
		env.fog_density = clampf(lerpf(0.32, 0.94, clampf(weather_blend * 0.88 + night_factor * 0.12, 0.0, 1.0)) * clampf(target_fog_mult * 0.10 + 0.88, 0.85, 1.32), 0.25, 0.96)
		var water_y := 1.6
		if city_world != null and city_world.plan != null and city_world.plan.terrain != null:
			water_y = city_world.plan.terrain.water_level
		var dawn_mist := _smoothstep(-0.08, 0.12, sun_elevation) * (1.0 - _smoothstep(0.14, 0.34, sun_elevation))
		env.fog_height = water_y + (16.0 if fog_boost > 0.7 else 7.5)
		env.fog_height_density = lerpf(0.012, 0.095, clampf(maxf(maxf(dawn_mist * 0.80, weather_rain * 0.95), fog_boost), 0.0, 1.0))
		env.fog_aerial_perspective = lerpf(0.38, 0.88, weather_blend)
		env.fog_sky_affect = lerpf(0.10, 0.72, weather_blend)
		var day_fog := Color(0.66, 0.82, 0.98).lerp(Color(0.95, 0.62, 0.42), _smoothstep(-0.08, 0.04, sun_elevation) * (1.0 - _smoothstep(0.06, 0.28, sun_elevation)))
		var night_fog := Color(0.045, 0.065, 0.12)
		var base_fog := day_fog.lerp(night_fog, night_factor)
		var storm_fog := Color(0.34, 0.39, 0.46).lerp(Color(0.055, 0.065, 0.095), night_factor)
		var snow_fog := Color(0.78, 0.84, 0.91).lerp(Color(0.10, 0.13, 0.19), night_factor)
		var eff_storm_fog := storm_fog.lerp(snow_fog, clampf(weather_snow * 1.15 + weather_snow_depth * 0.35, 0.0, 1.0))
		env.fog_light_color = base_fog.lerp(eff_storm_fog, clampf(_smoothstep(0.38, 0.95, weather_cloud_cover) * 0.85 + maxf(weather_rain, weather_snow) * 0.45 + fog_boost * 0.45, 0.0, 1.0))
		env.fog_sun_scatter = lerpf(0.30, 0.03, night_factor) * (1.0 - 0.72 * _smoothstep(0.35, 0.95, weather_cloud_cover))
		env.ambient_light_sky_contribution = lerpf(1.0, 0.78, night_factor)
		env.ambient_light_energy = lerpf(0.88, 0.36, night_factor) * (1.0 - 0.18 * weather_rain + 0.14 * weather_snow_depth)
		env.glow_enabled = glow_enabled_cfg
		env.glow_intensity = lerpf(0.38, 0.68, night_factor)
		env.glow_bloom = lerpf(0.06, 0.14, clampf(night_factor * 0.7 + weather_rain * 0.45, 0.0, 1.0))
		env.ssao_enabled = ssao_enabled_cfg
		env.tonemap_exposure = lerpf(1.06, 1.04, night_factor)
		# Genuine dynamic wet-only SSR (saves a full-screen raymarch pass on dry sunny days!)
		var want_ssr := (ssr_mode == 2) or (ssr_mode == 1 and (weather_wetness > 0.06 or weather_puddles > 0.06 or weather_slush > 0.12))
		if env.ssr_enabled != want_ssr:
			env.ssr_enabled = want_ssr

		# Submerged Underwater Medium & Volumetric God-Ray Lens Overlay
		var cam_p := _resolve_viewer_position()
		var sub_now := false
		var sub_d := 0.0
		if city_world != null and city_world.plan != null and city_world.plan.terrain != null:
			var terr := city_world.plan.terrain
			if cam_p.y < water_y + 0.05:
				var gh := terr.sample_height(cam_p.x, cam_p.z)
				var in_ocean := terr.beach_enabled and cam_p.z > terr.get_beach_shore_z(cam_p.x) - 6.0
				var in_creek := terr.distance_to_creek(Vector2(cam_p.x, cam_p.z)) < terr.creek_half_width + 4.0
				if gh < water_y - 0.05 or in_ocean or in_creek:
					sub_now = true
					sub_d = maxf(0.05, water_y - cam_p.y)
		is_camera_underwater = sub_now
		underwater_depth = sub_d
		if sub_now:
			var depth_t := clampf(sub_d / 5.5, 0.0, 1.0)
			var uw_fog := Color(0.05, 0.38, 0.46).lerp(Color(0.015, 0.16, 0.30), depth_t).lerp(Color(0.006, 0.03, 0.07), night_factor)
			env.fog_light_color = uw_fog
			env.fog_depth_begin = 1.5
			env.fog_depth_end = lerpf(44.0, 26.0, depth_t)
			env.fog_depth_curve = 0.92
			env.fog_sky_affect = 0.96
			env.fog_aerial_perspective = 0.0
			env.fog_sun_scatter = lerpf(0.45, 0.05, night_factor)
		else:
			env.fog_depth_begin = 75.0
			env.fog_depth_end = 950.0
			env.fog_depth_curve = 1.25
		if _underwater_rect != null and _underwater_mat != null:
			_underwater_rect.visible = sub_now
			if sub_now:
				_underwater_mat.set_shader_parameter("submerged_depth", sub_d)
				_underwater_mat.set_shader_parameter("day_factor", 1.0 - night_factor)
				_underwater_mat.set_shader_parameter("sun_elev", clampf(sun_elevation, 0.0, 1.0))

	if city_world != null and city_world.mats != null:
		var precip := maxf(weather_rain, weather_snow)
		if absf(night_factor - _last_emissive_nf) > 0.005 or absf(precip - _last_emissive_rain) > 0.02:
			_last_emissive_nf = night_factor
			_last_emissive_rain = precip
			city_world.mats.set_time_of_day_emissives(night_factor, precip)


func _sync_shader_globals() -> void:
	RenderingServer.global_shader_parameter_set(&"time_of_day_hour", time_of_day_hour)
	RenderingServer.global_shader_parameter_set(&"night_factor", night_factor)
	RenderingServer.global_shader_parameter_set(&"sun_elevation", sun_elevation)
	RenderingServer.global_shader_parameter_set(&"weather_rain", weather_rain)
	RenderingServer.global_shader_parameter_set(&"weather_wetness", weather_wetness)
	RenderingServer.global_shader_parameter_set(&"weather_puddles", weather_puddles)
	RenderingServer.global_shader_parameter_set(&"weather_cloud_cover", weather_cloud_cover)
	RenderingServer.global_shader_parameter_set(&"weather_lightning", weather_lightning)
	RenderingServer.global_shader_parameter_set(&"weather_snow", weather_snow)
	RenderingServer.global_shader_parameter_set(&"weather_snow_depth", weather_snow_depth)
	RenderingServer.global_shader_parameter_set(&"weather_slush", weather_slush)
	RenderingServer.global_shader_parameter_set(&"wind_vector", wind_vector)
	RenderingServer.global_shader_parameter_set(&"sun_direction", sun_direction)


func _resolve_viewer_position() -> Vector3:
	if camera_target != null and is_instance_valid(camera_target):
		if camera_target.has_method("get_camera_world_pos"):
			return camera_target.call("get_camera_world_pos")
		return camera_target.global_position
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null:
		return cam.global_position
	return _last_cam_pos


func _build_underwater_overlay() -> void:
	if _underwater_layer != null:
		return
	_underwater_layer = CanvasLayer.new()
	_underwater_layer.name = "UnderwaterLensOverlay"
	_underwater_layer.layer = 5
	add_child(_underwater_layer)

	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform float submerged_depth = 1.0;
uniform float day_factor = 1.0;
uniform float sun_elev = 0.6;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;
	// Volumetric downward sunlight God-ray shafts piercing through overhead waves
	float ray_u = uv.x * 11.0 + uv.y * 2.2;
	float r1 = sin(ray_u + TIME * 0.85) * 0.5 + 0.5;
	float r2 = sin(ray_u * 1.73 - TIME * 1.15 + 1.4) * 0.5 + 0.5;
	float r3 = sin(ray_u * 2.65 + TIME * 0.62 + 2.9) * 0.5 + 0.5;
	float rays = pow(r1 * 0.45 + r2 * 0.35 + r3 * 0.20, 2.6) * (1.0 - smoothstep(0.0, 0.92, uv.y));
	float ray_strength = rays * day_factor * clamp(sun_elev * 1.6 + 0.2, 0.15, 1.0) * (1.0 - clamp(submerged_depth * 0.08, 0.0, 0.65));

	// Floating luminous marine plankton & rising micro-bubbles
	float specs = 0.0;
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		vec2 p_uv = uv * (22.0 + fi * 14.0) + vec2(sin(TIME * 0.35 + fi) * 1.2, TIME * (0.55 + fi * 0.25));
		vec2 cell = floor(p_uv);
		vec2 f = fract(p_uv) - 0.5;
		float h = hash21(cell + fi * 37.0);
		if (h > 0.82) {
			vec2 jitter = vec2(fract(h * 13.7) - 0.5, fract(h * 29.3) - 0.5) * 0.55;
			float d = length(f - jitter);
			specs += smoothstep(0.11, 0.02, d) * (0.45 + 0.55 * sin(TIME * 2.4 + h * 18.0));
		}
	}

	// Deeper sapphire diving-mask peripheral vignette + aquamarine light shafts
	float vig = smoothstep(0.28, 0.92, length(uv - vec2(0.5)));
	vec3 water_tint = mix(vec3(0.04, 0.40, 0.48), vec3(0.01, 0.14, 0.28), clamp(submerged_depth / 5.0 + vig * 0.45, 0.0, 1.0));
	vec3 ray_col = vec3(0.32, 0.86, 0.92) * ray_strength * 0.38;
	vec3 spec_col = vec3(0.55, 0.94, 0.98) * specs * (0.25 + 0.55 * day_factor);

	vec3 final_rgb = water_tint * (0.22 + vig * 0.28) + ray_col + spec_col;
	float final_a = clamp(0.18 + vig * 0.24 + ray_strength * 0.16 + specs * 0.22, 0.0, 0.58);
	COLOR = vec4(final_rgb, final_a);
}
"""
	_underwater_mat = ShaderMaterial.new()
	_underwater_mat.shader = sh

	_underwater_rect = ColorRect.new()
	_underwater_rect.name = "UnderwaterLensRect"
	_underwater_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_underwater_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_underwater_rect.material = _underwater_mat
	_underwater_rect.visible = false
	_underwater_layer.add_child(_underwater_rect)


func _update_rain_volume(cam_pos: Vector3, jumped: bool) -> void:
	var rain_active := weather_rain > 0.02 and not is_camera_underwater
	var snow_active := weather_snow > 0.02 and not is_camera_underwater
	if _rain_particles != null:
		_rain_particles.emitting = rain_active
		_rain_particles.visible = rain_active
	if _snow_particles != null:
		_snow_particles.emitting = snow_active
		_snow_particles.visible = snow_active
	if not rain_active and not snow_active:
		return

	var em_center := cam_pos + Vector3(0.0, 4.5, 0.0)
	if rain_active and _rain_particles != null and _rain_process_mat != null:
		_rain_particles.global_position = em_center
		_rain_process_mat.set_shader_parameter("emitter_center", em_center)
	if snow_active and _snow_particles != null and _snow_process_mat != null:
		_snow_particles.global_position = em_center
		_snow_process_mat.set_shader_parameter("emitter_center", em_center)

	# Cache nearest-8 indoor exclusion OBBs until camera moves > 2.0m (shared across rain & snow!)
	if jumped or cam_pos.distance_squared_to(_last_rain_obb_pos) > 4.0:
		_last_rain_obb_pos = cam_pos
		var obb_arr: Array[Vector4] = []
		var ext_arr: Array[Vector4] = []
		obb_arr.resize(8)
		ext_arr.resize(8)
		for i in 8:
			obb_arr[i] = Vector4.ZERO
			ext_arr[i] = Vector4.ZERO

		var count := 0
		if city_world != null and city_world.plan != null:
			var cand: Array[Dictionary] = []
			var seen_ids := {}
			var cx0 := int(floor(cam_pos.x / _BP_CELL_SIZE))
			var cz0 := int(floor(cam_pos.z / _BP_CELL_SIZE))
			for oz in range(-1, 2):
				for ox in range(-1, 2):
					for bp in _get_nearby_blueprints(Vector3(float(cx0 + ox) * _BP_CELL_SIZE + 1.0, cam_pos.y, float(cz0 + oz) * _BP_CELL_SIZE + 1.0)):
						if seen_ids.has(bp.id):
							continue
						seen_ids[bp.id] = true
						var dx: float = bp.center.x - cam_pos.x
						var dz: float = bp.center.y - cam_pos.z
						var d2 := dx * dx + dz * dz
						if d2 < 2400.0: # within ~49m radius
							cand.append({"d2": d2, "bp": bp})
			cand.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d2"]) < float(b["d2"]))
			count = mini(8, cand.size())
			for i in count:
				var bp: BuildingBlueprint = cand[i]["bp"]
				obb_arr[i] = Vector4(bp.center.x, bp.center.y, cos(bp.yaw), sin(bp.yaw))
				ext_arr[i] = Vector4(bp.width * 0.5, bp.depth * 0.5, bp.base_y, bp.base_y + bp.get_total_wall_height() + 0.35)

		if _rain_process_mat != null:
			_rain_process_mat.set_shader_parameter("nearby_bld_count", count)
			_rain_process_mat.set_shader_parameter("nearby_bld_obb", obb_arr)
			_rain_process_mat.set_shader_parameter("nearby_bld_ext", ext_arr)
		if _snow_process_mat != null:
			_snow_process_mat.set_shader_parameter("nearby_bld_count", count)
			_snow_process_mat.set_shader_parameter("nearby_bld_obb", obb_arr)
			_snow_process_mat.set_shader_parameter("nearby_bld_ext", ext_arr)

	if jumped:
		if rain_active and _rain_particles != null:
			_rain_particles.restart()
		if snow_active and _snow_particles != null:
			_snow_particles.restart()


func _update_splash_rings(cam_pos: Vector3, update_all: bool) -> void:
	if _splash_mmi == null or _splash_mmi.multimesh == null:
		return
	var mm := _splash_mmi.multimesh
	var active := weather_rain > 0.05 and splash_ray_budget > 0
	_splash_mmi.visible = active
	if not active:
		mm.visible_instance_count = 0
		return

	mm.visible_instance_count = clampi(int(SPLASH_COUNT * weather_rain), 16, SPLASH_COUNT)
	var world_3d := get_world_3d()
	if world_3d == null or world_3d.direct_space_state == null:
		return
	var space := world_3d.direct_space_state
	var batch := mini(SPLASH_COUNT, maxi(splash_ray_budget, 24)) if update_all else splash_ray_budget
	var hidden_xform := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), cam_pos + Vector3(0.0, -500.0, 0.0))

	for s_i in batch:
		var idx := (_splash_cursor + s_i) % SPLASH_COUNT
		var off := _splash_offsets[idx]
		var wx := cam_pos.x + off.x
		var wz := cam_pos.z + off.y
		var ray_from := Vector3(wx, cam_pos.y + 38.0, wz)
		var ray_to := Vector3(wx, cam_pos.y - 24.0, wz)
		var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			mm.set_instance_transform(idx, hidden_xform)
			continue
		var hit_pos: Vector3 = hit["position"]
		# Keep splash rings off lower interior floors if a ceiling/opening happens to be missed
		if _is_pos_in_building_obb(hit_pos, -0.45, 0.08):
			mm.set_instance_transform(idx, hidden_xform)
			continue
		var xf := Transform3D(Basis(Vector3.UP, _splash_phases[idx] * TAU), hit_pos + Vector3(0.0, 0.032, 0.0))
		mm.set_instance_transform(idx, xf)
		mm.set_instance_custom_data(idx, Color(_splash_phases[idx], 1.0, 0.0, 1.0))

	_splash_cursor = (_splash_cursor + batch) % SPLASH_COUNT



func _ensure_lamp_grid() -> void:
	if city_world == null or city_world.plan == null:
		return
	var h := city_world.plan.plan_hash
	if h == _lamp_grid_hash:
		return
	_lamp_grid_hash = h
	_lamp_grid.clear()
	for head in city_world.streetlight_heads:
		var cc := Vector2i(int(floor(head.x / _BP_CELL_SIZE)), int(floor(head.z / _BP_CELL_SIZE)))
		if not _lamp_grid.has(cc):
			_lamp_grid[cc] = []
		_lamp_grid[cc].append(head)


func _update_streetlight_pool(cam_pos: Vector3) -> void:
	if night_factor <= 0.04 or lamp_pool_budget <= 0 or city_world == null or city_world.streetlight_heads.is_empty():
		for spot in _lamp_spots:
			spot.visible = false
			spot.light_energy = 0.0
		return

	_ensure_lamp_grid()
	var base_e := lerpf(0.0, 6.8, _smoothstep(0.04, 0.45, night_factor)) * (1.0 + 0.18 * weather_wetness)
	var cand: Array[Dictionary] = []
	var cx0 := int(floor(cam_pos.x / _BP_CELL_SIZE))
	var cz0 := int(floor(cam_pos.z / _BP_CELL_SIZE))
	for oz in range(-2, 3):
		for ox in range(-2, 3):
			var key := Vector2i(cx0 + ox, cz0 + oz)
			if not _lamp_grid.has(key):
				continue
			for head_v in _lamp_grid[key]:
				var head: Vector3 = head_v
				var d2 := (head.x - cam_pos.x) * (head.x - cam_pos.x) + (head.z - cam_pos.z) * (head.z - cam_pos.z)
				if d2 < 9025.0: # <= 95m
					cand.append({"d2": d2, "pos": head})
	cand.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d2"]) < float(b["d2"]))

	var max_lamps := mini(lamp_pool_budget, _lamp_spots.size())
	var active_n := mini(max_lamps, cand.size())
	for i in _lamp_spots.size():
		var spot := _lamp_spots[i]
		if i < active_n:
			var d := sqrt(float(cand[i]["d2"]))
			var fade := 1.0 - _smoothstep(68.0, 95.0, d)
			spot.global_position = cand[i]["pos"]
			spot.light_energy = base_e * fade
			spot.visible = spot.light_energy > 0.02
		else:
			spot.visible = false
			spot.light_energy = 0.0


func apply_quality_settings(cfg: Dictionary) -> void:
	if cfg.has("shadow_tier"):
		shadow_tier = clampi(int(cfg["shadow_tier"]), 0, 4)
	if cfg.has("ssao"):
		ssao_enabled_cfg = bool(cfg["ssao"])
	if cfg.has("ssr_mode"):
		ssr_mode = clampi(int(cfg["ssr_mode"]), 0, 2)
	if cfg.has("glow"):
		glow_enabled_cfg = bool(cfg["glow"])
	if cfg.has("rain_particles"):
		rain_particle_budget = clampi(int(cfg["rain_particles"]), 250, RAIN_PARTICLE_COUNT)
		if _rain_particles != null and _rain_particles.amount != rain_particle_budget:
			_rain_particles.amount = rain_particle_budget
		var snow_amt := clampi(int(round(float(rain_particle_budget) * 0.92)), 250, SNOW_PARTICLE_COUNT)
		if _snow_particles != null and _snow_particles.amount != snow_amt:
			_snow_particles.amount = snow_amt
	if cfg.has("splash_budget"):
		splash_ray_budget = clampi(int(cfg["splash_budget"]), 0, 24)
	if cfg.has("lamp_budget"):
		lamp_pool_budget = clampi(int(cfg["lamp_budget"]), 0, STREETLIGHT_POOL_SIZE)
	var rebuild_probes := false
	if cfg.has("probe_tier"):
		var new_pt := clampi(int(cfg["probe_tier"]), 0, 2)
		if new_pt != probe_tier:
			probe_tier = new_pt
			rebuild_probes = true

	if sun_light != null:
		match shadow_tier:
			0:
				sun_light.shadow_enabled = false
			1:
				sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
				sun_light.directional_shadow_max_distance = 72.0
				sun_light.directional_shadow_blend_splits = false
			2:
				sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
				sun_light.directional_shadow_split_1 = 0.16
				sun_light.directional_shadow_max_distance = 122.0
				sun_light.directional_shadow_blend_splits = true
			3:
				sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
				sun_light.directional_shadow_split_1 = 0.06
				sun_light.directional_shadow_split_2 = 0.18
				sun_light.directional_shadow_split_3 = 0.48
				sun_light.directional_shadow_max_distance = 175.0
				sun_light.directional_shadow_blend_splits = true
			_:
				sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
				sun_light.directional_shadow_split_1 = 0.06
				sun_light.directional_shadow_split_2 = 0.20
				sun_light.directional_shadow_split_3 = 0.50
				sun_light.directional_shadow_max_distance = 230.0
				sun_light.directional_shadow_blend_splits = true

	if world_env != null and world_env.environment != null:
		var env := world_env.environment
		env.ssao_enabled = ssao_enabled_cfg
		env.glow_enabled = glow_enabled_cfg
		env.ssr_max_steps = 12 if shadow_tier >= 4 else 8
		if shadow_tier <= 1:
			env.sky.radiance_size = Sky.RADIANCE_SIZE_64
		else:
			env.sky.radiance_size = Sky.RADIANCE_SIZE_128

	if rebuild_probes:
		_build_reflection_probes()

	_update_celestial_lighting()


static func _smoothstep(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / maxf(e1 - e0, 0.00001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _on_city_rebuilt_probes(_p: CityPlan) -> void:
	_lamp_grid_hash = ""
	_last_rain_obb_pos = Vector3(-99999.0, 0.0, -99999.0)
	_build_reflection_probes()


func _build_reflection_probes() -> void:
	if _probe_root != null and is_instance_valid(_probe_root):
		_probe_root.queue_free()
	_probes.clear()
	_probe_dirty_queue.clear()
	_probe_refresh_active_idx = -1
	_probe_refresh_cooldown = 0.0

	if probe_tier <= 0 or city_world == null or city_world.plan == null:
		return
	var ws := city_world.plan.config.world_size
	var grid_n := 3 if probe_tier >= 2 else 1
	var cell_sz := ws / float(grid_n)
	_probe_root = Node3D.new()
	_probe_root.name = "ExteriorReflectionProbes"
	add_child(_probe_root)

	for gz in range(grid_n):
		for gx in range(grid_n):
			var px := (float(gx) + 0.5) * cell_sz
			var pz := (float(gz) + 0.5) * cell_sz
			var ground_y := city_world.plan.terrain.sample_height(px, pz) if city_world.plan.terrain != null else 4.0
			var rp := ReflectionProbe.new()
			rp.name = "CityProbe_%d_%d" % [gx, gz]
			rp.position = Vector3(px, ground_y + 42.0, pz)
			rp.size = Vector3(cell_sz, 160.0, cell_sz)
			rp.box_projection = true
			rp.update_mode = ReflectionProbe.UPDATE_ONCE
			rp.interior = false
			rp.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
			rp.intensity = 0.78
			rp.cull_mask = 1
			_probe_root.add_child(rp)
			_probes.append(rp)

	_last_probe_nf = night_factor
	_last_probe_cc = weather_cloud_cover


func _update_reflection_probes(delta: float) -> void:
	if _probes.is_empty() or DisplayServer.get_name().to_lower().contains("headless"):
		return
	if _probe_refresh_active_idx >= 0 and _probe_refresh_active_idx < _probes.size():
		_probes[_probe_refresh_active_idx].update_mode = ReflectionProbe.UPDATE_ONCE
		_probe_refresh_active_idx = -1
		_probe_refresh_cooldown = 0.75

	if _probe_refresh_cooldown > 0.0:
		_probe_refresh_cooldown = maxf(0.0, _probe_refresh_cooldown - maxf(delta, 0.0))
		return

	if delta > 0.0 and _probe_dirty_queue.is_empty():
		var nf_diff := absf(night_factor - _last_probe_nf)
		var cc_diff := absf(weather_cloud_cover - _last_probe_cc)
		if nf_diff > 0.25 or cc_diff > 0.35:
			_last_probe_nf = night_factor
			_last_probe_cc = weather_cloud_cover
			for i in range(_probes.size()):
				_probe_dirty_queue.append(i)

	if not _probe_dirty_queue.is_empty():
		var next_idx: int = _probe_dirty_queue.pop_front()
		if next_idx >= 0 and next_idx < _probes.size():
			_probes[next_idx].update_mode = ReflectionProbe.UPDATE_ALWAYS
			_probe_refresh_active_idx = next_idx
