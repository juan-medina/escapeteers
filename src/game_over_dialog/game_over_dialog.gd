# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name GameOverDialog
extends CanvasLayer

@onready var _retry: Button = $Center/Panel/VBox/Buttons/Retry
@onready var _back_to_menu: Button = $Center/Panel/VBox/Buttons/BackToMenu


func _ready() -> void:
	Audio.connect_menu_sounds(self)
	Audio.grab_focus_silent(_retry)


func _on_retry_pressed() -> void:
	_retry.disabled = true
	_back_to_menu.disabled = true
	await Transition.reload_game()


func _on_back_to_menu_pressed() -> void:
	_retry.disabled = true
	_back_to_menu.disabled = true
	await Transition.go_to_menu(Transition.MenuTarget.MAIN_MENU)
