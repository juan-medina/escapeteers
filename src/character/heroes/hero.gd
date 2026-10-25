# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Hero
extends Character

signal melee_attack_started(attack_name: StringName)
signal enemy_hit(enemy: Enemy, damage: float, is_heavy: bool)

const RECRUIT_DISTANCE: float = 20.0
const MAX_HISTORY_DURATION: float = 2.5
const CRESCENT_BLEND_SPEED: float = 5.0
const PLAYER_LIGHT_TEXTURE: Texture2D = preload("res://map/light_texture.tres")
const _GROUP_ENEMIES: StringName = &"enemies"

@export var is_player: bool = false:
	set(value):
		is_player = value
		_update_collision_mode()
		_update_player_light()
		_update_ground_indicator()
@export var can_melee: bool = false
@export var can_heavy_melee: bool = false
@export var melee_range: float = 28.0
@export var melee1_cooldown: float = 0.5
@export var melee2_cooldown: float = 3.5
@export var melee2_chance: float = 0.35
@export var melee1_damage: float = 10.0
@export var melee2_damage: float = 25.0
@export var melee1_knockback: float = 85.0
@export var melee2_knockback: float = 260.0

var leader: Hero = null
var squad_member: SquadMember = null:
	set(value):
		squad_member = value
		_update_ground_indicator()
var is_moving: bool = false
var move_direction: Vector2 = Vector2.RIGHT
var crescent_blend: float = 0.0

var _elapsed_time: float = 0.0
var _pos_history: Array[Vector2] = []
var _time_history: Array[float] = []
var _player_light: PointLight2D = null
var _melee1_timer: float = 0.0
var _melee2_timer: float = 0.0
var _fast_attacks_done: int = 0
var _hit_applied_this_attack: bool = false
var _current_attack_name: StringName = StringName()
var _current_attack_target: Enemy = null

@onready var _ground_indicator: GroundIndicator = get_node_or_null(^"GroundIndicator") as GroundIndicator


func _ready() -> void:
	super._ready()
	_update_collision_mode()
	_update_player_light()
	_update_ground_indicator()
	_melee2_timer = melee2_cooldown * 0.5
	_animated_sprite.frame_changed.connect(_on_frame_changed)


func _process(delta: float) -> void:
	if _melee1_timer > 0.0:
		_melee1_timer -= delta
	if _melee2_timer > 0.0:
		_melee2_timer -= delta

	_check_auto_attack()

	if not is_player:
		return

	if _player_light != null:
		_player_light.energy = 0.65 + sin(_elapsed_time * 3.0) * 0.02

	var input_vector: Vector2 = Input.get_vector(&"left", &"right", &"up", &"down")

	if input_vector != Vector2.ZERO:
		is_moving = true
		move_direction = input_vector.normalized()
		crescent_blend = move_toward(crescent_blend, 1.0, CRESCENT_BLEND_SPEED * delta)
		velocity = input_vector * speed
		move_and_slide()
		if _ground_indicator != null:
			_ground_indicator.facing_direction = move_direction
		update_visuals(velocity * delta)
	else:
		is_moving = false
		crescent_blend = move_toward(crescent_blend, 0.0, CRESCENT_BLEND_SPEED * delta)
		velocity = Vector2.ZERO
		move_and_slide()
		update_visuals(Vector2.ZERO)


func _check_auto_attack() -> void:
	if not can_melee:
		return
	if not is_player and squad_member == null:
		return
	if is_attacking:
		return

	var closest_enemy: Enemy = _find_closest_enemy(melee_range)
	if closest_enemy == null:
		_fast_attacks_done = 0
		return

	if _melee1_timer > 0.0:
		return

	var choose_heavy: bool = false
	if can_heavy_melee and _melee2_timer <= 0.0:
		if _fast_attacks_done >= 2 and randf() < melee2_chance:
			choose_heavy = true

	if choose_heavy:
		_start_melee_attack(ANIM_ATTACK_MELEE2, closest_enemy)
	else:
		_start_melee_attack(ANIM_ATTACK_MELEE1, closest_enemy)


func _start_melee_attack(anim_name: StringName, target_enemy: Enemy) -> void:
	is_attacking = true
	_hit_applied_this_attack = false
	_current_attack_name = anim_name
	_current_attack_target = target_enemy

	if anim_name == ANIM_ATTACK_MELEE2:
		_melee2_timer = melee2_cooldown
		_melee1_timer = melee1_cooldown
		_fast_attacks_done = 0
	else:
		_melee1_timer = melee1_cooldown
		_fast_attacks_done += 1

	var diff_x: float = target_enemy.global_position.x - global_position.x
	if absf(diff_x) > 1.0:
		flip_h = diff_x < 0.0

	play(anim_name)
	melee_attack_started.emit(anim_name)


