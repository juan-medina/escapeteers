# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name HeroVfx
extends Node2D

const SPRINT_PUFF_COUNT: int = 3
const SPRINT_CYCLE_SPEED: float = 3.2
const SPRINT_PHASE_OFFSETS: Array[float] = [0.0, 0.33, 0.66]
const SPRINT_SIDE_OFFSETS: Array[float] = [-2.5, 2.0, -0.5]
const SPRINT_DUST_LIGHT: Color = Color(0.90, 0.85, 0.74, 0.85)
const SPRINT_DUST_DARK: Color = Color(0.68, 0.62, 0.52, 0.65)
const SPRINT_SHADOW: Color = Color(0.14, 0.12, 0.10, 0.65)

const STRIKE_DURATION: float = 0.22
const STRIKE_ARC_POINTS: int = 5
const STRIKE_HEAVY_COLOR: Color = Color(1.0, 0.88, 0.28, 0.95)
const STRIKE_KB_COLOR: Color = Color(0.92, 0.97, 1.0, 0.92)
const STRIKE_CORE_COLOR: Color = Color(1.0, 1.0, 0.88, 1.0)
const STRIKE_SHADOW_COLOR: Color = Color(0.18, 0.10, 0.02, 0.75)

const LEVEL_UP_DURATION: float = 0.85
const LEVEL_UP_SPARK_COUNT: int = 5
const LEVEL_UP_RING_POINTS: int = 16
const LEVEL_UP_X_OFFSETS: Array[float] = [-5.0, -2.5, 0.0, 2.5, 5.0]
const LEVEL_UP_PHASE_OFFSETS: Array[float] = [0.0, 0.25, 0.08, 0.35, 0.16]
const LEVEL_UP_GOLD: Color = Color(1.0, 0.86, 0.22, 0.95)
const LEVEL_UP_CORE: Color = Color(1.0, 0.98, 0.78, 1.0)
const LEVEL_UP_SHADOW: Color = Color(0.24, 0.16, 0.0, 0.80)

const DEATH_DURATION: float = 0.65
const DEATH_MOTE_COUNT: int = 6
const DEATH_SOUL_CORE: Color = Color(0.90, 0.98, 1.0, 0.95)
const DEATH_SOUL_OUTER: Color = Color(0.35, 0.85, 1.0, 0.85)
const DEATH_BURST_COLOR: Color = Color(1.0, 0.48, 0.36, 0.90)
const DEATH_SHADOW: Color = Color(0.06, 0.14, 0.24, 0.80)

var head_y: float = -10.0
var feet_y: float = 6.0

var _is_sprinting: bool = false
var _sprint_dir: Vector2 = Vector2.RIGHT
var _time: float = 0.0
var _strike_timer: float = 0.0
var _strike_dir: Vector2 = Vector2.RIGHT
var _strike_is_heavy: bool = false
var _level_up_timer: float = 0.0
var _death_timer: float = 0.0
var _arc_poly: PackedVector2Array = PackedVector2Array()
var _ring_poly: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	z_index = 1
	visible = false
	set_process(false)
	_arc_poly.resize(STRIKE_ARC_POINTS)
	_ring_poly.resize(LEVEL_UP_RING_POINTS + 1)


func set_sprinting(sprinting: bool, move_dir: Vector2) -> void:
	var changed: bool = _is_sprinting != sprinting
	_is_sprinting = sprinting
	if move_dir.length_squared() > 0.001:
		_sprint_dir = move_dir.normalized()
	_update_active_state(changed)


func trigger_knockback_strike(dir: Vector2, is_heavy: bool) -> void:
	if dir.length_squared() > 0.001:
		_strike_dir = dir.normalized()
	_strike_is_heavy = is_heavy
	_strike_timer = STRIKE_DURATION * (1.2 if is_heavy else 1.0)
	_update_active_state(true)


func trigger_level_up() -> void:
	_level_up_timer = LEVEL_UP_DURATION
	_update_active_state(true)


func trigger_death() -> void:
	_is_sprinting = false
	_strike_timer = 0.0
	_level_up_timer = 0.0
	_death_timer = DEATH_DURATION
	_update_active_state(true)


func _update_active_state(force_redraw: bool) -> void:
	var any_active: bool = _is_sprinting or (_strike_timer > 0.0) or (_level_up_timer > 0.0) or (_death_timer > 0.0)
	visible = any_active
	set_process(any_active)
	if force_redraw:
		queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	var state_ended: bool = false

	if _strike_timer > 0.0:
		_strike_timer = maxf(0.0, _strike_timer - delta)
		if _strike_timer <= 0.0:
			state_ended = true

	if _level_up_timer > 0.0:
		_level_up_timer = maxf(0.0, _level_up_timer - delta)
		if _level_up_timer <= 0.0:
			state_ended = true

	if _death_timer > 0.0:
		_death_timer = maxf(0.0, _death_timer - delta)
		if _death_timer <= 0.0:
			state_ended = true

	if state_ended:
		_update_active_state(true)
		if not is_processing():
			return

	queue_redraw()


