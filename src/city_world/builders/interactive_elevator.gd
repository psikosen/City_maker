class_name InteractiveElevator
extends Node3D

## Working multi-story hydraulic/traction elevator inside tall buildings and hospitals.
## Supports exterior hall call buttons, interior cab UP/DOWN/TOP/LOBBY controls via [E],
## bi-parting safety doors on every landing, live floor indicators, and smooth AnimatableBody3D lift.

const CAB_SPEED := 4.4
const DOOR_SPEED := 3.6
const CAB_CEIL_H := 2.38
const DOOR_OPEN_W := 1.08
const DOOR_OPEN_H := 2.18

var building_id: String = ""
var shaft_rect: Rect2 = Rect2()
var floor_ys: PackedFloat32Array = PackedFloat32Array()
var current_floor: int = 0
var target_floor: int = 0
var door_open_frac: float = 1.0
var is_moving: bool = false

var cab_body: AnimatableBody3D = null
var _cab_door_left: MeshInstance3D = null
var _cab_door_right: MeshInstance3D = null
var _cab_door_col: CollisionShape3D = null
var _cab_floor_label: Label3D = null
var _hall_floors: Array[Dictionary] = []
var _phase: String = "open"  # "open", "closing", "moving", "opening"


func setup(bp: BuildingBlueprint, ib: InteriorBlueprint, mats: MaterialLibrary) -> void:
	building_id = bp.id
	name = "InteractiveElevator_%s" % building_id
	var spec: Dictionary = ib.elevator
	shaft_rect = spec.get("shaft_rect", Rect2())
	floor_ys = spec.get("floor_ys", PackedFloat32Array([0.0]))
	if floor_ys.is_empty():
		return

	var cx := shaft_rect.get_center().x
	var cz := shaft_rect.get_center().y
	var inner_w := maxf(1.56, shaft_rect.size.x - 0.24)
	var inner_d := maxf(1.56, shaft_rect.size.y - 0.24)
	var front_z := shaft_rect.end.y

	# 1. Moving AnimatableBody3D Cab
	cab_body = AnimatableBody3D.new()
	cab_body.name = "ElevatorCab"
	cab_body.sync_to_physics = true
	cab_body.position = Vector3(cx, floor_ys[0], cz)
	cab_body.set_meta("elevator_node", self)
	cab_body.set_meta("building_id", building_id)
	add_child(cab_body)

	# Sleek beveled floor threshold plate (top surface at local y = +0.03m)
	_add_cab_solid(Vector3(inner_w, 0.05, inner_d), Vector3(0.0, 0.005, 0.0), mats.interior_floor_tile_mat)
	# Cab ceiling + recessed warm LED luminaire
	_add_cab_solid(Vector3(inner_w, 0.08, inner_d), Vector3(0.0, CAB_CEIL_H - 0.04, 0.0), mats.elevator_steel_mat)
	_add_cab_mesh(Vector3(inner_w * 0.56, 0.03, inner_d * 0.26), Vector3(0.0, CAB_CEIL_H - 0.09, 0.0), mats.interior_ceiling_light_mat)
	# Rear & side stainless cab walls + cedar/brass accent trim bar
	var wall_h := CAB_CEIL_H - 0.08
	_add_cab_solid(Vector3(inner_w, wall_h, 0.05), Vector3(0.0, wall_h * 0.5 + 0.02, -inner_d * 0.5 + 0.025), mats.elevator_steel_mat)
	_add_cab_mesh(Vector3(inner_w * 0.78, 0.06, 0.04), Vector3(0.0, 0.96, -inner_d * 0.5 + 0.06), mats.wood_cedar_mat)
	_add_cab_solid(Vector3(0.05, wall_h, inner_d), Vector3(-inner_w * 0.5 + 0.025, wall_h * 0.5 + 0.02, 0.0), mats.elevator_steel_mat)
	_add_cab_solid(Vector3(0.05, wall_h, inner_d), Vector3(inner_w * 0.5 - 0.025, wall_h * 0.5 + 0.02, 0.0), mats.elevator_steel_mat)
	_add_cab_mesh(Vector3(0.04, 0.06, inner_d * 0.76), Vector3(-inner_w * 0.5 + 0.06, 0.96, 0.0), mats.wood_cedar_mat)

	# Front cab return jambs + top transom leaving clear 1.08m center doorway
	var front_inner_z := inner_d * 0.5 - 0.03
	var pier_w := maxf(0.18, (inner_w - DOOR_OPEN_W) * 0.5)
	_add_cab_solid(Vector3(pier_w, wall_h, 0.05), Vector3(-DOOR_OPEN_W * 0.5 - pier_w * 0.5, wall_h * 0.5 + 0.02, front_inner_z), mats.elevator_steel_mat)
	_add_cab_solid(Vector3(pier_w, wall_h, 0.05), Vector3(DOOR_OPEN_W * 0.5 + pier_w * 0.5, wall_h * 0.5 + 0.02, front_inner_z), mats.elevator_steel_mat)
	var transom_h := maxf(0.12, wall_h - DOOR_OPEN_H)
	_add_cab_solid(Vector3(DOOR_OPEN_W, transom_h, 0.05), Vector3(0.0, DOOR_OPEN_H + transom_h * 0.5, front_inner_z), mats.elevator_steel_mat)

	# Bi-parting cab safety doors + unified travel barrier collider
	var cab_door_col_node := CollisionShape3D.new()
	var cab_door_box := BoxShape3D.new()
	cab_door_box.size = Vector3(DOOR_OPEN_W, DOOR_OPEN_H, 0.05)
	cab_door_col_node.shape = cab_door_box
	cab_door_col_node.position = Vector3(0.0, DOOR_OPEN_H * 0.5 + 0.02, front_inner_z - 0.03)
	cab_door_col_node.disabled = true
	cab_body.add_child(cab_door_col_node)
	_cab_door_col = cab_door_col_node

	var leaf_w := DOOR_OPEN_W * 0.5 + 0.02
	_cab_door_left = _add_cab_mesh(Vector3(leaf_w, DOOR_OPEN_H, 0.035), Vector3(-0.78, DOOR_OPEN_H * 0.5 + 0.02, front_inner_z - 0.03), mats.elevator_steel_mat)
	_cab_door_right = _add_cab_mesh(Vector3(leaf_w, DOOR_OPEN_H, 0.035), Vector3(0.78, DOOR_OPEN_H * 0.5 + 0.02, front_inner_z - 0.03), mats.elevator_steel_mat)

	# Interior right-wall control panel with 4 interactive raycast shapes
	var panel_x := inner_w * 0.5 - 0.065
	_add_cab_mesh(Vector3(0.03, 0.92, 0.48), Vector3(panel_x, 1.24, 0.16), mats.dark_metal_mat)
	_cab_floor_label = Label3D.new()
	_cab_floor_label.text = _fmt_floor_tag(0)
	_cab_floor_label.font_size = 44
	_cab_floor_label.pixel_size = 0.0024
	_cab_floor_label.modulate = Color(0.45, 0.96, 1.0)
	_cab_floor_label.outline_size = 4
	_cab_floor_label.no_depth_test = false
	_cab_floor_label.position = Vector3(panel_x - 0.022, 1.58, 0.16)
	_cab_floor_label.rotation.y = -PI * 0.5
	cab_body.add_child(_cab_floor_label)

	var btn_specs := [
		{"action": "up", "label": "UP +1", "z": 0.05, "y": 1.34, "mat": mats.medical_teal_mat},
		{"action": "down", "label": "DN -1", "z": 0.27, "y": 1.34, "mat": mats.medical_teal_mat},
		{"action": "top", "label": "TOP", "z": 0.05, "y": 1.08, "mat": mats.ada_tactile_mat},
		{"action": "lobby", "label": "LOBBY", "z": 0.27, "y": 1.08, "mat": mats.bollard_glow_mat},
	]
	for bs in btn_specs:
		var b_cs := CollisionShape3D.new()
		var b_box := BoxShape3D.new()
		b_box.size = Vector3(0.08, 0.20, 0.18)
		b_cs.shape = b_box
		b_cs.position = Vector3(panel_x - 0.02, float(bs["y"]), float(bs["z"]))
		b_cs.set_meta("elev_action", String(bs["action"]))
		cab_body.add_child(b_cs)

		_add_cab_mesh(Vector3(0.022, 0.15, 0.15), Vector3(panel_x - 0.022, float(bs["y"]), float(bs["z"])), bs["mat"])
		var bl := Label3D.new()
		bl.text = String(bs["label"])
		bl.font_size = 24
		bl.pixel_size = 0.0018
		bl.modulate = Color(0.98, 0.99, 1.0)
		bl.outline_size = 4
		bl.position = Vector3(panel_x - 0.038, float(bs["y"]), float(bs["z"]))
		bl.rotation.y = -PI * 0.5
		cab_body.add_child(bl)

	# 2. Landing Hall Doors, Call Stations, and Digital Indicators on every story
	_hall_floors.clear()
	for fi in range(floor_ys.size()):
		var fy := float(floor_ys[fi])
		var start_open := (fi == 0)
		var l_off := -0.78 if start_open else -0.27
		var r_off := 0.78 if start_open else 0.27

		var hall_door_z := front_z - 0.03
		var left_leaf := _build_hall_leaf(Vector3(cx + l_off, fy + DOOR_OPEN_H * 0.5, hall_door_z), Vector3(leaf_w, DOOR_OPEN_H, 0.04), mats.elevator_steel_mat)
		var right_leaf := _build_hall_leaf(Vector3(cx + r_off, fy + DOOR_OPEN_H * 0.5, hall_door_z), Vector3(leaf_w, DOOR_OPEN_H, 0.04), mats.elevator_steel_mat)

		var hall_lbl := Label3D.new()
		hall_lbl.text = "ELEV  %s" % _fmt_floor_tag(0)
		hall_lbl.font_size = 34
		hall_lbl.pixel_size = 0.0022
		hall_lbl.modulate = Color(0.45, 0.96, 1.0)
		hall_lbl.outline_size = 4
		hall_lbl.position = Vector3(cx, fy + DOOR_OPEN_H + 0.16, front_z + 0.04)
		add_child(hall_lbl)

		# Exterior hall call station mounted on right shaft pier
		var call_body := StaticBody3D.new()
		call_body.name = "HallCall_F%d" % fi
		call_body.position = Vector3(cx + DOOR_OPEN_W * 0.5 + 0.24, fy + 1.18, front_z + 0.04)
		call_body.set_meta("elevator_node", self)
		call_body.set_meta("elev_action", "call")
		call_body.set_meta("elev_floor", fi)
		var call_cs := CollisionShape3D.new()
		var call_box := BoxShape3D.new()
		call_box.size = Vector3(0.22, 0.34, 0.10)
		call_cs.shape = call_box
		call_body.add_child(call_cs)
		var plate_mi := MeshInstance3D.new()
		var plate_m := BoxMesh.new()
		plate_m.size = Vector3(0.14, 0.26, 0.03)
		plate_mi.mesh = plate_m
		plate_mi.material_override = mats.dark_metal_mat
		call_body.add_child(plate_mi)
		var btn_mi := MeshInstance3D.new()
		var btn_m := BoxMesh.new()
		btn_m.size = Vector3(0.07, 0.07, 0.04)
		btn_mi.mesh = btn_m
		btn_mi.material_override = mats.bollard_glow_mat
		call_body.add_child(btn_mi)
		add_child(call_body)

		_hall_floors.append({
			"floor": fi,
			"cx": cx,
			"left": left_leaf,
			"right": right_leaf,
			"label": hall_lbl,
			"is_open": start_open,
		})
	_set_cab_door_barrier(false)


