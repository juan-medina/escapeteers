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


static func _str_val(dict: Dictionary, key: String, default_val: String = "") -> String:
	var val: Variant = dict.get(key)
	if val is String:
		return val
	return default_val


static func _float_val(dict: Dictionary, key: String, default_val: float = 0.0) -> float:
	var val: Variant = dict.get(key)
	if val is float:
		return val
	if val is int:
		var i: int = val
		return float(i)
	return default_val


static func _dict_val(dict: Dictionary, key: String) -> Dictionary:
	var val: Variant = dict.get(key)
	if val is Dictionary:
		return val
	return {}


static func eval_stat(stat_val: Variant, level: int = 1, default_base: float = 0.0) -> float:
	if stat_val is Dictionary:
		var d: Dictionary = stat_val
		var base: float = _float_val(d, "base", default_base)
		var growth: float = _float_val(d, "growth", 0.0)
		return base * (1.0 + float(maxi(1, level) - 1) * growth)
	if stat_val is float:
		return stat_val
	if stat_val is int:
		var i: int = stat_val
		return float(i)
	return default_base


static func load_json_file(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		push_error("JSON file not found: " + file_path)
		return {}

	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open JSON file: " + file_path)
		return {}

	var json_text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(json_text)
	if parse_result != OK:
		push_error("Failed to parse " + file_path + ": " + json.get_error_message())
		return {}

	var root_data: Variant = json.data
	if root_data is Dictionary:
		return root_data

	push_error("JSON root must be a Dictionary: " + file_path)
	return {}


func parse_base_fields(dict: Dictionary) -> void:
	id = StringName(_str_val(dict, "id"))
	name = _str_val(dict, "name")
	scene_path = _str_val(dict, "scene_path")
	if ResourceLoader.exists(scene_path):
		var res: Resource = load(scene_path)
		if res is PackedScene:
			scene = res

	health_stat = _dict_val(dict, "health")
	speed_stat = _dict_val(dict, "speed")

	var raw_skills: Variant = dict.get("skills")
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
