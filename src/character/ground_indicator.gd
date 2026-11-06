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

@export var radius_x: float = DEFAULT_RADIUS_X:
	set(value):
		if not is_equal_approx(radius_x, value):
			radius_x = value
			_rebuild_ellipse()
			queue_redraw()
@export var radius_y: float = DEFAULT_RADIUS_Y:
	set(value):
		if not is_equal_approx(radius_y, value):
			radius_y = value
			_rebuild_ellipse()
			queue_redraw()
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

var _shadow_points: PackedVector2Array = PackedVector2Array()
var _ring_points: PackedVector2Array = PackedVector2Array()
var _chevron_poly: PackedVector2Array = PackedVector2Array()
var _border_poly: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	z_index = -1
	_chevron_poly.resize(4)
	_border_poly.resize(5)
	_rebuild_ellipse()
	queue_redraw()


func _rebuild_ellipse() -> void:
	_shadow_points.resize(POINT_COUNT)
	_ring_points.resize(POINT_COUNT + 1)
	for i: int in range(POINT_COUNT):
		var theta: float = (TAU * float(i)) / float(POINT_COUNT)
		var pt: Vector2 = Vector2(cos(theta) * radius_x, sin(theta) * radius_y)
		_shadow_points[i] = pt
		_ring_points[i] = pt
	_ring_points[POINT_COUNT] = _ring_points[0]


func _draw() -> void:
	_draw_shadow()
	_draw_ring()
	if is_player and facing_direction != Vector2.ZERO:
		_draw_facing_arrow()


func _draw_shadow() -> void:
	if _shadow_points.is_empty():
		_rebuild_ellipse()
	draw_colored_polygon(_shadow_points, SHADOW_COLOR)


func _draw_ring() -> void:
	if _ring_points.is_empty():
		_rebuild_ellipse()
	draw_polyline(_ring_points, _get_ring_color(), RING_WIDTH, true)


func _draw_facing_arrow() -> void:
	var dir: Vector2 = facing_direction.normalized()
	var rim_point: Vector2 = Vector2(dir.x * radius_x, dir.y * radius_y)
	var anchor: Vector2 = rim_point + dir * CHEVRON_OFFSET
	var perp: Vector2 = Vector2(-dir.y, dir.x)

	var tip: Vector2 = anchor + dir * CHEVRON_LENGTH
	var left: Vector2 = anchor - dir * CHEVRON_WING_BACK + perp * CHEVRON_WING_WIDTH
	var right: Vector2 = anchor - dir * CHEVRON_WING_BACK - perp * CHEVRON_WING_WIDTH
	var notch: Vector2 = anchor + dir * CHEVRON_NOTCH_FORWARD

	if _chevron_poly.size() != 4:
		_chevron_poly.resize(4)
	_chevron_poly[0] = tip
	_chevron_poly[1] = left
	_chevron_poly[2] = notch
	_chevron_poly[3] = right

	if _border_poly.size() != 5:
		_border_poly.resize(5)
	_border_poly[0] = left
	_border_poly[1] = tip
	_border_poly[2] = right
	_border_poly[3] = notch
	_border_poly[4] = left

	# Dark outline so the chevron remains readable on both dark floors and bright lights
	draw_polyline(_border_poly, ARROW_BORDER_COLOR, 1.5, true)
	draw_colored_polygon(_chevron_poly, PLAYER_ARROW_COLOR)


func _get_ring_color() -> Color:
	if is_player:
		return PLAYER_RING_COLOR
	if is_recruited:
		return COMPANION_RING_COLOR
	return UNRECRUITED_RING_COLOR
