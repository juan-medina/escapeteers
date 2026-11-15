# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name UiPanel
extends Control

@export var first_focus: Control = null


func _ready() -> void:
	Audio.connect_menu_sounds(self)
	if is_visible_in_tree():
		grab_first_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"back"):
		get_viewport().set_input_as_handled()
		_ensure_focus()


func grab_first_focus() -> void:
	if first_focus != null:
		Audio.grab_focus_silent(first_focus)


func _ensure_focus() -> void:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner != null and is_ancestor_of(focus_owner):
		return
	grab_first_focus()
