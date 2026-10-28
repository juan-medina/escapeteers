# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name HealAction
extends CombatAction

var heal_amount: float = 15.0
var cast_frame: int = 3
var heal_effect_scene: PackedScene = preload("res://projectile/heal/heal_effect.tscn")
var check_line_of_sight: bool = false


func can_execute(user: Character, target: Character) -> bool:
	if not is_ready():
		return false
	if target == null or not is_instance_valid(target) or target.is_dead or target.health <= 0.0:
		return false
	if target.health >= target.max_health:
		return false

	var dist: float = user.global_position.distance_to(target.global_position)
	if dist < min_range_distance or dist > range_distance:
		return false

	if check_line_of_sight:
		if not SquadNavigator.has_line_of_sight(user, target.global_position):
			return false

	return true


func execute(user: Character, target: Character) -> void:
	super.execute(user, target)
	user.play(Character.ANIM_HEAL)

	var diff_x: float = target.global_position.x - user.global_position.x
	if absf(diff_x) > 1.0:
		user.flip_h = diff_x < 0.0


func apply_heal(_user: Character, target: Character) -> void:
	if target == null or not is_instance_valid(target) or target.is_dead or target.health <= 0.0:
		return
	target.heal(heal_amount)


func spawn_heal_effect(_user: Character, target: Character) -> Projectile:
	if heal_effect_scene == null or target == null or not is_instance_valid(target):
		return null

	var effect: Projectile = heal_effect_scene.instantiate() as Projectile
	if effect != null:
		effect.global_position = target.global_position
	return effect
