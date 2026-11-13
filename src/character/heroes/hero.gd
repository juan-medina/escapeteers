# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Hero
extends Character

signal melee_attack_started(attack_name: StringName)
signal ranged_attack_started(attack_name: StringName)
signal heal_cast_started(anim_name: StringName)
signal enemy_hit(enemy: Enemy, damage: float, is_heavy: bool)
signal ally_healed(ally: Character, amount: float)

const MAX_HISTORY_DURATION: float = 2.5
const HISTORY_CAPACITY: int = 256
const CRESCENT_BLEND_SPEED: float = 5.0
const SPRINT_SPEED: float = 150.0
const PLAYER_LIGHT_TEXTURE: Texture2D = preload("res://map/light_texture.tres")
const PLAYER_LIGHT_BASE_ENERGY: float = 0.25
const PLAYER_LIGHT_SCALE: float = 1.6
const PLAYER_HURTBOX_RADIUS: float = 3.5
const COMPANION_HURTBOX_RADIUS: float = 4.5
const HERO_MELEE_VERTICAL_TOLERANCE: float = 12.0
const HEAL_TRIAGE_THRESHOLD: float = 0.75
const _GROUP_ENEMIES: StringName = &"enemies"
const _GROUP_HEROES: StringName = &"heroes"

@export var level: int = 1:
	set(value):
		level = value
		_update_level_display()
@export var is_player: bool = false:
	set(value):
		is_player = value
		_update_collision_mode()
		_update_player_light()
		_update_ground_indicator()
		_update_active_mode()

@export var melee_hit_effect_scene: PackedScene = null
@export var melee2_hit_frames: Array[int] = []
@export var ranged_frame: int = 7
@export var ranged_projectile_scene: PackedScene = preload("res://projectile/arrow/arrow.tscn")
@export var ranged_animation: StringName = Character.ANIM_ATTACK_RANGED1
@export var ranged_spawn_at_target: bool = false
@export var heal_frame: int = 3
@export var heal_effect_scene: PackedScene = preload("res://projectile/heal/heal_effect.tscn")

var can_heavy_melee: bool = false
var melee_leash_distance: float = 96.0
var melee1_cooldown: float = 0.5
var melee2_cooldown: float = 3.5
var melee2_chance: float = 0.35
var melee1_damage: float = 10.0
var melee2_damage: float = 25.0
var melee1_knockback: float = 85.0
var melee2_knockback: float = 260.0
var melee1_stun_duration: float = 0.0
var melee1_burn_dps: float = 0.0
var melee1_burn_duration: float = 0.0
var ranged_cooldown: float = 1.0
var ranged_damage: float = 10.0
var ranged_knockback: float = 0.0
var ranged_stun_duration: float = 0.0
var heal_cooldown: float = 2.4
var heal_amount: float = 20.0

var hero_data: HeroData = null
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
var _history_head: int = 0
var _history_count: int = 0
var _player_light: PointLight2D = null
var _hit_applied_this_attack: bool = false
var _hits_applied_frames: Array[int] = []
var _notifier: VisibleOnScreenNotifier2D = null
var _hero_vfx: HeroVfx = null
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

	_hero_vfx = HeroVfx.new()
	if _health_bar != null:
		_hero_vfx.head_y = _health_bar.position.y + 2.0
	add_child(_hero_vfx)

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
	_update_level_display()
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

	var input_vector: Vector2 = InputManager.get_movement_vector(get_global_transform_with_canvas().origin)

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
		melee.stun_duration = melee1_stun_duration
		melee.burn_dps = melee1_burn_dps
		melee.burn_duration = melee1_burn_duration
		melee.hit_effect_scene = melee_hit_effect_scene
		melee.can_heavy = can_heavy_melee
		melee.heavy_cooldown = melee2_cooldown
		melee.heavy_damage = melee2_damage
		melee.heavy_chance = melee2_chance
		melee.heavy_knockback = melee2_knockback
		melee.leash_distance = melee_leash_distance
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
		ranged.animation_name = ranged_animation
		ranged.stun_duration = ranged_stun_duration
		ranged.spawn_at_target = ranged_spawn_at_target
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


func update_visuals(movement_vector: Vector2) -> void:
	super.update_visuals(movement_vector)
	if _hero_vfx != null:
		var sprinting: bool = not is_dead and movement_vector.length_squared() > MIN_MOVEMENT_THRESHOLD_SQUARED and speed > BASE_SPEED + 5.0
		_hero_vfx.set_sprinting(sprinting, movement_vector)


func play_level_up_vfx() -> void:
	if _health_bar != null:
		_health_bar.update_health(health, max_health)
	if _hero_vfx != null and not is_dead:
		_hero_vfx.trigger_level_up()


