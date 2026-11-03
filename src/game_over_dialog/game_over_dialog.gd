# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name GameOverDialog
extends CanvasLayer

@onready var _retry: Button = $Center/Panel/VBox/Buttons/Retry
@onready var _back_to_menu: Button = $Center/Panel/VBox/Buttons/BackToMenu


func _ready() -> void:
	var audio_mgr: Node = get_node_or_null(^"/root/Audio")
	if audio_mgr != null:
		audio_mgr.call(&"connect_menu_sounds", self)
		audio_mgr.call(&"grab_focus_silent", _retry)


func _on_retry_pressed() -> void:
	_retry.disabled = true
	_back_to_menu.disabled = true
	var transition_mgr: Node = get_node_or_null(^"/root/Transition")
	if transition_mgr != null:
		await transition_mgr.call(&"reload_game")


func _on_back_to_menu_pressed() -> void:
	_retry.disabled = true
	_back_to_menu.disabled = true
	var transition_mgr: Node = get_node_or_null(^"/root/Transition")
	if transition_mgr != null:
		await transition_mgr.call(&"go_to_menu", 0)
