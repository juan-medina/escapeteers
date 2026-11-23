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
	var shortcut_waypoints: Array[Vector2i] = []
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
const MIN_KEY_HOPS: int = 4
const MAX_KEY_EXTEND_STEPS: int = 4


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


static func build_sector_gate(
	plan: WorldPlan,
	sector_rooms: Array[Rect2i],
	entry_room: Rect2i,
	sector_idx: int,
	current_depth: int,
) -> Rect2i:
	var gate_idx: int = GATE_DEPTHS.find(current_depth)
	if gate_idx < 0:
		return Rect2i()

	var gate_color: WorldPlan.KeyColor = gate_idx as WorldPlan.KeyColor
	var bfs_rooms: Array[Rect2i] = sector_rooms.duplicate()
	if not bfs_rooms.has(entry_room):
		bfs_rooms.append(entry_room)
	var dist_from_entry: Dictionary[Rect2i, int] = _bfs_sector_distances(plan, entry_room, bfs_rooms)
	var gate_room: Rect2i = _pick_gate_room(plan, sector_rooms, entry_room, dist_from_entry)
	if gate_room.size == Vector2i.ZERO:
		return Rect2i()

	var dist_from_gate: Dictionary[Rect2i, int] = _bfs_sector_distances(plan, gate_room, bfs_rooms)
	var key_room: Rect2i = _ensure_key_room(
		plan,
		gate_room,
		entry_room,
		sector_rooms,
		bfs_rooms,
		dist_from_gate,
		dist_from_entry,
		sector_idx,
		current_depth,
	)

	var gate: SectorGate = SectorGate.new()
	gate.color = gate_color
	gate.gate_depth = current_depth
	gate.gate_room = gate_room
	gate.key_room = key_room

	var next_room: Rect2i = _spawn_next_sector_room(plan, gate, gate_room, current_depth + 1, sector_idx + 1)
	if next_room.size == Vector2i.ZERO:
		return Rect2i()
	gate.next_room = next_room

	_setup_shortcut_and_key(plan, gate, key_room, gate_room, sector_idx)
	_add_safe_sector_loops(plan, gate, sector_rooms, bfs_rooms, gate_room, key_room, sector_idx)
	if key_room != gate_room:
		plan._add_neighbor_edge(key_room, gate_room)
	plan.sector_gates.append(gate)
	_register_gate_tiles_and_no_prop(plan, gate)
	return next_room


static func _bfs_sector_distances(plan: WorldPlan, origin: Rect2i, sector_rooms: Array[Rect2i]) -> Dictionary[Rect2i, int]:
	var allowed: Dictionary[Rect2i, bool] = {origin: true}
	for r: Rect2i in sector_rooms:
		allowed[r] = true

	var dists: Dictionary[Rect2i, int] = {origin: 0}
	var queue: Array[Rect2i] = [origin]
	var head: int = 0
	while head < queue.size():
		var cur: Rect2i = queue[head]
		head += 1
		var cur_dist: int = dists[cur]
		var neighbors: Array = plan._room_neighbors.get(cur, [])
		for n_var: Variant in neighbors:
			if n_var is Rect2i:
				var n_room: Rect2i = n_var
				if allowed.has(n_room) and not dists.has(n_room):
					dists[n_room] = cur_dist + 1
					queue.append(n_room)
	return dists


static func _get_sector_degree(plan: WorldPlan, room: Rect2i, sector_rooms: Array[Rect2i]) -> int:
	var deg: int = 0
	var neighbors: Array = plan._room_neighbors.get(room, [])
	for n_var: Variant in neighbors:
		if n_var is Rect2i:
			var n_room: Rect2i = n_var
			if sector_rooms.has(n_room) or n_room == plan.hero_room:
				deg += 1
	return deg


static func _has_clear_north_wall_strip(plan: WorldPlan, room: Rect2i, height: int = 6) -> bool:
	var door_x: int = room.get_center().x - 1
	var door_y: int = room.position.y
	var probe: Rect2i = Rect2i(door_x - 3, door_y - height, 8, height)
	if plan._is_outside_world_bounds(probe):
		return false
	return not plan.spatial_grid.intersects_any(probe, plan.carve_rects, 0)


