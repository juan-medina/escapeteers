# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name ShortcutTunnelPlanner
extends RefCounted


class LocalShortcut:
	extends RefCounted
	var id: int = 0
	var room_near: Rect2i = Rect2i()
	var room_far: Rect2i = Rect2i()
	var sector_near: int = 0
	var sector_far: int = 0
	var is_horizontal_door: bool = true
	var door_cells: Array[Vector2i] = []
	var lever_cell: Vector2i = Vector2i.ZERO
	var corridor_rect: Rect2i = Rect2i()
	var opened: bool = false


const MIN_SHORTCUT_GAP: int = 4
const MAX_SHORTCUT_GAP: int = 30
const MIN_SAME_SECTOR_HOPS: int = 3
const MIN_CROSS_SECTOR_HOPS: int = 3
const MAX_LOCAL_SHORTCUTS: int = 18
const MAX_SHORTCUTS_PER_ROOM: int = 3


static func plan_local_shortcuts(plan: WorldPlan) -> void:
	plan.local_shortcuts.clear()
	var all_rooms: Array[Rect2i] = [plan.hero_room]
	all_rooms.append_array(plan.rooms)
	if all_rooms.size() < 4:
		return

	var sector_origins: Dictionary[int, Rect2i] = {0: plan.hero_room}
	for gate: SectorGatePlanner.SectorGate in plan.sector_gates:
		var next_sector: int = plan._room_sectors.get(gate.next_room, -1)
		if next_sector > 0 and not sector_origins.has(next_sector):
			sector_origins[next_sector] = gate.next_room

	var global_dists: Dictionary[Rect2i, int] = _bfs_distances(plan, plan.hero_room, {})
	var sector_dists: Dictionary[Rect2i, int] = {}
	for s_idx: int in sector_origins:
		var origin_room: Rect2i = sector_origins[s_idx]
		var allowed: Dictionary[Rect2i, bool] = {}
		for r: Rect2i in all_rooms:
			if plan._room_sectors.get(r, 0) == s_idx:
				allowed[r] = true
		var s_bfs: Dictionary[Rect2i, int] = _bfs_distances(plan, origin_room, allowed)
		for r: Rect2i in s_bfs:
			sector_dists[r] = s_bfs[r]

	var candidates: Array[Dictionary] = []
	for i: int in range(all_rooms.size()):
		var room_a: Rect2i = all_rooms[i]
		for j: int in range(i + 1, all_rooms.size()):
			var room_b: Rect2i = all_rooms[j]
			var neighbors_a: Array = plan._room_neighbors.get(room_a, [])
			if neighbors_a.has(room_b):
				continue
			var cand: Dictionary = _evaluate_pair(plan, room_a, room_b, global_dists, sector_dists)
			if not cand.is_empty():
				candidates.append(cand)

	candidates.sort_custom(_compare_candidates_desc)

	var per_room_counts: Dictionary[Rect2i, int] = {}
	var committed_rects: Array[Rect2i] = []
	var next_id: int = 0
	for cand: Dictionary in candidates:
		if plan.local_shortcuts.size() >= MAX_LOCAL_SHORTCUTS:
			break
		var r_near: Rect2i = cand[&"room_near"]
		var r_far: Rect2i = cand[&"room_far"]
		if per_room_counts.get(r_near, 0) >= MAX_SHORTCUTS_PER_ROOM or per_room_counts.get(r_far, 0) >= MAX_SHORTCUTS_PER_ROOM:
			continue

		var neck_rect: Rect2i = cand[&"corridor_rect"]
		if WorldPlan._intersects_any_rect(neck_rect.grow(2), committed_rects):
			continue

		var cur_hops: int = _graph_distance(plan, r_near, r_far)
		var min_req: int = MIN_CROSS_SECTOR_HOPS if cand[&"sector_near"] != cand[&"sector_far"] else MIN_SAME_SECTOR_HOPS
		if cur_hops < min_req:
			continue

		var sc: LocalShortcut = LocalShortcut.new()
		sc.id = next_id
		next_id += 1
		sc.room_near = r_near
		sc.room_far = r_far
		sc.sector_near = cand[&"sector_near"]
		sc.sector_far = cand[&"sector_far"]
		sc.is_horizontal_door = cand[&"is_horizontal_door"]
		sc.door_cells = cand[&"door_cells"]
		sc.lever_cell = cand[&"lever_cell"]
		sc.corridor_rect = neck_rect

		_commit_local_shortcut(plan, sc)
		committed_rects.append(neck_rect)
		per_room_counts[r_near] = per_room_counts.get(r_near, 0) + 1
		per_room_counts[r_far] = per_room_counts.get(r_far, 0) + 1


