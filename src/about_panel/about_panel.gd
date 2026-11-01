# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name AboutPanel
extends MenuPanel

const ABOUT_PATH: StringName = &"res://about_panel/about.txt"
const WEBSITE_URL: StringName = &"https://github.com/juan-medina/escapeteers"

@onready var _back_button: Button = $VBox/Buttons/Back
@onready var _about_text: BigTextPanel = $VBox/AboutText


func _ready() -> void:
	super._ready()
	await _about_text.load_file(ABOUT_PATH)


func first_focus_control() -> Control:
	return _back_button


func _on_website_pressed() -> void:
	OS.shell_open(WEBSITE_URL)


func _on_back_pressed() -> void:
	back_requested.emit()
