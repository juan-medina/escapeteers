# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name StatusVfx
extends Node2D

const STUN_ORBIT_SPEED: float = 5.5
const STUN_RADIUS_X: float = 6.0
const STUN_RADIUS_Y: float = 2.0
const STUN_STAR_COUNT: int = 3
const STUN_COLOR_CORE: Color = Color(1.0, 0.98, 0.65, 1.0)
const STUN_COLOR_OUTER: Color = Color(1.0, 0.82, 0.15, 1.0)
const STUN_COLOR_SHADOW: Color = Color(0.22, 0.14, 0.0, 0.85)

const BURN_EMBER_COUNT: int = 5
const BURN_CYCLE_SPEED: float = 1.85
const BURN_PULSE_DECAY: float = 6.0
const BURN_COLOR_LOW: Color = Color(1.0, 0.92, 0.32, 0.95)
const BURN_COLOR_MID: Color = Color(1.0, 0.52, 0.10, 0.95)
const BURN_COLOR_HIGH: Color = Color(0.95, 0.24, 0.08, 0.85)
const BURN_COLOR_SHADOW: Color = Color(0.20, 0.04, 0.0, 0.70)
const BURN_X_OFFSETS: Array[float] = [-4.0, -2.0, 0.0, 2.0, 4.0]
const BURN_PHASE_OFFSETS: Array[float] = [0.0, 0.42, 0.18, 0.64, 0.83]

const SLOW_RING_POINTS: int = 16
const SLOW_RADIUS_X: float = 6.5
const SLOW_RADIUS_Y: float = 2.5
const SLOW_SHARD_COUNT: int = 3
const SLOW_RING_COLOR: Color = Color(0.35, 0.82, 1.0, 0.75)
const SLOW_SHARD_COLOR: Color = Color(0.85, 0.97, 1.0, 0.95)
const SLOW_SHADOW_COLOR: Color = Color(0.05, 0.20, 0.38, 0.75)

const KB_DURATION: float = 0.22
const KB_MIN_FORCE_SQ: float = 2500.0
const KB_LINE_COLOR: Color = Color(1.0, 0.96, 0.82, 0.92)
const KB_DUST_COLOR: Color = Color(0.88, 0.82, 0.70, 0.85)
const KB_SHADOW_COLOR: Color = Color(0.15, 0.12, 0.08, 0.70)
const KB_SIDE_OFFSETS: Array[float] = [-3.5, 0.0, 3.5]

var head_y: float = -8.0
var feet_y: float = 6.0

var _is_stunned: bool = false
var _is_burning: bool = false
var _is_slowed: bool = false
var _time: float = 0.0
var _burn_pulse: float = 0.0
var _kb_timer: float = 0.0
var _kb_duration: float = KB_DURATION
var _kb_dir: Vector2 = Vector2.RIGHT
var _kb_is_heavy: bool = false
var _slow_ring_poly: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	z_index = 1
	visible = false
	set_process(false)
	_rebuild_slow_ring()


func set_statuses(stunned: bool, burning: bool, slowed: bool) -> void:
	var changed: bool = (_is_stunned != stunned) or (_is_burning != burning) or (_is_slowed != slowed)
	_is_stunned = stunned
	_is_burning = burning
	_is_slowed = slowed
	_update_active_state(changed)


func trigger_burn_pulse() -> void:
	if not _is_burning:
		return
	_burn_pulse = 1.0
	queue_redraw()


func trigger_knockback(force: Vector2) -> void:
	var force_sq: float = force.length_squared()
	if force_sq < KB_MIN_FORCE_SQ:
		return
	_kb_dir = force.normalized()
	_kb_is_heavy = force_sq >= 32000.0
	_kb_duration = KB_DURATION * (1.25 if _kb_is_heavy else 1.0)
	_kb_timer = _kb_duration
	_update_active_state(true)


func clear() -> void:
	_is_stunned = false
	_is_burning = false
	_is_slowed = false
	_burn_pulse = 0.0
	_kb_timer = 0.0
	visible = false
	set_process(false)
	queue_redraw()


func _update_active_state(force_redraw: bool) -> void:
	var any_active: bool = _is_stunned or _is_burning or _is_slowed or (_kb_timer > 0.0)
	visible = any_active
	set_process(any_active)
	if not _is_burning:
		_burn_pulse = 0.0
	if force_redraw:
		queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _burn_pulse > 0.0:
		_burn_pulse = maxf(0.0, _burn_pulse - delta * BURN_PULSE_DECAY)
	if _kb_timer > 0.0:
		_kb_timer = maxf(0.0, _kb_timer - delta)
		if _kb_timer <= 0.0:
			_update_active_state(true)
			return
	queue_redraw()


func _draw() -> void:
	if _kb_timer > 0.0:
		_draw_knockback_impact()
	if _is_slowed:
		_draw_slow_frost()
	if _is_burning:
		_draw_burn_embers()
	if _is_stunned:
		_draw_stun_stars()


