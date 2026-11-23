# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name PausePanel
extends UiPanel

signal resume_requested
signal codex_requested
signal settings_requested

@onready var _codex_badge: Control = $VBox/Codex/UnreadBadge


func _ready() -> void:
	super._ready()
	Codex.unread_changed.connect(_sync_codex_badge)
	_sync_codex_badge()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready() and is_visible_in_tree():
		_sync_codex_badge()


func _sync_codex_badge() -> void:
	_codex_badge.visible = Codex.has_any_unread()


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_codex_pressed() -> void:
	codex_requested.emit()


func _on_back_to_menu_pressed() -> void:
	await Transition.go_to_menu()


func _on_settings_pressed() -> void:
	settings_requested.emit()
