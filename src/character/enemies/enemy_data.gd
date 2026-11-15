# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name EnemyData
extends CharacterData

const ENEMIES_JSON_PATH: StringName = &"res://character/enemies/enemies.json"

static var _cached_enemies: Dictionary[StringName, EnemyData] = {}
static var _cached_order: Array[StringName] = []

var detection_range_stat: Dictionary = {}
var xp_stat: Dictionary = {}


static func initialize() -> void:
	if not _cached_enemies.is_empty():
		return

	var root: Dictionary = await CharacterData.load_json_file(ENEMIES_JSON_PATH)
	for key: Variant in root.keys():
		var entry_val: Variant = root[key]
		if entry_val is Dictionary:
			var entry: Dictionary = entry_val
			var enemy_data: EnemyData = EnemyData._from_dict(entry)
			_cached_enemies[enemy_data.id] = enemy_data
			_cached_order.append(enemy_data.id)


static func _from_dict(dict: Dictionary) -> EnemyData:
	var e: EnemyData = EnemyData.new()
	e.parse_base_fields(dict)
	e.detection_range_stat = _dict_val(dict, &"detection_range")
	e.xp_stat = _dict_val(dict, &"xp")
	return e


static func get_all_enemies() -> Array[EnemyData]:
	var list: Array[EnemyData] = []
	for id_key: StringName in _cached_order:
		list.append(_cached_enemies[id_key])
	return list


static func get_enemy(enemy_id: StringName) -> EnemyData:
	return _cached_enemies.get(enemy_id, null)


func get_detection_range(level: int = 1) -> float:
	return eval_stat(detection_range_stat, level, 135.0)


func get_xp(level: int = 1) -> float:
	var base: float = _float_val(xp_stat, &"base", 10.0)
	var growth: float = _float_val(xp_stat, &"growth", 0.0)
	return base * (1.0 + float(maxi(1, level) - 1) * growth)


func apply_to_enemy(enemy: Enemy, level: int = 1) -> void:
	enemy.max_health = get_health(level)
	enemy.health = enemy.max_health
	enemy.speed = get_speed(level)
	enemy.detection_range = get_detection_range(level)
	enemy.xp_value = get_xp(level)

	var melee_idx: int = 0
	for skill: Dictionary in skills:
		var s: Dictionary = eval_skill(skill, level)
		var type: CharacterData.SkillType = s[&"type"]
		var amount: float = s[&"amount"]
		var cd: float = s[&"cooldown"]
		var rng: float = s[&"range"]

		match type:
			CharacterData.SkillType.MELEE:
				enemy.can_melee = true
				if melee_idx == 0:
					enemy.melee_range = rng
					enemy.attack_cooldown = cd
					enemy.melee_damage = amount
					melee_idx += 1
				elif melee_idx == 1:
					enemy.can_heavy_melee = true
					enemy.melee2_damage = amount
					enemy.melee2_cooldown = cd
					enemy.melee2_chance = s[&"chance"]
					melee_idx += 1
			CharacterData.SkillType.RANGED:
				enemy.can_ranged = true
				enemy.damage = amount
				enemy.ranged_range = rng
				enemy.ranged_min_range = s[&"min_range"]
				enemy.attack_cooldown = cd
			CharacterData.SkillType.SUMMON:
				enemy.can_summon = true
				enemy.summon_range = rng
				enemy.summon_count = int(amount)
				enemy.attack_cooldown = cd
