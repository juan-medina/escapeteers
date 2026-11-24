# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name SpikePlanner
extends RefCounted


static func plan_spike_traps(plan: WorldPlan) -> void:
	for room: Rect2i in plan.rooms:
		_plan_room_spike_traps(plan, room)
	_plan_corridor_spike_traps(plan)


static func _plan_room_spike_traps(plan: WorldPlan, room: Rect2i) -> void:
	var depth: int = plan.get_room_depth(room)
	if depth <= 0:
		return

	var chance: float = 0.80 if depth >= 4 else (0.60 if depth >= 2 else 0.35)
	var max_patches: int = plan._rng.randi_range(2, 3) if depth >= 4 else (plan._rng.randi_range(1, 2) if depth >= 2 else 1)
	if plan._rng.randf() > chance:
		return

	var margin: int = 4
	var min_x: int = room.position.x + margin
	var max_x: int = room.end.x - margin - 1
	var min_y: int = room.position.y + margin
	var max_y: int = room.end.y - margin - 1
	if min_x >= max_x or min_y >= max_y:
		return

	var center: Vector2i = room.get_center()
	var qx1: int = int(lerpf(float(min_x), float(center.x), 0.45))
	var qx2: int = int(lerpf(float(max_x), float(center.x), 0.45))
	var qy1: int = int(lerpf(float(min_y), float(center.y), 0.45))
	var qy2: int = int(lerpf(float(max_y), float(center.y), 0.45))
	var anchors: Array[Vector2i] = [Vector2i(qx1, qy1), Vector2i(qx2, qy1), Vector2i(qx1, qy2), Vector2i(qx2, qy2)]
	for i: int in range(anchors.size() - 1, 0, -1):
		var swap_idx: int = plan._rng.randi_range(0, i)
		var tmp: Vector2i = anchors[i]
		anchors[i] = anchors[swap_idx]
		anchors[swap_idx] = tmp

	var placed: int = 0
	for base_anchor: Vector2i in anchors:
		if placed >= max_patches:
			break
		var anchor: Vector2i = base_anchor + Vector2i(plan._rng.randi_range(-1, 1), plan._rng.randi_range(-1, 1))
		if _try_place_spike_patch(plan, anchor, _pick_room_spike_pattern(plan, depth), room):
			placed += 1


static func _pick_room_spike_pattern(plan: WorldPlan, depth: int) -> Array[Vector2i]:
	var roll: float = plan._rng.randf()
	var offsets: Array[Vector2i] = []
	if (depth <= 1 and roll < 0.65) or (depth > 1 and (roll < 0.30 or roll >= 0.80)):
		var size: int = 2 if (depth <= 1 or (depth == 2 and roll < 0.30)) else 3
		var start: int = -int(float(size) * 0.5)
		for dy: int in range(size):
			for dx: int in range(size):
				offsets.append(Vector2i(start + dx, start + dy))
		return offsets
	if depth <= 1 or roll < 0.60:
		var arm: int = 1 if depth <= 1 else 2
		offsets.append(Vector2i.ZERO)
		for d: int in range(1, arm + 1):
			offsets.append(Vector2i(d, 0))
			offsets.append(Vector2i(-d, 0))
			offsets.append(Vector2i(0, d))
			offsets.append(Vector2i(0, -d))
		return offsets
	var sx: int = -1 if plan._rng.randf() < 0.5 else 1
	return [Vector2i(-sx, -1), Vector2i(0, -1), Vector2i(0, 0), Vector2i(sx, 0), Vector2i(sx, 1), Vector2i(2 * sx, 1)]