func refresh_combat_actions() -> void:
	combat_actions.clear()
	_setup_actions()


func heal(amount: float) -> void:
	super.heal(amount)
	if not is_dead:
		Audio.play_hero_health(true)


func take_damage(amount: float, flash_hurt: bool = true) -> void:
	super.take_damage(amount, flash_hurt)
	if not is_dead and health > 0.0:
		Audio.play_hero_health(false)


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


func is_engaged() -> bool:
	if is_dead:
		return false
	if active_target is Enemy and is_instance_valid(active_target) and not active_target.is_dead:
		return true
	if combat_state == CombatState.ATTACKING and current_action != null and not (current_action is HealAction):
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

	var heal_action: HealAction = null
	if can_heal:
		for action: CombatAction in combat_actions:
			if action is HealAction:
				heal_action = action as HealAction
				break

	# 1. Triage priority: heal critically injured allies (<= 75% HP) if Heal is ready.
	if heal_action != null and heal_action.is_ready():
		var injured_ally: Hero = _find_injured_ally(HEAL_TRIAGE_THRESHOLD)
		if injured_ally != null and heal_action.can_execute(self, injured_ally):
			target_char = injured_ally
			selected_action = heal_action

	# 2. DPS / Stun: if no triage heal needed (or Heal is on cooldown), attack nearby enemies if DPS is ready.
	if selected_action == null and (can_melee or can_ranged):
		var closest_enemy: Enemy = _find_closest_enemy()
		if closest_enemy != null:
			for action: CombatAction in combat_actions:
				if not (action is HealAction) and action.can_execute(self, closest_enemy):
					target_char = closest_enemy
					selected_action = action
					break
			if target_char == null and can_melee and not is_player:
				var leash: float = get_current_leash()
				if leash > 0.0 and get_anchor_position().distance_squared_to(closest_enemy.global_position) <= leash * leash:
					target_char = closest_enemy

	# 3. Peaceful top-off: if no enemies in range to attack, top off any ally below 100% HP.
	if selected_action == null and heal_action != null and heal_action.is_ready():
		var any_injured: Hero = _find_injured_ally(1.0)
		if any_injured != null and heal_action.can_execute(self, any_injured):
			target_char = any_injured
			selected_action = heal_action

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
			Audio.play_melee_swoosh()
		elif selected_action is RangedAction:
			ranged_attack_started.emit(animation)
		elif selected_action is HealAction:
			heal_cast_started.emit(animation)


func _is_valid_enemy_target(enemy: Enemy) -> bool:
	if enemy == null or not is_instance_valid(enemy) or not enemy.visible:
		return false
	return not enemy.is_dead and enemy.health > 0.0 and not enemy.is_queued_for_deletion()


func _find_closest_enemy() -> Enemy:
	var closest: Enemy = null
	var min_dist_sq: float = INF
	var max_detection: float = get_detection_range()
	var max_detection_sq: float = max_detection * max_detection
	var leash: float = get_current_leash()
	var leash_sq: float = leash * leash
	var anchor_pos: Vector2 = get_anchor_position()
	var enforce_leash: bool = not is_player and not can_ranged and leash > 0.0

	for node: Node in get_tree().get_nodes_in_group(_GROUP_ENEMIES):
		var enemy: Enemy = node as Enemy
		if not _is_valid_enemy_target(enemy):
			continue

		var dist_to_self_sq: float = global_position.distance_squared_to(enemy.global_position)
		if dist_to_self_sq >= min_dist_sq:
			continue

		if enforce_leash:
			if anchor_pos.distance_squared_to(enemy.global_position) > leash_sq:
				continue
		elif dist_to_self_sq > max_detection_sq:
			continue

		min_dist_sq = dist_to_self_sq
		closest = enemy

	return closest


