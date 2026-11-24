# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name ShortcutTunnelPlanner
extends RefCounted


static func setup_shortcut_and_key(
	plan: WorldPlan,
	gate: SectorGatePlanner.SectorGate,
	key_room: Rect2i,
	target_room: Rect2i,
	allowed_sectors: Array[int],
	reserved_growth_rects: Array[Rect2i],
	fallback_target_room: Rect2i = Rect2i(),
) -> void:
	var exit_x: int = key_room.get_center().x - 1
	var exit_y: int = key_room.position.y
	gate.shortcut_wall_cells = [Vector2i(exit_x, exit_y), Vector2i(exit_x + 1, exit_y)]
	gate.shortcut_flank_cells = [Vector2i(exit_x - 1, exit_y), Vector2i(exit_x + 2, exit_y)]

	var cand_lever: Vector2i = Vector2i(exit_x - 1, exit_y + 2)
	if not plan.is_floor(cand_lever):
		cand_lever = Vector2i(exit_x, exit_y + 2)
	gate.lever_cell = cand_lever
	gate.key_cell = find_safe_key_cell(plan, key_room, gate.lever_cell)
	gate.shortcut_target_room = target_room

	var neck_top_y: int = exit_y - 5
	var shortcut_neck: Rect2i = Rect2i(exit_x, neck_top_y, 2, 6)
	var own_neck_guard: Rect2i = Rect2i(exit_x - 3, neck_top_y - 1, 8, 7)

	if key_room == target_room:
		gate.has_shortcut = false
		gate.shortcut_opened = true
		return

	var chosen: Dictionary = _pick_best_shortcut_route(
		plan,
		gate,
		key_room,
		target_room,
		allowed_sectors,
		reserved_growth_rects,
		exit_x,
		neck_top_y,
	)
	if chosen.is_empty() and fallback_target_room.size != Vector2i.ZERO and fallback_target_room != target_room:
		chosen = _pick_best_shortcut_route(
			plan,
			gate,
			key_room,
			fallback_target_room,
			allowed_sectors,
			reserved_growth_rects,
			exit_x,
			neck_top_y,
		)
		if not chosen.is_empty():
			gate.shortcut_target_room = fallback_target_room

	if chosen.is_empty():
		gate.has_shortcut = false
		gate.shortcut_opened = true
		return

	gate.has_shortcut = true
	var route_sector: int = gate.key_sector
	plan._corridor_rects.append(shortcut_neck)
	plan._corridor_sectors.append(route_sector)
	gate.shortcut_corridor_rects.append(shortcut_neck)
	plan.protected_neck_rects.append(own_neck_guard)
	gate.gate_entry_cell = chosen[&"entry_cell"]
	gate.shortcut_waypoints = chosen[&"waypoints"]
	var tunnel_segs: Array[Rect2i] = chosen[&"segs"]
	for seg: Rect2i in tunnel_segs:
		plan._corridor_rects.append(seg)
		plan._corridor_sectors.append(route_sector)
		gate.shortcut_corridor_rects.append(seg)


static func _pick_best_shortcut_route(
	plan: WorldPlan,
	gate: SectorGatePlanner.SectorGate,
	key_room: Rect2i,
	target_room: Rect2i,
	allowed_sectors: Array[int],
	reserved_growth_rects: Array[Rect2i],
	exit_x: int,
	neck_top_y: int,
) -> Dictionary:
	var prefer_west: bool = exit_x <= target_room.get_center().x
	var side_choices: Array[bool] = [prefer_west, not prefer_west]
	var entry_y: int = target_room.get_center().y
	var turn_ys: Array[int] = [
		neck_top_y,
		mini(neck_top_y, entry_y),
		mini(neck_top_y, target_room.position.y - 10),
		mini(neck_top_y, target_room.position.y - 22),
		neck_top_y - 12,
		neck_top_y - 26,
		mini(neck_top_y, gate.next_room.position.y - 6),
		target_room.end.y + 8,
	]
	var best_route: Dictionary = {}
	var best_score: int = 999999999

	for from_west: bool in side_choices:
		var near_x: int = (target_room.position.x - 5) if from_west else (target_room.end.x + 4)
		var clear_x: int = mini(near_x, gate.next_room.position.x - 6) if from_west else maxi(near_x, gate.next_room.end.x + 5)
		var chute_x: int = (clear_x - 5) if from_west else (clear_x + 5)
		var wide_x: int = (near_x - 16) if from_west else (near_x + 16)
		var side_xs: Array[int] = [near_x]
		if near_x != clear_x:
			side_xs.append(clear_x)
		side_xs.append(chute_x)
		side_xs.append(wide_x)
		var gate_wall_x: int = (target_room.position.x - 1) if from_west else target_room.end.x
		var gate_inside_x: int = (target_room.position.x + 2) if from_west else (target_room.end.x - 3)
		for side_x: int in side_xs:
			for turn_y: int in turn_ys:
				var segs: Array[Rect2i] = _build_shortcut_route_rects(exit_x, neck_top_y, turn_y, side_x, entry_y, gate_inside_x)
				if not _is_shortcut_route_valid(plan, gate, segs, key_room, target_room, allowed_sectors, reserved_growth_rects):
					continue
				var score: int = _score_shortcut_route(plan, gate, segs, key_room, target_room, gate_wall_x, entry_y)
				if score < best_score:
					best_score = score
					var wps: Array[Vector2i] = [
						Vector2i(exit_x, neck_top_y + 5),
						Vector2i(exit_x, turn_y),
						Vector2i(side_x, turn_y),
						Vector2i(side_x, entry_y),
						Vector2i(gate_inside_x, entry_y),
					]
					best_route = {&"segs": segs, &"entry_cell": Vector2i(gate_wall_x, entry_y), &"waypoints": wps}

	return best_route


