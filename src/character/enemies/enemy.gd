# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Enemy
extends Character

signal attacked(target: Hero, damage_amount: float)
signal projectile_spawn_requested(projectile: Projectile)

enum State {
	PATROL,
	CHASE,
	ATTACK,
}

const _ANIM_ATTACK: StringName = &"attack"
const WAYPOINT_ARRIVE_DIST_SQ: float = 64.0
const PATROL_TIMEOUT: float = 10.0

@export var detection_range: float = 140.0
@export var attack_range: float = 22.0
@export var attack_cooldown: float = 1.2
@export var damage: float = 10.0

var current_state: State = State.PATROL
var map: Map = null
var target: Hero = null

var _navigator: SquadNavigator = SquadNavigator.new()
var _patrol_destination: Vector2 = Vector2.ZERO
var _patrol_timer: float = 0.0
var _idle_wait_timer: float = 0.0
var _attack_cooldown_timer: float = 0.0
var _is_attacking: bool = false


func _ready() -> void:
	super._ready()
	collision_layer = 8
	collision_mask = 1
	_animated_sprite.animation_finished.connect(_on_animation_finished)


func _physics_process(delta: float) -> void:
	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= delta

	match current_state:
		State.PATROL:
			_process_patrol(delta)
		State.CHASE:
			_process_chase(delta)
		State.ATTACK:
			_process_attack(delta)


func set_target_candidate(hero_candidate: Hero) -> void:
	if hero_candidate == null or not is_instance_valid(hero_candidate):
		return

	var dist_sq: float = global_position.distance_squared_to(hero_candidate.global_position)
	if dist_sq > detection_range * detection_range:
		return

	if not SquadNavigator.has_line_of_sight(self, hero_candidate.global_position):
		return

	if target == null:
		target = hero_candidate
		current_state = State.CHASE
		_navigator.reset()
	elif target != hero_candidate and is_instance_valid(target):
		var current_dist_sq: float = global_position.distance_squared_to(target.global_position)
		if dist_sq < current_dist_sq * 0.5:
			target = hero_candidate
			_navigator.reset()


func spawn_projectile(projectile: Projectile) -> void:
	projectile_spawn_requested.emit(projectile)


func apply_melee_damage(attack_target: Hero, damage_amount: float) -> void:
	if attack_target != null and is_instance_valid(attack_target):
		attack_target.take_damage(damage_amount)
		attacked.emit(attack_target, damage_amount)


func _process_patrol(delta: float) -> void:
	if _idle_wait_timer > 0.0:
		_idle_wait_timer -= delta
		velocity = Vector2.ZERO
		update_visuals(Vector2.ZERO)
		return

	_patrol_timer -= delta

	if _patrol_destination == Vector2.ZERO or _patrol_timer <= 0.0:
		_pick_new_patrol_destination()

	var dist_to_patrol_sq: float = global_position.distance_squared_to(_patrol_destination)
	if dist_to_patrol_sq <= WAYPOINT_ARRIVE_DIST_SQ:
		_idle_wait_timer = randf_range(1.5, 3.5)
		_pick_new_patrol_destination()
		velocity = Vector2.ZERO
		update_visuals(Vector2.ZERO)
		return

	var waypoint: Vector2 = _navigator.get_next_waypoint(self, _patrol_destination, map, delta)
	var move_vec: Vector2 = (waypoint - global_position).normalized()
	velocity = move_vec * speed
	move_and_slide()
	update_visuals(velocity * delta)


func _process_chase(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		target = null
		current_state = State.PATROL
		_pick_new_patrol_destination()
		return

	var dist_to_target: float = global_position.distance_to(target.global_position)

	if dist_to_target > detection_range * 1.8:
		target = null
		current_state = State.PATROL
		_pick_new_patrol_destination()
		return

	if _can_attack_target():
		velocity = Vector2.ZERO
		current_state = State.ATTACK
		_start_attack()
		return

	var waypoint: Vector2 = _navigator.get_next_waypoint(self, target.global_position, map, delta)
	var move_vec: Vector2 = (waypoint - global_position).normalized()
	velocity = move_vec * speed
	move_and_slide()
	update_visuals(velocity * delta)


func _process_attack(_delta: float) -> void:
	velocity = Vector2.ZERO

	if target == null or not is_instance_valid(target):
		_is_attacking = false
		target = null
		current_state = State.PATROL
		_pick_new_patrol_destination()
		return

	# Face towards target while attacking
	var diff_x: float = target.global_position.x - global_position.x
	if absf(diff_x) > 2.0:
		flip_h = diff_x < 0.0

	if not _is_attacking:
		if _attack_cooldown_timer <= 0.0:
			if _can_attack_target():
				_start_attack()
			else:
				current_state = State.CHASE
				_navigator.reset()
		else:
			if animation != _ANIM_IDLE:
				play(_ANIM_IDLE)


func _can_attack_target() -> bool:
	return target != null and global_position.distance_to(target.global_position) <= attack_range


func _get_attack_animation_name() -> StringName:
	return _ANIM_ATTACK


func _start_attack() -> void:
	_is_attacking = true
	_attack_cooldown_timer = attack_cooldown
	var anim_name: StringName = _get_attack_animation_name()
	if sprite_frames.has_animation(anim_name):
		play(anim_name)
	else:
		_perform_attack()
		_finish_attack()


func _perform_attack() -> void:
	pass


func _finish_attack() -> void:
	_is_attacking = false
	if animation != _ANIM_IDLE:
		play(_ANIM_IDLE)

	if target == null or not is_instance_valid(target):
		current_state = State.PATROL
		_pick_new_patrol_destination()
	elif not _can_attack_target():
		current_state = State.CHASE
		_navigator.reset()


func _pick_new_patrol_destination() -> void:
	_patrol_timer = PATROL_TIMEOUT
	_navigator.reset()

	var candidate_rooms: Array[Rect2i] = map.companion_rooms
	if candidate_rooms.is_empty():
		_patrol_destination = global_position
		return

	var random_room: Rect2i = candidate_rooms[randi() % candidate_rooms.size()]
	var target_cell: Vector2i = random_room.get_center()

	# Add slight jitter inside the room
	var half_size: Vector2i = Vector2i(int(float(random_room.size.x) / 3.0), int(float(random_room.size.y) / 3.0))
	var offset: Vector2i = Vector2i(randi_range(-half_size.x, half_size.x), randi_range(-half_size.y, half_size.y))
	target_cell += offset

	var target_world: Vector2 = map.map_to_local(target_cell)
	_patrol_destination = map.clamp_to_walkable(target_world)


func _on_animation_finished() -> void:
	if _is_attacking:
		_perform_attack()
		_finish_attack()
