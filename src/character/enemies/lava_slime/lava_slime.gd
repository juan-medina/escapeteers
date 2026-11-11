# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name LavaSlime
extends Enemy

const LAVA_SPIKE_SCENE: PackedScene = preload("res://projectile/lava_spike/lava_spike.tscn")
const HORIZONTAL_ALIGNMENT_TOLERANCE: float = 16.0
const MELEE_VERTICAL_TOLERANCE: float = 10.0


func _ready() -> void:
	enemy_id = &"lava_slime"
	super._ready()


func _setup_actions() -> void:
	# 1. Close/mid range -> Melee attack
	if can_melee:
		var melee: MeleeAction = MeleeAction.new()
		melee.range_distance = melee_range
		melee.vertical_tolerance = MELEE_VERTICAL_TOLERANCE
		melee.damage = melee_damage
		melee.cooldown = attack_cooldown
		melee.leash_distance = 0.0
		combat_actions.append(melee)

	# 2. Ranged Spike attack if in line-of-sight & aligned
	if can_ranged:
		var ranged: RangedAction = RangedAction.new()
		ranged.projectile_scene = LAVA_SPIKE_SCENE
		ranged.range_distance = ranged_range
		ranged.min_range_distance = ranged_min_range
		ranged.damage = damage
		ranged.cooldown = attack_cooldown
		ranged.requires_horizontal_alignment = true
		ranged.horizontal_tolerance = HORIZONTAL_ALIGNMENT_TOLERANCE
		ranged.check_line_of_sight = true
		ranged.leash_distance = 0.0
		ranged.show_telegraph = true
		ranged.telegraph_color = Color(1.0, 1.0, 1.0, 0.35)
		ranged.telegraph_locked_color = Color(1.0, 1.0, 1.0, 0.85)
		ranged.telegraph_lock_time = 0.25
		combat_actions.append(ranged)