func _draw() -> void:
	if _is_sprinting:
		_draw_sprint_dust()
	if _strike_timer > 0.0:
		_draw_knockback_strike()
	if _level_up_timer > 0.0:
		_draw_level_up()
	if _death_timer > 0.0:
		_draw_death_soul()


func _draw_sprint_dust() -> void:
	var back_dir: Vector2 = -_sprint_dir
	var perp: Vector2 = Vector2(-back_dir.y, back_dir.x)

	for i: int in range(SPRINT_PUFF_COUNT):
		var phase: float = fmod(_time * SPRINT_CYCLE_SPEED + SPRINT_PHASE_OFFSETS[i], 1.0)
		var alpha: float = 1.0 - phase
		var dist: float = 3.0 + phase * 8.5
		var lift: float = phase * 2.5
		var side: float = SPRINT_SIDE_OFFSETS[i]
		var pos: Vector2 = Vector2(0.0, feet_y) + (back_dir * dist) + (perp * side) + Vector2(0.0, -lift)
		var px: float = roundf(pos.x)
		var py: float = roundf(pos.y)

		var shadow_col: Color = Color(SPRINT_SHADOW.r, SPRINT_SHADOW.g, SPRINT_SHADOW.b, SPRINT_SHADOW.a * alpha)
		var dust_base: Color = SPRINT_DUST_LIGHT if phase < 0.45 else SPRINT_DUST_DARK
		var dust_col: Color = Color(dust_base.r, dust_base.g, dust_base.b, dust_base.a * alpha)

		if phase < 0.55:
			draw_rect(Rect2(px - 1.0, py - 1.0, 3.0, 3.0), shadow_col, true)
			draw_rect(Rect2(px, py, 2.0, 2.0), dust_col, true)
		else:
			draw_rect(Rect2(px, py, 2.0, 2.0), shadow_col, true)
			draw_rect(Rect2(px, py, 1.0, 1.0), dust_col, true)


func _draw_knockback_strike() -> void:
	var max_dur: float = STRIKE_DURATION * (1.2 if _strike_is_heavy else 1.0)
	var progress: float = 1.0 - clampf(_strike_timer / maxf(0.01, max_dur), 0.0, 1.0)
	var alpha: float = 1.0 - progress
	var base_angle: float = _strike_dir.angle()
	var arc_span: float = (PI * 0.65) if _strike_is_heavy else (PI * 0.45)
	var radius: float = lerpf(5.5, 13.5 if _strike_is_heavy else 10.5, progress)

	if _arc_poly.size() != STRIKE_ARC_POINTS:
		_arc_poly.resize(STRIKE_ARC_POINTS)

	for i: int in range(STRIKE_ARC_POINTS):
		var t: float = float(i) / float(STRIKE_ARC_POINTS - 1) - 0.5
		var ang: float = base_angle + t * arc_span
		_arc_poly[i] = Vector2(cos(ang) * radius, 1.0 + sin(ang) * (radius * 0.75))

	var base_col: Color = STRIKE_HEAVY_COLOR if _strike_is_heavy else STRIKE_KB_COLOR
	var arc_col: Color = Color(base_col.r, base_col.g, base_col.b, base_col.a * alpha)
	var core_col: Color = Color(STRIKE_CORE_COLOR.r, STRIKE_CORE_COLOR.g, STRIKE_CORE_COLOR.b, STRIKE_CORE_COLOR.a * alpha)
	var shadow_col: Color = Color(STRIKE_SHADOW_COLOR.r, STRIKE_SHADOW_COLOR.g, STRIKE_SHADOW_COLOR.b, STRIKE_SHADOW_COLOR.a * alpha)

	draw_polyline(_arc_poly, shadow_col, 2.5 if _strike_is_heavy else 2.0, false)
	draw_polyline(_arc_poly, arc_col, 1.5 if _strike_is_heavy else 1.0, false)

	for idx: int in [0, 2, 4]:
		var spark_pos: Vector2 = _arc_poly[idx] + _strike_dir * (1.5 + progress * 2.5)
		var sx: float = roundf(spark_pos.x)
		var sy: float = roundf(spark_pos.y)
		draw_rect(Rect2(sx - 1.0, sy - 1.0, 3.0, 3.0), shadow_col, true)
		draw_rect(Rect2(sx, sy, 2.0 if _strike_is_heavy else 1.0, 2.0 if _strike_is_heavy else 1.0), core_col, true)


