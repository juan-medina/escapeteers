# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Character
extends CharacterBody2D

const SCENE: PackedScene = preload("res://character/character.tscn")
const FLIP_THRESHOLD_X: float = 0.35
const MIN_MOVEMENT_THRESHOLD_SQUARED: float = 0.04
const RECRUIT_DISTANCE: float = 20.0
const MAX_HISTORY_DURATION: float = 2.5
const CRESCENT_BLEND_SPEED: float = 5.0

const _ANIM_IDLE: StringName = &"idle"
const _ANIM_RUN: StringName = &"run"

@export var is_player: bool = false:
	set(value):
		is_player = value
		_update_collision_mode()
@export var speed: float = 100.0

var leader: Character = null
var squad_member: SquadMember = null
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

var _elapsed_time: float = 0.0
var _pos_history: Array[Vector2] = []
var _time_history: Array[float] = []

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


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


func is_touching(other: Character) -> bool:
	return position.distance_squared_to(other.position) <= RECRUIT_DISTANCE * RECRUIT_DISTANCE


func update_visuals(movement_vector: Vector2) -> void:
	if movement_vector.length_squared() > MIN_MOVEMENT_THRESHOLD_SQUARED:
		if absf(movement_vector.x) > FLIP_THRESHOLD_X:
			flip_h = movement_vector.x < 0.0
		if animation != _ANIM_RUN:
			play(_ANIM_RUN)
	else:
		if animation != _ANIM_IDLE:
			play(_ANIM_IDLE)


func _ready() -> void:
	play(_ANIM_IDLE)
	_update_collision_mode()


func _process(delta: float) -> void:
	if not is_player:
		return

	var input_vector: Vector2 = Input.get_vector(&"left", &"right", &"up", &"down")

	if input_vector != Vector2.ZERO:
		is_moving = true
		move_direction = input_vector.normalized()
		crescent_blend = move_toward(crescent_blend, 1.0, CRESCENT_BLEND_SPEED * delta)
		velocity = input_vector * speed
		move_and_slide()
		if input_vector.x > 0.05:
			flip_h = false
		elif input_vector.x < -0.05:
			flip_h = true
		if animation != _ANIM_RUN:
			play(_ANIM_RUN)
	else:
		is_moving = false
		crescent_blend = move_toward(crescent_blend, 0.0, CRESCENT_BLEND_SPEED * delta)
		velocity = Vector2.ZERO
		move_and_slide()
		if animation != _ANIM_IDLE:
			play(_ANIM_IDLE)


func _update_collision_mode() -> void:
	if is_player:
		collision_layer = 2
		collision_mask = 1
		if _collision_shape != null:
			_collision_shape.disabled = false
	else:
		collision_layer = 4
		collision_mask = 1
		if _collision_shape != null:
			_collision_shape.disabled = false


func _get_sprite() -> AnimatedSprite2D:
	if _animated_sprite != null:
		return _animated_sprite
	return get_node_or_null(^"AnimatedSprite2D") as AnimatedSprite2D
