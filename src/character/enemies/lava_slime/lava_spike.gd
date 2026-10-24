# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name LavaSpike
extends Projectile

const SCENE: PackedScene = preload("res://character/enemies/lava_slime/lava_spike.tscn")


static func instantiate() -> LavaSpike:
	var spike: LavaSpike = SCENE.instantiate() as LavaSpike
	if spike == null:
		printerr(&"LavaSpike: Failed to instantiate LavaSpike scene!")
		return null
	return spike


func _ready() -> void:
	speed = 95.0
	damage = 6.0
	lifetime = 2.5
	auto_rotate = false
	super._ready()
