# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name PausePanel
extends MenuPanel

signal resume_requested
signal settings_requested

@onready var _resume_button: Button = $VBox/Resume


func first_focus_control() -> Control:
	return _resume_button


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_back_to_menu_pressed() -> void:
	await Transition.go_to_menu(Transition.MenuTarget.MAIN_MENU)


func _on_settings_pressed() -> void:
	settings_requested.emit()
