class_name PlayerController
extends CharacterBody3D

## First-person explorer controller with curb step-up, door interaction,
## blueprint raycast inspection, flycam toggle, and save/reload shortcuts.

signal status_message(msg: String)

@export var walk_speed: float = 5.4
@export var sprint_speed: float = 9.8
@export var fly_speed: float = 22.0
@export var fly_sprint_speed: float = 55.0
@export var jump_velocity: float = 5.2
@export var mouse_sensitivity: float = 0.0022
@export var turn_speed: float = 2.2
@export var pan_look_sensitivity: float = 0.018
@export var max_step_height: float = 0.26

var city_world: CityWorld = null
var atmosphere: AtmosphereController = null
var fly_mode: bool = false
var is_swimming: bool = false
var camera_submerged: bool = false
var submerged_depth: float = 0.0
var ui_menu_open: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _mouse_released_by_user: bool = false
var _head: Node3D = null
var _cam: Camera3D = null
var _ray: RayCast3D = null
var _col: CollisionShape3D = null
var _ignore_next_motion: bool = false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	floor_max_angle = deg_to_rad(48.0)
	floor_snap_length = 0.28

	_col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.75
	_col.shape = cap
	_col.position = Vector3(0.0, 0.875, 0.0)
	add_child(_col)

	_head = Node3D.new()
	_head.position = Vector3(0.0, 1.62, 0.0)
	add_child(_head)

	_cam = Camera3D.new()
	_cam.far = 2600.0
	_cam.fov = 72.0
	_head.add_child(_cam)

	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0.0, 0.0, -4.2)
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true
	_head.add_child(_ray)

	if not _is_headless():
		_capture_mouse.call_deferred()


func _is_headless() -> bool:
	return DisplayServer.get_name().to_lower().contains("headless") or OS.has_feature("movie")


func _is_automated_cam() -> bool:
	if _is_headless():
		return true
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with("--write-movie") or arg == "--benchmark":
			return true
	return false


func get_camera_world_pos() -> Vector3:
	if _cam != null and _cam.is_inside_tree():
		return _cam.global_position
	if _head != null and _head.is_inside_tree():
		return _head.global_position
	return global_position + Vector3(0.0, 1.62, 0.0)


func _update_submerged_state() -> void:
	camera_submerged = false
	submerged_depth = 0.0
	if city_world == null or city_world.plan == null or city_world.plan.terrain == null:
		return
	var terr := city_world.plan.terrain
	var cpos := get_camera_world_pos()
	var wl := terr.water_level
	if cpos.y < wl + 0.08:
		var ground_h := terr.sample_height(cpos.x, cpos.z)
		var in_ocean := terr.beach_enabled and cpos.z > terr.get_beach_shore_z(cpos.x) - 6.0
		var in_creek := terr.distance_to_creek(Vector2(cpos.x, cpos.z)) < terr.creek_half_width + 4.0
		if ground_h < wl - 0.05 or in_ocean or in_creek:
			if cpos.y < wl + 0.04:
				camera_submerged = true
				submerged_depth = maxf(0.02, wl - cpos.y)


func _capture_mouse() -> void:
	if _is_automated_cam() or _mouse_released_by_user:
		return
	DisplayServer.window_move_to_foreground()
	_ignore_next_motion = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_IN and not _mouse_released_by_user and not _is_automated_cam():
		_ignore_next_motion = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _apply_look_delta(dyaw: float, dpitch: float) -> void:
	_yaw = wrapf(_yaw + dyaw, -PI, PI)
	_pitch = clampf(_pitch + dpitch, -1.48, 1.48)
	rotation.y = _yaw
	if _head != null:
		_head.rotation.x = _pitch


func place_at(pos: Vector3, yaw: float = 0.0, pitch: float = 0.0) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	_yaw = wrapf(yaw, -PI, PI)
	_pitch = clampf(pitch, -1.48, 1.48)
	rotation.y = _yaw
	if _head != null:
		_head.rotation.x = _pitch
	_update_submerged_state()


func set_fly_mode(enabled: bool) -> void:
	fly_mode = enabled
	if _col != null:
		_col.disabled = enabled
	velocity = Vector3.ZERO