static func _evaluate_pair(
	plan: WorldPlan,
	room_a: Rect2i,
	room_b: Rect2i,
	global_dists: Dictionary[Rect2i, int],
	sector_dists: Dictionary[Rect2i, int],
) -> Dictionary:
	var sec_a: int = plan._room_sectors.get(room_a, 0)
	var sec_b: int = plan._room_sectors.get(room_b, 0)
	var hops: int = _graph_distance(plan, room_a, room_b)
	var min_req: int = MIN_CROSS_SECTOR_HOPS if sec_a != sec_b else MIN_SAME_SECTOR_HOPS
	if hops < min_req:
		return {}

	var room_near: Rect2i = room_a
	var room_far: Rect2i = room_b
	var sec_near: int = sec_a
	var sec_far: int = sec_b
	if sec_a != sec_b:
		if sec_a > sec_b:
			room_near = room_b
			room_far = room_a
			sec_near = sec_b
			sec_far = sec_a
	else:
		var da: int = sector_dists.get(room_a, global_dists.get(room_a, 0))
		var db: int = sector_dists.get(room_b, global_dists.get(room_b, 0))
		if da > db or (da == db and global_dists.get(room_a, 0) > global_dists.get(room_b, 0)):
			room_near = room_b
			room_far = room_a
			sec_near = sec_b
			sec_far = sec_a

	var ns_cand: Dictionary = _try_ns_shortcut(plan, room_near, room_far, sec_near, sec_far, hops)
	if not ns_cand.is_empty():
		return ns_cand
	return _try_ew_shortcut(plan, room_near, room_far, sec_near, sec_far, hops)


static func _try_ns_shortcut(
	plan: WorldPlan,
	room_near: Rect2i,
	room_far: Rect2i,
	sec_near: int,
	sec_far: int,
	hops: int,
) -> Dictionary:
	var top_r: Rect2i = room_near if room_near.end.y <= room_far.position.y else room_far
	var bot_r: Rect2i = room_far if top_r == room_near else room_near
	var gap: int = bot_r.position.y - top_r.end.y
	if gap < MIN_SHORTCUT_GAP or gap > MAX_SHORTCUT_GAP:
		return {}

	var min_x: int = maxi(top_r.position.x, bot_r.position.x) + 3
	var max_x: int = mini(top_r.end.x, bot_r.end.x) - 5
	if min_x > max_x:
		return {}

	var far_is_top: bool = room_far == top_r
	var door_y: int = top_r.end.y if far_is_top else (bot_r.position.y - 1)

	var mid_x: int = floori(float(min_x + max_x) * 0.5)
	var x_offsets: Array[int] = [0, -2, 2, -4, 4, -6, 6, -8, 8, -10, 10, -12, 12]
	for off: int in x_offsets:
		var door_x: int = clampi(mid_x + off, min_x, max_x)
		var corridor_rect: Rect2i = Rect2i(door_x, top_r.end.y - 2, 2, gap + 4)
		var gap_rect: Rect2i = Rect2i(door_x, top_r.end.y, 2, gap)
		var corridor_check_rect: Rect2i = gap_rect.grow_individual(3, 0, 3, 0)
		var top_socket: Rect2i = Rect2i(door_x - 1, top_r.end.y - 2, 4, 2)
		var bot_socket: Rect2i = Rect2i(door_x - 1, bot_r.position.y, 4, 2)
		if not _is_shortcut_geometry_valid(plan, room_near, room_far, corridor_rect, gap_rect, corridor_check_rect, top_socket, bot_socket):
			continue

		var mouth_center: Vector2i = Vector2i(door_x, top_r.end.y - 2) if far_is_top else Vector2i(door_x, bot_r.position.y + 2)
		var inward_y: int = -1 if far_is_top else 1
		var lever_cell: Vector2i = _find_lever_cell(plan, room_far, mouth_center, Vector2i(0, inward_y), true)
		if lever_cell.x == 2147483647:
			continue

		var score: int = hops * 100 - gap * 4 + (160 if sec_near != sec_far else 0)
		return {
			&"room_near": room_near,
			&"room_far": room_far,
			&"sector_near": sec_near,
			&"sector_far": sec_far,
			&"is_horizontal_door": true,
			&"door_cells": [Vector2i(door_x, door_y), Vector2i(door_x + 1, door_y)] as Array[Vector2i],
			&"lever_cell": lever_cell,
			&"corridor_rect": corridor_rect,
			&"score": score,
		}
	return {}


