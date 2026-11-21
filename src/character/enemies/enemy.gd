# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Enemy
extends Character

signal attacked(target: Hero, damage_amount: float)
@warning_ignore("unused_signal")
signal minion_summon_requested(pos: Vector2, room: Rect2i, enemy_level: int)

enum State {
	PATROL,
	CHASE,
	ATTACK,
}

const _GROUP_ENEMIES: StringName = &"enemies"
const _GROUP_HEROES: StringName = &"heroes"
const WAYPOINT_ARRIVE_DIST_SQ: float = 64.0
const PATROL_TIMEOUT: float = 10.0
const KNOCKBACK_DECAY: float = 600.0
const SLOW_MODULATE: Color = Color(0.45, 0.75, 1.35, 1.0)
const MINION_MODULATE: Color = Color(0.85, 0.9, 1.1, 0.85)
const BURN_TICK_INTERVAL: float = 0.5
const ENEMY_HURTBOX_RADIUS: float = 10.0
const LEVEL_COLOR: Color = Color(1.0, 0.45, 0.35, 1.0)
const TELEGRAPH_COLOR: Color = Color(1.0, 1.0, 1.0, 0.35)
const TELEGRAPH_LOCKED_COLOR: Color = Color(1.0, 1.0, 1.0, 0.85)
const TELEGRAPH_LOCK_TIME: float = 0.25
const KNIGHT_TAUNT_WEIGHT: float = 0.06

@export var level: int = 1

var enemy_id: StringName = &""
var detection_range: float = 140.0
var attack_cooldown: float = 1.2
var damage: float = 10.0
var xp_value: float = 10.0
var melee_damage: float = 8.0
var melee_vertical_tolerance: float = 12.0
var can_heavy_melee: bool = false
var melee2_damage: float = 20.0
var melee2_cooldown: float = 3.5
var melee2_chance: float = 0.35
var ranged_projectile_scene: PackedScene = null
var requires_horizontal_alignment: bool = false
var horizontal_alignment_tolerance: float = 16.0
var can_summon: bool = false
var summon_range: float = 180.0
var summon_count: int = 2
var kite_distance: float = 0.0
var is_minion: bool = false

var current_state: State = State.PATROL
var map: Map = null
var target: Hero = null
var attack_target: Hero = null
var home_room: Rect2i = Rect2i()
var active_telegraph: Telegraph = null

var _navigator: SquadNavigator = SquadNavigator.new()
var _patrol_destination: Vector2 = Vector2.ZERO
var _patrol_timer: float = 0.0
var _idle_wait_timer: float = 0.0
var _knockback_velocity: Vector2 = Vector2.ZERO
var _slow_timer: float = 0.0
var _slow_multiplier: float = 1.0
var _stun_timer: float = 0.0
var _burn_timer: float = 0.0
var _burn_dps: float = 0.0
var _burn_tick_timer: float = 0.0
var _burn_source: Hero = null
var _mark_timer: float = 0.0
var _mark_bonus: float = 0.0
var _is_summoning_in: bool = false

@onready var _status_vfx: StatusVfx = $StatusVfx


func _ready() -> void:
	has_footsteps = false
	if enemy_id != &"":
		var data: EnemyData = EnemyData.get_enemy(enemy_id)
		if data != null:
			data.apply_to_enemy(self, level)
	super._ready()
	_health_bar.set_fill_color(HealthBar.DEFAULT_ENEMY_COLOR)
	_health_bar.set_level_color(LEVEL_COLOR)
	_health_bar.set_level(level)
	add_to_group(_GROUP_ENEMIES)
	collision_layer = 8
	collision_mask = 1 | 2 | 4 | 8

	hurtbox.setup(self, ENEMY_HURTBOX_RADIUS, Vector2.ZERO, 128)
	_status_vfx.head_y = _health_bar.position.y + 3.0
	_status_vfx.set_on_screen(is_on_screen)

	set_process(false)
	if not is_on_screen:
		_set_sleeping(true)
	_setup_actions()


func sync_screen_state(camera_pos: Vector2) -> void:
	var diff: Vector2 = (global_position - camera_pos).abs()
	is_on_screen = diff.x <= 384.0 and diff.y <= 244.0
	_status_vfx.set_on_screen(is_on_screen)
	if is_dead:
		return
	if not is_on_screen and current_state == State.PATROL and not is_burning():
		_set_sleeping(true)
	else:
		_set_sleeping(false)


