# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name MenuPanel
extends UiPanel

signal back_requested


func _on_back_pressed() -> void:
	back_requested.emit()