static func _try_ew_shortcut(
	plan: WorldPlan,
	room_near: Rect2i,
	room_far: Rect2i,
	sec_near: int,
	sec_far: int,
	hops: int,
) -> Dictionary:
	var left_r: Rect2i = room_near if room_near.end.x <= room_far.position.x else room_far
	var right_r: Rect2i = room_far if left_r == room_near else room_near
	var gap: int = right_r.position.x - left_r.end.x
	if gap < MIN_SHORTCUT_GAP or gap > MAX_SHORTCUT_GAP:
		return {}

	var min_y: int = maxi(left_r.position.y, right_r.position.y) + 3
	var max_y: int = mini(left_r.end.y, right_r.end.y) - 6
	if min_y > max_y:
		return {}

	var far_is_left: bool = room_far == left_r
	var door_x: int = left_r.end.x if far_is_left else (right_r.position.x - 1)

	var mid_y: int = floori(float(min_y + max_y) * 0.5)
	var y_offsets: Array[int] = [0, -2, 2, -4, 4, -6, 6, -8, 8, -10, 10, -12, 12]
	for off: int in y_offsets:
		var y0: int = clampi(mid_y + off, min_y, max_y)
		var corridor_rect: Rect2i = Rect2i(left_r.end.x - 2, y0, gap + 4, 3)
		var gap_rect: Rect2i = Rect2i(left_r.end.x, y0, gap, 3)
		var corridor_check_rect: Rect2i = gap_rect.grow_individual(0, 3, 0, 3)
		var left_socket: Rect2i = Rect2i(left_r.end.x - 2, y0 - 1, 2, 5)
		var right_socket: Rect2i = Rect2i(right_r.position.x, y0 - 1, 2, 5)
		if not _is_shortcut_geometry_valid(plan, room_near, room_far, corridor_rect, gap_rect, corridor_check_rect, left_socket, right_socket):
			continue

		var mouth_center: Vector2i = Vector2i(left_r.end.x - 2, y0 + 1) if far_is_left else Vector2i(right_r.position.x + 2, y0 + 1)
		var inward_x: int = -1 if far_is_left else 1
		var lever_cell: Vector2i = _find_lever_cell(plan, room_far, mouth_center, Vector2i(inward_x, 0), false)
		if lever_cell.x == 2147483647:
			continue

		var score: int = hops * 100 - gap * 4 + (160 if sec_near != sec_far else 0)
		return {
			&"room_near": room_near,
			&"room_far": room_far,
			&"sector_near": sec_near,
			&"sector_far": sec_far,
			&"is_horizontal_door": false,
			&"door_cells": [Vector2i(door_x, y0 + 1), Vector2i(door_x, y0 + 2)] as Array[Vector2i],
			&"lever_cell": lever_cell,
			&"corridor_rect": corridor_rect,
			&"score": score,
		}
	return {}


