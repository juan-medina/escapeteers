# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

## Draws the floor ritual ring, charging progress arc, and completion shockwave beneath a RunePlate.
class_name RuneRing
extends Node2D

const REDRAW_INTERVAL: float = 1.0 / 12.0
const POINT_COUNT: int = 44
const ARC_SEGMENTS: int = 48
const SHOCKWAVE_DURATION: float = 0.45
const SHOCKWAVE_MAX_RADIUS: float = 110.0

const DORMANT_RING_COLOR: Color = Color(0.40, 0.35, 0.55, 0.42)
const READY_FILL_COLOR: Color = Color(0.25, 0.72, 1.0, 0.06)
const CHARGING_FILL_COLOR: Color = Color(0.92, 0.85, 0.32, 0.11)
const DECAYING_FILL_COLOR: Color = Color(0.95, 0.52, 0.20, 0.07)
const COMPLETED_FILL_COLOR: Color = Color(0.35, 0.95, 0.58, 0.10)
const CHARGING_ARC_COLOR: Color = Color(0.95, 0.92, 0.42, 0.95)
const DECAYING_ARC_COLOR: Color = Color(1.0, 0.55, 0.22, 0.88)
const COMPLETED_RING_COLOR: Color = Color(0.48, 1.0, 0.65, 0.80)

var radius: float = 44.0:
	set(value):
		if not is_equal_approx(radius, value):
			radius = value
			_rebuild_ring()
			queue_redraw()

var _state: int = 0
var _progress: float = 0.0
var _time: float = 0.0
var _redraw_timer: float = 0.0
var _shockwave_timer: float = 0.0
var _ring_points: PackedVector2Array = PackedVector2Array()
var _fill_points: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	z_index = -1
	set_process(false)
	_rebuild_ring()
	queue_redraw()


func sync_state(plate_state: int, plate_progress: float) -> void:
	_state = plate_state
	_progress = plate_progress
	set_process(_state != 0 or _shockwave_timer > 0.0)
	queue_redraw()


func trigger_completed() -> void:
	_state = 4
	_progress = 1.0
	_shockwave_timer = SHOCKWAVE_DURATION
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _shockwave_timer > 0.0:
		_shockwave_timer = maxf(0.0, _shockwave_timer - delta)
		queue_redraw()
		return
	if _state == 0:
		set_process(false)
		return
	_redraw_timer += delta
	if _redraw_timer >= REDRAW_INTERVAL:
		_redraw_timer = fmod(_redraw_timer, REDRAW_INTERVAL)
		queue_redraw()


func _rebuild_ring() -> void:
	_fill_points.resize(POINT_COUNT)
	_ring_points.resize(POINT_COUNT + 1)
	for i: int in range(POINT_COUNT):
		var theta: float = (TAU * float(i)) / float(POINT_COUNT)
		var pt: Vector2 = Vector2(cos(theta), sin(theta)) * radius
		_fill_points[i] = pt
		_ring_points[i] = pt
	_ring_points[POINT_COUNT] = _ring_points[0]


func _draw() -> void:
	if _fill_points.is_empty():
		return
	if _state == 0:
		draw_polyline(_ring_points, DORMANT_RING_COLOR, 1.2, true)
	elif _state == 1:
		draw_colored_polygon(_fill_points, READY_FILL_COLOR)
		var pulse_a: float = 0.48 + 0.16 * sin(_time * 3.8)
		draw_polyline(_ring_points, Color(0.32, 0.78, 1.0, pulse_a), 1.5, true)
	elif _state == 2:
		draw_colored_polygon(_fill_points, CHARGING_FILL_COLOR)
		draw_polyline(_ring_points, Color(0.45, 0.85, 1.0, 0.65), 1.4, true)
		if _progress > 0.005:
			draw_arc(Vector2.ZERO, radius, -PI * 0.5, -PI * 0.5 + TAU * _progress, ARC_SEGMENTS, CHARGING_ARC_COLOR, 2.5, true)
	elif _state == 3:
		draw_colored_polygon(_fill_points, DECAYING_FILL_COLOR)
		draw_polyline(_ring_points, Color(0.65, 0.45, 0.30, 0.45), 1.3, true)
		if _progress > 0.005:
			draw_arc(Vector2.ZERO, radius, -PI * 0.5, -PI * 0.5 + TAU * _progress, ARC_SEGMENTS, DECAYING_ARC_COLOR, 2.5, true)
	else:
		draw_colored_polygon(_fill_points, COMPLETED_FILL_COLOR)
		draw_polyline(_ring_points, COMPLETED_RING_COLOR, 1.8, true)

	if _shockwave_timer > 0.0:
		var t: float = 1.0 - clampf(_shockwave_timer / SHOCKWAVE_DURATION, 0.0, 1.0)
		var wave_r: float = lerpf(radius, SHOCKWAVE_MAX_RADIUS, t)
		var wave_a: float = clampf(1.0 - t, 0.0, 1.0) * 0.90
		draw_arc(Vector2.ZERO, wave_r, 0.0, TAU, ARC_SEGMENTS, Color(0.65, 1.0, 0.82, wave_a), 2.5, true)
