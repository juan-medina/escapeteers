# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name ChunkRaster
extends RefCounted

const CHUNK_SIZE: int = 32
const RASTER_SIZE: int = 34
const TOTAL_CELLS: int = 1156

var chunk_coord: Vector2i = Vector2i.ZERO
var origin: Vector2i = Vector2i.ZERO
var data: PackedByteArray = PackedByteArray()
var floor_count: int = 0
var any_floor_in_raster: bool = false


func _init() -> void:
	data.resize(TOTAL_CELLS)
	data.fill(0)


func rasterize(coord: Vector2i, plan: WorldPlan) -> void:
	chunk_coord = coord
	origin = coord * CHUNK_SIZE
	floor_count = 0
	any_floor_in_raster = false
	data.fill(0)

	var chunk_rect: Rect2i = Rect2i(origin.x - 1, origin.y - 1, RASTER_SIZE, RASTER_SIZE)
	var candidate_ids: Array[int] = plan.spatial_grid.get_candidate_ids_for_rect(chunk_rect)
	if candidate_ids.is_empty():
		return

	var relevant_rects: Array[Rect2i] = []
	for idx: int in candidate_ids:
		if idx >= 0 and idx < plan.carve_rects.size():
			var r: Rect2i = plan.carve_rects[idx]
			if r.intersects(chunk_rect):
				relevant_rects.append(r)

	if relevant_rects.is_empty():
		return

	any_floor_in_raster = true
	for r: Rect2i in relevant_rects:
		var clipped: Rect2i = r.intersection(chunk_rect)
		for cy: int in range(clipped.position.y, clipped.end.y):
			var ly: int = cy - origin.y
			var row_offset: int = (ly + 1) * RASTER_SIZE
			for cx: int in range(clipped.position.x, clipped.end.x):
				var lx: int = cx - origin.x
				var idx: int = row_offset + (lx + 1)
				if data[idx] == 0:
					data[idx] = 1
					if lx >= 0 and lx < CHUNK_SIZE and ly >= 0 and ly < CHUNK_SIZE:
						floor_count += 1


func is_floor_local(lx: int, ly: int) -> bool:
	if lx < -1 or lx > CHUNK_SIZE or ly < -1 or ly > CHUNK_SIZE:
		return false
	return data[(ly + 1) * RASTER_SIZE + (lx + 1)] == 1


func has_any_floor() -> bool:
	return floor_count > 0


func has_any_content() -> bool:
	return any_floor_in_raster
