# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Arrow
extends Projectile


func _ready() -> void:
	speed = 220.0
	damage = 10.0
	lifetime = 4.0
	auto_rotate = true
	super._ready()