func _find_injured_ally(max_health_ratio: float = HEAL_TRIAGE_THRESHOLD) -> Hero:
	var best_target: Hero = null
	var lowest_health_ratio: float = max_health_ratio
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

		var ratio: float = ally.health / ally.max_health
		if ratio > max_health_ratio:
			continue

		var dist_sq: float = global_position.distance_squared_to(ally.global_position)
		if dist_sq > max_detection_sq:
			continue

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
		var should_hit: bool = false
		var hit_damage: float = melee.heavy_damage if is_heavy else melee.damage

		if is_heavy and not melee2_hit_frames.is_empty():
			for hit_frame: int in melee2_hit_frames:
				if frame >= hit_frame and not _hits_applied_frames.has(hit_frame):
					_hits_applied_frames.append(hit_frame)
					should_hit = true
					break
		elif not _hit_applied_this_attack and frame >= 2:
			_hit_applied_this_attack = true
			should_hit = true

		if should_hit:
			var applied_kb: float = melee.heavy_knockback if is_heavy else melee.knockback
			if _hero_vfx != null and (is_heavy or applied_kb >= 140.0):
				var strike_dir: Vector2 = (active_target.global_position - global_position).normalized()
				if strike_dir.length_squared() < 0.01:
					strike_dir = Vector2.LEFT if flip_h else Vector2.RIGHT
				_hero_vfx.trigger_knockback_strike(strike_dir, is_heavy)
			for node: Node in get_tree().get_nodes_in_group(_GROUP_ENEMIES):
				var enemy: Enemy = node as Enemy
				if not _is_valid_enemy_target(enemy):
					continue
				if melee.apply_hit(self, enemy):
					enemy_hit.emit(enemy, hit_damage, is_heavy)
					if melee.hit_effect_scene != null:
						var effect: Projectile = melee.hit_effect_scene.instantiate() as Projectile
						if effect != null:
							effect.global_position = enemy.global_position
							spawn_projectile(effect)
	elif current_action is RangedAction and active_target != null and not _hit_applied_this_attack:
		var ranged: RangedAction = current_action as RangedAction
		if frame >= ranged.projectile_frame:
			_hit_applied_this_attack = true
			if _hero_vfx != null and ranged.knockback >= 140.0:
				var shot_dir: Vector2 = (active_target.global_position - global_position).normalized()
				if shot_dir.length_squared() < 0.01:
					shot_dir = Vector2.LEFT if flip_h else Vector2.RIGHT
				_hero_vfx.trigger_knockback_strike(shot_dir, false)
			var proj: Projectile = ranged.spawn_projectile(self, active_target)
			if proj != null:
				spawn_projectile(proj)
				var is_magic: bool = hero_data != null and hero_data.id != &"archer"
				Audio.play_ranged_attack(is_magic)
	elif current_action is HealAction and active_target != null and not _hit_applied_this_attack:
		var heal_act: HealAction = current_action as HealAction
		if frame >= heal_act.cast_frame:
			_hit_applied_this_attack = true
			heal_act.apply_heal(self, active_target)
			var effect: Projectile = heal_act.spawn_heal_effect(self, active_target)
			if effect != null:
				spawn_projectile(effect)
			Audio.play_ranged_attack(true)
			ally_healed.emit(active_target, heal_act.heal_amount)


func _on_death() -> void:
	super._on_death()
	if _hero_vfx != null:
		_hero_vfx.trigger_death()
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
	if _pos_history.size() < HISTORY_CAPACITY:
		_pos_history.resize(HISTORY_CAPACITY)
		_time_history.resize(HISTORY_CAPACITY)

	_pos_history[_history_head] = position
	_time_history[_history_head] = _elapsed_time
	_history_head = (_history_head + 1) % HISTORY_CAPACITY
	if _history_count < HISTORY_CAPACITY:
		_history_count += 1

	var cutoff_time: float = _elapsed_time - MAX_HISTORY_DURATION
	while _history_count > 2:
		var oldest_idx: int = (_history_head - _history_count + HISTORY_CAPACITY) % HISTORY_CAPACITY
		if _time_history[oldest_idx] < cutoff_time:
			_history_count -= 1
		else:
			break


func get_delayed_position(delay: float) -> Vector2:
	if _history_count == 0 or delay <= 0.001:
		return position

	var target_time: float = _elapsed_time - delay
	for step: int in range(_history_count - 1):
		var idx1: int = (_history_head - 1 - step + HISTORY_CAPACITY) % HISTORY_CAPACITY
		var idx2: int = (_history_head - 2 - step + HISTORY_CAPACITY) % HISTORY_CAPACITY
		var t1: float = _time_history[idx1]
		var t2: float = _time_history[idx2]
		if t1 >= target_time and target_time >= t2:
			var span: float = t1 - t2
			if span <= 0.0001:
				return _pos_history[idx1]
			return _pos_history[idx1].lerp(_pos_history[idx2], (t1 - target_time) / span)

	var oldest_idx: int = (_history_head - _history_count + HISTORY_CAPACITY) % HISTORY_CAPACITY
	return _pos_history[oldest_idx]


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
	if _health_bar != null:
		_health_bar.visible = is_recruited
		_health_bar.set_level(level if (is_recruited and not is_dead) else 0)
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


func is_visible_on_screen() -> bool:
	return is_player or _is_on_screen


func _update_level_display() -> void:
	if _health_bar != null:
		var is_recruited: bool = is_player or squad_member != null
		_health_bar.set_level(level if (is_recruited and not is_dead) else 0)
