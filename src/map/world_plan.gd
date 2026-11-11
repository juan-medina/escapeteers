# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name WorldPlan
extends RefCounted

enum RoomArchetype {
	SLIME_PIT,
	BONE_SWARM,
	ARCHER_GARRISON,
	NECRO_CRYPT,
}

const WORLD_SIZE_TILES: int = 4096
const HALF_WORLD_SIZE: int = 2048

const HERO_ROOM_SIZE: Vector2i = Vector2i(18, 18)
const INITIAL_ROOM_COUNT: int = 3
const ROOM_PADDING: int = 8
const CORRIDOR_WIDTH: int = 4
const MAX_PLACEMENT_ATTEMPTS: int = 120
const LOOP_CONNECT_MAX_DISTANCE: float = 75.0
const LOOP_CONNECT_CHANCE: float = 0.40

const TIER_1_MIN_SIZE: Vector2i = Vector2i(16, 16)
const TIER_1_MAX_SIZE: Vector2i = Vector2i(22, 22)
const TIER_1_DISTANCE_RANGE: Vector2 = Vector2(30.0, 48.0)

const TIER_2_MIN_SIZE: Vector2i = Vector2i(24, 24)
const TIER_2_MAX_SIZE: Vector2i = Vector2i(34, 34)
const TIER_2_DISTANCE_RANGE: Vector2 = Vector2(42.0, 66.0)

const TIER_3_MIN_SIZE: Vector2i = Vector2i(36, 36)
const TIER_3_MAX_SIZE: Vector2i = Vector2i(50, 50)
const TIER_3_DISTANCE_RANGE: Vector2 = Vector2(56.0, 84.0)
const SPIKE_PHASE_GROUPS: int = 4

var run_seed: int = 0
var hero_room: Rect2i = Rect2i()
var rooms: Array[Rect2i] = []
var carve_rects: Array[Rect2i] = []
var spatial_grid: SpatialGrid = SpatialGrid.new()
var room_children: Dictionary[Rect2i, Array] = {}

var _room_depths: Dictionary[Rect2i, int] = {}
var _room_archetypes: Dictionary[Rect2i, RoomArchetype] = {}
var _room_neighbors: Dictionary[Rect2i, Array] = {}
var _room_enemy_quotas: Dictionary[Rect2i, int] = {}
var _room_companion_spawns: Dictionary[Rect2i, Array] = {}
var _room_grid: SpatialGrid = SpatialGrid.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _candle_post_bases: Dictionary[Vector2i, bool] = {}
var _candle_post_tops: Dictionary[Vector2i, bool] = {}
var _spike_cells: Dictionary[Vector2i, int] = {}
var _corridor_segments: Array[Dictionary] = []
var _next_spike_group: int = 0


func generate(seed_val: int = 0, max_depth: int = 12) -> void:
	run_seed = seed_val
	if run_seed != 0:
		_rng.seed = run_seed
	else:
		_rng.randomize()
		run_seed = int(_rng.seed)

	rooms.clear()
	carve_rects.clear()
	spatial_grid.clear()
	room_children.clear()
	_room_grid.clear()
	_room_depths.clear()
	_room_archetypes.clear()
	_room_neighbors.clear()
	_room_enemy_quotas.clear()
	_room_companion_spawns.clear()
	_candle_post_bases.clear()
	_candle_post_tops.clear()
	_spike_cells.clear()
	_corridor_segments.clear()
	_next_spike_group = 0

	_create_hero_room()
	_create_initial_rooms()
	_expand_dungeon_branches(max_depth)
	_color_room_graph()
	_eliminate_narrow_gaps()
	_plan_spike_traps()


func is_floor(cell: Vector2i) -> bool:
	if absi(cell.x) >= HALF_WORLD_SIZE or absi(cell.y) >= HALF_WORLD_SIZE:
		return false
	return spatial_grid.has_point(cell, carve_rects)


