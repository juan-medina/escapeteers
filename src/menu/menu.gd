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


func _ready() -> void:
	super._ready()
	get_tree().create_timer(NOTIFICATION_DELAY).timeout.connect(InputManager.enable_notifications)
	var changelog_hash: StringName = StringName(FileAccess.get_sha256(str(ChangelogPanel.CHANGELOG_PATH)))
	if not Options.is_changelog_seen(changelog_hash):
		Options.changelog_seen_hash = changelog_hash
		_changelog_panel.is_boot = true
		_show_first(_changelog_panel)
	else:
		Audio.play_music(false)
		_show_first(_main_menu_panel)


func _on_play_requested() -> void:
	show_panel(_hero_select_panel)


func _on_hero_selected(hero: HeroData) -> void:
	await Transition.reload_game(hero.id)


func _on_settings_requested() -> void:
	show_panel(_settings_panel)


func _on_about_requested() -> void:
	show_panel(_about_panel)


func _on_changelog_requested() -> void:
	_changelog_panel.is_boot = false
	show_panel(_changelog_panel)


func _on_exit_requested() -> void:
	await Alerts.quit_game()


func _on_panel_back_requested() -> void:
	Audio.play_music(false)
	show_panel(_main_menu_panel)
