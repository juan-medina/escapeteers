# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name HeroSelectCard
extends Button

signal chosen(hero: HeroData)

var hero_data: HeroData = null:
	set(value):
		hero_data = value
		if is_node_ready():
			_update_display()

@onready var _preview_sprite: AnimatedSprite2D = $Margin/VBox/PreviewContainer/PreviewSprite
@onready var _name_label: Label = $Margin/VBox/NameLabel
@onready var _role_label: Label = $Margin/VBox/RoleLabel
@onready var _hp_value_label: Label = $Margin/VBox/HPRow/HPValue


func _ready() -> void:
	if hero_data != null:
		_update_display()


func _update_display() -> void:
	if hero_data == null:
		return

	_name_label.text = hero_data.name
	_name_label.add_theme_color_override(&"font_color", hero_data.color)

	_role_label.text = hero_data.role
	_role_label.add_theme_color_override(&"font_color", hero_data.role_color)

	_hp_value_label.text = "%d" % int(hero_data.get_health(1))

	_setup_preview_sprite()


func _setup_preview_sprite() -> void:
	var frames: SpriteFrames = hero_data.get_sprite_frames()
	if frames != null:
		_preview_sprite.sprite_frames = frames
		if frames.has_animation(Character.ANIM_IDLE):
			_preview_sprite.play(Character.ANIM_IDLE)


func _on_pressed() -> void:
	if hero_data != null:
		chosen.emit(hero_data)
