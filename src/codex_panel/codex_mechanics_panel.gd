# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name CodexMechanicsPanel
extends MenuPanel

const MECHANICS_JSON_PATH: StringName = &"res://codex_panel/mechanics.json"
const TOPIC_STATUS_EFFECTS: StringName = &"status_effects"
const TOPIC_FORMATION: StringName = &"formation"
const TOPIC_SQUAD_LEVELING: StringName = &"squad_and_leveling"
const TOPIC_KEYS_TRAPS: StringName = &"keys_and_traps"

static var _topics: Dictionary[StringName, Dictionary] = {}

var _buttons_by_id: Dictionary[StringName, Button] = {}

@onready var _status_button: Button = $VBox/ContentRow/TopicsVBox/StatusEffects
@onready var _formation_button: Button = $VBox/ContentRow/TopicsVBox/Formation
@onready var _squad_button: Button = $VBox/ContentRow/TopicsVBox/SquadLeveling
@onready var _keys_button: Button = $VBox/ContentRow/TopicsVBox/KeysTraps
@onready var _detail_text: RichTextLabel = $VBox/ContentRow/DetailPanel/DetailText


static func initialize_data() -> void:
	if not _topics.is_empty():
		return

	var root: Dictionary = await CharacterData.load_json_file(MECHANICS_JSON_PATH)
	if root.is_empty():
		return

	for key_var: Variant in root:
		var topic_var: Variant = root[key_var]
		if topic_var is Dictionary:
			var topic_dict: Dictionary = topic_var
			_topics[StringName(str(key_var))] = topic_dict


func _ready() -> void:
	_buttons_by_id[TOPIC_STATUS_EFFECTS] = _status_button
	_buttons_by_id[TOPIC_FORMATION] = _formation_button
	_buttons_by_id[TOPIC_SQUAD_LEVELING] = _squad_button
	_buttons_by_id[TOPIC_KEYS_TRAPS] = _keys_button
	super._ready()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready() and is_visible_in_tree():
		back_button.focus_neighbor_top = _status_button.get_path()
		_show_topic(TOPIC_STATUS_EFFECTS)


func initialize() -> void:
	for topic_id: StringName in _buttons_by_id:
		var topic_var: Variant = _topics.get(topic_id)
		if topic_var is Dictionary:
			var topic_dict: Dictionary = topic_var
			var title: String = CharacterData._str_val(topic_dict, &"title")
			if not title.is_empty():
				_buttons_by_id[topic_id].text = title
	_show_topic(TOPIC_STATUS_EFFECTS)


func _select_topic(topic_id: StringName) -> void:
	var btn: Button = _buttons_by_id[topic_id]
	back_button.focus_neighbor_top = btn.get_path()
	_show_topic(topic_id)


func _show_topic(topic_id: StringName) -> void:
	var topic_var: Variant = _topics.get(topic_id)
	if not (topic_var is Dictionary):
		_detail_text.text = ""
		return

	var topic: Dictionary = topic_var
	var title: String = CharacterData._str_val(topic, &"title")
	var summary: String = CharacterData._str_val(topic, &"summary")
	var lines: PackedStringArray = PackedStringArray()
	if not title.is_empty():
		lines.append("[color=#ffffff][b]%s[/b][/color]" % title)
	if not summary.is_empty():
		lines.append("[color=#cbd5e1]%s[/color]\n" % summary)

	var entries_var: Variant = topic.get(&"entries")
	if entries_var is Array:
		var entries: Array = entries_var
		for item_var: Variant in entries:
			if item_var is Dictionary:
				var entry: Dictionary = item_var
				var entry_name: String = CharacterData._str_val(entry, &"name")
				var entry_color: String = CharacterData._str_val(entry, &"color", "#ffd166")
				var entry_text: String = CharacterData._str_val(entry, &"text")
				lines.append("[color=%s][b]%s:[/b][/color] %s" % [entry_color, entry_name, entry_text])

	_detail_text.text = "\n".join(lines)
	_detail_text.get_v_scroll_bar().value = 0.0


func _on_status_effects_inspected() -> void:
	_select_topic(TOPIC_STATUS_EFFECTS)


func _on_formation_inspected() -> void:
	_select_topic(TOPIC_FORMATION)


func _on_squad_leveling_inspected() -> void:
	_select_topic(TOPIC_SQUAD_LEVELING)


func _on_keys_traps_inspected() -> void:
	_select_topic(TOPIC_KEYS_TRAPS)
