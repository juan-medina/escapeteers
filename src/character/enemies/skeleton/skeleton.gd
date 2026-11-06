# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Skeleton
extends Enemy

const MELEE_VERTICAL_TOLERANCE: float = 12.0
const HEALER_WEIGHT: float = 0.10
const RANGED_WEIGHT: float = 0.25


func _ready() -> void:
	enemy_id = &"skeleton"
	super._ready()


func get_effective_target_dist_sq(hero_candidate: Hero) -> float:
	var dist_sq: float = global_position.distance_squared_to(hero_candidate.global_position)
	if hero_candidate.can_heal:
		return dist_sq * HEALER_WEIGHT
	if hero_candidate.can_ranged and not hero_candidate.can_melee:
		return dist_sq * RANGED_WEIGHT
	return dist_sq


func _setup_actions() -> void:
	if can_melee:
		var melee: MeleeAction = MeleeAction.new()
		melee.range_distance = melee_range
		melee.vertical_tolerance = MELEE_VERTICAL_TOLERANCE
		melee.damage = melee_damage
		melee.cooldown = attack_cooldown
		melee.can_heavy = can_heavy_melee
		melee.heavy_damage = melee2_damage
		melee.heavy_cooldown = melee2_cooldown
		melee.heavy_chance = melee2_chance
		melee.leash_distance = 0.0
		combat_actions.append(melee)