func _set_sleeping(sleeping: bool) -> void:
	set_physics_process(not sleeping)
	set_process(false)
	if sleeping:
		_cancel_telegraph()
		_animated_sprite.pause()
		_status_vfx.set_on_screen(false)
		_status_vfx.set_process(false)
		disable_collisions()
	else:
		if not _is_stunned() and not _animated_sprite.is_playing():
			_animated_sprite.play()
		_status_vfx.set_on_screen(is_on_screen)
		_status_vfx.set_statuses(_is_stunned(), is_burning(), is_slowed(), is_marked())
		if not is_dead:
			enable_collisions()


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_update_combat_cooldowns(delta)

	if _knockback_velocity.length_squared() > 1.0:
		_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)

	var status_changed: bool = false

	if _stun_timer > 0.0:
		_stun_timer -= delta
		if _stun_timer <= 0.0:
			_stun_timer = 0.0
			status_changed = true

	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_slow_timer = 0.0
			_slow_multiplier = 1.0
			status_changed = true

	if _burn_timer > 0.0:
		_burn_timer -= delta
		_burn_tick_timer -= delta
		if _burn_tick_timer <= 0.0:
			_burn_tick_timer += BURN_TICK_INTERVAL
			var tick_dmg: float = get_effective_damage_taken(_burn_dps * BURN_TICK_INTERVAL)
			if tick_dmg > 0.0 and not is_dead:
				var src: Hero = _burn_source
				_status_vfx.trigger_burn_pulse()
				take_damage(tick_dmg, false)
				if src != null:
					src.enemy_hit.emit(self, tick_dmg, false)
				if is_dead:
					return
		if _burn_timer <= 0.0:
			_burn_timer = 0.0
			_burn_dps = 0.0
			_burn_tick_timer = 0.0
			_burn_source = null
			status_changed = true

	if _mark_timer > 0.0:
		_mark_timer -= delta
		if _mark_timer <= 0.0:
			_mark_timer = 0.0
			_mark_bonus = 0.0
			status_changed = true

	if status_changed:
		_update_status_visuals()

	if _is_summoning_in:
		return

	if _is_stunned():
		velocity = _knockback_velocity
		move_and_slide()
		return

	_check_combat_actions()

	match current_state:
		State.PATROL:
			_process_patrol(delta)
		State.CHASE, State.ATTACK:
			_process_chase(delta)


func _on_screen_visibility_changed() -> void:
	_status_vfx.set_on_screen(is_on_screen)
	if is_dead:
		return
	if is_on_screen:
		_set_sleeping(false)
	elif current_state == State.PATROL and not is_burning():
		_set_sleeping(true)


func play_summon_intro() -> void:
	if is_dead:
		return
	is_minion = true
	_is_summoning_in = true
	_set_sleeping(false)
	scale = Vector2(0.85, 0.85)
	_base_modulate = MINION_MODULATE
	_animated_sprite.modulate = _base_modulate
	# Minions are fragile fodder: lower health and damage, disable heavy attacks
	max_health = maxf(15.0, roundf(max_health * 0.4))
	health = max_health
	damage = maxf(2.0, roundf(damage * 0.5))
	melee_damage = maxf(2.0, roundf(melee_damage * 0.5))
	can_heavy_melee = false
	xp_value = maxf(2.0, roundf(xp_value * 0.35))
	for action: CombatAction in combat_actions:
		if action is MeleeAction:
			var melee: MeleeAction = action as MeleeAction
			melee.damage = melee_damage
			melee.can_heavy = false
		elif action is RangedAction:
			var ranged: RangedAction = action as RangedAction
			ranged.damage = damage
	_health_bar.update_health(health, max_health)
	play(ANIM_SUMMON)


func get_effective_target_dist_sq(hero_candidate: Hero) -> float:
	var dist_sq: float = global_position.distance_squared_to(hero_candidate.global_position)
	if hero_candidate.hero_data != null and hero_candidate.hero_data.id == &"knight":
		return dist_sq * KNIGHT_TAUNT_WEIGHT
	return dist_sq


