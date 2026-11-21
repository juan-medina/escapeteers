# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Skeleton
extends Enemy

const HEALER_WEIGHT: float = 0.10
const RANGED_WEIGHT: float = 0.25


func _ready() -> void:
	enemy_id = &"skeleton"
	super._ready()


func get_effective_target_dist_sq(hero_candidate: Hero) -> float:
	if hero_candidate.hero_data != null and hero_candidate.hero_data.id == &"knight":
		return super.get_effective_target_dist_sq(hero_candidate)
	var dist_sq: float = global_position.distance_squared_to(hero_candidate.global_position)
	match hero_candidate.hero_data.role:
		HeroData.Role.HEALER:
			return dist_sq * HEALER_WEIGHT
		HeroData.Role.RANGED:
			return dist_sq * RANGED_WEIGHT
		_:
			return dist_sq