static func get_hit_info(collider: Object, shape_idx: int) -> Dictionary:
	if collider == null or not collider.has_meta("elevator_node"):
		return {}
	var elev: InteractiveElevator = collider.get_meta("elevator_node")
	if collider.has_meta("elev_action"):
		return {
			"elevator": elev,
			"action": String(collider.get_meta("elev_action")),
			"floor": int(collider.get_meta("elev_floor", 0)),
		}
	if collider is CollisionObject3D:
		var co := collider as CollisionObject3D
		var owner_id := co.shape_find_owner(shape_idx)
		if owner_id != -1:
			var owner_obj := co.shape_owner_get_owner(owner_id)
			if owner_obj != null and owner_obj.has_meta("elev_action"):
				return {
					"elevator": elev,
					"action": String(owner_obj.get_meta("elev_action")),
					"floor": int(owner_obj.get_meta("elev_floor", 0)),
				}
	return {}


func _physics_process(delta: float) -> void:
	if cab_body == null or floor_ys.is_empty():
		return

	match _phase:
		"closing":
			door_open_frac = maxf(0.0, door_open_frac - DOOR_SPEED * delta)
			_apply_door_positions()
			if door_open_frac <= 0.001:
				door_open_frac = 0.0
				_set_cab_door_barrier(true)
				_phase = "moving"
				is_moving = true
		"moving":
			var target_y := float(floor_ys[target_floor])
			var new_y := move_toward(cab_body.position.y, target_y, CAB_SPEED * delta)
			cab_body.position.y = new_y
			_update_floor_indicators(_nearest_floor_to_y(new_y))
			if absf(new_y - target_y) < 0.004:
				cab_body.position.y = target_y
				current_floor = target_floor
				is_moving = false
				_update_floor_indicators(current_floor)
				_phase = "opening"
		"opening":
			door_open_frac = minf(1.0, door_open_frac + DOOR_SPEED * delta)
			_apply_door_positions()
			if door_open_frac >= 0.999:
				door_open_frac = 1.0
				_set_cab_door_barrier(false)
				_phase = "open"


