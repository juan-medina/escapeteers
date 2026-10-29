# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Hero
extends Character

signal melee_attack_started(attack_name: StringName)
signal ranged_attack_started(attack_name: StringName)
signal heal_cast_started(anim_name: StringName)
signal enemy_hit(enemy: Enemy, damage: float, is_heavy: bool)
signal ally_healed(ally: Character, amount: float)

const RECRUIT_DISTANCE: float = 20.0
const MAX_HISTORY_DURATION: float = 2.5
const CRESCENT_BLEND_SPEED: float = 5.0
const PLAYER_LIGHT_TEXTURE: Texture2D = preload("res://map/light_texture.tres")
const PLAYER_LIGHT_BASE_ENERGY: float = 0.25
const PLAYER_LIGHT_SCALE: float = 1.6
const PLAYER_HURTBOX_RADIUS: float = 3.5
const COMPANION_HURTBOX_RADIUS: float = 4.5
const HERO_MELEE_VERTICAL_TOLERANCE: float = 20.0
const _GROUP_ENEMIES: StringName = &"enemies"
const _GROUP_HEROES: StringName = &"heroes"

@export var is_player: bool = false:
	set(value):
		is_player = value
		_update_collision_mode()
		_update_player_light()
		_update_ground_indicator()
		_update_active_mode()
@export var can_heavy_melee: bool = false
@export var melee1_cooldown: float = 0.5
@export var melee2_cooldown: float = 3.5
@export var melee2_chance: float = 0.35
@export var melee1_damage: float = 10.0
@export var melee2_damage: float = 25.0
@export var melee1_knockback: float = 85.0
@export var melee2_knockback: float = 260.0
@export var melee2_hit_frames: Array[int] = []
@export var ranged_cooldown: float = 1.0
@export var ranged_damage: float = 10.0
@export var ranged_knockback: float = 0.0
@export var ranged_frame: int = 7
@export var ranged_projectile_scene: PackedScene = preload("res://projectile/arrow/arrow.tscn")
@export var heal_cooldown: float = 2.4
@export var heal_amount: float = 20.0
@export var heal_frame: int = 3
@export var heal_effect_scene: PackedScene = preload("res://projectile/heal/heal_effect.tscn")

var leader: Hero = null
var squad_member: SquadMember = null:
	set(value):
		squad_member = value
		_update_ground_indicator()
		_update_active_mode()
var is_moving: bool = false
var move_direction: Vector2 = Vector2.RIGHT
var crescent_blend: float = 0.0
var combat_actions: Array[CombatAction] = []
var active_target: Character = null
var current_action: CombatAction = null

var _elapsed_time: float = 0.0
var _pos_history: Array[Vector2] = []
var _time_history: Array[float] = []
var _player_light: PointLight2D = null
var _hit_applied_this_attack: bool = false
var _hits_applied_frames: Array[int] = []
var _notifier: VisibleOnScreenNotifier2D = null
var _is_on_screen: bool = false

@onready var _ground_indicator: GroundIndicator = get_node_or_null(^"GroundIndicator") as GroundIndicator


func _ready() -> void:
	super._ready()
	add_to_group(_GROUP_HEROES)
	if _health_bar != null:
		_health_bar.set_fill_color(HealthBar.DEFAULT_HERO_COLOR)

	hurtbox = Hurtbox.new(self, PLAYER_HURTBOX_RADIUS if is_player else COMPANION_HURTBOX_RADIUS, Vector2(0.0, 2.0))
	hurtbox.collision_layer = 64
	hurtbox.collision_mask = 0
	add_child(hurtbox)

	_notifier = VisibleOnScreenNotifier2D.new()
	_notifier.rect = Rect2(-64.0, -64.0, 128.0, 128.0)
	_notifier.screen_entered.connect(_on_screen_entered)
	_notifier.screen_exited.connect(_on_screen_exited)
	add_child(_notifier)
	_is_on_screen = _notifier.is_on_screen()

	_update_collision_mode()
	_update_player_light()
	_update_ground_indicator()
	_update_active_mode()
	_animated_sprite.frame_changed.connect(_on_frame_changed)
	_setup_actions()


func _process(delta: float) -> void:
	if is_dead:
		return

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
		_player_light.energy = PLAYER_LIGHT_BASE_ENERGY + sin(_elapsed_time * 3.0) * 0.02

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
		melee.vertical_tolerance = HERO_MELEE_VERTICAL_TOLERANCE
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
		ranged.knockback = ranged_knockback
		ranged.projectile_frame = ranged_frame
		ranged.leash_distance = 0.0
		ranged.check_line_of_sight = true
		combat_actions.append(ranged)

	if can_heal:
		var heal_act: HealAction = HealAction.new()
		heal_act.heal_effect_scene = heal_effect_scene
		heal_act.range_distance = heal_range
		heal_act.cooldown = heal_cooldown
		heal_act.heal_amount = heal_amount
		heal_act.cast_frame = heal_frame
		heal_act.leash_distance = 0.0
		heal_act.check_line_of_sight = true
		combat_actions.append(heal_act)


