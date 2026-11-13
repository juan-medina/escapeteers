# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name UiPanel
extends Control

@export var first_focus: Control = null


func _ready() -> void:
	Audio.connect_menu_sounds(self)
	if is_visible_in_tree():
		grab_first_focus()


func grab_first_focus() -> void:
	if first_focus != null:
		Audio.grab_focus_silent(first_focus)

