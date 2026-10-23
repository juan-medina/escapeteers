# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Map
extends Node2D

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

const HERO_ROOM_SIZE: Vector2i = Vector2i(20, 20)
const COMPANION_ROOM_COUNT: int = 20
const COMPANION_ROOM_MIN_SIZE: Vector2i = Vector2i(8, 8)
const COMPANION_ROOM_MAX_SIZE: Vector2i = Vector2i(13, 13)
const COMPANION_MIN_DISTANCE: float = 24.0
const COMPANION_MAX_DISTANCE: float = 95.0
const ROOM_PADDING: int = 5
const CORRIDOR_WIDTH: int = 3
const EXTRA_CORRIDOR_LOOPS: int = 5
const MAX_PLACEMENT_ATTEMPTS: int = 1500

var hero_room: Rect2i = Rect2i()
var companion_rooms: Array[Rect2i] = []

var _astar: AStarGrid2D = AStarGrid2D.new()
var _walkable_cells: Dictionary[Vector2i, bool] = {}

@onready var _floor: TileMapLayer = $Floor
@onready var _walls: TileMapLayer = $Walls


func _ready() -> void:
	y_sort_enabled = true
	_walls.y_sort_enabled = true
	_floor.z_index = -1
	if _walls.tile_set == null:
		_walls.tile_set = _floor.tile_set
	generate_map()


func get_hero_spawn_position() -> Vector2:
	return _floor.map_to_local(hero_room.get_center())


func get_companion_spawn_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for room: Rect2i in companion_rooms:
		var center_cell: Vector2i = room.get_center()
		positions.append(_floor.map_to_local(center_cell))
		if randf() > 0.4:
			var offset: Vector2i = Vector2i(randi_range(-1, 1), randi_range(-1, 1))
			if offset != Vector2i.ZERO:
				positions.append(_floor.map_to_local(center_cell + offset))
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
	_floor.clear()
	_walls.clear()
	companion_rooms.clear()

	var cells: Dictionary[Vector2i, bool] = {}

	_create_hero_room(cells)
	_create_companion_rooms(cells)
	_create_corridors(cells)
	_eliminate_narrow_gaps(cells)

	for cell: Vector2i in cells:
		var atlas_coords: Vector2i = _get_random_floor_atlas_coords()
		_floor.set_cell(cell, TILE_SET_SOURCE_ID, atlas_coords)

	_create_all_walls(cells)
	_setup_navigation(cells)


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
	_walkable_cells.clear()
	for c: Vector2i in cells:
		if _walls.get_cell_source_id(c) == -1:
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


func _create_hero_room(cells: Dictionary[Vector2i, bool]) -> void:
	var top_left: Vector2i = Vector2i(Vector2(-HERO_ROOM_SIZE) * 0.5)
	hero_room = Rect2i(top_left, HERO_ROOM_SIZE)
	_carve_room(hero_room, cells)


func _create_companion_rooms(cells: Dictionary[Vector2i, bool]) -> void:
	var attempts: int = 0
	while companion_rooms.size() < COMPANION_ROOM_COUNT and attempts < MAX_PLACEMENT_ATTEMPTS:
		attempts += 1
		var angle: float = randf_range(0.0, TAU)
		var distance: float = randf_range(COMPANION_MIN_DISTANCE, COMPANION_MAX_DISTANCE)
		var size: Vector2i = Vector2i(
			randi_range(COMPANION_ROOM_MIN_SIZE.x, COMPANION_ROOM_MAX_SIZE.x), randi_range(COMPANION_ROOM_MIN_SIZE.y, COMPANION_ROOM_MAX_SIZE.y)
		)
		var center_pos: Vector2 = Vector2.from_angle(angle) * distance
		var top_left: Vector2i = Vector2i(center_pos.round()) - Vector2i(Vector2(size) * 0.5)
		var candidate_room: Rect2i = Rect2i(top_left, size)

		if _overlaps_any_room(candidate_room):
			continue

		companion_rooms.append(candidate_room)
		_carve_room(candidate_room, cells)


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


