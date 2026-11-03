# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name PlayerMarker
extends Control

const ARROW_COLOR: Color = Color(0.2, 0.9, 1.0, 0.95)
const BORDER_COLOR: Color = Color(1.0, 1.0, 1.0, 0.95)

var _points: PackedVector2Array = [
	Vector2(6.0, 0.0),
	Vector2(-5.0, -4.5),
	Vector2(-2.5, 0.0),
	Vector2(-5.0, 4.5),
]
var _outline_points: PackedVector2Array = [
	Vector2(6.0, 0.0),
	Vector2(-5.0, -4.5),
	Vector2(-2.5, 0.0),
	Vector2(-5.0, 4.5),
	Vector2(6.0, 0.0),
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_colored_polygon(_points, ARROW_COLOR)
	draw_polyline(_outline_points, BORDER_COLOR, 1.0)
