# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name SkillColumn
extends VBoxContainer

const COLOR_HP: Color = Color(0.40, 0.95, 0.45)
const COLOR_DMG: Color = Color(1.0, 0.50, 0.35)
const COLOR_BURN: Color = Color(1.0, 0.65, 0.20)
const COLOR_KB: Color = Color(0.90, 0.60, 1.0)
const COLOR_MARK: Color = Color(1.0, 0.35, 0.35)
const COLOR_SLOW: Color = Color(0.45, 0.85, 1.0)
const COOLDOWN_DELTA_EPSILON: float = -0.01

const SKILL_TYPE_NAMES: Dictionary[CharacterData.SkillType, String] = {
	CharacterData.SkillType.MELEE: "Melee",
	CharacterData.SkillType.RANGED: "Ranged",
	CharacterData.SkillType.HEAL: "Heal",
	CharacterData.SkillType.SUMMON: "Summon",
	CharacterData.SkillType.PASSIVE: "Passive",
}

@onready var _header_label: Label = $HeaderLabel
@onready var _amount_label: Label = $Grid/AmountPair/Label
@onready var _amount_value: Label = $Grid/AmountPair/Value
@onready var _effect_pair: HBoxContainer = $Grid/EffectPair
@onready var _effect_label: Label = $Grid/EffectPair/Label
@onready var _effect_value: Label = $Grid/EffectPair/Value
@onready var _cooldown_value: Label = $Grid/CooldownPair/Value
@onready var _range_value: Label = $Grid/RangePair/Value
@onready var _note_label: Label = $NoteLabel


static func format_int_delta(base_text: String, current_val: float, prev_val: float, has_prev: bool, multiplier: int = 1) -> String:
	if not has_prev:
		return base_text
	var delta: int = int(current_val) - int(prev_val)
	if delta > 0:
		return "%s (+%d)" % [base_text, delta * multiplier]
	return base_text


static func _get_default_effect_note(effect_type: CharacterData.EffectType) -> String:
	match effect_type:
		CharacterData.EffectType.KNOCKBACK:
			return &"Pushes struck enemies backward."
		CharacterData.EffectType.STUN:
			return &"Freezes struck enemies in place."
		CharacterData.EffectType.BURN:
			return &"Deals fire damage over time."
		CharacterData.EffectType.MARK:
			return &"Marked foes take bonus squad damage."
		CharacterData.EffectType.SLOW:
			return &"Reduces enemy movement speed."
	return &""


func display_skill(skill: Dictionary, target_level: int, prev_level: int = 0) -> void:
	setup_static(skill)
	update_stats(skill, target_level, prev_level)


func setup_static(skill: Dictionary) -> void:
	var info: Dictionary = CharacterData.eval_skill(skill, 1)
	var skill_name: String = info[&"name"]
	var skill_type: CharacterData.SkillType = info[&"type"]
	var has_chance: bool = info[&"has_chance"]
	var chance: float = info[&"chance"]
	if has_chance:
		var chance_pct: int = int(roundf(chance * 100.0))
		_header_label.text = "%s [%s, %d%%]" % [skill_name, SKILL_TYPE_NAMES[skill_type], chance_pct]
	else:
		_header_label.text = "%s [%s]" % [skill_name, SKILL_TYPE_NAMES[skill_type]]

	match skill_type:
		CharacterData.SkillType.HEAL:
			_amount_label.text = &"Heal:"
			_amount_value.add_theme_color_override(&"font_color", COLOR_HP)
		CharacterData.SkillType.SUMMON:
			_amount_label.text = &"Summons:"
			_amount_value.add_theme_color_override(&"font_color", COLOR_KB)
		_:
			_amount_label.text = &"Damage:"
			_amount_value.add_theme_color_override(&"font_color", COLOR_DMG)

	var effect_type: CharacterData.EffectType = info[&"effect_type"]
	_effect_pair.visible = effect_type != CharacterData.EffectType.NONE
	match effect_type:
		CharacterData.EffectType.KNOCKBACK:
			_effect_label.text = &"Knockback:"
			_effect_value.add_theme_color_override(&"font_color", COLOR_KB)
		CharacterData.EffectType.STUN:
			_effect_label.text = &"Stun:"
			_effect_value.add_theme_color_override(&"font_color", COLOR_KB)
		CharacterData.EffectType.BURN:
			_effect_label.text = &"Burn:"
			_effect_value.add_theme_color_override(&"font_color", COLOR_BURN)
		CharacterData.EffectType.MARK:
			_effect_label.text = &"Mark:"
			_effect_value.add_theme_color_override(&"font_color", COLOR_MARK)
		CharacterData.EffectType.SLOW:
			_effect_label.text = &"Slow:"
			_effect_value.add_theme_color_override(&"font_color", COLOR_SLOW)


