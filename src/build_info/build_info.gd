# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name BuildInfo
extends RefCounted

const INFO_PATH: StringName = &"res://build_info/build_info.json"
const DEV_BUILD: StringName = &"dev"

static var _display_string: String = ""


static func initialize() -> void:
	var version: String = str(ProjectSettings.get_setting(&"application/config/version", &"0.0.0"))

	var file: FileAccess = FileAccess.open(INFO_PATH, FileAccess.READ)
	if file == null:
		printerr(&"BuildInfo: Failed to open %s !" % INFO_PATH)
		await Alerts.fatal_error(&"Could not load game data")
		return

	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		printerr(&"BuildInfo: Failed to parse %s at line %d: %s !" % [INFO_PATH, json.get_error_line(), json.get_error_message()])
		await Alerts.fatal_error(&"Could not load game data")
		return

	var data: Dictionary = json.data
	var commit: String = str(data.get(&"commit", &""))
	var built_at: String = str(data.get(&"built_at", &""))

	# A build is identified by the commit it was made from, so the stamp is written
	# at build time by scripts/gen_build_info.py and is empty in a working tree.
	if commit.is_empty() or built_at.is_empty():
		_display_string = &"v%s (%s)" % [version, DEV_BUILD]
	else:
		_display_string = &"v%s+%s.%s" % [version, built_at, commit]


static func display_string() -> String:
	return _display_string
