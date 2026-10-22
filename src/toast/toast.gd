# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name ToastScene
extends CanvasLayer

const APPEAR_TIME: float = 1.0
const VISIBLE_TIME: float = 3.0
const DISAPPEAR_TIME: float = 2.0
const DISAPPEAR_AFTER_HOVER: float = 1.0
const DELAY_BETWEEN_TOASTS: float = 1.0

var _tween: Tween = null
var _toast_queue: Array[StringName] = []
var _is_showing_message: bool = false

@onready var _message: Button = $Container/Message
@onready var _container: Control = $Container


func show_message(message: StringName) -> void:
	_toast_queue.append(message)
	if not _is_showing_message:
		_process_next_toast()


func _process_next_toast() -> void:
	if _toast_queue.is_empty():
		return
	_is_showing_message = true
	var message: StringName = _toast_queue.pop_front()
	_display_message(message)


func _display_message(message: StringName) -> void:
	_message.text = message
	_container.modulate.a = 0.0
	if _tween and _tween.is_valid():
		_tween.kill()
		_tween = null
	_tween = _container.create_tween()
	_tween.tween_property(_container, ^"modulate:a", 1.0, APPEAR_TIME)
	_tween.tween_interval(VISIBLE_TIME)
	_tween.tween_property(_container, ^"modulate:a", 0.0, DISAPPEAR_TIME)
	_tween.tween_callback(_hide)
	show()


func _on_message_button_down() -> void:
	if visible:
		Audio.play_click()
	_hide()


func _hide() -> void:
	hide()
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null

	if not _toast_queue.is_empty():
		get_tree().create_timer(DELAY_BETWEEN_TOASTS).timeout.connect(_process_next_toast)
	else:
		_is_showing_message = false


func _on_message_mouse_entered() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
	_container.modulate.a = 1.0


func _on_message_mouse_exited() -> void:
	if _container.modulate.a < 1.0:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = _container.create_tween()
	_tween.tween_interval(VISIBLE_TIME)
	_tween.tween_property(_container, ^"modulate:a", 0.0, DISAPPEAR_AFTER_HOVER)
	_tween.tween_callback(_hide)
