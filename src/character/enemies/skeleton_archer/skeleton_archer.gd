# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name SkeletonArcher
extends Enemy

const BONE_ARROW_SCENE: PackedScene = preload("res://projectile/bone_arrow/bone_arrow.tscn")
const KITE_DISTANCE: float = 65.0


func _ready() -> void:
	enemy_id = &"skeleton_archer"
	kite_distance = KITE_DISTANCE
	ranged_projectile_scene = BONE_ARROW_SCENE
	super._ready()
