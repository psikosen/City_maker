class_name PerformanceController
extends CanvasLayer

## Real-time graphics quality presets, Adaptive Auto-FPS Governor,
## and toggleable [F4] Performance & Lag Control Panel.
## Hotkeys:
## - F2: Cycle quality presets (Low / Medium / High / Ultra)
## - F4: Toggle interactive Performance & Graphics Settings panel
## - F6: Toggle Adaptive Auto-FPS Governor (dynamic resolution + LOD scaling)

signal status_message(msg: String)

const SETTINGS_PATH := "user://graphics_settings.json"
const PRESET_ORDER: Array[String] = ["low", "medium", "high", "ultra"]

const PRESETS: Dictionary = {
	"low": {
		"label": "Low (Max FPS)",
		"render_scale": 0.72,
		"upscaler": 1, # 0=Bilinear, 1=FSR 2.2, 2=FSR 1.0
		"shadow_tier": 1,
		"ssao": false,
		"ssr_mode": 0, # 0=Off, 1=Wet Only, 2=Always
		"glow": false,
		"probe_tier": 0, # 0=Off, 1=1 Center, 2=3x3 Grid
		"interior_probes": false,
		"chunk_dist": 480.0,
		"keep_skyline": false,
		"traffic_density": 0.40,
		"crowd_density": 0.40,
		"sim_vis_scale": 0.62,
		"far_lod_divisor": 5,
		"rain_particles": 650,
		"splash_budget": 0,
		"lamp_budget": 6,
	},
	"medium": {
		"label": "Medium (Balanced)",
		"render_scale": 0.85,
		"upscaler": 1,
		"shadow_tier": 2,
		"ssao": false,
		"ssr_mode": 1,
		"glow": true,
		"probe_tier": 1,
		"interior_probes": false,
		"chunk_dist": 760.0,
		"keep_skyline": true,
		"traffic_density": 0.70,
		"crowd_density": 0.70,
		"sim_vis_scale": 0.82,
		"far_lod_divisor": 4,
		"rain_particles": 1300,
		"splash_budget": 4,
		"lamp_budget": 12,
	},
	"high": {
		"label": "High (Default)",
		"render_scale": 1.00,
		"upscaler": 0,
		"shadow_tier": 3,
		"ssao": true,
		"ssr_mode": 1,
		"glow": true,
		"probe_tier": 2,
		"interior_probes": false,
		"chunk_dist": 1150.0,
		"keep_skyline": true,
		"traffic_density": 1.00,
		"crowd_density": 1.00,
		"sim_vis_scale": 1.00,
		"far_lod_divisor": 4,
		"rain_particles": 2200,
		"splash_budget": 10,
		"lamp_budget": 18,
	},
	"ultra": {
		"label": "Ultra (Max Realism)",
		"render_scale": 1.00,
		"upscaler": 0,
		"shadow_tier": 4,
		"ssao": true,
		"ssr_mode": 2,
		"glow": true,
		"probe_tier": 2,
		"interior_probes": true,
		"chunk_dist": 1750.0,
		"keep_skyline": true,
		"traffic_density": 1.00,
		"crowd_density": 1.00,
		"sim_vis_scale": 1.20,
		"far_lod_divisor": 2,
		"rain_particles": 2600,
		"splash_budget": 14,
		"lamp_budget": 18,
	},
}

var city_world: CityWorld = null
var atmosphere: AtmosphereController = null
var player: PlayerController = null

# Active user baseline configuration
var preset_name: String = "high"
var render_scale: float = 1.00
var upscaler_mode: int = 0 # 0=Bilinear, 1=FSR 2.2, 2=FSR 1.0
var shadow_tier: int = 3
var ssao_enabled: bool = true
var ssr_mode: int = 1
var glow_enabled: bool = true
var probe_tier: int = 2
var interior_probes_enabled: bool = false
var vsync_enabled: bool = true
var chunk_dist: float = 1150.0
var keep_skyline: bool = true
var traffic_density: float = 1.00
var crowd_density: float = 1.00
var sim_vis_scale: float = 1.00
var far_lod_divisor: int = 4
var rain_particles: int = 2200
var splash_budget: int = 10
var lamp_budget: int = 18

