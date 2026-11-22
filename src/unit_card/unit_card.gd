# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name UnitCard
extends Button

signal chosen(hero: HeroData)
signal inspected(hero: HeroData, target_level: int, prev_level: int)

@export var hero_id: StringName = &""

var _hero_data: HeroData = null
var _target_level: int = 1
var _prev_level: int = 0

@onready var _preview_sprite: AnimatedSprite2D = $Margin/VBox/PreviewContainer/PreviewSprite
@onready var _name_label: Label = $Margin/VBox/NameLabel
@onready var _level_label: Label = $Margin/VBox/LevelLabel
@onready var _hp_value_label: Label = $Margin/VBox/HPRow/HPValue
@onready var _count_value_label: Label = $Margin/VBox/CountRow/CountValue


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_sync_sprite_playback()


func initialize() -> void:
	_hero_data = HeroData.get_hero(hero_id)
	_name_label.text = _hero_data.name
	_name_label.add_theme_color_override(&"font_color", _hero_data.color)
	_preview_sprite.sprite_frames = _hero_data.sprite_frames
	_sync_sprite_playback()


func update_stats(target_level: int, count: int, prev_level: int = 0) -> void:
	_target_level = target_level
	_prev_level = prev_level

	var has_prev: bool = prev_level > 0
	_level_label.text = "Lv. %d -> %d" % [prev_level, target_level] if has_prev else "Lv. %d" % target_level

	var current_hp: float = _hero_data.get_health(target_level)
	var prev_hp: float = _hero_data.get_health(prev_level) if has_prev else 0.0
	_hp_value_label.text = SkillColumn.format_int_delta("%d" % int(current_hp), current_hp, prev_hp, has_prev)
	_count_value_label.text = "%d" % count


func emit_inspected() -> void:
	if _hero_data != null:
		inspected.emit(_hero_data, _target_level, _prev_level)


func _sync_sprite_playback() -> void:
	if _hero_data == null:
		return
	if is_visible_in_tree():
		_preview_sprite.play(Character.ANIM_IDLE)
	else:
		_preview_sprite.pause()


func _on_pressed() -> void:
	chosen.emit(_hero_data)


func _on_focus_entered() -> void:
	emit_inspected()


func _on_mouse_entered() -> void:
	emit_inspected()