func get_child_rooms(parent_room: Rect2i) -> Array:
	if room_children.has(parent_room):
		return room_children[parent_room]
	return []


func get_depth_rooms(depth: int) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	for room: Rect2i in rooms:
		if get_room_depth(room) == depth:
			result.append(room)
	return result


func get_carve_rects_in_rect(query_rect: Rect2i) -> Array[Rect2i]:
	var candidate_ids: Array[int] = spatial_grid.get_candidate_ids_for_rect(query_rect)
	var result: Array[Rect2i] = []
	for idx: int in candidate_ids:
		if idx >= 0 and idx < carve_rects.size():
			if carve_rects[idx].intersects(query_rect):
				result.append(carve_rects[idx])
	return result


func get_room_depth(room: Rect2i) -> int:
	if _room_depths.has(room):
		return _room_depths[room]
	var center_y: float = float(room.get_center().y)
	return maxi(1, int(maxf(0.0, -center_y) / 50.0))


func get_room_tier(room: Rect2i) -> int:
	var depth: int = get_room_depth(room)
	if depth <= 1:
		return 1
	if depth <= 3:
		return 2
	return 3


func get_room_archetype(room: Rect2i) -> RoomArchetype:
	if _room_archetypes.has(room):
		return _room_archetypes[room]
	return RoomArchetype.SLIME_PIT


func _color_room_graph() -> void:
	var all_colors: Array[RoomArchetype] = [
		RoomArchetype.SLIME_PIT,
		RoomArchetype.BONE_SWARM,
		RoomArchetype.ARCHER_GARRISON,
		RoomArchetype.NECRO_CRYPT,
	]
	var necro_at_depth: Dictionary[int, int] = {}
	for room: Rect2i in rooms:
		if _room_archetypes.has(room):
			continue
		var depth: int = get_room_depth(room)
		var forbidden: Array[RoomArchetype] = _get_neighbor_archetypes(room)
		var candidates: Array[RoomArchetype] = []
		for color: RoomArchetype in all_colors:
			if depth <= 1 and color == RoomArchetype.NECRO_CRYPT:
				continue
			if not forbidden.has(color):
				candidates.append(color)
		if candidates.is_empty():
			candidates.append_array(all_colors)
		var needs_necro: bool = not necro_at_depth.has(depth)
		var chosen: RoomArchetype = _pick_weighted_archetype(candidates, depth, needs_necro)
		_room_archetypes[room] = chosen
		if chosen == RoomArchetype.NECRO_CRYPT:
			necro_at_depth[depth] = (necro_at_depth[depth] + 1) if necro_at_depth.has(depth) else 1


func _get_neighbor_archetypes(room: Rect2i) -> Array[RoomArchetype]:
	var used: Array[RoomArchetype] = []
	if not _room_neighbors.has(room):
		return used
	var neighbors: Array = _room_neighbors[room]
	for n_var: Variant in neighbors:
		if n_var is Rect2i:
			var n_room: Rect2i = n_var
			if _room_archetypes.has(n_room):
				var arch: RoomArchetype = _room_archetypes[n_room]
				if not used.has(arch):
					used.append(arch)
	return used


func _pick_weighted_archetype(candidates: Array[RoomArchetype], depth: int, needs_necro: bool) -> RoomArchetype:
	if depth >= 2 and needs_necro and candidates.has(RoomArchetype.NECRO_CRYPT):
		return RoomArchetype.NECRO_CRYPT
	var total_weight: int = 0
	for c: RoomArchetype in candidates:
		total_weight += _get_archetype_weight(c)
	var roll: int = _rng.randi_range(1, maxi(1, total_weight))
	var accum: int = 0
	var chosen: RoomArchetype = candidates[0]
	for c: RoomArchetype in candidates:
		accum += _get_archetype_weight(c)
		if roll <= accum:
			chosen = c
			break
	return chosen


static func _get_archetype_weight(archetype: RoomArchetype) -> int:
	var weight: int = 25
	if archetype == RoomArchetype.NECRO_CRYPT:
		weight = 35
	elif archetype == RoomArchetype.SLIME_PIT:
		weight = 15
	return weight


