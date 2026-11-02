# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name SpatialGrid
extends RefCounted

const BUCKET_SIZE: int = 64

var _buckets: Dictionary[Vector2i, Array] = {}


func clear() -> void:
	_buckets.clear()


func add_rect(rect_id: int, rect: Rect2i) -> void:
	var min_bx: int = _to_bucket(rect.position.x)
	var max_bx: int = _to_bucket(rect.position.x + rect.size.x - 1)
	var min_by: int = _to_bucket(rect.position.y)
	var max_by: int = _to_bucket(rect.position.y + rect.size.y - 1)

	for bx: int in range(min_bx, max_bx + 1):
		for by: int in range(min_by, max_by + 1):
			var b_pos: Vector2i = Vector2i(bx, by)
			if not _buckets.has(b_pos):
				_buckets[b_pos] = []
			_buckets[b_pos].append(rect_id)


func get_candidate_ids_for_rect(rect: Rect2i) -> Array[int]:
	var min_bx: int = _to_bucket(rect.position.x)
	var max_bx: int = _to_bucket(rect.position.x + rect.size.x - 1)
	var min_by: int = _to_bucket(rect.position.y)
	var max_by: int = _to_bucket(rect.position.y + rect.size.y - 1)

	var seen: Dictionary[int, bool] = {}
	var result: Array[int] = []

	for bx: int in range(min_bx, max_bx + 1):
		for by: int in range(min_by, max_by + 1):
			var b_pos: Vector2i = Vector2i(bx, by)
			if _buckets.has(b_pos):
				for rect_id: int in _buckets[b_pos]:
					if not seen.has(rect_id):
						seen[rect_id] = true
						result.append(rect_id)

	return result


func get_candidate_ids_for_point(point: Vector2i) -> Array:
	var b_pos: Vector2i = Vector2i(_to_bucket(point.x), _to_bucket(point.y))
	if _buckets.has(b_pos):
		return _buckets[b_pos]
	return []


func intersects_any(rect: Rect2i, all_rects: Array[Rect2i], padding: int = 0) -> bool:
	var check_rect: Rect2i = rect.grow(padding) if padding > 0 else rect
	var candidates: Array[int] = get_candidate_ids_for_rect(check_rect)
	for rect_id: int in candidates:
		if rect_id >= 0 and rect_id < all_rects.size():
			if all_rects[rect_id].grow(padding).intersects(rect):
				return true
	return false


func has_point(point: Vector2i, all_rects: Array[Rect2i]) -> bool:
	var candidates: Array = get_candidate_ids_for_point(point)
	for rect_id: int in candidates:
		if rect_id >= 0 and rect_id < all_rects.size():
			if all_rects[rect_id].has_point(point):
				return true
	return false


static func _to_bucket(coord: int) -> int:
	return int(floorf(float(coord) / float(BUCKET_SIZE)))
