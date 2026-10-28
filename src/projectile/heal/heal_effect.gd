# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name HealEffect
extends Projectile

const ANIM_DEFAULT: StringName = &"default"


func _ready() -> void:
	speed = 0.0
	auto_rotate = false
	disable_collisions()
	_animated_sprite.animation_finished.connect(_on_effect_finished)
	_animated_sprite.play(ANIM_DEFAULT)


func _physics_process(_delta: float) -> void:
	pass


func _on_effect_finished() -> void:
	_destroy()
