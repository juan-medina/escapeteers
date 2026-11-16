# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name UnitCard
extends PanelContainer

signal chosen(hero: HeroData)

@export var hero_id: StringName = &""
@export var button_text: StringName = &"Recruit":
	set(value):
		button_text = value
		if _recruit_button != null:
			_recruit_button.text = button_text

var _hero_data: HeroData = null

@onready var _name_label: Label = $Margin/HBox/UnitColumn/VBox/NameRow/NameLabel
@onready var _level_label: Label = $Margin/HBox/UnitColumn/VBox/NameRow/LevelLabel
@onready var _preview_sprite: AnimatedSprite2D = $Margin/HBox/UnitColumn/PreviewContainer/PreviewSprite
@onready var _hp_value_label: Label = $Margin/HBox/UnitColumn/VBox/HPRow/HPValue
@onready var _count_value_label: Label = $Margin/HBox/UnitColumn/VBox/CountRow/CountValue
@onready var _skill1_column: SkillColumn = $Margin/HBox/Skill1Column
@onready var _skill2_column: SkillColumn = $Margin/HBox/Skill2Column
@onready var _sep2: VSeparator = $Margin/HBox/VSeparator2
@onready var _recruit_button: Button = $Margin/HBox/RecruitButton


func _ready() -> void:
	_recruit_button.text = button_text
	_hero_data = HeroData.get_hero(hero_id)
	_name_label.text = _hero_data.name
	_preview_sprite.sprite_frames = _hero_data.sprite_frames

	_skill1_column.setup_static(_hero_data.skills[0])

	var has_second_skill: bool = _hero_data.skills.size() > 1
	_sep2.visible = has_second_skill
	_skill2_column.visible = has_second_skill
	if has_second_skill:
		_skill2_column.setup_static(_hero_data.skills[1])

	_sync_sprite_playback()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_sync_sprite_playback()


func update_stats(target_level: int, count: int, prev_level: int = 0) -> void:
	var has_prev: bool = prev_level > 0
	_level_label.text = "Lv. %d -> %d" % [prev_level, target_level] if has_prev else "Lv. %d" % target_level

	var current_hp: float = _hero_data.get_health(target_level)
	var prev_hp: float = _hero_data.get_health(prev_level) if has_prev else 0.0
	_hp_value_label.text = SkillColumn.format_int_delta("%d" % int(current_hp), current_hp, prev_hp, has_prev)
	_count_value_label.text = "%d" % count

	_skill1_column.update_stats(_hero_data.skills[0], target_level, prev_level)
	if _skill2_column.visible:
		_skill2_column.update_stats(_hero_data.skills[1], target_level, prev_level)


func get_recruit_button() -> Button:
	return _recruit_button


func _sync_sprite_playback() -> void:
	if not is_node_ready():
		return
	if is_visible_in_tree():
		_preview_sprite.play(Character.ANIM_IDLE)
	else:
		_preview_sprite.pause()


func _on_recruit_pressed() -> void:
	chosen.emit(_hero_data)