# Adaptive Auto-FPS Governor state
var auto_fps_enabled: bool = false
var target_fps: int = 60
var auto_tier: int = 0 # 0 = full baseline, 1..6 = progressive dynamic relief
var effective_render_scale: float = 1.00

# Live frame-time telemetry
var avg_frame_ms: float = 16.67
var p1_low_fps: float = 60.0
var _frame_ring: PackedFloat32Array = PackedFloat32Array()
var _frame_ring_pos: int = 0
var _frame_ring_count: int = 0
var _ema_ms: float = 16.67
var _gov_down_accum: float = 0.0
var _gov_up_accum: float = 0.0
var _gov_cooldown: float = 0.0
var _ui_refresh_timer: float = 0.0

var _menu_open: bool = false
var _persist_enabled: bool = true
var _syncing_ui: bool = false

# UI widget references
var _panel: PanelContainer = null
var _stats_label: Label = null
var _preset_buttons: Dictionary = {}
var _auto_fps_chk: CheckButton = null
var _target_fps_opt: OptionButton = null
var _scale_slider: HSlider = null
var _scale_val_lbl: Label = null
var _upscaler_opt: OptionButton = null
var _shadow_opt: OptionButton = null
var _ssao_chk: CheckButton = null
var _ssr_opt: OptionButton = null
var _glow_chk: CheckButton = null
var _probe_opt: OptionButton = null
var _int_probe_chk: CheckButton = null
var _vsync_chk: CheckButton = null
var _dist_slider: HSlider = null
var _dist_val_lbl: Label = null
var _traffic_slider: HSlider = null
var _traffic_val_lbl: Label = null
var _crowd_slider: HSlider = null
var _crowd_val_lbl: Label = null


func _ready() -> void:
	layer = 20
	_frame_ring.resize(120)
	_build_panel_ui()


func setup(p_city_world: CityWorld, p_atmosphere: AtmosphereController, p_player: PlayerController, allow_persist: bool = true) -> void:
	city_world = p_city_world
	atmosphere = p_atmosphere
	player = p_player
	_persist_enabled = allow_persist
	if city_world != null and not city_world.city_rebuilt.is_connected(_on_city_rebuilt):
		city_world.city_rebuilt.connect(_on_city_rebuilt)
	if _persist_enabled:
		_load_settings_from_disk()
	apply_all_settings(false)


func _on_city_rebuilt(_plan: CityPlan) -> void:
	apply_all_settings(false)


func apply_preset(p_name: String, save_disk: bool = true) -> String:
	var key := p_name.to_lower().strip_edges()
	if not PRESETS.has(key):
		key = "high"
	var cfg: Dictionary = PRESETS[key]
	preset_name = key
	render_scale = float(cfg["render_scale"])
	upscaler_mode = int(cfg["upscaler"])
	shadow_tier = int(cfg["shadow_tier"])
	ssao_enabled = bool(cfg["ssao"])
	ssr_mode = int(cfg["ssr_mode"])
	glow_enabled = bool(cfg["glow"])
	probe_tier = int(cfg["probe_tier"])
	interior_probes_enabled = bool(cfg["interior_probes"])
	chunk_dist = float(cfg["chunk_dist"])
	keep_skyline = bool(cfg["keep_skyline"])
	traffic_density = float(cfg["traffic_density"])
	crowd_density = float(cfg["crowd_density"])
	sim_vis_scale = float(cfg["sim_vis_scale"])
	far_lod_divisor = int(cfg["far_lod_divisor"])
	rain_particles = int(cfg["rain_particles"])
	splash_budget = int(cfg["splash_budget"])
	lamp_budget = int(cfg["lamp_budget"])
	auto_tier = 0
	apply_all_settings(save_disk)
	return String(cfg["label"])


func cycle_preset() -> String:
	var idx := PRESET_ORDER.find(preset_name)
	var next_idx := (idx + 1) % PRESET_ORDER.size() if idx >= 0 else 2
	return apply_preset(PRESET_ORDER[next_idx], true)