static func _plan_corridor_spike_traps(plan: WorldPlan) -> void:
	for seg: Dictionary in plan._corridor_segments:
		var is_horiz: bool = seg[&"is_horizontal"]
		var min_c: int = seg[&"min"]
		var max_c: int = seg[&"max"]
		var fixed_c: int = seg[&"fixed"]
		var half_w: int = seg[&"half_width"]

		var run_start: int = -999999
		var best_start: int = 0
		var best_len: int = 0

		for c: int in range(min_c, max_c + 1):
			var center_cell: Vector2i = Vector2i(c, fixed_c) if is_horiz else Vector2i(fixed_c, c)
			if plan.get_room_at(center_cell) == Rect2i():
				if run_start == -999999:
					run_start = c
				var cur_len: int = c - run_start + 1
				if cur_len > best_len:
					best_len = cur_len
					best_start = run_start
			else:
				run_start = -999999

		if best_len < 10:
			continue

		var mid_c: int = best_start + int(float(best_len) * 0.5)
		var mid_y: int = fixed_c if is_horiz else mid_c
		var approx_depth: int = maxi(1, int(maxf(0.0, float(-mid_y)) / 50.0))
		var chance: float = 0.25 if approx_depth <= 1 else (0.40 if approx_depth <= 3 else 0.55)
		if plan._rng.randf() > chance:
			continue

		var side_first: int = -1 if plan._rng.randf() < 0.5 else 1
		if best_len >= 18 and plan._rng.randf() < 0.45:
			_place_corridor_half_block(plan, is_horiz, mid_c - 3, fixed_c, half_w, side_first, 2)
			_place_corridor_half_block(plan, is_horiz, mid_c + 3, fixed_c, half_w, -side_first, 2)
		else:
			_place_corridor_half_block(plan, is_horiz, mid_c, fixed_c, half_w, side_first, 3)


static func _place_corridor_half_block(
	plan: WorldPlan,
	is_horiz: bool,
	along_center: int,
	fixed_c: int,
	half_w: int,
	side: int,
	length: int,
) -> void:
	var cells: Array[Vector2i] = []
	var start_along: int = along_center - int(float(length) * 0.5)
	if is_horiz:
		var y_base: int = (fixed_c - half_w + 1) if side < 0 else (fixed_c + half_w - 1)
		for dx: int in range(length):
			for dy: int in range(2):
				cells.append(Vector2i(start_along + dx, y_base + dy))
	else:
		var x_base: int = (fixed_c - half_w) if side < 0 else (fixed_c + half_w - 1)
		for dy: int in range(length):
			for dx: int in range(2):
				cells.append(Vector2i(x_base + dx, start_along + dy))

	for cell: Vector2i in cells:
		if plan.hero_room.grow(4).has_point(cell) or plan.get_room_at(cell) != Rect2i():
			return
		if plan.no_prop_cells.has(cell) or WorldPlan._intersects_any_point(cell, plan.protected_neck_rects):
			return
		if not plan.is_floor(cell) or not plan.is_floor(cell + Vector2i(0, -1)) or plan.has_candle_post_near(cell, 6):
			return
		if WorldPlan._has_cell_near(cell, plan._spike_cells, 9):
			return

	plan._commit_spike_cells(cells)


static func _try_place_spike_patch(plan: WorldPlan, anchor: Vector2i, offsets: Array[Vector2i], room: Rect2i) -> bool:
	var cells: Array[Vector2i] = []
	var center: Vector2i = room.get_center()
	var recruits: Array = plan.get_companion_spawns_for_room(room)
	var inner_rect: Rect2i = room.grow(-3)

	for offset: Vector2i in offsets:
		var cell: Vector2i = anchor + offset
		if not inner_rect.has_point(cell) or not plan.is_floor(cell) or not plan.is_floor(cell + Vector2i(0, -1)):
			return false
		if plan.no_prop_cells.has(cell):
			return false
		if cell.distance_squared_to(center) < 25 or plan.has_candle_post_near(cell, 6) or WorldPlan._has_cell_near(cell, plan._spike_cells, 25):
			return false
		for r_var: Variant in recruits:
			if r_var is Vector2i:
				var r_cell: Vector2i = r_var
				if cell.distance_squared_to(r_cell) < 25:
					return false
		cells.append(cell)

	plan._commit_spike_cells(cells)
	return true
