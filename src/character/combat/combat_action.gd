# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name CombatAction
extends RefCounted

var cooldown: float = 0.5
var cooldown_timer: float = 0.0
var damage: float = 10.0
var range_distance: float = 28.0
var min_range_distance: float = 0.0
var leash_distance: float = 96.0
var check_line_of_sight: bool = false


static func is_valid_target(target: Character) -> bool:
	return target != null and not target.is_dead and target.health > 0.0


static func face_target(user: Character, target: Character, threshold: float = 1.0) -> void:
	var diff_x: float = target.global_position.x - user.global_position.x
	if absf(diff_x) > threshold:
		user.flip_h = diff_x < 0.0


func update(delta: float) -> void:
	if cooldown_timer > 0.0:
		cooldown_timer -= delta


func is_ready() -> bool:
	return cooldown_timer <= 0.0


func can_reach(user: Character, target: Character) -> bool:
	if not is_valid_target(target):
		return false

	var dist_sq: float = user.global_position.distance_squared_to(target.global_position)
	if dist_sq < min_range_distance * min_range_distance or dist_sq > range_distance * range_distance:
		return false

	if check_line_of_sight and not SquadNavigator.has_line_of_sight(user, target.global_position):
		return false

	return true


func can_execute(user: Character, target: Character) -> bool:
	return is_ready() and can_reach(user, target)


func execute(user: Character, target: Character) -> void:
	cooldown_timer = cooldown
	face_target(user, target)