func set_auto_fps_enabled(enabled: bool, save_disk: bool = true) -> void:
	auto_fps_enabled = enabled
	if not auto_fps_enabled:
		auto_tier = 0
	_gov_down_accum = 0.0
	_gov_up_accum = 0.0
	_gov_cooldown = 1.0
	apply_all_settings(save_disk)


func set_menu_open(open_state: bool) -> void:
	_menu_open = open_state
	if _panel != null:
		_panel.visible = _menu_open
	if player != null:
		player.ui_menu_open = _menu_open
	if not _is_headless():
		if _menu_open:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			_sync_ui_from_state()
		elif player != null and not player._is_automated_cam():
			player._mouse_released_by_user = false
			player._ignore_next_motion = true
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func is_menu_open() -> bool:
	return _menu_open


func get_hud_summary() -> String:
	var p_lbl := preset_name.capitalize() if PRESETS.has(preset_name) else "Custom"
	var auto_str := ("Auto:%d(T%d)" % [target_fps, auto_tier]) if auto_fps_enabled else "Auto:OFF"
	var vis_chunks := city_world.get_visible_chunk_count() if city_world != null else 0
	var total_chunks := city_world.chunk_roots.size() if city_world != null else 0
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	return "Perf: %s | %.1fms (1%%: %d) | Scale: %d%% | %s | Chunks: %d/%d | Draws: %d" % [
		p_lbl,
		avg_frame_ms,
		int(round(p1_low_fps)),
		int(round(effective_render_scale * 100.0)),
		auto_str,
		vis_chunks,
		total_chunks,
		draws,
	]


