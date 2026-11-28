# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

## Encounter layout and trickle spawner for Rune Plates hold-the-zone chambers and boss sanctuary zones.
class_name RunePlateEncounter
extends RefCounted

const MIN_ROOM_DIM: int = 20
const PLATE_COUNT: int = 3
const MIN_BAIT_DIST_SQ: int = 25
const MIN_PLATE_SPACING_SQ: int = 49
const OPENING_SPAWN_COUNT: int = 4
const TRICKLE_SPAWN_COUNT: int = 3
const TRICKLE_INTERVAL_EARLY: float = 4.5
const TRICKLE_INTERVAL_DEEP: float = 3.5
const MAX_ALIVE_EARLY: int = 8
const MAX_ALIVE_DEEP: int = 11
const MAX_XP_GRANTS: int = 10

var room: Rect2i = Rect2i()
var bait_cell: Vector2i = Vector2i.ZERO
var plate_cells: Array[Vector2i] = []
var depth: int = 1
var is_triggered: bool = false
var is_cleared: bool = false
var spawn_timer: float = 0.0
var total_spawned: int = 0


static func can_fit_room(room_rect: Rect2i) -> bool:
	return room_rect.size.x >= MIN_ROOM_DIM and room_rect.size.y >= MIN_ROOM_DIM


static func build_for_room(plan: WorldPlan, room_rect: Rect2i) -> RunePlateEncounter:
	var enc: RunePlateEncounter = RunePlateEncounter.new()
	enc.room = room_rect
	enc.depth = plan.get_room_depth(room_rect)
	var occupied: Dictionary[Vector2i, bool] = {}
	enc.bait_cell = _pick_floor_cell_near(plan, room_rect.grow(-3), room_rect.get_center(), Vector2i(-99999, -99999), occupied, [])
	occupied[enc.bait_cell] = true

	var anchors: Array[Vector2i] = _get_triangle_anchors(room_rect, plan._rng.randi_range(0, 3))
	var search_bounds: Rect2i = room_rect.grow(-3)
	for anchor: Vector2i in anchors:
		var cell: Vector2i = _pick_floor_cell_near(plan, search_bounds, anchor, enc.bait_cell, occupied, enc.plate_cells)
		if cell.x == 2147483647:
			enc.plate_cells.clear()
			return enc
		occupied[cell] = true
		enc.plate_cells.append(cell)
	return enc


static func _get_triangle_anchors(room_rect: Rect2i, orientation: int) -> Array[Vector2i]:
	var left_x: int = room_rect.position.x + roundi(float(room_rect.size.x) * 0.24)
	var mid_x: int = room_rect.position.x + roundi(float(room_rect.size.x) * 0.50)
	var right_x: int = room_rect.position.x + roundi(float(room_rect.size.x) * 0.76) - 1
	var top_y: int = room_rect.position.y + roundi(float(room_rect.size.y) * 0.24)
	var mid_y: int = room_rect.position.y + roundi(float(room_rect.size.y) * 0.50)
	var bot_y: int = room_rect.position.y + roundi(float(room_rect.size.y) * 0.76) - 1

	match orientation % 4:
		0:
			return [Vector2i(mid_x, top_y), Vector2i(left_x, bot_y), Vector2i(right_x, bot_y)]
		1:
			return [Vector2i(mid_x, bot_y), Vector2i(left_x, top_y), Vector2i(right_x, top_y)]
		2:
			return [Vector2i(left_x, mid_y), Vector2i(right_x, top_y), Vector2i(right_x, bot_y)]
		_:
			return [Vector2i(right_x, mid_y), Vector2i(left_x, top_y), Vector2i(left_x, bot_y)]


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
			if occupied.has(c) or not _is_open_plate_floor(plan, c):
				continue
			if bait.x > -50000 and c.distance_squared_to(bait) < MIN_BAIT_DIST_SQ:
				continue
			var too_close: bool = false
			for other: Vector2i in existing:
				if c.distance_squared_to(other) < MIN_PLATE_SPACING_SQ:
					too_close = true
					break
			if too_close:
				continue
			var d_sq: int = c.distance_squared_to(target)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best = c
	return best


static func _is_open_plate_floor(plan: WorldPlan, c: Vector2i) -> bool:
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var nb: Vector2i = c + Vector2i(dx, dy)
			if not plan.is_floor(nb):
				return false
			if plan.is_candle_post_base(nb) or plan.is_candle_post_top(nb):
				return false
	return plan.is_floor(c + Vector2i(0, -2))


func get_max_alive() -> int:
	return MAX_ALIVE_EARLY if depth <= 5 else MAX_ALIVE_DEEP


func get_trickle_interval() -> float:
	return TRICKLE_INTERVAL_EARLY if depth <= 5 else TRICKLE_INTERVAL_DEEP


func build_spawn_roster(count: int) -> Array[StringName]:
	var roster: Array[StringName] = []
	for i: int in range(count):
		var idx: int = (total_spawned + i) % 5
		if idx == 1 or idx == 3:
			roster.append(&"skeleton_archer")
		elif idx == 4:
			roster.append(&"lava_slime")
		else:
			roster.append(&"skeleton")
	return roster


func clear() -> void:
	is_cleared = true
