# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Skeleton
extends Enemy

const MELEE_VERTICAL_TOLERANCE: float = 12.0
const HEALER_WEIGHT: float = 0.10
const RANGED_WEIGHT: float = 0.25

var melee_damage: float = 10.0
var can_heavy_melee: bool = false
var melee2_damage: float = 20.0
var melee2_cooldown: float = 3.5
var melee2_chance: float = 0.35


func _ready() -> void:
	var data: EnemyData = EnemyData.get_enemy(&"skeleton")
	if data != null:
		data.apply_to_enemy(self, level)
	super._ready()
	_setup_actions()


func set_level(new_level: int) -> void:
	super.set_level(new_level)
	var data: EnemyData = EnemyData.get_enemy(&"skeleton")
	if data != null:
		data.apply_to_enemy(self, level)
	if combat_actions.is_empty():
		_setup_actions()
	else:
		_refresh_actions()
	if _health_bar != null:
		_health_bar.update_health(health, max_health)


func get_effective_target_dist_sq(hero_candidate: Hero) -> float:
	var dist_sq: float = global_position.distance_squared_to(hero_candidate.global_position)
	if hero_candidate.can_heal:
		return dist_sq * HEALER_WEIGHT
	if hero_candidate.can_ranged and not hero_candidate.can_melee:
		return dist_sq * RANGED_WEIGHT
	return dist_sq


func _refresh_actions() -> void:
	for action: CombatAction in combat_actions:
		if action is MeleeAction:
			var melee: MeleeAction = action as MeleeAction
			melee.range_distance = melee_range
			melee.damage = melee_damage
			melee.cooldown = attack_cooldown
			melee.can_heavy = can_heavy_melee
			melee.heavy_damage = melee2_damage
			melee.heavy_cooldown = melee2_cooldown
			melee.heavy_chance = melee2_chance


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