func _add_neighbor_edge(room_a: Rect2i, room_b: Rect2i) -> void:
	if not _room_neighbors.has(room_a):
		_room_neighbors[room_a] = []
	if not _room_neighbors[room_a].has(room_b):
		_room_neighbors[room_a].append(room_b)
	if not _room_neighbors.has(room_b):
		_room_neighbors[room_b] = []
	if not _room_neighbors[room_b].has(room_a):
		_room_neighbors[room_b].append(room_a)


func get_room_enemy_quota(room: Rect2i) -> int:
	if _room_enemy_quotas.has(room):
		return _room_enemy_quotas[room]
	var depth: int = get_room_depth(room)
	var area_factor: float = float(room.size.x * room.size.y) / (28.0 * 28.0)
	var steps: int = depth - 1
	var base_min: int = 4 + steps * 4 + steps * steps
	var base_max: int = 6 + steps * 6 + steps * steps
	var scaled_min: int = int(roundf(float(base_min) * clampf(area_factor * 0.65, 0.8, 2.2)))
	var scaled_max: int = int(roundf(float(base_max) * clampf(area_factor * 0.65, 0.8, 2.2)))
	var quota: int = clampi(_rng.randi_range(scaled_min, maxi(scaled_min, scaled_max)), 4, 140)
	_room_enemy_quotas[room] = quota
	return quota


func get_companion_spawns_for_room(room: Rect2i) -> Array:
	if _room_companion_spawns.has(room):
		return _room_companion_spawns[room]
	var spawns: Array[Vector2i] = _compute_companion_spawns_for_room(room)
	_room_companion_spawns[room] = spawns
	return spawns


func get_room_at(cell: Vector2i) -> Rect2i:
	if hero_room.has_point(cell):
		return hero_room
	var candidate_ids: Array = _room_grid.get_candidate_ids_for_point(cell)
	for idx: int in candidate_ids:
		if idx >= 0 and idx < rooms.size():
			if rooms[idx].has_point(cell):
				return rooms[idx]
	return Rect2i()


func is_candle_post_top(cell: Vector2i) -> bool:
	return _candle_post_tops.has(cell)


func is_candle_post_base(cell: Vector2i) -> bool:
	return _candle_post_bases.has(cell)


func is_spike_cell(cell: Vector2i) -> bool:
	return _spike_cells.has(cell)


func get_spike_group(cell: Vector2i) -> int:
	return _spike_cells.get(cell, 0)


func _create_hero_room() -> void:
	var top_left: Vector2i = Vector2i(Vector2(-HERO_ROOM_SIZE) * 0.5)
	hero_room = Rect2i(top_left, HERO_ROOM_SIZE)
	_room_depths[hero_room] = 0
	_add_carve_rect(hero_room)


