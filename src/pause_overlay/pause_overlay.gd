# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name PauseOverlay
extends PanelHost

@onready var _pause_panel: PausePanel = $Center/PausePanel
@onready var _settings_panel: SettingsPanel = $Center/SettingsPanel


func _unhandled_input(event: InputEvent) -> void:
	if visible or get_tree().paused or not event.is_action_pressed(&"pause"):
		return
	Audio.play_pause()
	_open()


func _open() -> void:
	get_tree().paused = true
	set_host_alpha(0.0)
	_show_first(_pause_panel)
	visible = true
	fade_host(1.0)


func _close() -> void:
	get_viewport().gui_release_focus()
	fade_host(0.0).finished.connect(_on_close_finished)


func _on_close_finished() -> void:
	if _current != null:
		_current.visible = false
		_current = null
	visible = false
	get_tree().paused = false


func _on_resume_requested() -> void:
	_close()


func _on_pause_panel_settings_requested() -> void:
	show_panel(_settings_panel)


func _on_settings_panel_back_requested() -> void:
	show_panel(_pause_panel)
