# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name EulaScreen
extends UiPanel

const EULA_PATH: StringName = &"res://eula_screen/eula.txt"
const NOTIFICATION_DELAY: float = 2.0

@onready var _eula_text: BigTextPanel = $Center/EulaPanel/VBox/EulaText


func _ready() -> void:
	var current_hash: StringName = _eula_hash()
	if Options.is_eula_accepted(current_hash):
		Transition.go_to_menu_instant()
		return

	get_tree().create_timer(NOTIFICATION_DELAY).timeout.connect(InputManager.enable_notifications)
	await _eula_text.load_file(EULA_PATH)
	super._ready()


func _eula_hash() -> StringName:
	return StringName(FileAccess.get_sha256(str(EULA_PATH)))


func _on_accept_pressed() -> void:
	Options.eula_accepted_hash = _eula_hash()
	await Transition.go_to_menu(Transition.MenuTarget.MAIN_MENU)


func _on_decline_pressed() -> void:
	await Alerts.quit_game()