func update_stats(skill: Dictionary, target_level: int, prev_level: int) -> void:
	var has_prev: bool = prev_level > 0
	var cur: Dictionary = CharacterData.eval_skill(skill, target_level)
	var prev: Dictionary = CharacterData.eval_skill(skill, prev_level) if has_prev else {}

	var cur_amount: float = cur[&"amount"]
	var prev_amount: float = prev[&"amount"] if has_prev else 0.0
	var hits: int = cur[&"hits"]
	var base_amount: String = "%dx%d" % [int(cur_amount), hits] if hits > 1 else "%d" % int(cur_amount)
	_amount_value.text = format_int_delta(base_amount, cur_amount, prev_amount, has_prev, hits)

	if _effect_pair.visible:
		_update_effect_value(cur, prev, has_prev)

	var cur_cd: float = cur[&"cooldown"]
	var cd_str: String = "%.1fs" % cur_cd
	if has_prev:
		var prev_cd: float = prev[&"cooldown"]
		var delta_cd: float = cur_cd - prev_cd
		if delta_cd < COOLDOWN_DELTA_EPSILON:
			cd_str = "%.1fs (%.1fs)" % [cur_cd, delta_cd]
	_cooldown_value.text = cd_str

	var cur_range: float = cur[&"range"]
	_range_value.text = "%d" % int(cur_range)

	var note: String = cur[&"description"]
	if note.is_empty():
		var effect_type: CharacterData.EffectType = cur[&"effect_type"]
		note = _get_default_effect_note(effect_type)
	_note_label.text = note
	_note_label.visible = not note.is_empty()


func _update_effect_value(cur: Dictionary, prev: Dictionary, has_prev: bool) -> void:
	var effect_type: CharacterData.EffectType = cur[&"effect_type"]
	var cur_amount: float = cur[&"effect_amount"]
	var prev_amount: float = prev[&"effect_amount"] if has_prev else 0.0
	var cur_dur: float = cur[&"effect_duration"]

	match effect_type:
		CharacterData.EffectType.KNOCKBACK:
			_effect_value.text = format_int_delta("%d" % int(cur_amount), cur_amount, prev_amount, has_prev)
		CharacterData.EffectType.STUN:
			_effect_value.text = "%.1fs" % cur_dur
		CharacterData.EffectType.BURN:
			var base_burn: String = "%d/s (%ds)" % [int(cur_amount), int(cur_dur)]
			_effect_value.text = format_int_delta(base_burn, cur_amount, prev_amount, has_prev)
		CharacterData.EffectType.MARK:
			var cur_pct: float = roundf(cur_amount * 100.0)
			var prev_pct: float = roundf(prev_amount * 100.0)
			var base_mark: String = "+%d%% (%ds)" % [int(cur_pct), int(cur_dur)]
			_effect_value.text = format_int_delta(base_mark, cur_pct, prev_pct, has_prev)
		CharacterData.EffectType.SLOW:
			var slow_pct: int = int(roundf((1.0 - cur_amount) * 100.0))
			_effect_value.text = "%d%% (%ds)" % [slow_pct, int(cur_dur)]
