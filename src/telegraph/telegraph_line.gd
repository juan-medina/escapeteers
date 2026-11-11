# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name TelegraphLine
extends Telegraph

@export var line_length: float = 160.0
@export var horizontal_only: bool = false
@export var line_width: float = 1.0
@export var diagonal_boost: float = 0.4
@export var reticle_size: float = 2.5
@export var dash_length: float = 3.5

var target: Node2D = null
var locked_direction: Vector2 = Vector2.RIGHT
var current_end_point: Vector2 = Vector2.ZERO


func update_telegraph(delta: float) -> void:
	if not is_locked:
		if target != null and is_instance_valid(target):
			if horizontal_only:
				var dir_x: float = -1.0 if target.global_position.x < global_position.x else 1.0
				locked_direction = Vector2(dir_x, 0.0)
			else:
				var diff: Vector2 = target.global_position - global_position
				if diff.length_squared() > 1.0:
					locked_direction = diff.normalized()
		current_end_point = locked_direction * line_length

	super.update_telegraph(delta)


func _draw() -> void:
	if not is_active:
		return

	var dir: Vector2 = locked_direction.normalized() if locked_direction.length_squared() > 0.001 else Vector2.RIGHT
	var diagonal_factor: float = 2.0 * absf(dir.x) * absf(dir.y)
	var calc_width: float = line_width + (diagonal_boost * diagonal_factor)
	if is_locked:
		calc_width += 0.5

	var draw_color: Color = locked_color if is_locked else base_color
	var r_size: float = (reticle_size + 1.0) if is_locked else reticle_size

	draw_dashed_line(Vector2.ZERO, current_end_point, draw_color, calc_width, dash_length, true, false)
	draw_line(current_end_point + Vector2(-r_size, 0.0), current_end_point + Vector2(r_size, 0.0), draw_color, calc_width, false)
	draw_line(current_end_point + Vector2(0.0, -r_size), current_end_point + Vector2(0.0, r_size), draw_color, calc_width, false)