func set_target_candidate(hero_candidate: Hero) -> void:
	if not CombatAction.is_valid_target(hero_candidate):
		return

	var dist_sq: float = global_position.distance_squared_to(hero_candidate.global_position)
	if dist_sq > detection_range * detection_range:
		return

	if not SquadNavigator.has_line_of_sight(self, hero_candidate.global_position):
		return

	_set_sleeping(false)

	if not CombatAction.is_valid_target(target):
		target = hero_candidate
		current_state = State.CHASE
		_navigator.reset()
	elif target != hero_candidate:
		var candidate_eff_sq: float = get_effective_target_dist_sq(hero_candidate)
		var current_eff_sq: float = get_effective_target_dist_sq(target)
		if candidate_eff_sq < current_eff_sq * 0.85:
			target = hero_candidate
			_navigator.reset()


func clear_hero_references(hero: Hero) -> void:
	if target == hero:
		target = null
	if attack_target == hero:
		attack_target = null
	if _burn_source == hero:
		_burn_source = null
	if active_telegraph is TelegraphLine:
		var line: TelegraphLine = active_telegraph as TelegraphLine
		if line.target == hero:
			line.target = null


func apply_knockback(force: Vector2) -> void:
	if is_dead or not visible:
		return
	_set_sleeping(false)
	_knockback_velocity = force
	_status_vfx.trigger_knockback(force)


func apply_slow(factor: float, duration: float) -> void:
	if is_dead or not visible or duration <= 0.0:
		return
	_set_sleeping(false)
	_slow_multiplier = clampf(factor, 0.1, 1.0)
	_slow_timer = maxf(_slow_timer, duration)
	_update_status_visuals()


func apply_stun(duration: float) -> void:
	if is_dead or not visible or duration <= 0.0:
		return
	_set_sleeping(false)
	_stun_timer = maxf(_stun_timer, duration)
	if combat_state == CombatState.ATTACKING:
		_cancel_telegraph()
		combat_state = CombatState.COOLDOWN
		current_action = null
		attack_target = null
		play(ANIM_IDLE)
	_update_status_visuals()


func apply_burn(dps: float, duration: float, source_hero: Hero = null) -> void:
	if is_dead or not visible or duration <= 0.0 or dps <= 0.0:
		return
	_set_sleeping(false)
	if _burn_timer <= 0.0:
		_burn_tick_timer = BURN_TICK_INTERVAL
	_burn_dps = maxf(_burn_dps, dps)
	_burn_timer = maxf(_burn_timer, duration)
	if source_hero != null:
		_burn_source = source_hero
	_update_status_visuals()


func apply_mark(bonus: float, duration: float) -> void:
	if is_dead or not visible or duration <= 0.0 or bonus <= 0.0:
		return
	_set_sleeping(false)
	_mark_bonus = maxf(_mark_bonus, bonus)
	_mark_timer = maxf(_mark_timer, duration)
	_update_status_visuals()


func apply_taunt(taunter: Hero) -> void:
	if is_dead or not visible or not CombatAction.is_valid_target(taunter):
		return
	_set_sleeping(false)
	if target != taunter:
		target = taunter
		current_state = State.CHASE
		_navigator.reset()


func is_marked() -> bool:
	return _mark_timer > 0.0


func get_effective_damage_taken(raw_damage: float) -> float:
	if _mark_timer > 0.0 and _mark_bonus > 0.0:
		return raw_damage * (1.0 + _mark_bonus)
	return raw_damage


func is_burning() -> bool:
	return _burn_timer > 0.0


func is_slowed() -> bool:
	return _slow_timer > 0.0


func _is_stunned() -> bool:
	return _stun_timer > 0.0


func is_engaged() -> bool:
	if is_dead or not visible:
		return false
	return current_state == State.CHASE or current_state == State.ATTACK or CombatAction.is_valid_target(target)


func _update_status_visuals() -> void:
	_status_vfx.set_statuses(_is_stunned(), is_burning(), is_slowed(), is_marked())
	if _is_stunned():
		_animated_sprite.pause()
	elif not _animated_sprite.is_playing() and not is_dead:
		_animated_sprite.play()

	if is_slowed():
		_base_modulate = SLOW_MODULATE
		_animated_sprite.modulate = SLOW_MODULATE
	elif is_minion:
		_base_modulate = MINION_MODULATE
		_animated_sprite.modulate = MINION_MODULATE
	else:
		_base_modulate = Color.WHITE
		_animated_sprite.modulate = Color.WHITE


