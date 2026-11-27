# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

## Slimmer biome-matched stone wall blocking a local shortcut until its lever is pulled.
class_name ShortcutWall
extends StaticBody2D

const ROW_HEIGHT: float = 32.0
const HALF_SIZE: float = 16.0
const SLAB_THICKNESS: float = 8.0
const RUMBLE_DURATION: float = 0.06
const RETRACT_DURATION: float = 0.40

var _is_horizontal: bool = true
var _row_y: float = 0.0
var _opened: bool = false
var _base_pos_a: Vector2 = Vector2.ZERO
var _base_pos_b: Vector2 = Vector2.ZERO

@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _half_a: Sprite2D = $HalfA
@onready var _half_b: Sprite2D = $HalfB
@onready var _dust: CPUParticles2D = $DustParticles


## Configures orientation, collision bounds, and biome palette row.
func setup(is_horizontal: bool, tile_set: int) -> void:
	_is_horizontal = is_horizontal
	_row_y = float(clampi(tile_set, 0, TileClassifier.SET_BASE_ROWS.size() - 1)) * ROW_HEIGHT

	# Duplicate shape per instance so horizontal and vertical walls keep independent sizes.
	var rect_shape: RectangleShape2D = (_collision.shape as RectangleShape2D).duplicate() as RectangleShape2D
	rect_shape.size = Vector2(32.0, SLAB_THICKNESS) if is_horizontal else Vector2(SLAB_THICKNESS, 32.0)
	_collision.shape = rect_shape

	_dust.emission_rect_extents = Vector2(14.0, 4.0) if is_horizontal else Vector2(4.0, 14.0)
	_base_pos_a = Vector2(-16.0, -8.0) if is_horizontal else Vector2(-8.0, -16.0)
	_base_pos_b = Vector2(0.0, -8.0) if is_horizontal else Vector2(-8.0, 0.0)
	_half_a.visible = true
	_half_b.visible = true
	_apply_retract_progress(0.0)


## Disables collision immediately and slides both wall halves into the flanking walls.
func open_animated() -> void:
	if _opened:
		return
	_opened = true
	_collision.set_deferred(&"disabled", true)
	_dust.restart()

	var tween: Tween = create_tween()
	tween.tween_method(_apply_rumble_progress, 0.0, 1.0, RUMBLE_DURATION)
	tween.tween_method(_apply_retract_progress, 0.0, 1.0, RETRACT_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_on_retract_finished)


func _apply_rumble_progress(t: float) -> void:
	var shake: float = sin(t * PI * 4.0)
	var offset: Vector2 = Vector2(0.0, shake) if _is_horizontal else Vector2(shake, 0.0)
	_half_a.position = _base_pos_a + offset
	_half_b.position = _base_pos_b + offset


func _apply_retract_progress(t: float) -> void:
	var retract_px: float = clampf(roundf(t * HALF_SIZE), 0.0, HALF_SIZE)
	var rem: float = HALF_SIZE - retract_px
	if _is_horizontal:
		_half_a.position = _base_pos_a
		_half_a.region_rect = Rect2(retract_px, _row_y, rem, HALF_SIZE)
		_half_b.position = _base_pos_b + Vector2(retract_px, 0.0)
		_half_b.region_rect = Rect2(HALF_SIZE, _row_y, rem, HALF_SIZE)
	else:
		_half_a.position = _base_pos_a
		_half_a.region_rect = Rect2(32.0, _row_y + retract_px, HALF_SIZE, rem)
		_half_b.position = _base_pos_b + Vector2(0.0, retract_px)
		_half_b.region_rect = Rect2(32.0, _row_y + HALF_SIZE, HALF_SIZE, rem)


func _on_retract_finished() -> void:
	_half_a.visible = false
	_half_b.visible = false
