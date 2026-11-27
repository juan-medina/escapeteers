# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

## Reusable state and wave planner for lock-in wave ambush chambers and multi-wave arenas.
class_name WaveAmbush
extends RefCounted


class ExitOpening:
	extends RefCounted
	var is_horizontal: bool = true
	var cells: Array[Vector2i] = []


enum State {
	WAITING,
	WAVE_DELAY,
	PENTAGRAM_TELEGRAPH,
	WAVE_ACTIVE,
	CLEARED,
}

const TOTAL_WAVES: int = 3
const WAVE_START_DELAY: float = 0.8
const INTER_WAVE_DELAY: float = 1.4
const PENTAGRAM_DELAY: float = 0.65
const MIN_PLAYER_SPAWN_DIST_SQ: int = 16

var room: Rect2i = Rect2i()
var bait_cell: Vector2i = Vector2i.ZERO
var exits: Array[ExitOpening] = []
var depth: int = 1
var base_quota: int = 6
var state: State = State.WAITING
var current_wave: int = 0
var wave_remaining: int = 0
var is_locked: bool = false
var is_cleared: bool = false
var timer: float = 0.0
var pending_spawns: Array[Dictionary] = []


static func can_fit_room(room_rect: Rect2i) -> bool:
	return room_rect.size.x >= 18 and room_rect.size.y >= 18


static func build_for_room(plan: WorldPlan, room_rect: Rect2i) -> WaveAmbush:
	var ambush: WaveAmbush = WaveAmbush.new()
	ambush.room = room_rect
	ambush.depth = plan.get_room_depth(room_rect)
	ambush.base_quota = plan.get_room_enemy_quota(room_rect)
	ambush.exits = _collect_exit_openings(plan, room_rect)
	ambush.bait_cell = _pick_bait_cell(plan, room_rect)
	return ambush


static func _collect_exit_openings(plan: WorldPlan, room_rect: Rect2i) -> Array[ExitOpening]:
	var found: Array[ExitOpening] = []
	_scan_horizontal_face(plan, room_rect, room_rect.position.y - 1, 1, found)
	_scan_horizontal_face(plan, room_rect, room_rect.end.y, -1, found)
	_scan_vertical_face(plan, room_rect, room_rect.position.x - 1, 1, found)
	_scan_vertical_face(plan, room_rect, room_rect.end.x, -1, found)
	return found


static func _scan_horizontal_face(
	plan: WorldPlan,
	room_rect: Rect2i,
	edge_y: int,
	inward_dy: int,
	out: Array[ExitOpening],
) -> void:
	var current: Array[Vector2i] = []
	for x: int in range(room_rect.position.x, room_rect.end.x):
		var c: Vector2i = Vector2i(x, edge_y)
		if plan.is_floor(c) and plan.is_floor(c + Vector2i(0, inward_dy)):
			current.append(c)
		elif not current.is_empty():
			var op: ExitOpening = ExitOpening.new()
			op.is_horizontal = true
			op.cells = current
			out.append(op)
			current = []
	if not current.is_empty():
		var op_end: ExitOpening = ExitOpening.new()
		op_end.is_horizontal = true
		op_end.cells = current
		out.append(op_end)


static func _scan_vertical_face(
	plan: WorldPlan,
	room_rect: Rect2i,
	edge_x: int,
	inward_dx: int,
	out: Array[ExitOpening],
) -> void:
	var current: Array[Vector2i] = []
	for y: int in range(room_rect.position.y, room_rect.end.y):
		var c: Vector2i = Vector2i(edge_x, y)
		if plan.is_floor(c) and plan.is_floor(c + Vector2i(inward_dx, 0)) and plan.is_floor(c + Vector2i(0, -1)):
			current.append(c)
		elif not current.is_empty():
			var op: ExitOpening = ExitOpening.new()
			op.is_horizontal = false
			op.cells = current
			out.append(op)
			current = []
	if not current.is_empty():
		var op_end: ExitOpening = ExitOpening.new()
		op_end.is_horizontal = false
		op_end.cells = current
		out.append(op_end)


static func _pick_bait_cell(plan: WorldPlan, room_rect: Rect2i) -> Vector2i:
	var center: Vector2i = room_rect.get_center()
	var best: Vector2i = center
	var best_dist_sq: int = 2147483647
	var inner: Rect2i = room_rect.grow(-3)
	for y: int in range(inner.position.y, inner.end.y):
		for x: int in range(inner.position.x, inner.end.x):
			var c: Vector2i = Vector2i(x, y)
			if not plan.is_floor(c) or not plan.is_floor(c + Vector2i(0, -1)):
				continue
			if plan.is_candle_post_base(c) or plan.is_candle_post_top(c):
				continue
			var d_sq: int = c.distance_squared_to(center)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best = c
	return best


