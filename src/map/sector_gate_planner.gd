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
	var door_face: RoomLayout.Face = RoomLayout.Face.NORTH
	var door_cells: Array[Vector2i] = []
	var key_room: Rect2i = Rect2i()
	var key_cell: Vector2i = Vector2i.ZERO
	var door_unlocked: bool = false
	var has_key: bool = true
	var key_sector: int = 0


const GATE_DEPTHS: Array[int] = [2, 5, 8, 11]
const MIN_KEY_HOPS: int = 4
const MAX_KEY_EXTEND_STEPS: int = 4
const POCKET_SIZE: int = 56
const ALL_FACES: Array[RoomLayout.Face] = [
	RoomLayout.Face.NORTH,
	RoomLayout.Face.SOUTH,
	RoomLayout.Face.EAST,
	RoomLayout.Face.WEST,
]


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


static func generate_dungeon_sectors(plan: WorldPlan, target_max_depth: int) -> void:
	var s0_rooms: Array[Rect2i] = plan._build_sector_rooms(plan.hero_room, 0, target_max_depth, Vector2.ZERO)
	if target_max_depth <= 2:
		return

	var blue_gate: SectorGate = null
	var green_gate: SectorGate = null
	if target_max_depth > 5:
		var hub0: Dictionary = _build_hub_pair_gates(plan, s0_rooms, plan.hero_room, 0)
		blue_gate = hub0.get(&"primary_gate", null)
		green_gate = hub0.get(&"secondary_gate", null)
	else:
		blue_gate = build_sector_gate(plan, s0_rooms, plan.hero_room, 0, 2)

	if blue_gate == null:
		return

	var green_pocket: Rect2i = Rect2i()
	if green_gate != null:
		green_pocket = _make_gate_pocket(green_gate.next_room, green_gate.door_face)
		plan._reserved_pockets.append(green_pocket)

	var s1_dir: Vector2 = _face_to_vec(blue_gate.door_face)
	var s1_rooms: Array[Rect2i] = plan._build_sector_rooms(blue_gate.next_room, 1, target_max_depth, s1_dir)
	var yellow_gate: SectorGate = null
	var yellow_pocket: Rect2i = Rect2i()
	if target_max_depth > 8 and green_gate != null:
		yellow_gate = _spawn_wing_forward_gate(plan, s1_rooms, blue_gate.next_room, 1, WorldPlan.KeyColor.YELLOW, 8, 3, s1_dir)
		if yellow_gate != null:
			yellow_pocket = _make_gate_pocket(yellow_gate.next_room, yellow_gate.door_face)
			plan._reserved_pockets.append(yellow_pocket)

	if green_gate != null:
		_finalize_wing_key_gate(plan, green_gate, s1_rooms, blue_gate.next_room, 5)
	elif target_max_depth > 5:
		green_gate = build_sector_gate(plan, s1_rooms, blue_gate.next_room, 1, 5)
	_add_safe_sector_loops(plan, s1_rooms, blue_gate.next_room, green_gate.key_room if green_gate != null else Rect2i(), 1)

	if green_pocket.size != Vector2i.ZERO:
		plan._reserved_pockets.erase(green_pocket)
	if green_gate == null or target_max_depth <= 5:
		plan._reserved_pockets.clear()
		return

	var s2_dir: Vector2 = _face_to_vec(green_gate.door_face)
	var s2_rooms: Array[Rect2i] = plan._build_sector_rooms(green_gate.next_room, 2, target_max_depth, s2_dir)
	if target_max_depth <= 8:
		plan._reserved_pockets.clear()
		return

	var red_gate: SectorGate = null
	var red_pocket: Rect2i = Rect2i()
	if target_max_depth > 11 and yellow_gate != null:
		red_gate = _spawn_wing_forward_gate(plan, s2_rooms, green_gate.next_room, 2, WorldPlan.KeyColor.RED, 11, 4, s2_dir)
		if red_gate != null:
			red_pocket = _make_gate_pocket(red_gate.next_room, red_gate.door_face)
			plan._reserved_pockets.append(red_pocket)

	if yellow_gate != null:
		_finalize_wing_key_gate(plan, yellow_gate, s2_rooms, green_gate.next_room, 8)
	else:
		yellow_gate = build_sector_gate(plan, s2_rooms, green_gate.next_room, 2, 8)
	_add_safe_sector_loops(plan, s2_rooms, green_gate.next_room, yellow_gate.key_room if yellow_gate != null else Rect2i(), 2)

	if yellow_pocket.size != Vector2i.ZERO:
		plan._reserved_pockets.erase(yellow_pocket)
	if yellow_gate == null:
		plan._reserved_pockets.clear()
		return

	var s3_dir: Vector2 = _face_to_vec(yellow_gate.door_face)
	var s3_rooms: Array[Rect2i] = plan._build_sector_rooms(yellow_gate.next_room, 3, target_max_depth, s3_dir)
	if red_gate != null:
		_finalize_wing_key_gate(plan, red_gate, s3_rooms, yellow_gate.next_room, 11)
	elif target_max_depth > 11:
		red_gate = build_sector_gate(plan, s3_rooms, yellow_gate.next_room, 3, 11)
	_add_safe_sector_loops(plan, s3_rooms, yellow_gate.next_room, red_gate.key_room if red_gate != null else Rect2i(), 3)

	if red_pocket.size != Vector2i.ZERO:
		plan._reserved_pockets.erase(red_pocket)
	if red_gate == null or target_max_depth <= 11:
		plan._reserved_pockets.clear()
		return

	var s4_dir: Vector2 = _face_to_vec(red_gate.door_face)
	plan._build_sector_rooms(red_gate.next_room, 4, target_max_depth, s4_dir)
	plan._reserved_pockets.clear()