func _draw_level_up() -> void:
	var progress: float = 1.0 - clampf(_level_up_timer / LEVEL_UP_DURATION, 0.0, 1.0)
	var alpha: float = 1.0 - maxf(0.0, (progress - 0.55) / 0.45)
	var gold_col: Color = Color(LEVEL_UP_GOLD.r, LEVEL_UP_GOLD.g, LEVEL_UP_GOLD.b, LEVEL_UP_GOLD.a * alpha)
	var core_col: Color = Color(LEVEL_UP_CORE.r, LEVEL_UP_CORE.g, LEVEL_UP_CORE.b, LEVEL_UP_CORE.a * alpha)
	var shadow_col: Color = Color(LEVEL_UP_SHADOW.r, LEVEL_UP_SHADOW.g, LEVEL_UP_SHADOW.b, LEVEL_UP_SHADOW.a * alpha)

	var ring_rx: float = lerpf(4.0, 9.5, minf(1.0, progress * 1.4))
	var ring_ry: float = ring_rx * 0.42
	if _ring_poly.size() != LEVEL_UP_RING_POINTS + 1:
		_ring_poly.resize(LEVEL_UP_RING_POINTS + 1)
	for i: int in range(LEVEL_UP_RING_POINTS):
		var theta: float = (TAU * float(i)) / float(LEVEL_UP_RING_POINTS)
		_ring_poly[i] = Vector2(cos(theta) * ring_rx, feet_y + sin(theta) * ring_ry)
	_ring_poly[LEVEL_UP_RING_POINTS] = _ring_poly[0]
	draw_polyline(_ring_poly, gold_col, 1.0, false)

	for i: int in range(LEVEL_UP_SPARK_COUNT):
		var spark_t: float = clampf((progress * 1.35) - LEVEL_UP_PHASE_OFFSETS[i], 0.0, 1.0)
		if spark_t <= 0.0 or spark_t >= 1.0:
			continue
		var sx: float = roundf(LEVEL_UP_X_OFFSETS[i])
		var sy: float = roundf(lerpf(feet_y, head_y - 4.0, spark_t))

		draw_rect(Rect2(sx - 1.0, sy - 1.0, 3.0, 3.0), shadow_col, true)
		draw_rect(Rect2(sx - 1.0, sy, 3.0, 1.0), gold_col, true)
		draw_rect(Rect2(sx, sy - 1.0, 1.0, 3.0), gold_col, true)
		draw_rect(Rect2(sx, sy, 1.0, 1.0), core_col, true)


func _draw_death_soul() -> void:
	var progress: float = 1.0 - clampf(_death_timer / DEATH_DURATION, 0.0, 1.0)
	var alpha: float = 1.0 - maxf(0.0, (progress - 0.5) / 0.5)
	var shadow_col: Color = Color(DEATH_SHADOW.r, DEATH_SHADOW.g, DEATH_SHADOW.b, DEATH_SHADOW.a * alpha)

	if progress < 0.65:
		var burst_alpha: float = 1.0 - (progress / 0.65)
		var burst_col: Color = Color(DEATH_BURST_COLOR.r, DEATH_BURST_COLOR.g, DEATH_BURST_COLOR.b, DEATH_BURST_COLOR.a * burst_alpha)
		var burst_r: float = lerpf(2.0, 11.0, progress / 0.65)
		for i: int in range(DEATH_MOTE_COUNT):
			var ang: float = (TAU * float(i)) / float(DEATH_MOTE_COUNT)
			var mx: float = roundf(cos(ang) * burst_r)
			var my: float = roundf(sin(ang) * (burst_r * 0.6))
			draw_rect(Rect2(mx - 1.0, my - 1.0, 3.0, 3.0), shadow_col, true)
			draw_rect(Rect2(mx, my, 2.0, 2.0), burst_col, true)

	var soul_x: float = roundf(sin(progress * TAU * 1.5) * 1.5)
	var soul_y: float = roundf(lerpf(0.0, head_y - 8.0, progress))
	var outer_col: Color = Color(DEATH_SOUL_OUTER.r, DEATH_SOUL_OUTER.g, DEATH_SOUL_OUTER.b, DEATH_SOUL_OUTER.a * alpha)
	var core_col: Color = Color(DEATH_SOUL_CORE.r, DEATH_SOUL_CORE.g, DEATH_SOUL_CORE.b, DEATH_SOUL_CORE.a * alpha)

	draw_rect(Rect2(soul_x - 2.0, soul_y - 2.0, 5.0, 5.0), shadow_col, true)
	draw_rect(Rect2(soul_x - 1.0, soul_y - 2.0, 3.0, 5.0), outer_col, true)
	draw_rect(Rect2(soul_x - 2.0, soul_y - 1.0, 5.0, 3.0), outer_col, true)
	draw_rect(Rect2(soul_x - 1.0, soul_y - 1.0, 3.0, 3.0), core_col, true)

	var trail_y: float = soul_y + 4.0
	draw_rect(Rect2(soul_x, trail_y, 1.0, 2.0), outer_col, true)

