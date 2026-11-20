# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name SectorGatePlanner
extends RefCounted


class SectorGate:
	extends RefCounted
	var color: WorldPlan.KeyColor = WorldPlan.KeyColor.BLUE
	var gate_depth: int = 2
	var gate_room: Rect2i = Rect2i()
	var next_room: Rect2i = Rect2i()
	var door_cells: Array[Vector2i] = []
	var key_room: Rect2i = Rect2i()
	var key_cell: Vector2i = Vector2i.ZERO
	var gate_entry_cell: Vector2i = Vector2i.ZERO
	var shortcut_wall_cells: Array[Vector2i] = []
	var shortcut_flank_cells: Array[Vector2i] = []
	var lever_cell: Vector2i = Vector2i.ZERO
	var shortcut_corridor_rects: Array[Rect2i] = []
	var tunnel_floors: Dictionary[Vector2i, Vector2i] = {}
	var tunnel_walls: Dictionary[Vector2i, Vector2i] = {}
	var tunnel_erased_walls: Array[Vector2i] = []
	var tunnel_walkable: Array[Vector2i] = []
	var opened_map_chunk_coords: Array[Vector2i] = []
	var opened_map_floors: Dictionary[Vector2i, PackedVector2Array] = {}
	var opened_map_walls: Dictionary[Vector2i, PackedVector2Array] = {}
	var door_unlocked: bool = false
	var shortcut_opened: bool = false


const GATE_DEPTHS: Array[int] = [2, 5, 8, 11]


static func get_sector_for_depth(depth: int) -> int:
	if depth <= 2:
		return 0
	if depth <= 5:
		return 1
	if depth <= 8:
		return 2
	if depth <= 11:
		return 3
	return 4


static func build_sector_gate(plan: WorldPlan, frontier_rooms: Array[Rect2i], current_depth: int) -> Array[Rect2i]:
	var gate_idx: int = GATE_DEPTHS.find(current_depth)
	if gate_idx < 0:
		return []

	var gate_color: WorldPlan.KeyColor = gate_idx as WorldPlan.KeyColor
	var gate_room: Rect2i = _pick_gate_room(plan, frontier_rooms, current_depth)
	if gate_room.size == Vector2i.ZERO:
		return []

	var key_room: Rect2i = _ensure_key_room(plan, gate_room, current_depth, gate_idx)
	var gate: SectorGate = SectorGate.new()
	gate.color = gate_color
	gate.gate_depth = current_depth
	gate.gate_room = gate_room
	gate.key_room = key_room

	_setup_shortcut_and_key(plan, gate, key_room, gate_room)
	var next_room: Rect2i = _spawn_next_sector_room(plan, gate, gate_room, current_depth + 1)
	if next_room.size == Vector2i.ZERO:
		return []

	gate.next_room = next_room
	plan.sector_gates.append(gate)
	_register_gate_tiles_and_no_prop(plan, gate)
	return [next_room]


static func _pick_gate_room(plan: WorldPlan, frontier_rooms: Array[Rect2i], current_depth: int) -> Rect2i:
	var pool: Array[Rect2i] = frontier_rooms
	if pool.is_empty():
		pool = plan.get_depth_rooms(current_depth)
	if pool.is_empty():
		return Rect2i()

	var best: Rect2i = pool[0]
	var best_score: int = best.position.y * 10 + absi(best.get_center().x)
	for r: Rect2i in pool:
		var score: int = r.position.y * 10 + absi(r.get_center().x)
		if score < best_score:
			best_score = score
			best = r
	return best


static func _ensure_key_room(plan: WorldPlan, gate_room: Rect2i, current_depth: int, sector_idx: int) -> Rect2i:
	var candidates: Array[Rect2i] = []
	for r: Rect2i in plan.rooms:
		if r == gate_room:
			continue
		if get_sector_for_depth(plan.get_room_depth(r)) == sector_idx:
			candidates.append(r)

	var same_depth_count: int = 0
	for r: Rect2i in candidates:
		if plan.get_room_depth(r) == current_depth:
			same_depth_count += 1

	if same_depth_count == 0:
		var wing: Rect2i = _spawn_lateral_wing_room(plan, gate_room, current_depth)
		if wing.size != Vector2i.ZERO:
			candidates.append(wing)

	if candidates.is_empty():
		return gate_room

	var gate_center: Vector2i = gate_room.get_center()
	var best: Rect2i = candidates[0]
	var best_score: int = -999999999
	for r: Rect2i in candidates:
		var r_depth: int = plan.get_room_depth(r)
		var depth_bonus: int = 10000 if r_depth == current_depth else r_depth * 500
		var lateral_sep: int = absi(r.get_center().x - gate_center.x) * 20
		var north_penalty: int = maxi(0, gate_room.position.y - r.position.y) * 50
		var score: int = depth_bonus + lateral_sep - north_penalty
		if score > best_score:
			best_score = score
			best = r
	return best