func take_damage(amount: float, flash_hurt: bool = true) -> void:
	if is_dead or not visible:
		return
	_set_sleeping(false)
	super.take_damage(amount, flash_hurt)


func _process_patrol(delta: float) -> void:
	if _idle_wait_timer > 0.0:
		_idle_wait_timer -= delta
		velocity = _knockback_velocity
		if _knockback_velocity.length_squared() > 1.0:
			move_and_slide()
		else:
			update_visuals(Vector2.ZERO)
		return

	_patrol_timer -= delta

	if _patrol_destination == Vector2.ZERO or _patrol_timer <= 0.0:
		_pick_new_patrol_destination()

	var dist_to_patrol_sq: float = global_position.distance_squared_to(_patrol_destination)
	if dist_to_patrol_sq <= WAYPOINT_ARRIVE_DIST_SQ:
		_idle_wait_timer = randf_range(1.5, 3.5)
		_pick_new_patrol_destination()
		velocity = _knockback_velocity
		if _knockback_velocity.length_squared() > 1.0:
			move_and_slide()
		else:
			update_visuals(Vector2.ZERO)
		return

	var waypoint: Vector2 = _navigator.get_next_waypoint(self, _patrol_destination, map, delta)
	var move_vec: Vector2 = (waypoint - global_position).normalized()
	velocity = (move_vec * speed * _slow_multiplier) + _knockback_velocity
	move_and_slide()
	update_visuals(velocity * delta)


func _process_chase(delta: float) -> void:
	if not CombatAction.is_valid_target(target):
		target = null
		attack_target = null
		current_state = State.PATROL
		_pick_new_patrol_destination()
		if not is_on_screen:
			_set_sleeping(true)
		return

	var dist_to_target: float = global_position.distance_to(target.global_position)

	if dist_to_target > detection_range * 1.8:
		target = null
		attack_target = null
		current_state = State.PATROL
		_pick_new_patrol_destination()
		if not is_on_screen:
			_set_sleeping(true)
		return

	if _try_kite_away(dist_to_target, delta):
		return

	if not CombatAction.is_valid_target(attack_target):
		attack_target = null
	var look_target: Hero = attack_target if (combat_state == CombatState.ATTACKING and attack_target != null) else target
	CombatAction.face_target(self, look_target, 2.0)

	if combat_state == CombatState.ATTACKING:
		velocity = _knockback_velocity
		if _knockback_velocity.length_squared() > 1.0:
			move_and_slide()
		return

	if _can_reach_target():
		velocity = _knockback_velocity
		if _knockback_velocity.length_squared() > 1.0:
			move_and_slide()
		else:
			update_visuals(Vector2.ZERO)
		return

	var waypoint: Vector2 = _navigator.get_next_waypoint(self, target.global_position, map, delta)
	var move_vec: Vector2 = (waypoint - global_position).normalized()
	velocity = (move_vec * speed * _slow_multiplier) + _knockback_velocity
	move_and_slide()
	update_visuals(velocity * delta)


func _try_kite_away(dist_to_target: float, delta: float) -> bool:
	var too_close_to_shoot: bool = can_ranged and not can_melee and dist_to_target < ranged_min_range
	if kite_distance <= 0.0 or (combat_state != CombatState.COOLDOWN and not too_close_to_shoot) or dist_to_target >= kite_distance:
		return false
	CombatAction.face_target(self, target, 2.0)
	var away_dir: Vector2 = (global_position - target.global_position).normalized()
	if away_dir.length_squared() < 0.01:
		away_dir = Vector2.LEFT if not flip_h else Vector2.RIGHT
	velocity = (away_dir * speed * _slow_multiplier) + _knockback_velocity
	move_and_slide()
	update_visuals(velocity * delta)
	return true


func _can_reach_target() -> bool:
	if not CombatAction.is_valid_target(target):
		return false
	for action: CombatAction in combat_actions:
		if action.can_reach(self, target):
			return true
	return false


