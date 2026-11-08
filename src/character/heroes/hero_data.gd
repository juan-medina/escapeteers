# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name HeroData
extends CharacterData

const HEROES_JSON_PATH: StringName = &"res://character/heroes/heroes.json"

const COLOR_ROLE_MELEE: Color = Color(1.0, 0.45, 0.35)
const COLOR_ROLE_RANGED: Color = Color(0.40, 0.80, 1.0)
const COLOR_ROLE_HYBRID: Color = Color(1.0, 0.80, 0.30)
const COLOR_ROLE_HEALER: Color = Color(0.40, 0.95, 0.55)
const ROLE_PRIORITY: Dictionary[String, int] = {
	"Melee": 0,
	"Ranged": 1,
	"Healer": 2,
	"Hybrid": 3,
}

static var _cached_heroes: Dictionary[StringName, HeroData] = {}
static var _cached_order: Array[StringName] = []
static var _cached_role_order: Array[HeroData] = []

var role: String = ""
var role_color: Color = COLOR_ROLE_MELEE
var abbr: String = ""
var color: Color = Color.WHITE
var is_secret: bool = false
var _cached_sprite_frames: SpriteFrames = null


static func initialize() -> void:
	if not _cached_heroes.is_empty():
		return

	var root: Dictionary = await CharacterData.load_json_file(HEROES_JSON_PATH)
	for key: Variant in root.keys():
		var entry_val: Variant = root[key]
		if entry_val is Dictionary:
			var entry: Dictionary = entry_val
			var hero_data: HeroData = HeroData._from_dict(entry)
			_cached_heroes[hero_data.id] = hero_data
			if not hero_data.is_secret:
				_cached_order.append(hero_data.id)
				_cached_role_order.append(hero_data)

	_cached_role_order.sort_custom(HeroData._compare_role_order)


static func _from_dict(dict: Dictionary) -> HeroData:
	var h: HeroData = HeroData.new()
	h.parse_base_fields(dict)
	h.role = _str_val(dict, &"role")
	if h.role.is_empty():
		h.role = _infer_role_from_skills(h.skills)
	h.role_color = get_role_color_for_name(h.role)
	h.abbr = _str_val(dict, &"abbr")
	h.color = Color.from_string(_str_val(dict, &"color"), Color.WHITE)
	h.is_secret = dict.get(&"secret", false) == true
	return h


static func _infer_role_from_skills(skill_list: Array[Dictionary]) -> String:
	var has_melee: bool = false
	var has_ranged: bool = false
	var has_heal: bool = false
	for skill: Dictionary in skill_list:
		var st: String = CharacterData._str_val(skill, &"type")
		if st == "heal":
			has_heal = true
		elif st == "ranged":
			has_ranged = true
		elif st == "melee":
			has_melee = true
	if has_heal:
		return "Healer"
	if has_melee and has_ranged:
		return "Hybrid"
	if has_ranged:
		return "Ranged"
	return "Melee"


static func _compare_role_order(a: HeroData, b: HeroData) -> bool:
	var prio_a: int = ROLE_PRIORITY.get(a.role, 99)
	var prio_b: int = ROLE_PRIORITY.get(b.role, 99)
	if prio_a != prio_b:
		return prio_a < prio_b
	return a.name < b.name


static func get_all_heroes() -> Array[HeroData]:
	var list: Array[HeroData] = []
	for id_key: StringName in _cached_order:
		list.append(_cached_heroes[id_key])
	return list


static func get_heroes_by_role_order() -> Array[HeroData]:
	return _cached_role_order.duplicate()


static func get_hero(hero_id: StringName) -> HeroData:
	return _cached_heroes.get(hero_id, null)


static func get_random_choices(count: int) -> Array[HeroData]:
	var pool: Array[StringName] = _cached_order.duplicate()
	pool.shuffle()
	var result: Array[HeroData] = []
	var take_count: int = mini(count, pool.size())
	for i: int in range(take_count):
		result.append(_cached_heroes[pool[i]])
	return result


static func get_role_color_for_name(role_name: String) -> Color:
	var r: String = role_name.to_lower()
	if "heal" in r or "support" in r:
		return COLOR_ROLE_HEALER
	if "hybrid" in r:
		return COLOR_ROLE_HYBRID
	if "range" in r:
		return COLOR_ROLE_RANGED
	return COLOR_ROLE_MELEE


func get_role_name() -> String:
	return role


func get_role_color() -> Color:
	return role_color


func apply_to_hero(hero: Hero, level: int = 1) -> void:
	hero.level = level
	hero.hero_data = self
	hero.max_health = get_health(level)
	hero.health = hero.max_health

	var melee_idx: int = 0
	for skill: Dictionary in skills:
		var type: String = _str_val(skill, &"type")
		var cd: float = eval_stat(skill.get(&"cooldown"), level, 1.0)
		var rng: float = eval_stat(skill.get(&"range"), level, 20.0)
		var kb: float = eval_stat(skill.get(&"knockback"), level, 0.0)
		var chance: float = _float_val(skill, &"chance", 0.35)

		if type == "melee":
			var dmg: float = eval_stat(skill.get(&"damage"), level, 10.0)
			hero.can_melee = true
			if melee_idx == 0:
				hero.melee1_damage = dmg
				hero.melee1_cooldown = cd
				hero.melee_range = rng
				hero.melee1_knockback = kb
				hero.melee1_stun_duration = eval_stat(skill.get(&"stun_duration"), level, 0.0)
				hero.melee1_burn_dps = eval_stat(skill.get(&"burn_damage"), level, 0.0)
				hero.melee1_burn_duration = eval_stat(skill.get(&"burn_duration"), level, 0.0)
				if skill.has(&"leash"):
					hero.melee_leash_distance = _float_val(skill, &"leash", 96.0)
				melee_idx += 1
			elif melee_idx == 1:
				hero.can_heavy_melee = true
				hero.melee2_damage = dmg
				hero.melee2_cooldown = cd
				hero.melee2_knockback = kb
				hero.melee2_chance = chance
				melee_idx += 1
		elif type == "ranged":
			var dmg: float = eval_stat(skill.get(&"damage"), level, 10.0)
			hero.can_ranged = true
			hero.ranged_damage = dmg
			hero.ranged_cooldown = cd
			hero.ranged_range = rng
			hero.ranged_knockback = kb
			if skill.has(&"stun_duration"):
				hero.ranged_stun_duration = eval_stat(skill.get(&"stun_duration"), level, 0.0)
		elif type == "heal":
			var amount: float = eval_stat(skill.get(&"heal_amount"), level, 20.0)
			hero.can_heal = true
			hero.heal_amount = amount
			hero.heal_cooldown = cd
			hero.heal_range = rng

	if hero.is_node_ready():
		hero.refresh_combat_actions()


func instantiate_hero(level: int = 1) -> Hero:
	var hero: Hero = scene.instantiate() as Hero
	apply_to_hero(hero, level)
	return hero


func get_sprite_frames() -> SpriteFrames:
	if _cached_sprite_frames == null:
		_cached_sprite_frames = CharacterData.extract_sprite_frames(scene)
	return _cached_sprite_frames
