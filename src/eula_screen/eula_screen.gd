# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name EulaScreen
extends BigTextPanel

signal accepted

@onready var _decline_button: Button = $VBox/Buttons/Decline
@onready var _accept_button: Button = $VBox/Buttons/Accept


func _ready() -> void:
	await super._ready()
	_update_buttons()


func is_accepted() -> bool:
	return Options.is_eula_accepted(file_hash)


func _update_buttons() -> void:
	var accepted_state: bool = is_accepted()
	back_button.visible = accepted_state
	_decline_button.visible = not accepted_state
	_accept_button.visible = not accepted_state
	first_focus = back_button if accepted_state else _accept_button
	if is_visible_in_tree():
		grab_first_focus()


func _on_accept_pressed() -> void:
	Options.eula_accepted_hash = file_hash
	_update_buttons()
	accepted.emit()


func _on_decline_pressed() -> void:
	await Alerts.quit_game()
