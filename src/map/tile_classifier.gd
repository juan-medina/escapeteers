# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name TileClassifier
extends RefCounted

const TILE_SET_SOURCE_ID: int = 4
const SET_BASE_ROWS: Array[int] = [0, 11, 33, 44, 55, 66, 77, 88]
const SET_HEIGHT_ROWS: int = 11
const FLOOR_ATLAS_START: Vector2i = Vector2i(10, 3)
const FLOOR_ATLAS_SIZE: Vector2i = Vector2i(6, 3)

const WALL_TOP_LEFT_OUTER: Vector2i = Vector2i(2, 0)
const WALL_TOP_RIGHT_OUTER: Vector2i = Vector2i(5, 0)
const WALL_TOP_LEFT_INNER: Vector2i = Vector2i(2, 1)
const WALL_TOP_RIGHT_INNER: Vector2i = Vector2i(5, 1)
const WALL_TOP_VARIANTS: Array[Vector2i] = [Vector2i(3, 0), Vector2i(4, 0), Vector2i(9, 0), Vector2i(10, 0), Vector2i(11, 0)]
const WALL_TOP_VENT_VARIANTS: Array[Vector2i] = [Vector2i(12, 0), Vector2i(13, 0), Vector2i(14, 0)]

const WALL_BOTTOM_LEFT_OUTER: Vector2i = Vector2i(0, 5)
const WALL_BOTTOM_RIGHT_OUTER: Vector2i = Vector2i(7, 5)
const WALL_BOTTOM_LEFT_INNER: Vector2i = Vector2i(1, 5)
const WALL_BOTTOM_RIGHT_INNER: Vector2i = Vector2i(6, 5)
const WALL_BOTTOM_VARIANTS: Array[Vector2i] = [Vector2i(3, 7), Vector2i(4, 7)]

const WALL_LEFT_VARIANTS: Array[Vector2i] = [Vector2i(0, 3), Vector2i(0, 4)]
const WALL_RIGHT_VARIANTS: Array[Vector2i] = [Vector2i(7, 3), Vector2i(7, 4)]

const TORCH_TOP: Vector2i = Vector2i(12, 20)
const TORCH_SIDE: Vector2i = Vector2i(12, 19)
const TORCH_RIGHT_ALT_ID: int = 1
const TORCH_GRID_SIZE: int = 10
const TORCH_BLOCK_MARGIN: int = 2
const MIN_TORCH_DIST_SQ: int = 49
const CANDLE_POST_TOP: Vector2i = Vector2i(10, 30)
const CANDLE_POST_BOTTOM: Vector2i = Vector2i(10, 31)
const SPIKE_FRAMES: Array[Vector2i] = [
	Vector2i(0, 9),
	Vector2i(1, 9),
	Vector2i(2, 9),
	Vector2i(3, 9),
]
const FLOOR_PLATE_VARIANTS: Array[Vector2i] = [
	Vector2i(4, 9),
	Vector2i(5, 9),
	Vector2i(6, 9),
	Vector2i(7, 9),
]
const DOOR_CLOSED_LEFT: Array[Vector2i] = [
	Vector2i(7, 22),
	Vector2i(7, 23),
	Vector2i(7, 24),
	Vector2i(5, 24),
]
const DOOR_CLOSED_RIGHT: Array[Vector2i] = [
	Vector2i(8, 22),
	Vector2i(8, 23),
	Vector2i(8, 24),
	Vector2i(6, 24),
]
const DOOR_OPEN_TOP_LEFT: Array[Vector2i] = [
	Vector2i(2, 22),
	Vector2i(2, 24),
	Vector2i(0, 24),
	Vector2i(0, 22),
]
const DOOR_OPEN_TOP_RIGHT: Array[Vector2i] = [
	Vector2i(3, 22),
	Vector2i(3, 24),
	Vector2i(1, 24),
	Vector2i(1, 22),
]
const DOOR_OPEN_BOTTOM_LEFT: Array[Vector2i] = [
	Vector2i(2, 23),
	Vector2i(2, 25),
	Vector2i(0, 25),
	Vector2i(0, 23),
]
const DOOR_OPEN_BOTTOM_RIGHT: Array[Vector2i] = [
	Vector2i(3, 23),
	Vector2i(3, 25),
	Vector2i(1, 25),
	Vector2i(1, 23),
]
const LEVER_CLOSED: Vector2i = Vector2i(5, 31)
const LEVER_OPEN: Vector2i = Vector2i(6, 31)


