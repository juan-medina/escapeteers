# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name AnimatedTextureButton
extends TextureButton

const HOVER_SCALE: float = 1.15
const PRESS_SCALE: float = 0.9
const TWEEN_TIME: float = 0.08

var _hovered: bool = false


func _ready() -> void:
	# Scale from the arrow's centre, not its top-left corner.
	pivot_offset = size / 2.0


func _on_mouse_entered() -> void:
	_hovered = true
	_scale_to(HOVER_SCALE)


func _on_mouse_exited() -> void:
	_hovered = false
	_scale_to(1.0)


func _on_button_down() -> void:
	_scale_to(PRESS_SCALE)


func _on_button_up() -> void:
	# A click releases while still hovered; a drag-off releases outside.
	_scale_to(HOVER_SCALE if _hovered else 1.0)


func _scale_to(target: float) -> void:
	create_tween().tween_property(self, ^"scale", Vector2.ONE * target, TWEEN_TIME)