func _create_corridors(cells: Dictionary[Vector2i, bool]) -> void:
	var connected: Array[Rect2i] = [hero_room]
	var unconnected: Array[Rect2i] = companion_rooms.duplicate()

	while not unconnected.is_empty():
		var best_dist: float = INF
		var best_connected_index: int = 0
		var best_unconnected_index: int = 0

		for connected_index: int in range(connected.size()):
			var connected_center: Vector2 = Vector2(connected[connected_index].get_center())
			for unconnected_index: int in range(unconnected.size()):
				var unconnected_center: Vector2 = Vector2(unconnected[unconnected_index].get_center())
				var dist_sq: float = connected_center.distance_squared_to(unconnected_center)
				if dist_sq < best_dist:
					best_dist = dist_sq
					best_connected_index = connected_index
					best_unconnected_index = unconnected_index

		var from_pos: Vector2i = connected[best_connected_index].get_center()
		var to_pos: Vector2i = unconnected[best_unconnected_index].get_center()
		_carve_corridor(from_pos, to_pos, cells)

		connected.append(unconnected[best_unconnected_index])
		unconnected.remove_at(best_unconnected_index)

	# Add extra loops between nearby rooms for non-linear exploration
	for _i: int in range(EXTRA_CORRIDOR_LOOPS):
		if companion_rooms.size() < 2:
			break
		var room_a: Rect2i = companion_rooms[randi() % companion_rooms.size()]
		var room_b: Rect2i = companion_rooms[randi() % companion_rooms.size()]
		if room_a != room_b:
			_carve_corridor(room_a.get_center(), room_b.get_center(), cells)


func _carve_corridor(from: Vector2i, to: Vector2i, cells: Dictionary[Vector2i, bool]) -> void:
	var half_width: int = int(float(CORRIDOR_WIDTH) * 0.5)

	var h_cells: Dictionary[Vector2i, bool] = cells.duplicate()
	_carve_horizontal_line(from.x, to.x, from.y, half_width, h_cells)
	_carve_vertical_line(from.y, to.y, to.x, half_width, h_cells)

	var v_cells: Dictionary[Vector2i, bool] = cells.duplicate()
	_carve_vertical_line(from.y, to.y, from.x, half_width, v_cells)
	_carve_horizontal_line(from.x, to.x, to.y, half_width, v_cells)

	if _count_narrow_gaps(h_cells) <= _count_narrow_gaps(v_cells):
		cells.assign(h_cells)
	else:
		cells.assign(v_cells)


func _eliminate_narrow_gaps(cells: Dictionary[Vector2i, bool]) -> void:
	var changed: bool = true
	var pass_count: int = 0

	while changed and pass_count < 10:
		pass_count += 1
		changed = false
		var candidates: Dictionary[Vector2i, bool] = {}

		for f: Vector2i in cells:
			for dx: int in range(-2, 3):
				for dy: int in range(-2, 3):
					var p: Vector2i = f + Vector2i(dx, dy)
					if not cells.has(p):
						candidates[p] = true

		var to_add: Array[Vector2i] = []
		for p: Vector2i in candidates:
			var h_gap: bool = (
				(cells.has(p + Vector2i(-1, 0)) or cells.has(p + Vector2i(-2, 0)))
				and (cells.has(p + Vector2i(1, 0)) or cells.has(p + Vector2i(2, 0)))
			)
			var v_gap: bool = (
				(cells.has(p + Vector2i(0, -1)) or cells.has(p + Vector2i(0, -2)))
				and (cells.has(p + Vector2i(0, 1)) or cells.has(p + Vector2i(0, 2)))
			)
			if h_gap or v_gap:
				to_add.append(p)
				changed = true

		for p: Vector2i in to_add:
			cells[p] = true


func _count_narrow_gaps(cells: Dictionary[Vector2i, bool]) -> int:
	var candidates: Dictionary[Vector2i, bool] = {}
	for f: Vector2i in cells:
		for dx: int in range(-2, 3):
			for dy: int in range(-2, 3):
				var p: Vector2i = f + Vector2i(dx, dy)
				if not cells.has(p):
					candidates[p] = true

	var count: int = 0
	for p: Vector2i in candidates:
		var h_gap: bool = (
			(cells.has(p + Vector2i(-1, 0)) or cells.has(p + Vector2i(-2, 0))) and (cells.has(p + Vector2i(1, 0)) or cells.has(p + Vector2i(2, 0)))
		)
		var v_gap: bool = (
			(cells.has(p + Vector2i(0, -1)) or cells.has(p + Vector2i(0, -2))) and (cells.has(p + Vector2i(0, 1)) or cells.has(p + Vector2i(0, 2)))
		)
		if h_gap or v_gap:
			count += 1
	return count


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


func _create_all_walls(cells: Dictionary[Vector2i, bool]) -> void:
	var walls_placed: Dictionary[Vector2i, bool] = {}

	_create_top_walls(cells, walls_placed)
	_create_bottom_walls(cells, walls_placed)
	_create_vertical_walls(cells, walls_placed)