static func build_sector_gate(
	plan: WorldPlan,
	sector_rooms: Array[Rect2i],
	entry_room: Rect2i,
	sector_idx: int,
	current_depth: int,
) -> SectorGate:
	var gate_idx: int = GATE_DEPTHS.find(current_depth)
	if gate_idx < 0:
		return null

	var gate_color: WorldPlan.KeyColor = gate_idx as WorldPlan.KeyColor
	var bfs_rooms: Array[Rect2i] = sector_rooms.duplicate()
	if not bfs_rooms.has(entry_room):
		bfs_rooms.append(entry_room)
	var dist_from_entry: Dictionary[Rect2i, int] = _bfs_sector_distances(plan, entry_room, bfs_rooms)
	var candidates: Array[Dictionary] = _rank_gate_candidates(plan, sector_rooms, entry_room, dist_from_entry, Vector2.ZERO, Rect2i(), Vector2.ZERO)
	if candidates.is_empty():
		return null

	var gate: SectorGate = SectorGate.new()
	gate.color = gate_color
	gate.gate_depth = current_depth
	gate.key_sector = sector_idx

	var next_room: Rect2i = Rect2i()
	for cand: Dictionary in candidates:
		var cand_room: Rect2i = cand[&"room"]
		var cand_face: RoomLayout.Face = cand[&"face"]
		gate.gate_room = cand_room
		gate.door_face = cand_face
		next_room = _spawn_next_sector_room(plan, gate, cand_room, cand_face, current_depth + 1, sector_idx + 1)
		if next_room.size != Vector2i.ZERO:
			break
	if next_room.size == Vector2i.ZERO:
		return null
	gate.next_room = next_room
	_register_door_cells(plan, gate)

	var excluded: Array[Rect2i] = [gate.gate_room, entry_room, plan.hero_room]
	var dist_from_gate: Dictionary[Rect2i, int] = _bfs_sector_distances(plan, gate.gate_room, bfs_rooms)
	var key_room: Rect2i = _ensure_key_room(
		plan,
		gate.gate_room,
		entry_room,
		excluded,
		sector_rooms,
		bfs_rooms,
		dist_from_gate,
		dist_from_entry,
		sector_idx,
		current_depth,
	)
	gate.key_room = key_room
	gate.key_cell = ShortcutTunnelPlanner.find_safe_key_cell(plan, key_room, Vector2i(2147483647, 2147483647))
	_add_safe_sector_loops(plan, sector_rooms, gate.gate_room, key_room, sector_idx)
	plan.sector_gates.append(gate)
	_mark_no_prop_radius(plan, gate.key_cell, 2)
	return gate


