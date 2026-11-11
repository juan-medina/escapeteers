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
var show_telegraph: bool = false
var telegraph_color: Color = Color(1.0, 0.35, 0.2, 0.35)
var telegraph_locked_color: Color = Color(1.0, 0.15, 0.1, 0.85)
var telegraph_lock_time: float = 0.25
var active_telegraph: TelegraphLine = null
var locked_fire_direction: Vector2 = Vector2.ZERO


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

	locked_fire_direction = Vector2.ZERO
	if show_telegraph and user is Enemy:
		_start_telegraph(user as Enemy, target)


func _start_telegraph(enemy: Enemy, target: Character) -> void:
	if active_telegraph != null and is_instance_valid(active_telegraph):
		active_telegraph.cancel()
		active_telegraph = null

	var anim_duration: float = enemy.get_animation_duration(animation_name)
	if anim_duration <= 0.0:
		anim_duration = 0.9

	var line: TelegraphLine = TelegraphLine.new()
	line.line_length = range_distance
	line.horizontal_only = requires_horizontal_alignment
	line.base_color = telegraph_color
	line.locked_color = telegraph_locked_color
	line.target = target
	line.telegraph_locked.connect(_on_telegraph_locked)
	enemy.add_child(line)
	line.start(anim_duration, telegraph_lock_time)
	active_telegraph = line
	enemy.active_telegraph = line


func _on_telegraph_locked(telegraph: Telegraph) -> void:
	var line: TelegraphLine = telegraph as TelegraphLine
	if line != null:
		locked_fire_direction = line.locked_direction


func cancel_telegraph() -> void:
	if active_telegraph != null and is_instance_valid(active_telegraph):
		active_telegraph.cancel()
		active_telegraph = null
	locked_fire_direction = Vector2.ZERO


func spawn_projectile(user: Character, target: Character) -> Projectile:
	if projectile_scene == null or target == null or not is_instance_valid(target) or target.health <= 0.0:
		cancel_telegraph()
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
			var enemy: Enemy = target as Enemy
			if enemy != null and stun_duration > 0.0:
				enemy.apply_stun(stun_duration)
			target.take_damage(damage)
			if user is Hero and enemy != null:
				(user as Hero).enemy_hit.emit(enemy, damage, false)
		else:
			var spawn_pos: Vector2 = user.global_position + Vector2(dir_x * 8.0, 0.0)
			var fire_dir: Vector2 = Vector2(dir_x, 0.0)
			if locked_fire_direction != Vector2.ZERO:
				fire_dir = locked_fire_direction
			elif not requires_horizontal_alignment:
				var diff: Vector2 = target.global_position - spawn_pos
				if diff.length_squared() > 0.001:
					fire_dir = diff.normalized()
			projectile.global_position = spawn_pos
			projectile.direction = fire_dir
			projectile.damage = damage
			projectile.knockback = knockback

	if active_telegraph != null and is_instance_valid(active_telegraph):
		active_telegraph.finish()
		active_telegraph = null
	locked_fire_direction = Vector2.ZERO
	return projectile
