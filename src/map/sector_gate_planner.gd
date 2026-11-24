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
	var tunnel_chunk_diffs: Dictionary[Vector2i, Dictionary] = {}
	var opened_map_chunk_coords: Array[Vector2i] = []
	var opened_map_floors: Dictionary[Vector2i, PackedVector2Array] = {}
	var opened_map_walls: Dictionary[Vector2i, PackedVector2Array] = {}
	var door_unlocked: bool = false
	var shortcut_opened: bool = false
	var has_key: bool = true
	var has_shortcut: bool = true
	var key_sector: int = 0
	var shortcut_target_room: Rect2i = Rect2i()


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


static func generate_dungeon_sectors(plan: WorldPlan, target_max_depth: int) -> void:
	var s0_rooms: Array[Rect2i] = plan._build_sector_rooms(plan.hero_room, 0, target_max_depth, 0, 0)
	if target_max_depth <= 2:
		return

	var side_sign_0: int = -1 if plan._rng.randf() < 0.5 else 1
	var blue_gate: SectorGate = null
	var green_gate: SectorGate = null
	if target_max_depth > 5:
		var hub0: Dictionary = _build_hub_pair_gates(
			plan,
			s0_rooms,
			plan.hero_room,
			0,
			WorldPlan.KeyColor.BLUE,
			2,
			WorldPlan.KeyColor.GREEN,
			5,
			side_sign_0,
		)
		blue_gate = hub0.get(&"primary_gate", null)
		green_gate = hub0.get(&"secondary_gate", null)
	else:
		blue_gate = build_sector_gate(plan, s0_rooms, plan.hero_room, 0, 2)

	if blue_gate == null:
		return

	var lane_a_side: int = 0
	var lane_b_side: int = 0
	var lane_a_bound: int = 0
	var lane_b_bound: int = 0
	if green_gate != null:
		lane_a_side = -1 if blue_gate.next_room.get_center().x <= green_gate.next_room.get_center().x else 1
		lane_b_side = -lane_a_side
		lane_a_bound = (green_gate.next_room.position.x - 8) if lane_a_side < 0 else (green_gate.next_room.end.x + 8)
		if lane_a_side < 0:
			lane_a_bound = maxi(lane_a_bound, blue_gate.next_room.end.x + 4)
		else:
			lane_a_bound = mini(lane_a_bound, blue_gate.next_room.position.x - 4)
		lane_b_bound = (blue_gate.next_room.end.x + 8) if lane_b_side > 0 else (blue_gate.next_room.position.x - 8)
		if lane_b_side > 0:
			lane_b_bound = mini(lane_b_bound, green_gate.next_room.position.x - 4)
		else:
			lane_b_bound = maxi(lane_b_bound, green_gate.next_room.end.x + 4)
		plan._sector_x_bound_side = lane_a_side
		plan._sector_x_bound_val = lane_a_bound

	var s1_rooms: Array[Rect2i] = plan._build_sector_rooms(blue_gate.next_room, 1, target_max_depth, lane_a_side, lane_a_bound)
	var yellow_gate: SectorGate = null
	if target_max_depth > 8 and green_gate != null:
		yellow_gate = _spawn_wing_forward_gate(plan, s1_rooms, blue_gate.next_room, 1, WorldPlan.KeyColor.YELLOW, 8, 3, lane_a_side)

	if green_gate != null:
		var s1_reserved: Array[Rect2i] = [_make_reserved_sky_rect(green_gate.next_room, lane_a_side)]
		if yellow_gate != null:
			s1_reserved.append(_make_reserved_sky_rect(yellow_gate.next_room, 0))
		var s1_extra_excl: Rect2i = yellow_gate.gate_room if yellow_gate != null else Rect2i()
		_finalize_wing_key_gate(plan, green_gate, s1_rooms, blue_gate.next_room, [0, 1], 5, blue_gate.gate_room, s1_reserved, s1_extra_excl)
	elif target_max_depth > 5:
		green_gate = build_sector_gate(plan, s1_rooms, blue_gate.next_room, 1, 5)

	plan._sector_x_bound_side = 0
	plan._sector_x_bound_val = 0
	if green_gate == null or target_max_depth <= 5:
		return

	if lane_b_side != 0:
		plan._sector_x_bound_side = lane_b_side
		plan._sector_x_bound_val = lane_b_bound
	var s2_rooms: Array[Rect2i] = plan._build_sector_rooms(green_gate.next_room, 2, target_max_depth, lane_b_side, lane_b_bound)
	if target_max_depth <= 8:
		plan._sector_x_bound_side = 0
		plan._sector_x_bound_val = 0
		return

	var red_gate: SectorGate = null
	if target_max_depth > 11 and yellow_gate != null:
		red_gate = _spawn_wing_forward_gate(plan, s2_rooms, green_gate.next_room, 2, WorldPlan.KeyColor.RED, 11, 4, lane_b_side)

	if yellow_gate != null:
		var s2_reserved: Array[Rect2i] = [_make_reserved_sky_rect(yellow_gate.next_room, lane_b_side)]
		if red_gate != null:
			s2_reserved.append(_make_reserved_sky_rect(red_gate.next_room, 0))
		var s2_extra_excl: Rect2i = red_gate.gate_room if red_gate != null else Rect2i()
		_finalize_wing_key_gate(plan, yellow_gate, s2_rooms, green_gate.next_room, [0, 1, 2], 8, green_gate.gate_room, s2_reserved, s2_extra_excl)
	else:
		yellow_gate = build_sector_gate(plan, s2_rooms, green_gate.next_room, 2, 8)

	plan._sector_x_bound_side = 0
	plan._sector_x_bound_val = 0
	if yellow_gate == null:
		return

	if red_gate != null and lane_a_side != 0:
		plan._sector_x_bound_side = lane_a_side
		plan._sector_x_bound_val = lane_a_bound
	var s3_rooms: Array[Rect2i] = plan._build_sector_rooms(yellow_gate.next_room, 3, target_max_depth, lane_a_side, lane_a_bound)
	if red_gate != null:
		var s3_reserved: Array[Rect2i] = [_make_reserved_sky_rect(red_gate.next_room, lane_a_side)]
		_finalize_wing_key_gate(plan, red_gate, s3_rooms, yellow_gate.next_room, [0, 1, 2, 3], 11, yellow_gate.gate_room, s3_reserved)
	elif target_max_depth > 11:
		red_gate = build_sector_gate(plan, s3_rooms, yellow_gate.next_room, 3, 11)

	plan._sector_x_bound_side = 0
	plan._sector_x_bound_val = 0
	if red_gate == null or target_max_depth <= 11:
		return

	if lane_b_side != 0:
		plan._sector_x_bound_side = lane_b_side
		plan._sector_x_bound_val = lane_b_bound
	plan._build_sector_rooms(red_gate.next_room, 4, target_max_depth, lane_b_side, lane_b_bound)
	plan._sector_x_bound_side = 0
	plan._sector_x_bound_val = 0


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
	var candidates: Array[Rect2i] = _rank_gate_candidates(plan, sector_rooms, entry_room, dist_from_entry, 0, 0, false)
	if candidates.is_empty():
		return null

	var gate: SectorGate = SectorGate.new()
	gate.color = gate_color
	gate.gate_depth = current_depth
	gate.key_sector = sector_idx

	var next_room: Rect2i = Rect2i()
	for cand: Rect2i in candidates:
		gate.gate_room = cand
		next_room = _spawn_next_sector_room(plan, gate, cand, current_depth + 1, sector_idx + 1)
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

	var allowed_sectors: Array[int] = [sector_idx]
	var reserved: Array[Rect2i] = [_make_reserved_sky_rect(next_room, 0)]
	ShortcutTunnelPlanner.setup_shortcut_and_key(plan, gate, key_room, gate.gate_room, allowed_sectors, reserved)
	_add_safe_sector_loops(plan, gate, sector_rooms, bfs_rooms, gate.gate_room, key_room, sector_idx, reserved)
	if gate.has_shortcut and key_room != gate.shortcut_target_room:
		plan._add_neighbor_edge(key_room, gate.shortcut_target_room)
	plan.sector_gates.append(gate)
	_register_key_and_shortcut_tiles(plan, gate)
	return gate