static func _spawn_lateral_wing_room(plan: WorldPlan, gate_room: Rect2i, target_depth: int) -> Rect2i:
	var parent_room: Rect2i = _find_parent_for_wing(plan, gate_room, target_depth)
	var min_size: Vector2i = plan._get_min_size_for_depth(target_depth)
	var max_size: Vector2i = plan._get_max_size_for_depth(target_depth)
	var dist_range: Vector2 = plan._get_step_distance_for_depth(target_depth)
	var base_center: Vector2 = Vector2(parent_room.get_center())
	var prefer_side: float = -1.0 if gate_room.get_center().x >= 0 else 1.0

	for attempt: int in range(WorldPlan.MAX_PLACEMENT_ATTEMPTS * 2):
		var side_dir: float = prefer_side if attempt < WorldPlan.MAX_PLACEMENT_ATTEMPTS else -prefer_side
		var angle: float = -PI * 0.5 + side_dir * plan._rng.randf_range(0.75, 1.35)
		var step_dist: float = plan._rng.randf_range(dist_range.x, dist_range.y + 16.0)
		var size: Vector2i = Vector2i(plan._rng.randi_range(min_size.x, max_size.x), plan._rng.randi_range(min_size.y, max_size.y))
		var center_pos: Vector2 = base_center + Vector2.from_angle(angle) * step_dist
		var top_left: Vector2i = Vector2i(center_pos.round()) - Vector2i(Vector2(size) * 0.5)
		var candidate: Rect2i = Rect2i(top_left, size)
		if candidate.position.y < gate_room.position.y + 4:
			continue
		if plan._is_outside_world_bounds(candidate) or plan._overlaps_any_room(candidate):
			continue
		if not plan.room_children.has(parent_room):
			plan.room_children[parent_room] = []
		plan.room_children[parent_room].append(candidate)
		plan._add_neighbor_edge(parent_room, candidate)
		plan._add_room(candidate, target_depth)
		plan._carve_corridor(parent_room.get_center(), candidate.get_center())
		return candidate
	return Rect2i()


static func _find_parent_for_wing(plan: WorldPlan, gate_room: Rect2i, target_depth: int) -> Rect2i:
	for p: Rect2i in plan.room_children:
		var children: Array = plan.room_children[p]
		if children.has(gate_room):
			return p
	var prev_rooms: Array[Rect2i] = plan.get_depth_rooms(target_depth - 1)
	if not prev_rooms.is_empty():
		return prev_rooms[0]
	return plan.hero_room