static func _has_clear_north_gate_space(plan: WorldPlan, room: Rect2i, probe_height: int) -> bool:
	if not _has_clear_north_wall_strip(plan, room, 6):
		return false
	var probe_rect: Rect2i = Rect2i(room.get_center().x - 18, room.position.y - 14 - probe_height, 36, probe_height)
	if plan._is_outside_world_bounds(probe_rect) or plan.hero_room.grow(4).intersects(probe_rect):
		return false
	if plan._room_grid.intersects_any(probe_rect, plan.rooms, 4):
		return false
	return not WorldPlan._intersects_any_rect(probe_rect.grow(2), plan._corridor_rects)


static func _pick_gate_room(plan: WorldPlan, sector_rooms: Array[Rect2i], entry_room: Rect2i, dist_from_entry: Dictionary[Rect2i, int]) -> Rect2i:
	var pool: Array[Rect2i] = []
	for probe_h: int in [44, 24, 0]:
		for r: Rect2i in sector_rooms:
			if r == entry_room or r == plan.hero_room:
				continue
			var ok: bool = _has_clear_north_gate_space(plan, r, probe_h) if probe_h > 0 else _has_clear_north_wall_strip(plan, r, 6)
			if ok:
				pool.append(r)
		if not pool.is_empty():
			break

	if pool.is_empty():
		return sector_rooms[0] if not sector_rooms.is_empty() else Rect2i()

	var best: Rect2i = pool[0]
	var best_score: int = _score_gate_candidate(best, dist_from_entry)
	for r: Rect2i in pool:
		var score: int = _score_gate_candidate(r, dist_from_entry)
		if score < best_score:
			best_score = score
			best = r
	return best


static func _score_gate_candidate(room: Rect2i, dist_from_entry: Dictionary[Rect2i, int]) -> int:
	var entry_bonus: int = -120 if dist_from_entry.get(room, 0) >= 2 else 0
	return room.position.y * 10 + absi(room.get_center().x) + entry_bonus


static func _ensure_key_room(
	plan: WorldPlan,
	gate_room: Rect2i,
	entry_room: Rect2i,
	sector_rooms: Array[Rect2i],
	bfs_rooms: Array[Rect2i],
	dist_from_gate: Dictionary[Rect2i, int],
	dist_from_entry: Dictionary[Rect2i, int],
	sector_idx: int,
	current_depth: int,
) -> Rect2i:
	var valid: Array[Rect2i] = _collect_valid_key_candidates(plan, gate_room, entry_room, sector_rooms)
	var max_dist: int = _max_candidate_dist(valid, dist_from_gate)

	for step: int in range(MAX_KEY_EXTEND_STEPS + 1):
		if not valid.is_empty() and (step >= MAX_KEY_EXTEND_STEPS or max_dist >= MIN_KEY_HOPS):
			break
		var ext: Rect2i = _spawn_key_wing_extension(plan, gate_room, entry_room, sector_rooms, dist_from_gate, sector_idx, current_depth)
		if ext.size == Vector2i.ZERO:
			break
		sector_rooms.append(ext)
		bfs_rooms.append(ext)
		dist_from_gate = _bfs_sector_distances(plan, gate_room, bfs_rooms)
		dist_from_entry = _bfs_sector_distances(plan, entry_room, bfs_rooms)
		valid = _collect_valid_key_candidates(plan, gate_room, entry_room, sector_rooms)
		max_dist = _max_candidate_dist(valid, dist_from_gate)

	if valid.is_empty():
		for r: Rect2i in sector_rooms:
			if r != gate_room and r != entry_room and r != plan.hero_room:
				valid.append(r)
		if valid.is_empty():
			return gate_room

	return _pick_best_key_room(plan, gate_room, sector_rooms, valid, dist_from_gate, dist_from_entry)


static func _collect_valid_key_candidates(
	plan: WorldPlan,
	gate_room: Rect2i,
	entry_room: Rect2i,
	sector_rooms: Array[Rect2i],
) -> Array[Rect2i]:
	var valid: Array[Rect2i] = []
	for r: Rect2i in sector_rooms:
		if r == gate_room or r == entry_room or r == plan.hero_room:
			continue
		if _has_clear_north_wall_strip(plan, r, 6):
			valid.append(r)
	return valid


static func _max_candidate_dist(candidates: Array[Rect2i], dist_from_gate: Dictionary[Rect2i, int]) -> int:
	var best: int = -1
	for r: Rect2i in candidates:
		var d: int = dist_from_gate.get(r, -1)
		if d > best:
			best = d
	return best


