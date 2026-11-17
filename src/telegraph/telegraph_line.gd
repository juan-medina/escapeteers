# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name TelegraphLine
extends Telegraph

const DEFAULT_LINE_LENGTH: float = 160.0
const LINE_WIDTH: float = 1.0
const LOCKED_WIDTH_BOOST: float = 0.5
const DIAGONAL_BOOST: float = 0.4
const RETICLE_SIZE: float = 2.5
const LOCKED_RETICLE_BOOST: float = 1.0
const DASH_LENGTH: float = 3.5

var line_length: float = DEFAULT_LINE_LENGTH
var horizontal_only: bool = false
var target: Node2D = null
var locked_direction: Vector2 = Vector2.RIGHT

var _current_end_point: Vector2 = Vector2.ZERO


func start(new_duration: float = -1.0, new_lock_time: float = -1.0) -> void:
	_update_aim()
	super.start(new_duration, new_lock_time)


func update_telegraph(delta: float) -> void:
	if not is_locked:
		_update_aim()
	super.update_telegraph(delta)


func cancel() -> void:
	target = null
	super.cancel()


func _draw() -> void:
	if not is_active:
		return

	var dir: Vector2 = locked_direction.normalized() if locked_direction.length_squared() > 0.001 else Vector2.RIGHT
	var diagonal_factor: float = 2.0 * absf(dir.x) * absf(dir.y)
	var calc_width: float = LINE_WIDTH + (DIAGONAL_BOOST * diagonal_factor)
	if is_locked:
		calc_width += LOCKED_WIDTH_BOOST

	var draw_color: Color = locked_color if is_locked else base_color
	var r_size: float = (RETICLE_SIZE + LOCKED_RETICLE_BOOST) if is_locked else RETICLE_SIZE

	draw_dashed_line(Vector2.ZERO, _current_end_point, draw_color, calc_width, DASH_LENGTH, true, false)
	draw_line(_current_end_point + Vector2(-r_size, 0.0), _current_end_point + Vector2(r_size, 0.0), draw_color, calc_width, false)
	draw_line(_current_end_point + Vector2(0.0, -r_size), _current_end_point + Vector2(0.0, r_size), draw_color, calc_width, false)


func _update_aim() -> void:
	if target != null:
		if horizontal_only:
			var dir_x: float = -1.0 if target.global_position.x < global_position.x else 1.0
			locked_direction = Vector2(dir_x, 0.0)
		else:
			var diff: Vector2 = target.global_position - global_position
			if diff.length_squared() > 1.0:
				locked_direction = diff.normalized()
	var new_end_point: Vector2 = locked_direction * line_length
	if not new_end_point.is_equal_approx(_current_end_point):
		_current_end_point = new_end_point
		queue_redraw()