static func _build_hub_pair_gates(
	plan: WorldPlan,
	hub_rooms: Array[Rect2i],
	entry_room: Rect2i,
	hub_sector: int,
	primary_color: WorldPlan.KeyColor,
	primary_depth: int,
	secondary_color: WorldPlan.KeyColor,
	secondary_depth: int,
	side_sign: int,
) -> Dictionary:
	var bfs_rooms: Array[Rect2i] = hub_rooms.duplicate()
	if not bfs_rooms.has(entry_room):
		bfs_rooms.append(entry_room)
	var dist_from_entry: Dictionary[Rect2i, int] = _bfs_sector_distances(plan, entry_room, bfs_rooms)

	var primary_cands: Array[Rect2i] = _rank_gate_candidates(plan, hub_rooms, entry_room, dist_from_entry, side_sign, 0, false)
	var primary_gate: SectorGate = SectorGate.new()
	primary_gate.color = primary_color
	primary_gate.gate_depth = primary_depth
	primary_gate.key_sector = hub_sector
	var p_next: Rect2i = Rect2i()
	for cand: Rect2i in primary_cands:
		primary_gate.gate_room = cand
		p_next = _spawn_next_sector_room(plan, primary_gate, cand, primary_depth + 1, hub_sector + 1)
		if p_next.size != Vector2i.ZERO:
			break
	if p_next.size == Vector2i.ZERO:
		var extra_p_host: Rect2i = _spawn_extra_hub_gate_host(plan, hub_rooms, entry_room, Rect2i(), hub_sector, primary_depth, side_sign)
		if extra_p_host.size != Vector2i.ZERO:
			hub_rooms.append(extra_p_host)
			bfs_rooms.append(extra_p_host)
			primary_gate.gate_room = extra_p_host
			p_next = _spawn_next_sector_room(plan, primary_gate, extra_p_host, primary_depth + 1, hub_sector + 1)
	if p_next.size == Vector2i.ZERO:
		return {}
	primary_gate.next_room = p_next
	_register_door_cells(plan, primary_gate)

	var p_x: int = primary_gate.gate_room.get_center().x
	var secondary_cands: Array[Rect2i] = _rank_gate_candidates(plan, hub_rooms, entry_room, dist_from_entry, -side_sign, p_x, true)
	var secondary_gate: SectorGate = SectorGate.new()
	secondary_gate.color = secondary_color
	secondary_gate.gate_depth = secondary_depth
	secondary_gate.key_sector = hub_sector + 1
	var s_next: Rect2i = Rect2i()
	for cand: Rect2i in secondary_cands:
		if cand == primary_gate.gate_room:
			continue
		secondary_gate.gate_room = cand
		s_next = _spawn_next_sector_room(plan, secondary_gate, cand, secondary_depth + 1, hub_sector + 2)
		if s_next.size != Vector2i.ZERO:
			break

	if s_next.size == Vector2i.ZERO:
		for extra_sign: int in [-side_sign, side_sign]:
			var extra_host: Rect2i = _spawn_extra_hub_gate_host(
				plan, hub_rooms, entry_room, primary_gate.gate_room, hub_sector, primary_depth, extra_sign
			)
			if extra_host.size != Vector2i.ZERO:
				hub_rooms.append(extra_host)
				bfs_rooms.append(extra_host)
				secondary_gate.gate_room = extra_host
				s_next = _spawn_next_sector_room(plan, secondary_gate, extra_host, secondary_depth + 1, hub_sector + 2)
				if s_next.size != Vector2i.ZERO:
					break

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
		primary_depth,
	)
	primary_gate.key_room = primary_key_room

	var reserved: Array[Rect2i] = [_make_reserved_sky_rect(primary_gate.next_room, 0)]
	if secondary_gate != null:
		reserved.append(_make_reserved_sky_rect(secondary_gate.next_room, 0))

	var allowed_sectors: Array[int] = [hub_sector]
	ShortcutTunnelPlanner.setup_shortcut_and_key(plan, primary_gate, primary_key_room, primary_gate.gate_room, allowed_sectors, reserved)
	_add_safe_sector_loops(plan, primary_gate, hub_rooms, bfs_rooms, primary_gate.gate_room, primary_key_room, hub_sector, reserved)
	if primary_gate.has_shortcut and primary_key_room != primary_gate.shortcut_target_room:
		plan._add_neighbor_edge(primary_key_room, primary_gate.shortcut_target_room)
	plan.sector_gates.append(primary_gate)
	_register_key_and_shortcut_tiles(plan, primary_gate)

	return {&"primary_gate": primary_gate, &"secondary_gate": secondary_gate}


