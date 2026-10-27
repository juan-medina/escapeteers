# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name HealthBar
extends Node2D

const DEFAULT_HERO_COLOR: Color = Color(0.25, 0.85, 0.35, 1.0)
const DEFAULT_ENEMY_COLOR: Color = Color(0.9, 0.25, 0.25, 1.0)
const DEFAULT_BACKGROUND_COLOR: Color = Color(0.1, 0.1, 0.1, 0.8)
const DEFAULT_CATCHUP_COLOR: Color = Color(1.0, 1.0, 1.0, 0.95)
const DEFAULT_WIDTH: float = 12.0
const BAR_HEIGHT: float = 1.0
const HOLD_DELAY: float = 0.22
const DRAIN_DURATION: float = 0.32
const HEAL_FLASH_DURATION: float = 0.15

@export var bar_width: float = DEFAULT_WIDTH
@export var fill_color: Color = DEFAULT_HERO_COLOR
@export var background_color: Color = DEFAULT_BACKGROUND_COLOR
@export var catchup_color: Color = DEFAULT_CATCHUP_COLOR
@export var hold_delay: float = HOLD_DELAY
@export var drain_duration: float = DRAIN_DURATION

var current_health: float = 100.0
var max_health: float = 100.0

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
