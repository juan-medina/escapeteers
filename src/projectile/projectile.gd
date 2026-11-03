# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Projectile
extends Area2D

signal hit_target(target: Node2D, damage_dealt: float)

const ANIM_FLY: StringName = &"fly"
const ANIM_IMPACT: StringName = &"impact"

@export var speed: float = 140.0
@export var damage: float = 5.0
@export var knockback: float = 0.0
@export var lifetime: float = 3.0
@export var auto_rotate: bool = true

var direction: Vector2 = Vector2.RIGHT
var source_hero: Hero = null

var _elapsed: float = 0.0
var _is_dying: bool = false

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	_animated_sprite.animation_finished.connect(_on_animation_finished)
	if auto_rotate:
		rotation = direction.angle()
	else:
		rotation = 0.0
		if direction.x < 0.0:
			_animated_sprite.flip_h = true

	play(ANIM_FLY)


func play(anim_name: StringName = ANIM_FLY) -> void:
	_animated_sprite.play(anim_name)


func disable_collisions() -> void:
	if _collision_shape != null:
		_collision_shape.set_deferred(&"disabled", true)


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

	disable_collisions()
	queue_free()


func _on_body_entered(body: Node2D) -> void:
	if _is_dying:
		return

	_on_hit(body)


func _on_area_entered(area: Area2D) -> void:
	if _is_dying:
		return

	if area is Hurtbox:
		var hurtbox: Hurtbox = area as Hurtbox
		if hurtbox.owner_character != null and is_instance_valid(hurtbox.owner_character) and not hurtbox.owner_character.is_dead:
			_on_hit(hurtbox.owner_character)


func _on_hit(target: Node2D) -> void:
	if target.has_method(&"take_damage"):
		target.call(&"take_damage", damage)

	if knockback > 0.0 and target.has_method(&"apply_knockback"):
		target.call(&"apply_knockback", direction * knockback)

	hit_target.emit(target, damage)
	if source_hero != null and is_instance_valid(source_hero) and target is Enemy:
		source_hero.enemy_hit.emit(target as Enemy, damage, false)
	_destroy()


func _on_animation_finished() -> void:
	pass
