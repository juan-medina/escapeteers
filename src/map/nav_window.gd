# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name NavWindow
extends RefCounted

const WINDOW_SIZE: int = 192
const HALF_WINDOW_SIZE: int = 96
const RECENTER_THRESHOLD_TILES: int = 32

var _astar: AStarGrid2D = AStarGrid2D.new()
var _walkable_cells: Dictionary[Vector2i, bool] = {}
var _floor: TileMapLayer = null
var _center_cell: Vector2i = Vector2i(-999999, -999999)
var _current_region: Rect2i = Rect2i()


func setup(walkable_cells: Dictionary[Vector2i, bool], floor_layer: TileMapLayer) -> void:
	_walkable_cells = walkable_cells
	_floor = floor_layer
	_center_cell = Vector2i(-999999, -999999)


func update_center(player_cell: Vector2i) -> void:
	if _center_cell == Vector2i(-999999, -999999):
		_recenter(player_cell)
		return

	var dx: int = absi(player_cell.x - _center_cell.x)
	var dy: int = absi(player_cell.y - _center_cell.y)
	if dx >= RECENTER_THRESHOLD_TILES or dy >= RECENTER_THRESHOLD_TILES:
		_recenter(player_cell)


func set_cell_walkable(cell: Vector2i, walkable: bool) -> void:
	if _astar.is_in_boundsv(cell):
		_astar.set_point_solid(cell, not walkable)


func is_in_bounds(cell: Vector2i) -> bool:
	return _astar.is_in_boundsv(cell)


func is_point_solid(cell: Vector2i) -> bool:
	if not _astar.is_in_boundsv(cell):
		return true
	return _astar.is_point_solid(cell)


func get_path(from_pos: Vector2, to_pos: Vector2) -> PackedVector2Array:
	if _floor == null:
		return PackedVector2Array()

	var from_cell: Vector2i = _floor.local_to_map(from_pos)
	var to_cell: Vector2i = _floor.local_to_map(to_pos)

	if not _astar.is_in_boundsv(from_cell) or not _astar.is_in_boundsv(to_cell):
		return PackedVector2Array()

	if _astar.is_point_solid(from_cell):
		from_cell = _find_closest_walkable_cell(from_cell)

	if _astar.is_point_solid(to_cell):
		to_cell = _find_closest_walkable_cell(to_cell)

	if _astar.is_point_solid(from_cell) or _astar.is_point_solid(to_cell):
		return PackedVector2Array()

	if from_cell == to_cell:
		return PackedVector2Array([to_pos])

	var cell_path: Array[Vector2i] = _astar.get_id_path(from_cell, to_cell)
	if cell_path.is_empty():
		return PackedVector2Array()

	var world_path: PackedVector2Array = PackedVector2Array()
	for cell: Vector2i in cell_path:
		world_path.append(_floor.map_to_local(cell))

	if not world_path.is_empty():
		world_path[world_path.size() - 1] = to_pos

	return world_path


func _recenter(new_center: Vector2i) -> void:
	_center_cell = new_center
	var top_left: Vector2i = new_center - Vector2i(HALF_WINDOW_SIZE, HALF_WINDOW_SIZE)
	_current_region = Rect2i(top_left, Vector2i(WINDOW_SIZE, WINDOW_SIZE))

	_astar.region = _current_region
	_astar.cell_size = Vector2(16, 16)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.jumping_enabled = true
	_astar.update()

	_astar.fill_solid_region(_current_region, true)

	for cell: Vector2i in _walkable_cells:
		if _current_region.has_point(cell):
			_astar.set_point_solid(cell, false)


func _find_closest_walkable_cell(target_cell: Vector2i) -> Vector2i:
	if _astar.is_in_boundsv(target_cell) and not _astar.is_point_solid(target_cell):
		return target_cell

	for r: int in range(1, 6):
		for dx: int in range(-r, r + 1):
			for dy: int in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var candidate: Vector2i = target_cell + Vector2i(dx, dy)
				if _astar.is_in_boundsv(candidate) and not _astar.is_point_solid(candidate):
					return candidate

	return target_cell
