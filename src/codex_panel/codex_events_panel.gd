# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name CodexEventsPanel
extends CodexUnitsPanel

const EVENTS_JSON_PATH: StringName = &"res://codex_panel/events.json"
const EVENT_ICONS_FRAMES: SpriteFrames = preload("res://codex_panel/event_icons.tres")

static var _events: Dictionary[StringName, Dictionary] = {}


static func initialize_data() -> void:
	if not _events.is_empty():
		return

	var root: Dictionary = await CharacterData.load_json_file(EVENTS_JSON_PATH)
	if root.is_empty():
		return

	for key_var: Variant in root:
		var event_var: Variant = root[key_var]
		if event_var is Dictionary:
			var event_dict: Dictionary = event_var
			_events[StringName(str(key_var))] = event_dict


func _setup_card(card: CodexEntryCard) -> void:
	var event_data: Dictionary = _events.get(card.entry_id, {})
	var event_name: String = CharacterData._str_val(event_data, &"name")
	var event_color: Color = Color.from_string(CharacterData._str_val(event_data, &"color"), Color.WHITE)
	var anim_name: StringName = StringName(CharacterData._str_val(event_data, &"anim_name"))
	var icon_scale: float = CharacterData._float_val(event_data, &"icon_scale", 1.0)
	card.setup_event(event_name, event_color, EVENT_ICONS_FRAMES, anim_name, icon_scale)


func _is_entry_discovered(entry_id: StringName) -> bool:
	return Codex.is_discovered(Codex.Category.EVENTS, entry_id)


func _is_entry_unread(entry_id: StringName) -> bool:
	return Codex.is_unread(Codex.Category.EVENTS, entry_id)


func _mark_entry_viewed(entry_id: StringName) -> void:
	Codex.mark_viewed(Codex.Category.EVENTS, entry_id)


func _show_entry_details(entry_id: StringName) -> void:
	var event_data: Dictionary = _events.get(entry_id, {})
	details_panel.show_event(event_data)


func _get_unlock_hint(entry_id: StringName) -> String:
	var event_data: Dictionary = _events.get(entry_id, {})
	return CharacterData._str_val(event_data, &"unlock_hint")