static func _pick_best_key_room(
	plan: WorldPlan,
	gate_room: Rect2i,
	sector_rooms: Array[Rect2i],
	candidates: Array[Rect2i],
	dist_from_gate: Dictionary[Rect2i, int],
	dist_from_entry: Dictionary[Rect2i, int],
) -> Rect2i:
	var gate_center: Vector2i = gate_room.get_center()
	var best: Rect2i = candidates[0]
	var best_score: int = -999999999

	for r: Rect2i in candidates:
		var hop_dist: int = dist_from_gate.get(r, 1)
		var reach_bonus: int = 3000 if hop_dist >= MIN_KEY_HOPS else 0
		var hop_score: int = mini(hop_dist, 6) * 700
		var leaf_bonus: int = 600 if _get_sector_degree(plan, r, sector_rooms) <= 1 else 0
		var entry_sep: int = 200 if dist_from_entry.get(r, 0) >= 2 else 0
		var euclid_dist: int = int(roundf(Vector2(r.get_center()).distance_to(Vector2(gate_center))))
		var north_penalty: int = 400 if r.position.y < gate_room.position.y - 4 else 0
		var score: int = reach_bonus + hop_score + leaf_bonus + entry_sep - euclid_dist * 8 - north_penalty
		if score > best_score:
			best_score = score
			best = r
	return best


static func _spawn_key_wing_extension(
	plan: WorldPlan,
	gate_room: Rect2i,
	entry_room: Rect2i,
	sector_rooms: Array[Rect2i],
	dist_from_gate: Dictionary[Rect2i, int],
	sector_idx: int,
	target_depth: int,
) -> Rect2i:
	var tried: Dictionary[Rect2i, bool] = {}
	var south_limit_y: int = (plan.hero_room.end.y + 45) if sector_idx == 0 else (entry_room.end.y + 25)
	var gate_center: Vector2 = Vector2(gate_room.get_center())

	for _pick: int in range(sector_rooms.size()):
		var best_p: Rect2i = Rect2i()
		var best_score: int = -999999
		for r: Rect2i in sector_rooms:
			if r == gate_room or tried.has(r) or not dist_from_gate.has(r):
				continue
			var s: int = dist_from_gate[r] * 10 - _get_sector_degree(plan, r, sector_rooms)
			if s > best_score:
				best_score = s
				best_p = r
		if best_p.size == Vector2i.ZERO:
			break
		tried[best_p] = true
		var away_dir: Vector2 = Vector2(best_p.get_center()) - gate_center
		var away_angle: float = away_dir.angle() if away_dir.length_squared() > 1.0 else (-PI * 0.85 if best_p.get_center().x <= 0 else -PI * 0.15)
		for attempt: int in range(28):
			var spread: float = 0.75 if attempt < 16 else 1.55
			var angle: float = away_angle + plan._rng.randf_range(-spread, spread)
			var wing: Rect2i = plan._try_place_maze_child(best_p, sector_idx, target_depth, angle, south_limit_y, true)
			if wing.size != Vector2i.ZERO:
				return wing
	return Rect2i()


