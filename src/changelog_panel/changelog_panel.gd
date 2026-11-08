# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name ChangelogPanel
extends MenuPanel

const CHANGELOG_PATH: StringName = &"res://changelog_panel/changelog.txt"

var is_boot: bool = false:
	set(value):
		is_boot = value
		if _back_button != null:
			_back_button.text = "Continue" if is_boot else "Back"

@onready var _back_button: Button = $VBox/Buttons/Back
@onready var _changelog_text: BigTextPanel = $VBox/ChangelogText


func _ready() -> void:
	super._ready()
	_back_button.text = "Continue" if is_boot else "Back"
	await _changelog_text.load_file(CHANGELOG_PATH)


func first_focus_control() -> Control:
	return _back_button


func _on_back_pressed() -> void:
	back_requested.emit()
