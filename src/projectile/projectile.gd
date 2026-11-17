# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Projectile
extends Area2D

const ANIM_FLY: StringName = &"fly"
const ANIM_IMPACT: StringName = &"impact"
const ANIM_DEFAULT: StringName = &"default"

static var _pool: EntityPool = null

@export var speed: float = 140.0
@export var damage: float = 5.0
@export var knockback: float = 0.0
@export var lifetime: float = 3.0
@export var auto_rotate: bool = true
@export var is_effect: bool = false
@export var destroy_on_anim_finish: bool = false
@export var slow_factor: float = 0.0
@export var slow_duration: float = 0.0
@export var max_pierce_count: int = 1
@export var has_impact_anim: bool = false

var direction: Vector2 = Vector2.RIGHT
var source_hero: Hero = null

var _elapsed: float = 0.0
var _is_dying: bool = false
var _hit_targets: Array[Node2D] = []

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


static func set_pool(pool: EntityPool) -> void:
	_pool = pool


static func acquire(scene: PackedScene) -> Projectile:
	if _pool != null:
		return _pool.acquire(scene) as Projectile
	return scene.instantiate() as Projectile


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	_animated_sprite.animation_finished.connect(_on_animation_finished)


func _physics_process(delta: float) -> void:
	if _is_dying:
		return

	position += direction * speed * delta
	_elapsed += delta
	if _elapsed >= lifetime:
		_destroy()


func launch() -> void:
	_elapsed = 0.0
	_is_dying = false
	_hit_targets.clear()
	if is_effect:
		set_physics_process(false)
		_animated_sprite.flip_h = false
		rotation = 0.0
		_animated_sprite.play(ANIM_DEFAULT)
		return

	set_physics_process(true)
	if auto_rotate:
		rotation = direction.angle()
		_animated_sprite.flip_h = false
	else:
		rotation = 0.0
		_animated_sprite.flip_h = direction.x < 0.0
	_collision_shape.set_deferred(&"disabled", false)
	_animated_sprite.play(ANIM_FLY)


func reset_for_pool() -> void:
	source_hero = null
	direction = Vector2.RIGHT
	knockback = 0.0
	_elapsed = 0.0
	_is_dying = false
	_hit_targets.clear()
	rotation = 0.0
	_animated_sprite.flip_h = false
	set_physics_process(false)


func deactivate_for_pool() -> void:
	_is_dying = true
	source_hero = null
	_hit_targets.clear()
	_disable_collisions()
	_animated_sprite.stop()


func clear_character_references(character: Character) -> void:
	if source_hero == character:
		source_hero = null
	_hit_targets.erase(character)


func _disable_collisions() -> void:
	_collision_shape.set_deferred(&"disabled", true)


func _destroy() -> void:
	if _is_dying:
		return
	_is_dying = true
	_disable_collisions()
	if has_impact_anim:
		_animated_sprite.play(ANIM_IMPACT)
	else:
		_finish_destroy()


func _finish_destroy() -> void:
	if _pool != null:
		_pool.release(self)
	else:
		queue_free()


func _apply_character_hit(target: Node2D) -> void:
	var enemy: Enemy = target as Enemy
	if enemy != null and slow_duration > 0.0 and slow_factor > 0.0:
		enemy.apply_slow(slow_factor, slow_duration)

	var character: Character = target as Character
	if character != null:
		character.take_damage(damage)

	if knockback > 0.0 and enemy != null:
		enemy.apply_knockback(direction * knockback)

	if source_hero != null and enemy != null:
		source_hero.enemy_hit.emit(enemy, damage, false)


func _on_body_entered(body: Node2D) -> void:
	if _is_dying:
		return
	_on_hit(body)


func _on_area_entered(area: Area2D) -> void:
	if _is_dying:
		return

	if area is Hurtbox:
		var hurtbox: Hurtbox = area as Hurtbox
		var target: Character = hurtbox.owner_character
		if target != null and not target.is_dead:
			if _hit_targets.has(target):
				return
			_hit_targets.append(target)
			_apply_character_hit(target)
			if max_pierce_count > 0 and _hit_targets.size() >= max_pierce_count:
				_destroy()


func _on_hit(target: Node2D) -> void:
	_apply_character_hit(target)
	_destroy()


func _on_animation_finished() -> void:
	if is_effect or destroy_on_anim_finish:
		_destroy()
	elif has_impact_anim and _animated_sprite.animation == ANIM_IMPACT:
		_finish_destroy()
