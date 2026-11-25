class_name FurnitureBuilder
extends RefCounted

## Builds parametric multi-part 3D interior furniture meshes and Jolt Physics colliders.
## All items align strictly with FurnitureGenerator canonical space (+Z = front, +Y = up).


static func build_item(
	fn: Dictionary,
	body: StaticBody3D,
	sts: Dictionary
) -> void:
	var kind: String = String(fn["kind"])
	var pos: Vector3 = fn["pos"]
	var sz: Vector3 = fn["size"]
	var yaw: float = float(fn["yaw"])
	var has_col := bool(fn.get("collider", true))

	if has_col:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = sz
		cs.shape = box
		cs.transform = Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0.0, sz.y * 0.5, 0.0))
		body.add_child(cs)

	var basis := Basis(Vector3.UP, yaw)
	var wood_st: SurfaceTool = sts["wood"]
	var fabric_st: SurfaceTool = sts["fabric"]
	var dark_metal_st: SurfaceTool = sts["dark_metal"]
	var light_metal_st: SurfaceTool = sts["light_metal"]
	var light_st: SurfaceTool = sts["light"]
	var foliage_st: SurfaceTool = sts["foliage"]
	var recycle_st: SurfaceTool = sts["recycle"]
	var rubber_st: SurfaceTool = sts.get("rubber", dark_metal_st)
	var accent_st: SurfaceTool = sts.get("accent", fabric_st)
	var limestone_st: SurfaceTool = sts.get("limestone", light_metal_st)
	var gold_st: SurfaceTool = sts.get("gold", light_st)
	var police_blue_st: SurfaceTool = sts.get("police_blue", accent_st)
	var emergency_red_st: SurfaceTool = sts.get("emergency_red", accent_st)

	match kind:
		"counter", "reception_counter":
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 0.05, 0.0), Vector3(sz.x * 0.94, 0.10, sz.z * 0.78), basis)
			_emit_box_basis(wood_st, pos + Vector3(0.0, sz.y * 0.44, 0.0), Vector3(sz.x * 0.98, sz.y * 0.76, sz.z * 0.86), basis)
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, sz.y * 0.85, 0.0), Vector3(sz.x, 0.06, sz.z), basis)
			_emit_box_basis(wood_st, pos + Vector3(0.0, sz.y - 0.04, 0.0) + basis.z * (sz.z * 0.28), Vector3(sz.x * 0.88, 0.14, 0.20), basis)
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, sz.y + 0.16, 0.0) - basis.z * (sz.z * 0.08), Vector3(0.42, 0.26, 0.04), basis)
			_emit_box_basis(light_st, pos + Vector3(0.0, sz.y + 0.16, 0.0) - basis.z * (sz.z * 0.11), Vector3(0.36, 0.20, 0.02), basis)

		"desk", "workstation_desk":
			var top_y := sz.y - 0.03
			_emit_box_basis(wood_st, pos + Vector3(0.0, top_y, 0.0), Vector3(sz.x, 0.06, sz.z), basis)
			_emit_box_basis(wood_st, pos + Vector3(0.0, top_y - 0.20, 0.0) - basis.z * (sz.z * 0.36), Vector3(sz.x * 0.82, 0.32, 0.04), basis)
			for lx: float in [-sz.x * 0.43, sz.x * 0.43]:
				_emit_box_basis(dark_metal_st, pos + basis.x * lx + Vector3(0.0, top_y * 0.5, 0.0), Vector3(0.055, top_y, sz.z * 0.86), basis)
			# Dual-aspect workstation monitor facing +Z toward user chair
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, sz.y + 0.05, 0.0) - basis.z * (sz.z * 0.20), Vector3(0.14, 0.10, 0.12), basis)
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, sz.y + 0.23, 0.0) - basis.z * (sz.z * 0.18), Vector3(0.66, 0.34, 0.04), basis)
			_emit_box_basis(light_st, pos + Vector3(0.0, sz.y + 0.23, 0.0) - basis.z * (sz.z * 0.155), Vector3(0.60, 0.28, 0.015), basis)

		"office_chair":
			# 5-spoke base + pneumatic stem + seat cushion + backrest (-Z)
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 0.04, 0.0), Vector3(sz.x * 0.78, 0.05, 0.06), basis)
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 0.04, 0.0), Vector3(0.06, 0.05, sz.z * 0.78), basis)
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, 0.24, 0.0), Vector3(0.06, 0.36, 0.06), basis)
			_emit_box_basis(fabric_st, pos + Vector3(0.0, 0.46, 0.02), Vector3(sz.x * 0.86, 0.09, sz.z * 0.84), basis)
			_emit_box_basis(fabric_st, pos + Vector3(0.0, 0.74, 0.0) - basis.z * (sz.z * 0.34), Vector3(sz.x * 0.78, 0.46, 0.09), basis)
			for ax: float in [-sz.x * 0.44, sz.x * 0.44]:
				_emit_box_basis(dark_metal_st, pos + basis.x * ax + Vector3(0.0, 0.56, 0.02), Vector3(0.05, 0.20, sz.z * 0.56), basis)

		"dining_chair":
			var seat_y := 0.45
			for cx_s: float in [-sz.x * 0.38, sz.x * 0.38]:
				for cz_s: float in [-sz.z * 0.38, sz.z * 0.38]:
					_emit_box_basis(wood_st, pos + basis.x * cx_s + basis.z * cz_s + Vector3(0.0, seat_y * 0.5, 0.0), Vector3(0.045, seat_y, 0.045), basis)
			_emit_box_basis(fabric_st, pos + Vector3(0.0, seat_y + 0.03, 0.0), Vector3(sz.x * 0.92, 0.06, sz.z * 0.92), basis)
			_emit_box_basis(wood_st, pos + Vector3(0.0, 0.70, 0.0) - basis.z * (sz.z * 0.38), Vector3(sz.x * 0.88, 0.44, 0.05), basis)

		"sofa":
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 0.06, 0.0), Vector3(sz.x * 0.92, 0.12, sz.z * 0.88), basis)
			_emit_box_basis(fabric_st, pos + Vector3(0.0, 0.27, 0.04), Vector3(sz.x * 0.96, 0.32, sz.z * 0.88), basis)
			_emit_box_basis(fabric_st, pos + Vector3(0.0, 0.60, 0.0) - basis.z * (sz.z * 0.34), Vector3(sz.x * 0.96, 0.46, sz.z * 0.26), basis)
			for ax: float in [-sz.x * 0.44, sz.x * 0.44]:
				_emit_box_basis(wood_st, pos + basis.x * ax + Vector3(0.0, 0.34, 0.0), Vector3(0.13, 0.48, sz.z * 0.94), basis)

		"armchair":
			_emit_box_basis(fabric_st, pos + Vector3(0.0, 0.25, 0.03), Vector3(sz.x * 0.88, 0.34, sz.z * 0.86), basis)
			_emit_box_basis(fabric_st, pos + Vector3(0.0, 0.58, 0.0) - basis.z * (sz.z * 0.34), Vector3(sz.x * 0.88, 0.44, sz.z * 0.24), basis)
			for ax: float in [-sz.x * 0.42, sz.x * 0.42]:
				_emit_box_basis(wood_st, pos + basis.x * ax + Vector3(0.0, 0.32, 0.0), Vector3(0.11, 0.48, sz.z * 0.92), basis)

		"coffee_table", "table", "dining_table", "conference_table":
			var ty := sz.y - 0.03
			_emit_box_basis(wood_st, pos + Vector3(0.0, ty, 0.0), Vector3(sz.x, 0.055, sz.z), basis)
			if kind == "conference_table":
				for px: float in [-sz.x * 0.28, sz.x * 0.28]:
					_emit_box_basis(dark_metal_st, pos + basis.x * px + Vector3(0.0, ty * 0.5, 0.0), Vector3(0.12, ty, sz.z * 0.58), basis)
				_emit_box_basis(light_metal_st, pos + Vector3(0.0, sz.y + 0.01, 0.0), Vector3(0.28, 0.02, 0.16), basis)
			else:
				for tx: float in [-sz.x * 0.40, sz.x * 0.40]:
					for tz: float in [-sz.z * 0.38, sz.z * 0.38]:
						_emit_box_basis(dark_metal_st, pos + basis.x * tx + basis.z * tz + Vector3(0.0, ty * 0.5, 0.0), Vector3(0.055, ty, 0.055), basis)

		"bed", "queen_bed":
			_emit_box_basis(wood_st, pos + Vector3(0.0, 0.16, 0.0), Vector3(sz.x, 0.26, sz.z), basis)
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, 0.38, 0.02), Vector3(sz.x * 0.94, 0.22, sz.z * 0.92), basis)
			_emit_box_basis(fabric_st, pos + Vector3(0.0, 0.42, 0.0) + basis.z * (sz.z * 0.14), Vector3(sz.x * 0.96, 0.18, sz.z * 0.64), basis)
			for px: float in [-sz.x * 0.23, sz.x * 0.23]:
				_emit_box_basis(light_metal_st, pos + basis.x * px + Vector3(0.0, 0.53, 0.0) - basis.z * (sz.z * 0.34), Vector3(sz.x * 0.38, 0.09, 0.32), basis)
			_emit_box_basis(wood_st, pos + Vector3(0.0, 0.56, 0.0) - basis.z * (sz.z * 0.46), Vector3(sz.x * 1.02, 0.90, 0.09), basis)

		"nightstand":
			_emit_box_basis(wood_st, pos + Vector3(0.0, sz.y * 0.48, 0.0), Vector3(sz.x, sz.y * 0.88, sz.z), basis)
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, sz.y * 0.68, 0.0) + basis.z * (sz.z * 0.51), Vector3(sz.x * 0.36, 0.03, 0.03), basis)
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, sz.y + 0.09, 0.0), Vector3(0.11, 0.16, 0.11), basis)
			_emit_box_basis(light_st, pos + Vector3(0.0, sz.y + 0.22, 0.0), Vector3(0.20, 0.14, 0.20), basis)

		"kitchen_counter":
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 0.05, 0.0), Vector3(sz.x * 0.96, 0.10, sz.z * 0.82), basis)
			_emit_box_basis(wood_st, pos + Vector3(0.0, sz.y * 0.47, 0.0), Vector3(sz.x, sz.y * 0.82, sz.z * 0.92), basis)
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, sz.y - 0.03, 0.0), Vector3(sz.x + 0.02, 0.06, sz.z), basis)
			# Sink basin + faucet
			_emit_box_basis(dark_metal_st, pos + basis.x * (sz.x * 0.18) + Vector3(0.0, sz.y + 0.01, 0.0), Vector3(0.54, 0.02, 0.42), basis)
			_emit_box_basis(light_metal_st, pos + basis.x * (sz.x * 0.18) + Vector3(0.0, sz.y + 0.12, 0.0) - basis.z * (sz.z * 0.28), Vector3(0.05, 0.22, 0.14), basis)

		"shelf", "bookshelf", "retail_rack", "warehouse_rack":
			var upright_col := light_metal_st if kind == "warehouse_rack" else (wood_st if kind == "bookshelf" else dark_metal_st)
			for ux: float in [-sz.x * 0.46, sz.x * 0.46]:
				for uz: float in [-sz.z * 0.46, sz.z * 0.46]:
					_emit_box_basis(upright_col, pos + basis.x * ux + basis.z * uz + Vector3(0.0, sz.y * 0.5, 0.0), Vector3(0.055, sz.y, 0.055), basis)
			var tiers := 4 if sz.y > 1.7 else 3
			for ti in range(tiers):
				var sy := lerpf(0.24, sz.y - 0.20, float(ti) / float(maxi(1, tiers - 1)))
				_emit_box_basis(wood_st, pos + Vector3(0.0, sy, 0.0), Vector3(sz.x * 0.94, 0.05, sz.z * 0.92), basis)
				if ti < tiers - 1:
					_emit_box_basis(fabric_st, pos + basis.x * (sz.x * 0.16) + Vector3(0.0, sy + 0.14, 0.0), Vector3(sz.x * 0.34, 0.22, sz.z * 0.54), basis)

		"plant_pot":
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, 0.20, 0.0), Vector3(sz.x * 0.78, 0.40, sz.z * 0.78), basis)
			_emit_box_basis(wood_st, pos + Vector3(0.0, 0.41, 0.0), Vector3(sz.x * 0.68, 0.04, sz.z * 0.68), basis)
			_emit_box_basis(foliage_st, pos + Vector3(0.0, 0.74, 0.0), Vector3(sz.x * 0.92, 0.52, sz.z * 0.92), basis)
			_emit_box_basis(foliage_st, pos + Vector3(0.0, 0.98, 0.0), Vector3(sz.x * 0.62, 0.36, sz.z * 0.62), basis)

		"trashcan_indoor":
			# Brushed charcoal body, stainless collar rim, foot pedal on +Z front
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, sz.y * 0.46, 0.0), Vector3(sz.x * 0.92, sz.y * 0.88, sz.z * 0.92), basis)
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, sz.y - 0.04, 0.0), Vector3(sz.x, 0.08, sz.z), basis)
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, 0.03, 0.0) + basis.z * (sz.z * 0.48), Vector3(0.11, 0.03, 0.07), basis)

		"trashcan_recycle":
			# Twin-bay waste + blue recycling station
			var bay_w := sz.x * 0.45
			var off := sz.x * 0.25
			_emit_box_basis(dark_metal_st, pos - basis.x * off + Vector3(0.0, sz.y * 0.46, 0.0), Vector3(bay_w, sz.y * 0.88, sz.z * 0.92), basis)
			_emit_box_basis(light_metal_st, pos - basis.x * off + Vector3(0.0, sz.y - 0.04, 0.0), Vector3(bay_w + 0.02, 0.08, sz.z), basis)
			_emit_box_basis(dark_metal_st, pos + basis.x * off + Vector3(0.0, sz.y * 0.44, 0.0), Vector3(bay_w, sz.y * 0.84, sz.z * 0.92), basis)
			_emit_box_basis(recycle_st, pos + basis.x * off + Vector3(0.0, sz.y - 0.04, 0.0), Vector3(bay_w + 0.02, 0.09, sz.z), basis)
			_emit_box_basis(recycle_st, pos + basis.x * off + Vector3(0.0, sz.y * 0.56, 0.0) + basis.z * (sz.z * 0.47), Vector3(bay_w * 0.48, 0.14, 0.02), basis)

		"treadmill":
			# Deck frame + rubber running belt + upright masts & console at -Z facing +Z user
			for rx: float in [-sz.x * 0.42, sz.x * 0.42]:
				_emit_box_basis(dark_metal_st, pos + basis.x * rx + Vector3(0.0, 0.11, 0.0) + basis.z * 0.06, Vector3(0.08, 0.14, sz.z * 0.92), basis)
			_emit_box_basis(rubber_st, pos + Vector3(0.0, 0.13, 0.0) + basis.z * 0.10, Vector3(sz.x * 0.72, 0.08, sz.z * 0.82), basis)
			_emit_box_basis(accent_st, pos + Vector3(0.0, 0.18, 0.0) - basis.z * (sz.z * 0.36), Vector3(sz.x * 0.84, 0.16, 0.34), basis)
			for mx: float in [-sz.x * 0.38, sz.x * 0.38]:
				_emit_box_basis(light_metal_st, pos + basis.x * mx + Vector3(0.0, 0.68, 0.0) - basis.z * (sz.z * 0.34), Vector3(0.075, 1.05, 0.10), basis)
				_emit_box_basis(rubber_st, pos + basis.x * mx + Vector3(0.0, 0.94, 0.0) - basis.z * (sz.z * 0.14), Vector3(0.055, 0.06, 0.42), basis)
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 1.18, 0.0) - basis.z * (sz.z * 0.30), Vector3(sz.x * 0.86, 0.28, 0.18), basis)
			_emit_box_basis(light_st, pos + Vector3(0.0, 1.20, 0.0) - basis.z * (sz.z * 0.21), Vector3(sz.x * 0.62, 0.18, 0.03), basis)

		"squat_rack":
			# 4-post power cage, pull-up top beam, spotter bars, racked barbell + bumper plates
			for bx: float in [-sz.x * 0.44, sz.x * 0.44]:
				_emit_box_basis(dark_metal_st, pos + basis.x * bx + Vector3(0.0, 0.05, 0.0), Vector3(0.09, 0.09, sz.z * 0.96), basis)
				_emit_box_basis(accent_st, pos + basis.x * bx + Vector3(0.0, sz.y - 0.06, 0.0), Vector3(0.08, 0.08, sz.z * 0.94), basis)
				_emit_box_basis(light_metal_st, pos + basis.x * bx + Vector3(0.0, 0.72, 0.0), Vector3(0.05, 0.05, sz.z * 0.86), basis)
				for bz: float in [-sz.z * 0.42, sz.z * 0.42]:
					_emit_box_basis(dark_metal_st, pos + basis.x * bx + basis.z * bz + Vector3(0.0, sz.y * 0.5, 0.0), Vector3(0.085, sz.y, 0.085), basis)
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, sz.y - 0.08, 0.0) + basis.z * (sz.z * 0.42), Vector3(sz.x * 0.88, 0.05, 0.05), basis)
			_emit_barbell_with_plates(light_metal_st, rubber_st, accent_st, pos + Vector3(0.0, 1.32, 0.0) - basis.z * (sz.z * 0.24), sz.x * 1.18, basis)

		"weight_bench":
			# Adjustable bench + racked bench-press uprights + loaded barbell
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 0.06, 0.0), Vector3(sz.x * 0.65, 0.08, sz.z * 0.86), basis)
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 0.24, 0.0), Vector3(0.09, 0.30, sz.z * 0.72), basis)
			_emit_box_basis(rubber_st, pos + Vector3(0.0, 0.44, 0.0) + basis.z * 0.05, Vector3(0.34, 0.10, sz.z * 0.78), basis)
			for ux: float in [-0.46, 0.46]:
				_emit_box_basis(dark_metal_st, pos + basis.x * ux + Vector3(0.0, 0.52, 0.0) - basis.z * (sz.z * 0.36), Vector3(0.07, 1.02, 0.07), basis)
			_emit_barbell_with_plates(light_metal_st, rubber_st, accent_st, pos + Vector3(0.0, 0.94, 0.0) - basis.z * (sz.z * 0.36), maxf(1.38, sz.x * 1.85), basis)

		"dumbbell_rack":
			# Two-tier A-frame steel dumbbell rack with 5 pairs per tier
			for ax: float in [-sz.x * 0.45, sz.x * 0.45]:
				_emit_box_basis(dark_metal_st, pos + basis.x * ax + Vector3(0.0, sz.y * 0.48, 0.0), Vector3(0.07, sz.y * 0.96, sz.z * 0.76), basis)
			for ti in range(2):
				var ty := 0.38 + float(ti) * 0.38
				var tz := 0.09 - float(ti) * 0.16
				_emit_box_basis(accent_st, pos + Vector3(0.0, ty, 0.0) + basis.z * tz, Vector3(sz.x * 0.94, 0.055, 0.22), basis)
				for di in range(5):
					var dx := lerpf(-sz.x * 0.34, sz.x * 0.34, float(di) / 4.0)
					var dc := pos + basis.x * dx + Vector3(0.0, ty + 0.08, 0.0) + basis.z * tz
					_emit_box_basis(light_metal_st, dc, Vector3(0.04, 0.04, 0.24), basis)
					for side_s: float in [-0.09, 0.09]:
						_emit_box_basis(rubber_st, dc + basis.z * side_s, Vector3(0.11, 0.11, 0.055), basis)

		"exercise_bike":
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 0.05, 0.0), Vector3(sz.x * 0.88, 0.08, sz.z * 0.92), basis)
			_emit_box_basis(accent_st, pos + Vector3(0.0, 0.46, 0.0), Vector3(0.11, 0.72, sz.z * 0.62), basis)
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, 0.42, 0.0) - basis.z * (sz.z * 0.26), Vector3(0.09, 0.44, 0.44), basis)
			_emit_box_basis(rubber_st, pos + Vector3(0.0, 0.90, 0.0) + basis.z * (sz.z * 0.22), Vector3(0.24, 0.08, 0.28), basis)
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 1.06, 0.0) - basis.z * (sz.z * 0.22), Vector3(sz.x * 0.76, 0.06, 0.18), basis)
			_emit_box_basis(light_st, pos + Vector3(0.0, 1.15, 0.0) - basis.z * (sz.z * 0.24), Vector3(0.26, 0.15, 0.04), basis)

		"locker_bank":
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 0.05, 0.0), Vector3(sz.x * 0.98, 0.10, sz.z * 0.94), basis)
			var cols := maxi(2, int(round(sz.x / 0.48)))
			var cw := sz.x / float(cols)
			for ci in range(cols):
				var cx := -sz.x * 0.5 + (float(ci) + 0.5) * cw
				var c_p := pos + basis.x * cx
				_emit_box_basis(light_metal_st, c_p + Vector3(0.0, sz.y * 0.52, 0.0), Vector3(cw - 0.03, sz.y * 0.90, sz.z * 0.92), basis)
				_emit_box_basis(dark_metal_st, c_p + Vector3(0.0, sz.y * 0.80, 0.0) + basis.z * (sz.z * 0.47), Vector3(cw * 0.62, 0.14, 0.02), basis)
				_emit_box_basis(accent_st, c_p + Vector3(0.0, sz.y * 0.55, 0.0) + basis.z * (sz.z * 0.48), Vector3(0.05, 0.18, 0.02), basis)

		"espresso_bar":
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 0.06, 0.0), Vector3(sz.x * 0.96, 0.12, sz.z * 0.88), basis)
			_emit_box_basis(wood_st, pos + Vector3(0.0, 0.52, 0.0), Vector3(sz.x * 0.98, 0.82, sz.z * 0.90), basis)
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, 0.96, 0.0), Vector3(sz.x + 0.02, 0.06, sz.z), basis)
			# Stainless espresso machine (-X), coffee grinder (mid), glowing pastry case (+X)
			var esp_c := pos - basis.x * (sz.x * 0.28)
			_emit_box_basis(light_metal_st, esp_c + Vector3(0.0, 1.18, 0.0), Vector3(0.68, 0.40, 0.48), basis)
			_emit_box_basis(dark_metal_st, esp_c + Vector3(0.0, 1.04, 0.0) + basis.z * 0.25, Vector3(0.64, 0.07, 0.12), basis)
			_emit_box_basis(accent_st, esp_c + Vector3(0.0, 1.40, 0.0), Vector3(0.66, 0.05, 0.44), basis)
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 1.18, 0.0), Vector3(0.22, 0.38, 0.26), basis)
			var disp_c := pos + basis.x * (sz.x * 0.26)
			_emit_box_basis(light_metal_st, disp_c + Vector3(0.0, 1.16, 0.0), Vector3(0.76, 0.36, 0.52), basis)
			_emit_box_basis(light_st, disp_c + Vector3(0.0, 1.18, 0.0) + basis.z * 0.02, Vector3(0.68, 0.26, 0.44), basis)

		"cafe_table":
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 0.03, 0.0), Vector3(sz.x * 0.56, 0.06, sz.z * 0.56), basis)
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, (sz.y - 0.04) * 0.5, 0.0), Vector3(0.08, sz.y - 0.06, 0.08), basis)
			_emit_box_basis(wood_st, pos + Vector3(0.0, sz.y - 0.03, 0.0), Vector3(sz.x, 0.05, sz.z), basis)
			_emit_box_basis(light_metal_st, pos + basis.x * 0.14 + Vector3(0.0, sz.y + 0.045, 0.0), Vector3(0.09, 0.09, 0.09), basis)

		"bakery_rack":
			for ux: float in [-sz.x * 0.46, sz.x * 0.46]:
				_emit_box_basis(dark_metal_st, pos + basis.x * ux + Vector3(0.0, sz.y * 0.5, 0.0), Vector3(0.055, sz.y, sz.z * 0.86), basis)
			for ti in range(4):
				var ty := lerpf(0.28, sz.y - 0.32, float(ti) / 3.0)
				_emit_box_basis(wood_st, pos + Vector3(0.0, ty, 0.0), Vector3(sz.x * 0.94, 0.045, sz.z * 0.88), basis)
				for bi in range(3):
					var bx := lerpf(-sz.x * 0.30, sz.x * 0.30, float(bi) * 0.5)
					_emit_box_basis(accent_st if (ti + bi) % 2 == 0 else wood_st, pos + basis.x * bx + Vector3(0.0, ty + 0.11, 0.0), Vector3(sz.x * 0.24, 0.14, sz.z * 0.54), basis)

		"checkout_lane":
			_emit_box_basis(accent_st, pos + Vector3(0.0, 0.43, 0.0), Vector3(sz.x * 0.96, 0.84, sz.z * 0.88), basis)
			_emit_box_basis(rubber_st, pos - basis.x * (sz.x * 0.16) + Vector3(0.0, 0.88, 0.0), Vector3(sz.x * 0.56, 0.05, sz.z * 0.68), basis)
			_emit_box_basis(light_metal_st, pos + basis.x * (sz.x * 0.28) + Vector3(0.0, 0.88, 0.0), Vector3(sz.x * 0.34, 0.05, sz.z * 0.88), basis)
			_emit_box_basis(dark_metal_st, pos + basis.x * (sz.x * 0.14) + Vector3(0.0, 1.04, 0.0) - basis.z * (sz.z * 0.24), Vector3(0.10, 0.34, 0.10), basis)
			_emit_box_basis(light_st, pos + basis.x * (sz.x * 0.14) + Vector3(0.0, 1.18, 0.0) - basis.z * (sz.z * 0.18), Vector3(0.32, 0.22, 0.04), basis)

		"grocery_gondola":
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 0.10, 0.0), Vector3(sz.x * 0.96, 0.18, sz.z * 0.94), basis)
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, sz.y * 0.52, 0.0), Vector3(sz.x * 0.94, sz.y * 0.88, 0.07), basis)
			for ti in range(4):
				var sy := lerpf(0.26, sz.y - 0.24, float(ti) / 3.0)
				_emit_box_basis(light_metal_st, pos + Vector3(0.0, sy, 0.0), Vector3(sz.x * 0.96, 0.045, sz.z * 0.92), basis)
				for side_s: float in [-0.24, 0.24]:
					for gi in range(4):
						var gx := lerpf(-sz.x * 0.34, sz.x * 0.34, float(gi) / 3.0)
						var pkg_st := accent_st if (gi + ti) % 3 == 0 else (recycle_st if (gi + ti) % 3 == 1 else foliage_st)
						_emit_box_basis(pkg_st, pos + basis.x * gx + basis.z * (sz.z * side_s) + Vector3(0.0, sy + 0.13, 0.0), Vector3(sz.x * 0.18, 0.22, sz.z * 0.28), basis)

		"cooler_case":
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, sz.y * 0.5, 0.0), Vector3(sz.x, sz.y, sz.z * 0.86), basis)
			_emit_box_basis(light_st, pos + Vector3(0.0, sz.y * 0.54, 0.0) + basis.z * (sz.z * 0.18), Vector3(sz.x * 0.90, sz.y * 0.76, sz.z * 0.34), basis)
			for mx: float in [-sz.x * 0.33, 0.0, sz.x * 0.33]:
				_emit_box_basis(light_metal_st, pos + basis.x * mx + Vector3(0.0, sz.y * 0.54, 0.0) + basis.z * (sz.z * 0.44), Vector3(0.055, sz.y * 0.78, 0.06), basis)
			_emit_box_basis(accent_st, pos + Vector3(0.0, sz.y - 0.12, 0.0) + basis.z * (sz.z * 0.44), Vector3(sz.x * 0.96, 0.16, 0.05), basis)

		"bookstore_shelf":
			for sx_u: float in [-sz.x * 0.48, sz.x * 0.48]:
				_emit_box_basis(wood_st, pos + basis.x * sx_u + Vector3(0.0, sz.y * 0.5, 0.0), Vector3(0.06, sz.y, sz.z * 0.94), basis)
			_emit_box_basis(wood_st, pos + Vector3(0.0, sz.y * 0.5, 0.0) - basis.z * (sz.z * 0.44), Vector3(sz.x, sz.y, 0.04), basis)
			var b_mats: Array[SurfaceTool] = [accent_st, fabric_st, recycle_st, foliage_st, dark_metal_st]
			for ti in range(5):
				var sy := lerpf(0.18, sz.y - 0.18, float(ti) / 4.0)
				_emit_box_basis(wood_st, pos + Vector3(0.0, sy, 0.0), Vector3(sz.x * 0.96, 0.045, sz.z * 0.92), basis)
				if ti < 4:
					for bi in range(6):
						var bx := lerpf(-sz.x * 0.37, sz.x * 0.37, float(bi) / 5.0)
						var bh := 0.22 + float((bi * 3 + ti) % 4) * 0.032
						var book_st: SurfaceTool = b_mats[(bi + ti * 2) % b_mats.size()]
						_emit_box_basis(book_st, pos + basis.x * bx + Vector3(0.0, sy + bh * 0.5 + 0.02, 0.0) + basis.z * 0.04, Vector3(sz.x * 0.12, bh, sz.z * 0.60), basis)

		"exam_table":
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, 0.36, 0.0), Vector3(sz.x * 0.86, 0.68, sz.z * 0.82), basis)
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 0.36, 0.0) + basis.x * (sz.x * 0.44), Vector3(0.03, 0.42, sz.z * 0.64), basis)
			_emit_box_basis(recycle_st, pos + Vector3(0.0, 0.76, 0.0), Vector3(sz.x * 0.96, 0.12, sz.z * 0.96), basis)
			_emit_box_basis(recycle_st, pos + Vector3(0.0, 0.85, 0.0) - basis.z * (sz.z * 0.34), Vector3(sz.x * 0.94, 0.14, 0.38), basis)

		"med_cabinet":
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, sz.y * 0.5, 0.0), Vector3(sz.x, sz.y, sz.z * 0.88), basis)
			_emit_box_basis(light_st, pos + Vector3(0.0, sz.y * 0.68, 0.0) + basis.z * (sz.z * 0.22), Vector3(sz.x * 0.88, sz.y * 0.46, sz.z * 0.38), basis)
			_emit_box_basis(accent_st, pos + Vector3(0.0, sz.y * 0.88, 0.0) + basis.z * (sz.z * 0.46), Vector3(0.24, 0.08, 0.03), basis)
			_emit_box_basis(accent_st, pos + Vector3(0.0, sz.y * 0.88, 0.0) + basis.z * (sz.z * 0.46), Vector3(0.08, 0.24, 0.03), basis)

		"dining_booth":
			_emit_box_basis(wood_st, pos + Vector3(0.0, 0.16, 0.0), Vector3(sz.x * 0.96, 0.30, sz.z * 0.88), basis)
			_emit_box_basis(accent_st, pos + Vector3(0.0, 0.36, 0.0) + basis.z * (sz.z * 0.08), Vector3(sz.x * 0.96, 0.14, sz.z * 0.78), basis)
			_emit_box_basis(accent_st, pos + Vector3(0.0, sz.y * 0.62, 0.0) - basis.z * (sz.z * 0.34), Vector3(sz.x * 0.98, sz.y * 0.72, sz.z * 0.24), basis)

		"kitchen_pass":
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, 0.45, 0.0), Vector3(sz.x * 0.98, 0.88, sz.z * 0.92), basis)
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 0.92, 0.0), Vector3(sz.x * 0.92, 0.06, sz.z * 0.80), basis)
			for px: float in [-sz.x * 0.42, sz.x * 0.42]:
				_emit_box_basis(light_metal_st, pos + basis.x * px + Vector3(0.0, 1.12, 0.0), Vector3(0.06, 0.42, 0.06), basis)
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, sz.y - 0.05, 0.0), Vector3(sz.x * 0.96, 0.08, 0.32), basis)
			_emit_box_basis(light_st, pos + Vector3(0.0, sz.y - 0.11, 0.0), Vector3(sz.x * 0.88, 0.03, 0.16), basis)

		"teller_counter":
			_emit_box_basis(wood_st, pos + Vector3(0.0, 0.50, 0.0), Vector3(sz.x * 0.98, 0.98, sz.z * 0.88), basis)
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 1.02, 0.0), Vector3(sz.x, 0.07, sz.z), basis)
			for tx: float in [-sz.x * 0.44, 0.0, sz.x * 0.44]:
				_emit_box_basis(light_metal_st, pos + basis.x * tx + Vector3(0.0, 1.24, 0.0) + basis.z * (sz.z * 0.18), Vector3(0.06, 0.42, 0.08), basis)
			_emit_box_basis(light_st, pos - basis.x * (sz.x * 0.22) + Vector3(0.0, 1.16, 0.0) - basis.z * (sz.z * 0.16), Vector3(0.38, 0.22, 0.04), basis)
			_emit_box_basis(light_st, pos + basis.x * (sz.x * 0.22) + Vector3(0.0, 1.16, 0.0) - basis.z * (sz.z * 0.16), Vector3(0.38, 0.22, 0.04), basis)

		"atm_kiosk":
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, sz.y * 0.5, 0.0), Vector3(sz.x, sz.y, sz.z * 0.88), basis)
			_emit_box_basis(accent_st, pos + Vector3(0.0, sz.y - 0.16, 0.0) + basis.z * (sz.z * 0.46), Vector3(sz.x * 0.88, 0.20, 0.04), basis)
			_emit_box_basis(light_st, pos + Vector3(0.0, sz.y * 0.62, 0.0) + basis.z * (sz.z * 0.45), Vector3(sz.x * 0.56, 0.34, 0.04), basis)
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, sz.y * 0.40, 0.0) + basis.z * (sz.z * 0.48), Vector3(sz.x * 0.72, 0.06, 0.18), basis)

		"safe_vault_cabinet":
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, sz.y * 0.5, 0.0), Vector3(sz.x, sz.y, sz.z * 0.90), basis)
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, sz.y * 0.5, 0.0) + basis.z * (sz.z * 0.46), Vector3(sz.x * 0.84, sz.y * 0.86, 0.08), basis)
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, sz.y * 0.52, 0.0) + basis.z * (sz.z * 0.52), Vector3(0.28, 0.28, 0.06), basis)
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, sz.y * 0.52, 0.0) + basis.z * (sz.z * 0.54), Vector3(0.36, 0.04, 0.05), basis)
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, sz.y * 0.52, 0.0) + basis.z * (sz.z * 0.54), Vector3(0.04, 0.36, 0.05), basis)

		"server_rack":
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, sz.y * 0.5, 0.0), Vector3(sz.x, sz.y, sz.z), basis)
			for ui in range(8):
				var uy := lerpf(0.26, sz.y - 0.22, float(ui) / 7.0)
				_emit_box_basis(light_metal_st, pos + Vector3(0.0, uy, 0.0) + basis.z * (sz.z * 0.49), Vector3(sz.x * 0.84, 0.11, 0.03), basis)
				_emit_box_basis(light_st if ui % 2 == 0 else recycle_st, pos + basis.x * (sz.x * 0.32) + Vector3(0.0, uy, 0.0) + basis.z * (sz.z * 0.51), Vector3(0.10, 0.035, 0.02), basis)

		"studio_console":
			for lx: float in [-sz.x * 0.44, sz.x * 0.44]:
				_emit_box_basis(dark_metal_st, pos + basis.x * lx + Vector3(0.0, 0.38, 0.0), Vector3(0.08, 0.74, sz.z * 0.84), basis)
			_emit_box_basis(wood_st, pos + Vector3(0.0, 0.75, 0.0), Vector3(sz.x, 0.06, sz.z), basis)
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 0.81, 0.0) + basis.z * 0.10, Vector3(sz.x * 0.72, 0.07, sz.z * 0.46), basis)
			for sx_m: float in [-sz.x * 0.38, sz.x * 0.38]:
				_emit_box_basis(dark_metal_st, pos + basis.x * sx_m + Vector3(0.0, 0.96, 0.0) - basis.z * (sz.z * 0.28), Vector3(0.24, 0.36, 0.24), basis)
				_emit_box_basis(accent_st, pos + basis.x * sx_m + Vector3(0.0, 0.92, 0.0) - basis.z * (sz.z * 0.15), Vector3(0.14, 0.14, 0.02), basis)
			_emit_box_basis(light_st, pos + Vector3(0.0, 1.00, 0.0) - basis.z * (sz.z * 0.24), Vector3(sz.x * 0.46, 0.28, 0.04), basis)

		"gallery_pedestal":
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 0.05, 0.0), Vector3(sz.x * 0.92, 0.10, sz.z * 0.92), basis)
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, 0.56, 0.0), Vector3(sz.x * 0.84, 0.96, sz.z * 0.84), basis)
			_emit_box_basis(accent_st, pos + Vector3(0.0, 1.16, 0.0), Vector3(sz.x * 0.52, 0.22, sz.z * 0.52), basis)
			_emit_box_basis(wood_st, pos + Vector3(0.0, 1.38, 0.0), Vector3(sz.x * 0.30, 0.28, sz.z * 0.62), basis)

		"cinema_seats":
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 0.08, 0.0), Vector3(sz.x * 0.96, 0.16, sz.z * 0.84), basis)
			for si in range(3):
				var sx_c := lerpf(-sz.x * 0.32, sz.x * 0.32, float(si) * 0.5)
				_emit_box_basis(accent_st, pos + basis.x * sx_c + Vector3(0.0, 0.34, 0.0) + basis.z * 0.08, Vector3(sz.x * 0.28, 0.20, sz.z * 0.64), basis)
				_emit_box_basis(accent_st, pos + basis.x * sx_c + Vector3(0.0, 0.66, 0.0) - basis.z * (sz.z * 0.28), Vector3(sz.x * 0.28, 0.62, 0.18), basis)
			for ax_c: float in [-sz.x * 0.46, -sz.x * 0.16, sz.x * 0.16, sz.x * 0.46]:
				_emit_box_basis(dark_metal_st, pos + basis.x * ax_c + Vector3(0.0, 0.48, 0.0), Vector3(0.06, 0.22, sz.z * 0.58), basis)

		"cinema_screen":
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, sz.y * 0.5, 0.0), Vector3(sz.x, sz.y * 0.94, sz.z), basis)
			_emit_box_basis(light_st, pos + Vector3(0.0, sz.y * 0.52, 0.0) + basis.z * (sz.z * 0.36), Vector3(sz.x * 0.92, sz.y * 0.78, 0.05), basis)

		"bike_display_stand":
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 0.04, 0.0), Vector3(sz.x * 0.92, 0.07, sz.z * 0.88), basis)
			# Front & rear bike wheel assemblies + diamond frame + handlebars + saddle
			for wx_b: float in [-sz.x * 0.32, sz.x * 0.32]:
				var wc := pos + basis.x * wx_b + Vector3(0.0, 0.48, 0.0)
				_emit_box_basis(rubber_st, wc, Vector3(0.56, 0.56, 0.08), basis)
				_emit_box_basis(light_metal_st, wc, Vector3(0.40, 0.40, 0.095), basis)
			_emit_box_basis(accent_st, pos + Vector3(0.0, 0.76, 0.0), Vector3(sz.x * 0.46, 0.08, 0.07), basis)
			_emit_box_basis(accent_st, pos + basis.x * (sz.x * 0.22) + Vector3(0.0, 0.74, 0.0), Vector3(0.08, 0.56, 0.08), basis)
			_emit_box_basis(dark_metal_st, pos + basis.x * (sz.x * 0.22) + Vector3(0.0, 1.04, 0.0), Vector3(0.08, 0.06, sz.z * 0.72), basis)
			_emit_box_basis(rubber_st, pos - basis.x * (sz.x * 0.14) + Vector3(0.0, 0.94, 0.0), Vector3(0.24, 0.06, 0.14), basis)

		"workbench":
			for lx: float in [-sz.x * 0.45, sz.x * 0.45]:
				_emit_box_basis(dark_metal_st, pos + basis.x * lx + Vector3(0.0, 0.44, 0.0), Vector3(0.08, 0.86, sz.z * 0.86), basis)
			_emit_box_basis(wood_st, pos + Vector3(0.0, 0.88, 0.0), Vector3(sz.x, 0.07, sz.z), basis)
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 1.22, 0.0) - basis.z * (sz.z * 0.42), Vector3(sz.x * 0.96, 0.62, 0.05), basis)
			for ti in range(4):
				var tx := lerpf(-sz.x * 0.34, sz.x * 0.34, float(ti) / 3.0)
				_emit_box_basis(accent_st if ti % 2 == 0 else light_metal_st, pos + basis.x * tx + Vector3(0.0, 1.26, 0.0) - basis.z * (sz.z * 0.38), Vector3(0.10, 0.32, 0.04), basis)

		"ev_totem":
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, sz.y * 0.5, 0.0), Vector3(sz.x, sz.y, sz.z * 0.86), basis)
			_emit_box_basis(accent_st, pos + Vector3(0.0, sz.y - 0.08, 0.0), Vector3(sz.x * 1.02, 0.12, sz.z * 0.92), basis)
			_emit_box_basis(light_st, pos + Vector3(0.0, sz.y * 0.56, 0.0) + basis.z * (sz.z * 0.44), Vector3(sz.x * 0.72, sz.y * 0.62, 0.04), basis)

		"church_pew", "court_bench":
			# Heavy oak base standards + upholstered seat cushion + angled backrest + rear book/hymnal rack
			for sx: float in [-sz.x * 0.46, sz.x * 0.46]:
				_emit_box_basis(wood_st, pos + basis.x * sx + Vector3(0.0, sz.y * 0.46, 0.0), Vector3(0.09, sz.y * 0.92, sz.z * 0.94), basis)
				_emit_box_basis(wood_st, pos + basis.x * sx + Vector3(0.0, sz.y * 0.95, 0.0) - basis.z * (sz.z * 0.10), Vector3(0.11, 0.12, sz.z * 0.56), basis)
			_emit_box_basis(wood_st, pos + Vector3(0.0, 0.36, 0.0) + basis.z * (sz.z * 0.06), Vector3(sz.x * 0.92, 0.07, sz.z * 0.72), basis)
			_emit_box_basis(accent_st if kind == "church_pew" else fabric_st, pos + Vector3(0.0, 0.42, 0.0) + basis.z * (sz.z * 0.06), Vector3(sz.x * 0.88, 0.06, sz.z * 0.66), basis)
			_emit_box_basis(wood_st, pos + Vector3(0.0, sz.y * 0.68, 0.0) - basis.z * (sz.z * 0.28), Vector3(sz.x * 0.92, sz.y * 0.54, 0.08), basis)
			_emit_box_basis(wood_st, pos + Vector3(0.0, 0.56, 0.0) - basis.z * (sz.z * 0.40), Vector3(sz.x * 0.84, 0.10, 0.11), basis)

		"altar_table":
			# Stepped stone mensa altar with gold cross relief, velvet runner & brass twin candlesticks
			_emit_box_basis(limestone_st, pos + Vector3(0.0, 0.12, 0.0), Vector3(sz.x * 0.96, 0.24, sz.z * 0.92), basis)
			_emit_box_basis(limestone_st, pos + Vector3(0.0, sz.y * 0.54, 0.0), Vector3(sz.x * 0.84, sz.y * 0.62, sz.z * 0.78), basis)
			_emit_box_basis(limestone_st, pos + Vector3(0.0, sz.y - 0.06, 0.0), Vector3(sz.x, 0.12, sz.z), basis)
			_emit_box_basis(accent_st, pos + Vector3(0.0, sz.y * 0.76, 0.0) + basis.z * (sz.z * 0.26), Vector3(0.56, sz.y * 0.48, sz.z * 0.50), basis)
			_emit_box_basis(gold_st, pos + Vector3(0.0, sz.y * 0.58, 0.0) + basis.z * (sz.z * 0.42), Vector3(0.10, 0.42, 0.05), basis)
			_emit_box_basis(gold_st, pos + Vector3(0.0, sz.y * 0.66, 0.0) + basis.z * (sz.z * 0.42), Vector3(0.28, 0.09, 0.05), basis)
			for cx_a: float in [-sz.x * 0.34, sz.x * 0.34]:
				_emit_box_basis(gold_st, pos + basis.x * cx_a + Vector3(0.0, sz.y + 0.16, 0.0), Vector3(0.10, 0.32, 0.10), basis)
				_emit_box_basis(light_st, pos + basis.x * cx_a + Vector3(0.0, sz.y + 0.36, 0.0), Vector3(0.06, 0.10, 0.06), basis)

		"pulpit":
			# Stepped hardwood lectern column + sloped reading desk + brass trim & gooseneck lamp
			_emit_box_basis(wood_st, pos + Vector3(0.0, 0.09, 0.0), Vector3(sz.x * 0.94, 0.18, sz.z * 0.92), basis)
			_emit_box_basis(wood_st, pos + Vector3(0.0, sz.y * 0.50, 0.0), Vector3(sz.x * 0.62, sz.y * 0.72, sz.z * 0.60), basis)
			_emit_box_basis(wood_st, pos + Vector3(0.0, sz.y - 0.10, 0.0), Vector3(sz.x, 0.18, sz.z * 0.90), basis)
			_emit_box_basis(gold_st, pos + Vector3(0.0, sz.y * 0.66, 0.0) + basis.z * (sz.z * 0.32), Vector3(0.24, 0.24, 0.03), basis)
			_emit_box_basis(light_st, pos + Vector3(0.0, sz.y + 0.08, 0.0) - basis.z * (sz.z * 0.20), Vector3(0.26, 0.06, 0.10), basis)

		"judge_bench":
			# Raised mahogany judicial bench dais with curved flank wings, gold seal & monitor
			_emit_box_basis(wood_st, pos + Vector3(0.0, 0.14, 0.0), Vector3(sz.x * 0.98, 0.28, sz.z * 0.96), basis)
			_emit_box_basis(wood_st, pos + Vector3(0.0, sz.y * 0.56, 0.0) + basis.z * (sz.z * 0.06), Vector3(sz.x * 0.96, sz.y * 0.72, sz.z * 0.62), basis)
			_emit_box_basis(wood_st, pos + Vector3(0.0, sz.y - 0.06, 0.0) + basis.z * (sz.z * 0.06), Vector3(sz.x, 0.12, sz.z * 0.76), basis)
			_emit_box_basis(gold_st, pos + Vector3(0.0, sz.y * 0.60, 0.0) + basis.z * (sz.z * 0.40), Vector3(0.46, 0.46, 0.04), basis)
			for lx_j: float in [-sz.x * 0.34, sz.x * 0.34]:
				_emit_box_basis(gold_st, pos + basis.x * lx_j + Vector3(0.0, sz.y + 0.08, 0.0), Vector3(0.14, 0.16, 0.12), basis)
				_emit_box_basis(light_st, pos + basis.x * lx_j + Vector3(0.0, sz.y + 0.16, 0.0), Vector3(0.24, 0.06, 0.12), basis)
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, sz.y + 0.18, 0.0) - basis.z * (sz.z * 0.10), Vector3(0.54, 0.30, 0.05), basis)

		"holding_cell":
			# Concrete plinth + steel bench + perimeter steel frame + vertical prison bars
			_emit_box_basis(limestone_st, pos + Vector3(0.0, 0.06, 0.0), Vector3(sz.x, 0.12, sz.z), basis)
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, sz.y - 0.06, 0.0), Vector3(sz.x, 0.12, sz.z), basis)
			for cx_p: float in [-sz.x * 0.47, sz.x * 0.47]:
				for cz_p: float in [-sz.z * 0.46, sz.z * 0.46]:
					_emit_box_basis(dark_metal_st, pos + basis.x * cx_p + basis.z * cz_p + Vector3(0.0, sz.y * 0.5, 0.0), Vector3(0.09, sz.y, 0.09), basis)
			# Rear bench + wall sink inside cell
			_emit_box_basis(light_metal_st, pos - basis.z * (sz.z * 0.28) + Vector3(0.0, 0.44, 0.0), Vector3(sz.x * 0.72, 0.08, 0.46), basis)
			_emit_box_basis(light_metal_st, pos + basis.x * (sz.x * 0.30) - basis.z * (sz.z * 0.28) + Vector3(0.0, 0.88, 0.0), Vector3(0.36, 0.18, 0.34), basis)
			# Front & side steel jail bars
			var bar_n := maxi(4, int(round(sz.x / 0.28)))
			for bi in range(bar_n + 1):
				var bx := lerpf(-sz.x * 0.42, sz.x * 0.42, float(bi) / float(bar_n))
				_emit_box_basis(dark_metal_st, pos + basis.x * bx + basis.z * (sz.z * 0.45) + Vector3(0.0, sz.y * 0.5, 0.0), Vector3(0.045, sz.y - 0.16, 0.045), basis)
				_emit_box_basis(dark_metal_st, pos + basis.x * bx - basis.z * (sz.z * 0.45) + Vector3(0.0, sz.y * 0.5, 0.0), Vector3(0.045, sz.y - 0.16, 0.045), basis)
			var side_n := maxi(3, int(round(sz.z / 0.30)))
			for si in range(1, side_n):
				var bz := lerpf(-sz.z * 0.40, sz.z * 0.40, float(si) / float(side_n))
				for sx_side: float in [-sz.x * 0.46, sz.x * 0.46]:
					_emit_box_basis(dark_metal_st, pos + basis.x * sx_side + basis.z * bz + Vector3(0.0, sz.y * 0.5, 0.0), Vector3(0.045, sz.y - 0.16, 0.045), basis)

		"fire_truck":
			# Detailed Pumper Fire Engine oriented with cab facing +Z bay doors
			var cab_z := sz.z * 0.31
			var body_z := -sz.z * 0.14
			# Chassis rails & heavy bumpers
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 0.42, 0.0), Vector3(sz.x * 0.78, 0.24, sz.z * 0.94), basis)
			_emit_box_basis(light_metal_st, pos + basis.z * (sz.z * 0.48) + Vector3(0.0, 0.46, 0.0), Vector3(sz.x * 0.96, 0.26, 0.18), basis)
			_emit_box_basis(light_metal_st, pos - basis.z * (sz.z * 0.48) + Vector3(0.0, 0.46, 0.0), Vector3(sz.x * 0.92, 0.24, 0.16), basis)
			# 4 heavy rubber wheels + chrome rims
			for wx_f: float in [-sz.x * 0.44, sz.x * 0.44]:
				for wz_f: float in [-sz.z * 0.28, sz.z * 0.32]:
					var wc := pos + basis.x * wx_f + basis.z * wz_f + Vector3(0.0, 0.46, 0.0)
					_emit_box_basis(rubber_st, wc, Vector3(0.28, 0.88, 0.88), basis)
					_emit_box_basis(light_metal_st, wc, Vector3(0.30, 0.46, 0.46), basis)
			# Forward emergency red cab + windshield + chrome grille + twin LED headlights + lightbar
			_emit_box_basis(emergency_red_st, pos + basis.z * cab_z + Vector3(0.0, 1.38, 0.0), Vector3(sz.x * 0.94, 1.72, sz.z * 0.32), basis)
			_emit_box_basis(dark_metal_st, pos + basis.z * (cab_z + sz.z * 0.162) + Vector3(0.0, 1.56, 0.0), Vector3(sz.x * 0.84, 0.74, 0.06), basis)
			_emit_box_basis(light_metal_st, pos + basis.z * (cab_z + sz.z * 0.165) + Vector3(0.0, 0.92, 0.0), Vector3(sz.x * 0.52, 0.42, 0.06), basis)
			for hx_l: float in [-sz.x * 0.34, sz.x * 0.34]:
				_emit_box_basis(light_st, pos + basis.x * hx_l + basis.z * (cab_z + sz.z * 0.17) + Vector3(0.0, 0.86, 0.0), Vector3(0.24, 0.16, 0.05), basis)
			_emit_box_basis(emergency_red_st, pos - basis.x * (sz.x * 0.26) + basis.z * (cab_z + 0.25) + Vector3(0.0, 2.34, 0.0), Vector3(sz.x * 0.36, 0.16, 0.26), basis)
			_emit_box_basis(police_blue_st, pos + basis.x * (sz.x * 0.26) + basis.z * (cab_z + 0.25) + Vector3(0.0, 2.34, 0.0), Vector3(sz.x * 0.36, 0.16, 0.26), basis)
			_emit_box_basis(light_st, pos + basis.z * (cab_z + 0.25) + Vector3(0.0, 2.34, 0.0), Vector3(0.22, 0.16, 0.26), basis)
			# Rear pump & equipment body + stainless steel pump control panel & roll-up shutters + hose bed + aluminum ladder rack
			_emit_box_basis(emergency_red_st, pos + basis.z * body_z + Vector3(0.0, 1.34, 0.0), Vector3(sz.x * 0.94, 1.64, sz.z * 0.56), basis)
			_emit_box_basis(light_metal_st, pos + basis.z * (body_z + sz.z * 0.21) + Vector3(0.0, 1.38, 0.0), Vector3(sz.x * 0.98, 1.34, 0.68), basis)
			_emit_box_basis(light_st, pos + basis.x * (sz.x * 0.495) + basis.z * (body_z + sz.z * 0.21) + Vector3(0.0, 1.56, 0.0), Vector3(0.03, 0.42, 0.44), basis)
			_emit_box_basis(light_metal_st, pos - basis.x * (sz.x * 0.49) + basis.z * (body_z - sz.z * 0.08) + Vector3(0.0, 1.24, 0.0), Vector3(0.04, 1.12, sz.z * 0.32), basis)
			_emit_box_basis(light_metal_st, pos + basis.x * (sz.x * 0.49) + basis.z * (body_z - sz.z * 0.08) + Vector3(0.0, 1.24, 0.0), Vector3(0.04, 1.12, sz.z * 0.32), basis)
			_emit_box_basis(limestone_st, pos + basis.z * body_z + Vector3(0.0, 2.22, 0.0), Vector3(sz.x * 0.54, 0.22, sz.z * 0.44), basis)
			# Roof extension ladder on top right rack
			for lx_r: float in [sz.x * 0.22, sz.x * 0.40]:
				_emit_box_basis(light_metal_st, pos + basis.x * lx_r + basis.z * body_z + Vector3(0.0, 2.34, 0.0), Vector3(0.06, 0.10, sz.z * 0.62), basis)
			for ri in range(6):
				var rz := lerpf(body_z - sz.z * 0.26, body_z + sz.z * 0.26, float(ri) / 5.0)
				_emit_box_basis(light_metal_st, pos + basis.x * (sz.x * 0.31) + basis.z * rz + Vector3(0.0, 2.34, 0.0), Vector3(0.18, 0.05, 0.05), basis)

		"hospital_bed":
			# Clinical hospital gurney/bed: steel casters, adjustable deck, white mattress, pillow, side rails, IV pole & vital monitor
			_emit_box_basis(dark_metal_st, pos + Vector3(0.0, 0.16, 0.0), Vector3(sz.x * 0.88, 0.10, sz.z * 0.86), basis)
			for lx_b: float in [-sz.x * 0.38, sz.x * 0.38]:
				for lz_b: float in [-sz.z * 0.38, sz.z * 0.38]:
					_emit_box_basis(light_metal_st, pos + basis.x * lx_b + basis.z * lz_b + Vector3(0.0, 0.28, 0.0), Vector3(0.07, 0.56, 0.07), basis)
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, 0.56, 0.0), Vector3(sz.x * 0.94, 0.09, sz.z * 0.92), basis)
			_emit_box_basis(limestone_st, pos + Vector3(0.0, 0.69, 0.0) + basis.z * 0.02, Vector3(sz.x * 0.90, 0.18, sz.z * 0.88), basis)
			_emit_box_basis(fabric_st, pos + Vector3(0.0, 0.80, 0.0) - basis.z * (sz.z * 0.31), Vector3(sz.x * 0.66, 0.09, 0.34), basis)
			_emit_box_basis(accent_st, pos + Vector3(0.0, 0.78, 0.0) + basis.z * (sz.z * 0.16), Vector3(sz.x * 0.91, 0.04, sz.z * 0.48), basis)
			# Headboard, footboard, and side safety rails
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, 0.88, 0.0) - basis.z * (sz.z * 0.46), Vector3(sz.x * 0.94, 0.52, 0.06), basis)
			_emit_box_basis(light_metal_st, pos + Vector3(0.0, 0.78, 0.0) + basis.z * (sz.z * 0.46), Vector3(sz.x * 0.94, 0.36, 0.06), basis)
			for rs_x: float in [-sz.x * 0.48, sz.x * 0.48]:
				_emit_box_basis(light_metal_st, pos + basis.x * rs_x + Vector3(0.0, 0.84, 0.0), Vector3(0.04, 0.16, sz.z * 0.48), basis)
			# IV pole & luminous vital-signs monitor beside headboard
			_emit_box_basis(light_metal_st, pos - basis.x * (sz.x * 0.46) - basis.z * (sz.z * 0.42) + Vector3(0.0, 1.15, 0.0), Vector3(0.04, 1.90, 0.04), basis)
			_emit_box_basis(light_st, pos - basis.x * (sz.x * 0.46) - basis.z * (sz.z * 0.42) + Vector3(0.0, 1.92, 0.0), Vector3(0.14, 0.20, 0.08), basis)
			_emit_box_basis(dark_metal_st, pos + basis.x * (sz.x * 0.42) - basis.z * (sz.z * 0.42) + Vector3(0.0, 1.18, 0.0), Vector3(0.28, 0.22, 0.10), basis)
			_emit_box_basis(light_st, pos + basis.x * (sz.x * 0.42) - basis.z * (sz.z * 0.365) + Vector3(0.0, 1.18, 0.0), Vector3(0.22, 0.16, 0.02), basis)

		"school_desk":
			# Classroom student desk + integrated seat facing +Z instructor podium
			for lx_s: float in [-sz.x * 0.40, sz.x * 0.40]:
				_emit_box_basis(dark_metal_st, pos + basis.x * lx_s - basis.z * (sz.z * 0.18) + Vector3(0.0, 0.38, 0.0), Vector3(0.04, 0.74, 0.04), basis)
				_emit_box_basis(dark_metal_st, pos + basis.x * lx_s + basis.z * (sz.z * 0.26) + Vector3(0.0, 0.22, 0.0), Vector3(0.04, 0.44, 0.04), basis)
			_emit_box_basis(wood_st, pos - basis.z * (sz.z * 0.16) + Vector3(0.0, 0.74, 0.0), Vector3(sz.x, 0.045, sz.z * 0.46), basis)
			_emit_box_basis(accent_st, pos - basis.z * (sz.z * 0.16) + Vector3(0.0, 0.775, 0.0), Vector3(0.26, 0.025, 0.20), basis)
			_emit_box_basis(wood_st, pos + basis.z * (sz.z * 0.26) + Vector3(0.0, 0.45, 0.0), Vector3(sz.x * 0.68, 0.045, sz.z * 0.34), basis)
			_emit_box_basis(wood_st, pos + basis.z * (sz.z * 0.42) + Vector3(0.0, 0.68, 0.0), Vector3(sz.x * 0.68, 0.34, 0.04), basis)


static func _emit_barbell_with_plates(
	bar_st: SurfaceTool,
	plate_st: SurfaceTool,
	rim_st: SurfaceTool,
	center: Vector3,
	bar_len: float,
	basis: Basis
) -> void:
	_emit_box_basis(bar_st, center, Vector3(bar_len, 0.045, 0.045), basis)
	for side_s: float in [-1.0, 1.0]:
		var sleeve_x := side_s * (bar_len * 0.40)
		_emit_box_basis(plate_st, center + basis.x * sleeve_x, Vector3(0.075, 0.44, 0.44), basis)
		_emit_box_basis(rim_st, center + basis.x * (sleeve_x + side_s * 0.065), Vector3(0.045, 0.36, 0.36), basis)


static func _emit_box_basis(st: SurfaceTool, center: Vector3, size: Vector3, basis: Basis) -> void:
	InteriorBuilder._emit_box_basis(st, center, size, basis)
