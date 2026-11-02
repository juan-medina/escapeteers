# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name MeleeAction
extends CombatAction

var can_heavy: bool = false
var heavy_cooldown: float = 3.5
var heavy_cooldown_timer: float = 0.0
var heavy_chance: float = 0.35
var heavy_damage: float = 25.0
var knockback: float = 85.0
var heavy_knockback: float = 260.0
var vertical_tolerance: float = 18.0

var fast_attacks_done: int = 0
var current_is_heavy: bool = false


func update(delta: float) -> void:
	super.update(delta)
	if heavy_cooldown_timer > 0.0:
		heavy_cooldown_timer -= delta


func can_reach(user: Character, target: Character) -> bool:
	if target == null or not is_instance_valid(target) or target.health <= 0.0:
		return false

	var user_pos: Vector2 = user.get_hurtbox_position()
	var target_pos: Vector2 = target.get_hurtbox_position()
	var target_radius: float = target.get_hurtbox_radius()

	var dx: float = maxf(0.0, absf(target_pos.x - user_pos.x) - target_radius)
	var dy: float = maxf(0.0, absf(target_pos.y - user_pos.y) - target_radius)

	if dy > vertical_tolerance:
		return false
	if dx > range_distance:
		return false

	var diff_x: float = target_pos.x - user_pos.x
	if user.flip_h and diff_x > target_radius:
		return false
	if not user.flip_h and diff_x < -target_radius:
		return false

	var edge_dist: float = maxf(0.0, user_pos.distance_to(target_pos) - target_radius)
	return edge_dist >= min_range_distance and edge_dist <= range_distance


func execute(user: Character, target: Character) -> void:
	super.execute(user, target)

	current_is_heavy = false
	if can_heavy and heavy_cooldown_timer <= 0.0 and fast_attacks_done >= 2:
		if randf() < heavy_chance:
			current_is_heavy = true

	if current_is_heavy:
		heavy_cooldown_timer = heavy_cooldown
		fast_attacks_done = 0
		user.play(Character.ANIM_ATTACK_MELEE2)
	else:
		fast_attacks_done += 1
		user.play(Character.ANIM_ATTACK_MELEE1)

	var diff_x: float = target.global_position.x - user.global_position.x
	if absf(diff_x) > 1.0:
		user.flip_h = diff_x < 0.0


func apply_hit(user: Character, target: Character) -> bool:
	if target == null or not is_instance_valid(target) or target.health <= 0.0:
		return false

	if not can_reach(user, target):
		return false

	var applied_damage: float = heavy_damage if current_is_heavy else damage
	var applied_knockback: float = heavy_knockback if current_is_heavy else knockback

	var push_dir: Vector2 = (target.global_position - user.global_position).normalized()
	if push_dir.length_squared() < 0.01:
		push_dir = Vector2.LEFT if user.flip_h else Vector2.RIGHT

	if target is Enemy:
		(target as Enemy).apply_knockback(push_dir * applied_knockback)

	target.take_damage(applied_damage)
	return true
