# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Hero
extends Character

signal melee_attack_started(attack_name: StringName)
signal ranged_attack_started(attack_name: StringName)
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
@export var can_heavy_melee: bool = false
@export var melee1_cooldown: float = 0.5
@export var melee2_cooldown: float = 3.5
@export var melee2_chance: float = 0.35
@export var melee1_damage: float = 10.0
@export var melee2_damage: float = 25.0
@export var melee1_knockback: float = 85.0
@export var melee2_knockback: float = 260.0
@export var ranged_cooldown: float = 1.0
@export var ranged_damage: float = 10.0
@export var ranged_frame: int = 7
@export var ranged_projectile_scene: PackedScene = preload("res://projectile/arrow/arrow.tscn")

var leader: Hero = null
var squad_member: SquadMember = null:
	set(value):
		squad_member = value
		_update_ground_indicator()
var is_moving: bool = false
var move_direction: Vector2 = Vector2.RIGHT
var crescent_blend: float = 0.0
var combat_actions: Array[CombatAction] = []
var active_target: Enemy = null
var current_action: CombatAction = null

var _elapsed_time: float = 0.0
var _pos_history: Array[Vector2] = []
var _time_history: Array[float] = []
var _player_light: PointLight2D = null
var _hit_applied_this_attack: bool = false

@onready var _ground_indicator: GroundIndicator = get_node_or_null(^"GroundIndicator") as GroundIndicator


func _ready() -> void:
	super._ready()
	if _health_bar != null:
		_health_bar.set_fill_color(HealthBar.DEFAULT_HERO_COLOR)
	_update_collision_mode()
	_update_player_light()
	_update_ground_indicator()
	_animated_sprite.frame_changed.connect(_on_frame_changed)
	_setup_actions()


func _process(delta: float) -> void:
	for action: CombatAction in combat_actions:
		action.update(delta)

	if combat_state == CombatState.COOLDOWN:
		var any_ready: bool = false
		for action: CombatAction in combat_actions:
			if action.is_ready():
				any_ready = true
				break
		if any_ready:
			combat_state = CombatState.READY

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


func _setup_actions() -> void:
	if can_melee:
		var melee: MeleeAction = MeleeAction.new()
		melee.range_distance = melee_range
		melee.cooldown = melee1_cooldown
		melee.damage = melee1_damage
		melee.knockback = melee1_knockback
		melee.can_heavy = can_heavy_melee
		melee.heavy_cooldown = melee2_cooldown
		melee.heavy_damage = melee2_damage
		melee.heavy_chance = melee2_chance
		melee.heavy_knockback = melee2_knockback
		melee.leash_distance = 48.0
		combat_actions.append(melee)

	if can_ranged:
		var ranged: RangedAction = RangedAction.new()
		ranged.projectile_scene = ranged_projectile_scene
		ranged.range_distance = ranged_range
		ranged.min_range_distance = ranged_min_range if can_melee else 0.0
		ranged.cooldown = ranged_cooldown
		ranged.damage = ranged_damage
		ranged.projectile_frame = ranged_frame
		ranged.leash_distance = ranged_range
		ranged.check_line_of_sight = true
		combat_actions.append(ranged)


func get_anchor_position() -> Vector2:
	if is_player or squad_member == null or leader == null:
		return global_position
	return squad_member.get_formation_position(leader)


func get_current_leash() -> float:
	var max_leash: float = 48.0
	for action: CombatAction in combat_actions:
		max_leash = maxf(max_leash, action.leash_distance)
	return max_leash


func get_attack_range() -> float:
	var max_range: float = 0.0
	for action: CombatAction in combat_actions:
		max_range = maxf(max_range, action.range_distance)
	return max_range if max_range > 0.0 else melee_range


func _check_auto_attack() -> void:
	if combat_actions.is_empty():
		return
	if not is_player and squad_member == null:
		return
	if combat_state != CombatState.READY:
		return

	var anchor: Vector2 = get_anchor_position()
	var closest_enemy: Enemy = _find_closest_enemy_in_leash(anchor)
	if closest_enemy == null:
		return

	active_target = closest_enemy
	for action: CombatAction in combat_actions:
		if action.can_execute(self, closest_enemy, anchor):
			current_action = action
			combat_state = CombatState.ATTACKING
			_hit_applied_this_attack = false
			action.execute(self, closest_enemy)
			if action is MeleeAction:
				melee_attack_started.emit(animation)
			elif action is RangedAction:
				ranged_attack_started.emit(animation)
			break


func _find_closest_enemy_in_leash(anchor: Vector2) -> Enemy:
	var closest: Enemy = null
	var min_dist_sq: float = INF
	var max_leash: float = get_current_leash()
	var max_leash_sq: float = max_leash * max_leash

	for node: Node in get_tree().get_nodes_in_group(_GROUP_ENEMIES):
		var enemy: Enemy = node as Enemy
		if enemy == null or not is_instance_valid(enemy) or enemy.health <= 0.0 or enemy.is_queued_for_deletion():
			continue

		var dist_to_anchor_sq: float = anchor.distance_squared_to(enemy.global_position)
		if dist_to_anchor_sq <= max_leash_sq:
			var dist_to_self_sq: float = global_position.distance_squared_to(enemy.global_position)
			if dist_to_self_sq < min_dist_sq:
				min_dist_sq = dist_to_self_sq
				closest = enemy

	return closest


func _on_frame_changed() -> void:
	if combat_state != CombatState.ATTACKING or _hit_applied_this_attack:
		return

	if current_action is MeleeAction and active_target != null:
		if frame >= 2:
			_hit_applied_this_attack = true
			var melee: MeleeAction = current_action as MeleeAction
			melee.apply_hit(self, active_target)
			var is_heavy: bool = melee.current_is_heavy
			var dmg: float = melee.heavy_damage if is_heavy else melee.damage
			enemy_hit.emit(active_target, dmg, is_heavy)
	elif current_action is RangedAction and active_target != null:
		var ranged: RangedAction = current_action as RangedAction
		if frame >= ranged.projectile_frame:
			_hit_applied_this_attack = true
			var proj: Projectile = ranged.spawn_projectile(self, active_target)
			if proj != null:
				spawn_projectile(proj)


func _on_animation_finished() -> void:
	super._on_animation_finished()
	if not _hit_applied_this_attack and current_action is RangedAction and active_target != null:
		var ranged: RangedAction = current_action as RangedAction
		var proj: Projectile = ranged.spawn_projectile(self, active_target)
		if proj != null:
			spawn_projectile(proj)
	_hit_applied_this_attack = false


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