static func _spawn_wing_forward_gate(
	plan: WorldPlan,
	wing_rooms: Array[Rect2i],
	wing_entry: Rect2i,
	wing_sector: int,
	gate_color: WorldPlan.KeyColor,
	gate_depth: int,
	next_sector: int,
	lane_side: int,
) -> SectorGate:
	var bfs_rooms: Array[Rect2i] = wing_rooms.duplicate()
	if not bfs_rooms.has(wing_entry):
		bfs_rooms.append(wing_entry)
	var dist_from_entry: Dictionary[Rect2i, int] = _bfs_sector_distances(plan, wing_entry, bfs_rooms)
	var candidates: Array[Rect2i] = _rank_gate_candidates(plan, wing_rooms, wing_entry, dist_from_entry, 0, 0, false)

	var gate: SectorGate = SectorGate.new()
	gate.color = gate_color
	gate.gate_depth = gate_depth
	gate.key_sector = wing_sector + 1

	var next_room: Rect2i = Rect2i()
	for cand: Rect2i in candidates:
		gate.gate_room = cand
		next_room = _spawn_next_sector_room(plan, gate, cand, gate_depth + 1, next_sector)
		if next_room.size != Vector2i.ZERO:
			break

	if next_room.size == Vector2i.ZERO:
		var extra_host: Rect2i = _spawn_extra_hub_gate_host(plan, wing_rooms, wing_entry, Rect2i(), wing_sector, gate_depth, lane_side)
		if extra_host.size != Vector2i.ZERO:
			wing_rooms.append(extra_host)
			gate.gate_room = extra_host
			next_room = _spawn_next_sector_room(plan, gate, extra_host, gate_depth + 1, next_sector)

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
	allowed_sectors: Array[int],
	key_depth: int,
	fallback_target: Rect2i,
	reserved: Array[Rect2i],
	extra_excluded: Rect2i = Rect2i(),
) -> void:
	var wing_sector: int = gate.key_sector
	var bfs_rooms: Array[Rect2i] = wing_rooms.duplicate()
	if not bfs_rooms.has(wing_entry):
		bfs_rooms.append(wing_entry)
	var dist_from_entry: Dictionary[Rect2i, int] = _bfs_sector_distances(plan, wing_entry, bfs_rooms)
	var excluded: Array[Rect2i] = [wing_entry, plan.hero_room, gate.gate_room]
	if extra_excluded.size != Vector2i.ZERO and not excluded.has(extra_excluded):
		excluded.append(extra_excluded)
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

	ShortcutTunnelPlanner.setup_shortcut_and_key(plan, gate, key_room, gate.gate_room, allowed_sectors, reserved, fallback_target)
	_add_safe_sector_loops(plan, gate, wing_rooms, bfs_rooms, wing_entry, key_room, wing_sector, reserved)
	if gate.has_shortcut and key_room != gate.shortcut_target_room:
		plan._add_neighbor_edge(key_room, gate.shortcut_target_room)
	plan.sector_gates.append(gate)
	_register_key_and_shortcut_tiles(plan, gate)