static func _add_safe_sector_loops(
	plan: WorldPlan,
	gate: SectorGate,
	sector_rooms: Array[Rect2i],
	bfs_rooms: Array[Rect2i],
	gate_room: Rect2i,
	key_room: Rect2i,
	sector_idx: int,
) -> void:
	var pairs: Array[Array] = []
	for i: int in range(sector_rooms.size()):
		var room_a: Rect2i = sector_rooms[i]
		if room_a == key_room:
			continue
		for j: int in range(i + 1, sector_rooms.size()):
			var room_b: Rect2i = sector_rooms[j]
			if room_b == key_room:
				continue
			var neighbors_a: Array = plan._room_neighbors.get(room_a, [])
			if neighbors_a.has(room_b):
				continue
			var d: float = Vector2(room_a.get_center()).distance_to(Vector2(room_b.get_center()))
			if d <= WorldPlan.LOOP_CONNECT_MAX_DISTANCE:
				pairs.append([room_a, room_b])

	if pairs.is_empty():
		return

	for i: int in range(pairs.size() - 1, 0, -1):
		var swap_idx: int = plan._rng.randi_range(0, i)
		var tmp: Array = pairs[i]
		pairs[i] = pairs[swap_idx]
		pairs[swap_idx] = tmp

	var dist_from_gate: Dictionary[Rect2i, int] = _bfs_sector_distances(plan, gate_room, bfs_rooms)
	var dist_from_key: Dictionary[Rect2i, int] = _bfs_sector_distances(plan, key_room, bfs_rooms)
	var added: int = 0

	for pair: Array in pairs:
		if added >= WorldPlan.MAX_LOOPS_PER_SECTOR:
			break
		var room_a: Rect2i = pair[0]
		var room_b: Rect2i = pair[1]
		var path_a: int = dist_from_key.get(room_a, 999) + 1 + dist_from_gate.get(room_b, 999)
		var path_b: int = dist_from_key.get(room_b, 999) + 1 + dist_from_gate.get(room_a, 999)
		if mini(path_a, path_b) < MIN_KEY_HOPS:
			continue
		var segs: Array[Dictionary] = RoomLayout.plan_corridor(plan, room_a, room_b, [], sector_idx, true)
		if segs.is_empty() or _corridor_hits_shortcut(segs, gate.shortcut_corridor_rects):
			continue
		RoomLayout.commit_corridor(plan, segs, sector_idx)
		plan._add_neighbor_edge(room_a, room_b)
		added += 1
		dist_from_gate = _bfs_sector_distances(plan, gate_room, bfs_rooms)
		dist_from_key = _bfs_sector_distances(plan, key_room, bfs_rooms)


static func _corridor_hits_shortcut(segs: Array[Dictionary], shortcut_rects: Array[Rect2i]) -> bool:
	for seg: Dictionary in segs:
		var r: Rect2i = seg[&"rect"]
		if WorldPlan._intersects_any_rect(r.grow(2), shortcut_rects):
			return true
	return false


static func _setup_shortcut_and_key(
	plan: WorldPlan,
	gate: SectorGate,
	key_room: Rect2i,
	gate_room: Rect2i,
	sector_idx: int,
) -> void:
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
	var own_neck_guard: Rect2i = Rect2i(exit_x - 3, neck_top_y - 1, 8, 7)
	gate.shortcut_corridor_rects.append(shortcut_neck)

	if key_room == gate_room:
		plan.protected_neck_rects.append(own_neck_guard)
		return

	var chosen: Dictionary = _pick_best_shortcut_route(plan, gate, key_room, gate_room, sector_idx, exit_x, neck_top_y)
	plan.protected_neck_rects.append(own_neck_guard)
	gate.gate_entry_cell = chosen[&"entry_cell"]
	gate.shortcut_waypoints = chosen[&"waypoints"]
	var tunnel_segs: Array[Rect2i] = chosen[&"segs"]
	for seg: Rect2i in tunnel_segs:
		plan._corridor_rects.append(seg)
		plan._corridor_sectors.append(sector_idx)
		gate.shortcut_corridor_rects.append(seg)