func _create_initial_rooms() -> void:
	var placed: int = 0
	var attempts: int = 0
	# Distribute starter rooms in an upward arc centered on North (-PI * 0.5)
	var starter_angles: Array[float] = [-PI * 0.75, -PI * 0.5, -PI * 0.25]
	var starter_archetypes: Array[RoomArchetype] = [
		RoomArchetype.SLIME_PIT,
		RoomArchetype.BONE_SWARM,
		RoomArchetype.ARCHER_GARRISON,
	]
	for s_idx: int in range(starter_archetypes.size() - 1, 0, -1):
		var swap_idx: int = _rng.randi_range(0, s_idx)
		var tmp: RoomArchetype = starter_archetypes[s_idx]
		starter_archetypes[s_idx] = starter_archetypes[swap_idx]
		starter_archetypes[swap_idx] = tmp

	while placed < INITIAL_ROOM_COUNT and attempts < MAX_PLACEMENT_ATTEMPTS * 4:
		attempts += 1
		var base_angle: float = starter_angles[placed % starter_angles.size()]
		var slot_angle: float = base_angle + _rng.randf_range(-0.15, 0.15)
		var distance: float = _rng.randf_range(TIER_1_DISTANCE_RANGE.x, TIER_1_DISTANCE_RANGE.y)
		var size: Vector2i = Vector2i(_rng.randi_range(TIER_1_MIN_SIZE.x, TIER_1_MAX_SIZE.x), _rng.randi_range(TIER_1_MIN_SIZE.y, TIER_1_MAX_SIZE.y))
		var center_pos: Vector2 = Vector2.from_angle(slot_angle) * distance
		var top_left: Vector2i = Vector2i(center_pos.round()) - Vector2i(Vector2(size) * 0.5)
		var candidate_room: Rect2i = Rect2i(top_left, size)

		if _overlaps_any_room(candidate_room):
			continue

		_room_archetypes[candidate_room] = starter_archetypes[placed % starter_archetypes.size()]
		_add_room(candidate_room, 1)
		_carve_corridor(hero_room.get_center(), candidate_room.get_center())
		placed += 1

	for i: int in range(rooms.size()):
		var next_idx: int = (i + 1) % rooms.size()
		if i != next_idx and _rng.randf() <= 0.5:
			var center_a: Vector2i = rooms[i].get_center()
			var center_b: Vector2i = rooms[next_idx].get_center()
			if Vector2(center_a).distance_to(Vector2(center_b)) <= LOOP_CONNECT_MAX_DISTANCE:
				_add_neighbor_edge(rooms[i], rooms[next_idx])
				_carve_corridor(center_a, center_b)


func _expand_dungeon_branches(target_max_depth: int) -> void:
	var current_depth: int = 1
	var frontier_rooms: Array[Rect2i] = rooms.duplicate()

	while current_depth < target_max_depth and not frontier_rooms.is_empty():
		var next_frontier: Array[Rect2i] = []
		for parent_room: Rect2i in frontier_rooms:
			var child_depth: int = current_depth + 1
			var target_branches: int = _rng.randi_range(1, 2)
			var source_center: Vector2 = Vector2(parent_room.get_center())

			var min_size: Vector2i = _get_min_size_for_depth(child_depth)
			var max_size: Vector2i = _get_max_size_for_depth(child_depth)
			var dist_range: Vector2 = _get_step_distance_for_depth(child_depth)

			var placed: int = 0
			var attempts: int = 0
			while placed < target_branches and attempts < MAX_PLACEMENT_ATTEMPTS:
				attempts += 1
				var angle: float
				if placed == 0:
					# Primary branch: Northward ascent (-Y direction)
					angle = -PI * 0.5 + _rng.randf_range(-0.55, 0.55)
				else:
					# Secondary branch: Lateral East or West wing
					var side_dir: float = -1.0 if _rng.randf() < 0.5 else 1.0
					angle = -PI * 0.5 + side_dir * _rng.randf_range(0.65, 1.25)

				var step_dist: float = _rng.randf_range(dist_range.x, dist_range.y)
				var size: Vector2i = Vector2i(_rng.randi_range(min_size.x, max_size.x), _rng.randi_range(min_size.y, max_size.y))
				var center_pos: Vector2 = source_center + Vector2.from_angle(angle) * step_dist
				var top_left: Vector2i = Vector2i(center_pos.round()) - Vector2i(Vector2(size) * 0.5)
				var candidate: Rect2i = Rect2i(top_left, size)

				# Prevent deep branches from looping far back to South
				if candidate.get_center().y > parent_room.get_center().y + 10:
					continue

				if _is_outside_world_bounds(candidate) or _overlaps_any_room(candidate):
					continue

				if not room_children.has(parent_room):
					room_children[parent_room] = []
				for sibling_var: Variant in room_children[parent_room]:
					if sibling_var is Rect2i:
						var sibling_room: Rect2i = sibling_var
						_add_neighbor_edge(candidate, sibling_room)
				room_children[parent_room].append(candidate)
				_add_neighbor_edge(parent_room, candidate)

				_add_room(candidate, child_depth)
				_carve_corridor(parent_room.get_center(), candidate.get_center())
				next_frontier.append(candidate)
				placed += 1

				for other_room: Rect2i in rooms:
					if other_room == candidate or other_room == parent_room:
						continue
					var d: float = Vector2(candidate.get_center()).distance_to(Vector2(other_room.get_center()))
					if d <= LOOP_CONNECT_MAX_DISTANCE and _rng.randf() <= LOOP_CONNECT_CHANCE:
						_add_neighbor_edge(candidate, other_room)
						_carve_corridor(candidate.get_center(), other_room.get_center())
						break

		frontier_rooms = next_frontier
		current_depth += 1


