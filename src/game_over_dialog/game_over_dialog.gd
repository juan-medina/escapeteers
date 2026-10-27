# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name GameOverDialog
extends CanvasLayer

@onready var _retry: Button = $Center/Panel/VBox/Retry


func _ready() -> void:
	Audio.connect_menu_sounds(self)
	Audio.grab_focus_silent(_retry)


func _on_retry_pressed() -> void:
	_retry.disabled = true
	await Transition.reload_game()
