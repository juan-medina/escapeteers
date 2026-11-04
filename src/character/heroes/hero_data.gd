# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name HeroData
extends CharacterData

const HEROES_JSON_PATH: String = "res://character/heroes/heroes.json"

static var _cached_heroes: Dictionary[StringName, HeroData] = {}
static var _cached_order: Array[StringName] = []

var role: String = ""


static func _ensure_loaded() -> void:
	if not _cached_heroes.is_empty():
		return

	var root: Dictionary = CharacterData.load_json_file(HEROES_JSON_PATH)
	for key: Variant in root.keys():
		var entry_val: Variant = root[key]
		if entry_val is Dictionary:
			var entry: Dictionary = entry_val
			var hero_data: HeroData = HeroData._from_dict(entry)
			_cached_heroes[hero_data.id] = hero_data
			_cached_order.append(hero_data.id)


static func _from_dict(dict: Dictionary) -> HeroData:
	var h: HeroData = HeroData.new()
	h.parse_base_fields(dict)
	h.role = _str_val(dict, "role")
	return h


static func get_all_heroes() -> Array[HeroData]:
	_ensure_loaded()
	var list: Array[HeroData] = []
	for id_key: StringName in _cached_order:
		list.append(_cached_heroes[id_key])
	return list


static func get_hero(hero_id: StringName) -> HeroData:
	_ensure_loaded()
	return _cached_heroes.get(hero_id, null)


static func get_random_choices(count: int) -> Array[HeroData]:
	_ensure_loaded()
	var pool: Array[StringName] = _cached_order.duplicate()
	pool.shuffle()
	var result: Array[HeroData] = []
	var take_count: int = mini(count, pool.size())
	for i: int in range(take_count):
		result.append(_cached_heroes[pool[i]])
	return result


func apply_to_hero(hero: Hero, level: int = 1) -> void:
	hero.level = level
	hero.hero_data = self
	hero.max_health = get_health(level)
	hero.health = hero.max_health

	var melee_idx: int = 0
	for skill: Dictionary in skills:
		var type: String = _str_val(skill, "type")
		var cd: float = eval_stat(skill.get("cooldown"), level, 1.0)
		var rng: float = eval_stat(skill.get("range"), level, 28.0)
		var kb: float = eval_stat(skill.get("knockback"), level, 0.0)
		var chance: float = _float_val(skill, "chance", 0.35)

		if type == "melee":
			var dmg: float = eval_stat(skill.get("damage"), level, 10.0)
			hero.can_melee = true
			if melee_idx == 0:
				hero.melee1_damage = dmg
				hero.melee1_cooldown = cd
				hero.melee_range = rng
				hero.melee1_knockback = kb
				hero.melee1_stun_duration = eval_stat(skill.get("stun_duration"), level, 0.0)
				if skill.has("leash"):
					hero.melee_leash_distance = _float_val(skill, "leash", 72.0)
				melee_idx += 1
			elif melee_idx == 1:
				hero.can_heavy_melee = true
				hero.melee2_damage = dmg
				hero.melee2_cooldown = cd
				hero.melee2_knockback = kb
				hero.melee2_chance = chance
				melee_idx += 1
		elif type == "ranged":
			var dmg: float = eval_stat(skill.get("damage"), level, 10.0)
			hero.can_ranged = true
			hero.ranged_damage = dmg
			hero.ranged_cooldown = cd
			hero.ranged_range = rng
			hero.ranged_knockback = kb
			if skill.has("stun_duration"):
				hero.ranged_stun_duration = eval_stat(skill.get("stun_duration"), level, 0.0)
		elif type == "heal":
			var amount: float = eval_stat(skill.get("heal_amount"), level, 20.0)
			hero.can_heal = true
			hero.heal_amount = amount
			hero.heal_cooldown = cd
			hero.heal_range = rng

	if hero.is_node_ready():
		hero.refresh_combat_actions()


func instantiate_hero(level: int = 1) -> Hero:
	if scene == null:
		push_error("Cannot instantiate hero, scene is null for: " + name)
		return null
	var inst: Node = scene.instantiate()
	if inst is Hero:
		var hero: Hero = inst
		apply_to_hero(hero, level)
		return hero
	return null
