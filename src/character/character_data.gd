# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name CharacterData
extends RefCounted

enum SkillType {
	MELEE,
	RANGED,
	HEAL,
	SUMMON,
	PASSIVE,
}

enum EffectType {
	NONE,
	KNOCKBACK,
	STUN,
	BURN,
	MARK,
	SLOW,
}

var id: StringName = &""
var name: String = ""
var description: String = ""
var unlock_hint: String = ""
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
		var steps: float = float(maxi(1, level) - 1)
		if growth < 0.0:
			return base / (1.0 + steps * absf(growth))
		if growth > 0.0:
			return base * pow(1.0 + growth, steps)
		return base
	if stat_val is float:
		return stat_val
	if stat_val is int:
		var i: int = stat_val
		return float(i)
	return default_base


static func eval_skill(skill: Dictionary, level: int) -> Dictionary:
	var effect: Dictionary = _dict_val(skill, &"effect")
	var effect_type: EffectType = EffectType.NONE
	var effect_amount: float = 0.0
	var effect_duration: float = 0.0
	if not effect.is_empty():
		effect_type = effect[&"type"]
		effect_amount = eval_stat(effect.get(&"amount"), level, 0.0)
		effect_duration = eval_stat(effect.get(&"duration"), level, 0.0)
	return {
		&"name": _str_val(skill, &"name"),
		&"description": _str_val(skill, &"description"),
		&"type": skill[&"type"],
		&"hits": int(_float_val(skill, &"hits", 1.0)),
		&"has_chance": skill.has(&"chance"),
		&"amount": eval_stat(skill.get(&"amount"), level, 10.0),
		&"cooldown": eval_stat(skill.get(&"cooldown"), level, 1.0),
		&"range": eval_stat(skill.get(&"range"), level, 20.0),
		&"min_range": _float_val(skill, &"min_range", 65.0),
		&"leash": _float_val(skill, &"leash", 96.0),
		&"chance": _float_val(skill, &"chance", 0.35),
		&"effect_type": effect_type,
		&"effect_amount": effect_amount,
		&"effect_duration": effect_duration,
	}


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


static func extract_sprite_frames(packed_scene: PackedScene) -> SpriteFrames:
	var state: SceneState = packed_scene.get_state()
	for i: int in range(state.get_node_count()):
		if state.get_node_name(i) == &"AnimatedSprite2D":
			for j: int in range(state.get_node_property_count(i)):
				if state.get_node_property_name(i, j) == &"sprite_frames":
					var val: Variant = state.get_node_property_value(i, j)
					if val is SpriteFrames:
						return val
	return null


func parse_base_fields(dict: Dictionary) -> void:
	id = StringName(_str_val(dict, &"id"))
	name = _str_val(dict, &"name")
	description = _str_val(dict, &"description")
	unlock_hint = _str_val(dict, &"unlock_hint")
	scene_path = _str_val(dict, &"scene_path")
	scene = load(scene_path) as PackedScene

	health_stat = _dict_val(dict, &"health")
	speed_stat = _dict_val(dict, &"speed")

	var raw_skills: Variant = dict.get(&"skills")
	if raw_skills is Array:
		var arr: Array = raw_skills
		for item: Variant in arr:
			if item is Dictionary:
				var item_dict: Dictionary = item
				var s: Dictionary = item_dict.duplicate()
				s[&"type"] = SkillType[_str_val(s, &"type")]
				if s.has(&"effect"):
					var eff_dict: Dictionary = _dict_val(s, &"effect").duplicate()
					eff_dict[&"type"] = EffectType[_str_val(eff_dict, &"type")]
					s[&"effect"] = eff_dict
				skills.append(s)


func get_health(level: int = 1) -> float:
	return eval_stat(health_stat, level, 100.0)


func get_speed(level: int = 1) -> float:
	return eval_stat(speed_stat, level, 100.0)


func get_active_skills() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for skill: Dictionary in skills:
		if skill[&"type"] != SkillType.PASSIVE:
			result.append(skill)
	return result


func get_passive_skills() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for skill: Dictionary in skills:
		if skill[&"type"] == SkillType.PASSIVE:
			result.append(skill)
	return result