func interact(action: String, caller_floor: int = 0) -> String:
	if floor_ys.is_empty():
		return "Elevator offline"
	var max_fl := floor_ys.size() - 1
	var dest := current_floor
	match action:
		"call":
			dest = clampi(caller_floor, 0, max_fl)
		"up":
			dest = clampi((target_floor if is_moving else current_floor) + 1, 0, max_fl)
		"down":
			dest = clampi((target_floor if is_moving else current_floor) - 1, 0, max_fl)
		"top":
			dest = max_fl
		"lobby":
			dest = 0
		_:
			dest = clampi(caller_floor, 0, max_fl)

	if dest == current_floor and _phase == "open":
		return "Elevator ready at %s" % _fmt_floor_tag(current_floor)

	request_floor(dest)
	return "Elevator heading to %s (%s)" % [_fmt_floor_tag(dest), building_id]


func request_floor(fl_idx: int) -> void:
	if floor_ys.is_empty():
		return
	target_floor = clampi(fl_idx, 0, floor_ys.size() - 1)
	if target_floor == current_floor and absf(cab_body.position.y - float(floor_ys[target_floor])) < 0.02:
		is_moving = false
		_phase = "opening"
		_set_cab_door_barrier(false)
		return
	if _phase == "open" or _phase == "opening":
		_set_cab_door_barrier(true)
		_phase = "closing"
	elif _phase == "moving":
		is_moving = true