static func _spawn_extra_hub_gate_host(
	plan: WorldPlan,
	hub_rooms: Array[Rect2i],
	entry_room: Rect2i,
	primary_gate_room: Rect2i,
	hub_sector: int,
	target_depth: int,
	prefer_side_sign: int,
) -> Rect2i:
	var south_limit_y: int = (plan.hero_room.end.y + 45) if hub_sector == 0 else (entry_room.end.y + 25)
	var base_angle: float = (-PI * 0.78) if prefer_side_sign < 0 else (-PI * 0.22)
	for r: Rect2i in hub_rooms:
		if r == primary_gate_room:
			continue
		for attempt: int in range(20):
			var angle: float = base_angle + plan._rng.randf_range(-0.65, 0.65)
			var host: Rect2i = plan._try_place_maze_child(r, hub_sector, target_depth, angle, south_limit_y, true)
			if host.size != Vector2i.ZERO:
				return host
	return Rect2i()


static func verify_solvability(plan: WorldPlan) -> bool:
	return ShortcutTunnelPlanner.verify_solvability(plan)


static func _make_reserved_sky_rect(anchor_room: Rect2i, wing_bias_side: int = 0) -> Rect2i:
	var limit: int = WorldPlan.HALF_WORLD_SIZE - 120
	var top_y: int = -limit
	var bot_y: int = anchor_room.position.y - 2
	var h: int = maxi(1, bot_y - top_y)
	if wing_bias_side < 0:
		var x_start: int = anchor_room.position.x - 2
		return Rect2i(x_start, top_y, maxi(1, limit - x_start), h)
	if wing_bias_side > 0:
		var x_end: int = anchor_room.end.x + 2
		return Rect2i(-limit, top_y, maxi(1, x_end + limit), h)
	return Rect2i(anchor_room.position.x - 16, top_y, anchor_room.size.x + 32, h)


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