static func _setup_shortcut_and_key(plan: WorldPlan, gate: SectorGate, key_room: Rect2i, gate_room: Rect2i) -> void:
	var exit_x: int = key_room.get_center().x - 1
	var exit_y: int = key_room.position.y
	gate.shortcut_wall_cells = [Vector2i(exit_x, exit_y), Vector2i(exit_x + 1, exit_y)]
	gate.shortcut_flank_cells = [Vector2i(exit_x - 1, exit_y), Vector2i(exit_x + 2, exit_y)]

	var cand_lever: Vector2i = Vector2i(exit_x - 1, exit_y + 2)
	if not plan.is_floor(cand_lever):
		cand_lever = Vector2i(exit_x, exit_y + 2)
	gate.lever_cell = cand_lever
	gate.key_cell = _find_safe_key_cell(plan, key_room, gate.lever_cell)

	var neck_top_y: int = exit_y - 5
	var shortcut_neck: Rect2i = Rect2i(exit_x, neck_top_y, 2, 6)
	plan.protected_neck_rects.append(Rect2i(exit_x - 3, neck_top_y - 1, 8, 7))
	gate.shortcut_corridor_rects.append(shortcut_neck)

	if key_room == gate_room:
		return

	var from_west: bool = exit_x <= gate_room.get_center().x
	var side_x: int = (gate_room.position.x - 5) if from_west else (gate_room.end.x + 4)
	var entry_y: int = clampi(gate_room.get_center().y, gate_room.position.y + 5, gate_room.end.y - 5)
	var gate_wall_x: int = (gate_room.position.x - 1) if from_west else gate_room.end.x
	gate.gate_entry_cell = Vector2i(gate_wall_x, entry_y)

	var turn_y: int = neck_top_y
	if turn_y >= gate_room.end.y and turn_y <= gate_room.end.y + 3:
		turn_y = gate_room.end.y + 4
		var ext_rect: Rect2i = Rect2i(exit_x, neck_top_y, 2, turn_y - neck_top_y + 1)
		gate.shortcut_corridor_rects.append(ext_rect)

	var leg1: Rect2i = _make_horiz_corridor_rect(exit_x, side_x, turn_y, 1)
	var leg2: Rect2i = _make_vert_corridor_rect(turn_y, entry_y, side_x, 1)
	var leg3: Rect2i = _make_horiz_corridor_rect(side_x, gate_room.get_center().x, entry_y, 2)

	for seg: Rect2i in [leg1, leg2, leg3]:
		plan._corridor_rects.append(seg)
		gate.shortcut_corridor_rects.append(seg)

	plan._add_neighbor_edge(key_room, gate_room)


static func _spawn_next_sector_room(plan: WorldPlan, gate: SectorGate, gate_room: Rect2i, next_depth: int) -> Rect2i:
	var door_x: int = gate_room.get_center().x - 1
	var door_y: int = gate_room.position.y
	gate.door_cells = [Vector2i(door_x, door_y), Vector2i(door_x + 1, door_y)]

	var door_neck: Rect2i = Rect2i(door_x, door_y - 5, 2, 6)
	plan._add_carve_rect(door_neck)
	plan.protected_neck_rects.append(Rect2i(door_x - 3, door_y - 6, 8, 7))

	var min_size: Vector2i = plan._get_min_size_for_depth(next_depth)
	var max_size: Vector2i = plan._get_max_size_for_depth(next_depth)
	var x_offsets: Array[int] = [0, -6, 6, -12, 12, -18, 18, -24, 24]
	var y_extras: Array[int] = [0, 8, 16, 24, 32, 40, 52]

	for y_extra: int in y_extras:
		for x_off: int in x_offsets:
			var size: Vector2i = Vector2i(plan._rng.randi_range(min_size.x, max_size.x), plan._rng.randi_range(min_size.y, max_size.y))
			var bottom_y: int = door_y - 12 - y_extra
			var top_left: Vector2i = Vector2i(gate_room.get_center().x + x_off - int(float(size.x) * 0.5), bottom_y - size.y)
			var candidate: Rect2i = Rect2i(top_left, size)
			if plan._is_outside_world_bounds(candidate) or plan._overlaps_any_room(candidate):
				continue
			if not plan.room_children.has(gate_room):
				plan.room_children[gate_room] = []
			plan.room_children[gate_room].append(candidate)
			plan._add_neighbor_edge(gate_room, candidate)
			plan._add_room(candidate, next_depth)

			var dest_center: Vector2i = candidate.get_center()
			plan._add_vertical_corridor_rect(door_y - 5, dest_center.y, door_x, 2)
			if dest_center.x != door_x:
				plan._add_horizontal_corridor_rect(door_x, dest_center.x, dest_center.y, 2)
			return candidate

	return Rect2i()


static func _find_safe_key_cell(plan: WorldPlan, key_room: Rect2i, lever_cell: Vector2i) -> Vector2i:
	var center: Vector2i = key_room.get_center()
	var spawns: Array = plan.get_companion_spawns_for_room(key_room)
	var offsets: Array[Vector2i] = [
		Vector2i(0, 3),
		Vector2i(0, -3),
		Vector2i(3, 0),
		Vector2i(-3, 0),
		Vector2i(2, 2),
		Vector2i(-2, 2),
	]
	for off: Vector2i in offsets:
		var cand: Vector2i = center + off
		if not plan.is_floor(cand) or not plan.is_floor(cand + Vector2i(0, -1)):
			continue
		if cand.distance_squared_to(lever_cell) < 9:
			continue
		if plan._is_near_pillar(cand, 1):
			continue
		var near_spawn: bool = false
		for s_var: Variant in spawns:
			if s_var is Vector2i:
				var s_cell: Vector2i = s_var
				if cand.distance_squared_to(s_cell) < 4:
					near_spawn = true
					break
		if not near_spawn:
			return cand
	return center + Vector2i(0, 2)


