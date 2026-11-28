# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name CodexDetailsPanel
extends PanelContainer

const LOCKED_TITLE_COLOR: Color = Color(0.55, 0.58, 0.65, 1.0)
const DEFAULT_LOCKED_HINT: StringName = &"Undiscovered entry. Keep exploring the dungeon."

@onready var _name_label: Label = $Margin/VBox/HeaderRow/NameLabel
@onready var _tag_label: Label = $Margin/VBox/HeaderRow/TagLabel
@onready var _overview_label: Label = $Margin/VBox/OverviewLabel
@onready var _behavior_row: HBoxContainer = $Margin/VBox/BehaviorRow
@onready var _behavior_name_label: Label = $Margin/VBox/BehaviorRow/BehaviorNameLabel
@onready var _behavior_desc_label: Label = $Margin/VBox/BehaviorRow/BehaviorDescLabel
@onready var _h_separator: HSeparator = $Margin/VBox/HSeparator
@onready var _skill1_box: VBoxContainer = $Margin/VBox/SkillsVBox/Skill1
@onready var _skill1_title: Label = $Margin/VBox/SkillsVBox/Skill1/TitleLabel
@onready var _skill1_desc: Label = $Margin/VBox/SkillsVBox/Skill1/DescLabel
@onready var _skill2_box: VBoxContainer = $Margin/VBox/SkillsVBox/Skill2
@onready var _skill2_title: Label = $Margin/VBox/SkillsVBox/Skill2/TitleLabel
@onready var _skill2_desc: Label = $Margin/VBox/SkillsVBox/Skill2/DescLabel


func show_hero(hero_data: HeroData) -> void:
	_name_label.text = hero_data.name
	_name_label.add_theme_color_override(&"font_color", hero_data.color)
	_tag_label.text = "[%s]" % HeroSelectCard.ROLE_NAMES[hero_data.role]
	_tag_label.add_theme_color_override(&"font_color", HeroSelectCard.ROLE_COLORS[hero_data.role])
	_tag_label.visible = true

	var overview: String = hero_data.codex if not hero_data.codex.is_empty() else hero_data.description
	_overview_label.text = overview
	_overview_label.visible = not overview.is_empty()

	var passives: Array[Dictionary] = hero_data.get_passive_skills()
	if passives.is_empty():
		_behavior_row.visible = false
	else:
		var passive: Dictionary = passives[0]
		var p_name: String = CharacterData._str_val(passive, &"name")
		var p_desc: String = CharacterData._str_val(passive, &"description")
		_behavior_name_label.text = "Passive - %s:" % p_name
		_behavior_desc_label.text = p_desc
		_behavior_row.visible = true

	_show_active_skills(hero_data.get_active_skills())


func show_enemy(enemy_data: EnemyData) -> void:
	_name_label.text = enemy_data.name
	_name_label.add_theme_color_override(&"font_color", enemy_data.color)
	_tag_label.text = "[%s]" % enemy_data.role
	_tag_label.add_theme_color_override(&"font_color", enemy_data.color)
	_tag_label.visible = not enemy_data.role.is_empty()

	_overview_label.text = enemy_data.description
	_overview_label.visible = not enemy_data.description.is_empty()

	if enemy_data.behavior.is_empty():
		_behavior_row.visible = false
	else:
		_behavior_name_label.text = &"Behavior:"
		_behavior_desc_label.text = enemy_data.behavior
		_behavior_row.visible = true

	_show_active_skills(enemy_data.get_active_skills())


func show_item(item: Dictionary) -> void:
	var item_color: Color = Color.from_string(CharacterData._str_val(item, &"color"), Color.WHITE)
	var tag: String = CharacterData._str_val(item, &"tag")
	_name_label.text = CharacterData._str_val(item, &"name")
	_name_label.add_theme_color_override(&"font_color", item_color)
	_tag_label.text = "[%s]" % tag
	_tag_label.add_theme_color_override(&"font_color", item_color)
	_tag_label.visible = not tag.is_empty()

	var desc: String = CharacterData._str_val(item, &"description")
	_overview_label.text = desc
	_overview_label.visible = not desc.is_empty()

	var where_found: String = CharacterData._str_val(item, &"where_found")
	if where_found.is_empty():
		_behavior_row.visible = false
	else:
		_behavior_name_label.text = &"Found In:"
		_behavior_desc_label.text = where_found
		_behavior_row.visible = true

	var effect_title: String = CharacterData._str_val(item, &"effect_title")
	var effect_desc: String = CharacterData._str_val(item, &"effect_desc")
	_h_separator.visible = not effect_title.is_empty()
	if effect_title.is_empty():
		_skill1_box.visible = false
	else:
		_skill1_title.text = "%s:" % effect_title
		_skill1_desc.text = effect_desc
		_skill1_desc.visible = not effect_desc.is_empty()
		_skill1_box.visible = true
	_skill2_box.visible = false


