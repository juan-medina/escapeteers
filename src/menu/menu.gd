# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Menu
extends PanelHost

const NOTIFICATION_DELAY: float = 2.0

@onready var _main_menu_panel: MainMenuPanel = $Center/MainMenuPanel
@onready var _settings_panel: SettingsPanel = $Center/SettingsPanel
@onready var _about_panel: AboutPanel = $Center/AboutPanel


func _ready() -> void:
	super._ready()
	get_tree().create_timer(NOTIFICATION_DELAY).timeout.connect(InputManager.enable_notifications)
	_show_first(_main_menu_panel)


func _on_play_requested() -> void:
	await Transition.reload_game()


func _on_settings_requested() -> void:
	show_panel(_settings_panel)


func _on_about_requested() -> void:
	show_panel(_about_panel)


func _on_exit_requested() -> void:
	await Alerts.quit_game()


func _on_panel_back_requested() -> void:
	show_panel(_main_menu_panel)
