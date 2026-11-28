# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name PauseOverlay
extends PanelHost

var _codex_return_panel: UiPanel = null

@onready var _pause_panel: PausePanel = $Center/PausePanel
@onready var _settings_panel: SettingsPanel = $Center/SettingsPanel
@onready var _game_over_dialog: GameOverDialog = $Center/GameOverDialog
@onready var _codex_panel: CodexPanel = $Center/CodexPanel
@onready var _codex_heroes_panel: CodexHeroesPanel = $Center/CodexHeroesPanel
@onready var _codex_enemies_panel: CodexEnemiesPanel = $Center/CodexEnemiesPanel
@onready var _codex_items_panel: CodexItemsPanel = $Center/CodexItemsPanel
@onready var _codex_events_panel: CodexEventsPanel = $Center/CodexEventsPanel
@onready var _codex_mechanics_panel: CodexMechanicsPanel = $Center/CodexMechanicsPanel


func _unhandled_input(event: InputEvent) -> void:
	if visible or get_tree().paused or not event.is_action_pressed(&"pause"):
		return
	Audio.play_pause()
	_open_panel(_pause_panel)


func initialize() -> void:
	_codex_heroes_panel.initialize()
	_codex_enemies_panel.initialize()
	_codex_items_panel.initialize()
	_codex_events_panel.initialize()
	_codex_mechanics_panel.initialize()


func open_game_over() -> void:
	_open_panel(_game_over_dialog)


func _open_panel(panel: UiPanel) -> void:
	get_tree().paused = true
	set_host_alpha(0.0)
	_show_first(panel)
	visible = true
	fade_host(1.0)


func _close() -> void:
	get_viewport().gui_release_focus()
	fade_host(0.0).finished.connect(_on_close_finished)


func _open_codex(from_panel: UiPanel) -> void:
	_codex_return_panel = from_panel
	_codex_panel.reset_focus_target()
	show_panel(_codex_panel)


func _on_close_finished() -> void:
	hide_current()
	visible = false
	get_tree().paused = false


func _on_resume_requested() -> void:
	_close()


func _on_pause_panel_settings_requested() -> void:
	show_panel(_settings_panel)


func _on_settings_panel_back_requested() -> void:
	show_panel(_pause_panel)


func _on_pause_panel_codex_requested() -> void:
	_open_codex(_pause_panel)


func _on_game_over_codex_requested() -> void:
	_open_codex(_game_over_dialog)


func _on_codex_back_requested() -> void:
	show_panel(_codex_return_panel)


func _on_codex_heroes_requested() -> void:
	show_panel(_codex_heroes_panel)


func _on_codex_enemies_requested() -> void:
	show_panel(_codex_enemies_panel)


func _on_codex_items_requested() -> void:
	show_panel(_codex_items_panel)


func _on_codex_events_requested() -> void:
	show_panel(_codex_events_panel)


func _on_codex_mechanics_requested() -> void:
	show_panel(_codex_mechanics_panel)


func _on_codex_subpanel_back_requested() -> void:
	show_panel(_codex_panel)
