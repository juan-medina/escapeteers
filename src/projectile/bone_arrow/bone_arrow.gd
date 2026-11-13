# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name BoneArrow
extends Projectile


func _init() -> void:
	damage = 5.0


func _ready() -> void:
	speed = 175.0
	lifetime = 3.5
	auto_rotate = true
	super._ready()