func apply_all_settings(save_disk: bool = false) -> void:
	# Compute effective parameters combining user baseline + Auto-FPS Governor relief tier
	var eff_scale := render_scale
	var eff_upscaler := upscaler_mode
	var eff_shadow := shadow_tier
	var eff_ssao := ssao_enabled
	var eff_ssr := ssr_mode
	var eff_glow := glow_enabled
	var eff_probe := probe_tier
	var eff_int_probes := interior_probes_enabled
	var eff_chunk_dist := chunk_dist
	var eff_keep_sky := keep_skyline
	var eff_traffic := traffic_density
	var eff_crowd := crowd_density
	var eff_sim_vis := sim_vis_scale
	var eff_lod_div := far_lod_divisor
	var eff_rain := rain_particles
	var eff_splash := splash_budget
	var eff_lamps := lamp_budget

	if auto_fps_enabled and auto_tier > 0:
		match auto_tier:
			1:
				eff_scale = maxf(0.55, eff_scale * 0.90)
				eff_sim_vis = maxf(0.50, eff_sim_vis * 0.90)
			2:
				eff_scale = maxf(0.55, eff_scale * 0.82)
				eff_ssr = 0
				eff_sim_vis = maxf(0.50, eff_sim_vis * 0.82)
				eff_lod_div = maxi(eff_lod_div, 5)
			3:
				eff_scale = maxf(0.55, eff_scale * 0.75)
				eff_ssr = 0
				eff_ssao = false
				eff_shadow = mini(eff_shadow, 2)
				eff_chunk_dist = minf(eff_chunk_dist, 720.0)
				eff_sim_vis = maxf(0.48, eff_sim_vis * 0.75)
				eff_splash = mini(eff_splash, 4)
			4:
				eff_scale = maxf(0.55, eff_scale * 0.68)
				eff_ssr = 0
				eff_ssao = false
				eff_shadow = mini(eff_shadow, 2)
				eff_probe = mini(eff_probe, 1)
				eff_int_probes = false
				eff_chunk_dist = minf(eff_chunk_dist, 600.0)
				eff_traffic = maxf(0.25, eff_traffic * 0.72)
				eff_crowd = maxf(0.25, eff_crowd * 0.72)
				eff_sim_vis = maxf(0.45, eff_sim_vis * 0.68)
				eff_rain = mini(eff_rain, 1000)
				eff_splash = 0
			5:
				eff_scale = maxf(0.52, eff_scale * 0.62)
				eff_ssr = 0
				eff_ssao = false
				eff_shadow = mini(eff_shadow, 1)
				eff_probe = 0
				eff_int_probes = false
				eff_chunk_dist = minf(eff_chunk_dist, 500.0)
				eff_keep_sky = false
				eff_traffic = maxf(0.22, eff_traffic * 0.55)
				eff_crowd = maxf(0.22, eff_crowd * 0.55)
				eff_sim_vis = 0.52
				eff_lod_div = 6
				eff_rain = mini(eff_rain, 650)
				eff_splash = 0
				eff_lamps = mini(eff_lamps, 8)
			_:
				eff_scale = maxf(0.50, eff_scale * 0.55)
				eff_ssr = 0
				eff_ssao = false
				eff_glow = false
				eff_shadow = 0
				eff_probe = 0
				eff_int_probes = false
				eff_chunk_dist = minf(eff_chunk_dist, 420.0)
				eff_keep_sky = false
				eff_traffic = maxf(0.20, eff_traffic * 0.40)
				eff_crowd = maxf(0.20, eff_crowd * 0.40)
				eff_sim_vis = 0.45
				eff_lod_div = 6
				eff_rain = mini(eff_rain, 450)
				eff_splash = 0
				eff_lamps = mini(eff_lamps, 6)
		if eff_scale < 0.98 and eff_upscaler == 0:
			eff_upscaler = 1 # Automatically use FSR 2.2 when scaling below native resolution

	effective_render_scale = clampf(eff_scale, 0.50, 1.00)

	# 1. Viewport 3D Resolution Scale + Upscaler + VSync
	var vp := get_viewport()
	if vp != null and not _is_headless():
		vp.scaling_3d_scale = effective_render_scale
		if effective_render_scale >= 0.995:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		elif eff_upscaler == 1:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		elif eff_upscaler == 2:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		else:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		if not OS.has_feature("movie"):
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)

	# 2. Atmosphere / Shadows / SSAO / SSR / Glow / Reflection Probes / Rain / Lamps
	if atmosphere != null:
		atmosphere.apply_quality_settings({
			"shadow_tier": eff_shadow,
			"ssao": eff_ssao,
			"ssr_mode": eff_ssr,
			"glow": eff_glow,
			"probe_tier": eff_probe,
			"rain_particles": eff_rain,
			"splash_budget": eff_splash,
			"lamp_budget": eff_lamps,
		})

	# 3. CityWorld Chunk Distance Culling & Interior Probes
	if city_world != null:
		city_world.enable_interior_probes = eff_int_probes
		city_world.set_chunk_cull_distance(eff_chunk_dist, eff_keep_sky)
		if city_world.traffic_manager != null and is_instance_valid(city_world.traffic_manager):
			city_world.traffic_manager.set_performance_profile(eff_traffic, eff_sim_vis, eff_lod_div)
		if city_world.crowd_manager != null and is_instance_valid(city_world.crowd_manager):
			city_world.crowd_manager.set_performance_profile(eff_crowd, eff_sim_vis, eff_lod_div)

	_sync_ui_from_state()
	if save_disk and _persist_enabled:
		_save_settings_to_disk()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var kc: int = event.keycode
	if kc == KEY_F4:
		set_menu_open(not _menu_open)
		get_viewport().set_input_as_handled()
	elif kc == KEY_ESCAPE and _menu_open:
		set_menu_open(false)
		get_viewport().set_input_as_handled()
	elif kc == KEY_F2:
		var lbl := cycle_preset()
		status_message.emit("Quality Preset: %s (Scale %d%%)" % [lbl, int(round(effective_render_scale * 100.0))])
		get_viewport().set_input_as_handled()
	elif kc == KEY_F6:
		set_auto_fps_enabled(not auto_fps_enabled, true)
		status_message.emit("Adaptive Auto-FPS Governor: %s (Target %d FPS)" % ["ON" if auto_fps_enabled else "OFF", target_fps])
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var dt_ms := clampf(delta * 1000.0, 0.5, 250.0)
	_frame_ring[_frame_ring_pos] = dt_ms
	_frame_ring_pos = (_frame_ring_pos + 1) % _frame_ring.size()
	_frame_ring_count = mini(_frame_ring_count + 1, _frame_ring.size())
	_ema_ms = lerpf(_ema_ms, dt_ms, clampf(delta * 2.4, 0.02, 0.25))

	_ui_refresh_timer += delta
	if _ui_refresh_timer >= 0.25:
		_ui_refresh_timer = 0.0
		_recompute_frame_stats()
		if _menu_open and _stats_label != null:
			_stats_label.text = get_hud_summary()

	if auto_fps_enabled and not _is_headless() and not OS.has_feature("movie"):
		_step_auto_fps_governor(delta)