func _draw_knockback_impact() -> void:
	var progress: float = 1.0 - clampf(_kb_timer / maxf(0.01, _kb_duration), 0.0, 1.0)
	var alpha: float = 1.0 - progress
	var perp: Vector2 = Vector2(-_kb_dir.y, _kb_dir.x)
	var line_len: float = (8.0 if _kb_is_heavy else 5.5) * (1.0 - progress * 0.4)
	var line_col: Color = Color(KB_LINE_COLOR.r, KB_LINE_COLOR.g, KB_LINE_COLOR.b, KB_LINE_COLOR.a * alpha)
	var shadow_col: Color = Color(KB_SHADOW_COLOR.r, KB_SHADOW_COLOR.g, KB_SHADOW_COLOR.b, KB_SHADOW_COLOR.a * alpha)

	for i: int in range(KB_SIDE_OFFSETS.size()):
		var side: float = KB_SIDE_OFFSETS[i]
		var start_offset: float = 2.0 + progress * 4.0 + (1.5 if i == 1 else 0.0)
		var p_start: Vector2 = (-_kb_dir * start_offset) + (perp * side)
		var p_end: Vector2 = p_start - (_kb_dir * line_len)
		draw_line(p_start + Vector2(0.0, 1.0), p_end + Vector2(0.0, 1.0), shadow_col, 1.5)
		draw_line(p_start, p_end, line_col, 1.5 if (_kb_is_heavy and i == 1) else 1.0)

	var dust_col: Color = Color(KB_DUST_COLOR.r, KB_DUST_COLOR.g, KB_DUST_COLOR.b, KB_DUST_COLOR.a * alpha)
	for side_sign: float in [-1.0, 1.0]:
		var dust_pos: Vector2 = Vector2(0.0, feet_y) - (_kb_dir * (3.0 + progress * 5.0)) + (perp * side_sign * (2.5 + progress * 2.0))
		var dx: float = roundf(dust_pos.x)
		var dy: float = roundf(dust_pos.y)
		draw_rect(Rect2(dx - 1.0, dy - 1.0, 3.0, 3.0), shadow_col, true)
		draw_rect(Rect2(dx, dy, 2.0, 2.0), dust_col, true)


func _rebuild_slow_ring() -> void:
	_slow_ring_poly.resize(SLOW_RING_POINTS + 1)
	for i: int in range(SLOW_RING_POINTS):
		var theta: float = (TAU * float(i)) / float(SLOW_RING_POINTS)
		_slow_ring_poly[i] = Vector2(cos(theta) * SLOW_RADIUS_X, feet_y + sin(theta) * SLOW_RADIUS_Y)
	_slow_ring_poly[SLOW_RING_POINTS] = _slow_ring_poly[0]


func _draw_slow_frost() -> void:
	if _slow_ring_poly.is_empty():
		_rebuild_slow_ring()
	draw_polyline(_slow_ring_poly, SLOW_RING_COLOR, 1.0, false)

	for i: int in range(SLOW_SHARD_COUNT):
		var angle: float = _time * 1.6 + (TAU * float(i)) / float(SLOW_SHARD_COUNT)
		var px: float = roundf(cos(angle) * (SLOW_RADIUS_X - 1.0))
		var py: float = roundf(feet_y + sin(angle) * SLOW_RADIUS_Y)
		draw_rect(Rect2(px - 1.0, py - 1.0, 2.0, 2.0), SLOW_SHADOW_COLOR, true)
		draw_rect(Rect2(px, py - 1.0, 1.0, 2.0), SLOW_SHARD_COLOR, true)


func _draw_burn_embers() -> void:
	var pulse_lift: float = _burn_pulse * 2.5
	for i: int in range(BURN_EMBER_COUNT):
		var phase: float = fmod(_time * BURN_CYCLE_SPEED + BURN_PHASE_OFFSETS[i], 1.0)
		var base_x: float = BURN_X_OFFSETS[i]
		var sway_x: float = sin((_time * 6.0) + float(i) * 1.7) * 1.2
		var px: float = roundf(base_x + sway_x)
		var py: float = roundf(lerpf(feet_y - 2.0, head_y + 2.0 - pulse_lift, phase))

		var ember_color: Color = BURN_COLOR_LOW
		if phase >= 0.68:
			ember_color = BURN_COLOR_HIGH
		elif phase >= 0.35:
			ember_color = BURN_COLOR_MID

		if phase < 0.65 or _burn_pulse > 0.25:
			draw_rect(Rect2(px - 1.0, py - 1.0, 3.0, 3.0), BURN_COLOR_SHADOW, true)
			draw_rect(Rect2(px, py - 1.0, 2.0, 2.0), ember_color, true)
			if phase < 0.35:
				draw_rect(Rect2(px, py, 1.0, 1.0), STUN_COLOR_CORE, true)
		else:
			draw_rect(Rect2(px, py, 2.0, 2.0), BURN_COLOR_SHADOW, true)
			draw_rect(Rect2(px, py, 1.0, 1.0), ember_color, true)


func _draw_stun_stars() -> void:
	for i: int in range(STUN_STAR_COUNT):
		var angle: float = _time * STUN_ORBIT_SPEED + (TAU * float(i)) / float(STUN_STAR_COUNT)
		var sx: float = roundf(cos(angle) * STUN_RADIUS_X)
		var sy: float = roundf(head_y + sin(angle) * STUN_RADIUS_Y)

		draw_rect(Rect2(sx - 1.0, sy - 1.0, 3.0, 3.0), STUN_COLOR_SHADOW, true)
		if i == 0:
			draw_rect(Rect2(sx - 1.0, sy, 3.0, 1.0), STUN_COLOR_OUTER, true)
			draw_rect(Rect2(sx, sy - 1.0, 1.0, 3.0), STUN_COLOR_OUTER, true)
			draw_rect(Rect2(sx, sy, 1.0, 1.0), STUN_COLOR_CORE, true)
		else:
			draw_rect(Rect2(sx, sy, 2.0, 2.0), STUN_COLOR_OUTER, true)
			draw_rect(Rect2(sx, sy, 1.0, 1.0), STUN_COLOR_CORE, true)