func get_anchor_position() -> Vector2:
	if is_player or squad_member == null or leader == null:
		return global_position
	return squad_member.get_formation_position(leader)


func get_current_leash() -> float:
	var max_leash: float = 0.0
	for action: CombatAction in combat_actions:
		max_leash = maxf(max_leash, action.leash_distance)
	return max_leash


func get_detection_range() -> float:
	var max_detect: float = 0.0
	for action: CombatAction in combat_actions:
		max_detect = maxf(max_detect, maxf(action.range_distance, action.leash_distance))
	return max_detect if max_detect > 0.0 else melee_range


func get_attack_range() -> float:
	var max_range: float = 0.0
	for action: CombatAction in combat_actions:
		max_range = maxf(max_range, action.range_distance)
	return max_range if max_range > 0.0 else melee_range


func can_reach_target(target_char: Character) -> bool:
	if target_char == null or not is_instance_valid(target_char) or target_char.health <= 0.0 or target_char.is_dead:
		return false
	for action: CombatAction in combat_actions:
		if target_char is Enemy and action is HealAction:
			continue
		if not (target_char is Enemy) and not (action is HealAction):
			continue
		if action.can_reach(self, target_char):
			return true
	return false


func _check_auto_attack() -> void:
	if combat_actions.is_empty():
		return
	if not is_player and squad_member == null:
		return
	if combat_state != CombatState.READY:
		return

	var target_char: Character = null
	var selected_action: CombatAction = null

	if can_heal:
		var injured_ally: Hero = _find_injured_ally()
		if injured_ally != null:
			for action: CombatAction in combat_actions:
				if action is HealAction:
					target_char = injured_ally
					if action.can_execute(self, injured_ally):
						selected_action = action
					break

	if target_char == null and (can_melee or can_ranged):
		var closest_enemy: Enemy = _find_closest_enemy()
		if closest_enemy != null:
			target_char = closest_enemy
			for action: CombatAction in combat_actions:
				if not (action is HealAction) and action.can_execute(self, closest_enemy):
					selected_action = action
					break

	active_target = target_char
	if active_target == null:
		return

	if selected_action != null:
		current_action = selected_action
		combat_state = CombatState.ATTACKING
		_hit_applied_this_attack = false
		_hits_applied_frames.clear()
		selected_action.execute(self, active_target)
		if selected_action is MeleeAction:
			melee_attack_started.emit(animation)
		elif selected_action is RangedAction:
			ranged_attack_started.emit(animation)
		elif selected_action is HealAction:
			heal_cast_started.emit(animation)


func _find_closest_enemy() -> Enemy:
	var closest: Enemy = null
	var min_dist_sq: float = INF
	var max_detection: float = get_detection_range()
	var max_detection_sq: float = max_detection * max_detection

	for node: Node in get_tree().get_nodes_in_group(_GROUP_ENEMIES):
		var enemy: Enemy = node as Enemy
		if enemy == null or not is_instance_valid(enemy) or enemy.health <= 0.0 or enemy.is_queued_for_deletion():
			continue

		var dist_to_self_sq: float = global_position.distance_squared_to(enemy.global_position)
		if dist_to_self_sq <= max_detection_sq and dist_to_self_sq < min_dist_sq:
			min_dist_sq = dist_to_self_sq
			closest = enemy

	return closest


func _find_injured_ally() -> Hero:
	var best_target: Hero = null
	var lowest_health_ratio: float = 1.0
	var closest_dist_sq: float = INF
	var max_detection: float = heal_range
	var max_detection_sq: float = max_detection * max_detection

	for node: Node in get_tree().get_nodes_in_group(_GROUP_HEROES):
		var ally: Hero = node as Hero
		if ally == null or not is_instance_valid(ally) or ally.is_dead or ally.health <= 0.0 or ally.is_queued_for_deletion():
			continue
		if not ally.is_player and ally.squad_member == null:
			continue
		if ally.health >= ally.max_health:
			continue

		var dist_sq: float = global_position.distance_squared_to(ally.global_position)
		if dist_sq > max_detection_sq:
			continue

		var ratio: float = ally.health / ally.max_health
		if ratio < lowest_health_ratio - 0.001 or (absf(ratio - lowest_health_ratio) <= 0.001 and dist_sq < closest_dist_sq):
			lowest_health_ratio = ratio
			closest_dist_sq = dist_sq
			best_target = ally

	return best_target


