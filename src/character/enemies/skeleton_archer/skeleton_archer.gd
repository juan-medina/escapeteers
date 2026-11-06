# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name SkeletonArcher
extends Enemy

const BONE_ARROW_SCENE: PackedScene = preload("res://projectile/bone_arrow/bone_arrow.tscn")
const KITE_DISTANCE: float = 65.0


func _ready() -> void:
	var data: EnemyData = EnemyData.get_enemy(&"skeleton_archer")
	if data != null:
		data.apply_to_enemy(self, level)
	super._ready()
	_setup_actions()


func set_level(new_level: int) -> void:
	if level == new_level and not combat_actions.is_empty():
		health = max_health
		if _health_bar != null:
			_health_bar.set_level(level)
			_health_bar.update_health(health, max_health)
		return
	super.set_level(new_level)
	var data: EnemyData = EnemyData.get_enemy(&"skeleton_archer")
	if data != null:
		data.apply_to_enemy(self, level)
	if combat_actions.is_empty():
		_setup_actions()
	else:
		_refresh_actions()
	if _health_bar != null:
		_health_bar.update_health(health, max_health)


func _process_chase(delta: float) -> void:
	if target != null and is_instance_valid(target) and target.health > 0.0 and not target.is_dead and combat_state == CombatState.COOLDOWN:
		var dist_to_target: float = global_position.distance_to(target.global_position)
		if dist_to_target < KITE_DISTANCE:
			var diff_x: float = target.global_position.x - global_position.x
			if absf(diff_x) > 2.0:
				flip_h = diff_x < 0.0
			var away_dir: Vector2 = (global_position - target.global_position).normalized()
			if away_dir.length_squared() < 0.01:
				away_dir = Vector2.LEFT if not flip_h else Vector2.RIGHT
			velocity = (away_dir * speed * _slow_multiplier) + _knockback_velocity
			move_and_slide()
			update_visuals(velocity * delta)
			return
	super._process_chase(delta)


func _refresh_actions() -> void:
	for action: CombatAction in combat_actions:
		if action is RangedAction:
			var ranged: RangedAction = action as RangedAction
			ranged.range_distance = ranged_range
			ranged.min_range_distance = ranged_min_range
			ranged.damage = damage
			ranged.cooldown = attack_cooldown


func _setup_actions() -> void:
	if can_ranged:
		var ranged: RangedAction = RangedAction.new()
		ranged.projectile_scene = BONE_ARROW_SCENE
		ranged.range_distance = ranged_range
		ranged.min_range_distance = ranged_min_range
		ranged.damage = damage
		ranged.cooldown = attack_cooldown
		ranged.requires_horizontal_alignment = false
		ranged.check_line_of_sight = true
		ranged.leash_distance = 0.0
		combat_actions.append(ranged)
