# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Character
extends CharacterBody2D

signal damaged(amount: float, current_health: float)
signal died

const FLIP_THRESHOLD_X: float = 0.35
const MIN_MOVEMENT_THRESHOLD_SQUARED: float = 0.04

const _ANIM_IDLE: StringName = &"idle"
const _ANIM_RUN: StringName = &"run"

@export var max_health: float = 100.0
@export var speed: float = 100.0

var health: float = 100.0

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

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	health = max_health
	play(_ANIM_IDLE)


func play(anim_name: StringName = _ANIM_IDLE) -> void:
	var sprite: AnimatedSprite2D = _get_sprite()
	if sprite != null and sprite.sprite_frames != null:
		if sprite.sprite_frames.has_animation(anim_name):
			sprite.play(anim_name)


func update_visuals(movement_vector: Vector2) -> void:
	if movement_vector.length_squared() > MIN_MOVEMENT_THRESHOLD_SQUARED:
		if absf(movement_vector.x) > FLIP_THRESHOLD_X:
			flip_h = movement_vector.x < 0.0
		if animation != _ANIM_RUN:
			play(_ANIM_RUN)
	else:
		if animation != _ANIM_IDLE:
			play(_ANIM_IDLE)


func get_spawn_position() -> Vector2:
	var marker: Marker2D = get_node_or_null(^"SpawnPoint") as Marker2D
	if marker != null:
		return marker.global_position
	return global_position + Vector2(0.0, 2.0)


func take_damage(amount: float) -> void:
	health = maxf(0.0, health - amount)
	damaged.emit(amount, health)
	_flash_hurt()
	if health <= 0.0:
		died.emit()
		_on_death()


func _on_death() -> void:
	pass


func _flash_hurt() -> void:
	var sprite: AnimatedSprite2D = _get_sprite()
	if sprite != null:
		sprite.modulate = Color(1.0, 0.35, 0.35, 1.0)
		var tween: Tween = create_tween()
		tween.tween_property(sprite, ^"modulate", Color.WHITE, 0.15)


func _get_sprite() -> AnimatedSprite2D:
	if _animated_sprite != null:
		return _animated_sprite
	return get_node_or_null(^"AnimatedSprite2D") as AnimatedSprite2D
