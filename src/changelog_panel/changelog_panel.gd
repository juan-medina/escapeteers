# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name ChangelogPanel
extends BigTextPanel


func is_seen() -> bool:
	return Options.is_changelog_seen(file_hash)


func mark_seen() -> void:
	Options.changelog_seen_hash = file_hash
