# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

## Computes line-of-sight chunk visibility over a precomputed flat tile opacity grid.
class_name MapVisibility
extends RefCounted

const CELL_WALL: int = 0
const CELL_FLOOR: int = 1
const CELL_LOCKED_DOOR: int = 2

const OCTANT_XX: Array[int] = [1, -1, 0, 0, -1, 1, 0, 0]
const OCTANT_XY: Array[int] = [0, 0, -1, -1, 0, 0, 1, 1]
const OCTANT_YX: Array[int] = [0, 0, 1, -1, 0, 0, -1, 1]
const OCTANT_YY: Array[int] = [1, 1, 0, 0, -1, -1, 0, 0]

const FALLBACK_OFFSETS: Array[Vector2i] = [
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(1, 1),
	Vector2i(-1, 1),
	Vector2i(1, -1),
	Vector2i(-1, -1),
]

var _origin: Vector2i = Vector2i.ZERO
var _width: int = 0
var _height: int = 0
var _grid: PackedByteArray = PackedByteArray()


## Precomputes the flat opacity grid for all carved dungeon rooms, corridors, doors, and shortcuts.
func setup(plan: WorldPlan) -> void:
	if plan == null or plan.carve_rects.is_empty():
		_origin = Vector2i.ZERO
		_width = 0
		_height = 0
		_grid.clear()
		return

	var bounds: Rect2i = plan.carve_rects[0]
	for rect: Rect2i in plan.carve_rects:
		bounds = bounds.merge(rect)
	bounds = bounds.grow(2)

	_origin = bounds.position
	_width = bounds.size.x
	_height = bounds.size.y
	_grid.resize(_width * _height)
	_grid.fill(CELL_WALL)

	for rect: Rect2i in plan.carve_rects:
		_fill_rect(rect, CELL_FLOOR)

	_apply_north_wall_pass()

	for cell: Vector2i in plan.door_cell_codes:
		_set_cell(cell.x, cell.y, CELL_LOCKED_DOOR)

	for cell: Vector2i in plan.shortcut_blocker_cells:
		_set_cell(cell.x, cell.y, CELL_LOCKED_DOOR)


## Marks the locked door cells of a gate as transparent floor once unlocked.
func open_door(gate: SectorGatePlanner.SectorGate) -> void:
	for cell: Vector2i in gate.door_cells:
		_set_cell(cell.x, cell.y, CELL_FLOOR)


## Marks the door cells of a local shortcut as transparent floor once opened.
func open_shortcut(shortcut: ShortcutTunnelPlanner.LocalShortcut) -> void:
	for cell: Vector2i in shortcut.door_cells:
		_set_cell(cell.x, cell.y, CELL_FLOOR)


## Returns true if tile (tx, ty) blocks line of sight (wall, locked door, or outside bounds).
func is_opaque(tx: int, ty: int) -> bool:
	var lx: int = tx - _origin.x
	var ly: int = ty - _origin.y
	if lx < 0 or ly < 0 or lx >= _width or ly >= _height:
		return true
	return _grid[ly * _width + lx] != CELL_FLOOR


## Populates out_chunks with chunk -> is_explored using 8-octant recursive shadowcasting.
func compute_fov(
	origin_tile: Vector2i,
	reveal_radius_tiles: int,
	explore_radius_tiles: int,
	out_chunks: Dictionary[Vector2i, bool],
) -> void:
	out_chunks.clear()
	if _width <= 0 or _height <= 0:
		return

	var origin: Vector2i = _resolve_origin(origin_tile)
	out_chunks[Vector2i(origin_tile.x >> 1, origin_tile.y >> 1)] = true
	out_chunks[Vector2i(origin.x >> 1, origin.y >> 1)] = true

	var radii: Vector3i = Vector3i(
		reveal_radius_tiles,
		reveal_radius_tiles * reveal_radius_tiles,
		explore_radius_tiles * explore_radius_tiles,
	)
	for octant: int in range(8):
		_cast_light(origin, 1, 1.0, 0.0, radii, octant, out_chunks)


func _fill_rect(rect: Rect2i, value: int) -> void:
	var x_start: int = rect.position.x - _origin.x
	var x_end: int = rect.end.x - _origin.x
	for ty: int in range(rect.position.y, rect.end.y):
		var row_offset: int = (ty - _origin.y) * _width
		for lx: int in range(x_start, x_end):
			_grid[row_offset + lx] = value


func _apply_north_wall_pass() -> void:
	for ly: int in range(_height - 1, 0, -1):
		var row_offset: int = ly * _width
		var north_offset: int = row_offset - _width
		for lx: int in range(_width):
			if _grid[row_offset + lx] == CELL_FLOOR and _grid[north_offset + lx] == CELL_WALL:
				_grid[row_offset + lx] = CELL_WALL
	for lx: int in range(_width):
		_grid[lx] = CELL_WALL


func _set_cell(tx: int, ty: int, value: int) -> void:
	var lx: int = tx - _origin.x
	var ly: int = ty - _origin.y
	if lx >= 0 and ly >= 0 and lx < _width and ly < _height:
		_grid[ly * _width + lx] = value


func _resolve_origin(origin_tile: Vector2i) -> Vector2i:
	if not is_opaque(origin_tile.x, origin_tile.y):
		return origin_tile
	for offset: Vector2i in FALLBACK_OFFSETS:
		var cand: Vector2i = origin_tile + offset
		if not is_opaque(cand.x, cand.y):
			return cand
	return origin_tile


func _cast_light(
	origin: Vector2i,
	start_row: int,
	start_slope: float,
	end_slope: float,
	radii: Vector3i,
	octant: int,
	out_chunks: Dictionary[Vector2i, bool],
) -> void:
	if start_slope < end_slope:
		return

	var xx: int = OCTANT_XX[octant]
	var xy: int = OCTANT_XY[octant]
	var yx: int = OCTANT_YX[octant]
	var yy: int = OCTANT_YY[octant]

	for r_row: int in range(start_row, radii.x + 1):
		var dy: int = -r_row
		var blocked: bool = false
		var new_start: float = 0.0
		for step_dx: int in range(-r_row, 1):
			var l_slope: float = (float(step_dx) - 0.5) / (float(dy) + 0.5)
			var r_slope: float = (float(step_dx) + 0.5) / (float(dy) - 0.5)
			if start_slope < r_slope:
				continue
			if end_slope > l_slope:
				break

			var wx: int = origin.x + step_dx * xx + dy * xy
			var wy: int = origin.y + step_dx * yx + dy * yy
			var d_sq: int = step_dx * step_dx + dy * dy
			if d_sq <= radii.y:
				var chunk: Vector2i = Vector2i(wx >> 1, wy >> 1)
				if d_sq <= radii.z:
					out_chunks[chunk] = true
				elif not out_chunks.has(chunk):
					out_chunks[chunk] = false

			var cell_blocked: bool = is_opaque(wx, wy)
			if blocked:
				if cell_blocked:
					new_start = r_slope
					continue
				blocked = false
				start_slope = new_start
			elif cell_blocked and r_row < radii.x:
				blocked = true
				_cast_light(origin, r_row + 1, start_slope, l_slope, radii, octant, out_chunks)
				new_start = r_slope

		if blocked:
			break
