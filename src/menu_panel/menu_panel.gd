# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name MenuPanel
extends PanelContainer

signal back_requested

@export var first_focus: Control = null


func _ready() -> void:
	Audio.connect_menu_sounds(self)


func grab_first_focus() -> void:
	Audio.grab_focus_silent(first_focus)


func _on_back_pressed() -> void:
	back_requested.emit()
