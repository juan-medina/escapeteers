# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name HealthBar
extends Node2D

const DEFAULT_HERO_COLOR: Color = Color(0.25, 0.85, 0.35, 1.0)
const DEFAULT_ENEMY_COLOR: Color = Color(0.9, 0.25, 0.25, 1.0)
const DEFAULT_BACKGROUND_COLOR: Color = Color(0.1, 0.1, 0.1, 0.8)
const DEFAULT_CATCHUP_COLOR: Color = Color(1.0, 1.0, 1.0, 0.95)
const LEVEL_COLOR: Color = Color(1.0, 0.85, 0.40, 1.0)
const LEVEL_SHADOW: Color = Color(0.05, 0.05, 0.05, 0.9)
const DEFAULT_WIDTH: float = 12.0
const BAR_HEIGHT: float = 1.0
const HOLD_DELAY: float = 0.22
const DRAIN_DURATION: float = 0.32
const HEAL_FLASH_DURATION: float = 0.15

@export var bar_width: float = DEFAULT_WIDTH
@export var fill_color: Color = DEFAULT_HERO_COLOR
@export var level_color: Color = LEVEL_COLOR
@export var background_color: Color = DEFAULT_BACKGROUND_COLOR
@export var catchup_color: Color = DEFAULT_CATCHUP_COLOR
@export var hold_delay: float = HOLD_DELAY
@export var drain_duration: float = DRAIN_DURATION

var current_health: float = 100.0
var max_health: float = 100.0
var level: int = 0:
	set(value):
		level = value
		queue_redraw()

var _lag_health: float = 100.0
var _hold_timer: float = 0.0
var _heal_flash_timer: float = 0.0
var _heal_previous_health: float = 100.0
var _is_initialized: bool = false


func _ready() -> void:
	z_index = 1
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	var needs_redraw: bool = false

	if _heal_flash_timer > 0.0:
		_heal_flash_timer -= delta
		needs_redraw = true

	if _hold_timer > 0.0:
		_hold_timer -= delta
	elif _lag_health > current_health:
		var drain_speed: float = max_health / maxf(0.05, drain_duration)
		_lag_health = maxf(current_health, _lag_health - drain_speed * delta)
		needs_redraw = true

	if _lag_health <= current_health and _heal_flash_timer <= 0.0:
		_lag_health = current_health
		if current_health <= 0.0:
			visible = false
		set_process(false)
		needs_redraw = true

	if needs_redraw:
		queue_redraw()


func _draw() -> void:
	if _lag_health <= 0.0 and current_health <= 0.0:
		return

	var half_width: float = bar_width * 0.5
	var bg_rect: Rect2 = Rect2(-half_width, 0.0, bar_width, BAR_HEIGHT)
	draw_rect(bg_rect, background_color, true)

	var curr_ratio: float = clampf(current_health / max_health, 0.0, 1.0)
	var curr_pixels: float = floorf(bar_width * curr_ratio)
	if curr_ratio > 0.0 and curr_pixels < 1.0:
		curr_pixels = 1.0

	var lag_ratio: float = clampf(_lag_health / max_health, 0.0, 1.0)
	var lag_pixels: float = floorf(bar_width * lag_ratio)
	if lag_ratio > 0.0 and lag_pixels < 1.0:
		lag_pixels = 1.0

	# Draw white damage catch-up bar (if lag > current)
	if lag_pixels > curr_pixels:
		var lag_rect: Rect2 = Rect2(-half_width, 0.0, lag_pixels, BAR_HEIGHT)
		draw_rect(lag_rect, catchup_color, true)

	# Draw current health in team color
	if curr_pixels > 0.0:
		var fill_rect: Rect2 = Rect2(-half_width, 0.0, curr_pixels, BAR_HEIGHT)
		draw_rect(fill_rect, fill_color, true)

	# Draw heal flash chunk (if heal flash is active)
	if _heal_flash_timer > 0.0 and curr_pixels > 0.0:
		var prev_ratio: float = clampf(_heal_previous_health / max_health, 0.0, 1.0)
		var prev_pixels: float = floorf(bar_width * prev_ratio)
		if curr_pixels > prev_pixels:
			var flash_start_x: float = -half_width + prev_pixels
			var flash_w: float = curr_pixels - prev_pixels
			var flash_rect: Rect2 = Rect2(flash_start_x, 0.0, flash_w, BAR_HEIGHT)
			draw_rect(flash_rect, catchup_color, true)

	if level > 0:
		_draw_roman_level(half_width)


