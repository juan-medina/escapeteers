# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name HeroSelectCard
extends Button

signal chosen(hero: HeroData)

const ROLE_NAMES: Dictionary[HeroData.Role, String] = {
	HeroData.Role.MELEE: "Melee",
	HeroData.Role.RANGED: "Ranged",
	HeroData.Role.HEALER: "Healer",
	HeroData.Role.HYBRID: "Hybrid",
}
const ROLE_COLORS: Dictionary[HeroData.Role, Color] = {
	HeroData.Role.MELEE: Color(1.0, 0.45, 0.35),
	HeroData.Role.RANGED: Color(0.40, 0.80, 1.0),
	HeroData.Role.HEALER: Color(0.40, 0.95, 0.55),
	HeroData.Role.HYBRID: Color(1.0, 0.80, 0.30),
}

@export var hero_id: StringName = &""

var _hero_data: HeroData = null

@onready var _preview_sprite: AnimatedSprite2D = $Margin/VBox/PreviewContainer/PreviewSprite
@onready var _name_label: Label = $Margin/VBox/NameLabel
@onready var _role_label: Label = $Margin/VBox/RoleLabel
@onready var _hp_value_label: Label = $Margin/VBox/HPRow/HPValue


func initialize() -> void:
	_hero_data = HeroData.get_hero(hero_id)
	_name_label.text = _hero_data.name
	_name_label.add_theme_color_override(&"font_color", _hero_data.color)

	_role_label.text = ROLE_NAMES[_hero_data.role]
	_role_label.add_theme_color_override(&"font_color", ROLE_COLORS[_hero_data.role])

	_hp_value_label.text = &"%d" % int(_hero_data.get_health(1))

	_preview_sprite.sprite_frames = _hero_data.sprite_frames
	_sync_sprite_playback()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_sync_sprite_playback()


func _sync_sprite_playback() -> void:
	if _hero_data == null:
		return
	if is_visible_in_tree():
		_preview_sprite.play(Character.ANIM_IDLE)
	else:
		_preview_sprite.pause()


func _on_pressed() -> void:
	chosen.emit(_hero_data)