static func _build_shortcut_route_rects(
	exit_x: int,
	neck_top_y: int,
	turn_y: int,
	side_x: int,
	entry_y: int,
	gate_inside_x: int,
) -> Array[Rect2i]:
	var segs: Array[Rect2i] = []
	if turn_y != neck_top_y:
		segs.append(make_vert_corridor_rect(turn_y, neck_top_y, exit_x, 1))
	var leg1_start_x: int = exit_x if side_x > exit_x else (exit_x + 1)
	segs.append(make_horiz_corridor_rect(leg1_start_x, side_x, turn_y, 1))
	segs.append(make_vert_corridor_rect(turn_y, entry_y, side_x, 1))
	segs.append(make_horiz_corridor_rect(side_x, gate_inside_x, entry_y, 2))
	return segs


static func _is_shortcut_route_valid(
	plan: WorldPlan,
	gate: SectorGatePlanner.SectorGate,
	segs: Array[Rect2i],
	key_room: Rect2i,
	target_room: Rect2i,
	allowed_sectors: Array[int],
	reserved_growth_rects: Array[Rect2i],
) -> bool:
	var last_idx: int = segs.size() - 1
	for i: int in range(segs.size()):
		var r: Rect2i = segs[i]
		if plan._is_outside_world_bounds(r) or r.intersects(gate.next_room.grow(2)) or r.intersects(key_room.grow(1)):
			return false
		if i < last_idx and r.intersects(target_room.grow(1)):
			return false
		if WorldPlan._intersects_any_rect(r.grow(1), plan.protected_neck_rects):
			return false
		if WorldPlan._intersects_any_rect(r.grow(1), reserved_growth_rects):
			return false
		if _hits_other_sector_geometry(plan, r, allowed_sectors, key_room, target_room):
			return false
	return true


static func _hits_other_sector_geometry(
	plan: WorldPlan,
	rect: Rect2i,
	allowed_sectors: Array[int],
	key_room: Rect2i,
	target_room: Rect2i,
) -> bool:
	var padded: Rect2i = rect.grow(2)
	if not allowed_sectors.has(0) and plan.hero_room.intersects(padded):
		return true
	for r_id: int in plan._room_grid.get_candidate_ids_for_rect(padded):
		if r_id >= 0 and r_id < plan.rooms.size():
			var other: Rect2i = plan.rooms[r_id]
			if other == key_room or other == target_room:
				continue
			if not other.intersects(padded):
				continue
			if not allowed_sectors.has(plan._room_sectors.get(other, 0)):
				return true
	for c_idx: int in range(plan._corridor_rects.size()):
		if not allowed_sectors.has(plan._corridor_sectors[c_idx]) and plan._corridor_rects[c_idx].intersects(padded):
			return true
	return false


static func _score_shortcut_route(
	plan: WorldPlan,
	gate: SectorGatePlanner.SectorGate,
	segs: Array[Rect2i],
	key_room: Rect2i,
	target_room: Rect2i,
	gate_wall_x: int,
	entry_y: int,
) -> int:
	var score: int = 0
	var last_idx: int = segs.size() - 1
	for i: int in range(segs.size()):
		var r: Rect2i = segs[i]
		score += r.size.x + r.size.y
		if r.position.y < gate.next_room.position.y:
			score += 50000
		for r_id: int in plan._room_grid.get_candidate_ids_for_rect(r):
			if r_id >= 0 and r_id < plan.rooms.size():
				var other: Rect2i = plan.rooms[r_id]
				if other == key_room or (i == last_idx and other == target_room):
					continue
				if other.intersects(r):
					score += 10000
		for c_rect: Rect2i in plan._corridor_rects:
			if c_rect.intersects(r):
				score += 2000
	if plan.is_floor(Vector2i(gate_wall_x, entry_y)):
		score += 50
	return score