func _recompute_frame_stats() -> void:
	if _frame_ring_count <= 0:
		return
	var vals: Array[float] = []
	vals.resize(_frame_ring_count)
	var sum := 0.0
	for i in range(_frame_ring_count):
		var v := _frame_ring[i]
		vals[i] = v
		sum += v
	vals.sort()
	avg_frame_ms = sum / float(_frame_ring_count)
	var p99_idx := mini(_frame_ring_count - 1, int(float(_frame_ring_count) * 0.99))
	p1_low_fps = 1000.0 / maxf(1.0, vals[p99_idx])


func _step_auto_fps_governor(delta: float) -> void:
	if _gov_cooldown > 0.0:
		_gov_cooldown = maxf(0.0, _gov_cooldown - delta)
		return
	var cur_fps := 1000.0 / maxf(1.0, _ema_ms)
	var low_thresh := float(target_fps) - 5.5
	var high_thresh := float(target_fps) - 1.0
	var target_ms := 1000.0 / maxf(20.0, float(target_fps))

	if cur_fps < low_thresh and auto_tier < 6:
		_gov_down_accum += delta
		_gov_up_accum = 0.0
		if _gov_down_accum >= 1.8:
			_gov_down_accum = 0.0
			_gov_cooldown = 2.2
			auto_tier += 1
			apply_all_settings(false)
			status_message.emit("Auto-FPS Relief -> Tier %d (Scale %d%%)" % [auto_tier, int(round(effective_render_scale * 100.0))])
	elif auto_tier > 0 and (cur_fps >= high_thresh or _ema_ms < target_ms * 0.84):
		_gov_up_accum += delta
		_gov_down_accum = 0.0
		if _gov_up_accum >= 4.5:
			_gov_up_accum = 0.0
			_gov_cooldown = 2.6
			auto_tier -= 1
			apply_all_settings(false)
			status_message.emit("Auto-FPS Restored -> Tier %d (Scale %d%%)" % [auto_tier, int(round(effective_render_scale * 100.0))])
	else:
		_gov_down_accum = maxf(0.0, _gov_down_accum - delta * 0.6)
		_gov_up_accum = maxf(0.0, _gov_up_accum - delta * 0.6)


func _is_headless() -> bool:
	return DisplayServer.get_name().to_lower().contains("headless")


func _save_settings_to_disk() -> void:
	if _is_headless():
		return
	var data := {
		"preset_name": preset_name,
		"render_scale": snapped(render_scale, 0.01),
		"upscaler_mode": upscaler_mode,
		"shadow_tier": shadow_tier,
		"ssao_enabled": ssao_enabled,
		"ssr_mode": ssr_mode,
		"glow_enabled": glow_enabled,
		"probe_tier": probe_tier,
		"interior_probes_enabled": interior_probes_enabled,
		"vsync_enabled": vsync_enabled,
		"chunk_dist": snapped(chunk_dist, 1.0),
		"keep_skyline": keep_skyline,
		"traffic_density": snapped(traffic_density, 0.01),
		"crowd_density": snapped(crowd_density, 0.01),
		"auto_fps_enabled": auto_fps_enabled,
		"target_fps": target_fps,
	}
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()


