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

enum RoomShape {
	RECTANGLE,
	CUT_CORNERS,
	PILLARED,
	CROSS,
}

enum FloorPattern {
	BORDER_TRIM,
	CROSSROADS,
	ARENA_RINGS,
	CHECKERED_COURT,
	PILLAR_PLINTHS,
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
const TILE_SET_COUNT: int = 8

var run_seed: int = 0
var hero_room: Rect2i = Rect2i()
var rooms: Array[Rect2i] = []
var carve_rects: Array[Rect2i] = []
var spatial_grid: SpatialGrid = SpatialGrid.new()
var room_children: Dictionary[Rect2i, Array] = {}

var _room_depths: Dictionary[Rect2i, int] = {}
var _room_archetypes: Dictionary[Rect2i, RoomArchetype] = {}
var _room_tile_sets: Dictionary[Rect2i, int] = {}
var _room_shapes: Dictionary[Rect2i, RoomShape] = {}
var _room_floor_patterns: Dictionary[Rect2i, FloorPattern] = {}
var _room_pillars: Dictionary[Rect2i, Array] = {}
var _room_neighbors: Dictionary[Rect2i, Array] = {}
var _room_enemy_quotas: Dictionary[Rect2i, int] = {}
var _room_companion_spawns: Dictionary[Rect2i, Array] = {}
var _room_grid: SpatialGrid = SpatialGrid.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _candle_post_bases: Dictionary[Vector2i, bool] = {}
var _candle_post_tops: Dictionary[Vector2i, bool] = {}
var _spike_cells: Dictionary[Vector2i, int] = {}
var _corridor_segments: Array[Dictionary] = []
var _corridor_rects: Array[Rect2i] = []
var _all_pillars: Array[Rect2i] = []
var _cut_corner_rects: Array[Rect2i] = []
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
	_room_tile_sets.clear()
	_room_shapes.clear()
	_room_floor_patterns.clear()
	_room_pillars.clear()
	_room_neighbors.clear()
	_room_enemy_quotas.clear()
	_room_companion_spawns.clear()
	_candle_post_bases.clear()
	_candle_post_tops.clear()
	_spike_cells.clear()
	_corridor_segments.clear()
	_corridor_rects.clear()
	_all_pillars.clear()
	_cut_corner_rects.clear()
	_next_spike_group = 0

	_create_hero_room()
	_create_initial_rooms()
	_expand_dungeon_branches(max_depth)
	_prune_clipped_pillars()
	_color_room_graph()
	_eliminate_narrow_gaps()
	for room: Rect2i in rooms:
		_plan_candle_posts_for_room(room)
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


func get_room_tile_set(room: Rect2i) -> int:
	return _room_tile_sets.get(room, 1)


func get_cell_tile_set(cell: Vector2i) -> int:
	var room: Rect2i = get_room_at(cell)
	if room.size != Vector2i.ZERO:
		return _room_tile_sets.get(room, 1)

	var best_room: Rect2i = hero_room
	var best_dist_sq: int = _dist_sq_to_rect(cell, hero_room)
	if best_dist_sq > 2:
		for candidate: Rect2i in rooms:
			var dist_sq: int = _dist_sq_to_rect(cell, candidate)
			if dist_sq < best_dist_sq:
				best_dist_sq = dist_sq
				best_room = candidate
				if best_dist_sq <= 2:
					break

	return _room_tile_sets.get(best_room, 1)


static func _dist_sq_to_rect(cell: Vector2i, rect: Rect2i) -> int:
	var dx: int = maxi(rect.position.x - cell.x, maxi(0, cell.x - (rect.end.x - 1)))
	var dy: int = maxi(rect.position.y - cell.y, maxi(0, cell.y - (rect.end.y - 1)))
	return dx * dx + dy * dy


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


func get_floor_plate_index(cell: Vector2i) -> int:
	var room: Rect2i = get_room_at(cell)
	if room.size == Vector2i.ZERO:
		return -1

	var pattern: FloorPattern = _room_floor_patterns.get(room, FloorPattern.BORDER_TRIM)
	if pattern == FloorPattern.PILLAR_PLINTHS:
		var plinth_idx: int = _get_pillar_plinth_plate(cell, room)
		if plinth_idx >= 0:
			return plinth_idx

	if not _is_wall_buffer_free(cell):
		return -1