static func cell_hash(run_seed: int, gx: int, gy: int) -> int:
	var h: int = run_seed
	h = (h ^ (gx * 374761393)) * 668265263
	h = (h ^ (gy * 1442695041)) * 374761393
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = h ^ (h >> 16)
	return absi(h)


static func get_floor_atlas(run_seed: int, gx: int, gy: int, tile_set: int = 0) -> Vector2i:
	var h: int = cell_hash(run_seed, gx, gy)
	var ax: int = FLOOR_ATLAS_START.x + (h % FLOOR_ATLAS_SIZE.x)
	var ay: int = FLOOR_ATLAS_START.y + (floori(float(h) / float(FLOOR_ATLAS_SIZE.x)) % FLOOR_ATLAS_SIZE.y)
	return _apply_set_offset(Vector2i(ax, ay), tile_set)


static func get_spike_frame(frame_idx: int, tile_set: int = 0) -> Vector2i:
	return _apply_set_offset(SPIKE_FRAMES[frame_idx], tile_set)


static func get_floor_plate_atlas(plate_idx: int, tile_set: int = 0) -> Vector2i:
	return _apply_set_offset(FLOOR_PLATE_VARIANTS[clampi(plate_idx, 0, FLOOR_PLATE_VARIANTS.size() - 1)], tile_set)


static func get_closed_door_atlas(door_code: int) -> Vector2i:
	var color_idx: int = clampi(door_code >> 1, 0, DOOR_CLOSED_LEFT.size() - 1)
	return DOOR_CLOSED_RIGHT[color_idx] if (door_code % 2) == 1 else DOOR_CLOSED_LEFT[color_idx]


static func get_wall_top_for_cell(run_seed: int, cell: Vector2i, tile_set: int) -> Vector2i:
	var h: int = cell_hash(run_seed, cell.x, cell.y)
	return _apply_set_offset(WALL_TOP_VARIANTS[h % WALL_TOP_VARIANTS.size()], tile_set)


static func get_wall_top_inner_for_side(is_right: bool, tile_set: int) -> Vector2i:
	return _apply_set_offset(WALL_TOP_RIGHT_INNER if is_right else WALL_TOP_LEFT_INNER, tile_set)


static func is_top_wall(atlas: Vector2i) -> bool:
	return _to_base_coords(atlas) in WALL_TOP_VARIANTS


static func is_left_wall(atlas: Vector2i) -> bool:
	return _to_base_coords(atlas) in WALL_LEFT_VARIANTS


static func is_right_wall(atlas: Vector2i) -> bool:
	return _to_base_coords(atlas) in WALL_RIGHT_VARIANTS


static func _apply_set_offset(coords: Vector2i, tile_set: int) -> Vector2i:
	var base_row: int = SET_BASE_ROWS[clampi(tile_set, 0, SET_BASE_ROWS.size() - 1)]
	return Vector2i(coords.x, coords.y + base_row)


static func _to_base_coords(atlas: Vector2i) -> Vector2i:
	for base_row: int in SET_BASE_ROWS:
		if atlas.y >= base_row and atlas.y < base_row + SET_HEIGHT_ROWS:
			return Vector2i(atlas.x, atlas.y - base_row)
	return Vector2i(-1, -1)