func _load_settings_from_disk() -> void:
	if _is_headless() or not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return
	var d: Dictionary = parsed
	if d.has("preset_name") and PRESETS.has(String(d["preset_name"])):
		apply_preset(String(d["preset_name"]), false)
	preset_name = String(d.get("preset_name", preset_name))
	render_scale = clampf(float(d.get("render_scale", render_scale)), 0.50, 1.00)
	upscaler_mode = clampi(int(d.get("upscaler_mode", upscaler_mode)), 0, 2)
	shadow_tier = clampi(int(d.get("shadow_tier", shadow_tier)), 0, 4)
	ssao_enabled = bool(d.get("ssao_enabled", ssao_enabled))
	ssr_mode = clampi(int(d.get("ssr_mode", ssr_mode)), 0, 2)
	glow_enabled = bool(d.get("glow_enabled", glow_enabled))
	probe_tier = clampi(int(d.get("probe_tier", probe_tier)), 0, 2)
	interior_probes_enabled = bool(d.get("interior_probes_enabled", interior_probes_enabled))
	vsync_enabled = bool(d.get("vsync_enabled", vsync_enabled))
	chunk_dist = clampf(float(d.get("chunk_dist", chunk_dist)), 380.0, 1900.0)
	keep_skyline = bool(d.get("keep_skyline", keep_skyline))
	traffic_density = clampf(float(d.get("traffic_density", traffic_density)), 0.20, 1.00)
	crowd_density = clampf(float(d.get("crowd_density", crowd_density)), 0.20, 1.00)
	auto_fps_enabled = bool(d.get("auto_fps_enabled", auto_fps_enabled))
	target_fps = clampi(int(d.get("target_fps", target_fps)), 24, 120)