func _add_room(room: Rect2i, depth: int) -> void:
	rooms.append(room)
	_room_depths[room] = depth
	_room_grid.add_rect(rooms.size() - 1, room)
	_add_carve_rect(room)
	get_room_enemy_quota(room)
	get_companion_spawns_for_room(room)
	_plan_candle_posts_for_room(room)


func _add_carve_rect(rect: Rect2i) -> void:
	carve_rects.append(rect)
	spatial_grid.add_rect(carve_rects.size() - 1, rect)


func _plan_candle_posts_for_room(room: Rect2i) -> void:
	var cols: int = maxi(1, roundi(float(room.size.x - 6) / 14.0))
	var rows: int = maxi(1, roundi(float(room.size.y - 6) / 14.0))
	var center: Vector2i = room.get_center()

	var step_x: float = float(room.size.x - 6) / float(cols + 1)
	var step_y: float = float(room.size.y - 6) / float(rows + 1)

	for r_idx: int in range(rows):
		var target_y: int = room.position.y + 3 + int(roundf(float(r_idx + 1) * step_y))
		for c_idx: int in range(cols):
			var target_x: int = room.position.x + 3 + int(roundf(float(c_idx + 1) * step_x))
			var base_cell: Vector2i = Vector2i(target_x, target_y)

			# If landing on companion spawn at room center, shift slightly
			if base_cell.distance_squared_to(center) <= 6:
				base_cell.x += 2 if (c_idx % 2 == 0) else -2

			var top_cell: Vector2i = base_cell + Vector2i(0, -1)
			_candle_post_bases[base_cell] = true
			_candle_post_tops[top_cell] = true


func has_candle_post_near(cell: Vector2i, radius_sq: int = 81) -> bool:
	var r: int = int(ceilf(sqrt(float(radius_sq))))
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			if dx * dx + dy * dy <= radius_sq:
				if _candle_post_tops.has(cell + Vector2i(dx, dy)):
					return true
	return false


func _overlaps_any_room(candidate: Rect2i) -> bool:
	if hero_room.grow(ROOM_PADDING).intersects(candidate):
		return true
	return _room_grid.intersects_any(candidate, rooms, ROOM_PADDING)


func _is_outside_world_bounds(rect: Rect2i) -> bool:
	var limit: int = HALF_WORLD_SIZE - ROOM_PADDING - 100
	return absi(rect.position.x) > limit or absi(rect.position.y) > limit or absi(rect.end.x) > limit or absi(rect.end.y) > limit


func _carve_corridor(from: Vector2i, to: Vector2i) -> void:
	var half_width: int = int(float(CORRIDOR_WIDTH) * 0.5)
	if _rng.randf() <= 0.5:
		_add_horizontal_corridor_rect(from.x, to.x, from.y, half_width)
		_add_vertical_corridor_rect(from.y, to.y, to.x, half_width)
	else:
		_add_vertical_corridor_rect(from.y, to.y, from.x, half_width)
		_add_horizontal_corridor_rect(from.x, to.x, to.y, half_width)


