# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name ClosingSpikeHazard
extends RefCounted


class SpikeRing:
	extends RefCounted
	var cells: Array[Vector2i] = []
	var state: RingState = RingState.IDLE
	var timer: float = 0.0
	var frame: int = 0


enum RingState {
	IDLE,
	TELEGRAPH_1,
	TELEGRAPH_2,
	ACTIVE,
	RETRACTING,
}

const RING_THICKNESS: int = 2
const MIN_SAFE_CORE_SIZE: int = 2
const MAX_RINGS: int = 12
const CENTER_SPAWN_HALF_SIZE: int = 2
const ENTRY_ARM_MARGIN: int = 2
const INITIAL_ARM_DELAY: float = 0.6
const RING_TELEGRAPH_1_TIME: float = 1.0
const RING_TELEGRAPH_2_TIME: float = 0.35
const NEXT_RING_INTERVAL: float = 3.0
const RETRACT_STEP_TIME: float = 0.10
const RETREAT_RESET_DELAY: float = 1.0

var room: Rect2i = Rect2i()
var safe_rect: Rect2i = Rect2i()
var rings: Array[SpikeRing] = []
var cell_to_ring: Dictionary[Vector2i, int] = {}
var is_armed: bool = false
var is_cleared: bool = false

var _next_ring_idx: int = 0
var _ring_delay_timer: float = 0.0
var _retreat_timer: float = 0.0


static func compute_ring_count(room_rect: Rect2i) -> int:
	# Account for north top-wall row when computing playable interior height.
	var min_dim: int = mini(room_rect.size.x, room_rect.size.y - 1)
	var usable: int = maxi(0, min_dim - MIN_SAFE_CORE_SIZE)
	var possible: int = floori(float(usable) / float(RING_THICKNESS * 2))
	return clampi(possible, 0, MAX_RINGS)


static func can_fit_room(room_rect: Rect2i) -> bool:
	return room_rect.size.x >= 20 and room_rect.size.y >= 20 and compute_ring_count(room_rect) >= 2


static func build_for_room(plan: WorldPlan, room_rect: Rect2i) -> ClosingSpikeHazard:
	var hazard: ClosingSpikeHazard = ClosingSpikeHazard.new()
	hazard.room = room_rect
	var num_rings: int = compute_ring_count(room_rect)
	var inner_bounds: Rect2i = Rect2i(room_rect.position.x, room_rect.position.y + 1, room_rect.size.x, room_rect.size.y - 1)
	var inset: int = num_rings * RING_THICKNESS
	var raw_safe: Rect2i = Rect2i(inner_bounds.position + Vector2i(inset, inset), inner_bounds.size - Vector2i(inset * 2, inset * 2))
	if raw_safe.size.x > 0 and raw_safe.size.y > 0:
		hazard.safe_rect = raw_safe
	else:
		var center: Vector2i = inner_bounds.get_center()
		var core_pos: Vector2i = center - Vector2i(CENTER_SPAWN_HALF_SIZE, CENTER_SPAWN_HALF_SIZE)
		var core_size: Vector2i = Vector2i(CENTER_SPAWN_HALF_SIZE * 2, CENTER_SPAWN_HALF_SIZE * 2)
		hazard.safe_rect = Rect2i(core_pos, core_size).intersection(inner_bounds)

	for _i: int in range(num_rings):
		hazard.rings.append(SpikeRing.new())

	for y: int in range(inner_bounds.position.y, inner_bounds.end.y):
		for x: int in range(inner_bounds.position.x, inner_bounds.end.x):
			var cell: Vector2i = Vector2i(x, y)
			var dx_edge: int = mini(x - inner_bounds.position.x, inner_bounds.end.x - 1 - x)
			var dy_edge: int = mini(y - inner_bounds.position.y, inner_bounds.end.y - 1 - y)
			var edge_dist: int = mini(dx_edge, dy_edge)
			var ring_idx: int = floori(float(edge_dist) / float(RING_THICKNESS))
			if ring_idx < 0 or ring_idx >= num_rings:
				continue
			if not plan.is_floor(cell) or not plan.is_floor(cell + Vector2i(0, -1)):
				continue
			if plan.no_prop_cells.has(cell) or plan.is_candle_post_base(cell) or plan.is_candle_post_top(cell):
				continue
			hazard.rings[ring_idx].cells.append(cell)
			hazard.cell_to_ring[cell] = ring_idx

	return hazard


