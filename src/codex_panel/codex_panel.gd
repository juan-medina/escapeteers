# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name CodexPanel
extends MenuPanel

signal heroes_requested
signal enemies_requested
signal mechanics_requested

@onready var _heroes_button: Button = $VBox/ButtonsVBox/Heroes
@onready var _heroes_badge: Control = $VBox/ButtonsVBox/Heroes/UnreadBadge
@onready var _enemies_button: Button = $VBox/ButtonsVBox/Enemies
@onready var _enemies_badge: Control = $VBox/ButtonsVBox/Enemies/UnreadBadge
@onready var _mechanics_button: Button = $VBox/ButtonsVBox/Mechanics


func _ready() -> void:
	super._ready()
	Codex.unread_changed.connect(_sync_badges)
	_sync_badges()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready() and is_visible_in_tree():
		_sync_badges()


func reset_focus_target() -> void:
	first_focus = _heroes_button


func _sync_badges() -> void:
	_heroes_badge.visible = Codex.has_unread_heroes()
	_enemies_badge.visible = Codex.has_unread_enemies()


func _on_heroes_pressed() -> void:
	first_focus = _heroes_button
	heroes_requested.emit()


func _on_enemies_pressed() -> void:
	first_focus = _enemies_button
	enemies_requested.emit()


func _on_mechanics_pressed() -> void:
	first_focus = _mechanics_button
	mechanics_requested.emit()