static func _build_hub_pair_gates(
	plan: WorldPlan,
	hub_rooms: Array[Rect2i],
	entry_room: Rect2i,
	hub_sector: int,
) -> Dictionary:
	var bfs_rooms: Array[Rect2i] = hub_rooms.duplicate()
	if not bfs_rooms.has(entry_room):
		bfs_rooms.append(entry_room)
	var dist_from_entry: Dictionary[Rect2i, int] = _bfs_sector_distances(plan, entry_room, bfs_rooms)

	var primary_cands: Array[Dictionary] = _rank_gate_candidates(plan, hub_rooms, entry_room, dist_from_entry, Vector2.ZERO, Rect2i(), Vector2.ZERO)
	var primary_gate: SectorGate = SectorGate.new()
	primary_gate.color = WorldPlan.KeyColor.BLUE
	primary_gate.gate_depth = 2
	primary_gate.key_sector = hub_sector
	var p_next: Rect2i = Rect2i()
	for cand: Dictionary in primary_cands:
		var cand_room: Rect2i = cand[&"room"]
		var cand_face: RoomLayout.Face = cand[&"face"]
		primary_gate.gate_room = cand_room
		primary_gate.door_face = cand_face
		p_next = _spawn_next_sector_room(plan, primary_gate, cand_room, cand_face, 3, hub_sector + 1)
		if p_next.size != Vector2i.ZERO:
			break
	if p_next.size == Vector2i.ZERO:
		var extra_p: Dictionary = _spawn_extra_gate_host(plan, hub_rooms, Rect2i(), hub_sector, 2, Vector2.ZERO)
		if not extra_p.is_empty():
			var extra_p_host: Rect2i = extra_p[&"room"]
			var extra_p_face: RoomLayout.Face = extra_p[&"face"]
			hub_rooms.append(extra_p_host)
			bfs_rooms.append(extra_p_host)
			primary_gate.gate_room = extra_p_host
			primary_gate.door_face = extra_p_face
			p_next = _spawn_next_sector_room(plan, primary_gate, extra_p_host, extra_p_face, 3, hub_sector + 1)
	if p_next.size == Vector2i.ZERO:
		return {}
	primary_gate.next_room = p_next
	_register_door_cells(plan, primary_gate)

	var p_dir: Vector2 = _face_to_vec(primary_gate.door_face)
	var secondary_cands: Array[Dictionary] = _rank_gate_candidates(
		plan,
		hub_rooms,
		entry_room,
		dist_from_entry,
		-p_dir,
		primary_gate.gate_room,
		p_dir,
	)
	var secondary_gate: SectorGate = SectorGate.new()
	secondary_gate.color = WorldPlan.KeyColor.GREEN
	secondary_gate.gate_depth = 5
	secondary_gate.key_sector = hub_sector + 1
	var s_next: Rect2i = Rect2i()
	for cand: Dictionary in secondary_cands:
		var cand_room: Rect2i = cand[&"room"]
		if cand_room == primary_gate.gate_room:
			continue
		var cand_face: RoomLayout.Face = cand[&"face"]
		secondary_gate.gate_room = cand_room
		secondary_gate.door_face = cand_face
		s_next = _spawn_next_sector_room(plan, secondary_gate, cand_room, cand_face, 6, hub_sector + 2)
		if s_next.size != Vector2i.ZERO:
			break

	if s_next.size == Vector2i.ZERO:
		var extra_s: Dictionary = _spawn_extra_gate_host(plan, hub_rooms, primary_gate.gate_room, hub_sector, 2, -p_dir)
		if not extra_s.is_empty():
			var extra_s_host: Rect2i = extra_s[&"room"]
			var extra_s_face: RoomLayout.Face = extra_s[&"face"]
			hub_rooms.append(extra_s_host)
			bfs_rooms.append(extra_s_host)
			secondary_gate.gate_room = extra_s_host
			secondary_gate.door_face = extra_s_face
			s_next = _spawn_next_sector_room(plan, secondary_gate, extra_s_host, extra_s_face, 6, hub_sector + 2)

	if s_next.size != Vector2i.ZERO:
		secondary_gate.next_room = s_next
		_register_door_cells(plan, secondary_gate)
	else:
		secondary_gate = null

	var excluded_for_key: Array[Rect2i] = [entry_room, plan.hero_room, primary_gate.gate_room]
	if secondary_gate != null:
		excluded_for_key.append(secondary_gate.gate_room)
	dist_from_entry = _bfs_sector_distances(plan, entry_room, bfs_rooms)
	var dist_from_primary: Dictionary[Rect2i, int] = _bfs_sector_distances(plan, primary_gate.gate_room, bfs_rooms)
	var primary_key_room: Rect2i = _ensure_key_room(
		plan,
		primary_gate.gate_room,
		entry_room,
		excluded_for_key,
		hub_rooms,
		bfs_rooms,
		dist_from_primary,
		dist_from_entry,
		hub_sector,
		2,
	)
	primary_gate.key_room = primary_key_room
	primary_gate.key_cell = ShortcutTunnelPlanner.find_safe_key_cell(plan, primary_key_room, Vector2i(2147483647, 2147483647))
	_add_safe_sector_loops(plan, hub_rooms, primary_gate.gate_room, primary_key_room, hub_sector)
	plan.sector_gates.append(primary_gate)
	_mark_no_prop_radius(plan, primary_gate.key_cell, 2)

	return {&"primary_gate": primary_gate, &"secondary_gate": secondary_gate}


static func _spawn_wing_forward_gate(
	plan: WorldPlan,
	wing_rooms: Array[Rect2i],
	wing_entry: Rect2i,
	wing_sector: int,
	gate_color: WorldPlan.KeyColor,
	gate_depth: int,
	next_sector: int,
	prefer_dir: Vector2,
) -> SectorGate:
	var bfs_rooms: Array[Rect2i] = wing_rooms.duplicate()
	if not bfs_rooms.has(wing_entry):
		bfs_rooms.append(wing_entry)
	var dist_from_entry: Dictionary[Rect2i, int] = _bfs_sector_distances(plan, wing_entry, bfs_rooms)
	var candidates: Array[Dictionary] = _rank_gate_candidates(plan, wing_rooms, wing_entry, dist_from_entry, prefer_dir, Rect2i(), Vector2.ZERO)

	var gate: SectorGate = SectorGate.new()
	gate.color = gate_color
	gate.gate_depth = gate_depth
	gate.key_sector = wing_sector + 1

	var next_room: Rect2i = Rect2i()
	for cand: Dictionary in candidates:
		var cand_room: Rect2i = cand[&"room"]
		var cand_face: RoomLayout.Face = cand[&"face"]
		gate.gate_room = cand_room
		gate.door_face = cand_face
		next_room = _spawn_next_sector_room(plan, gate, cand_room, cand_face, gate_depth + 1, next_sector)
		if next_room.size != Vector2i.ZERO:
			break

	if next_room.size == Vector2i.ZERO:
		var extra: Dictionary = _spawn_extra_gate_host(plan, wing_rooms, Rect2i(), wing_sector, gate_depth, prefer_dir)
		if not extra.is_empty():
			var extra_host: Rect2i = extra[&"room"]
			var extra_face: RoomLayout.Face = extra[&"face"]
			wing_rooms.append(extra_host)
			gate.gate_room = extra_host
			gate.door_face = extra_face
			next_room = _spawn_next_sector_room(plan, gate, extra_host, extra_face, gate_depth + 1, next_sector)

	if next_room.size == Vector2i.ZERO:
		return null
	gate.next_room = next_room
	_register_door_cells(plan, gate)
	return gate