static func _register_gate_tiles_and_no_prop(plan: WorldPlan, gate: SectorGate) -> void:
	for i: int in range(gate.door_cells.size()):
		plan.door_cell_codes[gate.door_cells[i]] = int(gate.color) * 2 + i
		_mark_no_prop_radius(plan, gate.door_cells[i], 2)

	for cell: Vector2i in gate.shortcut_wall_cells:
		plan.closed_shortcut_walls[cell] = true
		_mark_no_prop_radius(plan, cell, 2)

	for cell: Vector2i in gate.shortcut_flank_cells:
		plan.closed_shortcut_walls[cell] = true
		_mark_no_prop_radius(plan, cell, 1)

	plan.lever_cells[gate.lever_cell] = gate.color
	_mark_no_prop_radius(plan, gate.lever_cell, 2)
	_mark_no_prop_radius(plan, gate.key_cell, 2)
	if gate.key_room != gate.gate_room:
		_mark_no_prop_radius(plan, gate.gate_entry_cell, 3)


static func _mark_no_prop_radius(plan: WorldPlan, center: Vector2i, radius: int) -> void:
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			plan.no_prop_cells[center + Vector2i(dx, dy)] = true


static func _make_horiz_corridor_rect(x_start: int, x_end: int, y: int, half_width: int) -> Rect2i:
	var min_x: int = mini(x_start, x_end)
	var max_x: int = maxi(x_start, x_end)
	return Rect2i(min_x, y - half_width, (max_x - min_x) + 1, half_width * 2 + 1)


static func _make_vert_corridor_rect(y_start: int, y_end: int, x: int, half_width: int) -> Rect2i:
	var min_y: int = mini(y_start, y_end)
	var max_y: int = maxi(y_start, y_end)
	return Rect2i(x - half_width, min_y, half_width * 2 + 1, (max_y - min_y) + 1)


static func prebake_shortcut_tunnels(plan: WorldPlan, raster: ChunkRaster) -> void:
	if plan.sector_gates.is_empty():
		return
	var base_count: int = plan.carve_rects.size()
	var saved_closed_walls: Dictionary[Vector2i, bool] = plan.closed_shortcut_walls.duplicate()

	for gate: SectorGate in plan.sector_gates:
		if gate.key_room == gate.gate_room or gate.shortcut_corridor_rects.is_empty():
			continue
		for seg: Rect2i in gate.shortcut_corridor_rects:
			plan._add_carve_rect(seg)
		for cell: Vector2i in gate.shortcut_wall_cells:
			plan.closed_shortcut_walls.erase(cell)
		for cell: Vector2i in gate.shortcut_flank_cells:
			plan.closed_shortcut_walls.erase(cell)

		var touched: Array[Vector2i] = collect_rects_chunks(gate.shortcut_corridor_rects, MapStreamer.CHUNK_SIZE, 1)
		for coord: Vector2i in touched:
			raster.rasterize(coord, plan)
			if not raster.has_any_content():
				continue
			var open_data: Dictionary = TileClassifier.classify_chunk(raster, plan.run_seed, plan)
			if not plan.baked_chunks.has(coord):
				plan.baked_chunks[coord] = _create_empty_baked_chunk()
			_diff_shortcut_chunk(gate, plan.baked_chunks[coord], open_data)

		plan.carve_rects.resize(base_count)
		rebuild_spatial_grid(plan)
		for cell: Vector2i in gate.shortcut_wall_cells:
			if saved_closed_walls.has(cell):
				plan.closed_shortcut_walls[cell] = true
		for cell: Vector2i in gate.shortcut_flank_cells:
			if saved_closed_walls.has(cell):
				plan.closed_shortcut_walls[cell] = true


