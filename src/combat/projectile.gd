# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Projectile
extends Area2D

signal hit_target(target: Node2D, damage_dealt: float)

const _ANIM_FLY: StringName = &"fly"

@export var speed: float = 140.0
@export var damage: float = 5.0
@export var lifetime: float = 3.0
@export var auto_rotate: bool = true

var direction: Vector2 = Vector2.RIGHT

var _elapsed: float = 0.0
var _is_dying: bool = false

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if auto_rotate:
		rotation = direction.angle()
	else:
		rotation = 0.0
		if _animated_sprite != null and direction.x < 0.0:
			_animated_sprite.flip_h = true

	if _animated_sprite != null and _animated_sprite.sprite_frames != null:
		if _animated_sprite.sprite_frames.has_animation(_ANIM_FLY):
			_animated_sprite.play(_ANIM_FLY)
		elif _animated_sprite.sprite_frames.has_animation(&"default"):
			_animated_sprite.play(&"default")


func _physics_process(delta: float) -> void:
	if _is_dying:
		return

	position += direction * speed * delta
	_elapsed += delta
	if _elapsed >= lifetime:
		_destroy()


func _destroy() -> void:
	if _is_dying:
		return
	_is_dying = true

	if _collision_shape != null:
		_collision_shape.set_deferred(&"disabled", true)

	queue_free()


func _on_body_entered(body: Node2D) -> void:
	if _is_dying:
		return

	if body.has_method(&"take_damage"):
		body.call(&"take_damage", damage)

	hit_target.emit(body, damage)
	_destroy()