static func _rank_gate_candidates(
	plan: WorldPlan,
	sector_rooms: Array[Rect2i],
	entry_room: Rect2i,
	dist_from_entry: Dictionary[Rect2i, int],
	side_sign: int,
	other_gate_x: int,
	prefer_separated: bool,
) -> Array[Rect2i]:
	var scored: Array[Dictionary] = []
	for r: Rect2i in sector_rooms:
		if r == entry_room or r == plan.hero_room:
			continue
		var tier_penalty: int = 9000
		if _has_clear_north_gate_space(plan, r, 44):
			tier_penalty = 0
		elif _has_clear_north_gate_space(plan, r, 24):
			tier_penalty = 600
		elif _has_clear_north_wall_strip(plan, r, 6):
			tier_penalty = 2000
		var s: int = tier_penalty + _score_gate_candidate(r, dist_from_entry)
		var cx: int = r.get_center().x
		if side_sign != 0:
			s -= side_sign * cx * 6
		if prefer_separated and absi(cx - other_gate_x) < 36:
			s += 4000
		scored.append({&"room": r, &"score": s})

	scored.sort_custom(_compare_scored_room_asc)
	var result: Array[Rect2i] = []
	for entry: Dictionary in scored:
		result.append(entry[&"room"])
	return result


static func _compare_scored_room_asc(a: Dictionary, b: Dictionary) -> bool:
	var sa: int = a[&"score"]
	var sb: int = b[&"score"]
	return sa < sb


