# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

extends Node

signal unread_changed

const SAVE_PATH: StringName = &"user://codex.cfg"
const SECTION_PROGRESS: StringName = &"progress"
const KEY_DISCOVERED_HEROES: StringName = &"discovered_heroes"
const KEY_VIEWED_HEROES: StringName = &"viewed_heroes"
const KEY_DISCOVERED_ENEMIES: StringName = &"discovered_enemies"
const KEY_VIEWED_ENEMIES: StringName = &"viewed_enemies"

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

var _discovered_heroes: Dictionary[StringName, bool] = {}
var _viewed_heroes: Dictionary[StringName, bool] = {}
var _discovered_enemies: Dictionary[StringName, bool] = {}
var _viewed_enemies: Dictionary[StringName, bool] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_seed_default_heroes()
	_load()


func is_hero_discovered(hero_id: StringName) -> bool:
	return _discovered_heroes.has(hero_id)


func is_hero_unread(hero_id: StringName) -> bool:
	return _discovered_heroes.has(hero_id) and not _viewed_heroes.has(hero_id)


func is_enemy_discovered(enemy_id: StringName) -> bool:
	return _discovered_enemies.has(enemy_id)


func is_enemy_unread(enemy_id: StringName) -> bool:
	return _discovered_enemies.has(enemy_id) and not _viewed_enemies.has(enemy_id)


func has_unread_heroes() -> bool:
	for hero_id: StringName in _discovered_heroes:
		if not _viewed_heroes.has(hero_id):
			return true
	return false


func has_unread_enemies() -> bool:
	for enemy_id: StringName in _discovered_enemies:
		if not _viewed_enemies.has(enemy_id):
			return true
	return false


func has_any_unread() -> bool:
	return has_unread_heroes() or has_unread_enemies()


func discover_hero(hero_id: StringName) -> void:
	if hero_id.is_empty() or _discovered_heroes.has(hero_id):
		return
	_discovered_heroes[hero_id] = true
	_save()
	unread_changed.emit()


func discover_enemy(enemy_id: StringName) -> void:
	if enemy_id.is_empty() or _discovered_enemies.has(enemy_id):
		return
	_discovered_enemies[enemy_id] = true
	_save()
	unread_changed.emit()


func mark_hero_viewed(hero_id: StringName) -> void:
	if not _discovered_heroes.has(hero_id) or _viewed_heroes.has(hero_id):
		return
	_viewed_heroes[hero_id] = true
	_save()
	unread_changed.emit()


func mark_enemy_viewed(enemy_id: StringName) -> void:
	if not _discovered_enemies.has(enemy_id) or _viewed_enemies.has(enemy_id):
		return
	_viewed_enemies[enemy_id] = true
	_save()
	unread_changed.emit()


func _seed_default_heroes() -> void:
	for hero_id: StringName in DEFAULT_HERO_IDS:
		_discovered_heroes[hero_id] = true
		_viewed_heroes[hero_id] = true


func _load() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(SAVE_PATH)
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			printerr(&"Codex: Failed to load progress from %s. Error: %d !" % [SAVE_PATH, err])
		_seed_default_heroes()
		return

	_read_id_set(config, KEY_DISCOVERED_HEROES, _discovered_heroes)
	_read_id_set(config, KEY_VIEWED_HEROES, _viewed_heroes)
	_read_id_set(config, KEY_DISCOVERED_ENEMIES, _discovered_enemies)
	_read_id_set(config, KEY_VIEWED_ENEMIES, _viewed_enemies)
	_seed_default_heroes()


func _save() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value(SECTION_PROGRESS, KEY_DISCOVERED_HEROES, _dict_to_packed_array(_discovered_heroes))
	config.set_value(SECTION_PROGRESS, KEY_VIEWED_HEROES, _dict_to_packed_array(_viewed_heroes))
	config.set_value(SECTION_PROGRESS, KEY_DISCOVERED_ENEMIES, _dict_to_packed_array(_discovered_enemies))
	config.set_value(SECTION_PROGRESS, KEY_VIEWED_ENEMIES, _dict_to_packed_array(_viewed_enemies))

	var err: Error = config.save(SAVE_PATH)
	if err != OK:
		printerr(&"Codex: Failed to save progress to %s. Error: %d !" % [SAVE_PATH, err])


func _read_id_set(config: ConfigFile, key: StringName, target: Dictionary[StringName, bool]) -> void:
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


static func _dict_to_packed_array(dict: Dictionary[StringName, bool]) -> PackedStringArray:
	var arr: PackedStringArray = PackedStringArray()
	for id: StringName in dict:
		arr.append(String(id))
	return arr
