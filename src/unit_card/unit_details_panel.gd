# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name UnitDetailsPanel
extends PanelContainer

@onready var _name_label: Label = $Margin/VBox/HeaderRow/NameLabel
@onready var _role_label: Label = $Margin/VBox/HeaderRow/RoleLabel
@onready var _description_label: Label = $Margin/VBox/DescriptionLabel
@onready var _passive_row: HBoxContainer = $Margin/VBox/PassiveRow
@onready var _passive_name_label: Label = $Margin/VBox/PassiveRow/PassiveNameLabel
@onready var _passive_desc_label: Label = $Margin/VBox/PassiveRow/PassiveDescLabel
@onready var _h_separator: HSeparator = $Margin/VBox/HSeparator
@onready var _skill1_column: SkillColumn = $Margin/VBox/SkillsRow/Skill1Column
@onready var _v_separator: VSeparator = $Margin/VBox/SkillsRow/VSeparator
@onready var _skill2_column: SkillColumn = $Margin/VBox/SkillsRow/Skill2Column


func show_hero(hero_data: HeroData, target_level: int = 1, prev_level: int = 0) -> void:
	_name_label.text = hero_data.name
	_name_label.add_theme_color_override(&"font_color", hero_data.color)
	_role_label.text = "[%s]" % HeroSelectCard.ROLE_NAMES[hero_data.role]
	_role_label.add_theme_color_override(&"font_color", HeroSelectCard.ROLE_COLORS[hero_data.role])
	_role_label.visible = true
	_show_character_details(hero_data, target_level, prev_level)


func show_character(data: CharacterData, target_level: int = 1, prev_level: int = 0) -> void:
	_name_label.text = data.name
	_name_label.remove_theme_color_override(&"font_color")
	_role_label.visible = false
	_show_character_details(data, target_level, prev_level)


func _show_character_details(data: CharacterData, target_level: int, prev_level: int) -> void:
	_description_label.text = data.description
	_description_label.visible = not data.description.is_empty()

	var passives: Array[Dictionary] = data.get_passive_skills()
	if passives.is_empty():
		_passive_row.visible = false
	else:
		var passive_info: Dictionary = CharacterData.eval_skill(passives[0], target_level)
		var passive_name: String = passive_info[&"name"]
		var passive_desc: String = passive_info[&"description"]
		_passive_name_label.text = "Passive - %s:" % passive_name
		_passive_desc_label.text = passive_desc
		_passive_row.visible = true

	var active_skills: Array[Dictionary] = data.get_active_skills()
	var has_skill1: bool = active_skills.size() > 0
	_h_separator.visible = has_skill1
	_skill1_column.visible = has_skill1
	if has_skill1:
		_skill1_column.display_skill(active_skills[0], target_level, prev_level)

	var has_skill2: bool = active_skills.size() > 1
	_v_separator.visible = has_skill2
	_skill2_column.visible = has_skill2
	if has_skill2:
		_skill2_column.display_skill(active_skills[1], target_level, prev_level)
