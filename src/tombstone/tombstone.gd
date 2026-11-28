# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Tombstone
extends Node2D

const BASE_LIGHT_ENERGY: float = 0.28
const PULSE_AMP: float = 0.05
const PULSE_SPEED: float = 1.8
const SPAWN_DELAY: float = 0.25
const FADE_IN_DURATION: float = 0.35

var _is_on_screen: bool = false
var _pulse_time: float = 0.0

@onready var _sprite: Sprite2D = $Sprite
@onready var _class_crest: Polygon2D = $ClassCrest
@onready var _class_label: Label = $ClassLabel
@onready var _memorial_light: PointLight2D = $MemorialLight
@onready var _notifier: VisibleOnScreenNotifier2D = $VisibleOnScreenNotifier2D


func _ready() -> void:
	_is_on_screen = _notifier.is_on_screen()
	_memorial_light.enabled = _is_on_screen
	set_process(_is_on_screen)


func _process(delta: float) -> void:
	_pulse_time += delta
	_memorial_light.energy = BASE_LIGHT_ENERGY + sin(_pulse_time * PULSE_SPEED) * PULSE_AMP


func setup(hero_data: HeroData) -> void:
	_class_crest.color = hero_data.color
	_class_label.text = hero_data.abbr
	var label_color: Color = hero_data.color.lerp(Color.WHITE, 0.30)
	label_color.a = 0.85
	_class_label.add_theme_color_override(&"font_color", label_color)
	_memorial_light.color = hero_data.color.lerp(Color(0.72, 0.84, 1.0, 1.0), 0.55)

	modulate.a = 0.0
	_sprite.position.y = 0.0
	var tween: Tween = create_tween()
	tween.tween_interval(SPAWN_DELAY)
	tween.tween_property(self, ^"modulate:a", 1.0, FADE_IN_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_sprite, ^"position:y", -3.0, FADE_IN_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_screen_entered() -> void:
	_is_on_screen = true
	_memorial_light.enabled = true
	set_process(true)


func _on_screen_exited() -> void:
	_is_on_screen = false
	_memorial_light.enabled = false
	set_process(false)
