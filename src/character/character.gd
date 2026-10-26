# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Character
extends CharacterBody2D

signal damaged(amount: float, current_health: float)
signal died
signal projectile_spawn_requested(projectile: Projectile)

enum MovementState {
	IDLE,
	NAVIGATING,
	FALL_BACK,
}

enum CombatState {
	READY,
	ATTACKING,
	COOLDOWN,
}

const FLIP_THRESHOLD_X: float = 0.35
const MIN_MOVEMENT_THRESHOLD_SQUARED: float = 0.04

const ANIM_IDLE: StringName = &"idle"
const ANIM_RUN: StringName = &"run"
const ANIM_HIT: StringName = &"hit"
const ANIM_DEATH: StringName = &"death"
const ANIM_ATTACK_MELEE1: StringName = &"attack_melee1"
const ANIM_ATTACK_MELEE2: StringName = &"attack_melee2"
const ANIM_ATTACK_RANGED1: StringName = &"attack_ranged1"

@export var max_health: float = 100.0
@export var speed: float = 100.0
@export var can_melee: bool = false
@export var melee_range: float = 28.0
@export var can_ranged: bool = false
@export var ranged_min_range: float = 45.0
@export var ranged_range: float = 140.0

var health: float = 100.0
var is_dead: bool = false
var movement_state: MovementState = MovementState.IDLE
var combat_state: CombatState = CombatState.READY

var flip_h: bool:
	get:
		return _animated_sprite.flip_h
	set(value):
		_animated_sprite.flip_h = value

var frame: int:
	get:
		return _animated_sprite.frame
	set(value):
		_animated_sprite.frame = value

var frame_progress: float:
	get:
		return _animated_sprite.frame_progress
	set(value):
		_animated_sprite.frame_progress = value

var animation: StringName:
	get:
		return _animated_sprite.animation

var is_attacking: bool:
	get:
		return combat_state == CombatState.ATTACKING

var sprite_frames: SpriteFrames:
	get:
		return _animated_sprite.sprite_frames
	set(value):
		_animated_sprite.sprite_frames = value

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _spawn_point: Marker2D = $SpawnPoint


func _ready() -> void:
	health = max_health
	_animated_sprite.animation_finished.connect(_on_animation_finished)
	play(ANIM_IDLE)


func play(anim_name: StringName = ANIM_IDLE) -> void:
	_animated_sprite.play(anim_name)


func disable_collisions() -> void:
	_collision_shape.set_deferred(&"disabled", true)


func enable_collisions() -> void:
	_collision_shape.set_deferred(&"disabled", false)


func update_visuals(movement_vector: Vector2) -> void:
	if movement_vector.length_squared() > MIN_MOVEMENT_THRESHOLD_SQUARED:
		if absf(movement_vector.x) > FLIP_THRESHOLD_X:
			flip_h = movement_vector.x < 0.0
		if combat_state != CombatState.ATTACKING and animation != ANIM_RUN:
			play(ANIM_RUN)
	else:
		if combat_state != CombatState.ATTACKING and animation != ANIM_IDLE:
			play(ANIM_IDLE)


func get_spawn_position() -> Vector2:
	return _spawn_point.global_position


func spawn_projectile(projectile: Projectile) -> void:
	projectile_spawn_requested.emit(projectile)


func can_attack_at_distance(dist: float) -> bool:
	if can_melee and dist <= melee_range:
		return true
	if can_ranged and dist >= ranged_min_range and dist <= ranged_range:
		return true
	return false


func take_damage(amount: float) -> void:
	if is_dead:
		return

	health = maxf(0.0, health - amount)
	damaged.emit(amount, health)
	if health <= 0.0:
		is_dead = true
		movement_state = MovementState.IDLE
		combat_state = CombatState.READY
		died.emit()
		_on_death()
	else:
		_flash_hurt()


func _on_death() -> void:
	pass


func _flash_hurt() -> void:
	var tween: Tween = create_tween()
	_animated_sprite.modulate = Color(2.5, 0.4, 0.4)
	tween.tween_property(_animated_sprite, "modulate", Color.WHITE, 0.08)


func _on_animation_finished() -> void:
	if combat_state == CombatState.ATTACKING:
		combat_state = CombatState.COOLDOWN
		if velocity.length_squared() > MIN_MOVEMENT_THRESHOLD_SQUARED:
			play(ANIM_RUN)
		else:
			play(ANIM_IDLE)
