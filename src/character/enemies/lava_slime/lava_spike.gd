# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name LavaSpike
extends Projectile


func _ready() -> void:
	speed = 95.0
	damage = 6.0
	lifetime = 2.5
	auto_rotate = false
	super._ready()