func _add_horizontal_corridor_rect(x_start: int, x_end: int, y: int, half_width: int) -> void:
	var min_x: int = mini(x_start, x_end)
	var max_x: int = maxi(x_start, x_end)
	var rect: Rect2i = Rect2i(min_x, y - half_width, (max_x - min_x) + 1, half_width * 2 + 1)
	_add_carve_rect(rect)
	_corridor_segments.append({&"is_horizontal": true, &"min": min_x, &"max": max_x, &"fixed": y, &"half_width": half_width})


func _add_vertical_corridor_rect(y_start: int, y_end: int, x: int, half_width: int) -> void:
	var min_y: int = mini(y_start, y_end)
	var max_y: int = maxi(y_start, y_end)
	var rect: Rect2i = Rect2i(x - half_width, min_y, half_width * 2 + 1, (max_y - min_y) + 1)
	_add_carve_rect(rect)
	_corridor_segments.append({&"is_horizontal": false, &"min": min_y, &"max": max_y, &"fixed": x, &"half_width": half_width})


func _eliminate_narrow_gaps() -> void:
	var bridges_to_add: Array[Rect2i] = []
	for i: int in range(carve_rects.size()):
		var rect_a: Rect2i = carve_rects[i]
		var query_rect: Rect2i = rect_a.grow(3)
		var candidates: Array[int] = spatial_grid.get_candidate_ids_for_rect(query_rect)

		for j: int in candidates:
			if j <= i or j >= carve_rects.size():
				continue
			var rect_b: Rect2i = carve_rects[j]

			var gap_x1: int = rect_b.position.x - rect_a.end.x
			if gap_x1 > 0 and gap_x1 <= 2:
				var ov_y_start: int = maxi(rect_a.position.y, rect_b.position.y)
				var ov_y_end: int = mini(rect_a.end.y, rect_b.end.y)
				if ov_y_end > ov_y_start:
					bridges_to_add.append(Rect2i(rect_a.end.x, ov_y_start, gap_x1, ov_y_end - ov_y_start))

			var gap_x2: int = rect_a.position.x - rect_b.end.x
			if gap_x2 > 0 and gap_x2 <= 2:
				var ov_y_start: int = maxi(rect_a.position.y, rect_b.position.y)
				var ov_y_end: int = mini(rect_a.end.y, rect_b.end.y)
				if ov_y_end > ov_y_start:
					bridges_to_add.append(Rect2i(rect_b.end.x, ov_y_start, gap_x2, ov_y_end - ov_y_start))

			var gap_y1: int = rect_b.position.y - rect_a.end.y
			if gap_y1 > 0 and gap_y1 <= 2:
				var ov_x_start: int = maxi(rect_a.position.x, rect_b.position.x)
				var ov_x_end: int = mini(rect_a.end.x, rect_b.end.x)
				if ov_x_end > ov_x_start:
					bridges_to_add.append(Rect2i(ov_x_start, rect_a.end.y, ov_x_end - ov_x_start, gap_y1))

			var gap_y2: int = rect_a.position.y - rect_b.end.y
			if gap_y2 > 0 and gap_y2 <= 2:
				var ov_x_start: int = maxi(rect_a.position.x, rect_b.position.x)
				var ov_x_end: int = mini(rect_a.end.x, rect_b.end.x)
				if ov_x_end > ov_x_start:
					bridges_to_add.append(Rect2i(ov_x_start, rect_b.end.y, ov_x_end - ov_x_start, gap_y2))

	for bridge: Rect2i in bridges_to_add:
		_add_carve_rect(bridge)


func _compute_companion_spawns_for_room(room: Rect2i) -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	var center_cell: Vector2i = room.get_center()
	var tier: int = get_room_tier(room)

	positions.append(center_cell)
	if tier == 2 and _rng.randf() < 0.35:
		var offset: Vector2i = Vector2i(_rng.randi_range(-2, 2), _rng.randi_range(-2, 2))
		if offset != Vector2i.ZERO:
			positions.append(center_cell + offset)
	elif tier >= 3 and _rng.randf() < 0.65:
		var offset: Vector2i = Vector2i(_rng.randi_range(-3, 3), _rng.randi_range(-3, 3))
		if offset != Vector2i.ZERO:
			positions.append(center_cell + offset)

	return positions


