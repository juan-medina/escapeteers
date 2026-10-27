# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name RangedAction
extends CombatAction

var projectile_scene: PackedScene = null
var projectile_frame: int = 0
var knockback: float = 0.0
var requires_horizontal_alignment: bool = false
var horizontal_tolerance: float = 16.0
var check_line_of_sight: bool = false


func can_execute(user: Character, target: Character) -> bool:
	if not super.can_execute(user, target):
		return false

	if requires_horizontal_alignment:
		var y_diff: float = absf(target.global_position.y - user.global_position.y)
		if y_diff > horizontal_tolerance:
			return false

	if check_line_of_sight:
		if not SquadNavigator.has_line_of_sight(user, target.global_position):
			return false

	return true


func execute(user: Character, target: Character) -> void:
	super.execute(user, target)
	user.play(Character.ANIM_ATTACK_RANGED1)

	var dir_x: float = -1.0 if target.global_position.x < user.global_position.x else 1.0
	user.flip_h = dir_x < 0.0


func spawn_projectile(user: Character, target: Character) -> Projectile:
	if projectile_scene == null or target == null or not is_instance_valid(target):
		return null

	var dir_x: float = -1.0 if target.global_position.x < user.global_position.x else 1.0
	var projectile: Projectile = projectile_scene.instantiate() as Projectile
	if projectile != null:
		var spawn_pos: Vector2 = user.global_position + Vector2(dir_x * 8.0, 0.0)
		var fire_dir: Vector2 = Vector2(dir_x, 0.0)
		if not requires_horizontal_alignment:
			var diff: Vector2 = target.global_position - spawn_pos
			if diff.length_squared() > 0.001:
				fire_dir = diff.normalized()
		projectile.global_position = spawn_pos
		projectile.direction = fire_dir
		projectile.damage = damage
		projectile.knockback = knockback
	return projectile
