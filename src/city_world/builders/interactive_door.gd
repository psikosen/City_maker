class_name InteractiveDoor
extends Node3D

## Physical hinged door with separate interaction state, collision shape,
## and blueprint metadata for persistence.

signal door_toggled(door_id: String, is_open: bool)

var door_id: String = ""
var building_id: String = ""
var door_width: float = 1.3
var door_height: float = 2.4
var is_open: bool = false
var _target_angle: float = 0.0
var _current_angle: float = 0.0
var _door_body: StaticBody3D = null


func setup(p_door_id: String, p_building_id: String, p_width: float, p_height: float, commercial_glass: bool, mats: MaterialLibrary) -> void:
	door_id = p_door_id
	building_id = p_building_id
	door_width = p_width
	door_height = p_height
	name = "Door_%s" % p_door_id

	_door_body = StaticBody3D.new()
	_door_body.name = "DoorLeafBody"
	_door_body.set_meta("door_node", self)
	_door_body.set_meta("building_id", building_id)
	add_child(_door_body)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(door_width, door_height, 0.08)
	col.shape = box
	col.position = Vector3(door_width * 0.5, door_height * 0.5, 0.0)
	_door_body.add_child(col)

	set_process(false)

	# Merge door frame / leaf visuals into one multi-surface ArrayMesh to eliminate draw-call bloat.
	var surf_boxes := {}
	if commercial_glass:
		surf_boxes[mats.dark_metal_mat] = [
			[Vector3(0.09, door_height, 0.08), Vector3(0.045, door_height * 0.5, 0.0)],
			[Vector3(0.09, door_height, 0.08), Vector3(door_width - 0.045, door_height * 0.5, 0.0)],
			[Vector3(door_width, 0.10, 0.08), Vector3(door_width * 0.5, door_height - 0.05, 0.0)],
			[Vector3(door_width, 0.16, 0.08), Vector3(door_width * 0.5, 0.08, 0.0)],
		]
		surf_boxes[mats.glass_dark_mat] = [
			[Vector3(maxf(0.2, door_width - 0.18), door_height - 0.26, 0.03), Vector3(door_width * 0.5, door_height * 0.5 + 0.03, 0.0)],
		]
		surf_boxes[mats.light_metal_mat] = [
			[Vector3(0.04, 0.45, 0.14), Vector3(door_width - 0.18, 1.05, 0.0)],
		]
	else:
		surf_boxes[mats.wood_door_mat] = [
			[Vector3(door_width, door_height, 0.07), Vector3(door_width * 0.5, door_height * 0.5, 0.0)],
		]
		surf_boxes[mats.glass_warm_mat] = [
			[Vector3(door_width * 0.45, 0.45, 0.08), Vector3(door_width * 0.5, door_height * 0.72, 0.0)],
		]
		surf_boxes[mats.light_metal_mat] = [
			[Vector3(0.06, 0.06, 0.14), Vector3(door_width - 0.14, 1.0, 0.0)],
		]

	var arr_mesh := ArrayMesh.new()
	var surf_idx := 0
	for mat_k in surf_boxes.keys():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for entry in surf_boxes[mat_k]:
			_emit_box_st(st, entry[1], entry[0])
		st.commit(arr_mesh)
		arr_mesh.surface_set_material(surf_idx, mat_k as Material)
		surf_idx += 1

	var mi := MeshInstance3D.new()
	mi.mesh = arr_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 90.0
	mi.visibility_range_end_margin = 12.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_door_body.add_child(mi)


func toggle() -> void:
	set_open(not is_open, false)


func set_open(open_state: bool, instant: bool = false) -> void:
	is_open = open_state
	_target_angle = PI * 0.52 if is_open else 0.0
	if instant:
		_current_angle = _target_angle
		rotation.y = _current_angle
		set_process(false)
	else:
		set_process(true)
	door_toggled.emit(door_id, is_open)


func _process(delta: float) -> void:
	if not is_equal_approx(_current_angle, _target_angle):
		_current_angle = lerpf(_current_angle, _target_angle, minf(1.0, delta * 9.0))
		if absf(_current_angle - _target_angle) < 0.005:
			_current_angle = _target_angle
			set_process(false)
		rotation.y = _current_angle
	else:
		set_process(false)


func _emit_box_st(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var p000 := center + Vector3(-h.x, -h.y, -h.z)
	var p100 := center + Vector3(h.x, -h.y, -h.z)
	var p110 := center + Vector3(h.x, h.y, -h.z)
	var p010 := center + Vector3(-h.x, h.y, -h.z)
	var p001 := center + Vector3(-h.x, -h.y, h.z)
	var p101 := center + Vector3(h.x, -h.y, h.z)
	var p111 := center + Vector3(h.x, h.y, h.z)
	var p011 := center + Vector3(-h.x, h.y, h.z)
	var quads := [
		[p011, p111, p001, p101, Vector3(0, 0, 1)],
		[p110, p010, p100, p000, Vector3(0, 0, -1)],
		[p010, p011, p000, p001, Vector3(-1, 0, 0)],
		[p111, p110, p101, p100, Vector3(1, 0, 0)],
		[p010, p110, p011, p111, Vector3(0, 1, 0)],
		[p001, p101, p000, p100, Vector3(0, -1, 0)],
	]
	for q in quads:
		var n: Vector3 = q[4]
		var pts := [q[0], q[1], q[2], q[1], q[3], q[2]]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for i in range(6):
			st.set_normal(n)
			st.set_uv(uvs[i])
			st.add_vertex(pts[i])
