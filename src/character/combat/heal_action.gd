# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name HealAction
extends CombatAction

var heal_amount: float = 15.0
var cast_frame: int = 3
var heal_effect_scene: PackedScene = preload("res://projectile/heal/heal_effect.tscn")


func can_reach(user: Character, target: Character) -> bool:
	return super.can_reach(user, target) and target.health < target.max_health


func execute(user: Character, target: Character) -> void:
	super.execute(user, target)
	user.play(Character.ANIM_HEAL)


func apply_heal(_user: Character, target: Character) -> void:
	if is_valid_target(target):
		target.heal(heal_amount)


func spawn_heal_effect(_user: Character, target: Character) -> Projectile:
	if not is_valid_target(target):
		return null

	var effect: Projectile = Projectile.acquire(heal_effect_scene)
	effect.global_position = target.global_position
	return effect