static func bake_chunk(coord: Vector2i, raster: ChunkRaster, plan: WorldPlan) -> void:
	raster.rasterize(coord, plan)
	if not raster.has_any_content():
		return
	var data: Dictionary = classify_chunk(raster, plan.run_seed, plan)
	var floors: Array[Vector2i] = data[&"floors"]
	var walls: Array[Vector2i] = data[&"walls"]
	var wall_set: Dictionary[Vector2i, bool] = {}
	for wpos: Vector2i in walls:
		wall_set[wpos] = true
	var walkable: Array[Vector2i] = []
	for fpos: Vector2i in floors:
		if not wall_set.has(fpos):
			walkable.append(fpos)
	data[&"walkable"] = walkable
	plan.baked_chunks[coord] = data


static func classify_chunk(raster: ChunkRaster, run_seed: int, plan: WorldPlan) -> Dictionary:
	var out_floors: Array[Vector2i] = []
	var out_floor_atlas: Array[Vector2i] = []
	var out_spikes: Array[Vector2i] = []
	var out_walls: Array[Vector2i] = []
	var out_wall_atlas: Array[Vector2i] = []
	var out_wall_alt_ids: Array[int] = []
	var out_torches: Array[Vector2i] = []
	var out_torch_atlas: Array[Vector2i] = []
	var out_torch_alt_ids: Array[int] = []
	var out_lights: Array[Vector2i] = []

	var wall_grid: Dictionary[Vector2i, Vector2i] = {}
	var data: PackedByteArray = raster.data
	var pitch: int = ChunkRaster.RASTER_SIZE

	for ly: int in range(ChunkRaster.CHUNK_SIZE):
		var gy: int = raster.origin.y + ly
		var row_cur: int = (ly + 1) * pitch
		var row_above: int = ly * pitch

		for lx: int in range(ChunkRaster.CHUNK_SIZE):
			var col: int = lx + 1
			var is_f: bool = data[row_cur + col] == 1
			var n: bool = data[row_above + col] == 1
			var e: bool = data[row_cur + col + 1] == 1
			var w: bool = data[row_cur + col - 1] == 1
			var ne: bool = data[row_above + col + 1] == 1
			var nw: bool = data[row_above + col - 1] == 1

			var gx: int = raster.origin.x + lx
			var gpos: Vector2i = Vector2i(gx, gy)

			var wall_coords: Vector2i = Vector2i(-1, -1)
			var is_fixed_door: bool = false
			if plan.door_cell_codes.has(gpos):
				var door_code: int = plan.door_cell_codes[gpos]
				wall_coords = get_closed_door_atlas(door_code)
				is_fixed_door = true
				if (door_code % 2) == 0:
					out_lights.append(gpos)
			elif plan.closed_shortcut_walls.has(gpos):
				var h: int = cell_hash(run_seed, gx, gy)
				wall_coords = WALL_TOP_VARIANTS[h % WALL_TOP_VARIANTS.size()]
			elif is_f:
				if not n:
					if ne and not nw:
						wall_coords = WALL_TOP_LEFT_INNER
					elif nw and not ne:
						wall_coords = WALL_TOP_RIGHT_INNER
					else:
						var h: int = cell_hash(run_seed, gx, gy)
						if (h % 7) == 0:
							wall_coords = WALL_TOP_VENT_VARIANTS[(h >> 3) % WALL_TOP_VENT_VARIANTS.size()]
						else:
							wall_coords = WALL_TOP_VARIANTS[h % WALL_TOP_VARIANTS.size()]
			else:
				if e and not ne:
					wall_coords = WALL_TOP_LEFT_OUTER
				elif w and not nw:
					wall_coords = WALL_TOP_RIGHT_OUTER
				elif n:
					if e and not w:
						wall_coords = WALL_BOTTOM_LEFT_INNER
					elif w and not e:
						wall_coords = WALL_BOTTOM_RIGHT_INNER
					else:
						var h: int = cell_hash(run_seed, gx, gy)
						wall_coords = WALL_BOTTOM_VARIANTS[h % WALL_BOTTOM_VARIANTS.size()]
				elif ne and not e:
					wall_coords = WALL_BOTTOM_LEFT_OUTER
				elif nw and not w:
					wall_coords = WALL_BOTTOM_RIGHT_OUTER
				elif e:
					var h: int = cell_hash(run_seed, gx, gy)
					wall_coords = WALL_LEFT_VARIANTS[h % WALL_LEFT_VARIANTS.size()]
				elif w:
					var h: int = cell_hash(run_seed, gx, gy)
					wall_coords = WALL_RIGHT_VARIANTS[h % WALL_RIGHT_VARIANTS.size()]

			if is_f or wall_coords.x != -1:
				var tile_set: int = plan.get_cell_tile_set(gpos)
				if is_f:
					out_floors.append(gpos)
					if wall_coords.x == -1 and plan.is_spike_cell(gpos):
						out_floor_atlas.append(get_spike_frame(0, tile_set))
						out_spikes.append(gpos)
					elif wall_coords.x == -1:
						var plate_idx: int = plan.get_floor_plate_index(gpos)
						if plate_idx >= 0:
							out_floor_atlas.append(get_floor_plate_atlas(plate_idx, tile_set))
						else:
							out_floor_atlas.append(get_floor_atlas(run_seed, gx, gy, tile_set))
					else:
						out_floor_atlas.append(get_floor_atlas(run_seed, gx, gy, tile_set))

				if wall_coords.x != -1:
					if not is_fixed_door:
						wall_coords = _apply_set_offset(wall_coords, tile_set)
					out_walls.append(gpos)
					out_wall_atlas.append(wall_coords)
					out_wall_alt_ids.append(0)
					wall_grid[Vector2i(lx, ly)] = wall_coords

	# Deterministic jittered-grid torch placement with candidate wall scan:
	var block_start_x: int = floori(float(raster.origin.x) / float(TORCH_GRID_SIZE))
	var block_start_y: int = floori(float(raster.origin.y) / float(TORCH_GRID_SIZE))
	var blocks_x: int = floori(float(ChunkRaster.CHUNK_SIZE) / float(TORCH_GRID_SIZE)) + 2
	var blocks_y: int = floori(float(ChunkRaster.CHUNK_SIZE) / float(TORCH_GRID_SIZE)) + 2

	for b_idx_y: int in range(blocks_y):
		var by: int = block_start_y + b_idx_y
		for b_idx_x: int in range(blocks_x):
			var bx: int = block_start_x + b_idx_x
			var h: int = cell_hash(run_seed, bx, by)

			# Collect all candidate torch wall locations in the inner core of this block
			# so two neighboring blocks can never place torches closer than 2 * TORCH_BLOCK_MARGIN + 1 tiles.
			var top_candidates: Array[Vector2i] = []
			var left_candidates: Array[Vector2i] = []
			var right_candidates: Array[Vector2i] = []

			for dy: int in range(TORCH_BLOCK_MARGIN, TORCH_GRID_SIZE - TORCH_BLOCK_MARGIN):
				var target_gy: int = by * TORCH_GRID_SIZE + dy
				var ly: int = target_gy - raster.origin.y
				if ly < 0 or ly >= ChunkRaster.CHUNK_SIZE:
					continue
				for dx: int in range(TORCH_BLOCK_MARGIN, TORCH_GRID_SIZE - TORCH_BLOCK_MARGIN):
					var target_gx: int = bx * TORCH_GRID_SIZE + dx
					var lx: int = target_gx - raster.origin.x
					if lx < 0 or lx >= ChunkRaster.CHUNK_SIZE:
						continue
					var lpos: Vector2i = Vector2i(lx, ly)
					if wall_grid.has(lpos):
						var atlas: Vector2i = wall_grid[lpos]
						if is_top_wall(atlas):
							var cand_top: Vector2i = Vector2i(target_gx, target_gy)
							if (
								not plan.no_prop_cells.has(cand_top)
								and not plan.has_candle_post_near(cand_top, 64)
								and not _is_near_any(cand_top, out_lights, MIN_TORCH_DIST_SQ)
							):
								top_candidates.append(cand_top)
						elif is_left_wall(atlas):
							var adj_lx: int = lx + 1
							if adj_lx < ChunkRaster.CHUNK_SIZE and not wall_grid.has(Vector2i(adj_lx, ly)) and raster.is_floor_local(adj_lx, ly):
								var cand_left: Vector2i = Vector2i(target_gx + 1, target_gy)
								if (
									not plan.no_prop_cells.has(cand_left)
									and not plan.has_candle_post_near(cand_left, 64)
									and not plan.is_spike_cell(cand_left)
									and not _is_near_any(cand_left, out_lights, MIN_TORCH_DIST_SQ)
								):
									left_candidates.append(cand_left)
						elif is_right_wall(atlas):
							var adj_lx: int = lx - 1
							if adj_lx >= 0 and not wall_grid.has(Vector2i(adj_lx, ly)) and raster.is_floor_local(adj_lx, ly):
								var cand_right: Vector2i = Vector2i(target_gx - 1, target_gy)
								if (
									not plan.no_prop_cells.has(cand_right)
									and not plan.has_candle_post_near(cand_right, 64)
									and not plan.is_spike_cell(cand_right)
									and not _is_near_any(cand_right, out_lights, MIN_TORCH_DIST_SQ)
								):
									right_candidates.append(cand_right)

			# Prefer top walls, then left, then right
			if not _try_append_torch(top_candidates, h, TORCH_TOP, 0, out_torches, out_torch_atlas, out_torch_alt_ids, out_lights):
				if not _try_append_torch(left_candidates, h, TORCH_SIDE, 0, out_torches, out_torch_atlas, out_torch_alt_ids, out_lights):
					_try_append_torch(
						right_candidates, h, TORCH_SIDE, TORCH_RIGHT_ALT_ID, out_torches, out_torch_atlas, out_torch_alt_ids, out_lights
					)

	# Candle posts streamed directly from WorldPlan
	for ly: int in range(ChunkRaster.CHUNK_SIZE):
		var gy: int = raster.origin.y + ly
		for lx: int in range(ChunkRaster.CHUNK_SIZE):
			var gx: int = raster.origin.x + lx
			var gpos: Vector2i = Vector2i(gx, gy)
			if not wall_grid.has(Vector2i(lx, ly)) and raster.is_floor_local(lx, ly):
				if plan.is_candle_post_top(gpos):
					out_torches.append(gpos)
					out_torch_atlas.append(CANDLE_POST_TOP)
					out_torch_alt_ids.append(0)
					out_lights.append(gpos)
				elif plan.is_candle_post_base(gpos):
					out_torches.append(gpos)
					out_torch_atlas.append(CANDLE_POST_BOTTOM)
					out_torch_alt_ids.append(0)
				elif plan.lever_cells.has(gpos):
					out_torches.append(gpos)
					out_torch_atlas.append(LEVER_CLOSED)
					out_torch_alt_ids.append(0)
					out_lights.append(gpos)

	return {
		&"floors": out_floors,
		&"floor_atlas": out_floor_atlas,
		&"spikes": out_spikes,
		&"walls": out_walls,
		&"wall_atlas": out_wall_atlas,
		&"wall_alt_ids": out_wall_alt_ids,
		&"torches": out_torches,
		&"torch_atlas": out_torch_atlas,
		&"torch_alt_ids": out_torch_alt_ids,
		&"lights": out_lights,
	}


static func _try_append_torch(
	candidates: Array[Vector2i],
	h: int,
	atlas: Vector2i,
	alt_id: int,
	out_torches: Array[Vector2i],
	out_torch_atlas: Array[Vector2i],
	out_torch_alt_ids: Array[int],
	out_lights: Array[Vector2i]
) -> bool:
	if candidates.is_empty():
		return false
	var chosen_idx: int = h % candidates.size()
	var gpos: Vector2i = candidates[chosen_idx]
	out_torches.append(gpos)
	out_torch_atlas.append(atlas)
	out_torch_alt_ids.append(alt_id)
	out_lights.append(gpos)
	return true


static func _is_near_any(cell: Vector2i, existing: Array[Vector2i], min_dist_sq: int) -> bool:
	for other: Vector2i in existing:
		if cell.distance_squared_to(other) < min_dist_sq:
			return true
	return false
