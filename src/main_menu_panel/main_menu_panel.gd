# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name MainMenuPanel
extends UiPanel

signal play_requested
signal settings_requested
signal about_requested
signal changelog_requested
signal exit_requested

@onready var _exit_separator: HSeparator = $VBox/MenuBox/ButtonsVBox/HSeparator
@onready var _exit_button: Button = $VBox/MenuBox/ButtonsVBox/Exit


func _ready() -> void:
	super._ready()
	if OS.has_feature(&"web"):
		_exit_separator.visible = false
		_exit_button.visible = false


func _on_play_pressed() -> void:
	play_requested.emit()


func _on_settings_pressed() -> void:
	settings_requested.emit()


func _on_about_pressed() -> void:
	about_requested.emit()


func _on_changelog_pressed() -> void:
	changelog_requested.emit()


func _on_exit_pressed() -> void:
	exit_requested.emit()