static func _finalize_wing_key_gate(
	plan: WorldPlan,
	gate: SectorGate,
	wing_rooms: Array[Rect2i],
	wing_entry: Rect2i,
	key_depth: int,
) -> void:
	var wing_sector: int = gate.key_sector
	var bfs_rooms: Array[Rect2i] = wing_rooms.duplicate()
	if not bfs_rooms.has(wing_entry):
		bfs_rooms.append(wing_entry)
	var dist_from_entry: Dictionary[Rect2i, int] = _bfs_sector_distances(plan, wing_entry, bfs_rooms)
	var excluded: Array[Rect2i] = [wing_entry, plan.hero_room, gate.gate_room]
	for other_gate: SectorGate in plan.sector_gates:
		if not excluded.has(other_gate.gate_room):
			excluded.append(other_gate.gate_room)
	for r: Rect2i in wing_rooms:
		if r != wing_entry and plan._room_sectors.get(r, -1) != wing_sector:
			excluded.append(r)

	var key_room: Rect2i = _ensure_key_room(
		plan,
		wing_entry,
		wing_entry,
		excluded,
		wing_rooms,
		bfs_rooms,
		dist_from_entry,
		dist_from_entry,
		wing_sector,
		key_depth,
	)
	gate.key_room = key_room
	gate.key_cell = ShortcutTunnelPlanner.find_safe_key_cell(plan, key_room, Vector2i(2147483647, 2147483647))
	plan.sector_gates.append(gate)
	_mark_no_prop_radius(plan, gate.key_cell, 2)


static func _spawn_extra_gate_host(
	plan: WorldPlan,
	sector_rooms: Array[Rect2i],
	exclude_room: Rect2i,
	sector_idx: int,
	target_depth: int,
	prefer_dir: Vector2,
) -> Dictionary:
	var base_angle: float = prefer_dir.angle() if prefer_dir != Vector2.ZERO else (-PI * 0.5)
	for r: Rect2i in sector_rooms:
		if r == exclude_room:
			continue
		for _attempt: int in range(20):
			var angle: float = base_angle + plan._rng.randf_range(-1.25, 1.25)
			var host: Rect2i = plan._try_place_maze_child(r, sector_idx, target_depth, angle)
			if host.size != Vector2i.ZERO:
				var best_face: RoomLayout.Face = _pick_best_face_for_room(plan, host, prefer_dir)
				if _has_clear_face_strip(plan, host, best_face, 8):
					return {&"room": host, &"face": best_face}
	return {}


static func verify_solvability(plan: WorldPlan) -> bool:
	return ShortcutTunnelPlanner.verify_solvability(plan)


static func _face_to_vec(face: RoomLayout.Face) -> Vector2:
	match face:
		RoomLayout.Face.NORTH:
			return Vector2.UP
		RoomLayout.Face.SOUTH:
			return Vector2.DOWN
		RoomLayout.Face.EAST:
			return Vector2.RIGHT
		_:
			return Vector2.LEFT


static func _make_gate_pocket(anchor_room: Rect2i, face: RoomLayout.Face) -> Rect2i:
	var center: Vector2i = anchor_room.get_center()
	var half: int = int(float(POCKET_SIZE) * 0.5)
	match face:
		RoomLayout.Face.NORTH:
			return Rect2i(center.x - half, anchor_room.position.y - POCKET_SIZE - 2, POCKET_SIZE, POCKET_SIZE)
		RoomLayout.Face.SOUTH:
			return Rect2i(center.x - half, anchor_room.end.y + 2, POCKET_SIZE, POCKET_SIZE)
		RoomLayout.Face.WEST:
			return Rect2i(anchor_room.position.x - POCKET_SIZE - 2, center.y - half, POCKET_SIZE, POCKET_SIZE)
		_:
			return Rect2i(anchor_room.end.x + 2, center.y - half, POCKET_SIZE, POCKET_SIZE)


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


static func _has_clear_face_strip(plan: WorldPlan, room: Rect2i, face: RoomLayout.Face, depth: int = 6) -> bool:
	var probe: Rect2i = _face_probe_rect(room, face, 8, depth, 0)
	if plan._is_outside_world_bounds(probe):
		return false
	if plan.spatial_grid.intersects_any(probe, plan.carve_rects, 0):
		return false
	if WorldPlan._intersects_any_rect(probe.grow(1), plan._reserved_pockets):
		return false
	return _is_face_socket_floor_ok(plan, room, face)


static func _has_clear_face_pocket(plan: WorldPlan, room: Rect2i, face: RoomLayout.Face, probe_dist: int) -> bool:
	if not _has_clear_face_strip(plan, room, face, 6):
		return false
	var probe_rect: Rect2i = _face_probe_rect(room, face, 32, probe_dist, 12)
	if plan._is_outside_world_bounds(probe_rect) or plan.hero_room.grow(4).intersects(probe_rect):
		return false
	if plan._room_grid.intersects_any(probe_rect, plan.rooms, 4):
		return false
	if WorldPlan._intersects_any_rect(probe_rect.grow(1), plan._reserved_pockets):
		return false
	return not WorldPlan._intersects_any_rect(probe_rect.grow(2), plan._corridor_rects)


static func _face_probe_rect(room: Rect2i, face: RoomLayout.Face, span: int, depth: int, gap: int) -> Rect2i:
	var c: Vector2i = room.get_center()
	var half_span: int = int(float(span) * 0.5)
	match face:
		RoomLayout.Face.NORTH:
			return Rect2i(c.x - half_span, room.position.y - gap - depth, span, depth)
		RoomLayout.Face.SOUTH:
			return Rect2i(c.x - half_span, room.end.y + gap, span, depth)
		RoomLayout.Face.WEST:
			return Rect2i(room.position.x - gap - depth, c.y - half_span, depth, span)
		_:
			return Rect2i(room.end.x + gap, c.y - half_span, depth, span)