func _input(event: InputEvent) -> void:
	if ui_menu_open:
		return
	if event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED and not _is_automated_cam():
			_mouse_released_by_user = false
			_ignore_next_motion = true
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			_mouse_released_by_user = true
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			_mouse_released_by_user = false
			_ignore_next_motion = true
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		if _is_automated_cam():
			return
		if _ignore_next_motion:
			_ignore_next_motion = false
			return
		var captured: bool = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		var drag_mask: int = int(MOUSE_BUTTON_MASK_LEFT) | int(MOUSE_BUTTON_MASK_RIGHT) | int(MOUSE_BUTTON_MASK_MIDDLE)
		var dragging: bool = (int(event.button_mask) & drag_mask) != 0
		if captured or dragging or not _mouse_released_by_user:
			if absf(event.relative.x) < 350.0 and absf(event.relative.y) < 350.0:
				_apply_look_delta(-event.relative.x * mouse_sensitivity, -event.relative.y * mouse_sensitivity)
		return

	if event is InputEventPanGesture:
		_apply_look_delta(-event.delta.x * pan_look_sensitivity, -event.delta.y * pan_look_sensitivity)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fly"):
		fly_mode = not fly_mode
		_col.disabled = fly_mode
		velocity = Vector3.ZERO
		status_message.emit("Fly Mode ON" if fly_mode else "Walk Mode ON (Collision Active)")

	if event.is_action_pressed("interact"):
		_try_interact()

	if event.is_action_pressed("next_seed") and city_world != null:
		var next_s := city_world.config.world_seed + 1
		var p := city_world.build_from_seed(next_s)
		place_at(p.spawn_position, p.spawn_yaw)
		status_message.emit("Generated Seed %d (%d buildings)" % [next_s, p.blueprints.size()])

	if event.is_action_pressed("cycle_time") and atmosphere != null:
		status_message.emit("Time Preset: %s" % atmosphere.cycle_time_preset())

	if event.is_action_pressed("cycle_weather") and atmosphere != null:
		status_message.emit("Weather: %s" % atmosphere.cycle_weather())

	if event.is_action_pressed("toggle_time_pause") and atmosphere != null:
		var now_paused := atmosphere.toggle_paused()
		status_message.emit("Day/Night Clock: %s (%s)" % ["Paused" if now_paused else "Running", atmosphere.get_time_string()])

	if event.is_action_pressed("save_state") and city_world != null:
		var atm_state: Dictionary = atmosphere.get_state_dict() if atmosphere != null else {}
		if city_world.save_to_disk(global_position, _yaw, PersistenceManager.DEFAULT_SAVE_PATH, atm_state):
			status_message.emit("Saved seed %d + ChangedWorldState" % city_world.config.world_seed)

	if event.is_action_pressed("load_state") and city_world != null:
		var data := city_world.load_from_disk()
		if not data.is_empty():
			var changed: Dictionary = data.get("changed_world_state", {})
			var pp: Array = changed.get("player_position", [])
			if pp.size() == 3:
				place_at(Vector3(float(pp[0]), float(pp[1]), float(pp[2])), float(changed.get("player_yaw", 0.0)))
			if atmosphere != null and changed.has("atmosphere"):
				atmosphere.apply_state_dict(changed["atmosphere"])
			status_message.emit("Reloaded seed %d + saved state" % city_world.config.world_seed)