func should_arm_for_cell(player_cell: Vector2i) -> bool:
	return not is_armed and not is_cleared and room.grow(-ENTRY_ARM_MARGIN).has_point(player_cell)


func arm() -> void:
	is_armed = true
	_next_ring_idx = 0
	_ring_delay_timer = INITIAL_ARM_DELAY
	_retreat_timer = 0.0


func disarm() -> void:
	is_armed = false
	_next_ring_idx = 0
	_ring_delay_timer = 0.0
	_retreat_timer = 0.0
	for ring: SpikeRing in rings:
		if ring.frame > 0 or ring.state != RingState.IDLE:
			ring.state = RingState.RETRACTING
			ring.timer = RETRACT_STEP_TIME


func clear() -> void:
	is_cleared = true
	disarm()


func trigger_ring(ring_idx: int) -> bool:
	if ring_idx < 0 or ring_idx >= rings.size():
		return false
	var ring: SpikeRing = rings[ring_idx]
	if ring.state == RingState.IDLE or ring.state == RingState.RETRACTING:
		ring.state = RingState.TELEGRAPH_1
		ring.timer = RING_TELEGRAPH_1_TIME
		ring.frame = 1
		return true
	return false


func update_player_presence(delta: float, player_cell: Vector2i) -> void:
	if is_cleared:
		return
	if not is_armed:
		if should_arm_for_cell(player_cell):
			arm()
	elif room.has_point(player_cell):
		_retreat_timer = 0.0
	else:
		_retreat_timer += delta
		if _retreat_timer >= RETREAT_RESET_DELAY:
			disarm()


func update(delta: float, auto_advance: bool = true) -> Dictionary:
	var changed_rings: Array[int] = []
	var telegraph_started: bool = false
	var snapped_active: bool = false

	if is_armed and not is_cleared and auto_advance and _next_ring_idx < rings.size():
		_ring_delay_timer -= delta
		if _ring_delay_timer <= 0.0:
			if trigger_ring(_next_ring_idx):
				changed_rings.append(_next_ring_idx)
				telegraph_started = true
			_next_ring_idx += 1
			_ring_delay_timer = RING_TELEGRAPH_1_TIME + RING_TELEGRAPH_2_TIME + NEXT_RING_INTERVAL

	for i: int in range(rings.size()):
		var ring: SpikeRing = rings[i]
		var prev_frame: int = ring.frame
		match ring.state:
			RingState.TELEGRAPH_1:
				ring.timer -= delta
				if ring.timer <= 0.0:
					ring.state = RingState.TELEGRAPH_2
					ring.timer = RING_TELEGRAPH_2_TIME
					ring.frame = 2
			RingState.TELEGRAPH_2:
				ring.timer -= delta
				if ring.timer <= 0.0:
					ring.state = RingState.ACTIVE
					ring.timer = 0.0
					ring.frame = 3
					snapped_active = true
			RingState.RETRACTING:
				ring.timer -= delta
				if ring.timer <= 0.0:
					ring.frame = maxi(0, ring.frame - 1)
					if ring.frame <= 0:
						ring.state = RingState.IDLE
						ring.timer = 0.0
					else:
						ring.timer = RETRACT_STEP_TIME
		if ring.frame != prev_frame and not changed_rings.has(i):
			changed_rings.append(i)

	return {
		&"changed_rings": changed_rings,
		&"telegraph_started": telegraph_started,
		&"snapped_active": snapped_active,
	}


func get_cell_frame(cell: Vector2i) -> int:
	if not cell_to_ring.has(cell):
		return 0
	return rings[cell_to_ring[cell]].frame


func is_cell_active(cell: Vector2i) -> bool:
	return get_cell_frame(cell) == 3


func get_active_safe_rect() -> Rect2i:
	if not is_armed or is_cleared:
		return Rect2i()
	var active_rings: int = 0
	for i: int in range(rings.size()):
		if rings[i].state == RingState.ACTIVE:
			active_rings = i + 1
	if active_rings <= 0:
		return Rect2i()
	if active_rings >= rings.size():
		return safe_rect
	var inner_bounds: Rect2i = Rect2i(room.position.x, room.position.y + 1, room.size.x, room.size.y - 1)
	var inset: int = active_rings * RING_THICKNESS
	var dynamic_safe: Rect2i = Rect2i(
		inner_bounds.position + Vector2i(inset, inset),
		inner_bounds.size - Vector2i(inset * 2, inset * 2),
	)
	if dynamic_safe.size.x <= 0 or dynamic_safe.size.y <= 0:
		return safe_rect
	return dynamic_safe
