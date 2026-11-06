# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Necromancer
extends Enemy

const KITE_DISTANCE: float = 95.0
const SUMMON_FRAME: int = 6
const SUMMON_RADIUS_MIN: float = 22.0
const SUMMON_RADIUS_MAX: float = 48.0

var can_summon: bool = false
var summon_range: float = 180.0
var summon_count: int = 2

var _summoned_this_cast: bool = false


func _ready() -> void:
	var data: EnemyData = EnemyData.get_enemy(&"necromancer")
	if data != null:
		data.apply_to_enemy(self, level)
	super._ready()
	_animated_sprite.frame_changed.connect(_on_frame_changed)
	_setup_actions()


func set_level(new_level: int) -> void:
	if level == new_level and not combat_actions.is_empty():
		health = max_health
		if _health_bar != null:
			_health_bar.set_level(level)
			_health_bar.update_health(health, max_health)
		return
	super.set_level(new_level)
	var data: EnemyData = EnemyData.get_enemy(&"necromancer")
	if data != null:
		data.apply_to_enemy(self, level)
	if combat_actions.is_empty():
		_setup_actions()
	else:
		_refresh_actions()
	if _health_bar != null:
		_health_bar.update_health(health, max_health)


func reset_for_pool() -> void:
	_summoned_this_cast = false
	super.reset_for_pool()


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


func _check_combat_actions() -> void:
	var prev_state: CombatState = combat_state
	super._check_combat_actions()
	if prev_state != CombatState.ATTACKING and combat_state == CombatState.ATTACKING:
		_summoned_this_cast = false


func _on_frame_changed() -> void:
	if is_dead or combat_state != CombatState.ATTACKING or _summoned_this_cast:
		return
	if animation == ANIM_SUMMON and frame == SUMMON_FRAME:
		_summoned_this_cast = true
		_emit_summons()


func _on_animation_finished() -> void:
	if not is_dead and current_action is SummonAction and not _summoned_this_cast:
		_summoned_this_cast = true
		_emit_summons()
	super._on_animation_finished()


func _emit_summons() -> void:
	var base_angle: float = randf() * TAU
	var count: int = maxi(1, summon_count)
	var step_angle: float = TAU / float(count)
	for i: int in range(count):
		var angle: float = base_angle + float(i) * step_angle + randf_range(-0.35, 0.35)
		var dist: float = randf_range(SUMMON_RADIUS_MIN, SUMMON_RADIUS_MAX)
		var candidate_pos: Vector2 = global_position + Vector2.from_angle(angle) * dist
		if map != null:
			candidate_pos = map.clamp_to_walkable(candidate_pos)
		minion_summon_requested.emit(candidate_pos, home_room, level)


func _refresh_actions() -> void:
	for action: CombatAction in combat_actions:
		if action is SummonAction:
			var summon: SummonAction = action as SummonAction
			summon.range_distance = summon_range
			summon.cooldown = attack_cooldown
			summon.summon_count = summon_count


func _setup_actions() -> void:
	if can_summon:
		var summon: SummonAction = SummonAction.new()
		summon.range_distance = summon_range
		summon.cooldown = attack_cooldown
		summon.summon_count = summon_count
		summon.check_line_of_sight = true
		summon.leash_distance = 0.0
		combat_actions.append(summon)
