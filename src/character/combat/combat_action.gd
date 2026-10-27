# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name CombatAction
extends RefCounted

var cooldown: float = 0.5
var cooldown_timer: float = 0.0
var damage: float = 10.0
var range_distance: float = 28.0
var min_range_distance: float = 0.0
var leash_distance: float = 48.0


func update(delta: float) -> void:
	if cooldown_timer > 0.0:
		cooldown_timer -= delta


func is_ready() -> bool:
	return cooldown_timer <= 0.0


func can_execute(user: Character, target: Character) -> bool:
	if not is_ready():
		return false
	if target == null or not is_instance_valid(target) or target.health <= 0.0:
		return false

	var dist: float = user.global_position.distance_to(target.global_position)
	return dist >= min_range_distance and dist <= range_distance


func execute(_user: Character, _target: Character) -> void:
	cooldown_timer = cooldown
