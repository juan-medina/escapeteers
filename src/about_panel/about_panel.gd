# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name AboutPanel
extends BigTextPanel

signal license_requested


func _on_license_pressed() -> void:
	license_requested.emit()


func _on_website_pressed() -> void:
	OS.shell_open(WEBSITE_URL)
