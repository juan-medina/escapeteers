# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

## Encounter layout and corner guard spawner for Cursed Obelisk chambers and boss pylon phases.
class_name ObeliskEncounter
extends RefCounted

const MIN_ROOM_DIM: int = 20
const AURA_RADIUS_ROOM_RATIO: float = 0.42
const MIN_AURA_RADIUS: float = 128.0
const MAX_AURA_RADIUS: float = 224.0
const MIN_BAIT_DIST_SQ: int = 25
const MIN_OBELISK_SPACING_SQ: int = 36

var room: Rect2i = Rect2i()
var bait_cell: Vector2i = Vector2i.ZERO
var obelisk_cells: Array[Vector2i] = []
var aura_radius: float = 144.0
var depth: int = 1
var is_triggered: bool = false
var is_cleared: bool = false


static func can_fit_room(room_rect: Rect2i) -> bool:
	return room_rect.size.x >= MIN_ROOM_DIM and room_rect.size.y >= MIN_ROOM_DIM


static func build_for_room(plan: WorldPlan, room_rect: Rect2i) -> ObeliskEncounter:
	var enc: ObeliskEncounter = ObeliskEncounter.new()
	enc.room = room_rect
	enc.depth = plan.get_room_depth(room_rect)
	var max_dim_px: float = float(maxi(room_rect.size.x, room_rect.size.y)) * 16.0
	enc.aura_radius = clampf(max_dim_px * AURA_RADIUS_ROOM_RATIO, MIN_AURA_RADIUS, MAX_AURA_RADIUS)
	var occupied: Dictionary[Vector2i, bool] = {}
	enc.bait_cell = _pick_floor_cell_near(plan, room_rect.grow(-3), room_rect.get_center(), Vector2i(-99999, -99999), occupied, [])
	occupied[enc.bait_cell] = true

	var qx1: int = room_rect.position.x + roundi(float(room_rect.size.x) * 0.25)
	var qx2: int = room_rect.position.x + roundi(float(room_rect.size.x) * 0.75) - 1
	var qy1: int = room_rect.position.y + roundi(float(room_rect.size.y) * 0.25)
	var qy2: int = room_rect.position.y + roundi(float(room_rect.size.y) * 0.75) - 1
	var corners: Array[Vector2i] = [
		Vector2i(qx1, qy1),
		Vector2i(qx2, qy1),
		Vector2i(qx1, qy2),
		Vector2i(qx2, qy2),
	]
	var search_bounds: Rect2i = room_rect.grow(-2)
	for corner: Vector2i in corners:
		var cell: Vector2i = _pick_floor_cell_near(plan, search_bounds, corner, enc.bait_cell, occupied, enc.obelisk_cells)
		if cell.x == 2147483647:
			enc.obelisk_cells.clear()
			return enc
		occupied[cell] = true
		enc.obelisk_cells.append(cell)
	return enc


static func _pick_floor_cell_near(
	plan: WorldPlan,
	bounds: Rect2i,
	target: Vector2i,
	bait: Vector2i,
	occupied: Dictionary[Vector2i, bool],
	existing: Array[Vector2i],
) -> Vector2i:
	var best: Vector2i = Vector2i(2147483647, 2147483647)
	var best_dist_sq: int = 2147483647
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var c: Vector2i = Vector2i(x, y)
			if occupied.has(c) or not _is_valid_prop_floor(plan, c):
				continue
			if bait.x > -50000 and c.distance_squared_to(bait) < MIN_BAIT_DIST_SQ:
				continue
			var too_close: bool = false
			for other: Vector2i in existing:
				if c.distance_squared_to(other) < MIN_OBELISK_SPACING_SQ:
					too_close = true
					break
			if too_close:
				continue
			var d_sq: int = c.distance_squared_to(target)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best = c
	return best


static func _is_valid_prop_floor(plan: WorldPlan, c: Vector2i) -> bool:
	if not plan.is_floor(c) or not plan.is_floor(c + Vector2i(0, -1)):
		return false
	if plan.is_candle_post_base(c) or plan.is_candle_post_top(c):
		return false
	return true


func build_guard_roster_for_obelisk(obelisk_idx: int) -> Array[StringName]:
	if depth <= 4:
		if (obelisk_idx % 2) == 0:
			return [&"skeleton", &"skeleton", &"skeleton_archer"]
		return [&"skeleton", &"skeleton_archer", &"lava_slime"]
	if (obelisk_idx % 2) == 0:
		return [&"skeleton", &"skeleton", &"skeleton_archer", &"lava_slime"]
	return [&"skeleton", &"skeleton_archer", &"skeleton_archer", &"lava_slime"]


func pick_guard_cells_around(plan: WorldPlan, obelisk_cell: Vector2i, count: int, used: Dictionary[Vector2i, bool]) -> Array[Vector2i]:
	var inner: Rect2i = room.grow(-1)
	var candidates: Array[Vector2i] = []
	for dy: int in range(-3, 4):
		for dx: int in range(-3, 4):
			if dx == 0 and dy == 0:
				continue
			var c: Vector2i = obelisk_cell + Vector2i(dx, dy)
			if c == bait_cell or used.has(c) or not inner.has_point(c):
				continue
			if _is_valid_prop_floor(plan, c):
				candidates.append(c)

	for i: int in range(candidates.size() - 1, 0, -1):
		var swap_idx: int = randi() % (i + 1)
		var tmp: Vector2i = candidates[i]
		candidates[i] = candidates[swap_idx]
		candidates[swap_idx] = tmp

	var chosen: Array[Vector2i] = []
	var take_count: int = mini(count, candidates.size())
	for i: int in range(take_count):
		var picked: Vector2i = candidates[i]
		used[picked] = true
		chosen.append(picked)
	return chosen


func clear() -> void:
	is_cleared = true
