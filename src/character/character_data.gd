# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name CharacterData
extends RefCounted

var id: StringName = &""
var name: String = ""
var scene_path: String = ""
var scene: PackedScene = null

var health_stat: Dictionary = {}
var speed_stat: Dictionary = {}
var skills: Array[Dictionary] = []


static func _str_val(dict: Dictionary, key: StringName, default_val: String = "") -> String:
	var val: Variant = dict.get(key)
	if val is String:
		return val
	return default_val


static func _float_val(dict: Dictionary, key: StringName, default_val: float = 0.0) -> float:
	var val: Variant = dict.get(key)
	if val is float:
		return val
	if val is int:
		var i: int = val
		return float(i)
	return default_val


static func _dict_val(dict: Dictionary, key: StringName) -> Dictionary:
	var val: Variant = dict.get(key)
	if val is Dictionary:
		return val
	return {}


static func eval_stat(stat_val: Variant, level: int = 1, default_base: float = 0.0) -> float:
	if stat_val is Dictionary:
		var d: Dictionary = stat_val
		var base: float = _float_val(d, &"base", default_base)
		var growth: float = _float_val(d, &"growth", 0.0)
		return base * (1.0 + float(maxi(1, level) - 1) * growth)
	if stat_val is float:
		return stat_val
	if stat_val is int:
		var i: int = stat_val
		return float(i)
	return default_base


static func load_json_file(file_path: StringName) -> Dictionary:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		printerr(&"CharacterData: Failed to open %s !" % file_path)
		await Alerts.fatal_error(&"Could not load game data")
		return {}

	var json_text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(json_text)
	if parse_result != OK:
		printerr(&"CharacterData: Failed to parse %s at line %d: %s !" % [file_path, json.get_error_line(), json.get_error_message()])
		await Alerts.fatal_error(&"Could not load game data")
		return {}

	var root_data: Variant = json.data
	if root_data is Dictionary:
		return root_data

	printerr(&"CharacterData: JSON root must be a Dictionary in %s !" % file_path)
	await Alerts.fatal_error(&"Could not load game data")
	return {}


func parse_base_fields(dict: Dictionary) -> void:
	id = StringName(_str_val(dict, &"id"))
	name = _str_val(dict, &"name")
	scene_path = _str_val(dict, &"scene_path")
	scene = load(scene_path) as PackedScene

	health_stat = _dict_val(dict, &"health")
	speed_stat = _dict_val(dict, &"speed")

	var raw_skills: Variant = dict.get(&"skills")
	if raw_skills is Array:
		var arr: Array = raw_skills
		for item: Variant in arr:
			if item is Dictionary:
				var s: Dictionary = item
				skills.append(s)


func get_health(level: int = 1) -> float:
	return eval_stat(health_stat, level, 100.0)


func get_speed(level: int = 1) -> float:
	return eval_stat(speed_stat, level, 100.0)