func _build_panel_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "PerformanceSettingsPanel"
	_panel.visible = false
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -396
	_panel.offset_top = 16
	_panel.offset_right = -16
	_panel.offset_bottom = 660
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.070, 0.095, 0.90)
	style.border_color = Color(0.28, 0.44, 0.62, 0.72)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 7)
	_panel.add_child(vbox)

	# Header
	var hdr := HBoxContainer.new()
	vbox.add_child(hdr)
	var title := Label.new()
	title.text = "Performance & Realism Controls"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.86, 0.94, 1.0))
	hdr.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Close [F4]"
	close_btn.pressed.connect(func() -> void: set_menu_open(false))
	hdr.add_child(close_btn)

	_stats_label = Label.new()
	_stats_label.text = "Perf: Initializing..."
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_label.add_theme_font_size_override("font_size", 12)
	_stats_label.add_theme_color_override("font_color", Color(0.68, 0.90, 0.80))
	vbox.add_child(_stats_label)

	vbox.add_child(HSeparator.new())

	# Quality Presets Row
	var p_lbl := Label.new()
	p_lbl.text = "Quality Preset [F2 cycles]:"
	p_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(p_lbl)
	var p_row := HBoxContainer.new()
	p_row.add_theme_constant_override("separation", 6)
	vbox.add_child(p_row)
	for pk in PRESET_ORDER:
		var btn := Button.new()
		btn.text = pk.capitalize()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.toggle_mode = true
		var key_copy := pk
		btn.pressed.connect(func() -> void:
			var lbl := apply_preset(key_copy, true)
			status_message.emit("Quality Preset: %s" % lbl)
		)
		p_row.add_child(btn)
		_preset_buttons[pk] = btn

	# Adaptive Auto-FPS Governor Row
	var gov_row := HBoxContainer.new()
	vbox.add_child(gov_row)
	_auto_fps_chk = CheckButton.new()
	_auto_fps_chk.text = "Auto-FPS Governor [F6]"
	_auto_fps_chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auto_fps_chk.toggled.connect(func(v: bool) -> void:
		if _syncing_ui:
			return
		set_auto_fps_enabled(v, true)
	)
	gov_row.add_child(_auto_fps_chk)

	_target_fps_opt = OptionButton.new()
	_target_fps_opt.add_item("30 FPS", 30)
	_target_fps_opt.add_item("45 FPS", 45)
	_target_fps_opt.add_item("60 FPS", 60)
	_target_fps_opt.item_selected.connect(func(idx: int) -> void:
		if _syncing_ui:
			return
		target_fps = _target_fps_opt.get_item_id(idx)
		apply_all_settings(true)
	)
	gov_row.add_child(_target_fps_opt)

	vbox.add_child(HSeparator.new())

	# 3D Render Scale + Upscaler
	var sc_res := _add_slider_row(vbox, "3D Render Scale", 50.0, 100.0, 5.0, "%")
	_scale_slider = sc_res["slider"]
	_scale_val_lbl = sc_res["value"]
	_scale_slider.value_changed.connect(func(val: float) -> void:
		if _syncing_ui:
			return
		preset_name = "custom"
		render_scale = clampf(val / 100.0, 0.50, 1.00)
		apply_all_settings(true)
	)

	_upscaler_opt = _add_option_row(vbox, "3D Upscaler", ["Bilinear (Native)", "FSR 2.2 (Sharp)", "FSR 1.0 (Fast)"])
	_upscaler_opt.item_selected.connect(func(idx: int) -> void:
		if _syncing_ui:
			return
		preset_name = "custom"
		upscaler_mode = idx
		apply_all_settings(true)
	)

	_shadow_opt = _add_option_row(vbox, "Sun Shadows", ["Off (Fastest)", "Low (72m)", "Medium (122m)", "High (175m)", "Ultra (230m)"])
	_shadow_opt.item_selected.connect(func(idx: int) -> void:
		if _syncing_ui:
			return
		preset_name = "custom"
		shadow_tier = idx
		apply_all_settings(true)
	)

	_ssr_opt = _add_option_row(vbox, "Reflections (SSR)", ["Off", "Wet Roads Only", "Always On"])
	_ssr_opt.item_selected.connect(func(idx: int) -> void:
		if _syncing_ui:
			return
		preset_name = "custom"
		ssr_mode = idx
		apply_all_settings(true)
	)

	_probe_opt = _add_option_row(vbox, "City Refl. Probes", ["Off (Zero Bake)", "1 Center Probe", "3x3 City Grid"])
	_probe_opt.item_selected.connect(func(idx: int) -> void:
		if _syncing_ui:
			return
		preset_name = "custom"
		probe_tier = idx
		apply_all_settings(true)
	)

	# Toggles Grid (2x2)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	vbox.add_child(grid)

	_ssao_chk = CheckButton.new()
	_ssao_chk.text = "SSAO"
	_ssao_chk.toggled.connect(func(v: bool) -> void:
		if _syncing_ui:
			return
		preset_name = "custom"
		ssao_enabled = v
		apply_all_settings(true)
	)
	grid.add_child(_ssao_chk)

	_glow_chk = CheckButton.new()
	_glow_chk.text = "HDR Bloom"
	_glow_chk.toggled.connect(func(v: bool) -> void:
		if _syncing_ui:
			return
		preset_name = "custom"
		glow_enabled = v
		apply_all_settings(true)
	)
	grid.add_child(_glow_chk)

	_vsync_chk = CheckButton.new()
	_vsync_chk.text = "VSync"
	_vsync_chk.toggled.connect(func(v: bool) -> void:
		if _syncing_ui:
			return
		vsync_enabled = v
		apply_all_settings(true)
	)
	grid.add_child(_vsync_chk)

	_int_probe_chk = CheckButton.new()
	_int_probe_chk.text = "Interior Probes"
	_int_probe_chk.toggled.connect(func(v: bool) -> void:
		if _syncing_ui:
			return
		preset_name = "custom"
		interior_probes_enabled = v
		apply_all_settings(true)
	)
	grid.add_child(_int_probe_chk)

	vbox.add_child(HSeparator.new())

	# Distance, Traffic & Crowd Density Sliders
	var d_res := _add_slider_row(vbox, "Chunk Draw Dist", 400.0, 1800.0, 50.0, "m")
	_dist_slider = d_res["slider"]
	_dist_val_lbl = d_res["value"]
	_dist_slider.value_changed.connect(func(val: float) -> void:
		if _syncing_ui:
			return
		preset_name = "custom"
		chunk_dist = val
		apply_all_settings(true)
	)

	var t_res := _add_slider_row(vbox, "Traffic Density", 20.0, 100.0, 5.0, "%")
	_traffic_slider = t_res["slider"]
	_traffic_val_lbl = t_res["value"]
	_traffic_slider.value_changed.connect(func(val: float) -> void:
		if _syncing_ui:
			return
		preset_name = "custom"
		traffic_density = clampf(val / 100.0, 0.20, 1.00)
		apply_all_settings(true)
	)

	var c_res := _add_slider_row(vbox, "NPC Crowd Density", 20.0, 100.0, 5.0, "%")
	_crowd_slider = c_res["slider"]
	_crowd_val_lbl = c_res["value"]
	_crowd_slider.value_changed.connect(func(val: float) -> void:
		if _syncing_ui:
			return
		preset_name = "custom"
		crowd_density = clampf(val / 100.0, 0.20, 1.00)
		apply_all_settings(true)
	)

	# Footer action row
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	vbox.add_child(foot)
	var reset_btn := Button.new()
	reset_btn.text = "Reset High Default"
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_btn.pressed.connect(func() -> void:
		auto_fps_enabled = false
		vsync_enabled = true
		apply_preset("high", true)
		status_message.emit("Reset graphics settings to High Default")
	)
	foot.add_child(reset_btn)


