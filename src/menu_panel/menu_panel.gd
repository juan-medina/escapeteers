# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name MenuPanel
extends UiPanel

signal back_requested

@export var back_button: Button = null

var back_button_text: StringName = &"Back":
	set(value):
		back_button_text = value
		back_button.text = back_button_text


func _on_back_pressed() -> void:
	back_requested.emit()
