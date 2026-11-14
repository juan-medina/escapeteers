# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Menu
extends PanelHost

const NOTIFICATION_DELAY: float = 2.0

@onready var _main_menu_panel: MainMenuPanel = $Center/MainMenuPanel
@onready var _hero_select_panel: HeroSelectPanel = $Center/HeroSelectPanel
@onready var _settings_panel: SettingsPanel = $Center/SettingsPanel
@onready var _about_panel: AboutPanel = $Center/AboutPanel
@onready var _changelog_panel: ChangelogPanel = $Center/ChangelogPanel
@onready var _eula_screen: EulaScreen = $Center/EulaScreen


func _ready() -> void:
	get_tree().create_timer(NOTIFICATION_DELAY).timeout.connect(InputManager.enable_notifications)
	if not _eula_screen.is_accepted():
		_show_first(_eula_screen)
	else:
		_show_first(_get_start_panel())


func _get_start_panel() -> UiPanel:
	if not _changelog_panel.is_seen():
		_changelog_panel.mark_seen()
		_changelog_panel.back_button_text = &"Continue"
		return _changelog_panel
	return _main_menu_panel


func _on_eula_accepted() -> void:
	show_panel(_get_start_panel())


func _on_eula_back_requested() -> void:
	show_panel(_about_panel)


func _on_license_requested() -> void:
	show_panel(_eula_screen)


func _on_play_requested() -> void:
	show_panel(_hero_select_panel)


func _on_hero_selected(hero: HeroData) -> void:
	await Transition.reload_game(hero.id)


func _on_settings_requested() -> void:
	show_panel(_settings_panel)


func _on_about_requested() -> void:
	show_panel(_about_panel)


func _on_changelog_requested() -> void:
	_changelog_panel.back_button_text = &"Back"
	show_panel(_changelog_panel)


func _on_exit_requested() -> void:
	await Alerts.quit_game()


func _on_panel_back_requested() -> void:
	show_panel(_main_menu_panel)