func _apply_melee_hit() -> void:
	_hit_applied_this_attack = true

	var is_heavy: bool = _current_attack_name == ANIM_ATTACK_MELEE2
	var damage_amount: float = melee2_damage if is_heavy else melee1_damage
	var knockback_amount: float = melee2_knockback if is_heavy else melee1_knockback

	var hit_range: float = melee_range * (1.3 if is_heavy else 1.15)
	var targets: Array[Enemy] = _find_enemies_in_range(hit_range)

	if targets.is_empty() and _current_attack_target != null and is_instance_valid(_current_attack_target):
		if global_position.distance_to(_current_attack_target.global_position) <= hit_range * 1.3:
			targets.append(_current_attack_target)

	for enemy: Enemy in targets:
		if not is_heavy and enemy != _current_attack_target and _current_attack_target != null:
			if (
				not is_instance_valid(_current_attack_target)
				or global_position.distance_squared_to(_current_attack_target.global_position) > hit_range * hit_range
			):
				_current_attack_target = enemy
			else:
				continue

		var push_dir: Vector2 = (enemy.global_position - global_position).normalized()
		if push_dir.length_squared() < 0.01:
			push_dir = Vector2.LEFT if flip_h else Vector2.RIGHT

		enemy.apply_knockback(push_dir * knockback_amount)
		enemy.take_damage(damage_amount)
		enemy_hit.emit(enemy, damage_amount, is_heavy)

		if not is_heavy:
			break


func _find_closest_enemy(max_distance: float) -> Enemy:
	var closest: Enemy = null
	var min_dist_sq: float = max_distance * max_distance
	for node: Node in get_tree().get_nodes_in_group(_GROUP_ENEMIES):
		var enemy: Enemy = node as Enemy
		if enemy == null or not is_instance_valid(enemy) or enemy.health <= 0.0 or enemy.is_queued_for_deletion():
			continue
		var dist_sq: float = global_position.distance_squared_to(enemy.global_position)
		if dist_sq <= min_dist_sq:
			min_dist_sq = dist_sq
			closest = enemy
	return closest


func _find_enemies_in_range(max_distance: float) -> Array[Enemy]:
	var result: Array[Enemy] = []
	var max_dist_sq: float = max_distance * max_distance
	for node: Node in get_tree().get_nodes_in_group(_GROUP_ENEMIES):
		var enemy: Enemy = node as Enemy
		if enemy == null or not is_instance_valid(enemy) or enemy.health <= 0.0 or enemy.is_queued_for_deletion():
			continue
		var dist_sq: float = global_position.distance_squared_to(enemy.global_position)
		if dist_sq <= max_dist_sq:
			result.append(enemy)
	return result


func _on_frame_changed() -> void:
	if not is_attacking or _hit_applied_this_attack:
		return

	if animation == ANIM_ATTACK_MELEE1 or animation == ANIM_ATTACK_MELEE2:
		if frame >= 2:
			_apply_melee_hit()


func _on_animation_finished() -> void:
	super._on_animation_finished()
	if is_attacking:
		if not _hit_applied_this_attack:
			_apply_melee_hit()
		is_attacking = false
		_current_attack_target = null
		if is_moving:
			play(ANIM_RUN)
		else:
			play(ANIM_IDLE)


func record_step(delta: float) -> void:
	_elapsed_time += delta
	_pos_history.push_front(position)
	_time_history.push_front(_elapsed_time)

	var cutoff_time: float = _elapsed_time - MAX_HISTORY_DURATION
	while _time_history.size() > 2 and _time_history.back() < cutoff_time:
		_time_history.pop_back()
		_pos_history.pop_back()


func get_delayed_position(delay: float) -> Vector2:
	if _pos_history.is_empty() or delay <= 0.001:
		return position

	var target_time: float = _elapsed_time - delay
	for i: int in range(_time_history.size() - 1):
		var t1: float = _time_history[i]
		var t2: float = _time_history[i + 1]
		if t1 >= target_time and target_time >= t2:
			var span: float = t1 - t2
			if span <= 0.0001:
				return _pos_history[i]
			return _pos_history[i].lerp(_pos_history[i + 1], (t1 - target_time) / span)

	return _pos_history.back()


func is_touching(other: Hero) -> bool:
	return position.distance_squared_to(other.position) <= RECRUIT_DISTANCE * RECRUIT_DISTANCE


func _update_player_light() -> void:
	if not is_inside_tree():
		return

	if is_player:
		if _player_light == null:
			_player_light = PointLight2D.new()
			_player_light.name = &"PlayerLight"
			_player_light.texture = PLAYER_LIGHT_TEXTURE
			_player_light.color = Color(1.0, 0.88, 0.70, 1.0)
			_player_light.energy = 0.65
			_player_light.texture_scale = 1.0
			add_child(_player_light)
	else:
		if _player_light != null:
			_player_light.queue_free()
			_player_light = null


func _update_collision_mode() -> void:
	if is_player:
		collision_layer = 2
		collision_mask = 1
	else:
		collision_layer = 4
		collision_mask = 1


func _update_ground_indicator() -> void:
	if _ground_indicator == null:
		return
	_ground_indicator.is_player = is_player
	_ground_indicator.is_recruited = (is_player or squad_member != null)
	_ground_indicator.facing_direction = move_direction