static func rebuild_spatial_grid(plan: WorldPlan) -> void:
	plan.spatial_grid.clear()
	for i: int in range(plan.carve_rects.size()):
		plan.spatial_grid.add_rect(i, plan.carve_rects[i])


static func collect_rects_chunks(rects: Array[Rect2i], chunk_size: int, padding: int = 1) -> Array[Vector2i]:
	var seen: Dictionary[Vector2i, bool] = {}
	var result: Array[Vector2i] = []
	for r: Rect2i in rects:
		var padded: Rect2i = r.grow(padding) if padding > 0 else r
		var min_cx: int = floori(float(padded.position.x) / float(chunk_size))
		var max_cx: int = floori(float(padded.end.x - 1) / float(chunk_size))
		var min_cy: int = floori(float(padded.position.y) / float(chunk_size))
		var max_cy: int = floori(float(padded.end.y - 1) / float(chunk_size))
		for cy: int in range(min_cy, max_cy + 1):
			for cx: int in range(min_cx, max_cx + 1):
				var coord: Vector2i = Vector2i(cx, cy)
				if not seen.has(coord):
					seen[coord] = true
					result.append(coord)
	return result


static func _create_empty_baked_chunk() -> Dictionary:
	return {
		&"floors": [] as Array[Vector2i],
		&"floor_atlas": [] as Array[Vector2i],
		&"spikes": [] as Array[Vector2i],
		&"walls": [] as Array[Vector2i],
		&"wall_atlas": [] as Array[Vector2i],
		&"wall_alt_ids": [] as Array[int],
		&"torches": [] as Array[Vector2i],
		&"torch_atlas": [] as Array[Vector2i],
		&"torch_alt_ids": [] as Array[int],
		&"lights": [] as Array[Vector2i],
		&"walkable": [] as Array[Vector2i],
	}


static func _diff_shortcut_chunk(gate: SectorGate, closed_data: Dictionary, open_data: Dictionary) -> void:
	var closed_floors: Dictionary[Vector2i, Vector2i] = {}
	var c_floors: Array[Vector2i] = closed_data[&"floors"]
	var c_floor_atlas: Array[Vector2i] = closed_data[&"floor_atlas"]
	for i: int in range(c_floors.size()):
		closed_floors[c_floors[i]] = c_floor_atlas[i]

	var closed_walls: Dictionary[Vector2i, Vector2i] = {}
	var c_walls: Array[Vector2i] = closed_data[&"walls"]
	var c_wall_atlas: Array[Vector2i] = closed_data[&"wall_atlas"]
	for i: int in range(c_walls.size()):
		closed_walls[c_walls[i]] = c_wall_atlas[i]

	var closed_walkable: Dictionary[Vector2i, bool] = {}
	var c_walk: Array[Vector2i] = closed_data[&"walkable"]
	for cell: Vector2i in c_walk:
		closed_walkable[cell] = true

	var open_wall_map: Dictionary[Vector2i, Vector2i] = {}
	var o_walls: Array[Vector2i] = open_data[&"walls"]
	var o_wall_atlas: Array[Vector2i] = open_data[&"wall_atlas"]
	for i: int in range(o_walls.size()):
		var wcell: Vector2i = o_walls[i]
		var watlas: Vector2i = o_wall_atlas[i]
		open_wall_map[wcell] = watlas
		if not closed_walls.has(wcell) or closed_walls[wcell] != watlas:
			gate.tunnel_walls[wcell] = watlas

	for wcell: Vector2i in closed_walls:
		if not open_wall_map.has(wcell):
			gate.tunnel_erased_walls.append(wcell)

	var o_floors: Array[Vector2i] = open_data[&"floors"]
	var o_floor_atlas: Array[Vector2i] = open_data[&"floor_atlas"]
	for i: int in range(o_floors.size()):
		var fcell: Vector2i = o_floors[i]
		var fatlas: Vector2i = o_floor_atlas[i]
		if not closed_floors.has(fcell) or closed_floors[fcell] != fatlas:
			gate.tunnel_floors[fcell] = fatlas
		if not open_wall_map.has(fcell) and not closed_walkable.has(fcell):
			gate.tunnel_walkable.append(fcell)


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


static func _place_corridor_half_block(plan: WorldPlan, is_horiz: bool, along_center: int, fixed_c: int, half_w: int, side: int, length: int) -> void:
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