func _add_option_row(parent: VBoxContainer, label_text: String, items: Array[String]) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(lbl)
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(165, 0)
	for it in items:
		opt.add_item(it)
	row.add_child(opt)
	return opt


func _add_slider_row(parent: VBoxContainer, label_text: String, min_v: float, max_v: float, step_v: float, unit: String) -> Dictionary:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	parent.add_child(wrap)
	var top := HBoxContainer.new()
	wrap.add_child(top)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 12)
	top.add_child(lbl)
	var val_lbl := Label.new()
	val_lbl.text = "100" + unit
	val_lbl.add_theme_font_size_override("font_size", 12)
	val_lbl.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0))
	top.add_child(val_lbl)
	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step_v
	sl.value = max_v
	wrap.add_child(sl)
	return {"slider": sl, "value": val_lbl}


func _sync_ui_from_state() -> void:
	if _panel == null:
		return
	_syncing_ui = true
	for pk in _preset_buttons.keys():
		var b: Button = _preset_buttons[pk]
		b.button_pressed = (pk == preset_name)
	if _auto_fps_chk != null:
		_auto_fps_chk.button_pressed = auto_fps_enabled
	if _target_fps_opt != null:
		var t_idx := 2
		if target_fps <= 35:
			t_idx = 0
		elif target_fps <= 50:
			t_idx = 1
		_target_fps_opt.select(t_idx)
	if _scale_slider != null:
		_scale_slider.value = round(render_scale * 100.0)
		_scale_val_lbl.text = "%d%% (eff %d%%)" % [int(round(render_scale * 100.0)), int(round(effective_render_scale * 100.0))]
	if _upscaler_opt != null:
		_upscaler_opt.select(clampi(upscaler_mode, 0, 2))
	if _shadow_opt != null:
		_shadow_opt.select(clampi(shadow_tier, 0, 4))
	if _ssr_opt != null:
		_ssr_opt.select(clampi(ssr_mode, 0, 2))
	if _probe_opt != null:
		_probe_opt.select(clampi(probe_tier, 0, 2))
	if _ssao_chk != null:
		_ssao_chk.button_pressed = ssao_enabled
	if _glow_chk != null:
		_glow_chk.button_pressed = glow_enabled
	if _vsync_chk != null:
		_vsync_chk.button_pressed = vsync_enabled
	if _int_probe_chk != null:
		_int_probe_chk.button_pressed = interior_probes_enabled
	if _dist_slider != null:
		_dist_slider.value = chunk_dist
		_dist_val_lbl.text = "%dm" % int(round(chunk_dist))
	if _traffic_slider != null:
		_traffic_slider.value = round(traffic_density * 100.0)
		_traffic_val_lbl.text = "%d%%" % int(round(traffic_density * 100.0))
	if _crowd_slider != null:
		_crowd_slider.value = round(crowd_density * 100.0)
		_crowd_val_lbl.text = "%d%%" % int(round(crowd_density * 100.0))
	if _stats_label != null:
		_stats_label.text = get_hud_summary()
	_syncing_ui = false
