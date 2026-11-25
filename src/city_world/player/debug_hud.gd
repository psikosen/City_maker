class_name DebugHUD
extends CanvasLayer

## Displays crosshair, door interaction prompt, blueprint inspector,
## chunk coordinates, and Milestone 3 weather/time status.

var city_world: CityWorld = null
var player: PlayerController = null
var atmosphere: AtmosphereController = null
var performance: Node = null

var _info_panel: PanelContainer = null
var _info_label: Label = null
var _prompt_label: Label = null
var _status_label: Label = null
var _crosshair: ColorRect = null
var _status_timer: float = 0.0
var _hud_refresh_timer: float = 99.0
var _show_debug: bool = true


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	_crosshair = ColorRect.new()
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.color = Color(1.0, 1.0, 1.0, 0.85)
	_crosshair.size = Vector2(4, 4)
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.offset_left = -2
	_crosshair.offset_top = -2
	_crosshair.offset_right = 2
	_crosshair.offset_bottom = 2
	add_child(_crosshair)

	_prompt_label = Label.new()
	_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	_prompt_label.offset_left = -180
	_prompt_label.offset_top = 24
	_prompt_label.offset_right = 180
	_prompt_label.offset_bottom = 56
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 16)
	_prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt_label.add_theme_constant_override("outline_size", 4)
	add_child(_prompt_label)

	_status_label = Label.new()
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status_label.offset_top = -48
	_status_label.offset_bottom = -16
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color(0.75, 0.96, 0.85))
	_status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_status_label.add_theme_constant_override("outline_size", 4)
	add_child(_status_label)

	_info_panel = PanelContainer.new()
	_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_panel.position = Vector2(14, 14)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.11, 0.72)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_info_panel.add_theme_stylebox_override("panel", style)
	add_child(_info_panel)

	_info_label = Label.new()
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_label.add_theme_font_size_override("font_size", 13)
	_info_label.add_theme_color_override("font_color", Color(0.92, 0.95, 0.98))
	_info_panel.add_child(_info_label)


func show_status(msg: String) -> void:
	_status_label.text = msg
	_status_timer = 3.5


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_hud"):
		_show_debug = not _show_debug
		_info_panel.visible = _show_debug


