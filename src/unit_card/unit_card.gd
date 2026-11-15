# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name UnitCard
extends PanelContainer

signal chosen(hero: HeroData)

const COLOR_LABEL: Color = Color(0.65, 0.70, 0.78)
const COLOR_HP: Color = Color(0.40, 0.95, 0.45)
const COLOR_DMG: Color = Color(1.0, 0.50, 0.35)
const COLOR_BURN: Color = Color(1.0, 0.65, 0.20)
const COLOR_RNG: Color = Color(0.45, 0.80, 1.0)
const COLOR_KB: Color = Color(0.90, 0.60, 1.0)
const COLOR_CD: Color = Color(1.0, 0.90, 0.50)
const COLOR_SKILL_NAME: Color = Color(1.0, 0.85, 0.40)

const SKILL_TYPE_NAMES: Dictionary[CharacterData.SkillType, String] = {
	CharacterData.SkillType.MELEE: "Melee",
	CharacterData.SkillType.RANGED: "Ranged",
	CharacterData.SkillType.HEAL: "Heal",
	CharacterData.SkillType.SUMMON: "Summon",
}

@export var button_text: StringName = &"Recruit":
	set(value):
		button_text = value
		if _recruit_button != null:
			_recruit_button.text = button_text

var hero_data: HeroData = null
var level: int = 1
var previous_level: int = 0
var unit_count: int = 0

@onready var _name_label: Label = $Margin/HBox/UnitColumn/VBox/NameRow/NameLabel
@onready var _level_label: Label = $Margin/HBox/UnitColumn/VBox/NameRow/LevelLabel
@onready var _preview_sprite: AnimatedSprite2D = $Margin/HBox/UnitColumn/PreviewContainer/PreviewSprite
@onready var _hp_value_label: Label = $Margin/HBox/UnitColumn/VBox/HPRow/HPValue
@onready var _count_value_label: Label = $Margin/HBox/UnitColumn/VBox/CountRow/CountValue
@onready var _skill1_container: VBoxContainer = $Margin/HBox/Skill1Column
@onready var _skill2_container: VBoxContainer = $Margin/HBox/Skill2Column
@onready var _sep2: VSeparator = $Margin/HBox/VSeparator2
@onready var _recruit_button: Button = $Margin/HBox/RecruitButton


func _ready() -> void:
	_recruit_button.text = button_text

	if hero_data != null:
		_update_display()


func setup(data: HeroData, target_level: int, count: int, prev_level: int = 0) -> void:
	hero_data = data
	level = target_level
	unit_count = count
	previous_level = prev_level
	_update_display()


func get_recruit_button() -> Button:
	return _recruit_button


func _update_display() -> void:
	if hero_data == null:
		return

	_name_label.text = hero_data.name
	if previous_level > 0:
		_level_label.text = "Lv. %d -> %d" % [previous_level, level]
	else:
		_level_label.text = "Lv. %d" % level

	var current_hp: float = hero_data.get_health(level)
	if previous_level > 0:
		var prev_hp: float = hero_data.get_health(previous_level)
		var delta_hp: int = int(current_hp) - int(prev_hp)
		if delta_hp > 0:
			_hp_value_label.text = "%d (+%d)" % [int(current_hp), delta_hp]
		else:
			_hp_value_label.text = "%d" % int(current_hp)
	else:
		_hp_value_label.text = "%d" % int(current_hp)

	if _count_value_label != null:
		_count_value_label.text = "%d" % unit_count

	_setup_preview_sprite()

	var skill_count: int = hero_data.skills.size()
	if skill_count > 0:
		_skill1_container.visible = true
		_render_skill_column(_skill1_container, hero_data.skills[0])
	else:
		_skill1_container.visible = false

	if skill_count > 1:
		_sep2.visible = true
		_skill2_container.visible = true
		_render_skill_column(_skill2_container, hero_data.skills[1])
	else:
		_sep2.visible = false
		_skill2_container.visible = false