	var center: Vector2i = room.get_center()
	var result: int = -1
	match pattern:
		FloorPattern.BORDER_TRIM, FloorPattern.PILLAR_PLINTHS:
			result = 0 if _is_border_trim_cell(cell) else -1
		FloorPattern.CROSSROADS:
			var dx: int = absi(cell.x - center.x)
			var dy: int = absi(cell.y - center.y)
			var cheb: int = maxi(dx, dy)
			if cheb == 3:
				result = 0
			elif cheb > 3 and (dx == 2 or dy == 2):
				result = 1
		FloorPattern.ARENA_RINGS:
			var cheb: int = maxi(absi(cell.x - center.x), absi(cell.y - center.y))
			if cheb == 4:
				result = 0
			elif mini(room.size.x, room.size.y) >= 24 and cheb == 8:
				result = 1
		FloorPattern.CHECKERED_COURT:
			if absi(cell.x - center.x) % 3 == 0 and absi(cell.y - center.y) % 3 == 0:
				result = 2 if absi(cell.x + cell.y) % 2 == 0 else 3
	return result


func _get_pillar_plinth_plate(cell: Vector2i, room: Rect2i) -> int:
	if not is_floor(cell) or not is_floor(cell + Vector2i(0, -1)):
		return -1
	var pillars: Array = _room_pillars.get(room, [])
	for p_var: Variant in pillars:
		if p_var is Rect2i:
			var p: Rect2i = p_var
			var ring: Rect2i = Rect2i(p.position.x - 1, p.position.y - 1, p.size.x + 2, p.size.y + 3)
			if ring.has_point(cell):
				var on_side: bool = cell.x == ring.position.x or cell.x == ring.end.x - 1
				var on_cap: bool = cell.y == ring.position.y or cell.y == ring.end.y - 1
				return 2 if (on_side and on_cap) else 0
	return -1


func _is_wall_buffer_free(cell: Vector2i) -> bool:
	return (
		is_floor(cell)
		and is_floor(cell + Vector2i(0, -1))
		and is_floor(cell + Vector2i(0, -2))
		and is_floor(cell + Vector2i(0, 1))
		and is_floor(cell + Vector2i(-1, 0))
		and is_floor(cell + Vector2i(1, 0))
	)


func _is_border_trim_cell(cell: Vector2i) -> bool:
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var n_cell: Vector2i = cell + Vector2i(dx, dy)
			if not _is_wall_buffer_free(n_cell):
				var in_pillar: bool = false
				for p: Rect2i in _all_pillars:
					if Rect2i(p.position.x - 1, p.position.y - 1, p.size.x + 2, p.size.y + 3).has_point(n_cell):
						in_pillar = true
						break
				if not in_pillar:
					return true
	return false


func _create_hero_room() -> void:
	var top_left: Vector2i = Vector2i(Vector2(-HERO_ROOM_SIZE) * 0.5)
	hero_room = Rect2i(top_left, HERO_ROOM_SIZE)
	_room_depths[hero_room] = 0
	_room_tile_sets[hero_room] = _rng.randi_range(0, TILE_SET_COUNT - 1)
	_room_shapes[hero_room] = RoomShape.RECTANGLE
	_room_floor_patterns[hero_room] = FloorPattern.ARENA_RINGS
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
	_room_tile_sets[room] = _rng.randi_range(0, TILE_SET_COUNT - 1)
	var shape_roll: float = _rng.randf()
	var shape: RoomShape = RoomShape.RECTANGLE
	if shape_roll >= 0.85:
		shape = RoomShape.CROSS
	elif shape_roll >= 0.55:
		shape = RoomShape.PILLARED
	elif shape_roll >= 0.25:
		shape = RoomShape.CUT_CORNERS
	_room_shapes[room] = shape

	var pattern: FloorPattern = FloorPattern.BORDER_TRIM
	match shape:
		RoomShape.PILLARED:
			pattern = FloorPattern.PILLAR_PLINTHS if _rng.randf() < 0.65 else FloorPattern.CROSSROADS
		RoomShape.CROSS:
			pattern = FloorPattern.CROSSROADS if _rng.randf() < 0.70 else FloorPattern.BORDER_TRIM
		RoomShape.CUT_CORNERS:
			pattern = FloorPattern.ARENA_RINGS if _rng.randf() < 0.60 else FloorPattern.BORDER_TRIM
		_:
			var r_pat: int = _rng.randi_range(0, 3)
			pattern = r_pat as FloorPattern
	_room_floor_patterns[room] = pattern

