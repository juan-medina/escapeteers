# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Map
extends Node2D

signal generation_progress_updated(progress: float, stage_name: StringName)

const TILE_SET_SOURCE_ID: int = 4

const FLOOR_ATLAS_START: Vector2i = Vector2i(10, 14)
const FLOOR_ATLAS_SIZE: Vector2i = Vector2i(6, 3)

const WALL_TOP_LEFT_OUTER: Vector2i = Vector2i(2, 11)
const WALL_TOP_RIGHT_OUTER: Vector2i = Vector2i(5, 11)
const WALL_TOP_LEFT_INNER: Vector2i = Vector2i(2, 12)
const WALL_TOP_RIGHT_INNER: Vector2i = Vector2i(5, 12)
const WALL_TOP_VARIANTS: Array[Vector2i] = [Vector2i(3, 11), Vector2i(4, 11)]

const WALL_BOTTOM_LEFT_OUTER: Vector2i = Vector2i(0, 16)
const WALL_BOTTOM_RIGHT_OUTER: Vector2i = Vector2i(7, 16)
const WALL_BOTTOM_LEFT_INNER: Vector2i = Vector2i(1, 16)
const WALL_BOTTOM_RIGHT_INNER: Vector2i = Vector2i(6, 16)
const WALL_BOTTOM_VARIANTS: Array[Vector2i] = [Vector2i(3, 18), Vector2i(4, 18)]

const WALL_LEFT_VARIANTS: Array[Vector2i] = [Vector2i(0, 14), Vector2i(0, 15)]
const WALL_RIGHT_VARIANTS: Array[Vector2i] = [Vector2i(7, 14), Vector2i(7, 15)]

const TORCH_TOP: Vector2i = Vector2i(12, 20)
const TORCH_SIDE: Vector2i = Vector2i(12, 19)
const TORCH_RIGHT_ALT_ID: int = 1
const TORCH_SPAWN_CHANCE: float = 0.1
const MIN_TORCH_DISTANCE_SQUARED: int = 36

const CANDLE_POST_TOP: Vector2i = Vector2i(10, 30)
const CANDLE_POST_BOTTOM: Vector2i = Vector2i(10, 31)

const PROP_BARREL: Vector2i = Vector2i(4, 28)
const PROP_BOX: Vector2i = Vector2i(4, 29)
const PROP_SKULLS_AND_BONES: Array[Vector2i] = [Vector2i(5, 29), Vector2i(6, 29), Vector2i(7, 29), Vector2i(8, 29)]
const CORRIDOR_BONE_CHANCE: float = 0.02

const HERO_ROOM_SIZE: Vector2i = Vector2i(30, 30)
const INITIAL_ROOM_COUNT: int = 5
const ROOM_PADDING: int = 8
const CORRIDOR_WIDTH: int = 4
const MAX_PLACEMENT_ATTEMPTS: int = 120
const EXPAND_TRIGGER_DISTANCE_TILES: float = 75.0
const LOOP_CONNECT_MAX_DISTANCE: float = 95.0
const LOOP_CONNECT_CHANCE: float = 0.45

const TIER_1_MIN_SIZE: Vector2i = Vector2i(24, 24)
const TIER_1_MAX_SIZE: Vector2i = Vector2i(33, 33)
const TIER_1_DISTANCE_RANGE: Vector2 = Vector2(45.0, 80.0)

const TIER_2_MIN_SIZE: Vector2i = Vector2i(36, 36)
const TIER_2_MAX_SIZE: Vector2i = Vector2i(48, 48)
const TIER_2_DISTANCE_RANGE: Vector2 = Vector2(58.0, 95.0)

const TIER_3_MIN_SIZE: Vector2i = Vector2i(56, 56)
const TIER_3_MAX_SIZE: Vector2i = Vector2i(76, 76)
const TIER_3_DISTANCE_RANGE: Vector2 = Vector2(75.0, 115.0)

@export var debug_seed: int = 0

var hero_room: Rect2i = Rect2i()
var companion_rooms: Array[Rect2i] = []

var _astar: AStarGrid2D = AStarGrid2D.new()
var _cells: Dictionary[Vector2i, bool] = {}
var _walkable_cells: Dictionary[Vector2i, bool] = {}
var _placed_torches: Array[Vector2i] = []
var _torch_nodes: Dictionary[Vector2i, TorchLight] = {}
var _room_depths: Dictionary[Rect2i, int] = {}
var _expanded_rooms: Dictionary[Rect2i, bool] = {}
var _decorated_rooms: Dictionary[Rect2i, bool] = {}

@onready var _floor: TileMapLayer = $Floor
@onready var _walls: TileMapLayer = $Walls
@onready var _decorations: TileMapLayer = $Decorations
@onready var _lights: Node2D = $Lights


func _ready() -> void:
	y_sort_enabled = true
	_walls.y_sort_enabled = true
	_decorations.y_sort_enabled = true
	_floor.z_index = -1
	if _walls.tile_set == null:
		_walls.tile_set = _floor.tile_set
	if _decorations.tile_set == null:
		_decorations.tile_set = _floor.tile_set


func get_active_light_count() -> int:
	return _torch_nodes.size()


func get_hero_spawn_position() -> Vector2:
	return _floor.map_to_local(hero_room.get_center())


func map_to_local(cell: Vector2i) -> Vector2:
	return _floor.map_to_local(cell)


func local_to_map(world_pos: Vector2) -> Vector2i:
	return _floor.local_to_map(world_pos)


func get_room_depth(room: Rect2i) -> int:
	if _room_depths.has(room):
		return _room_depths[room]
	var center_dist: float = Vector2(room.get_center()).length()
	return maxi(1, int(center_dist / 65.0))