func _on_frame_changed() -> void:
	if is_dead or combat_state != CombatState.ATTACKING:
		return

	if current_action is MeleeAction and active_target != null:
		var melee: MeleeAction = current_action as MeleeAction
		var is_heavy: bool = melee.current_is_heavy
		if is_heavy and not melee2_hit_frames.is_empty():
			for hit_frame: int in melee2_hit_frames:
				if frame >= hit_frame and not _hits_applied_frames.has(hit_frame):
					_hits_applied_frames.append(hit_frame)
					if melee.apply_hit(self, active_target) and active_target is Enemy:
						enemy_hit.emit(active_target as Enemy, melee.heavy_damage, true)
		elif not _hit_applied_this_attack and frame >= 2:
			_hit_applied_this_attack = true
			var dmg: float = melee.heavy_damage if is_heavy else melee.damage
			if melee.apply_hit(self, active_target) and active_target is Enemy:
				enemy_hit.emit(active_target as Enemy, dmg, is_heavy)
	elif current_action is RangedAction and active_target != null and not _hit_applied_this_attack:
		var ranged: RangedAction = current_action as RangedAction
		if frame >= ranged.projectile_frame:
			_hit_applied_this_attack = true
			var proj: Projectile = ranged.spawn_projectile(self, active_target)
			if proj != null:
				spawn_projectile(proj)
	elif current_action is HealAction and active_target != null and not _hit_applied_this_attack:
		var heal_act: HealAction = current_action as HealAction
		if frame >= heal_act.cast_frame:
			_hit_applied_this_attack = true
			heal_act.apply_heal(self, active_target)
			var effect: Projectile = heal_act.spawn_heal_effect(self, active_target)
			if effect != null:
				spawn_projectile(effect)
			ally_healed.emit(active_target, heal_act.heal_amount)


func _on_death() -> void:
	super._on_death()
	if _player_light != null:
		_player_light.visible = false
	if _ground_indicator != null:
		_ground_indicator.visible = false
	if not is_player:
		if not _animated_sprite.animation_finished.is_connected(queue_free):
			_animated_sprite.animation_finished.connect(queue_free, CONNECT_ONE_SHOT)


func _on_animation_finished() -> void:
	super._on_animation_finished()
	if is_dead:
		return
	if not _hit_applied_this_attack and current_action is RangedAction and active_target != null:
		var ranged: RangedAction = current_action as RangedAction
		var proj: Projectile = ranged.spawn_projectile(self, active_target)
		if proj != null:
			spawn_projectile(proj)
	elif not _hit_applied_this_attack and current_action is HealAction and active_target != null:
		var heal_act: HealAction = current_action as HealAction
		heal_act.apply_heal(self, active_target)
		var effect: Projectile = heal_act.spawn_heal_effect(self, active_target)
		if effect != null:
			spawn_projectile(effect)
		ally_healed.emit(active_target, heal_act.heal_amount)
	_hit_applied_this_attack = false
	_hits_applied_frames.clear()


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
			_player_light.energy = PLAYER_LIGHT_BASE_ENERGY
			_player_light.texture_scale = PLAYER_LIGHT_SCALE
			add_child(_player_light)
	else:
		if _player_light != null:
			_player_light.queue_free()
			_player_light = null


func _update_collision_mode() -> void:
	if is_player:
		collision_layer = 2
		collision_mask = 1 | 8
	else:
		collision_layer = 4
		collision_mask = 1 | 8
	if hurtbox != null:
		hurtbox.radius = PLAYER_HURTBOX_RADIUS if is_player else COMPANION_HURTBOX_RADIUS


func _update_ground_indicator() -> void:
	if _ground_indicator == null:
		return
	_ground_indicator.is_player = is_player
	_ground_indicator.is_recruited = (is_player or squad_member != null)
	_ground_indicator.facing_direction = move_direction


func _on_screen_entered() -> void:
	_is_on_screen = true
	_update_active_mode()


func _on_screen_exited() -> void:
	_is_on_screen = false
	_update_active_mode()


func _update_active_mode() -> void:
	if not is_inside_tree():
		return
	var is_recruited: bool = is_player or squad_member != null
	if is_recruited:
		set_process(true)
		set_physics_process(true)
		if not _animated_sprite.is_playing() and not is_dead:
			_animated_sprite.play()
		if not is_dead:
			enable_collisions()
	else:
		set_process(false)
		set_physics_process(false)
		disable_collisions()
		if _is_on_screen:
			if not _animated_sprite.is_playing() and not is_dead:
				_animated_sprite.play()
		else:
			_animated_sprite.pause()