func _get_min_size_for_depth(depth: int) -> Vector2i:
	if depth <= 1:
		return TIER_1_MIN_SIZE
	if depth <= 3:
		return TIER_2_MIN_SIZE
	var bonus: int = mini((depth - 4) * 2, 10)
	return TIER_3_MIN_SIZE + Vector2i(bonus, bonus)


func _get_max_size_for_depth(depth: int) -> Vector2i:
	if depth <= 1:
		return TIER_1_MAX_SIZE
	if depth <= 3:
		return TIER_2_MAX_SIZE
	var bonus: int = mini((depth - 4) * 3, 12)
	return TIER_3_MAX_SIZE + Vector2i(bonus, bonus)


func _get_step_distance_for_depth(depth: int) -> Vector2:
	if depth <= 1:
		return TIER_1_DISTANCE_RANGE
	if depth <= 3:
		return TIER_2_DISTANCE_RANGE
	var bonus: float = minf(float(depth - 4) * 3.0, 16.0)
	return TIER_3_DISTANCE_RANGE + Vector2(bonus, bonus)


func _plan_spike_traps() -> void:
	for room: Rect2i in rooms:
		_plan_room_spike_traps(room)
	_plan_corridor_spike_traps()


func _plan_room_spike_traps(room: Rect2i) -> void:
	var depth: int = get_room_depth(room)
	if depth <= 0:
		return

	var chance: float = 0.35
	var max_patches: int = 1
	if depth >= 4:
		chance = 0.80
		max_patches = _rng.randi_range(2, 3)
	elif depth >= 2:
		chance = 0.60
		max_patches = _rng.randi_range(1, 2)

	if _rng.randf() > chance:
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
	var anchors: Array[Vector2i] = [
		Vector2i(qx1, qy1),
		Vector2i(qx2, qy1),
		Vector2i(qx1, qy2),
		Vector2i(qx2, qy2),
	]
	for i: int in range(anchors.size() - 1, 0, -1):
		var swap_idx: int = _rng.randi_range(0, i)
		var tmp: Vector2i = anchors[i]
		anchors[i] = anchors[swap_idx]
		anchors[swap_idx] = tmp

	var placed: int = 0
	for base_anchor: Vector2i in anchors:
		if placed >= max_patches:
			break
		var jitter: Vector2i = Vector2i(_rng.randi_range(-1, 1), _rng.randi_range(-1, 1))
		var anchor: Vector2i = base_anchor + jitter
		var offsets: Array[Vector2i] = _pick_room_spike_pattern(depth)
		if _try_place_spike_patch(anchor, offsets, room, 25):
			placed += 1


func _pick_room_spike_pattern(depth: int) -> Array[Vector2i]:
	if depth <= 1:
		if _rng.randf() < 0.65:
			return _get_rect_offsets(2, 2)
		return _get_cross_offsets(1)

	var roll: float = _rng.randf()
	if roll < 0.30:
		return _get_rect_offsets(2, 2) if depth == 2 else _get_rect_offsets(3, 3)
	if roll < 0.60:
		return _get_cross_offsets(2)
	if roll < 0.80:
		return _get_zigzag_offsets(_rng.randf() < 0.5)
	return _get_rect_offsets(3, 3)


