# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name EulaScreen
extends CanvasLayer

const EULA_PATH: StringName = &"res://eula_screen/eula.txt"
const NOTIFICATION_DELAY: float = 2.0

@onready var _eula_text: BigTextPanel = $Center/EulaPanel/VBox/EulaText
@onready var _accept_button: Button = $Center/EulaPanel/VBox/Buttons/Accept


func _ready() -> void:
	Audio.connect_menu_sounds(self)
	Audio.play_menu_music()
	if Options.is_eula_accepted(_eula_version()):
		Transition.go_to_menu_instant()
		return

	get_tree().create_timer(NOTIFICATION_DELAY).timeout.connect(InputManager.enable_notifications)
	await _eula_text.load_file(EULA_PATH)
	Audio.grab_focus_silent(_accept_button)


# Acceptance is keyed to the major.minor version so a patch release does not
# force the player to agree again, but a minor bump (a changed EULA) does.
func _eula_version() -> StringName:
	var parts: PackedStringArray = BuildInfo.version.split(&".")
	if parts.size() >= 2:
		return StringName(&"%s.%s" % [parts[0], parts[1]])
	return BuildInfo.version


func _on_accept_pressed() -> void:
	Options.eula_accepted_version = _eula_version()
	await Transition.go_to_menu(Transition.MenuTarget.MAIN_MENU)


func _on_decline_pressed() -> void:
	await Alerts.quit_game()