static func _is_face_socket_floor_ok(plan: WorldPlan, room: Rect2i, face: RoomLayout.Face) -> bool:
	var c: Vector2i = room.get_center()
	var check_rect: Rect2i = Rect2i()
	match face:
		RoomLayout.Face.NORTH:
			check_rect = Rect2i(c.x - 2, room.position.y, 4, 2)
		RoomLayout.Face.SOUTH:
			check_rect = Rect2i(c.x - 2, room.end.y - 2, 4, 2)
		RoomLayout.Face.WEST:
			check_rect = Rect2i(room.position.x, c.y - 2, 2, 4)
		_:
			check_rect = Rect2i(room.end.x - 2, c.y - 2, 2, 4)
	for cy: int in range(check_rect.position.y, check_rect.end.y):
		for cx: int in range(check_rect.position.x, check_rect.end.x):
			if not plan.is_floor(Vector2i(cx, cy)):
				return false
	return true


static func _pick_best_face_for_room(plan: WorldPlan, room: Rect2i, prefer_dir: Vector2) -> RoomLayout.Face:
	var best_face: RoomLayout.Face = RoomLayout.Face.NORTH
	var best_score: float = -INF
	for face: RoomLayout.Face in ALL_FACES:
		var score: float = 0.0
		if _has_clear_face_pocket(plan, room, face, 36):
			score += 1000.0
		elif _has_clear_face_pocket(plan, room, face, 20):
			score += 500.0
		elif _has_clear_face_strip(plan, room, face, 6):
			score += 100.0
		if prefer_dir != Vector2.ZERO:
			score += _face_to_vec(face).dot(prefer_dir) * 80.0
		if score > best_score:
			best_score = score
			best_face = face
	return best_face


static func _rank_gate_candidates(
	plan: WorldPlan,
	sector_rooms: Array[Rect2i],
	entry_room: Rect2i,
	dist_from_entry: Dictionary[Rect2i, int],
	prefer_dir: Vector2,
	other_gate_room: Rect2i,
	avoid_dir: Vector2,
) -> Array[Dictionary]:
	var scored: Array[Dictionary] = []
	for r: Rect2i in sector_rooms:
		if r == entry_room or r == plan.hero_room:
			continue
		for face: RoomLayout.Face in ALL_FACES:
			var tier_penalty: int = 9000
			if _has_clear_face_pocket(plan, r, face, 40):
				tier_penalty = 0
			elif _has_clear_face_pocket(plan, r, face, 22):
				tier_penalty = 600
			elif _has_clear_face_strip(plan, r, face, 6):
				tier_penalty = 2000

			var f_vec: Vector2 = _face_to_vec(face)
			var s: int = tier_penalty
			s -= 180 if dist_from_entry.get(r, 0) >= 2 else 0
			s -= 140 if _get_sector_degree(plan, r, sector_rooms) <= 1 else 0
			if prefer_dir != Vector2.ZERO:
				s -= int(roundf(f_vec.dot(prefer_dir) * 260.0))
			if avoid_dir != Vector2.ZERO and f_vec.dot(avoid_dir) > 0.4:
				s += 600
			if other_gate_room.size != Vector2i.ZERO:
				var dist_other: float = Vector2(r.get_center()).distance_to(Vector2(other_gate_room.get_center()))
				if dist_other < 40.0:
					s += 2500
			scored.append({&"room": r, &"face": face, &"score": s})

	scored.sort_custom(_compare_scored_room_asc)
	return scored


static func _compare_scored_room_asc(a: Dictionary, b: Dictionary) -> bool:
	var sa: int = a[&"score"]
	var sb: int = b[&"score"]
	return sa < sb


static func _ensure_key_room(
	plan: WorldPlan,
	origin_room: Rect2i,
	entry_room: Rect2i,
	excluded_rooms: Array[Rect2i],
	sector_rooms: Array[Rect2i],
	bfs_rooms: Array[Rect2i],
	dist_from_origin: Dictionary[Rect2i, int],
	dist_from_entry: Dictionary[Rect2i, int],
	sector_idx: int,
	current_depth: int,
) -> Rect2i:
	var valid: Array[Rect2i] = _collect_valid_key_candidates(excluded_rooms, sector_rooms)
	var max_dist: int = _max_candidate_dist(valid, dist_from_origin)

	for step: int in range(MAX_KEY_EXTEND_STEPS + 1):
		if not valid.is_empty() and (step >= MAX_KEY_EXTEND_STEPS or max_dist >= MIN_KEY_HOPS):
			break
		var ext: Rect2i = _spawn_key_wing_extension(plan, origin_room, sector_rooms, dist_from_origin, sector_idx, current_depth)
		if ext.size == Vector2i.ZERO:
			break
		sector_rooms.append(ext)
		bfs_rooms.append(ext)
		dist_from_origin = _bfs_sector_distances(plan, origin_room, bfs_rooms)
		dist_from_entry = _bfs_sector_distances(plan, entry_room, bfs_rooms)
		valid = _collect_valid_key_candidates(excluded_rooms, sector_rooms)
		max_dist = _max_candidate_dist(valid, dist_from_origin)

	if valid.is_empty():
		for r: Rect2i in sector_rooms:
			if not excluded_rooms.has(r):
				valid.append(r)
		if valid.is_empty():
			return origin_room

	return _pick_best_key_room(plan, origin_room, sector_rooms, valid, dist_from_origin, dist_from_entry)


