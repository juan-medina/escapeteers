# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name LavaSlime
extends Enemy

const LAVA_SPIKE_SCENE: PackedScene = preload("res://projectile/lava_spike/lava_spike.tscn")
const HORIZONTAL_ALIGNMENT_TOLERANCE: float = 16.0
const MELEE_VERTICAL_TOLERANCE: float = 10.0

var melee_damage: float = 8.0


func _ready() -> void:
	var data: EnemyData = EnemyData.get_enemy(&"lava_slime")
	if data != null:
		data.apply_to_enemy(self, level)
	super._ready()
	_setup_actions()


func set_level(new_level: int) -> void:
	super.set_level(new_level)
	var data: EnemyData = EnemyData.get_enemy(&"lava_slime")
	if data != null:
		data.apply_to_enemy(self, level)
	if combat_actions.is_empty():
		_setup_actions()
	else:
		_refresh_actions()
	if _health_bar != null:
		_health_bar.update_health(health, max_health)


func _refresh_actions() -> void:
	for action: CombatAction in combat_actions:
		if action is MeleeAction:
			var melee: MeleeAction = action as MeleeAction
			melee.range_distance = melee_range
			melee.damage = melee_damage
			melee.cooldown = attack_cooldown
		elif action is RangedAction:
			var ranged: RangedAction = action as RangedAction
			ranged.range_distance = ranged_range
			ranged.min_range_distance = ranged_min_range
			ranged.damage = damage
			ranged.cooldown = attack_cooldown


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
		combat_actions.append(ranged)
