# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name EnemyData
extends CharacterData

const ENEMIES_JSON_PATH: String = "res://character/enemies/enemies.json"

static var _cached_enemies: Dictionary[StringName, EnemyData] = {}
static var _cached_order: Array[StringName] = []

var detection_range_stat: Dictionary = {}
var xp_stat: Dictionary = {}


static func _ensure_loaded() -> void:
	if not _cached_enemies.is_empty():
		return

	var root: Dictionary = CharacterData.load_json_file(ENEMIES_JSON_PATH)
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
	e.detection_range_stat = _dict_val(dict, "detection_range")
	e.xp_stat = _dict_val(dict, "xp")
	return e


static func get_all_enemies() -> Array[EnemyData]:
	_ensure_loaded()
	var list: Array[EnemyData] = []
	for id_key: StringName in _cached_order:
		list.append(_cached_enemies[id_key])
	return list


static func get_enemy(enemy_id: StringName) -> EnemyData:
	_ensure_loaded()
	return _cached_enemies.get(enemy_id, null)


func get_detection_range(level: int = 1) -> float:
	return eval_stat(detection_range_stat, level, 135.0)


func get_xp(level: int = 1) -> float:
	return eval_stat(xp_stat, level, 10.0)


func apply_to_enemy(enemy: Enemy, level: int = 1) -> void:
	enemy.max_health = get_health(level)
	enemy.health = enemy.max_health
	enemy.speed = get_speed(level)
	enemy.detection_range = get_detection_range(level)
	enemy.xp_value = get_xp(level)

	var melee_idx: int = 0
	for skill: Dictionary in skills:
		var type: String = _str_val(skill, "type")
		var cd: float = eval_stat(skill.get("cooldown"), level, 1.2)
		var rng: float = eval_stat(skill.get("range"), level, 20.0)

		if type == "melee":
			var dmg: float = eval_stat(skill.get("damage"), level, 8.0)
			enemy.can_melee = true
			if melee_idx == 0:
				enemy.melee_range = rng
				enemy.attack_cooldown = cd
				enemy.set(&"melee_damage", dmg)
				melee_idx += 1
			elif melee_idx == 1:
				var chance: float = _float_val(skill, "chance", 0.35)
				enemy.set(&"can_heavy_melee", true)
				enemy.set(&"melee2_damage", dmg)
				enemy.set(&"melee2_cooldown", cd)
				enemy.set(&"melee2_chance", chance)
				melee_idx += 1
		elif type == "ranged":
			var dmg: float = eval_stat(skill.get("damage"), level, 5.0)
			var min_rng: float = _float_val(skill, "min_range", 65.0)
			enemy.can_ranged = true
			enemy.damage = dmg
			enemy.ranged_range = rng
			enemy.ranged_min_range = min_rng
			enemy.attack_cooldown = cd


func instantiate_enemy(level: int = 1) -> Enemy:
	if scene == null:
		push_error("Cannot instantiate enemy, scene is null for: " + name)
		return null
	var inst: Node = scene.instantiate()
	if inst is Enemy:
		var enemy: Enemy = inst
		apply_to_enemy(enemy, level)
		return enemy
	return null