static func _pick_best_shortcut_route(
	plan: WorldPlan,
	gate: SectorGate,
	key_room: Rect2i,
	gate_room: Rect2i,
	sector_idx: int,
	exit_x: int,
	neck_top_y: int,
) -> Dictionary:
	var prefer_west: bool = exit_x <= gate_room.get_center().x
	var side_choices: Array[bool] = [prefer_west, not prefer_west]
	var entry_y: int = gate_room.get_center().y
	var turn_ys: Array[int] = [
		neck_top_y,
		mini(neck_top_y, entry_y),
		mini(neck_top_y, gate_room.position.y - 10),
		mini(neck_top_y, gate_room.position.y - 22),
		neck_top_y - 12,
		neck_top_y - 26,
		mini(neck_top_y, gate.next_room.position.y - 6),
	]
	var best_route: Dictionary = {}
	var best_score: int = 999999999

	for from_west: bool in side_choices:
		var near_x: int = (gate_room.position.x - 5) if from_west else (gate_room.end.x + 4)
		var clear_x: int = mini(near_x, gate.next_room.position.x - 6) if from_west else maxi(near_x, gate.next_room.end.x + 5)
		var side_xs: Array[int] = [near_x]
		if near_x != clear_x:
			side_xs.append(clear_x)
		var gate_wall_x: int = (gate_room.position.x - 1) if from_west else gate_room.end.x
		var gate_inside_x: int = (gate_room.position.x + 2) if from_west else (gate_room.end.x - 3)
		for side_x: int in side_xs:
			for turn_y: int in turn_ys:
				var segs: Array[Rect2i] = _build_shortcut_route_rects(exit_x, neck_top_y, turn_y, side_x, entry_y, gate_inside_x)
				if not _is_shortcut_route_valid(plan, gate, segs, key_room, gate_room, sector_idx):
					continue
				var score: int = _score_shortcut_route(plan, gate, segs, key_room, gate_room, gate_wall_x, entry_y)
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

	if not best_route.is_empty():
		return best_route

	var fb_west_x: int = mini(gate_room.position.x - 5, gate.next_room.position.x - 6)
	var fb_east_x: int = maxi(gate_room.end.x + 4, gate.next_room.end.x + 5)
	var fb_side: int = fb_west_x if prefer_west else fb_east_x
	var fb_wall: int = (gate_room.position.x - 1) if prefer_west else gate_room.end.x
	var fb_in: int = (gate_room.position.x + 2) if prefer_west else (gate_room.end.x - 3)
	var fb_y: int = mini(neck_top_y, gate.next_room.position.y - 6)
	var fb_segs: Array[Rect2i] = _build_shortcut_route_rects(exit_x, neck_top_y, fb_y, fb_side, entry_y, fb_in)
	var fb_wps: Array[Vector2i] = [
		Vector2i(exit_x, neck_top_y + 5),
		Vector2i(exit_x, fb_y),
		Vector2i(fb_side, fb_y),
		Vector2i(fb_side, entry_y),
		Vector2i(fb_in, entry_y),
	]
	return {&"segs": fb_segs, &"entry_cell": Vector2i(fb_wall, entry_y), &"waypoints": fb_wps}


static func _build_shortcut_route_rects(
	exit_x: int,
	neck_top_y: int,
	turn_y: int,
	side_x: int,
	entry_y: int,
	gate_inside_x: int,
) -> Array[Rect2i]:
	var segs: Array[Rect2i] = []
	if turn_y < neck_top_y:
		segs.append(_make_vert_corridor_rect(turn_y, neck_top_y, exit_x, 1))
	var leg1_start_x: int = exit_x if side_x > exit_x else (exit_x + 1)
	segs.append(_make_horiz_corridor_rect(leg1_start_x, side_x, turn_y, 1))
	segs.append(_make_vert_corridor_rect(turn_y, entry_y, side_x, 1))
	segs.append(_make_horiz_corridor_rect(side_x, gate_inside_x, entry_y, 2))
	return segs


static func _is_shortcut_route_valid(
	plan: WorldPlan,
	gate: SectorGate,
	segs: Array[Rect2i],
	key_room: Rect2i,
	gate_room: Rect2i,
	sector_idx: int,
) -> bool:
	var last_idx: int = segs.size() - 1
	for i: int in range(segs.size()):
		var r: Rect2i = segs[i]
		if plan._is_outside_world_bounds(r) or r.intersects(gate.next_room.grow(2)) or r.intersects(key_room.grow(1)):
			return false
		if i < last_idx and r.intersects(gate_room.grow(1)):
			return false
		if WorldPlan._intersects_any_rect(r.grow(1), plan.protected_neck_rects):
			return false
		if _hits_other_sector_geometry(plan, r, sector_idx):
			return false
	return true


static func _hits_other_sector_geometry(plan: WorldPlan, rect: Rect2i, sector_idx: int) -> bool:
	var padded: Rect2i = rect.grow(2)
	if sector_idx != 0 and plan.hero_room.intersects(padded):
		return true
	for r_id: int in plan._room_grid.get_candidate_ids_for_rect(padded):
		if r_id >= 0 and r_id < plan.rooms.size():
			var other: Rect2i = plan.rooms[r_id]
			if plan._room_sectors.get(other, 0) != sector_idx and other.intersects(padded):
				return true
	for c_idx: int in range(plan._corridor_rects.size()):
		if plan._corridor_sectors[c_idx] != sector_idx and plan._corridor_rects[c_idx].intersects(padded):
			return true
	return false


