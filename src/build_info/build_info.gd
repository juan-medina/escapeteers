# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name BuildInfo
extends RefCounted

const INFO_PATH: StringName = &"res://build_info/build_info.json"
const DEV_BUILD: StringName = &"dev"

static var name: StringName = &""
static var version: StringName = &""
static var version_simple: StringName = &""
static var commit: StringName = &""
static var built_at: StringName = &""


static func initialize() -> void:
	name = str(ProjectSettings.get_setting(&"application/config/name", &"unknown"))
	version = str(ProjectSettings.get_setting(&"application/config/version", &"0.0.0"))
	var parts: PackedStringArray = version.split(&".")
	if parts.size() >= 2:
		version_simple = StringName(&"%s.%s" % [parts[0], parts[1]])
	else:
		version_simple = version

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
	commit = _read_string(data, &"commit")
	built_at = _read_string(data, &"built_at")


# A build is identified by the commit it was made from, so the stamp is written
# at build time by scripts/gen_build_info.py and is empty in a working tree.
static func display_string() -> String:
	if commit.is_empty() or built_at.is_empty():
		return &"v%s (%s)" % [version, DEV_BUILD]
	return &"v%s+%s.%s" % [version, built_at, commit]


static func _read_string(data: Dictionary, key: StringName) -> StringName:
	var value: Variant = data.get(key, &"")
	if value is StringName:
		@warning_ignore("unsafe_cast")
		return value as StringName
	if value is String:
		@warning_ignore("unsafe_cast")
		return StringName(value as String)
	return &""
