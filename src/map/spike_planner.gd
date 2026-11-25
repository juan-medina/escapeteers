# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name SpikePlanner
extends RefCounted

const CORRIDOR_MIN_SPIKE_LEN: int = 10
const CORRIDOR_END_MARGIN: int = 4
const CORRIDOR_SPIKE_INTERVAL: int = 16
const CORRIDOR_MAX_PATCHES: int = 5
const SHORTCUT_MIN_SPIKE_LEN: int = 12
const SHORTCUT_SPIKE_INTERVAL: int = 18
const SHORTCUT_MAX_PATCHES: int = 10
const SHORTCUT_WAYPOINT_CLEAR_SQ: int = 9
const SHORTCUT_SPIKE_SPACING_SQ: int = 16


static func plan_spike_traps(plan: WorldPlan) -> void:
	_plan_closing_spike_rooms(plan)
	for room: Rect2i in plan.rooms:
		if not plan.is_event_room(room):
			_plan_room_spike_traps(plan, room)
	_plan_corridor_spike_traps(plan)
	_plan_shortcut_spike_traps(plan)


static func _plan_closing_spike_rooms(plan: WorldPlan) -> void:
	var excluded: Dictionary[Rect2i, bool] = {plan.hero_room: true}
	for gate: SectorGatePlanner.SectorGate in plan.sector_gates:
		excluded[gate.gate_room] = true
		excluded[gate.key_room] = true

	var sector_candidates: Dictionary[int, Array] = {}
	for room: Rect2i in plan.rooms:
		if excluded.has(room) or plan.get_room_depth(room) < 2:
			continue
		var sector_idx: int = plan._room_sectors.get(room, 0)
		if sector_idx >= 4:
			continue
		var shape: WorldPlan.RoomShape = plan._room_shapes.get(room, WorldPlan.RoomShape.RECTANGLE)
		if shape != WorldPlan.RoomShape.RECTANGLE and shape != WorldPlan.RoomShape.CUT_CORNERS:
			continue
		if not ClosingSpikeHazard.can_fit_room(room):
			continue
		if not sector_candidates.has(sector_idx):
			sector_candidates[sector_idx] = []
		sector_candidates[sector_idx].append(room)

	for sector_idx: int in range(4):
		if not sector_candidates.has(sector_idx):
			continue
		var list: Array = sector_candidates[sector_idx]
		for i: int in range(list.size() - 1, 0, -1):
			var swap_idx: int = plan._rng.randi_range(0, i)
			var tmp: Rect2i = list[i]
			list[i] = list[swap_idx]
			list[swap_idx] = tmp
		for r_var: Variant in list:
			var room: Rect2i = r_var
			if _has_event_neighbor(plan, room):
				continue
			var hazard: ClosingSpikeHazard = ClosingSpikeHazard.build_for_room(plan, room)
			if hazard.rings.size() < 2 or hazard.cell_to_ring.is_empty():
				continue
			plan.room_event_types[room] = WorldPlan.RoomEventType.CLOSING_SPIKES
			plan.closing_spike_hazards[room] = hazard
			for cell: Vector2i in hazard.cell_to_ring:
				plan.event_spike_cell_rooms[cell] = room
				plan.spike_tile_sets[cell] = plan.get_cell_tile_set(cell)
			break


static func _has_event_neighbor(plan: WorldPlan, room: Rect2i) -> bool:
	if not plan._room_neighbors.has(room):
		return false
	for n_var: Variant in plan._room_neighbors[room]:
		if n_var is Rect2i:
			var n_room: Rect2i = n_var
			if plan.is_event_room(n_room):
				return true
	return false


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
		var fixed_c: int = seg[&"fixed"]
		var half_w: int = seg[&"half_width"]

		var run: Vector2i = RoomLayout.get_usable_corridor_run(plan, seg)
		var best_start: int = run.x
		var best_len: int = run.y
		if best_len < CORRIDOR_MIN_SPIKE_LEN:
			continue

		var usable_start: int = best_start + CORRIDOR_END_MARGIN
		var usable_end: int = best_start + best_len - 1 - CORRIDOR_END_MARGIN
		if usable_start > usable_end:
			continue

		var mid_c: int = best_start + floori(float(best_len) * 0.5)
		var mid_y: int = fixed_c if is_horiz else mid_c
		var approx_depth: int = maxi(1, floori(maxf(0.0, float(-mid_y)) / 50.0))
		var chance: float = 0.30 if approx_depth <= 1 else (0.45 if approx_depth <= 3 else 0.60)
		if best_len >= 24:
			chance = minf(0.85, chance + 0.20)
		if plan._rng.randf() > chance:
			continue

		var patch_count: int = 1
		if best_len >= 18:
			patch_count = clampi(floori(float(best_len) / float(CORRIDOR_SPIKE_INTERVAL)) + 1, 1, CORRIDOR_MAX_PATCHES)

		var side_first: int = -1 if plan._rng.randf() < 0.5 else 1
		for i: int in range(patch_count):
			var t: float = float(i + 1) / float(patch_count + 1)
			var along_c: int = clampi(
				roundi(lerpf(float(usable_start), float(usable_end), t)) + plan._rng.randi_range(-1, 1),
				usable_start,
				usable_end,
			)
			var side: int = side_first if (i % 2) == 0 else -side_first
			var patch_len: int = 3 if patch_count == 1 else 2
			_place_corridor_half_block(plan, is_horiz, along_c, fixed_c, half_w, side, patch_len)