static func _collect_valid_key_candidates(
	excluded_rooms: Array[Rect2i],
	sector_rooms: Array[Rect2i],
) -> Array[Rect2i]:
	var valid: Array[Rect2i] = []
	for r: Rect2i in sector_rooms:
		if not excluded_rooms.has(r):
			valid.append(r)
	return valid


static func _max_candidate_dist(candidates: Array[Rect2i], dist_from_origin: Dictionary[Rect2i, int]) -> int:
	var best: int = -1
	for r: Rect2i in candidates:
		var d: int = dist_from_origin.get(r, -1)
		if d > best:
			best = d
	return best


static func _pick_best_key_room(
	plan: WorldPlan,
	origin_room: Rect2i,
	sector_rooms: Array[Rect2i],
	candidates: Array[Rect2i],
	dist_from_origin: Dictionary[Rect2i, int],
	dist_from_entry: Dictionary[Rect2i, int],
) -> Rect2i:
	var origin_center: Vector2i = origin_room.get_center()
	var best: Rect2i = candidates[0]
	var best_score: int = -999999999

	for r: Rect2i in candidates:
		var hop_dist: int = dist_from_origin.get(r, 1)
		var reach_bonus: int = 3000 if hop_dist >= MIN_KEY_HOPS else 0
		var hop_score: int = mini(hop_dist, 6) * 700
		var leaf_bonus: int = 600 if _get_sector_degree(plan, r, sector_rooms) <= 1 else 0
		var entry_sep: int = 200 if dist_from_entry.get(r, 0) >= 2 else 0
		var euclid_dist: int = int(roundf(Vector2(r.get_center()).distance_to(Vector2(origin_center))))
		var score: int = reach_bonus + hop_score + leaf_bonus + entry_sep - euclid_dist * 4
		if score > best_score:
			best_score = score
			best = r
	return best


static func _spawn_key_wing_extension(
	plan: WorldPlan,
	origin_room: Rect2i,
	sector_rooms: Array[Rect2i],
	dist_from_origin: Dictionary[Rect2i, int],
	sector_idx: int,
	target_depth: int,
) -> Rect2i:
	var tried: Dictionary[Rect2i, bool] = {}
	var origin_center: Vector2 = Vector2(origin_room.get_center())

	for _pick: int in range(sector_rooms.size()):
		var best_p: Rect2i = Rect2i()
		var best_score: int = -999999
		for r: Rect2i in sector_rooms:
			if r == origin_room or tried.has(r) or not dist_from_origin.has(r):
				continue
			var s: int = dist_from_origin[r] * 10 - _get_sector_degree(plan, r, sector_rooms)
			if s > best_score:
				best_score = s
				best_p = r
		if best_p.size == Vector2i.ZERO:
			break
		tried[best_p] = true
		var away_dir: Vector2 = Vector2(best_p.get_center()) - origin_center
		var away_angle: float = away_dir.angle() if away_dir.length_squared() > 1.0 else (-PI * 0.5)
		for attempt: int in range(28):
			var spread: float = 0.85 if attempt < 16 else 1.85
			var angle: float = away_angle + plan._rng.randf_range(-spread, spread)
			var wing: Rect2i = plan._try_place_maze_child(best_p, sector_idx, target_depth, angle)
			if wing.size != Vector2i.ZERO:
				return wing
	return Rect2i()


static func _add_safe_sector_loops(
	plan: WorldPlan,
	sector_rooms: Array[Rect2i],
	origin_room: Rect2i,
	key_room: Rect2i,
	sector_idx: int,
) -> void:
	if WorldPlan.MAX_LOOPS_PER_SECTOR <= 0:
		return
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

	var dist_from_origin: Dictionary[Rect2i, int] = _bfs_sector_distances(plan, origin_room, sector_rooms)
	var dist_from_key: Dictionary[Rect2i, int] = _bfs_sector_distances(plan, key_room, sector_rooms) if key_room.size != Vector2i.ZERO else {}
	var added: int = 0

	for pair: Array in pairs:
		if added >= WorldPlan.MAX_LOOPS_PER_SECTOR:
			break
		var room_a: Rect2i = pair[0]
		var room_b: Rect2i = pair[1]
		if key_room.size != Vector2i.ZERO:
			var path_a: int = dist_from_key.get(room_a, 999) + 1 + dist_from_origin.get(room_b, 999)
			var path_b: int = dist_from_key.get(room_b, 999) + 1 + dist_from_origin.get(room_a, 999)
			if mini(path_a, path_b) < MIN_KEY_HOPS:
				continue
		var segs: Array[Dictionary] = RoomLayout.plan_corridor(plan, room_a, room_b, [], sector_idx, true)
		if segs.is_empty():
			continue
		RoomLayout.commit_corridor(plan, segs, sector_idx)
		plan._add_neighbor_edge(room_a, room_b)
		added += 1
		dist_from_origin = _bfs_sector_distances(plan, origin_room, sector_rooms)
		if key_room.size != Vector2i.ZERO:
			dist_from_key = _bfs_sector_distances(plan, key_room, sector_rooms)


