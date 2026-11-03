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
var animation_name: StringName = Character.ANIM_ATTACK_RANGED1
var stun_duration: float = 0.0
var spawn_at_target: bool = false


func can_reach(user: Character, target: Character) -> bool:
	if not super.can_reach(user, target):
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
	user.play(animation_name)

	var dir_x: float = -1.0 if target.global_position.x < user.global_position.x else 1.0
	user.flip_h = dir_x < 0.0


func spawn_projectile(user: Character, target: Character) -> Projectile:
	if projectile_scene == null or target == null or not is_instance_valid(target) or target.health <= 0.0:
		return null

	var dir_x: float = -1.0 if target.global_position.x < user.global_position.x else 1.0
	var projectile: Projectile = projectile_scene.instantiate() as Projectile
	if projectile != null:
		if user is Hero:
			projectile.source_hero = user as Hero
		if spawn_at_target:
			projectile.global_position = target.global_position
			projectile.direction = Vector2.ZERO
			projectile.damage = damage
			projectile.knockback = 0.0
			if target is Enemy and stun_duration > 0.0:
				(target as Enemy).apply_stun(stun_duration)
			if target.has_method(&"take_damage"):
				target.call(&"take_damage", damage)
			if user is Hero and target is Enemy:
				(user as Hero).enemy_hit.emit(target as Enemy, damage, false)
		else:
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