func get_action_label(action: String, caller_floor: int = 0) -> String:
	var max_fl := maxi(0, floor_ys.size() - 1)
	match action:
		"call":
			return "Call Elevator (%s, Cab %s)" % [_fmt_floor_tag(caller_floor), _fmt_floor_tag(current_floor)]
		"up":
			return "Elevator Up -> %s" % _fmt_floor_tag(mini(max_fl, current_floor + 1))
		"down":
			return "Elevator Down -> %s" % _fmt_floor_tag(maxi(0, current_floor - 1))
		"top":
			return "Elevator Top Floor -> %s" % _fmt_floor_tag(max_fl)
		"lobby":
			return "Elevator Lobby -> %s" % _fmt_floor_tag(0)
	return "Use Elevator"


func _apply_door_positions() -> void:
	var off := lerpf(0.27, 0.78, door_open_frac)
	if _cab_door_left != null:
		_cab_door_left.position.x = -off
	if _cab_door_right != null:
		_cab_door_right.position.x = off
	for h in _hall_floors:
		var fi := int(h["floor"])
		var h_frac := door_open_frac if (fi == current_floor and _phase != "moving") else 0.0
		var h_off := lerpf(0.27, 0.78, h_frac)
		var cx := float(h["cx"])
		(h["left"] as Node3D).position.x = cx - h_off
		(h["right"] as Node3D).position.x = cx + h_off


func _set_cab_door_barrier(closed: bool) -> void:
	if _cab_door_col != null:
		_cab_door_col.disabled = not closed
	for h in _hall_floors:
		var fi := int(h["floor"])
		var allow_open := (not closed) and (fi == current_floor) and (_phase != "moving")
		var left_body := (h["left"] as Node3D).get_node_or_null("DoorBody") as StaticBody3D
		var right_body := (h["right"] as Node3D).get_node_or_null("DoorBody") as StaticBody3D
		if left_body != null:
			(left_body.get_child(0) as CollisionShape3D).disabled = allow_open
		if right_body != null:
			(right_body.get_child(0) as CollisionShape3D).disabled = allow_open


func _nearest_floor_to_y(y: float) -> int:
	var best := 0
	var best_d := INF
	for i in range(floor_ys.size()):
		var d := absf(float(floor_ys[i]) - y)
		if d < best_d:
			best_d = d
			best = i
	return best


func _update_floor_indicators(disp_floor: int) -> void:
	var tag := _fmt_floor_tag(disp_floor)
	if _cab_floor_label != null:
		_cab_floor_label.text = tag
	for h in _hall_floors:
		(h["label"] as Label3D).text = "ELEV  %s" % tag


func _fmt_floor_tag(fi: int) -> String:
	return "G (F0)" if fi == 0 else "F%d" % fi


func _add_cab_solid(size: Vector3, pos: Vector3, mat: Material) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	cab_body.add_child(cs)
	_add_cab_mesh(size, pos, mat)


func _add_cab_mesh(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	cab_body.add_child(mi)
	return mi


func _build_hall_leaf(pos: Vector3, size: Vector3, mat: Material) -> Node3D:
	var wrap := Node3D.new()
	wrap.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	wrap.add_child(mi)

	var body := StaticBody3D.new()
	body.name = "DoorBody"
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	wrap.add_child(body)
	add_child(wrap)
	return wrap
