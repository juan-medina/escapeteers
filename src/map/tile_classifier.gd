# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name TileClassifier
extends RefCounted

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
const TORCH_GRID_SIZE: int = 10
const TORCH_BLOCK_MARGIN: int = 2
const MIN_TORCH_DIST_SQ: int = 49
const CANDLE_POST_TOP: Vector2i = Vector2i(10, 30)
const CANDLE_POST_BOTTOM: Vector2i = Vector2i(10, 31)
const SPIKE_FRAMES: Array[Vector2i] = [
	Vector2i(0, 19),
	Vector2i(1, 19),
	Vector2i(2, 19),
	Vector2i(3, 19),
]


static func cell_hash(run_seed: int, gx: int, gy: int) -> int:
	var h: int = run_seed
	h = (h ^ (gx * 374761393)) * 668265263
	h = (h ^ (gy * 1442695041)) * 374761393
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = h ^ (h >> 16)
	return absi(h)


static func get_floor_atlas(run_seed: int, gx: int, gy: int) -> Vector2i:
	var h: int = cell_hash(run_seed, gx, gy)
	var ax: int = FLOOR_ATLAS_START.x + (h % FLOOR_ATLAS_SIZE.x)
	var ay: int = FLOOR_ATLAS_START.y + (floori(float(h) / float(FLOOR_ATLAS_SIZE.x)) % FLOOR_ATLAS_SIZE.y)
	return Vector2i(ax, ay)


static func classify_chunk(raster: ChunkRaster, run_seed: int, plan: WorldPlan = null) -> Dictionary:
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
			if is_f:
				if not n:
					if ne and not w:
						wall_coords = WALL_TOP_LEFT_INNER
					elif nw and not e:
						wall_coords = WALL_TOP_RIGHT_INNER
					else:
						var h: int = cell_hash(run_seed, gx, gy)
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

			if is_f:
				out_floors.append(gpos)
				if wall_coords.x == -1 and plan != null and plan.is_spike_cell(gpos):
					out_floor_atlas.append(SPIKE_FRAMES[0])
					out_spikes.append(gpos)
				else:
					out_floor_atlas.append(get_floor_atlas(run_seed, gx, gy))

			if wall_coords.x != -1:
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
						if atlas in WALL_TOP_VARIANTS:
							var cand_top: Vector2i = Vector2i(target_gx, target_gy)
							if (
								(plan == null or not plan.has_candle_post_near(cand_top, 64))
								and not _is_near_any(cand_top, out_lights, MIN_TORCH_DIST_SQ)
							):
								top_candidates.append(cand_top)
						elif atlas in WALL_LEFT_VARIANTS:
							var adj_lx: int = lx + 1
							if adj_lx < ChunkRaster.CHUNK_SIZE and not wall_grid.has(Vector2i(adj_lx, ly)) and raster.is_floor_local(adj_lx, ly):
								var cand_left: Vector2i = Vector2i(target_gx + 1, target_gy)
								if (
									(plan == null or (not plan.has_candle_post_near(cand_left, 64) and not plan.is_spike_cell(cand_left)))
									and not _is_near_any(cand_left, out_lights, MIN_TORCH_DIST_SQ)
								):
									left_candidates.append(cand_left)
						elif atlas in WALL_RIGHT_VARIANTS:
							var adj_lx: int = lx - 1
							if adj_lx >= 0 and not wall_grid.has(Vector2i(adj_lx, ly)) and raster.is_floor_local(adj_lx, ly):
								var cand_right: Vector2i = Vector2i(target_gx - 1, target_gy)
								if (
									(plan == null or (not plan.has_candle_post_near(cand_right, 64) and not plan.is_spike_cell(cand_right)))
									and not _is_near_any(cand_right, out_lights, MIN_TORCH_DIST_SQ)
								):
									right_candidates.append(cand_right)

			# Prefer top walls, then left, then right
			if not top_candidates.is_empty():
				var chosen_idx: int = h % top_candidates.size()
				var gpos: Vector2i = top_candidates[chosen_idx]
				out_torches.append(gpos)
				out_torch_atlas.append(TORCH_TOP)
				out_torch_alt_ids.append(0)
				out_lights.append(gpos)
			elif not left_candidates.is_empty():
				var chosen_idx: int = h % left_candidates.size()
				var gpos: Vector2i = left_candidates[chosen_idx]
				out_torches.append(gpos)
				out_torch_atlas.append(TORCH_SIDE)
				out_torch_alt_ids.append(0)
				out_lights.append(gpos)
			elif not right_candidates.is_empty():
				var chosen_idx: int = h % right_candidates.size()
				var gpos: Vector2i = right_candidates[chosen_idx]
				out_torches.append(gpos)
				out_torch_atlas.append(TORCH_SIDE)
				out_torch_alt_ids.append(TORCH_RIGHT_ALT_ID)
				out_lights.append(gpos)

	# Candle posts streamed directly from WorldPlan
	if plan != null:
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


static func _is_near_any(cell: Vector2i, existing: Array[Vector2i], min_dist_sq: int) -> bool:
	for other: Vector2i in existing:
		if cell.distance_squared_to(other) < min_dist_sq:
			return true
	return false