func start() -> void:
	is_locked = true
	current_wave = 1
	state = State.WAVE_DELAY
	timer = WAVE_START_DELAY
	wave_remaining = 0
	pending_spawns.clear()


func begin_pentagrams(spawns: Array[Dictionary]) -> void:
	pending_spawns = spawns
	state = State.PENTAGRAM_TELEGRAPH
	timer = PENTAGRAM_DELAY


func activate_wave(spawned_count: int) -> void:
	wave_remaining = spawned_count
	pending_spawns.clear()
	state = State.WAVE_ACTIVE
	timer = 0.0


func advance_or_clear() -> bool:
	if current_wave < TOTAL_WAVES:
		current_wave += 1
		state = State.WAVE_DELAY
		timer = INTER_WAVE_DELAY
		return false
	clear()
	return true


func clear() -> void:
	is_cleared = true
	is_locked = false
	state = State.CLEARED
	wave_remaining = 0
	pending_spawns.clear()


func update(delta: float) -> Dictionary:
	var ready_for_pentagrams: bool = false
	var ready_to_materialize: bool = false
	if state == State.WAVE_DELAY:
		timer -= delta
		if timer <= 0.0:
			timer = 0.0
			ready_for_pentagrams = true
	elif state == State.PENTAGRAM_TELEGRAPH:
		timer -= delta
		if timer <= 0.0:
			timer = 0.0
			ready_to_materialize = true
	return {
		&"ready_for_pentagrams": ready_for_pentagrams,
		&"ready_to_materialize": ready_to_materialize,
		&"wave": current_wave,
	}


func build_wave_roster(wave_idx: int) -> Array[StringName]:
	var roster: Array[StringName] = []
	if wave_idx == 1:
		var count: int = maxi(4, roundi(float(base_quota) * 0.55))
		for i: int in range(count):
			roster.append(&"lava_slime" if (i % 4 == 3) else &"skeleton")
	elif wave_idx == 2:
		var count: int = maxi(7, roundi(float(base_quota) * 1.05))
		for i: int in range(count):
			var mod: int = i % 5
			if mod == 1 or mod == 3:
				roster.append(&"skeleton_archer")
			elif mod == 4:
				roster.append(&"lava_slime")
			else:
				roster.append(&"skeleton")
	else:
		# Double the normal NECRO_CRYPT summoner count (1->2 at depth<=6, 2->4 at depth>=7).
		var necro_count: int = 2 if depth <= 6 else 4
		for _i: int in range(necro_count):
			roster.append(&"necromancer")
		var escort_count: int = maxi(4, roundi(float(base_quota) * 0.50))
		for j: int in range(escort_count):
			roster.append(&"skeleton_archer" if (j % 3 == 1) else &"skeleton")
	return roster


func pick_spawn_cells(plan: WorldPlan, count: int, player_cell: Vector2i) -> Array[Vector2i]:
	return pick_spawn_cells_in_room(plan, room, count, player_cell)


static func pick_spawn_cells_in_room(plan: WorldPlan, room_rect: Rect2i, count: int, player_cell: Vector2i) -> Array[Vector2i]:
	var inner: Rect2i = room_rect.grow(-2)
	var preferred: Array[Vector2i] = []
	var fallback: Array[Vector2i] = []
	for y: int in range(inner.position.y, inner.end.y):
		for x: int in range(inner.position.x, inner.end.x):
			var c: Vector2i = Vector2i(x, y)
			if not plan.is_floor(c) or not plan.is_floor(c + Vector2i(0, -1)):
				continue
			if plan.is_candle_post_base(c) or plan.is_candle_post_top(c):
				continue
			fallback.append(c)
			if c.distance_squared_to(player_cell) >= MIN_PLAYER_SPAWN_DIST_SQ:
				preferred.append(c)

	var pool: Array[Vector2i] = preferred if preferred.size() >= count else fallback
	if pool.is_empty():
		return []

	var chosen: Array[Vector2i] = []
	var used: Dictionary[Vector2i, bool] = {}
	var base_angle: float = randf() * TAU
	var step: float = TAU / float(maxi(1, count))
	for i: int in range(count):
		var target_angle: float = base_angle + float(i) * step
		var dir: Vector2 = Vector2.from_angle(target_angle)
		var best_cell: Vector2i = pool[randi() % pool.size()]
		var best_score: float = -INF
		for _attempt: int in range(18):
			var cand: Vector2i = pool[randi() % pool.size()]
			if used.has(cand):
				continue
			var delta_v: Vector2 = Vector2(cand - player_cell)
			var align: float = delta_v.normalized().dot(dir) if delta_v.length_squared() > 0.1 else 0.0
			if align > best_score:
				best_score = align
				best_cell = cand
		used[best_cell] = true
		chosen.append(best_cell)
	return chosen
