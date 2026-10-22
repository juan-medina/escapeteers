# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name BadWordFilter
extends RefCounted

const BAD_WORDS_PATH: StringName = &"res://filtered_line_edit/bad_words.txt"

const LEETSPEAK_MAP: Dictionary = {"@": "a", "4": "a", "8": "b", "3": "e", "1": "i", "!": "i", "0": "o", "$": "s", "5": "s", "7": "t"}

static var _regex: RegEx
static var _repeating_regex: RegEx
static var _non_alpha_regex: RegEx


static func initialize() -> void:
	if _regex != null:
		return

	_repeating_regex = RegEx.new()
	_repeating_regex.compile("(.)\\1+")
	_non_alpha_regex = RegEx.new()
	_non_alpha_regex.compile("[^a-z]")

	if not FileAccess.file_exists(BAD_WORDS_PATH):
		printerr(&"Bad words file not found at: ", BAD_WORDS_PATH)
		await Alerts.fatal_error(&"Could not load game data")
		return

	var file: FileAccess = FileAccess.open(BAD_WORDS_PATH, FileAccess.READ)
	if file:
		var content: String = file.get_as_text()
		var words: PackedStringArray = content.split("\n", false)
		var valid_words: PackedStringArray = []
		for word: String in words:
			if not word.is_empty():
				valid_words.append(word)

		if not valid_words.is_empty():
			var pattern: String = "\\b(" + "|".join(valid_words) + ")\\b"
			_regex = RegEx.new()
			var err: int = _regex.compile(pattern)
			if err != OK:
				printerr(&"Failed to compile bad words regex pattern!")
				await Alerts.fatal_error(&"Could not load game data")
				return
		else:
			printerr(&"Bad-words list is empty!")
			await Alerts.fatal_error(&"Could not load game data")
			return
	else:
		printerr(&"Failed to open bad words file at: ", BAD_WORDS_PATH)
		await Alerts.fatal_error(&"Could not load game data")


static func _normalize_text(text: String, use_leetspeak: bool) -> String:
	var result: String = text

	if use_leetspeak:
		for key: String in LEETSPEAK_MAP:
			result = result.replace(key, str(LEETSPEAK_MAP[key]))

	result = _non_alpha_regex.sub(result, "", true)
	result = _repeating_regex.sub(result, "$1", true)

	return result


static func is_bad(text: String) -> bool:
	if _regex == null:
		return false

	var lower_text: String = text.to_lower()
	if _regex.search(lower_text) != null:
		return true

	var leet_text: String = _normalize_text(lower_text, true)
	if not leet_text.is_empty() and _regex.search(leet_text) != null:
		return true

	var strip_text: String = _normalize_text(lower_text, false)
	if not strip_text.is_empty() and _regex.search(strip_text) != null:
		return true

	return false