	_room_grid.add_rect(rooms.size() - 1, room)
	_carve_room_layout(room, shape)
	get_room_enemy_quota(room)
	get_companion_spawns_for_room(room)


func _carve_room_layout(room: Rect2i, shape: RoomShape) -> void:
	var cut_x: int = 0
	var cut_y: int = 0
	if shape == RoomShape.CUT_CORNERS:
		cut_x = clampi(int(float(mini(room.size.x, room.size.y)) * 0.18), 3, 6)
		cut_y = cut_x
	elif shape == RoomShape.CROSS:
		cut_x = mini(clampi(int(float(room.size.x) * 0.25), 4, 10), maxi(0, int(float(room.size.x - 8) * 0.5)))
		cut_y = mini(clampi(int(float(room.size.y) * 0.25), 4, 10), maxi(0, int(float(room.size.y - 8) * 0.5)))
	elif shape == RoomShape.PILLARED and room.size.x >= 26 and room.size.y >= 26 and _rng.randf() < 0.5:
		cut_x = 3
		cut_y = 3

	var floor_rects: Array[Rect2i] = []
	if cut_x > 0 and cut_y > 0:
		floor_rects.append(Rect2i(room.position.x + cut_x, room.position.y, room.size.x - 2 * cut_x, cut_y))
		floor_rects.append(Rect2i(room.position.x, room.position.y + cut_y, room.size.x, room.size.y - 2 * cut_y))
		floor_rects.append(Rect2i(room.position.x + cut_x, room.end.y - cut_y, room.size.x - 2 * cut_x, cut_y))
		_cut_corner_rects.append(Rect2i(room.position.x, room.position.y, cut_x, cut_y))
		_cut_corner_rects.append(Rect2i(room.end.x - cut_x, room.position.y, cut_x, cut_y))
		_cut_corner_rects.append(Rect2i(room.position.x, room.end.y - cut_y, cut_x, cut_y))
		_cut_corner_rects.append(Rect2i(room.end.x - cut_x, room.end.y - cut_y, cut_x, cut_y))
	else:
		floor_rects.append(room)

	if shape == RoomShape.PILLARED:
		var center: Vector2i = room.get_center()
		var ps: int = 3 if mini(room.size.x, room.size.y) >= 26 else 2
		var ox: int = maxi(4, int(float(room.size.x) * 0.22))
		var oy: int = maxi(4, int(float(room.size.y) * 0.22))
		var p_size: Vector2i = Vector2i(ps, ps)
		var pillars: Array[Rect2i] = [
			Rect2i(Vector2i(center.x - ox - ps + 1, center.y - oy - ps + 1), p_size),
			Rect2i(Vector2i(center.x + ox, center.y - oy - ps + 1), p_size),
			Rect2i(Vector2i(center.x - ox - ps + 1, center.y + oy), p_size),
			Rect2i(Vector2i(center.x + ox, center.y + oy), p_size),
		]
		_room_pillars[room] = pillars
		_all_pillars.append_array(pillars)
		for p: Rect2i in pillars:
			floor_rects = _subtract_rect_from_list(floor_rects, p)

	for r: Rect2i in floor_rects:
		_add_carve_rect(r)


static func _subtract_rect_from_list(rects: Array[Rect2i], hole: Rect2i) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	for r: Rect2i in rects:
		if not r.intersects(hole):
			result.append(r)
			continue
		var inter: Rect2i = r.intersection(hole)
		if inter.position.y > r.position.y:
			result.append(Rect2i(r.position.x, r.position.y, r.size.x, inter.position.y - r.position.y))
		if inter.end.y < r.end.y:
			result.append(Rect2i(r.position.x, inter.end.y, r.size.x, r.end.y - inter.end.y))
		if inter.position.x > r.position.x:
			result.append(Rect2i(r.position.x, inter.position.y, inter.position.x - r.position.x, inter.size.y))
		if inter.end.x < r.end.x:
			result.append(Rect2i(inter.end.x, inter.position.y, r.end.x - inter.end.x, inter.size.y))
	return result


func _prune_clipped_pillars() -> void:
	for room: Rect2i in rooms:
		if not _room_pillars.has(room):
			continue
		var pillars: Array = _room_pillars[room]
		var kept: Array[Rect2i] = []
		for p_var: Variant in pillars:
			if p_var is Rect2i:
				var p: Rect2i = p_var
				var padded: Rect2i = p.grow(1)
				var touched: bool = false
				for c_rect: Rect2i in _corridor_rects:
					if c_rect.intersects(padded):
						touched = true
						break
				if touched:
					_add_carve_rect(p)
					_all_pillars.erase(p)
				else:
					kept.append(p)
		_room_pillars[room] = kept


func _add_carve_rect(rect: Rect2i) -> void:
	carve_rects.append(rect)
	spatial_grid.add_rect(carve_rects.size() - 1, rect)


func _plan_candle_posts_for_room(room: Rect2i) -> void:
	var cols: int = maxi(1, roundi(float(room.size.x - 6) / 14.0))
	var rows: int = maxi(1, roundi(float(room.size.y - 6) / 14.0))
	var center: Vector2i = room.get_center()

