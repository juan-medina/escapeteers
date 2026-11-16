# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Ice
extends Projectile

const ANIM_FORM: StringName = &"form"

@export var slow_factor: float = 0.4
@export var slow_duration: float = 4.0
@export var max_pierce_count: int = 0

var _is_forming: bool = true
var _hit_targets: Array[Node2D] = []


func _physics_process(delta: float) -> void:
	if _is_forming or _is_dying:
		return
	super._physics_process(delta)


func launch() -> void:
	_elapsed = 0.0
	_is_dying = false
	_is_forming = true
	_hit_targets.clear()
	set_physics_process(true)
	rotation = 0.0
	_animated_sprite.flip_h = direction.x < 0.0
	_disable_collisions()
	_animated_sprite.play(ANIM_FORM)


func reset_for_pool() -> void:
	super.reset_for_pool()
	_is_forming = true
	_hit_targets.clear()


func _destroy() -> void:
	if _is_dying:
		return
	_is_dying = true
	_is_forming = false
	_disable_collisions()
	_animated_sprite.play(ANIM_IMPACT)


func _on_body_entered(_body: Node2D) -> void:
	if _is_dying or _is_forming:
		return
	_destroy()


func _on_area_entered(area: Area2D) -> void:
	if _is_dying or _is_forming:
		return

	if area is Hurtbox:
		var hurtbox: Hurtbox = area as Hurtbox
		var target: Character = hurtbox.owner_character
		if target != null and is_instance_valid(target) and not target.is_dead:
			if _hit_targets.has(target):
				return
			_hit_targets.append(target)
			var enemy: Enemy = target as Enemy
			if enemy != null:
				enemy.apply_slow(slow_factor, slow_duration)
			_apply_character_hit(target)
			if max_pierce_count > 0 and _hit_targets.size() >= max_pierce_count:
				_destroy()


func _on_animation_finished() -> void:
	if _animated_sprite.animation == ANIM_FORM:
		if _is_dying:
			return
		_is_forming = false
		_collision_shape.set_deferred(&"disabled", false)
		_animated_sprite.play(ANIM_FLY)
	elif _animated_sprite.animation == ANIM_IMPACT:
		_finish_destroy()