func _render_skill_column(container: VBoxContainer, skill: Dictionary) -> void:
	for child: Node in container.get_children():
		child.queue_free()

	var skill_name: String = CharacterData._str_val(skill, &"name")
	var skill_type: CharacterData.SkillType = skill[&"type"]

	var header: Label = Label.new()
	header.text = "%s [%s]" % [skill_name, SKILL_TYPE_NAMES[skill_type]]
	header.add_theme_color_override(&"font_color", COLOR_SKILL_NAME)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(header)

	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 2)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var amount_val: float = CharacterData.eval_stat(skill.get(&"amount"), level, 10.0)
	var hits: int = int(CharacterData._float_val(skill, &"hits", 1.0))
	var amount_str: String = "%dx%d" % [int(amount_val), hits] if hits > 1 else "%d" % int(amount_val)
	if previous_level > 0:
		var prev_amount: float = CharacterData.eval_stat(skill.get(&"amount"), previous_level, 10.0)
		var d_amount: int = int(amount_val) - int(prev_amount)
		if d_amount > 0:
			amount_str = "%s (+%d)" % [amount_str, d_amount * hits]

	var cd: float = CharacterData.eval_stat(skill.get(&"cooldown"), level, 1.0)
	var cd_str: String = "%.1fs" % cd
	if previous_level > 0:
		var prev_cd: float = CharacterData.eval_stat(skill.get(&"cooldown"), previous_level, 1.0)
		var d_cd: float = cd - prev_cd
		if d_cd < -0.01:
			cd_str = "%.1fs (%.1fs)" % [cd, d_cd]

	var rng: float = CharacterData.eval_stat(skill.get(&"range"), level, 20.0)
	var amount_label: String = "HEAL" if skill_type == CharacterData.SkillType.HEAL else "DMG"
	var amount_color: Color = COLOR_HP if skill_type == CharacterData.SkillType.HEAL else COLOR_DMG
	_add_stat_pair(grid, amount_label, amount_str, amount_color)
	_render_skill_effect(grid, CharacterData._dict_val(skill, &"effect"))
	_add_stat_pair(grid, "CD", cd_str, COLOR_CD)
	_add_stat_pair(grid, "RNG", "%d" % int(rng), COLOR_RNG)

	container.add_child(grid)


func _render_skill_effect(grid: GridContainer, effect: Dictionary) -> void:
	if effect.is_empty():
		return
	var effect_type: CharacterData.EffectType = effect[&"type"]
	var eff_amount: float = CharacterData.eval_stat(effect.get(&"amount"), level, 0.0)
	var eff_dur: float = CharacterData.eval_stat(effect.get(&"duration"), level, 0.0)
	match effect_type:
		CharacterData.EffectType.KNOCKBACK:
			var kb_str: String = "%d" % int(eff_amount)
			if previous_level > 0:
				var prev_kb: float = CharacterData.eval_stat(effect.get(&"amount"), previous_level, 0.0)
				var d_kb: int = int(eff_amount) - int(prev_kb)
				if d_kb > 0:
					kb_str = "%d (+%d)" % [int(eff_amount), d_kb]
			_add_stat_pair(grid, "KB", kb_str, COLOR_KB)
		CharacterData.EffectType.STUN:
			_add_stat_pair(grid, "STUN", "%.1fs" % eff_dur, COLOR_KB)
		CharacterData.EffectType.BURN:
			var burn_str: String = "%d/s (%ds)" % [int(eff_amount), int(eff_dur)]
			if previous_level > 0:
				var prev_burn: float = CharacterData.eval_stat(effect.get(&"amount"), previous_level, 0.0)
				var d_burn: int = int(eff_amount) - int(prev_burn)
				if d_burn > 0:
					burn_str = "%d/s (+%d)" % [int(eff_amount), d_burn]
			_add_stat_pair(grid, "BURN", burn_str, COLOR_BURN)


func _add_stat_pair(container: Control, label_text: String, value_text: String, value_color: Color) -> void:
	var pair: HBoxContainer = HBoxContainer.new()
	pair.add_theme_constant_override(&"separation", 2)
	pair.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var lbl: Label = Label.new()
	lbl.text = label_text + ":"
	lbl.add_theme_color_override(&"font_color", COLOR_LABEL)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pair.add_child(lbl)

	var val: Label = Label.new()
	val.text = value_text
	val.add_theme_color_override(&"font_color", value_color)
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pair.add_child(val)

	container.add_child(pair)


func _setup_preview_sprite() -> void:
	if hero_data == null or _preview_sprite == null:
		return
	var frames: SpriteFrames = hero_data.sprite_frames
	if frames != null:
		_preview_sprite.sprite_frames = frames
		if frames.has_animation(Character.ANIM_IDLE):
			_preview_sprite.play(Character.ANIM_IDLE)


func _on_recruit_pressed() -> void:
	if hero_data != null:
		chosen.emit(hero_data)