func _check_combat_actions() -> void:
	if combat_state != CombatState.READY or not CombatAction.is_valid_target(target):
		return

	for action: CombatAction in combat_actions:
		if action.can_execute(self, target):
			current_action = action
			attack_target = target
			combat_state = CombatState.ATTACKING
			action.execute(self, target)
			return

	for action: CombatAction in combat_actions:
		if action is MeleeAction and action.is_ready():
			var melee: MeleeAction = action as MeleeAction
			var blocker: Hero = _find_blocking_hero(melee)
			if blocker != null:
				current_action = melee
				attack_target = blocker
				combat_state = CombatState.ATTACKING
				melee.execute(self, blocker)
				return


func _find_blocking_hero(melee: MeleeAction) -> Hero:
	var best_blocker: Hero = null
	var min_dist_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group(_GROUP_HEROES):
		var hero: Hero = node as Hero
		if not CombatAction.is_valid_target(hero):
			continue
		if not hero.is_player and hero.squad_member == null:
			continue
		if not melee.can_reach(self, hero):
			continue
		var dist_sq: float = global_position.distance_squared_to(hero.global_position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			best_blocker = hero
	return best_blocker


func _pick_new_patrol_destination() -> void:
	_patrol_timer = PATROL_TIMEOUT
	_navigator.reset()

	if map == null:
		_patrol_destination = global_position
		return

	var current_cell: Vector2i = map.local_to_map(global_position)
	if not map.is_cell_walkable(current_cell):
		_patrol_destination = global_position
		_idle_wait_timer = randf_range(0.6, 1.4)
		return

	if home_room != Rect2i():
		var min_x: int = home_room.position.x + 2
		var max_x: int = home_room.position.x + home_room.size.x - 3
		var min_y: int = home_room.position.y + 2
		var max_y: int = home_room.position.y + home_room.size.y - 3
		if max_x >= min_x and max_y >= min_y:
			var rx: int = randi_range(min_x, max_x)
			var ry: int = randi_range(min_y, max_y)
			var target_cell: Vector2i = Vector2i(rx, ry)
			if not map.is_cell_walkable(target_cell):
				_patrol_destination = global_position
				_idle_wait_timer = randf_range(0.6, 1.4)
				return
			_patrol_destination = map.map_to_local(target_cell)
			return

	var local_offset: Vector2 = Vector2(randf_range(-60.0, 60.0), randf_range(-60.0, 60.0))
	_patrol_destination = map.clamp_to_walkable(global_position + local_offset)


func set_level(new_level: int) -> void:
	if level == new_level and not combat_actions.is_empty():
		health = max_health
		_health_bar.set_level(level)
		_health_bar.update_health(health, max_health)
		return
	level = new_level
	if enemy_id != &"":
		var data: EnemyData = EnemyData.get_enemy(enemy_id)
		data.apply_to_enemy(self, level)
	if combat_actions.is_empty():
		_setup_actions()
	else:
		_refresh_actions()
	_health_bar.set_level_color(LEVEL_COLOR)
	_health_bar.set_level(level)
	_health_bar.update_health(health, max_health)


func _setup_actions() -> void:
	if can_melee:
		combat_actions.append(MeleeAction.new())
	if can_ranged:
		combat_actions.append(RangedAction.new())
	if can_summon:
		combat_actions.append(SummonAction.new())
	_refresh_actions()


func _refresh_actions() -> void:
	for action: CombatAction in combat_actions:
		if action is MeleeAction:
			var melee: MeleeAction = action as MeleeAction
			melee.range_distance = melee_range
			melee.vertical_tolerance = melee_vertical_tolerance
			melee.damage = melee_damage
			melee.cooldown = attack_cooldown
			melee.can_heavy = can_heavy_melee
			melee.heavy_damage = melee2_damage
			melee.heavy_cooldown = melee2_cooldown
			melee.heavy_chance = melee2_chance
			melee.leash_distance = 0.0
		elif action is RangedAction:
			var ranged: RangedAction = action as RangedAction
			ranged.projectile_scene = ranged_projectile_scene
			ranged.range_distance = ranged_range
			ranged.min_range_distance = ranged_min_range
			ranged.damage = damage
			ranged.cooldown = attack_cooldown
			ranged.requires_horizontal_alignment = requires_horizontal_alignment
			ranged.horizontal_tolerance = horizontal_alignment_tolerance
			ranged.check_line_of_sight = true
			ranged.leash_distance = 0.0
			ranged.show_telegraph = true
			ranged.telegraph_color = TELEGRAPH_COLOR
			ranged.telegraph_locked_color = TELEGRAPH_LOCKED_COLOR
			ranged.telegraph_lock_time = TELEGRAPH_LOCK_TIME
		elif action is SummonAction:
			var summon: SummonAction = action as SummonAction
			summon.range_distance = summon_range
			summon.cooldown = attack_cooldown
			summon.summon_count = summon_count
			summon.check_line_of_sight = true
			summon.leash_distance = 0.0


func deactivate_for_pool() -> void:
	if is_in_group(_GROUP_ENEMIES):
		remove_from_group(_GROUP_ENEMIES)
	target = null
	attack_target = null
	current_action = null
	_burn_source = null
	_is_summoning_in = false
	_knockback_velocity = Vector2.ZERO
	_set_sleeping(true)


func reset_for_pool() -> void:
	scale = Vector2.ONE
	if is_minion:
		level = -1
	is_minion = false
	health = max_health
	is_dead = false
	_is_summoning_in = false
	movement_state = MovementState.IDLE
	combat_state = CombatState.READY
	current_state = State.PATROL
	target = null
	attack_target = null
	current_action = null
	_patrol_destination = Vector2.ZERO
	_patrol_timer = 0.0
	_idle_wait_timer = randf_range(0.1, 0.8)
	_stun_timer = 0.0
	_slow_timer = 0.0
	_slow_multiplier = 1.0
	_burn_timer = 0.0
	_burn_dps = 0.0
	_burn_tick_timer = 0.0
	_burn_source = null
	_mark_timer = 0.0
	_mark_bonus = 0.0
	_knockback_velocity = Vector2.ZERO
	_navigator.reset()
	_base_modulate = Color.WHITE
	_status_vfx.clear()
	_animated_sprite.modulate = Color.WHITE
	_animated_sprite.play(ANIM_IDLE)
	_health_bar.visible = true
	_health_bar.update_health(health, max_health)
	visible = true
	if not is_in_group(_GROUP_ENEMIES):
		add_to_group(_GROUP_ENEMIES)
	_set_sleeping(true)


func _cancel_telegraph() -> void:
	if active_telegraph != null:
		active_telegraph.cancel()
		active_telegraph = null
	if current_action is RangedAction:
		(current_action as RangedAction).cancel_telegraph()


func _on_death() -> void:
	_cancel_telegraph()
	_is_summoning_in = false
	target = null
	attack_target = null
	current_action = null
	set_physics_process(false)
	remove_from_group(_GROUP_ENEMIES)
	_stun_timer = 0.0
	_slow_timer = 0.0
	_slow_multiplier = 1.0
	_burn_timer = 0.0
	_burn_dps = 0.0
	_burn_tick_timer = 0.0
	_burn_source = null
	_mark_timer = 0.0
	_mark_bonus = 0.0
	_status_vfx.clear()
	_base_modulate = Color.WHITE
	_animated_sprite.modulate = Color.WHITE
	super._on_death()
	if death_completed.get_connections().is_empty():
		if not _animated_sprite.animation_finished.is_connected(queue_free):
			_animated_sprite.animation_finished.connect(queue_free, CONNECT_ONE_SHOT)


func _on_animation_finished() -> void:
	if is_dead:
		_is_summoning_in = false
		super._on_animation_finished()
		return
	if _is_summoning_in:
		_is_summoning_in = false
		combat_state = CombatState.READY
		play(ANIM_IDLE)
		return
	super._on_animation_finished()
	var hit_target: Hero = null
	if CombatAction.is_valid_target(attack_target):
		hit_target = attack_target
	elif CombatAction.is_valid_target(target):
		hit_target = target
	attack_target = null
	if current_action is MeleeAction and hit_target != null:
		var melee: MeleeAction = current_action as MeleeAction
		if melee.apply_hit(self, hit_target):
			var applied_dmg: float = melee.heavy_damage if melee.current_is_heavy else melee.damage
			attacked.emit(hit_target, applied_dmg)
	elif current_action is RangedAction and hit_target != null:
		var ranged: RangedAction = current_action as RangedAction
		var proj: Projectile = ranged.spawn_projectile(self, hit_target)
		if proj != null:
			spawn_projectile(proj)