static func _plan_shortcut_spike_traps(plan: WorldPlan) -> void:
	for gate: SectorGatePlanner.SectorGate in plan.sector_gates:
		if not gate.has_shortcut or gate.key_room == gate.shortcut_target_room or gate.shortcut_segments.is_empty():
			continue

		var runs: Array[Dictionary] = ShortcutTunnelPlanner.get_usable_shortcut_runs(plan, gate)
		var total_len: int = ShortcutTunnelPlanner.get_total_runs_length(runs)
		if total_len < SHORTCUT_MIN_SPIKE_LEN:
			continue

		var patch_count: int = clampi(maxi(1, roundi(float(total_len) / float(SHORTCUT_SPIKE_INTERVAL))), 1, SHORTCUT_MAX_PATCHES)
		var side_first: int = -1 if plan._rng.randf() < 0.5 else 1
		for i: int in range(patch_count):
			var offset: int = clampi(
				roundi((float(i) + 0.5) * float(total_len) / float(patch_count)) + plan._rng.randi_range(-2, 2),
				0,
				total_len - 1,
			)
			var sample: Dictionary = ShortcutTunnelPlanner.sample_run_position(runs, offset)
			var seg: Dictionary = sample[&"seg"]
			var run_start: int = sample[&"run_start"]
			var run_end: int = sample[&"run_end"]
			var raw_coord: int = sample[&"coord"]
			var along_c: int = clampi(raw_coord, run_start + 1, run_end - 1)
			var side: int = side_first if (i % 2) == 0 else -side_first
			_place_shortcut_half_block(plan, gate, seg, along_c, side, 2)


static func _place_shortcut_half_block(
	plan: WorldPlan,
	gate: SectorGatePlanner.SectorGate,
	seg: Dictionary,
	along_center: int,
	side: int,
	length: int,
) -> void:
	var is_horiz: bool = seg[&"is_horizontal"]
	var fixed_c: int = seg[&"fixed"]
	var half_w: int = seg[&"half_width"]
	var cells: Array[Vector2i] = []
	var start_along: int = along_center - floori(float(length) * 0.5)

	if half_w == 1:
		if is_horiz:
			var y_row: int = fixed_c if side < 0 else (fixed_c + 1)
			for dx: int in range(length):
				cells.append(Vector2i(start_along + dx, y_row))
		else:
			var x_col: int = (fixed_c - 1) if side < 0 else (fixed_c + 1)
			for dy: int in range(length):
				cells.append(Vector2i(x_col, start_along + dy))
	else:
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
		if (
			not ShortcutTunnelPlanner.is_shortcut_floor_cell(cell, gate)
			or not ShortcutTunnelPlanner.is_shortcut_floor_cell(cell + Vector2i(0, -1), gate)
		):
			return
		if plan.get_room_at(cell) != Rect2i() or plan.hero_room.grow(4).has_point(cell):
			return
		if plan.is_floor(cell) or plan.no_prop_cells.has(cell) or WorldPlan._intersects_any_point(cell, plan.protected_neck_rects):
			return
		for wp: Vector2i in gate.shortcut_waypoints:
			if cell.distance_squared_to(wp) < SHORTCUT_WAYPOINT_CLEAR_SQ:
				return
		if WorldPlan._has_cell_near(cell, plan._spike_cells, SHORTCUT_SPIKE_SPACING_SQ):
			return

	plan._commit_spike_cells(cells)


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