static func _score_gate_candidate(room: Rect2i, dist_from_entry: Dictionary[Rect2i, int]) -> int:
	var entry_bonus: int = -120 if dist_from_entry.get(room, 0) >= 2 else 0
	return room.position.y * 10 + absi(room.get_center().x) + entry_bonus


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
	var valid: Array[Rect2i] = _collect_valid_key_candidates(plan, excluded_rooms, sector_rooms)
	var max_dist: int = _max_candidate_dist(valid, dist_from_origin)

	for step: int in range(MAX_KEY_EXTEND_STEPS + 1):
		if not valid.is_empty() and (step >= MAX_KEY_EXTEND_STEPS or max_dist >= MIN_KEY_HOPS):
			break
		var ext: Rect2i = _spawn_key_wing_extension(plan, origin_room, entry_room, sector_rooms, dist_from_origin, sector_idx, current_depth)
		if ext.size == Vector2i.ZERO:
			break
		sector_rooms.append(ext)
		bfs_rooms.append(ext)
		dist_from_origin = _bfs_sector_distances(plan, origin_room, bfs_rooms)
		dist_from_entry = _bfs_sector_distances(plan, entry_room, bfs_rooms)
		valid = _collect_valid_key_candidates(plan, excluded_rooms, sector_rooms)
		max_dist = _max_candidate_dist(valid, dist_from_origin)

	if valid.is_empty():
		for r: Rect2i in sector_rooms:
			if not excluded_rooms.has(r):
				valid.append(r)
		if valid.is_empty():
			return origin_room

	return _pick_best_key_room(plan, origin_room, sector_rooms, valid, dist_from_origin, dist_from_entry)


static func _collect_valid_key_candidates(
	plan: WorldPlan,
	excluded_rooms: Array[Rect2i],
	sector_rooms: Array[Rect2i],
) -> Array[Rect2i]:
	var valid: Array[Rect2i] = []
	for r: Rect2i in sector_rooms:
		if excluded_rooms.has(r):
			continue
		if _has_clear_north_wall_strip(plan, r, 6):
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
		var north_penalty: int = 400 if r.position.y < origin_room.position.y - 4 else 0
		var score: int = reach_bonus + hop_score + leaf_bonus + entry_sep - euclid_dist * 8 - north_penalty
		if score > best_score:
			best_score = score
			best = r
	return best


static func _spawn_key_wing_extension(
	plan: WorldPlan,
	origin_room: Rect2i,
	entry_room: Rect2i,
	sector_rooms: Array[Rect2i],
	dist_from_origin: Dictionary[Rect2i, int],
	sector_idx: int,
	target_depth: int,
) -> Rect2i:
	var tried: Dictionary[Rect2i, bool] = {}
	var south_limit_y: int = (plan.hero_room.end.y + 45) if sector_idx == 0 else (entry_room.end.y + 25)
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
	origin_room: Rect2i,
	key_room: Rect2i,
	sector_idx: int,
	reserved_growth_rects: Array[Rect2i],
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

	var dist_from_origin: Dictionary[Rect2i, int] = _bfs_sector_distances(plan, origin_room, bfs_rooms)
	var dist_from_key: Dictionary[Rect2i, int] = _bfs_sector_distances(plan, key_room, bfs_rooms)
	var added: int = 0

	for pair: Array in pairs:
		if added >= WorldPlan.MAX_LOOPS_PER_SECTOR:
			break
		var room_a: Rect2i = pair[0]
		var room_b: Rect2i = pair[1]
		var path_a: int = dist_from_key.get(room_a, 999) + 1 + dist_from_origin.get(room_b, 999)
		var path_b: int = dist_from_key.get(room_b, 999) + 1 + dist_from_origin.get(room_a, 999)
		if mini(path_a, path_b) < MIN_KEY_HOPS:
			continue
		var segs: Array[Dictionary] = RoomLayout.plan_corridor(plan, room_a, room_b, [], sector_idx, true)
		if segs.is_empty() or _corridor_hits_protected(segs, gate.shortcut_corridor_rects, reserved_growth_rects):
			continue
		RoomLayout.commit_corridor(plan, segs, sector_idx)
		plan._add_neighbor_edge(room_a, room_b)
		added += 1
		dist_from_origin = _bfs_sector_distances(plan, origin_room, bfs_rooms)
		dist_from_key = _bfs_sector_distances(plan, key_room, bfs_rooms)