func _draw_roman_level(half_width: float) -> void:
	var roman_str: String = _get_roman_string(level)
	if roman_str.is_empty():
		return

	var total_width: float = 0.0
	for i: int in range(roman_str.length()):
		var ch: String = roman_str[i]
		if ch == "I":
			total_width += 1.0
		elif ch == "V" or ch == "X":
			total_width += 3.0
		if i < roman_str.length() - 1:
			total_width += 1.0

	var cursor_x: float = -half_width - 2.0 - total_width
	var base_y: float = -2.0

	var pixels: Array[Vector2] = []
	for i: int in range(roman_str.length()):
		var ch: String = roman_str[i]
		if ch == "I":
			for y_off: int in range(4):
				pixels.append(Vector2(cursor_x, base_y + float(y_off)))
			cursor_x += 2.0
		elif ch == "V":
			pixels.append(Vector2(cursor_x + 0.0, base_y + 0.0))
			pixels.append(Vector2(cursor_x + 0.0, base_y + 1.0))
			pixels.append(Vector2(cursor_x + 0.0, base_y + 2.0))
			pixels.append(Vector2(cursor_x + 1.0, base_y + 3.0))
			pixels.append(Vector2(cursor_x + 2.0, base_y + 2.0))
			pixels.append(Vector2(cursor_x + 2.0, base_y + 1.0))
			pixels.append(Vector2(cursor_x + 2.0, base_y + 0.0))
			cursor_x += 4.0
		elif ch == "X":
			pixels.append(Vector2(cursor_x + 0.0, base_y + 0.0))
			pixels.append(Vector2(cursor_x + 2.0, base_y + 0.0))
			pixels.append(Vector2(cursor_x + 1.0, base_y + 1.0))
			pixels.append(Vector2(cursor_x + 1.0, base_y + 2.0))
			pixels.append(Vector2(cursor_x + 0.0, base_y + 3.0))
			pixels.append(Vector2(cursor_x + 2.0, base_y + 3.0))
			cursor_x += 4.0

	for p: Vector2 in pixels:
		draw_rect(Rect2(p.x + 1.0, p.y + 1.0, 1.0, 1.0), LEVEL_SHADOW, true)

	for p: Vector2 in pixels:
		draw_rect(Rect2(p.x, p.y, 1.0, 1.0), level_color, true)


static func _get_roman_string(val: int) -> String:
	match val:
		1:
			return "I"
		2:
			return "II"
		3:
			return "III"
		4:
			return "IV"
		5:
			return "V"
		6:
			return "VI"
		7:
			return "VII"
		8:
			return "VIII"
		9:
			return "IX"
		10:
			return "X"
		_:
			if val > 10 and val <= 20:
				return "X" + _get_roman_string(val - 10)
			return "I"


func set_level(new_level: int) -> void:
	level = new_level


func set_level_color(new_color: Color) -> void:
	level_color = new_color
	queue_redraw()


func update_health(new_health: float, new_max_health: float) -> void:
	max_health = maxf(1.0, new_max_health)
	var prev_health: float = current_health
	current_health = clampf(new_health, 0.0, max_health)

	if not _is_initialized:
		_is_initialized = true
		_lag_health = current_health
		visible = current_health > 0.0
		queue_redraw()
		return

	if current_health < prev_health:
		# Taking damage: hold catchup bar, then drain down
		_heal_flash_timer = 0.0
		_hold_timer = hold_delay
		visible = true
		set_process(true)
		queue_redraw()
	elif current_health > prev_health:
		# Healing: flash gained portion, snap lag health up
		_heal_previous_health = prev_health
		_heal_flash_timer = HEAL_FLASH_DURATION
		_lag_health = current_health
		_hold_timer = 0.0
		visible = true
		set_process(true)
		queue_redraw()


func set_fill_color(new_color: Color) -> void:
	fill_color = new_color
	queue_redraw()
