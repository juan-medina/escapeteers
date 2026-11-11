# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name SkeletonArcher
extends Enemy

const BONE_ARROW_SCENE: PackedScene = preload("res://projectile/bone_arrow/bone_arrow.tscn")
const KITE_DISTANCE: float = 65.0


func _ready() -> void:
	enemy_id = &"skeleton_archer"
	kite_distance = KITE_DISTANCE
	super._ready()


func _setup_actions() -> void:
	if can_ranged:
		var ranged: RangedAction = RangedAction.new()
		ranged.projectile_scene = BONE_ARROW_SCENE
		ranged.range_distance = ranged_range
		ranged.min_range_distance = ranged_min_range
		ranged.damage = damage
		ranged.cooldown = attack_cooldown
		ranged.requires_horizontal_alignment = false
		ranged.check_line_of_sight = true
		ranged.leash_distance = 0.0
		ranged.show_telegraph = true
		ranged.telegraph_color = Color(1.0, 1.0, 1.0, 0.35)
		ranged.telegraph_locked_color = Color(1.0, 1.0, 1.0, 0.85)
		ranged.telegraph_lock_time = 0.25
		combat_actions.append(ranged)