func get_room_tier(room: Rect2i) -> int:
	var depth: int = get_room_depth(room)
	if depth <= 1:
		return 1
	if depth <= 3:
		return 2
	return 3


func get_starter_companion_spawn_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var hero_center: Vector2i = hero_room.get_center()
	for offset_x: int in [-1, 1]:
		var recruit_cell: Vector2i = hero_center + Vector2i(offset_x, 0)
		if is_cell_walkable(recruit_cell):
			positions.append(_floor.map_to_local(recruit_cell))
	return positions


func get_companion_spawn_positions_for_room(room: Rect2i) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var center_cell: Vector2i = room.get_center()
	var tier: int = get_room_tier(room)

	if tier == 1:
		positions.append(_floor.map_to_local(center_cell))
		if randf() > 0.6:
			var offset: Vector2i = Vector2i(randi_range(-1, 1), randi_range(-1, 1))
			if offset != Vector2i.ZERO and is_cell_walkable(center_cell + offset):
				positions.append(_floor.map_to_local(center_cell + offset))
	elif tier == 2:
		positions.append(_floor.map_to_local(center_cell))
		for _k: int in range(2):
			var offset: Vector2i = Vector2i(randi_range(-2, 2), randi_range(-2, 2))
			if offset != Vector2i.ZERO and is_cell_walkable(center_cell + offset):
				positions.append(_floor.map_to_local(center_cell + offset))
	else:
		positions.append(_floor.map_to_local(center_cell))
		var extra_recruits: int = clampi(1 + int(float(get_room_depth(room)) * 0.5), 2, 4)
		for _k: int in range(extra_recruits):
			var offset: Vector2i = Vector2i(randi_range(-3, 3), randi_range(-3, 3))
			if offset != Vector2i.ZERO and is_cell_walkable(center_cell + offset):
				positions.append(_floor.map_to_local(center_cell + offset))

	return positions


func get_companion_spawn_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = get_starter_companion_spawn_positions()
	for room: Rect2i in companion_rooms:
		positions.append_array(get_companion_spawn_positions_for_room(room))
	return positions


func get_room_enemy_quota(room: Rect2i) -> int:
	var depth: int = get_room_depth(room)
	var area_factor: float = float(room.size.x * room.size.y) / (28.0 * 28.0)
	var base_min: int = 5 + (depth - 1) * 6
	var base_max: int = 8 + (depth - 1) * 9
	var scaled_min: int = int(roundf(float(base_min) * clampf(area_factor * 0.65, 0.8, 2.6)))
	var scaled_max: int = int(roundf(float(base_max) * clampf(area_factor * 0.65, 0.8, 2.6)))
	return clampi(randi_range(scaled_min, maxi(scaled_min, scaled_max)), 5, 65)