static func _spawn_next_sector_room(
	plan: WorldPlan,
	gate: SectorGate,
	gate_room: Rect2i,
	face: RoomLayout.Face,
	next_depth: int,
	next_sector: int,
) -> Rect2i:
	if face == RoomLayout.Face.NORTH or face == RoomLayout.Face.SOUTH:
		return _spawn_ns_sector_room(plan, gate, gate_room, face == RoomLayout.Face.NORTH, next_depth, next_sector)
	return _spawn_ew_sector_room(plan, gate, gate_room, face == RoomLayout.Face.WEST, next_depth, next_sector)


static func _spawn_ns_sector_room(
	plan: WorldPlan,
	gate: SectorGate,
	gate_room: Rect2i,
	is_north: bool,
	next_depth: int,
	next_sector: int,
) -> Rect2i:
	var min_dx: int = gate_room.position.x + 3
	var max_dx: int = gate_room.end.x - 5
	if min_dx > max_dx:
		return Rect2i()

	var center_dx: int = clampi(gate_room.get_center().x - 1, min_dx, max_dx)
	var dx_offsets: Array[int] = [0, -3, 3, -6, 6]
	var gaps: Array[int] = [8, 10, 14, 18, 24]
	var lat_shifts: Array[int] = [0, -4, 4, -8, 8]

	for gap: int in gaps:
		for dx_off: int in dx_offsets:
			var door_x: int = clampi(center_dx + dx_off, min_dx, max_dx)
			var door_y: int = (gate_room.position.y - floori(float(gap) * 0.5)) if is_north else (gate_room.end.y + floori(float(gap) * 0.5))
			var neck_y: int = (gate_room.position.y - gap - 2) if is_north else (gate_room.end.y - 2)
			var neck: Rect2i = Rect2i(door_x, neck_y, 2, gap + 4)
			var gap_rect: Rect2i = Rect2i(door_x, neck_y + 2, 2, gap)

			var size: Vector2i = RoomLayout.roll_room_size(plan._rng, next_depth)
			for lat: int in lat_shifts:
				var top_x: int = clampi(door_x + 1 - int(float(size.x) * 0.5) + lat, door_x - size.x + 5, door_x - 3)
				var top_y: int = (gate_room.position.y - gap - size.y) if is_north else (gate_room.end.y + gap)
				var candidate: Rect2i = Rect2i(top_x, top_y, size.x, size.y)
				if not _is_sector_candidate_clear(plan, gate_room, candidate, neck, gap_rect):
					continue
				var dest_sock: Rect2i = Rect2i(door_x - 1, candidate.end.y - 2, 4, 2) if is_north else Rect2i(door_x - 1, candidate.position.y, 4, 2)
				var src_sock: Rect2i = Rect2i(door_x - 1, gate_room.position.y, 4, 2) if is_north else Rect2i(door_x - 1, gate_room.end.y - 2, 4, 2)
				if not _is_socket_tiles_clear(plan, src_sock):
					continue

				var shape_cutouts: Dictionary = _pick_clear_room_shape(plan, candidate, dest_sock)
				gate.door_cells = [Vector2i(door_x, door_y), Vector2i(door_x + 1, door_y)]
				_commit_sector_room_and_neck(plan, gate, gate_room, candidate, neck, shape_cutouts, next_depth, next_sector, true)
				return candidate
	return Rect2i()


static func _spawn_ew_sector_room(
	plan: WorldPlan,
	gate: SectorGate,
	gate_room: Rect2i,
	is_west: bool,
	next_depth: int,
	next_sector: int,
) -> Rect2i:
	var min_y0: int = gate_room.position.y + 4
	var max_y0: int = gate_room.end.y - 7
	if min_y0 > max_y0:
		return Rect2i()

	var center_y0: int = clampi(gate_room.get_center().y - 1, min_y0, max_y0)
	var y_offsets: Array[int] = [0, -3, 3, -6, 6]
	var gaps: Array[int] = [8, 10, 14, 18, 24]
	var vert_shifts: Array[int] = [0, -4, 4, -8, 8]

	for gap: int in gaps:
		for y_off: int in y_offsets:
			var y0: int = clampi(center_y0 + y_off, min_y0, max_y0)
			var door_x: int = (gate_room.position.x - floori(float(gap) * 0.5)) if is_west else (gate_room.end.x + floori(float(gap) * 0.5))
			var neck_x: int = (gate_room.position.x - gap - 2) if is_west else (gate_room.end.x - 2)
			var neck: Rect2i = Rect2i(neck_x, y0, gap + 4, 3)
			var gap_rect: Rect2i = Rect2i(neck_x + 2, y0, gap, 3)

			var size: Vector2i = RoomLayout.roll_room_size(plan._rng, next_depth)
			for v_shift: int in vert_shifts:
				var top_y: int = clampi(y0 + 1 - int(float(size.y) * 0.5) + v_shift, y0 - size.y + 7, y0 - 4)
				var top_x: int = (gate_room.position.x - gap - size.x) if is_west else (gate_room.end.x + gap)
				var candidate: Rect2i = Rect2i(top_x, top_y, size.x, size.y)
				if not _is_sector_candidate_clear(plan, gate_room, candidate, neck, gap_rect):
					continue
				var dest_sock: Rect2i = Rect2i(candidate.end.x - 2, y0 - 1, 2, 5) if is_west else Rect2i(candidate.position.x, y0 - 1, 2, 5)
				var src_sock: Rect2i = Rect2i(gate_room.position.x, y0 - 1, 2, 5) if is_west else Rect2i(gate_room.end.x - 2, y0 - 1, 2, 5)
				if not _is_socket_tiles_clear(plan, src_sock):
					continue

				var shape_cutouts: Dictionary = _pick_clear_room_shape(plan, candidate, dest_sock)
				gate.door_cells = [Vector2i(door_x, y0 + 1), Vector2i(door_x, y0 + 2)]
				_commit_sector_room_and_neck(plan, gate, gate_room, candidate, neck, shape_cutouts, next_depth, next_sector, false)
				return candidate
	return Rect2i()