func show_event(event_data: Dictionary) -> void:
	var event_color: Color = Color.from_string(CharacterData._str_val(event_data, &"color"), Color.WHITE)
	var tag: String = CharacterData._str_val(event_data, &"tag")
	_name_label.text = CharacterData._str_val(event_data, &"name")
	_name_label.add_theme_color_override(&"font_color", event_color)
	_tag_label.text = "[%s]" % tag
	_tag_label.add_theme_color_override(&"font_color", event_color)
	_tag_label.visible = not tag.is_empty()

	var desc: String = CharacterData._str_val(event_data, &"description")
	_overview_label.text = desc
	_overview_label.visible = not desc.is_empty()

	var trigger: String = CharacterData._str_val(event_data, &"trigger")
	if trigger.is_empty():
		_behavior_row.visible = false
	else:
		_behavior_name_label.text = &"Trigger:"
		_behavior_desc_label.text = trigger
		_behavior_row.visible = true

	var hazard_title: String = CharacterData._str_val(event_data, &"hazard_title")
	var hazard_desc: String = CharacterData._str_val(event_data, &"hazard_desc")
	var reward_title: String = CharacterData._str_val(event_data, &"reward_title")
	var reward_desc: String = CharacterData._str_val(event_data, &"reward_desc")
	_h_separator.visible = not hazard_title.is_empty() or not reward_title.is_empty()
	_set_event_section(_skill1_box, _skill1_title, _skill1_desc, hazard_title, hazard_desc)
	_set_event_section(_skill2_box, _skill2_title, _skill2_desc, reward_title, reward_desc)


func show_locked(hint: String) -> void:
	_name_label.text = &"???"
	_name_label.add_theme_color_override(&"font_color", LOCKED_TITLE_COLOR)
	_tag_label.visible = false
	_overview_label.text = hint if not hint.is_empty() else String(DEFAULT_LOCKED_HINT)
	_overview_label.visible = true
	_behavior_row.visible = false
	_h_separator.visible = false
	_skill1_box.visible = false
	_skill2_box.visible = false


func _show_active_skills(active_skills: Array[Dictionary]) -> void:
	var has_skills: bool = not active_skills.is_empty()
	_h_separator.visible = has_skills
	_set_skill_slot(_skill1_box, _skill1_title, _skill1_desc, active_skills[0] if active_skills.size() > 0 else {})
	_set_skill_slot(_skill2_box, _skill2_title, _skill2_desc, active_skills[1] if active_skills.size() > 1 else {})


func _set_skill_slot(box: VBoxContainer, title_label: Label, desc_label: Label, skill: Dictionary) -> void:
	if skill.is_empty():
		box.visible = false
		return

	var skill_name: String = CharacterData._str_val(skill, &"name")
	var skill_type: CharacterData.SkillType = skill[&"type"]
	var type_name: String = SkillColumn.SKILL_TYPE_NAMES[skill_type]
	if skill.has(&"chance"):
		title_label.text = "%s [%s, Chance]:" % [skill_name, type_name]
	else:
		title_label.text = "%s [%s]:" % [skill_name, type_name]

	var skill_desc: String = CharacterData._str_val(skill, &"description")
	desc_label.text = skill_desc
	desc_label.visible = not skill_desc.is_empty()
	box.visible = true


func _set_event_section(box: VBoxContainer, title_label: Label, desc_label: Label, section_title: String, section_desc: String) -> void:
	if section_title.is_empty():
		box.visible = false
		return
	title_label.text = "%s:" % section_title
	desc_label.text = section_desc
	desc_label.visible = not section_desc.is_empty()
	box.visible = true