static func find_safe_key_cell(plan: WorldPlan, key_room: Rect2i, lever_cell: Vector2i) -> Vector2i:
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
		if cand.distance_squared_to(lever_cell) < 9 or plan._is_near_pillar(cand, 1):
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
	var fallback: Vector2i = center + Vector2i(0, 2)
	return fallback if plan.is_floor(fallback) else center


static func make_horiz_corridor_rect(x_start: int, x_end: int, y: int, half_width: int) -> Rect2i:
	var min_x: int = mini(x_start, x_end)
	var max_x: int = maxi(x_start, x_end)
	return Rect2i(min_x, y - half_width, (max_x - min_x) + 1, half_width * 2 + 1)


static func make_vert_corridor_rect(y_start: int, y_end: int, x: int, half_width: int) -> Rect2i:
	var min_y: int = mini(y_start, y_end)
	var max_y: int = maxi(y_start, y_end)
	return Rect2i(x - half_width, min_y, half_width * 2 + 1, (max_y - min_y) + 1)


static func prebake_shortcut_tunnels(plan: WorldPlan, raster: ChunkRaster) -> void:
	if plan.sector_gates.is_empty():
		return
	var base_count: int = plan.carve_rects.size()
	var saved_closed_walls: Dictionary[Vector2i, bool] = plan.closed_shortcut_walls.duplicate()

	for gate: SectorGatePlanner.SectorGate in plan.sector_gates:
		if not gate.has_shortcut or gate.key_room == gate.shortcut_target_room or gate.shortcut_corridor_rects.is_empty():
			continue
		for seg: Rect2i in gate.shortcut_corridor_rects:
			plan._add_carve_rect(seg)
		for cell: Vector2i in gate.shortcut_wall_cells:
			plan.closed_shortcut_walls.erase(cell)
		for cell: Vector2i in gate.shortcut_flank_cells:
			plan.closed_shortcut_walls.erase(cell)

		var touched: Array[Vector2i] = SectorGatePlanner.collect_rects_chunks(gate.shortcut_corridor_rects, MapStreamer.CHUNK_SIZE, 1)
		for coord: Vector2i in touched:
			raster.rasterize(coord, plan)
			if not raster.has_any_content():
				continue
			var open_data: Dictionary = TileClassifier.classify_chunk(raster, plan.run_seed, plan)
			if not plan.baked_chunks.has(coord):
				plan.baked_chunks[coord] = _create_empty_baked_chunk()
			_diff_shortcut_chunk(gate, coord, plan.baked_chunks[coord], open_data)

		plan.carve_rects.resize(base_count)
		SectorGatePlanner.rebuild_spatial_grid(plan)
		for cell: Vector2i in gate.shortcut_wall_cells:
			if saved_closed_walls.has(cell):
				plan.closed_shortcut_walls[cell] = true
		for cell: Vector2i in gate.shortcut_flank_cells:
			if saved_closed_walls.has(cell):
				plan.closed_shortcut_walls[cell] = true


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
		&"walkable_rects": [] as Array[Rect2i],
	}


static func _diff_shortcut_chunk(
	gate: SectorGatePlanner.SectorGate,
	coord: Vector2i,
	closed_data: Dictionary,
	open_data: Dictionary,
) -> void:
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

	var chunk_floors: Array[Vector2i] = []
	var chunk_erased_walls: Dictionary[Vector2i, bool] = {}
	var chunk_walls: Array[Vector2i] = []
	var chunk_walkable: Array[Vector2i] = []

	var open_wall_map: Dictionary[Vector2i, Vector2i] = {}
	var o_walls: Array[Vector2i] = open_data[&"walls"]
	var o_wall_atlas: Array[Vector2i] = open_data[&"wall_atlas"]
	for i: int in range(o_walls.size()):
		var wcell: Vector2i = o_walls[i]
		var watlas: Vector2i = o_wall_atlas[i]
		open_wall_map[wcell] = watlas
		if not closed_walls.has(wcell) or closed_walls[wcell] != watlas:
			gate.tunnel_walls[wcell] = watlas
			chunk_walls.append(wcell)

	for wcell: Vector2i in closed_walls:
		if not open_wall_map.has(wcell):
			gate.tunnel_erased_walls.append(wcell)
			chunk_erased_walls[wcell] = true

	var o_floors: Array[Vector2i] = open_data[&"floors"]
	var o_floor_atlas: Array[Vector2i] = open_data[&"floor_atlas"]
	for i: int in range(o_floors.size()):
		var fcell: Vector2i = o_floors[i]
		var fatlas: Vector2i = o_floor_atlas[i]
		if not closed_floors.has(fcell) or closed_floors[fcell] != fatlas:
			gate.tunnel_floors[fcell] = fatlas
			chunk_floors.append(fcell)
		if not open_wall_map.has(fcell) and not closed_walkable.has(fcell):
			gate.tunnel_walkable.append(fcell)
			chunk_walkable.append(fcell)

	if not chunk_floors.is_empty() or not chunk_erased_walls.is_empty() or not chunk_walls.is_empty() or not chunk_walkable.is_empty():
		gate.tunnel_chunk_diffs[coord] = {
			&"floors": chunk_floors,
			&"erased_walls": chunk_erased_walls,
			&"walls": chunk_walls,
			&"walkable": chunk_walkable,
		}