static func _score_shortcut_route(
	plan: WorldPlan,
	gate: SectorGate,
	segs: Array[Rect2i],
	key_room: Rect2i,
	gate_room: Rect2i,
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
				if other == key_room or (i == last_idx and other == gate_room):
					continue
				if other.intersects(r):
					score += 10000
		for c_rect: Rect2i in plan._corridor_rects:
			if c_rect.intersects(r):
				score += 2000
	if plan.is_floor(Vector2i(gate_wall_x, entry_y)):
		score += 50
	return score


static func _spawn_next_sector_room(
	plan: WorldPlan,
	gate: SectorGate,
	gate_room: Rect2i,
	next_depth: int,
	next_sector: int,
) -> Rect2i:
	var door_x: int = gate_room.get_center().x - 1
	var door_y: int = gate_room.position.y
	gate.door_cells = [Vector2i(door_x, door_y), Vector2i(door_x + 1, door_y)]

	var x_offsets: Array[int] = [0, -6, 6, -12, 12, -18, 18, -24, 24, -32, 32]
	var y_extras: Array[int] = [0, 8, 16, 24, 32, 40, 52, 66]

	for y_extra: int in y_extras:
		for x_off: int in x_offsets:
			var size: Vector2i = RoomLayout.roll_room_size(plan._rng, next_depth)
			var bottom_y: int = door_y - 14 - y_extra
			var top_left: Vector2i = Vector2i(gate_room.get_center().x + x_off - int(float(size.x) * 0.5), bottom_y - size.y)
			var candidate: Rect2i = Rect2i(top_left, size)
			if plan._is_outside_world_bounds(candidate) or plan._overlaps_any_room(candidate):
				continue

			var dest_center: Vector2i = candidate.get_center()
			var mid_y: int = bottom_y + 5
			if _next_room_entry_blocked(plan, gate_room, candidate, door_x, door_y, mid_y, dest_center):
				continue

			var door_neck: Rect2i = Rect2i(door_x, door_y - 5, 2, 6)
			plan._add_carve_rect(door_neck)
			plan.protected_neck_rects.append(Rect2i(door_x - 3, door_y - 6, 8, 7))
			if not plan.room_children.has(gate_room):
				plan.room_children[gate_room] = []
			plan.room_children[gate_room].append(candidate)
			plan._add_neighbor_edge(gate_room, candidate)
			plan._add_room(candidate, next_depth, next_sector)

			if dest_center.x == door_x:
				plan._add_vertical_corridor_rect(door_y - 5, dest_center.y, door_x, 2, next_sector)
			else:
				plan._add_vertical_corridor_rect(door_y - 5, mid_y, door_x, 2, next_sector)
				plan._add_horizontal_corridor_rect(door_x, dest_center.x, mid_y, 2, next_sector)
				plan._add_vertical_corridor_rect(mid_y, dest_center.y, dest_center.x, 2, next_sector)
			return candidate

	return Rect2i()


static func _next_room_entry_blocked(
	plan: WorldPlan,
	gate_room: Rect2i,
	candidate: Rect2i,
	door_x: int,
	door_y: int,
	mid_y: int,
	dest_center: Vector2i,
) -> bool:
	var segs: Array[Rect2i] = []
	if dest_center.x == door_x:
		segs.append(_make_vert_corridor_rect(door_y - 5, dest_center.y, door_x, 2))
	else:
		segs.append(_make_vert_corridor_rect(door_y - 5, mid_y, door_x, 2))
		segs.append(_make_horiz_corridor_rect(door_x, dest_center.x, mid_y, 2))
		segs.append(_make_vert_corridor_rect(mid_y, dest_center.y, dest_center.x, 2))

	for i: int in range(segs.size()):
		var seg: Rect2i = segs[i]
		if plan._is_outside_world_bounds(seg) or seg.grow(2).intersects(plan.hero_room):
			return true
		if i > 0 and seg.intersects(gate_room.grow(1)):
			return true
		if i < segs.size() - 1 and seg.intersects(candidate):
			return true
		for r_id: int in plan._room_grid.get_candidate_ids_for_rect(seg.grow(2)):
			if r_id >= 0 and r_id < plan.rooms.size():
				var other: Rect2i = plan.rooms[r_id]
				if other != gate_room and other.intersects(seg.grow(2)):
					return true
		if WorldPlan._intersects_any_rect(seg.grow(2), plan._corridor_rects):
			return true
	return false


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