	var step_x: float = float(room.size.x - 6) / float(cols + 1)
	var step_y: float = float(room.size.y - 6) / float(rows + 1)
	var nudges: Array[Vector2i] = [Vector2i.ZERO, Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2), Vector2i(2, 2), Vector2i(-2, -2)]

	for r_idx: int in range(rows):
		var target_y: int = room.position.y + 3 + int(roundf(float(r_idx + 1) * step_y))
		for c_idx: int in range(cols):
			var target_x: int = room.position.x + 3 + int(roundf(float(c_idx + 1) * step_x))
			var base_cell: Vector2i = Vector2i(target_x, target_y)

			# If landing on companion spawn at room center, shift slightly
			if base_cell.distance_squared_to(center) <= 6:
				base_cell.x += 2 if (c_idx % 2 == 0) else -2

			for offset: Vector2i in nudges:
				var candidate: Vector2i = base_cell + offset
				if _is_valid_candle_base(candidate, center):
					_candle_post_bases[candidate] = true
					_candle_post_tops[candidate + Vector2i(0, -1)] = true
					break


func _is_valid_candle_base(cell: Vector2i, center: Vector2i) -> bool:
	if cell.distance_squared_to(center) <= 6:
		return false
	var top_cell: Vector2i = cell + Vector2i(0, -1)
	if not is_floor(cell) or not is_floor(top_cell) or not is_floor(top_cell + Vector2i(0, -1)):
		return false
	return not _is_near_pillar(cell, 1) and not _is_near_pillar(top_cell, 1)


func _is_near_pillar(cell: Vector2i, margin: int) -> bool:
	for p: Rect2i in _all_pillars:
		if p.grow(margin).has_point(cell):
			return true
	return false


func has_candle_post_near(cell: Vector2i, radius_sq: int = 81) -> bool:
	return _has_cell_near(cell, _candle_post_tops, radius_sq)


static func _has_cell_near(cell: Vector2i, lookup: Dictionary, radius_sq: int) -> bool:
	var r: int = int(ceilf(sqrt(float(radius_sq))))
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			if dx * dx + dy * dy <= radius_sq:
				if lookup.has(cell + Vector2i(dx, dy)):
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
	_corridor_rects.append(rect)
	_corridor_segments.append({&"is_horizontal": true, &"min": min_x, &"max": max_x, &"fixed": y, &"half_width": half_width})


func _add_vertical_corridor_rect(y_start: int, y_end: int, x: int, half_width: int) -> void:
	var min_y: int = mini(y_start, y_end)
	var max_y: int = maxi(y_start, y_end)
	var rect: Rect2i = Rect2i(x - half_width, min_y, half_width * 2 + 1, (max_y - min_y) + 1)
	_add_carve_rect(rect)
	_corridor_rects.append(rect)
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
			_try_add_horizontal_bridge(rect_a, rect_b, bridges_to_add)
			_try_add_horizontal_bridge(rect_b, rect_a, bridges_to_add)
			_try_add_vertical_bridge(rect_a, rect_b, bridges_to_add)
			_try_add_vertical_bridge(rect_b, rect_a, bridges_to_add)

	for bridge: Rect2i in bridges_to_add:
		if not _intersects_any_rect(bridge, _all_pillars) and not _intersects_any_rect(bridge, _cut_corner_rects):
			_add_carve_rect(bridge)


static func _intersects_any_rect(rect: Rect2i, rects: Array[Rect2i]) -> bool:
	for other: Rect2i in rects:
		if rect.intersects(other):
			return true
	return false


static func _try_add_horizontal_bridge(left_rect: Rect2i, right_rect: Rect2i, bridges: Array[Rect2i]) -> void:
	var gap: int = right_rect.position.x - left_rect.end.x
	if gap <= 0 or gap > 2:
		return
	var ov_y_start: int = maxi(left_rect.position.y, right_rect.position.y)
	var ov_y_end: int = mini(left_rect.end.y, right_rect.end.y)
	if ov_y_end > ov_y_start:
		bridges.append(Rect2i(left_rect.end.x, ov_y_start, gap, ov_y_end - ov_y_start))