func _create_top_walls(cells: Dictionary[Vector2i, bool], walls_placed: Dictionary[Vector2i, bool]) -> void:
	for f: Vector2i in cells:
		if cells.has(f + Vector2i(0, -1)):
			continue

		var has_ne: bool = cells.has(f + Vector2i(1, -1))
		var has_nw: bool = cells.has(f + Vector2i(-1, -1))
		var has_w: bool = cells.has(f + Vector2i(-1, 0))
		var has_e: bool = cells.has(f + Vector2i(1, 0))

		if has_ne and not has_w:
			_walls.set_cell(f, TILE_SET_SOURCE_ID, WALL_TOP_LEFT_INNER)
		elif has_nw and not has_e:
			_walls.set_cell(f, TILE_SET_SOURCE_ID, WALL_TOP_RIGHT_INNER)
		else:
			_walls.set_cell(f, TILE_SET_SOURCE_ID, _pick_random_tile(WALL_TOP_VARIANTS))

		var left_cell: Vector2i = f + Vector2i(-1, 0)
		if not cells.has(left_cell) and not walls_placed.has(left_cell):
			_walls.set_cell(left_cell, TILE_SET_SOURCE_ID, WALL_TOP_LEFT_OUTER)
			walls_placed[left_cell] = true

		var right_cell: Vector2i = f + Vector2i(1, 0)
		if not cells.has(right_cell) and not walls_placed.has(right_cell):
			_walls.set_cell(right_cell, TILE_SET_SOURCE_ID, WALL_TOP_RIGHT_OUTER)
			walls_placed[right_cell] = true


func _create_bottom_walls(cells: Dictionary[Vector2i, bool], walls_placed: Dictionary[Vector2i, bool]) -> void:
	for f: Vector2i in cells:
		if cells.has(f + Vector2i(0, 1)):
			continue

		var bottom_cell: Vector2i = f + Vector2i(0, 1)
		if not walls_placed.has(bottom_cell) and not cells.has(bottom_cell):
			var has_e: bool = cells.has(bottom_cell + Vector2i(1, 0))
			var has_w: bool = cells.has(bottom_cell + Vector2i(-1, 0))

			if has_e and not has_w:
				_walls.set_cell(bottom_cell, TILE_SET_SOURCE_ID, WALL_BOTTOM_LEFT_INNER)
			elif has_w and not has_e:
				_walls.set_cell(bottom_cell, TILE_SET_SOURCE_ID, WALL_BOTTOM_RIGHT_INNER)
			else:
				_walls.set_cell(bottom_cell, TILE_SET_SOURCE_ID, _pick_random_tile(WALL_BOTTOM_VARIANTS))

			walls_placed[bottom_cell] = true

		var bl_cell: Vector2i = f + Vector2i(-1, 1)
		if not cells.has(bl_cell) and not cells.has(f + Vector2i(-1, 0)) and not walls_placed.has(bl_cell):
			_walls.set_cell(bl_cell, TILE_SET_SOURCE_ID, WALL_BOTTOM_LEFT_OUTER)
			walls_placed[bl_cell] = true

		var br_cell: Vector2i = f + Vector2i(1, 1)
		if not cells.has(br_cell) and not cells.has(f + Vector2i(1, 0)) and not walls_placed.has(br_cell):
			_walls.set_cell(br_cell, TILE_SET_SOURCE_ID, WALL_BOTTOM_RIGHT_OUTER)
			walls_placed[br_cell] = true


func _create_vertical_walls(cells: Dictionary[Vector2i, bool], walls_placed: Dictionary[Vector2i, bool]) -> void:
	for f: Vector2i in cells:
		var left_cell: Vector2i = f + Vector2i(-1, 0)
		if not cells.has(left_cell) and not walls_placed.has(left_cell):
			_walls.set_cell(left_cell, TILE_SET_SOURCE_ID, _pick_random_tile(WALL_LEFT_VARIANTS))
			walls_placed[left_cell] = true

		var right_cell: Vector2i = f + Vector2i(1, 0)
		if not cells.has(right_cell) and not walls_placed.has(right_cell):
			_walls.set_cell(right_cell, TILE_SET_SOURCE_ID, _pick_random_tile(WALL_RIGHT_VARIANTS))
			walls_placed[right_cell] = true


func _pick_random_tile(tiles: Array[Vector2i]) -> Vector2i:
	return tiles[randi() % tiles.size()]


func _get_random_floor_atlas_coords() -> Vector2i:
	var atlas_x: int = randi_range(FLOOR_ATLAS_START.x, FLOOR_ATLAS_START.x + FLOOR_ATLAS_SIZE.x - 1)
	var atlas_y: int = randi_range(FLOOR_ATLAS_START.y, FLOOR_ATLAS_START.y + FLOOR_ATLAS_SIZE.y - 1)
	return Vector2i(atlas_x, atlas_y)
