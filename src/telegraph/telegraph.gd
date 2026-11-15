# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Telegraph
extends Node2D

signal telegraph_locked(telegraph: Telegraph)

const DEFAULT_DURATION: float = 0.8
const DEFAULT_LOCK_TIME: float = 0.25
const DEFAULT_BASE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.35)
const DEFAULT_LOCKED_COLOR: Color = Color(1.0, 1.0, 1.0, 0.85)

var duration: float = DEFAULT_DURATION
var lock_time: float = DEFAULT_LOCK_TIME
var base_color: Color = DEFAULT_BASE_COLOR
var locked_color: Color = DEFAULT_LOCKED_COLOR
var is_active: bool = false
var is_locked: bool = false

var _elapsed: float = 0.0
var _lock_delay: float = DEFAULT_DURATION - DEFAULT_LOCK_TIME


func _ready() -> void:
	z_index = -1
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	update_telegraph(delta)


func start(new_duration: float = -1.0, new_lock_time: float = -1.0) -> void:
	if new_duration > 0.0:
		duration = new_duration
	if new_lock_time >= 0.0:
		lock_time = new_lock_time
	_lock_delay = maxf(0.0, duration - lock_time)
	_elapsed = 0.0
	is_locked = false
	is_active = true
	visible = true
	set_process(true)
	queue_redraw()


func update_telegraph(delta: float) -> void:
	_elapsed += delta
	if not is_locked and _elapsed >= _lock_delay:
		is_locked = true
		set_process(false)
		telegraph_locked.emit(self)
		queue_redraw()


func cancel() -> void:
	if not is_active:
		return
	is_active = false
	is_locked = false
	visible = false
	set_process(false)


func finish() -> void:
	cancel()
