# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name LavaSlime
extends Enemy

const LAVA_SPIKE_SCENE: PackedScene = preload("res://projectile/lava_spike/lava_spike.tscn")
const HORIZONTAL_ALIGNMENT_TOLERANCE: float = 16.0
const MELEE_VERTICAL_TOLERANCE: float = 10.0


func _ready() -> void:
	enemy_id = &"lava_slime"
	melee_vertical_tolerance = MELEE_VERTICAL_TOLERANCE
	ranged_projectile_scene = LAVA_SPIKE_SCENE
	requires_horizontal_alignment = true
	horizontal_alignment_tolerance = HORIZONTAL_ALIGNMENT_TOLERANCE
	super._ready()
