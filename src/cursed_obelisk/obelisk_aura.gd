# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

## Draws the pulsing immunity aura ring and link tethers beneath an active obelisk or boss pylon.
class_name ObeliskAura
extends Node2D

const REDRAW_INTERVAL: float = 1.0 / 12.0
const POINT_COUNT: int = 48
const FILL_COLOR: Color = Color(0.52, 0.18, 0.92, 0.055)
const TETHER_ORIGIN: Vector2 = Vector2(0.0, -8.0)

var radius: float = 76.0:
	set(value):
		if not is_equal_approx(radius, value):
			radius = value
			_rebuild_ring()
			queue_redraw()

var _active: bool = false
var _time: float = 0.0
var _redraw_timer: float = 0.0
var _tethers: Array[Vector2] = []
var _ring_points: PackedVector2Array = PackedVector2Array()
var _fill_points: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	z_index = -1
	visible = false
	set_process(false)
	_rebuild_ring()


func set_active(enabled: bool) -> void:
	if _active == enabled:
		return
	_active = enabled
	visible = enabled
	set_process(enabled)
	if not enabled:
		_tethers.clear()
	_rebuild_ring()
	queue_redraw()


func set_tethers(local_targets: Array[Vector2]) -> void:
	_tethers = local_targets
	if _active:
		queue_redraw()


func _process(delta: float) -> void:
	_time += delta
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
	if not _active or _fill_points.is_empty():
		return
	draw_colored_polygon(_fill_points, FILL_COLOR)
	var pulse: float = 0.45 + 0.15 * sin(_time * 4.0)
	draw_polyline(_ring_points, Color(0.78, 0.42, 1.0, pulse), 1.5, true)
	var tether_color: Color = Color(0.85, 0.50, 1.0, 0.38 + 0.14 * sin(_time * 6.0))
	for target_pos: Vector2 in _tethers:
		draw_line(TETHER_ORIGIN, target_pos, tether_color, 1.0)