static func _is_shortcut_geometry_valid(
	plan: WorldPlan,
	room_near: Rect2i,
	room_far: Rect2i,
	corridor_rect: Rect2i,
	gap_rect: Rect2i,
	corridor_check_rect: Rect2i,
	socket_a: Rect2i,
	socket_b: Rect2i,
) -> bool:
	if plan._is_outside_world_bounds(corridor_rect):
		return false
	if WorldPlan._intersects_any_rect(corridor_rect.grow(1), plan.protected_neck_rects):
		return false
	if WorldPlan._intersects_any_rect(corridor_rect.grow(1), plan._cut_corner_rects):
		return false
	if WorldPlan._intersects_any_rect(socket_a.grow(1), plan._all_pillars) or WorldPlan._intersects_any_rect(socket_b.grow(1), plan._all_pillars):
		return false

	for sock: Rect2i in [socket_a, socket_b]:
		for cy: int in range(sock.position.y, sock.end.y):
			for cx: int in range(sock.position.x, sock.end.x):
				var cell: Vector2i = Vector2i(cx, cy)
				if not plan.is_floor(cell) or plan.no_prop_cells.has(cell) or plan.door_cell_codes.has(cell) or plan.shortcut_blocker_cells.has(cell):
					return false

	var padded_gap: Rect2i = gap_rect.grow(3)
	if plan.hero_room != room_near and plan.hero_room != room_far and plan.hero_room.intersects(padded_gap):
		return false
	for r_id: int in plan._room_grid.get_candidate_ids_for_rect(padded_gap):
		if r_id >= 0 and r_id < plan.rooms.size():
			var other: Rect2i = plan.rooms[r_id]
			if other != room_near and other != room_far and other.intersects(padded_gap):
				return false
	if WorldPlan._intersects_any_rect(corridor_check_rect, plan._corridor_rects):
		return false
	return true


static func _find_lever_cell(
	plan: WorldPlan,
	room_far: Rect2i,
	mouth_cell: Vector2i,
	inward_dir: Vector2i,
	is_horizontal_door: bool,
) -> Vector2i:
	var spawns: Array = plan.get_companion_spawns_for_room(room_far)
	var inner_bounds: Rect2i = Rect2i(room_far.position.x + 2, room_far.position.y + 2, room_far.size.x - 4, room_far.size.y - 4)
	var lat_offsets: Array[int] = [-1, 2, -2, 3, 0, 1]
	for depth_step: int in [0, 1, 2]:
		for lat: int in lat_offsets:
			var cand: Vector2i = mouth_cell + inward_dir * depth_step + (Vector2i(lat, 0) if is_horizontal_door else Vector2i(0, lat))
			if not inner_bounds.has_point(cand):
				continue
			if not plan.is_floor(cand) or not plan.is_floor(cand + Vector2i(0, -1)):
				continue
			if plan.no_prop_cells.has(cand) or plan.lever_cells.has(cand) or plan._is_near_pillar(cand, 1):
				continue
			var blocked: bool = false
			for s_var: Variant in spawns:
				if s_var is Vector2i:
					var s_cell: Vector2i = s_var
					if cand.distance_squared_to(s_cell) < 4:
						blocked = true
						break
			if blocked:
				continue
			for gate: SectorGatePlanner.SectorGate in plan.sector_gates:
				if gate.has_key and cand.distance_squared_to(gate.key_cell) < 6:
					blocked = true
					break
			if not blocked:
				return cand
	return Vector2i(2147483647, 2147483647)


static func _commit_local_shortcut(plan: WorldPlan, sc: LocalShortcut) -> void:
	plan._add_carve_rect(sc.corridor_rect, sc.sector_far)
	plan._corridor_rects.append(sc.corridor_rect)
	plan._corridor_sectors.append(sc.sector_far)
	plan.protected_neck_rects.append(sc.corridor_rect.grow(1))

	if sc.is_horizontal_door:
		var dx: int = sc.corridor_rect.position.x
		var y_min: int = sc.corridor_rect.position.y
		var y_max: int = sc.corridor_rect.end.y - 1
		(
			plan
			. _corridor_segments
			. append(
				{
					&"is_horizontal": false,
					&"min": y_min,
					&"max": y_max,
					&"fixed": dx,
					&"half_width": 1,
					&"is_shortcut": true,
				}
			)
		)
	else:
		var x_min: int = sc.corridor_rect.position.x
		var x_max: int = sc.corridor_rect.end.x - 1
		var y_mid: int = sc.corridor_rect.position.y + 1
		(
			plan
			. _corridor_segments
			. append(
				{
					&"is_horizontal": true,
					&"min": x_min,
					&"max": x_max,
					&"fixed": y_mid,
					&"half_width": 1,
					&"is_shortcut": true,
				}
			)
		)

	for dcell: Vector2i in sc.door_cells:
		plan.shortcut_blocker_cells[dcell] = sc.id
		SectorGatePlanner._mark_no_prop_radius(plan, dcell, 2)

	plan.lever_cells[sc.lever_cell] = sc.id
	SectorGatePlanner._mark_no_prop_radius(plan, sc.lever_cell, 2)
	plan._add_neighbor_edge(sc.room_near, sc.room_far)
	plan.local_shortcuts.append(sc)


