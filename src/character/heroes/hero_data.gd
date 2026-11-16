# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name HeroData
extends CharacterData

enum Role {
	MELEE,
	RANGED,
	HEALER,
	HYBRID,
}

const HEROES_JSON_PATH: StringName = &"res://character/heroes/heroes.json"

static var _heroes: Dictionary[StringName, HeroData] = {}
static var _heroes_by_role: Array[HeroData] = []

var role: Role = Role.MELEE
var abbr: String = ""
var color: Color = Color.WHITE
var is_secret: bool = false
var sprite_frames: SpriteFrames = null


static func initialize() -> void:
	var root: Dictionary = await load_json_file(HEROES_JSON_PATH)
	for entry: Dictionary in root.values():
		var hero_data: HeroData = _from_dict(entry)
		_heroes[hero_data.id] = hero_data
		if not hero_data.is_secret:
			_heroes_by_role.append(hero_data)


static func get_hero(hero_id: StringName) -> HeroData:
	return _heroes.get(hero_id, null)


static func get_random_choices(count: int) -> Array[HeroData]:
	var pool: Array[HeroData] = _heroes_by_role.duplicate()
	pool.shuffle()
	return pool.slice(0, count)


func apply_to_hero(hero: Hero, level: int = 1) -> void:
	hero.level = level
	hero.hero_data = self
	hero.max_health = get_health(level)
	hero.health = hero.max_health

	var melee_idx: int = 0
	for skill: Dictionary in skills:
		var type: CharacterData.SkillType = skill[&"type"]
		match type:
			CharacterData.SkillType.MELEE:
				hero.can_melee = true
				var prefix: String = "melee1" if melee_idx == 0 else "melee2"
				if melee_idx == 1:
					hero.can_heavy_melee = true
				_apply_skill(hero, prefix, skill, level)
				melee_idx += 1
			CharacterData.SkillType.RANGED:
				hero.can_ranged = true
				_apply_skill(hero, "ranged", skill, level)
			CharacterData.SkillType.HEAL:
				hero.can_heal = true
				_apply_skill(hero, "heal", skill, level)

	if hero.is_node_ready():
		hero.refresh_combat_actions()


static func _from_dict(dict: Dictionary) -> HeroData:
	var h: HeroData = HeroData.new()
	h.parse_base_fields(dict)
	h.role = Role[_str_val(dict, &"role")]
	h.abbr = _str_val(dict, &"abbr")
	h.color = Color.from_string(_str_val(dict, &"color"), Color.WHITE)
	h.is_secret = dict.get(&"secret", false) == true
	h.sprite_frames = extract_sprite_frames(h.scene)
	return h


static func _apply_skill(hero: Hero, prefix: String, skill: Dictionary, level: int) -> void:
	var s: Dictionary = eval_skill(skill, level)
	var amount: float = s[&"amount"]
	var effect_type: CharacterData.EffectType = s[&"effect_type"]
	var effect_amount: float = s[&"effect_amount"]
	var effect_duration: float = s[&"effect_duration"]

	hero.set(prefix + "_damage", amount)
	hero.set(prefix + "_amount", amount)
	hero.set(prefix + "_cooldown", s[&"cooldown"])
	hero.set(prefix + "_range", s[&"range"])
	hero.set(prefix + "_chance", s[&"chance"])
	hero.set(prefix + "_knockback", effect_amount if effect_type == CharacterData.EffectType.KNOCKBACK else 0.0)
	hero.set(prefix + "_stun_duration", effect_duration if effect_type == CharacterData.EffectType.STUN else 0.0)
	hero.set(prefix + "_burn_dps", effect_amount if effect_type == CharacterData.EffectType.BURN else 0.0)
	hero.set(prefix + "_burn_duration", effect_duration if effect_type == CharacterData.EffectType.BURN else 0.0)
	if prefix == "melee1":
		hero.melee_range = s[&"range"]
		if skill.has(&"leash"):
			hero.melee_leash_distance = s[&"leash"]