static func _try_add_vertical_bridge(top_rect: Rect2i, bottom_rect: Rect2i, bridges: Array[Rect2i]) -> void:
	var gap: int = bottom_rect.position.y - top_rect.end.y
	if gap <= 0 or gap > 2:
		return
	var ov_x_start: int = maxi(top_rect.position.x, bottom_rect.position.x)
	var ov_x_end: int = mini(top_rect.end.x, bottom_rect.end.x)
	if ov_x_end > ov_x_start:
		bridges.append(Rect2i(ov_x_start, top_rect.end.y, ov_x_end - ov_x_start, gap))


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
	var bonus: int = mini((depth - 4) * 2, 10)
	return TIER_1_MIN_SIZE if depth <= 1 else (TIER_2_MIN_SIZE if depth <= 3 else TIER_3_MIN_SIZE + Vector2i(bonus, bonus))


func _get_max_size_for_depth(depth: int) -> Vector2i:
	var bonus: int = mini((depth - 4) * 3, 12)
	return TIER_1_MAX_SIZE if depth <= 1 else (TIER_2_MAX_SIZE if depth <= 3 else TIER_3_MAX_SIZE + Vector2i(bonus, bonus))


func _get_step_distance_for_depth(depth: int) -> Vector2:
	var bonus: float = minf(float(depth - 4) * 3.0, 16.0)
	return TIER_1_DISTANCE_RANGE if depth <= 1 else (TIER_2_DISTANCE_RANGE if depth <= 3 else TIER_3_DISTANCE_RANGE + Vector2(bonus, bonus))


func _plan_spike_traps() -> void:
	for room: Rect2i in rooms:
		_plan_room_spike_traps(room)
	_plan_corridor_spike_traps()


func _plan_room_spike_traps(room: Rect2i) -> void:
	var depth: int = get_room_depth(room)
	if depth <= 0:
		return

	var chance: float = 0.80 if depth >= 4 else (0.60 if depth >= 2 else 0.35)
	var max_patches: int = _rng.randi_range(2, 3) if depth >= 4 else (_rng.randi_range(1, 2) if depth >= 2 else 1)
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
	var anchors: Array[Vector2i] = [Vector2i(qx1, qy1), Vector2i(qx2, qy1), Vector2i(qx1, qy2), Vector2i(qx2, qy2)]
	for i: int in range(anchors.size() - 1, 0, -1):
		var swap_idx: int = _rng.randi_range(0, i)
		var tmp: Vector2i = anchors[i]
		anchors[i] = anchors[swap_idx]
		anchors[swap_idx] = tmp

	var placed: int = 0
	for base_anchor: Vector2i in anchors:
		if placed >= max_patches:
			break
		var anchor: Vector2i = base_anchor + Vector2i(_rng.randi_range(-1, 1), _rng.randi_range(-1, 1))
		if _try_place_spike_patch(anchor, _pick_room_spike_pattern(depth), room):
			placed += 1


func _pick_room_spike_pattern(depth: int) -> Array[Vector2i]:
	var roll: float = _rng.randf()
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
	var sx: int = -1 if _rng.randf() < 0.5 else 1
	var zigzag: Array[Vector2i] = [Vector2i(-sx, -1), Vector2i(0, -1), Vector2i(0, 0), Vector2i(sx, 0), Vector2i(sx, 1), Vector2i(2 * sx, 1)]
	return zigzag


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
		if hero_room.grow(4).has_point(cell) or get_room_at(cell) != Rect2i():
			return
		if not is_floor(cell) or not is_floor(cell + Vector2i(0, -1)) or has_candle_post_near(cell, 6):
			return
		if _has_cell_near(cell, _spike_cells, 9):
			return

	_commit_spike_cells(cells)


func _try_place_spike_patch(anchor: Vector2i, offsets: Array[Vector2i], room: Rect2i) -> bool:
	var cells: Array[Vector2i] = []
	var center: Vector2i = room.get_center()
	var recruits: Array = get_companion_spawns_for_room(room)
	var inner_rect: Rect2i = room.grow(-3)

	for offset: Vector2i in offsets:
		var cell: Vector2i = anchor + offset
		if not inner_rect.has_point(cell) or not is_floor(cell) or not is_floor(cell + Vector2i(0, -1)):
			return false
		if cell.distance_squared_to(center) < 25 or has_candle_post_near(cell, 6) or _has_cell_near(cell, _spike_cells, 25):
			return false
		for r_var: Variant in recruits:
			if r_var is Vector2i:
				var r_cell: Vector2i = r_var
				if cell.distance_squared_to(r_cell) < 25:
					return false
		cells.append(cell)

	_commit_spike_cells(cells)
	return true


func _commit_spike_cells(cells: Array[Vector2i]) -> void:
	var group_id: int = _next_spike_group % SPIKE_PHASE_GROUPS
	_next_spike_group += 1
	for cell: Vector2i in cells:
		_spike_cells[cell] = group_id
