# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name CodexItemsPanel
extends CodexUnitsPanel

const ITEMS_JSON_PATH: StringName = &"res://codex_panel/items.json"

static var _items: Dictionary[StringName, Dictionary] = {}
static var _frames_by_path: Dictionary[String, SpriteFrames] = {}


static func initialize_data() -> void:
	if not _items.is_empty():
		return

	var root: Dictionary = await CharacterData.load_json_file(ITEMS_JSON_PATH)
	if root.is_empty():
		return

	for key_var: Variant in root:
		var item_var: Variant = root[key_var]
		if item_var is Dictionary:
			var item_dict: Dictionary = item_var
			_items[StringName(str(key_var))] = item_dict
			var scene_path: String = CharacterData._str_val(item_dict, &"scene_path")
			if not scene_path.is_empty() and not _frames_by_path.has(scene_path):
				var packed: PackedScene = load(scene_path) as PackedScene
				_frames_by_path[scene_path] = CharacterData.extract_sprite_frames(packed)


func _setup_card(card: CodexEntryCard) -> void:
	var item: Dictionary = _items.get(card.entry_id, {})
	var item_name: String = CharacterData._str_val(item, &"name")
	var item_color: Color = Color.from_string(CharacterData._str_val(item, &"color"), Color.WHITE)
	var scene_path: String = CharacterData._str_val(item, &"scene_path")
	var anim_name: StringName = StringName(CharacterData._str_val(item, &"anim_name", "idle"))
	var frames: SpriteFrames = _frames_by_path.get(scene_path, null)
	card.setup_item(item_name, item_color, frames, anim_name)


func _is_entry_discovered(entry_id: StringName) -> bool:
	return Codex.is_item_discovered(entry_id)


func _is_entry_unread(entry_id: StringName) -> bool:
	return Codex.is_item_unread(entry_id)


func _mark_entry_viewed(entry_id: StringName) -> void:
	Codex.mark_item_viewed(entry_id)


func _show_entry_details(entry_id: StringName) -> void:
	var item: Dictionary = _items.get(entry_id, {})
	details_panel.show_item(item)


func _get_unlock_hint(entry_id: StringName) -> String:
	var item: Dictionary = _items.get(entry_id, {})
	return CharacterData._str_val(item, &"unlock_hint")
