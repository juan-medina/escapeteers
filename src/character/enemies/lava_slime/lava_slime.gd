# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name LavaSlime
extends Enemy

const LAVA_SPIKE_SCENE: PackedScene = preload("res://projectile/lava_spike/lava_spike.tscn")
const HORIZONTAL_ALIGNMENT_TOLERANCE: float = 16.0

@export var melee_damage: float = 8.0


func _ready() -> void:
	speed = 35.0
	detection_range = 135.0
	can_melee = true
	melee_range = 45.0
	can_ranged = true
	ranged_min_range = 65.0
	ranged_range = 135.0
	attack_cooldown = 1.5
	damage = 5.0
	super._ready()
	_setup_actions()


func _setup_actions() -> void:
	# 1. Close/mid range -> Melee attack
	if can_melee:
		var melee: MeleeAction = MeleeAction.new()
		melee.range_distance = melee_range
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
		combat_actions.append(ranged)