static func verify_solvability(plan: WorldPlan) -> bool:
	var adj: Dictionary[Rect2i, Array] = {}
	adj[plan.hero_room] = []
	for room: Rect2i in plan.rooms:
		adj[room] = []

	for parent_r: Rect2i in plan.room_children:
		var children: Array = plan.room_children[parent_r]
		for child_var: Variant in children:
			if child_var is Rect2i:
				var child_room: Rect2i = child_var
				_connect_adj(adj, parent_r, child_room)

	for room_a: Rect2i in plan._room_neighbors:
		var neighbors: Array = plan._room_neighbors[room_a]
		for n_var: Variant in neighbors:
			if n_var is Rect2i:
				var n_room: Rect2i = n_var
				_connect_adj(adj, room_a, n_room)

	var visited: Dictionary[Rect2i, bool] = {plan.hero_room: true}
	var owned_keys: Dictionary[WorldPlan.KeyColor, bool] = {}
	var opened_shortcuts: Dictionary[SectorGatePlanner.SectorGate, bool] = {}

	var progress: bool = true
	while progress:
		progress = false
		var queue: Array[Rect2i] = []
		for r: Rect2i in visited:
			queue.append(r)
		var head: int = 0
		while head < queue.size():
			var curr: Rect2i = queue[head]
			head += 1
			var neighbors: Array = adj.get(curr, [])
			for n_var: Variant in neighbors:
				if n_var is Rect2i:
					var nxt: Rect2i = n_var
					if visited.has(nxt):
						continue
					if _is_verify_edge_blocked(plan, curr, nxt, owned_keys, opened_shortcuts):
						continue
					visited[nxt] = true
					queue.append(nxt)
					progress = true

		for gate: SectorGatePlanner.SectorGate in plan.sector_gates:
			if gate.has_key and visited.has(gate.key_room) and not owned_keys.has(gate.color):
				owned_keys[gate.color] = true
				progress = true
			if gate.has_shortcut and visited.has(gate.key_room) and not opened_shortcuts.has(gate):
				opened_shortcuts[gate] = true
				progress = true

	for gate: SectorGatePlanner.SectorGate in plan.sector_gates:
		if gate.has_key and not owned_keys.has(gate.color):
			return false
		if not visited.has(gate.next_room):
			return false
	for room: Rect2i in plan.rooms:
		if not visited.has(room):
			return false
	return true


static func _connect_adj(adj: Dictionary[Rect2i, Array], room_a: Rect2i, room_b: Rect2i) -> void:
	if not adj.has(room_a):
		adj[room_a] = []
	if not adj[room_a].has(room_b):
		adj[room_a].append(room_b)
	if not adj.has(room_b):
		adj[room_b] = []
	if not adj[room_b].has(room_a):
		adj[room_b].append(room_a)


static func _is_verify_edge_blocked(
	plan: WorldPlan,
	room_a: Rect2i,
	room_b: Rect2i,
	owned_keys: Dictionary[WorldPlan.KeyColor, bool],
	opened_shortcuts: Dictionary[SectorGatePlanner.SectorGate, bool],
) -> bool:
	for gate: SectorGatePlanner.SectorGate in plan.sector_gates:
		if not owned_keys.has(gate.color):
			if (room_a == gate.gate_room and room_b == gate.next_room) or (room_b == gate.gate_room and room_a == gate.next_room):
				return true
		if gate.has_shortcut and gate.key_room != gate.shortcut_target_room and not opened_shortcuts.has(gate):
			if (room_a == gate.key_room and room_b == gate.shortcut_target_room) or (room_b == gate.key_room and room_a == gate.shortcut_target_room):
				return true
	return false
