# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Character
extends CharacterBody2D

const SCENE: PackedScene = preload("res://character/character.tscn")
const FLIP_THRESHOLD_X: float = 0.35
const MIN_MOVEMENT_THRESHOLD_SQUARED: float = 0.04
const RECRUIT_DISTANCE: float = 20.0

const RING_BASE_RADIUS: float = 28.0
const RING_LAYER_SPACING: float = 22.0
const RING_BASE_CAPACITY: int = 6
const SEPARATION_RADIUS: float = 18.0
const SEPARATION_SPEED: float = 65.0
const PLAYER_CLEARANCE_RADIUS: float = 25.0
const PLAYER_PUSH_SPEED: float = 145.0
const FOLLOW_ARRIVAL_RADIUS: float = 16.0
const FOLLOW_STOP_DISTANCE: float = 1.5
const FOLLOW_ACCELERATION: float = 480.0
const REACTION_DELAY_BASE: float = 0.12
const REACTION_DELAY_STEP: float = 0.06
const REACTION_JITTER: float = 0.05
const MAX_HISTORY_DURATION: float = 0.6

const CRESCENT_BACK_SHIFT: float = 10.0
const CRESCENT_FRONT_CLEAR_ANGLE: float = 0.85
const CRESCENT_BLEND_SPEED: float = 5.0

const _ANIM_IDLE: StringName = &"idle"
const _ANIM_RUN: StringName = &"run"

@export var is_player: bool = false
@export var speed: float = 100.0

var leader: Character = null
var slot_offset: Vector2 = Vector2.ZERO
var reaction_delay: float = REACTION_DELAY_BASE
var is_moving: bool = false
var move_direction: Vector2 = Vector2.RIGHT
var crescent_blend: float = 0.0

var flip_h: bool:
	get:
		var sprite: AnimatedSprite2D = _get_sprite()
		return sprite.flip_h if sprite != null else false
	set(value):
		var sprite: AnimatedSprite2D = _get_sprite()
		if sprite != null:
			sprite.flip_h = value

var frame: int:
	get:
		var sprite: AnimatedSprite2D = _get_sprite()
		return sprite.frame if sprite != null else 0
	set(value):
		var sprite: AnimatedSprite2D = _get_sprite()
		if sprite != null:
			sprite.frame = value

var frame_progress: float:
	get:
		var sprite: AnimatedSprite2D = _get_sprite()
		return sprite.frame_progress if sprite != null else 0.0
	set(value):
		var sprite: AnimatedSprite2D = _get_sprite()
		if sprite != null:
			sprite.frame_progress = value

var animation: StringName:
	get:
		var sprite: AnimatedSprite2D = _get_sprite()
		return sprite.animation if sprite != null else StringName()

var sprite_frames: SpriteFrames:
	get:
		var sprite: AnimatedSprite2D = _get_sprite()
		return sprite.sprite_frames if sprite != null else null
	set(value):
		var sprite: AnimatedSprite2D = _get_sprite()
		if sprite != null:
			sprite.sprite_frames = value

var _velocity: Vector2 = Vector2.ZERO
var _elapsed_time: float = 0.0
var _pos_history: Array[Vector2] = []
var _time_history: Array[float] = []

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
# @onready var _collision_shape: CollisionShape2D = $CollisionShape2D


static func instantiate() -> Character:
	var ch: Character = SCENE.instantiate() as Character
	if ch == null:
		printerr(&"Character: Failed to instantiate Character scene!")
		await Alerts.fatal_error(&"Could not spawn characters")
		return null
	return ch


func play(anim_name: StringName = _ANIM_IDLE) -> void:
	var sprite: AnimatedSprite2D = _get_sprite()
	if sprite != null and sprite.sprite_frames != null:
		if sprite.sprite_frames.has_animation(anim_name):
			sprite.play(anim_name)


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


func assign_escort_slot(slot_index: int, total_slots: int) -> void:
	var remaining_index: int = slot_index
	var remaining_total: int = total_slots
	var ring: int = 0
	var ring_capacity: int = RING_BASE_CAPACITY

	while remaining_index >= ring_capacity:
		remaining_index -= ring_capacity
		remaining_total -= ring_capacity
		ring += 1
		ring_capacity = RING_BASE_CAPACITY * (ring + 1)

	var count_in_ring: int = mini(remaining_total, ring_capacity)
	var angle: float = (float(ring) * 0.55) + (TAU * float(remaining_index) / float(maxi(count_in_ring, 1)))
	var radius: float = RING_BASE_RADIUS + (float(ring) * RING_LAYER_SPACING)
	slot_offset = Vector2(cos(angle), sin(angle)) * radius

	var jitter: float = fmod(float(slot_index) * 0.6180339, 1.0) * REACTION_JITTER
	reaction_delay = REACTION_DELAY_BASE + (float(ring) * REACTION_DELAY_STEP) + jitter


