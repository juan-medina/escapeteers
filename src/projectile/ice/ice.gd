# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Ice
extends Projectile

const ANIM_FORM: StringName = &"form"

@export var slow_factor: float = 0.5
@export var slow_duration: float = 3.0

var _is_forming: bool = true


func _ready() -> void:
	speed = 160.0
	damage = 8.0
	lifetime = 3.5
	auto_rotate = false
	super._ready()
	_is_forming = true
	if _collision_shape != null:
		_collision_shape.set_deferred(&"disabled", true)
	play(ANIM_FORM)


func _physics_process(delta: float) -> void:
	if _is_forming or _is_dying:
		return
	super._physics_process(delta)


func _on_hit(target: Node2D) -> void:
	if target.has_method(&"apply_slow"):
		target.call(&"apply_slow", slow_factor, slow_duration)
	super._on_hit(target)


func _destroy() -> void:
	if _is_dying:
		return
	_is_dying = true
	_is_forming = false
	disable_collisions()
	play(ANIM_IMPACT)


func _on_animation_finished() -> void:
	if _animated_sprite.animation == ANIM_FORM:
		_is_forming = false
		if not _is_dying and _collision_shape != null:
			_collision_shape.set_deferred(&"disabled", false)
		play(ANIM_FLY)
	elif _animated_sprite.animation == ANIM_IMPACT:
		queue_free()