static func _bfs_distances(
	plan: WorldPlan,
	origin: Rect2i,
	allowed_rooms: Dictionary[Rect2i, bool],
) -> Dictionary[Rect2i, int]:
	var dists: Dictionary[Rect2i, int] = {origin: 0}
	var queue: Array[Rect2i] = [origin]
	var head: int = 0
	var restrict: bool = not allowed_rooms.is_empty()
	while head < queue.size():
		var cur: Rect2i = queue[head]
		head += 1
		var cur_d: int = dists[cur]
		for n_var: Variant in plan._room_neighbors.get(cur, []):
			if n_var is Rect2i:
				var nb: Rect2i = n_var
				if restrict and not allowed_rooms.has(nb):
					continue
				if not dists.has(nb):
					dists[nb] = cur_d + 1
					queue.append(nb)
	return dists


static func _graph_distance(plan: WorldPlan, room_a: Rect2i, room_b: Rect2i) -> int:
	if room_a == room_b:
		return 0
	var dists: Dictionary[Rect2i, int] = {room_a: 0}
	var queue: Array[Rect2i] = [room_a]
	var head: int = 0
	while head < queue.size():
		var cur: Rect2i = queue[head]
		head += 1
		var next_d: int = dists[cur] + 1
		for n_var: Variant in plan._room_neighbors.get(cur, []):
			if n_var is Rect2i:
				var nb: Rect2i = n_var
				if nb == room_b:
					return next_d
				if not dists.has(nb):
					dists[nb] = next_d
					queue.append(nb)
	return 999


static func _compare_candidates_desc(a: Dictionary, b: Dictionary) -> bool:
	var sa: int = a[&"score"]
	var sb: int = b[&"score"]
	return sa > sb


static func find_safe_key_cell(plan: WorldPlan, key_room: Rect2i, avoid_cell: Vector2i) -> Vector2i:
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
		if avoid_cell.x != 2147483647 and cand.distance_squared_to(avoid_cell) < 9:
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
	var opened_shortcuts: Dictionary[LocalShortcut, bool] = {}
	var unlocked_sectors: Dictionary[int, bool] = {0: true}

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
					var nxt_sec: int = plan._room_sectors.get(nxt, 0)
					if not unlocked_sectors.has(nxt_sec):
						return false
					visited[nxt] = true
					queue.append(nxt)
					progress = true

		for gate: SectorGatePlanner.SectorGate in plan.sector_gates:
			if gate.has_key and visited.has(gate.key_room) and not owned_keys.has(gate.color):
				owned_keys[gate.color] = true
				var next_sec: int = plan._room_sectors.get(gate.next_room, -1)
				if next_sec > 0:
					unlocked_sectors[next_sec] = true
				progress = true

		for sc: LocalShortcut in plan.local_shortcuts:
			if visited.has(sc.room_far) and not opened_shortcuts.has(sc):
				opened_shortcuts[sc] = true
				progress = true

	for gate: SectorGatePlanner.SectorGate in plan.sector_gates:
		if gate.has_key and not owned_keys.has(gate.color):
			return false
		if not visited.has(gate.next_room):
			return false
	for sc: LocalShortcut in plan.local_shortcuts:
		if not opened_shortcuts.has(sc):
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
	opened_shortcuts: Dictionary[LocalShortcut, bool],
) -> bool:
	for gate: SectorGatePlanner.SectorGate in plan.sector_gates:
		if not owned_keys.has(gate.color):
			if (room_a == gate.gate_room and room_b == gate.next_room) or (room_b == gate.gate_room and room_a == gate.next_room):
				return true
	for sc: LocalShortcut in plan.local_shortcuts:
		if not opened_shortcuts.has(sc):
			if (room_a == sc.room_near and room_b == sc.room_far) or (room_b == sc.room_near and room_a == sc.room_far):
				return true
	return false
