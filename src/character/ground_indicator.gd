# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name GroundIndicator
extends Node2D

const SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.4)
const PLAYER_RING_COLOR: Color = Color(0.15, 0.85, 1.0, 0.95)
const PLAYER_ARROW_COLOR: Color = Color(0.25, 0.95, 1.0, 1.0)
const ARROW_BORDER_COLOR: Color = Color(0.02, 0.08, 0.18, 0.95)
const COMPANION_RING_COLOR: Color = Color(0.2, 0.5, 0.8, 0.5)
const UNRECRUITED_RING_COLOR: Color = Color(1.0, 0.8, 0.3, 0.45)

const DEFAULT_RADIUS_X: float = 7.0
const DEFAULT_RADIUS_Y: float = 3.5
const RING_WIDTH: float = 1.0
const CHEVRON_OFFSET: float = 5.0
const CHEVRON_LENGTH: float = 4.5
const CHEVRON_WING_WIDTH: float = 4.5
const CHEVRON_WING_BACK: float = 1.5
const CHEVRON_NOTCH_FORWARD: float = 0.5
const POINT_COUNT: int = 24

@export var radius_x: float = DEFAULT_RADIUS_X
@export var radius_y: float = DEFAULT_RADIUS_Y
@export var is_player: bool = false:
	set(value):
		if is_player != value:
			is_player = value
			queue_redraw()
@export var is_recruited: bool = false:
	set(value):
		if is_recruited != value:
			is_recruited = value
			queue_redraw()
@export var facing_direction: Vector2 = Vector2.RIGHT:
	set(value):
		if value != Vector2.ZERO and facing_direction != value:
			facing_direction = value.normalized()
			queue_redraw()


func _ready() -> void:
	z_index = -1
	queue_redraw()


func _draw() -> void:
	_draw_shadow()
	_draw_ring()
	if is_player and facing_direction != Vector2.ZERO:
		_draw_facing_arrow()


func _draw_shadow() -> void:
	var shadow_points: PackedVector2Array = PackedVector2Array()
	for i: int in range(POINT_COUNT):
		var theta: float = (TAU * float(i)) / float(POINT_COUNT)
		shadow_points.append(Vector2(cos(theta) * radius_x, sin(theta) * radius_y))
	draw_colored_polygon(shadow_points, SHADOW_COLOR)


func _draw_ring() -> void:
	var ring_color: Color = _get_ring_color()
	var ring_points: PackedVector2Array = PackedVector2Array()
	for i: int in range(POINT_COUNT + 1):
		var theta: float = (TAU * float(i)) / float(POINT_COUNT)
		ring_points.append(Vector2(cos(theta) * radius_x, sin(theta) * radius_y))
	draw_polyline(ring_points, ring_color, RING_WIDTH, true)


func _draw_facing_arrow() -> void:
	var dir: Vector2 = facing_direction.normalized()
	var rim_point: Vector2 = Vector2(dir.x * radius_x, dir.y * radius_y)
	var anchor: Vector2 = rim_point + dir * CHEVRON_OFFSET
	var perp: Vector2 = Vector2(-dir.y, dir.x)

	var tip: Vector2 = anchor + dir * CHEVRON_LENGTH
	var left: Vector2 = anchor - dir * CHEVRON_WING_BACK + perp * CHEVRON_WING_WIDTH
	var right: Vector2 = anchor - dir * CHEVRON_WING_BACK - perp * CHEVRON_WING_WIDTH
	var notch: Vector2 = anchor + dir * CHEVRON_NOTCH_FORWARD

	var chevron_poly: PackedVector2Array = PackedVector2Array([tip, left, notch, right])
	var border_poly: PackedVector2Array = PackedVector2Array([left, tip, right, notch, left])

	# Dark outline so the chevron remains readable on both dark floors and bright lights
	draw_polyline(border_poly, ARROW_BORDER_COLOR, 1.5, true)
	draw_colored_polygon(chevron_poly, PLAYER_ARROW_COLOR)


func _get_ring_color() -> Color:
	if is_player:
		return PLAYER_RING_COLOR
	if is_recruited:
		return COMPANION_RING_COLOR
	return UNRECRUITED_RING_COLOR
