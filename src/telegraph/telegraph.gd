# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Telegraph
extends Node2D

signal telegraph_locked(telegraph: Telegraph)
signal telegraph_finished(telegraph: Telegraph)
signal telegraph_cancelled(telegraph: Telegraph)

@export var duration: float = 0.8
@export var lock_time: float = 0.25
@export var base_color: Color = Color(1.0, 1.0, 1.0, 0.35)
@export var locked_color: Color = Color(1.0, 1.0, 1.0, 0.85)

var elapsed: float = 0.0
var is_active: bool = false
var is_locked: bool = false


func _ready() -> void:
	z_index = -1


func _process(delta: float) -> void:
	if not is_active:
		return
	update_telegraph(delta)


func start(new_duration: float = -1.0, new_lock_time: float = -1.0) -> void:
	if new_duration > 0.0:
		duration = new_duration
	if new_lock_time >= 0.0:
		lock_time = new_lock_time
	elapsed = 0.0
	is_locked = false
	is_active = true
	visible = true
	queue_redraw()


func update_telegraph(delta: float) -> void:
	elapsed += delta
	if not is_locked and elapsed >= maxf(0.0, duration - lock_time):
		is_locked = true
		telegraph_locked.emit(self)

	queue_redraw()


func cancel() -> void:
	if not is_active:
		return
	is_active = false
	telegraph_cancelled.emit(self)
	queue_free()


func finish() -> void:
	if not is_active:
		return
	is_active = false
	telegraph_finished.emit(self)
	queue_free()


func get_progress() -> float:
	return clampf(elapsed / maxf(0.001, duration), 0.0, 1.0)