func _process(delta: float) -> void:
	if _status_timer > 0.0:
		_status_timer -= delta
		if _status_timer <= 0.0:
			_status_label.text = ""

	if player == null:
		return

	var target := player.get_raycast_target_info()
	if target.has("door"):
		var door: InteractiveDoor = target["door"]
		_prompt_label.text = "[E] %s Door (%s)" % ["Close" if door.is_open else "Open", door.building_id]
	elif target.has("elevator"):
		var elev: InteractiveElevator = target["elevator"]
		_prompt_label.text = "[E] %s" % elev.get_action_label(String(target.get("elev_action", "call")), int(target.get("elev_floor", 0)))
	else:
		_prompt_label.text = ""

	if not _show_debug or city_world == null or city_world.plan == null:
		return

	# Refresh heavy telemetry & string assembly at ~6 Hz instead of every frame (keeps [E] prompt at 60 Hz)
	_hud_refresh_timer += delta
	if _hud_refresh_timer < 0.16:
		return
	_hud_refresh_timer = 0.0

	var p := city_world.plan
	var pos := player.global_position
	var cx := int(floor(pos.x / p.config.chunk_size))
	var cz := int(floor(pos.z / p.config.chunk_size))
	var mode_str := "FLYCAM" if player.fly_mode else ("SWIM" if player.is_swimming else ("WALK (Grounded)" if player.is_on_floor() else "WALK (Air)"))
	if player.camera_submerged:
		mode_str += " [Underwater -%.1fm]" % player.submerged_depth

	var env_line := "Sky/Weather: Initializing..."
	if atmosphere != null:
		var paused_tag := " [Paused]" if atmosphere.time_paused else ""
		var shelter_tag := ""
		if player != null and (atmosphere.weather_rain > 0.05 or atmosphere.weather_snow > 0.05) and atmosphere.is_point_sheltered(player.global_position + Vector3(0.0, 1.0, 0.0)):
			shelter_tag = "  |  Indoors (Dry)"
		var snow_tag := ""
		if atmosphere.weather_snow_depth > 0.01 or atmosphere.weather_snow > 0.02:
			snow_tag = "  |  Snow: %d%%" % int(round(atmosphere.weather_snow_depth * 100.0))
			if atmosphere.weather_slush > 0.05:
				snow_tag += " (Slush %d%%)" % int(round(atmosphere.weather_slush * 100.0))
		env_line = "Time: %s (%s)%s  |  Weather: %s  |  Wet: %d%%  |  Puddles: %d%%%s  |  Lamps: %d%s" % [
			atmosphere.get_time_string(),
			atmosphere.get_phase_name(),
			paused_tag,
			atmosphere.get_weather_label(),
			int(round(atmosphere.weather_wetness * 100.0)),
			int(round(atmosphere.weather_puddles * 100.0)),
			snow_tag,
			atmosphere.get_active_streetlamp_count(),
			shelter_tag,
		]

	var sim_line := ""
	if city_world.traffic_manager != null and city_world.crowd_manager != null:
		var ts: Dictionary = city_world.traffic_manager.get_traffic_stats()
		var cs: Dictionary = city_world.crowd_manager.get_crowd_stats()
		var umb_str := (" | %d umbrellas" % int(cs.get("umbrellas", 0))) if int(cs.get("umbrellas", 0)) > 0 else ""
		sim_line = "Traffic: %d/%d active (%s, %d buses, %d LC)  |  NPCs: %d (%d walk, %d wait, %d plaza, %d indoors%s)" % [
			int(ts.get("active", 0)),
			int(ts.get("total_pool", 0)),
			String(ts.get("period", "")),
			int(ts.get("buses", 0)),
			int(ts.get("lane_changes", 0)),
			int(cs.get("total", 0)),
			int(cs.get("walking", 0)),
			int(cs.get("waiting_crosswalk", 0)) + int(cs.get("waiting_bus", 0)),
			int(cs.get("lingering", 0)),
			int(cs.get("indoors", 0)),
			umb_str,
		]

	var lines: Array[String] = [
		"Procedural City 2028 • Milestone 10 (%dx%dm)" % [int(round(p.config.world_size)), int(round(p.config.world_size))],
		"Seed: %d  |  Hash: %s  |  FPS: %d" % [p.config.world_seed, p.plan_hash, Engine.get_frames_per_second()],
		env_line,
		"Buildings: %d (%d active interiors)  |  Parcels: %d  |  Roads: %d edges / %d lanes" % [p.blueprints.size(), city_world.get_active_interior_count(), p.parcels.size(), p.road_graph.edges.size(), p.road_graph.lanes.size()],
		"Pos: (%.1f, %.1f, %.1f)  |  Chunk: (%d, %d)  |  %s" % [pos.x, pos.y, pos.z, cx, cz, mode_str],
		"WASD Move | E Door/Elev | F Fly | T Time | G Weather | F2 Quality | F4 Perf Menu | F6 Auto-FPS | F3 HUD",
	]
	if sim_line != "":
		lines.insert(4, sim_line)
	if performance != null and performance.has_method("get_hud_summary"):
		lines.insert(2, String(performance.call("get_hud_summary")))

	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		lines.append("Mouse unlocked — Click window or drag to look (Esc toggles cursor)")

	if target.has("blueprint") and target["blueprint"] != null:
		var bp: BuildingBlueprint = target["blueprint"]
		var label_tag := (" • " + bp.sign_label) if bp.sign_label != "" else ""
		var venue_tag := (" [" + bp.venue_type + "]") if bp.venue_type != "" else ""
		lines.append("Target: %s%s%s (%s / %s, %d fl, %.1fx%.1fm, zone=%s)" % [bp.id, label_tag, venue_tag, bp.archetype, bp.style, bp.floors, bp.width, bp.depth, bp.district_zone])

	_info_label.text = "\n".join(lines)
