# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name HeroSelectCard
extends Button

signal chosen(hero: HeroData)

var _hero_data: HeroData = null

@onready var _preview_sprite: AnimatedSprite2D = $Margin/VBox/PreviewContainer/PreviewSprite
@onready var _name_label: Label = $Margin/VBox/NameLabel
@onready var _role_label: Label = $Margin/VBox/RoleLabel
@onready var _hp_value_label: Label = $Margin/VBox/HPRow/HPValue


func setup(data: HeroData) -> void:
	_hero_data = data
	_name_label.text = _hero_data.name
	_name_label.add_theme_color_override(&"font_color", _hero_data.color)

	_role_label.text = _hero_data.role
	_role_label.add_theme_color_override(&"font_color", _hero_data.role_color)

	_hp_value_label.text = &"%d" % int(_hero_data.get_health(1))

	_preview_sprite.sprite_frames = _hero_data.get_sprite_frames()
	_preview_sprite.play(Character.ANIM_IDLE)


func _on_pressed() -> void:
	chosen.emit(_hero_data)