func get_enemy_spawn_positions_for_room(room: Rect2i, count: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var center: Vector2i = room.get_center()
	var attempts: int = 0
	var max_attempts: int = count * 6

	while positions.size() < count and attempts < max_attempts:
		attempts += 1
		var cell: Vector2i = Vector2i(
			randi_range(room.position.x + 1, room.position.x + room.size.x - 2), randi_range(room.position.y + 1, room.position.y + room.size.y - 2)
		)
		if is_cell_walkable(cell) and cell.distance_squared_to(center) >= 2:
			positions.append(_floor.map_to_local(cell))

	if positions.is_empty() and is_cell_walkable(center):
		positions.append(_floor.map_to_local(center))

	return positions


func is_cell_walkable(cell: Vector2i) -> bool:
	return _walkable_cells.has(cell)


func clamp_to_walkable(world_pos: Vector2) -> Vector2:
	var cell: Vector2i = _floor.local_to_map(world_pos)
	if is_cell_walkable(cell):
		return world_pos
	var closest_cell: Vector2i = _find_closest_walkable_cell(cell)
	return _floor.map_to_local(closest_cell)


func get_navigation_path(from_pos: Vector2, to_pos: Vector2) -> PackedVector2Array:
	if _astar == null:
		return PackedVector2Array()

	var from_cell: Vector2i = _floor.local_to_map(from_pos)
	var to_cell: Vector2i = _floor.local_to_map(to_pos)

	if not _astar.is_in_boundsv(from_cell) or not _astar.is_in_boundsv(to_cell):
		return PackedVector2Array()

	if _astar.is_point_solid(from_cell):
		from_cell = _find_closest_walkable_cell(from_cell)

	if _astar.is_point_solid(to_cell):
		to_cell = _find_closest_walkable_cell(to_cell)

	if from_cell == to_cell:
		return PackedVector2Array([to_pos])

	var cell_path: Array[Vector2i] = _astar.get_id_path(from_cell, to_cell)
	if cell_path.is_empty():
		return PackedVector2Array()

	var world_path: PackedVector2Array = PackedVector2Array()
	for cell: Vector2i in cell_path:
		world_path.append(_floor.map_to_local(cell))

	if not world_path.is_empty():
		world_path[world_path.size() - 1] = clamp_to_walkable(to_pos)

	return world_path


func generate_map() -> void:
	if debug_seed != 0:
		seed(debug_seed)
		print(&"[Map] Seed set to debug_seed: %d" % debug_seed)

	generation_progress_updated.emit(0.15, &"Surveying primal chamber...")
	await get_tree().process_frame

	_floor.clear()
	_walls.clear()
	_decorations.clear()
	_clear_lights()
	companion_rooms.clear()
	_cells.clear()
	_walkable_cells.clear()
	_placed_torches.clear()
	_torch_nodes.clear()
	_room_depths.clear()
	_expanded_rooms.clear()
	_decorated_rooms.clear()

	_create_hero_room()
	_create_initial_rooms()

	generation_progress_updated.emit(0.45, &"Carving starting passages...")
	await get_tree().process_frame

	_eliminate_narrow_gaps_in_rect(_get_cells_bounds(_cells).grow(4))

	generation_progress_updated.emit(0.70, &"Raising fortified walls...")
	await get_tree().process_frame

	var initial_rooms: Array[Rect2i] = [hero_room]
	initial_rooms.append_array(companion_rooms)
	_rebuild_region(_get_cells_bounds(_cells).grow(4), initial_rooms)

	generation_progress_updated.emit(0.90, &"Lighting dungeon torches...")
	await get_tree().process_frame


func expand_frontier_near(player_world_pos: Vector2) -> Array[Rect2i]:
	var player_cell: Vector2i = _floor.local_to_map(player_world_pos)
	var trigger_dist_sq: float = EXPAND_TRIGGER_DISTANCE_TILES * EXPAND_TRIGGER_DISTANCE_TILES

	var best_room: Rect2i = Rect2i()
	var best_dist_sq: float = INF
	var found: bool = false

	for room: Rect2i in companion_rooms:
		if _expanded_rooms.has(room):
			continue
		var dist_sq: float = Vector2(player_cell).distance_squared_to(Vector2(room.get_center()))
		if dist_sq <= trigger_dist_sq and dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_room = room
			found = true

	if not found:
		return []

	_expanded_rooms[best_room] = true
	return _expand_from_room(best_room)


func _create_hero_room() -> void:
	var top_left: Vector2i = Vector2i(Vector2(-HERO_ROOM_SIZE) * 0.5)
	hero_room = Rect2i(top_left, HERO_ROOM_SIZE)
	_room_depths[hero_room] = 0
	_expanded_rooms[hero_room] = true
	_carve_room(hero_room, _cells)


func _create_initial_rooms() -> void:
	var placed: int = 0
	var attempts: int = 0
	var base_angle_step: float = TAU / float(INITIAL_ROOM_COUNT)

	while placed < INITIAL_ROOM_COUNT and attempts < MAX_PLACEMENT_ATTEMPTS * 4:
		attempts += 1
		var slot_angle: float = float(placed) * base_angle_step + randf_range(-0.45, 0.45)
		var distance: float = randf_range(TIER_1_DISTANCE_RANGE.x, TIER_1_DISTANCE_RANGE.y)
		var size: Vector2i = Vector2i(randi_range(TIER_1_MIN_SIZE.x, TIER_1_MAX_SIZE.x), randi_range(TIER_1_MIN_SIZE.y, TIER_1_MAX_SIZE.y))
		var center_pos: Vector2 = Vector2.from_angle(slot_angle) * distance
		var top_left: Vector2i = Vector2i(center_pos.round()) - Vector2i(Vector2(size) * 0.5)
		var candidate_room: Rect2i = Rect2i(top_left, size)

		if _overlaps_any_room(candidate_room):
			continue

		companion_rooms.append(candidate_room)
		_room_depths[candidate_room] = 1
		_carve_room(candidate_room, _cells)
		_carve_corridor(hero_room.get_center(), candidate_room.get_center(), _cells)
		placed += 1

	for i: int in range(companion_rooms.size()):
		var next_idx: int = (i + 1) % companion_rooms.size()
		if i != next_idx and randf() <= 0.5:
			var center_a: Vector2i = companion_rooms[i].get_center()
			var center_b: Vector2i = companion_rooms[next_idx].get_center()
			if Vector2(center_a).distance_to(Vector2(center_b)) <= LOOP_CONNECT_MAX_DISTANCE:
				_carve_corridor(center_a, center_b, _cells)


func _expand_from_room(source_room: Rect2i) -> Array[Rect2i]:
	var start_usec: int = Time.get_ticks_usec()
	var parent_depth: int = get_room_depth(source_room)
	var child_depth: int = parent_depth + 1
	var target_branches: int = randi_range(1, 2)
	var new_rooms: Array[Rect2i] = []

	var source_center: Vector2 = Vector2(source_room.get_center())
	var outward_angle: float = source_center.angle()
	var dirty_rect: Rect2i = source_room

	var min_size: Vector2i = _get_min_size_for_depth(child_depth)
	var max_size: Vector2i = _get_max_size_for_depth(child_depth)
	var dist_range: Vector2 = _get_step_distance_for_depth(child_depth)

	var attempts: int = 0
	while new_rooms.size() < target_branches and attempts < MAX_PLACEMENT_ATTEMPTS:
		attempts += 1
		var branch_spread: float = randf_range(-1.15, 1.15)
		var angle: float = outward_angle + branch_spread
		var step_dist: float = randf_range(dist_range.x, dist_range.y)
		var size: Vector2i = Vector2i(randi_range(min_size.x, max_size.x), randi_range(min_size.y, max_size.y))
		var center_pos: Vector2 = source_center + Vector2.from_angle(angle) * step_dist
		var top_left: Vector2i = Vector2i(center_pos.round()) - Vector2i(Vector2(size) * 0.5)
		var candidate: Rect2i = Rect2i(top_left, size)

		if _overlaps_any_room(candidate):
			continue

		companion_rooms.append(candidate)
		_room_depths[candidate] = child_depth
		new_rooms.append(candidate)

		_carve_room(candidate, _cells)
		_carve_corridor(source_room.get_center(), candidate.get_center(), _cells)
		dirty_rect = dirty_rect.merge(candidate)

		# Optionally create a loop corridor to an existing nearby room
		for other_room: Rect2i in companion_rooms:
			if other_room == candidate or other_room == source_room:
				continue
			var d: float = Vector2(candidate.get_center()).distance_to(Vector2(other_room.get_center()))
			if d <= LOOP_CONNECT_MAX_DISTANCE and randf() <= LOOP_CONNECT_CHANCE:
				_carve_corridor(candidate.get_center(), other_room.get_center(), _cells)
				dirty_rect = dirty_rect.merge(other_room)
				break

	if not new_rooms.is_empty():
		var padded_dirty: Rect2i = dirty_rect.grow(8)
		_eliminate_narrow_gaps_in_rect(padded_dirty)
		_rebuild_region(padded_dirty, new_rooms)

	_log_perf(&"_expand_from_room", start_usec, " (depth: %d, new_rooms: %d)" % [child_depth, new_rooms.size()])

	return new_rooms


func _get_min_size_for_depth(depth: int) -> Vector2i:
	if depth <= 1:
		return TIER_1_MIN_SIZE
	if depth <= 3:
		return TIER_2_MIN_SIZE
	var bonus: int = mini((depth - 4) * 4, 20)
	return TIER_3_MIN_SIZE + Vector2i(bonus, bonus)


func _get_max_size_for_depth(depth: int) -> Vector2i:
	if depth <= 1:
		return TIER_1_MAX_SIZE
	if depth <= 3:
		return TIER_2_MAX_SIZE
	var bonus: int = mini((depth - 4) * 5, 24)
	return TIER_3_MAX_SIZE + Vector2i(bonus, bonus)


func _get_step_distance_for_depth(depth: int) -> Vector2:
	if depth <= 1:
		return TIER_1_DISTANCE_RANGE
	if depth <= 3:
		return TIER_2_DISTANCE_RANGE
	var bonus: float = minf(float(depth - 4) * 6.0, 30.0)
	return TIER_3_DISTANCE_RANGE + Vector2(bonus, bonus)


func _get_cells_bounds(cells: Dictionary[Vector2i, bool]) -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var min_c: Vector2i = Vector2i(2147483647, 2147483647)
	var max_c: Vector2i = Vector2i(-2147483648, -2147483648)
	for c: Vector2i in cells:
		min_c.x = mini(min_c.x, c.x)
		min_c.y = mini(min_c.y, c.y)
		max_c.x = maxi(max_c.x, c.x)
		max_c.y = maxi(max_c.y, c.y)
	return Rect2i(min_c, (max_c - min_c) + Vector2i.ONE)


func _rebuild_region(region: Rect2i, rooms_to_decorate: Array[Rect2i]) -> void:
	var start_usec: int = Time.get_ticks_usec()
	var work_rect: Rect2i = region.grow(2)

	# 1. Clear walls and wall torches inside work_rect; place floors for new floor cells
	for x: int in range(work_rect.position.x, work_rect.end.x):
		for y: int in range(work_rect.position.y, work_rect.end.y):
			var cell: Vector2i = Vector2i(x, y)
			_walls.erase_cell(cell)

			var existing_decor: Vector2i = _decorations.get_cell_atlas_coords(cell)
			if existing_decor == TORCH_TOP or existing_decor == TORCH_SIDE:
				_decorations.erase_cell(cell)
				_remove_torch_at(cell)

			if _cells.has(cell):
				if _floor.get_cell_source_id(cell) == -1:
					_floor.set_cell(cell, TILE_SET_SOURCE_ID, _get_random_floor_atlas_coords())
				# If a corridor carved through an existing prop/candle, clear it
				if not _is_inside_any_room(cell):
					if existing_decor == PROP_BARREL or existing_decor == PROP_BOX:
						_decorations.erase_cell(cell)

	# 2. Rebuild walls in work_rect
	var walls_placed: Dictionary[Vector2i, bool] = {}
	_create_top_walls_in_rect(work_rect, walls_placed)
	_create_bottom_walls_in_rect(work_rect, walls_placed)
	_create_vertical_walls_in_rect(work_rect, walls_placed)

	# 3. Clear any floor decoration that is now covered by a wall
	for x: int in range(work_rect.position.x, work_rect.end.x):
		for y: int in range(work_rect.position.y, work_rect.end.y):
			var cell: Vector2i = Vector2i(x, y)
			if _walls.get_cell_source_id(cell) != -1:
				var decor: Vector2i = _decorations.get_cell_atlas_coords(cell)
				if decor != TORCH_TOP:
					_decorations.erase_cell(cell)
					_remove_torch_at(cell)

	# 4. Place torches & decorations for newly added rooms and region
	var new_torches: Array[Vector2i] = []
	_place_wall_torches_in_rect(work_rect, new_torches)
	_ensure_room_torches_for_rooms(rooms_to_decorate, new_torches)
	_place_candle_posts_for_rooms(rooms_to_decorate, new_torches)
	_place_room_props_for_rooms(rooms_to_decorate)
	_place_corridor_bones_in_rect(work_rect)
	_spawn_torch_lights(new_torches)

	for room: Rect2i in rooms_to_decorate:
		_decorated_rooms[room] = true

	# 5. Refresh navigation
	_setup_navigation(_cells)

	_log_perf(&"_rebuild_region", start_usec, " (region: %s, rooms: %d)" % [str(region), rooms_to_decorate.size()])


func _remove_torch_at(cell: Vector2i) -> void:
	var idx: int = _placed_torches.find(cell)
	if idx != -1:
		_placed_torches.remove_at(idx)
	if _torch_nodes.has(cell):
		var node: TorchLight = _torch_nodes[cell]
		if is_instance_valid(node):
			node.queue_free()
		_torch_nodes.erase(cell)


func _find_closest_walkable_cell(target_cell: Vector2i) -> Vector2i:
	if is_cell_walkable(target_cell):
		return target_cell

	for r: int in range(1, 6):
		for dx: int in range(-r, r + 1):
			for dy: int in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var candidate: Vector2i = target_cell + Vector2i(dx, dy)
				if is_cell_walkable(candidate):
					return candidate

	return target_cell


func _setup_navigation(cells: Dictionary[Vector2i, bool]) -> void:
	var start_usec: int = Time.get_ticks_usec()
	_walkable_cells.clear()
	for c: Vector2i in cells:
		if _walls.get_cell_source_id(c) == -1:
			var decor_tile: Vector2i = _decorations.get_cell_atlas_coords(c)
			if decor_tile == PROP_BARREL or decor_tile == PROP_BOX:
				continue
			_walkable_cells[c] = true

	if _walkable_cells.is_empty():
		return

	var min_c: Vector2i = Vector2i(2147483647, 2147483647)
	var max_c: Vector2i = Vector2i(-2147483648, -2147483648)
	for c: Vector2i in _walkable_cells:
		min_c.x = mini(min_c.x, c.x)
		min_c.y = mini(min_c.y, c.y)
		max_c.x = maxi(max_c.x, c.x)
		max_c.y = maxi(max_c.y, c.y)

	var margin: int = 4
	var region_rect: Rect2i = Rect2i(min_c - Vector2i(margin, margin), (max_c - min_c) + Vector2i(margin * 2, margin * 2))

	_astar.region = region_rect
	_astar.cell_size = Vector2(16, 16)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.jumping_enabled = true
	_astar.update()

	_astar.fill_solid_region(region_rect, true)
	for c: Vector2i in _walkable_cells:
		_astar.set_point_solid(c, false)

	_log_perf(&"_setup_navigation", start_usec, " (walkable: %d, region: %s)" % [_walkable_cells.size(), str(_astar.region)])


func _overlaps_any_room(candidate: Rect2i) -> bool:
	if hero_room.grow(ROOM_PADDING).intersects(candidate):
		return true

	for room: Rect2i in companion_rooms:
		if room.grow(ROOM_PADDING).intersects(candidate):
			return true

	return false


func _carve_room(room: Rect2i, cells: Dictionary[Vector2i, bool]) -> void:
	for x: int in range(room.position.x, room.position.x + room.size.x):
		for y: int in range(room.position.y, room.position.y + room.size.y):
			cells[Vector2i(x, y)] = true


func _carve_corridor(from: Vector2i, to: Vector2i, cells: Dictionary[Vector2i, bool]) -> void:
	var half_width: int = int(float(CORRIDOR_WIDTH) * 0.5)
	if randf() <= 0.5:
		_carve_horizontal_line(from.x, to.x, from.y, half_width, cells)
		_carve_vertical_line(from.y, to.y, to.x, half_width, cells)
	else:
		_carve_vertical_line(from.y, to.y, from.x, half_width, cells)
		_carve_horizontal_line(from.x, to.x, to.y, half_width, cells)


func _eliminate_narrow_gaps_in_rect(region: Rect2i) -> void:
	var start_usec: int = Time.get_ticks_usec()
	var changed: bool = true
	var pass_count: int = 0

	while changed and pass_count < 6:
		pass_count += 1
		changed = false
		var candidates: Dictionary[Vector2i, bool] = {}

		for x: int in range(region.position.x, region.end.x):
			for y: int in range(region.position.y, region.end.y):
				var f: Vector2i = Vector2i(x, y)
				if not _cells.has(f):
					continue
				for dx: int in range(-2, 3):
					for dy: int in range(-2, 3):
						var p: Vector2i = f + Vector2i(dx, dy)
						if not _cells.has(p) and region.has_point(p):
							candidates[p] = true

		var to_add: Array[Vector2i] = []
		for p: Vector2i in candidates:
			var h_gap: bool = (
				(_cells.has(p + Vector2i(-1, 0)) or _cells.has(p + Vector2i(-2, 0)))
				and (_cells.has(p + Vector2i(1, 0)) or _cells.has(p + Vector2i(2, 0)))
			)
			var v_gap: bool = (
				(_cells.has(p + Vector2i(0, -1)) or _cells.has(p + Vector2i(0, -2)))
				and (_cells.has(p + Vector2i(0, 1)) or _cells.has(p + Vector2i(0, 2)))
			)
			if h_gap or v_gap:
				to_add.append(p)
				changed = true

		for p: Vector2i in to_add:
			_cells[p] = true

	_log_perf(&"_eliminate_narrow_gaps_in_rect", start_usec, " (region: %s, passes: %d)" % [str(region), pass_count])


func _carve_horizontal_line(x_start: int, x_end: int, y: int, half_width: int, cells: Dictionary[Vector2i, bool]) -> void:
	var min_x: int = mini(x_start, x_end)
	var max_x: int = maxi(x_start, x_end)

	for x: int in range(min_x, max_x + 1):
		for offset: int in range(-half_width, half_width + 1):
			cells[Vector2i(x, y + offset)] = true


func _carve_vertical_line(y_start: int, y_end: int, x: int, half_width: int, cells: Dictionary[Vector2i, bool]) -> void:
	var min_y: int = mini(y_start, y_end)
	var max_y: int = maxi(y_start, y_end)

	for y: int in range(min_y, max_y + 1):
		for offset: int in range(-half_width, half_width + 1):
			cells[Vector2i(x + offset, y)] = true


func _create_top_walls_in_rect(region: Rect2i, walls_placed: Dictionary[Vector2i, bool]) -> void:
	for x: int in range(region.position.x, region.end.x):
		for y: int in range(region.position.y, region.end.y):
			var f: Vector2i = Vector2i(x, y)
			if not _cells.has(f) or _cells.has(f + Vector2i(0, -1)):
				continue

			var has_ne: bool = _cells.has(f + Vector2i(1, -1))
			var has_nw: bool = _cells.has(f + Vector2i(-1, -1))
			var has_w: bool = _cells.has(f + Vector2i(-1, 0))
			var has_e: bool = _cells.has(f + Vector2i(1, 0))

			if has_ne and not has_w:
				_walls.set_cell(f, TILE_SET_SOURCE_ID, WALL_TOP_LEFT_INNER)
			elif has_nw and not has_e:
				_walls.set_cell(f, TILE_SET_SOURCE_ID, WALL_TOP_RIGHT_INNER)
			else:
				_walls.set_cell(f, TILE_SET_SOURCE_ID, _pick_random_tile(WALL_TOP_VARIANTS))

			var left_cell: Vector2i = f + Vector2i(-1, 0)
			if not _cells.has(left_cell) and not walls_placed.has(left_cell):
				_walls.set_cell(left_cell, TILE_SET_SOURCE_ID, WALL_TOP_LEFT_OUTER)
				walls_placed[left_cell] = true

			var right_cell: Vector2i = f + Vector2i(1, 0)
			if not _cells.has(right_cell) and not walls_placed.has(right_cell):
				_walls.set_cell(right_cell, TILE_SET_SOURCE_ID, WALL_TOP_RIGHT_OUTER)
				walls_placed[right_cell] = true


func _create_bottom_walls_in_rect(region: Rect2i, walls_placed: Dictionary[Vector2i, bool]) -> void:
	for x: int in range(region.position.x, region.end.x):
		for y: int in range(region.position.y, region.end.y):
			var f: Vector2i = Vector2i(x, y)
			if not _cells.has(f) or _cells.has(f + Vector2i(0, 1)):
				continue

			var bottom_cell: Vector2i = f + Vector2i(0, 1)
			if not walls_placed.has(bottom_cell) and not _cells.has(bottom_cell):
				var has_e: bool = _cells.has(bottom_cell + Vector2i(1, 0))
				var has_w: bool = _cells.has(bottom_cell + Vector2i(-1, 0))

				if has_e and not has_w:
					_walls.set_cell(bottom_cell, TILE_SET_SOURCE_ID, WALL_BOTTOM_LEFT_INNER)
				elif has_w and not has_e:
					_walls.set_cell(bottom_cell, TILE_SET_SOURCE_ID, WALL_BOTTOM_RIGHT_INNER)
				else:
					_walls.set_cell(bottom_cell, TILE_SET_SOURCE_ID, _pick_random_tile(WALL_BOTTOM_VARIANTS))

				walls_placed[bottom_cell] = true

			var bl_cell: Vector2i = f + Vector2i(-1, 1)
			if not _cells.has(bl_cell) and not _cells.has(f + Vector2i(-1, 0)) and not walls_placed.has(bl_cell):
				_walls.set_cell(bl_cell, TILE_SET_SOURCE_ID, WALL_BOTTOM_LEFT_OUTER)
				walls_placed[bl_cell] = true

			var br_cell: Vector2i = f + Vector2i(1, 1)
			if not _cells.has(br_cell) and not _cells.has(f + Vector2i(1, 0)) and not walls_placed.has(br_cell):
				_walls.set_cell(br_cell, TILE_SET_SOURCE_ID, WALL_BOTTOM_RIGHT_OUTER)
				walls_placed[br_cell] = true


func _create_vertical_walls_in_rect(region: Rect2i, walls_placed: Dictionary[Vector2i, bool]) -> void:
	for x: int in range(region.position.x, region.end.x):
		for y: int in range(region.position.y, region.end.y):
			var f: Vector2i = Vector2i(x, y)
			if not _cells.has(f):
				continue

			var left_cell: Vector2i = f + Vector2i(-1, 0)
			if not _cells.has(left_cell) and not walls_placed.has(left_cell):
				_walls.set_cell(left_cell, TILE_SET_SOURCE_ID, _pick_random_tile(WALL_LEFT_VARIANTS))
				walls_placed[left_cell] = true

			var right_cell: Vector2i = f + Vector2i(1, 0)
			if not _cells.has(right_cell) and not walls_placed.has(right_cell):
				_walls.set_cell(right_cell, TILE_SET_SOURCE_ID, _pick_random_tile(WALL_RIGHT_VARIANTS))
				walls_placed[right_cell] = true


func _pick_random_tile(tiles: Array[Vector2i]) -> Vector2i:
	return tiles[randi() % tiles.size()]


func _get_random_floor_atlas_coords() -> Vector2i:
	var atlas_x: int = randi_range(FLOOR_ATLAS_START.x, FLOOR_ATLAS_START.x + FLOOR_ATLAS_SIZE.x - 1)
	var atlas_y: int = randi_range(FLOOR_ATLAS_START.y, FLOOR_ATLAS_START.y + FLOOR_ATLAS_SIZE.y - 1)
	return Vector2i(atlas_x, atlas_y)


func _clear_lights() -> void:
	if _lights == null:
		return
	for child: Node in _lights.get_children():
		child.queue_free()


func _place_wall_torches_in_rect(region: Rect2i, new_torches: Array[Vector2i]) -> void:
	for x: int in range(region.position.x, region.end.x):
		for y: int in range(region.position.y, region.end.y):
			var w: Vector2i = Vector2i(x, y)
			if _walls.get_cell_source_id(w) == -1:
				continue
			var atlas: Vector2i = _walls.get_cell_atlas_coords(w)
			if atlas in WALL_TOP_VARIANTS:
				if randf() <= TORCH_SPAWN_CHANCE and _is_far_from_torches(w, _placed_torches):
					_decorations.set_cell(w, TILE_SET_SOURCE_ID, TORCH_TOP)
					_placed_torches.append(w)
					new_torches.append(w)
			elif atlas in WALL_LEFT_VARIANTS:
				var target_cell: Vector2i = w + Vector2i(1, 0)
				var above: Vector2i = _walls.get_cell_atlas_coords(w + Vector2i(0, -1))
				var below: Vector2i = _walls.get_cell_atlas_coords(w + Vector2i(0, 1))
				if (
					(above in WALL_LEFT_VARIANTS or below in WALL_LEFT_VARIANTS)
					and _walls.get_cell_source_id(target_cell) == -1
					and _decorations.get_cell_source_id(target_cell) == -1
					and randf() <= TORCH_SPAWN_CHANCE
					and _is_far_from_torches(target_cell, _placed_torches)
				):
					_decorations.set_cell(target_cell, TILE_SET_SOURCE_ID, TORCH_SIDE, 0)
					_placed_torches.append(target_cell)
					new_torches.append(target_cell)
			elif atlas in WALL_RIGHT_VARIANTS:
				var target_cell: Vector2i = w + Vector2i(-1, 0)
				var above: Vector2i = _walls.get_cell_atlas_coords(w + Vector2i(0, -1))
				var below: Vector2i = _walls.get_cell_atlas_coords(w + Vector2i(0, 1))
				if (
					(above in WALL_RIGHT_VARIANTS or below in WALL_RIGHT_VARIANTS)
					and _walls.get_cell_source_id(target_cell) == -1
					and _decorations.get_cell_source_id(target_cell) == -1
					and randf() <= TORCH_SPAWN_CHANCE
					and _is_far_from_torches(target_cell, _placed_torches)
				):
					_decorations.set_cell(target_cell, TILE_SET_SOURCE_ID, TORCH_SIDE, TORCH_RIGHT_ALT_ID)
					_placed_torches.append(target_cell)
					new_torches.append(target_cell)


func _is_far_from_torches(candidate: Vector2i, placed_torches: Array[Vector2i]) -> bool:
	for torch: Vector2i in placed_torches:
		var dist_sq: int = (candidate.x - torch.x) * (candidate.x - torch.x) + (candidate.y - torch.y) * (candidate.y - torch.y)
		if dist_sq < MIN_TORCH_DISTANCE_SQUARED:
			return false
	return true


func _ensure_room_torches_for_rooms(rooms: Array[Rect2i], new_torches: Array[Vector2i]) -> void:
	for room: Rect2i in rooms:
		if _decorated_rooms.has(room):
			continue
		var top_y: int = room.position.y - 1
		var north_torch_count: int = 0
		for x: int in range(room.position.x, room.position.x + room.size.x):
			if _placed_torches.has(Vector2i(x, top_y)):
				north_torch_count += 1

		var target_count: int = 2 if room.size.x >= 14 else 1
		if north_torch_count < target_count:
			var candidate_x_offsets: Array[float] = []
			if target_count == 1:
				candidate_x_offsets.append(0.5)
			else:
				candidate_x_offsets.append(0.33)
				candidate_x_offsets.append(0.67)
			for offset: float in candidate_x_offsets:
				var target_x: int = room.position.x + int(float(room.size.x) * offset)
				var candidate: Vector2i = Vector2i(target_x, top_y)
				if (
					_walls.get_cell_atlas_coords(candidate) in WALL_TOP_VARIANTS
					and not _placed_torches.has(candidate)
					and _is_far_from_torches(candidate, _placed_torches)
				):
					_decorations.set_cell(candidate, TILE_SET_SOURCE_ID, TORCH_TOP)
					_placed_torches.append(candidate)
					new_torches.append(candidate)
				else:
					for dx: int in range(-2, 3):
						var alt_candidate: Vector2i = Vector2i(target_x + dx, top_y)
						if (
							alt_candidate.x >= room.position.x
							and alt_candidate.x < room.position.x + room.size.x
							and _walls.get_cell_atlas_coords(alt_candidate) in WALL_TOP_VARIANTS
							and not _placed_torches.has(alt_candidate)
							and _is_far_from_torches(alt_candidate, _placed_torches)
						):
							_decorations.set_cell(alt_candidate, TILE_SET_SOURCE_ID, TORCH_TOP)
							_placed_torches.append(alt_candidate)
							new_torches.append(alt_candidate)
							break


func _place_candle_posts_for_rooms(rooms: Array[Rect2i], new_torches: Array[Vector2i]) -> void:
	for room: Rect2i in rooms:
		if _decorated_rooms.has(room):
			continue
		var center: Vector2i = room.get_center()
		var candidate_points: Array[Vector2i] = []

		if room.size.x >= 50 and room.size.y >= 50:
			var qw: int = int(float(room.size.x) * 0.28)
			var qh: int = int(float(room.size.y) * 0.28)
			candidate_points.append(center + Vector2i(-qw, -qh))
			candidate_points.append(center + Vector2i(qw, -qh))
			candidate_points.append(center + Vector2i(-qw, qh))
			candidate_points.append(center + Vector2i(qw, qh))
			candidate_points.append(center + Vector2i(0, -qh))
			candidate_points.append(center + Vector2i(0, qh))
			candidate_points.append(center + Vector2i(-qw, 0))
			candidate_points.append(center + Vector2i(qw, 0))
		elif room.size.x >= 20 and room.size.y >= 20:
			var half_w: int = int(float(room.size.x) * 0.25)
			var half_h: int = int(float(room.size.y) * 0.25)
			candidate_points.append(center + Vector2i(-half_w, -half_h))
			candidate_points.append(center + Vector2i(half_w, -half_h))
			candidate_points.append(center + Vector2i(-half_w, half_h))
			candidate_points.append(center + Vector2i(half_w, half_h))
		else:
			var half_w: int = int(float(room.size.x) * 0.25)
			candidate_points.append(center + Vector2i(-half_w, 0))
			candidate_points.append(center + Vector2i(half_w, 0))

		for base_candidate: Vector2i in candidate_points:
			var placed: bool = false
			for dx: int in range(-1, 2):
				if placed:
					break
				for dy: int in range(-1, 2):
					var base_cell: Vector2i = base_candidate + Vector2i(dx, dy)
					var top_cell: Vector2i = base_cell + Vector2i(0, -1)

					if not _cells.has(base_cell) or not _cells.has(top_cell):
						continue
					if _walls.get_cell_source_id(base_cell) != -1 or _walls.get_cell_source_id(top_cell) != -1:
						continue
					if _decorations.get_cell_source_id(base_cell) != -1 or _decorations.get_cell_source_id(top_cell) != -1:
						continue
					if base_cell.distance_squared_to(center) < 4:
						continue
					if not _is_far_from_torches(top_cell, _placed_torches):
						continue

					_decorations.set_cell(top_cell, TILE_SET_SOURCE_ID, CANDLE_POST_TOP)
					_decorations.set_cell(base_cell, TILE_SET_SOURCE_ID, CANDLE_POST_BOTTOM)
					_placed_torches.append(top_cell)
					new_torches.append(top_cell)
					placed = true
					break


func _spawn_torch_lights(torches_to_spawn: Array[Vector2i]) -> void:
	if _lights == null:
		return
	for cell: Vector2i in torches_to_spawn:
		if _torch_nodes.has(cell) and is_instance_valid(_torch_nodes[cell]):
			continue
		var torch_light: TorchLight = TorchLight.new()
		torch_light.position = _decorations.map_to_local(cell)
		_lights.add_child(torch_light)
		_torch_nodes[cell] = torch_light


func _is_corner_cell(cell: Vector2i) -> bool:
	if _walls.get_cell_source_id(cell) != -1:
		return false
	var wall_n: bool = _walls.get_cell_source_id(cell + Vector2i(0, -1)) != -1
	var wall_s: bool = _walls.get_cell_source_id(cell + Vector2i(0, 1)) != -1
	var wall_w: bool = _walls.get_cell_source_id(cell + Vector2i(-1, 0)) != -1
	var wall_e: bool = _walls.get_cell_source_id(cell + Vector2i(1, 0)) != -1
	return (wall_n and wall_w) or (wall_n and wall_e) or (wall_s and wall_w) or (wall_s and wall_e)


func _place_room_props_for_rooms(rooms: Array[Rect2i]) -> void:
	for room: Rect2i in rooms:
		if _decorated_rooms.has(room):
			continue
		var center: Vector2i = room.get_center()
		var corner_cells: Array[Vector2i] = []
		var floor_cells: Array[Vector2i] = []

		for x: int in range(room.position.x, room.position.x + room.size.x):
			for y: int in range(room.position.y, room.position.y + room.size.y):
				var cell: Vector2i = Vector2i(x, y)
				if not _cells.has(cell) or _walls.get_cell_source_id(cell) != -1:
					continue
				if cell.distance_squared_to(center) <= 4:
					continue
				if _is_corner_cell(cell):
					corner_cells.append(cell)
				else:
					floor_cells.append(cell)

		corner_cells.shuffle()
		floor_cells.shuffle()

		# Barrels and boxes only in corners
		for cell: Vector2i in corner_cells:
			if _decorations.get_cell_source_id(cell) != -1:
				continue
			if randf() <= 0.75:
				var prop_tile: Vector2i = PROP_BARREL if randf() > 0.5 else PROP_BOX
				_decorations.set_cell(cell, TILE_SET_SOURCE_ID, prop_tile)

		# Skulls and bones in rooms
		var bones_count: int = clampi(int(float(room.size.x * room.size.y) * 0.025), 1, 4)
		var bones_placed: int = 0
		for cell: Vector2i in floor_cells:
			if bones_placed >= bones_count:
				break
			if _decorations.get_cell_source_id(cell) != -1:
				continue
			var bone_tile: Vector2i = _pick_random_tile(PROP_SKULLS_AND_BONES)
			_decorations.set_cell(cell, TILE_SET_SOURCE_ID, bone_tile)
			bones_placed += 1


func _place_corridor_bones_in_rect(region: Rect2i) -> void:
	for x: int in range(region.position.x, region.end.x):
		for y: int in range(region.position.y, region.end.y):
			var cell: Vector2i = Vector2i(x, y)
			if not _cells.has(cell):
				continue
			if _walls.get_cell_source_id(cell) != -1 or _decorations.get_cell_source_id(cell) != -1:
				continue
			if _is_inside_any_room(cell):
				continue
			if randf() <= CORRIDOR_BONE_CHANCE:
				var bone_tile: Vector2i = _pick_random_tile(PROP_SKULLS_AND_BONES)
				_decorations.set_cell(cell, TILE_SET_SOURCE_ID, bone_tile)


func _is_inside_any_room(cell: Vector2i) -> bool:
	if hero_room.has_point(cell):
		return true
	for room: Rect2i in companion_rooms:
		if room.has_point(cell):
			return true
	return false


static func _log_perf(stage: StringName, start_usec: int, extra: String = "") -> void:
	var elapsed_ms: float = float(Time.get_ticks_usec() - start_usec) / 1000.0
	if elapsed_ms >= 2.0:
		print(&"[Perf] %s took %.2f ms%s" % [stage, elapsed_ms, extra])
