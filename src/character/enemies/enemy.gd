# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Enemy
extends Character

signal attacked(target: Hero, damage_amount: float)

enum State {
	PATROL,
	CHASE,
	ATTACK,
}

const _GROUP_ENEMIES: StringName = &"enemies"
const WAYPOINT_ARRIVE_DIST_SQ: float = 64.0
const PATROL_TIMEOUT: float = 10.0
const KNOCKBACK_DECAY: float = 600.0
const SLOW_MODULATE: Color = Color(0.45, 0.75, 1.35, 1.0)
const ENEMY_HURTBOX_RADIUS: float = 10.0

@export var detection_range: float = 140.0
@export var attack_cooldown: float = 1.2
@export var damage: float = 10.0

var combat_actions: Array[CombatAction] = []
var current_action: CombatAction = null
var current_state: State = State.PATROL
var map: Map = null
var target: Hero = null
var home_room: Rect2i = Rect2i()
var is_on_screen: bool = false

var _navigator: SquadNavigator = SquadNavigator.new()
var _patrol_destination: Vector2 = Vector2.ZERO
var _patrol_timer: float = 0.0
var _idle_wait_timer: float = 0.0
var _knockback_velocity: Vector2 = Vector2.ZERO
var _notifier: VisibleOnScreenNotifier2D = null
var _slow_timer: float = 0.0
var _slow_multiplier: float = 1.0


func _ready() -> void:
	super._ready()
	if _health_bar != null:
		_health_bar.set_fill_color(HealthBar.DEFAULT_ENEMY_COLOR)
	add_to_group(_GROUP_ENEMIES)
	collision_layer = 8
	collision_mask = 1 | 2 | 4 | 8

	hurtbox = Hurtbox.new(self, ENEMY_HURTBOX_RADIUS, Vector2(0.0, 0.0))
	hurtbox.collision_layer = 128
	hurtbox.collision_mask = 0
	add_child(hurtbox)

	_notifier = VisibleOnScreenNotifier2D.new()
	_notifier.rect = Rect2(-64.0, -64.0, 128.0, 128.0)
	_notifier.screen_entered.connect(_on_screen_entered)
	_notifier.screen_exited.connect(_on_screen_exited)
	add_child(_notifier)
	is_on_screen = _notifier.is_on_screen()
	if not is_on_screen:
		_set_sleeping(true)


func _set_sleeping(sleeping: bool) -> void:
	set_physics_process(not sleeping)
	set_process(not sleeping)
	if sleeping:
		_animated_sprite.pause()
		disable_collisions()
	else:
		if not _animated_sprite.is_playing():
			_animated_sprite.play()
		if not is_dead:
			enable_collisions()


func _physics_process(delta: float) -> void:
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

	if _knockback_velocity.length_squared() > 1.0:
		_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)

	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_slow_timer = 0.0
			_slow_multiplier = 1.0
			_base_modulate = Color.WHITE
			_animated_sprite.modulate = Color.WHITE

	_check_combat_actions()

	match current_state:
		State.PATROL:
			_process_patrol(delta)
		State.CHASE, State.ATTACK:
			_process_chase(delta)


func _on_screen_entered() -> void:
	is_on_screen = true
	_set_sleeping(false)


func _on_screen_exited() -> void:
	is_on_screen = false
	if current_state == State.PATROL:
		_set_sleeping(true)


func set_target_candidate(hero_candidate: Hero) -> void:
	if hero_candidate == null or not is_instance_valid(hero_candidate) or hero_candidate.is_dead:
		return

	var dist_sq: float = global_position.distance_squared_to(hero_candidate.global_position)
	if dist_sq > detection_range * detection_range:
		return

	if not SquadNavigator.has_line_of_sight(self, hero_candidate.global_position):
		return

	_set_sleeping(false)

	if target == null:
		target = hero_candidate
		current_state = State.CHASE
		_navigator.reset()
	elif target != hero_candidate and is_instance_valid(target):
		var current_dist_sq: float = global_position.distance_squared_to(target.global_position)
		if dist_sq < current_dist_sq * 0.85:
			target = hero_candidate
			_navigator.reset()


func apply_knockback(force: Vector2) -> void:
	_set_sleeping(false)
	_knockback_velocity = force


func apply_slow(factor: float, duration: float) -> void:
	if is_dead or duration <= 0.0:
		return
	_set_sleeping(false)
	_slow_multiplier = clampf(factor, 0.1, 1.0)
	_slow_timer = maxf(_slow_timer, duration)
	_base_modulate = SLOW_MODULATE
	_animated_sprite.modulate = SLOW_MODULATE


func take_damage(amount: float) -> void:
	_set_sleeping(false)
	super.take_damage(amount)


func apply_melee_damage(attack_target: Hero, damage_amount: float) -> void:
	if attack_target != null and is_instance_valid(attack_target):
		attack_target.take_damage(damage_amount)
		attacked.emit(attack_target, damage_amount)


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
	if target == null or not is_instance_valid(target) or target.health <= 0.0 or target.is_dead:
		target = null
		current_state = State.PATROL
		_pick_new_patrol_destination()
		if not is_on_screen:
			_set_sleeping(true)
		return

	var dist_to_target: float = global_position.distance_to(target.global_position)

	if dist_to_target > detection_range * 1.8:
		target = null
		current_state = State.PATROL
		_pick_new_patrol_destination()
		if not is_on_screen:
			_set_sleeping(true)
		return

	var diff_x: float = target.global_position.x - global_position.x
	if absf(diff_x) > 2.0:
		flip_h = diff_x < 0.0

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


func _can_reach_target() -> bool:
	if target == null or not is_instance_valid(target) or target.health <= 0.0 or target.is_dead:
		return false
	for action: CombatAction in combat_actions:
		if action.can_reach(self, target):
			return true
	return false


func _check_combat_actions() -> void:
	if combat_state != CombatState.READY or target == null or not is_instance_valid(target) or target.health <= 0.0:
		return

	for action: CombatAction in combat_actions:
		if action.can_execute(self, target):
			current_action = action
			combat_state = CombatState.ATTACKING
			action.execute(self, target)
			break


func _pick_new_patrol_destination() -> void:
	_patrol_timer = PATROL_TIMEOUT
	_navigator.reset()

	if map == null:
		_patrol_destination = global_position
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
			_patrol_destination = map.clamp_to_walkable(map.map_to_local(target_cell))
			return

	var local_offset: Vector2 = Vector2(randf_range(-60.0, 60.0), randf_range(-60.0, 60.0))
	_patrol_destination = map.clamp_to_walkable(global_position + local_offset)


func _on_death() -> void:
	set_physics_process(false)
	remove_from_group(_GROUP_ENEMIES)
	_slow_timer = 0.0
	_slow_multiplier = 1.0
	_base_modulate = Color.WHITE
	_animated_sprite.modulate = Color.WHITE
	super._on_death()
	if not _animated_sprite.animation_finished.is_connected(queue_free):
		_animated_sprite.animation_finished.connect(queue_free, CONNECT_ONE_SHOT)


func _on_animation_finished() -> void:
	super._on_animation_finished()
	if is_dead:
		return
	if current_action is MeleeAction and target != null:
		var melee: MeleeAction = current_action as MeleeAction
		if melee.apply_hit(self, target):
			attacked.emit(target, melee.damage)
	elif current_action is RangedAction and target != null:
		var ranged: RangedAction = current_action as RangedAction
		var proj: Projectile = ranged.spawn_projectile(self, target)
		if proj != null:
			spawn_projectile(proj)