func _physics_process(delta: float) -> void:
	if atmosphere != null:
		var time_scrub := (1.0 if Input.is_action_pressed("time_forward") else 0.0) - (1.0 if Input.is_action_pressed("time_back") else 0.0)
		if time_scrub != 0.0:
			atmosphere.set_time_of_day(atmosphere.time_of_day_hour + time_scrub * 2.4 * delta)

	var key_yaw := (1.0 if Input.is_key_pressed(KEY_LEFT) else 0.0) - (1.0 if Input.is_key_pressed(KEY_RIGHT) else 0.0)
	var key_pitch := (1.0 if Input.is_key_pressed(KEY_UP) else 0.0) - (1.0 if Input.is_key_pressed(KEY_DOWN) else 0.0)
	if key_yaw != 0.0 or key_pitch != 0.0:
		_apply_look_delta(key_yaw * turn_speed * delta, key_pitch * turn_speed * 0.75 * delta)

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var sprinting := Input.is_action_pressed("sprint")

	if fly_mode:
		is_swimming = false
		var spd := fly_sprint_speed if sprinting else fly_speed
		var cam_basis := _head.global_transform.basis
		var move := (cam_basis.z * input_dir.y + cam_basis.x * input_dir.x)
		if Input.is_action_pressed("jump"):
			move += Vector3.UP
		if Input.is_key_pressed(KEY_C) or Input.is_key_pressed(KEY_CTRL):
			move -= Vector3.UP
		if move.length_squared() > 0.001:
			move = move.normalized() * spd
		global_position += move * delta
		_update_submerged_state()
		return

	# Check water immersion for 3D swimming & diving physics in Walk mode
	var water_lvl := -999.0
	var in_water_basin := false
	if city_world != null and city_world.plan != null and city_world.plan.terrain != null:
		var terr := city_world.plan.terrain
		water_lvl = terr.water_level
		var gh := terr.sample_height(global_position.x, global_position.z)
		in_water_basin = (gh < water_lvl - 0.12) or (terr.beach_enabled and global_position.z > terr.get_beach_shore_z(global_position.x) - 3.0)

	if in_water_basin and global_position.y < water_lvl - 0.85:
		is_swimming = true
		var swim_spd := (sprint_speed * 0.92) if sprinting else (walk_speed * 0.88)
		var cam_b := _head.global_transform.basis
		var swim_move := (cam_b.z * input_dir.y + cam_b.x * input_dir.x)
		if Input.is_action_pressed("jump"):
			swim_move.y += 1.0
		if Input.is_key_pressed(KEY_C) or Input.is_key_pressed(KEY_CTRL):
			swim_move.y -= 1.0
		if swim_move.length_squared() > 0.001:
			swim_move = swim_move.normalized() * swim_spd
			velocity = velocity.lerp(swim_move, clampf(delta * 7.5, 0.0, 1.0))
		else:
			# Gentle water drag + near-neutral buoyancy when hovering underwater
			velocity = velocity.lerp(Vector3(0.0, -0.15, 0.0), clampf(delta * 5.0, 0.0, 1.0))
		# Allow breaching/jumping onto shore or pier when swimming up near the surface
		if Input.is_action_pressed("jump") and global_position.y >= water_lvl - 1.25:
			velocity.y = maxf(velocity.y, jump_velocity * 0.92)
		move_and_slide()
		_update_submerged_state()
		return

	is_swimming = false
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var wish_dir := (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y))
	wish_dir.y = 0.0
	if wish_dir.length_squared() > 0.001:
		wish_dir = wish_dir.normalized()

	var spd := sprint_speed if sprinting else walk_speed
	velocity.x = wish_dir.x * spd
	velocity.z = wish_dir.z * spd

	# Curb / low-step assist before move_and_slide when grounded.
	if is_on_floor() and wish_dir.length_squared() > 0.01:
		var horiz_motion := Vector3(velocity.x, 0.0, velocity.z) * delta
		if test_move(global_transform, horiz_motion):
			var up_tf := global_transform.translated(Vector3(0.0, max_step_height, 0.0))
			if not test_move(up_tf, horiz_motion):
				var stepped_tf := up_tf.translated(horiz_motion)
				var down_col := KinematicCollision3D.new()
				if test_move(stepped_tf, Vector3(0.0, -max_step_height - 0.05, 0.0), down_col):
					var rem := down_col.get_remainder()
					var new_pos := stepped_tf.origin + down_col.get_travel()
					if new_pos.y > global_position.y - 0.02 and new_pos.y <= global_position.y + max_step_height + 0.02:
						global_position = new_pos
						_update_submerged_state()
						return

	move_and_slide()
	_update_submerged_state()

	# Safety catch: never let player fall infinitely below terrain if spawned off-map.
	if city_world != null and city_world.plan != null and global_position.y < -15.0:
		place_at(city_world.plan.spawn_position, 0.0)
		status_message.emit("Respawned at safe sidewalk")


func _try_interact() -> void:
	_ray.force_raycast_update()
	if not _ray.is_colliding():
		return
	var collider := _ray.get_collider()
	if collider != null and collider.has_meta("door_node"):
		var door: InteractiveDoor = collider.get_meta("door_node")
		door.toggle()
		status_message.emit("%s %s" % ["Opened" if door.is_open else "Closed", door.door_id])
		return
	var elev_hit := InteractiveElevator.get_hit_info(collider, _ray.get_collider_shape())
	if not elev_hit.is_empty():
		var elev: InteractiveElevator = elev_hit["elevator"]
		var msg := elev.interact(String(elev_hit["action"]), int(elev_hit["floor"]))
		status_message.emit(msg)


func get_raycast_target_info() -> Dictionary:
	if _ray == null:
		return {}
	_ray.force_raycast_update()
	if not _ray.is_colliding():
		return {}
	var col := _ray.get_collider()
	if col == null:
		return {}
	var info := {"hit": true}
	if col.has_meta("door_node"):
		var door: InteractiveDoor = col.get_meta("door_node")
		info["door"] = door
	var elev_hit := InteractiveElevator.get_hit_info(col, _ray.get_collider_shape())
	if not elev_hit.is_empty():
		info["elevator"] = elev_hit["elevator"]
		info["elev_action"] = elev_hit["action"]
		info["elev_floor"] = elev_hit["floor"]
	if col.has_meta("blueprint"):
		info["blueprint"] = col.get_meta("blueprint")
	elif col.has_meta("building_id") and city_world != null and city_world.plan != null:
		info["blueprint"] = city_world.plan.get_blueprint_by_id(str(col.get_meta("building_id")))
	return info