static func _corridor_hits_protected(
	segs: Array[Dictionary],
	shortcut_rects: Array[Rect2i],
	reserved_growth_rects: Array[Rect2i],
) -> bool:
	for seg: Dictionary in segs:
		var r: Rect2i = seg[&"rect"]
		if WorldPlan._intersects_any_rect(r.grow(2), shortcut_rects):
			return true
		if WorldPlan._intersects_any_rect(r.grow(1), reserved_growth_rects):
			return true
	return false


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

	var x_offsets: Array[int] = [0, -6, 6, -12, 12, -18, 18, -24, 24, -32, 32, -44, 44]
	var y_extras: Array[int] = [0, 8, 16, 24, 32, 40, 52, 66, 84]

	for y_extra: int in y_extras:
		for x_off: int in x_offsets:
			var size: Vector2i = RoomLayout.roll_room_size(plan._rng, next_depth)
			var bottom_y: int = door_y - 14 - y_extra
			var top_left: Vector2i = Vector2i(gate_room.get_center().x + x_off - int(float(size.x) * 0.5), bottom_y - size.y)
			var candidate: Rect2i = Rect2i(top_left, size)
			if plan._is_outside_world_bounds(candidate) or plan._is_outside_sector_x_bound(candidate) or plan._overlaps_any_room(candidate):
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
		segs.append(ShortcutTunnelPlanner.make_vert_corridor_rect(door_y - 5, dest_center.y, door_x, 2))
	else:
		segs.append(ShortcutTunnelPlanner.make_vert_corridor_rect(door_y - 5, mid_y, door_x, 2))
		segs.append(ShortcutTunnelPlanner.make_horiz_corridor_rect(door_x, dest_center.x, mid_y, 2))
		segs.append(ShortcutTunnelPlanner.make_vert_corridor_rect(mid_y, dest_center.y, dest_center.x, 2))

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


static func _register_door_cells(plan: WorldPlan, gate: SectorGate) -> void:
	for i: int in range(gate.door_cells.size()):
		plan.door_cell_codes[gate.door_cells[i]] = int(gate.color) * 2 + i
		_mark_no_prop_radius(plan, gate.door_cells[i], 2)


static func _register_key_and_shortcut_tiles(plan: WorldPlan, gate: SectorGate) -> void:
	_mark_no_prop_radius(plan, gate.key_cell, 2)
	if not gate.has_shortcut:
		return
	for cell: Vector2i in gate.shortcut_wall_cells:
		plan.closed_shortcut_walls[cell] = true
		_mark_no_prop_radius(plan, cell, 2)
	for cell: Vector2i in gate.shortcut_flank_cells:
		plan.closed_shortcut_walls[cell] = true
		_mark_no_prop_radius(plan, cell, 1)
	plan.lever_cells[gate.lever_cell] = gate.color
	_mark_no_prop_radius(plan, gate.lever_cell, 2)
	if gate.key_room != gate.shortcut_target_room:
		_mark_no_prop_radius(plan, gate.gate_entry_cell, 3)


static func _mark_no_prop_radius(plan: WorldPlan, center: Vector2i, radius: int) -> void:
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			plan.no_prop_cells[center + Vector2i(dx, dy)] = true


static func prebake_shortcut_tunnels(plan: WorldPlan, raster: ChunkRaster) -> void:
	ShortcutTunnelPlanner.prebake_shortcut_tunnels(plan, raster)


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
