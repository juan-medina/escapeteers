# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

extends Node

signal unread_changed

enum Category {
	HEROES,
	ENEMIES,
	ITEMS,
	EVENTS,
}

const SAVE_PATH: StringName = &"user://codex.cfg"
const SECTION_PROGRESS: StringName = &"progress"
const DISCOVERED_KEYS: Dictionary[Category, StringName] = {
	Category.HEROES: &"discovered_heroes",
	Category.ENEMIES: &"discovered_enemies",
	Category.ITEMS: &"discovered_items",
	Category.EVENTS: &"discovered_events",
}
const VIEWED_KEYS: Dictionary[Category, StringName] = {
	Category.HEROES: &"viewed_heroes",
	Category.ENEMIES: &"viewed_enemies",
	Category.ITEMS: &"viewed_items",
	Category.EVENTS: &"viewed_events",
}
const DEFAULT_HERO_IDS: Array[StringName] = [
	&"archer",
	&"armored_axeman",
	&"knight",
	&"knight_templar",
	&"priest",
	&"soldier",
	&"swordsman",
	&"wizard",
]

var _discovered: Dictionary[Category, Dictionary] = {}
var _viewed: Dictionary[Category, Dictionary] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for category: Category in DISCOVERED_KEYS:
		_discovered[category] = {}
		_viewed[category] = {}
	_seed_default_heroes()
	_load()


func is_discovered(category: Category, entry_id: StringName) -> bool:
	var discovered_set: Dictionary = _discovered[category]
	return discovered_set.has(entry_id)


func is_unread(category: Category, entry_id: StringName) -> bool:
	var discovered_set: Dictionary = _discovered[category]
	var viewed_set: Dictionary = _viewed[category]
	return discovered_set.has(entry_id) and not viewed_set.has(entry_id)


func has_unread(category: Category) -> bool:
	var discovered_set: Dictionary = _discovered[category]
	var viewed_set: Dictionary = _viewed[category]
	for entry_id: Variant in discovered_set:
		if not viewed_set.has(entry_id):
			return true
	return false


func has_any_unread() -> bool:
	for category: Category in DISCOVERED_KEYS:
		if has_unread(category):
			return true
	return false


func discover(category: Category, entry_id: StringName) -> void:
	var discovered_set: Dictionary = _discovered[category]
	if entry_id.is_empty() or discovered_set.has(entry_id):
		return
	discovered_set[entry_id] = true
	_save()
	unread_changed.emit()


func mark_viewed(category: Category, entry_id: StringName) -> void:
	var discovered_set: Dictionary = _discovered[category]
	var viewed_set: Dictionary = _viewed[category]
	if not discovered_set.has(entry_id) or viewed_set.has(entry_id):
		return
	viewed_set[entry_id] = true
	_save()
	unread_changed.emit()


func _seed_default_heroes() -> void:
	var discovered_heroes: Dictionary = _discovered[Category.HEROES]
	var viewed_heroes: Dictionary = _viewed[Category.HEROES]
	for hero_id: StringName in DEFAULT_HERO_IDS:
		discovered_heroes[hero_id] = true
		viewed_heroes[hero_id] = true


func _load() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(SAVE_PATH)
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			printerr(&"Codex: Failed to load progress from %s. Error: %d !" % [SAVE_PATH, err])
		_seed_default_heroes()
		return

	for category: Category in DISCOVERED_KEYS:
		_read_id_set(config, DISCOVERED_KEYS[category], _discovered[category])
		_read_id_set(config, VIEWED_KEYS[category], _viewed[category])
	_seed_default_heroes()


func _save() -> void:
	var config: ConfigFile = ConfigFile.new()
	for category: Category in DISCOVERED_KEYS:
		config.set_value(SECTION_PROGRESS, DISCOVERED_KEYS[category], _dict_to_packed_array(_discovered[category]))
		config.set_value(SECTION_PROGRESS, VIEWED_KEYS[category], _dict_to_packed_array(_viewed[category]))

	var err: Error = config.save(SAVE_PATH)
	if err != OK:
		printerr(&"Codex: Failed to save progress to %s. Error: %d !" % [SAVE_PATH, err])


func _read_id_set(config: ConfigFile, key: StringName, target: Dictionary) -> void:
	var raw: Variant = config.get_value(SECTION_PROGRESS, key, PackedStringArray())
	if raw is PackedStringArray:
		var packed: PackedStringArray = raw
		for item: String in packed:
			if not item.is_empty():
				target[StringName(item)] = true
	elif raw is Array:
		var arr: Array = raw
		for item: Variant in arr:
			if item is String or item is StringName:
				var item_str: String = str(item)
				if not item_str.is_empty():
					target[StringName(item_str)] = true


static func _dict_to_packed_array(dict: Dictionary) -> PackedStringArray:
	var arr: PackedStringArray = PackedStringArray()
	for id_var: Variant in dict:
		arr.append(str(id_var))
	return arr