static func _is_sector_candidate_clear(
	plan: WorldPlan,
	gate_room: Rect2i,
	candidate: Rect2i,
	neck: Rect2i,
	gap_rect: Rect2i,
) -> bool:
	if plan._is_outside_world_bounds(candidate) or plan._is_outside_world_bounds(neck):
		return false
	if plan._overlaps_any_room(candidate) or WorldPlan._intersects_any_rect(candidate.grow(2), plan._reserved_pockets):
		return false
	if WorldPlan._intersects_any_rect(neck.grow(1), plan.protected_neck_rects):
		return false
	if WorldPlan._intersects_any_rect(neck.grow(1), plan._reserved_pockets):
		return false
	if WorldPlan._intersects_any_rect(neck.grow(2), plan._corridor_rects):
		return false
	var padded_gap: Rect2i = gap_rect.grow(3)
	if plan.hero_room != gate_room and plan.hero_room.intersects(padded_gap):
		return false
	for r_id: int in plan._room_grid.get_candidate_ids_for_rect(padded_gap):
		if r_id >= 0 and r_id < plan.rooms.size():
			var other: Rect2i = plan.rooms[r_id]
			if other != gate_room and other.intersects(padded_gap):
				return false
	return true


static func _is_socket_tiles_clear(plan: WorldPlan, sock: Rect2i) -> bool:
	if WorldPlan._intersects_any_rect(sock.grow(1), plan._all_pillars):
		return false
	for cy: int in range(sock.position.y, sock.end.y):
		for cx: int in range(sock.position.x, sock.end.x):
			var cell: Vector2i = Vector2i(cx, cy)
			if not plan.is_floor(cell) or plan.no_prop_cells.has(cell) or plan.door_cell_codes.has(cell):
				return false
	return true


static func _pick_clear_room_shape(plan: WorldPlan, candidate: Rect2i, dest_sock: Rect2i) -> Dictionary:
	var shape: WorldPlan.RoomShape = RoomLayout.pick_room_shape(plan._rng, candidate.size)
	var cutouts: Array[Rect2i] = RoomLayout.build_room_cutouts(plan._rng, candidate, shape)
	if WorldPlan._intersects_any_rect(dest_sock, cutouts):
		return {&"shape": WorldPlan.RoomShape.RECTANGLE, &"cutouts": [] as Array[Rect2i]}
	if shape == WorldPlan.RoomShape.PILLARED:
		var pillars: Array[Rect2i] = RoomLayout._build_pillars_for_room(candidate)
		if WorldPlan._intersects_any_rect(dest_sock.grow(1), pillars):
			return {&"shape": WorldPlan.RoomShape.RECTANGLE, &"cutouts": [] as Array[Rect2i]}
	return {&"shape": shape, &"cutouts": cutouts}


static func _commit_sector_room_and_neck(
	plan: WorldPlan,
	gate: SectorGate,
	gate_room: Rect2i,
	candidate: Rect2i,
	neck: Rect2i,
	shape_cutouts: Dictionary,
	next_depth: int,
	next_sector: int,
	is_ns: bool,
) -> void:
	plan._add_carve_rect(neck, next_sector)
	plan._corridor_rects.append(neck)
	plan._corridor_sectors.append(next_sector)
	plan.protected_neck_rects.append(neck.grow(1))
	var seg_def: Dictionary = {
		&"is_horizontal": not is_ns,
		&"min": neck.position.y if is_ns else neck.position.x,
		&"max": (neck.end.y - 1) if is_ns else (neck.end.x - 1),
		&"fixed": neck.position.x if is_ns else (neck.position.y + 1),
		&"half_width": 1,
	}
	plan._corridor_segments.append(seg_def)
	if not plan.room_children.has(gate_room):
		plan.room_children[gate_room] = []
	plan.room_children[gate_room].append(candidate)
	plan._add_neighbor_edge(gate_room, candidate)
	var shape: WorldPlan.RoomShape = shape_cutouts[&"shape"]
	var cutouts: Array[Rect2i] = shape_cutouts[&"cutouts"]
	plan._add_room_with_layout(candidate, next_depth, next_sector, shape, cutouts)
	if gate.door_cells.size() >= 2:
		_mark_no_prop_radius(plan, gate.door_cells[0], 2)
		_mark_no_prop_radius(plan, gate.door_cells[1], 2)


static func _register_door_cells(plan: WorldPlan, gate: SectorGate) -> void:
	var is_vert: bool = gate.door_face == RoomLayout.Face.EAST or gate.door_face == RoomLayout.Face.WEST
	var code_offset: int = TileClassifier.DOOR_CODE_VERT_OFFSET if is_vert else 0
	for i: int in range(gate.door_cells.size()):
		plan.door_cell_codes[gate.door_cells[i]] = code_offset + int(gate.color) * 2 + i
		_mark_no_prop_radius(plan, gate.door_cells[i], 2)


static func _mark_no_prop_radius(plan: WorldPlan, center: Vector2i, radius: int) -> void:
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			plan.no_prop_cells[center + Vector2i(dx, dy)] = true


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