static func _get_rect_offsets(w: int, h: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	var start_x: int = -int(float(w) * 0.5)
	var start_y: int = -int(float(h) * 0.5)
	for dy: int in range(h):
		for dx: int in range(w):
			offsets.append(Vector2i(start_x + dx, start_y + dy))
	return offsets


static func _get_cross_offsets(arm_len: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = [Vector2i.ZERO]
	for d: int in range(1, arm_len + 1):
		offsets.append(Vector2i(d, 0))
		offsets.append(Vector2i(-d, 0))
		offsets.append(Vector2i(0, d))
		offsets.append(Vector2i(0, -d))
	return offsets


static func _get_zigzag_offsets(flip_x: bool) -> Array[Vector2i]:
	var raw: Array[Vector2i] = [
		Vector2i(-1, -1),
		Vector2i(0, -1),
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(1, 1),
		Vector2i(2, 1),
	]
	if not flip_x:
		return raw
	var flipped: Array[Vector2i] = []
	for p: Vector2i in raw:
		flipped.append(Vector2i(-p.x, p.y))
	return flipped


func _plan_corridor_spike_traps() -> void:
	for seg: Dictionary in _corridor_segments:
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
			if get_room_at(center_cell) == Rect2i():
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
		if _rng.randf() > chance:
			continue

		var side_first: int = -1 if _rng.randf() < 0.5 else 1
		if best_len >= 18 and _rng.randf() < 0.45:
			_place_corridor_half_block(is_horiz, mid_c - 3, fixed_c, half_w, side_first, 2)
			_place_corridor_half_block(is_horiz, mid_c + 3, fixed_c, half_w, -side_first, 2)
		else:
			_place_corridor_half_block(is_horiz, mid_c, fixed_c, half_w, side_first, 3)


func _place_corridor_half_block(is_horiz: bool, along_center: int, fixed_c: int, half_w: int, side: int, length: int) -> void:
	var cells: Array[Vector2i] = []
	var start_along: int = along_center - int(float(length) * 0.5)
	if is_horiz:
		# Top row (fixed_c - half_w) has the top wall on it; walkable rows are fixed_c - half_w + 1 .. fixed_c + half_w
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
		if not _is_valid_corridor_spike_cell(cell) or _has_spike_near(cell, 9):
			return

	var group_id: int = _next_spike_group % SPIKE_PHASE_GROUPS
	_next_spike_group += 1
	for cell: Vector2i in cells:
		_spike_cells[cell] = group_id


func _try_place_spike_patch(anchor: Vector2i, offsets: Array[Vector2i], room: Rect2i, min_other_patch_dist_sq: int) -> bool:
	var cells: Array[Vector2i] = []
	var center: Vector2i = room.get_center()
	var recruits: Array = get_companion_spawns_for_room(room)

	for offset: Vector2i in offsets:
		var cell: Vector2i = anchor + offset
		if not _is_valid_room_spike_cell(cell, room, center, recruits):
			return false
		if _has_spike_near(cell, min_other_patch_dist_sq):
			return false
		cells.append(cell)

	var group_id: int = _next_spike_group % SPIKE_PHASE_GROUPS
	_next_spike_group += 1
	for cell: Vector2i in cells:
		_spike_cells[cell] = group_id
	return true


func _is_valid_room_spike_cell(cell: Vector2i, room: Rect2i, center: Vector2i, recruits: Array) -> bool:
	if not room.grow(-3).has_point(cell):
		return false
	if not is_floor(cell) or not is_floor(cell + Vector2i(0, -1)):
		return false
	if cell.distance_squared_to(center) < 25:
		return false
	for r_var: Variant in recruits:
		if r_var is Vector2i:
			var r_cell: Vector2i = r_var
			if cell.distance_squared_to(r_cell) < 25:
				return false
	if has_candle_post_near(cell, 6):
		return false
	return true


func _is_valid_corridor_spike_cell(cell: Vector2i) -> bool:
	if hero_room.grow(4).has_point(cell):
		return false
	if get_room_at(cell) != Rect2i():
		return false
	if not is_floor(cell) or not is_floor(cell + Vector2i(0, -1)):
		return false
	if has_candle_post_near(cell, 6):
		return false
	return true


func _has_spike_near(cell: Vector2i, radius_sq: int) -> bool:
	var r: int = int(ceilf(sqrt(float(radius_sq))))
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			if dx * dx + dy * dy <= radius_sq:
				if _spike_cells.has(cell + Vector2i(dx, dy)):
					return true
	return false