func follow_leader(delta: float, squad: Array[Character]) -> void:
	var dynamic_offset: Vector2 = _compute_crescent_slot_offset()

	# Followers in front of the leader's movement react immediately so the leader never walks into them.
	var effective_delay: float = reaction_delay
	if leader.is_moving and dynamic_offset.length_squared() > 0.001:
		var forward_alignment: float = dynamic_offset.normalized().dot(leader.move_direction)
		if forward_alignment > 0.0:
			effective_delay = reaction_delay * (1.0 - forward_alignment) * (1.0 - leader.crescent_blend)

	var target_pos: Vector2 = leader.get_delayed_position(effective_delay) + dynamic_offset
	var to_target: Vector2 = target_pos - position
	var dist: float = to_target.length()

	var desired_velocity: Vector2 = Vector2.ZERO
	if dist > FOLLOW_STOP_DISTANCE:
		var target_speed: float = speed
		if dist < FOLLOW_ARRIVAL_RADIUS:
			target_speed = speed * (dist / FOLLOW_ARRIVAL_RADIUS)
		else:
			target_speed = minf(speed * 2.0, speed + (dist - FOLLOW_ARRIVAL_RADIUS) * 2.5)
		desired_velocity = (to_target / dist) * target_speed

	desired_velocity += _compute_separation(squad)
	_velocity = _velocity.move_toward(desired_velocity, FOLLOW_ACCELERATION * delta)

	var step: Vector2 = _velocity * delta
	if dist <= FOLLOW_STOP_DISTANCE and desired_velocity.length_squared() < MIN_MOVEMENT_THRESHOLD_SQUARED:
		_velocity = Vector2.ZERO
		step = Vector2.ZERO

	position += step
	is_moving = _velocity.length_squared() > 4.0
	_update_visuals(step)


func is_touching(other: Character) -> bool:
	return position.distance_squared_to(other.position) <= RECRUIT_DISTANCE * RECRUIT_DISTANCE


func _ready() -> void:
	play(_ANIM_IDLE)


func _process(delta: float) -> void:
	if not is_player:
		return

	var input_vector: Vector2 = Input.get_vector(&"left", &"right", &"up", &"down")

	if input_vector != Vector2.ZERO:
		is_moving = true
		move_direction = input_vector.normalized()
		crescent_blend = move_toward(crescent_blend, 1.0, CRESCENT_BLEND_SPEED * delta)
		position += input_vector * speed * delta
		if input_vector.x > 0.05:
			flip_h = false
		elif input_vector.x < -0.05:
			flip_h = true
		if animation != _ANIM_RUN:
			play(_ANIM_RUN)
	else:
		is_moving = false
		crescent_blend = move_toward(crescent_blend, 0.0, CRESCENT_BLEND_SPEED * delta)
		if animation != _ANIM_IDLE:
			play(_ANIM_IDLE)


func _get_sprite() -> AnimatedSprite2D:
	if _animated_sprite != null:
		return _animated_sprite
	return get_node_or_null(^"AnimatedSprite2D") as AnimatedSprite2D


func _update_visuals(movement_vector: Vector2) -> void:
	if movement_vector.length_squared() > MIN_MOVEMENT_THRESHOLD_SQUARED:
		if absf(movement_vector.x) > FLIP_THRESHOLD_X:
			flip_h = movement_vector.x < 0.0
		if animation != _ANIM_RUN:
			play(_ANIM_RUN)
	else:
		if animation != _ANIM_IDLE:
			play(_ANIM_IDLE)


func _compute_crescent_slot_offset() -> Vector2:
	if leader.crescent_blend <= 0.001:
		return slot_offset

	var radius: float = slot_offset.length()
	if radius <= 0.001:
		return slot_offset

	var move_angle: float = leader.move_direction.angle()
	var rel_angle: float = wrapf(slot_offset.angle() - move_angle, -PI, PI)
	var sign_dir: float = -1.0 if rel_angle < 0.0 else 1.0
	var remapped: float = CRESCENT_FRONT_CLEAR_ANGLE + (absf(rel_angle) / PI) * (PI - CRESCENT_FRONT_CLEAR_ANGLE)
	var target_angle: float = move_angle + (sign_dir * remapped)
	var crescent_pos: Vector2 = (Vector2(cos(target_angle), sin(target_angle)) * radius) - (leader.move_direction * CRESCENT_BACK_SHIFT)
	return slot_offset.lerp(crescent_pos, leader.crescent_blend)


func _compute_separation(squad: Array[Character]) -> Vector2:
	var push: Vector2 = Vector2.ZERO
	var min_dist_sq: float = SEPARATION_RADIUS * SEPARATION_RADIUS
	var player_dist_sq: float = PLAYER_CLEARANCE_RADIUS * PLAYER_CLEARANCE_RADIUS

	for other: Character in squad:
		if other == self:
			continue
		var diff: Vector2 = position - other.position
		var dist_sq: float = diff.length_squared()

		if other.is_player:
			if dist_sq > 0.0001 and dist_sq < player_dist_sq:
				var dist: float = sqrt(dist_sq)
				var strength: float = (PLAYER_CLEARANCE_RADIUS - dist) / PLAYER_CLEARANCE_RADIUS
				var push_dir: Vector2 = diff / dist
				if other.is_moving and push_dir.dot(other.move_direction) > 0.7:
					var perp: Vector2 = Vector2(-other.move_direction.y, other.move_direction.x)
					if push_dir.dot(perp) < 0.0:
						perp = -perp
					push_dir = (push_dir + perp * 1.2).normalized()
				push += push_dir * (PLAYER_PUSH_SPEED * strength)
		elif dist_sq > 0.0001 and dist_sq < min_dist_sq:
			var dist: float = sqrt(dist_sq)
			var strength: float = (SEPARATION_RADIUS - dist) / SEPARATION_RADIUS
			push += (diff / dist) * (SEPARATION_SPEED * strength)

	return push
