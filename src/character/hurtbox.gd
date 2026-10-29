# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Hurtbox
extends Area2D

var owner_character: Character = null
var radius: float = 6.0:
	set(value):
		radius = value
		if _circle_shape != null:
			_circle_shape.radius = radius

var _collision_shape: CollisionShape2D = null
var _circle_shape: CircleShape2D = null


func _init(target_owner: Character = null, initial_radius: float = 6.0, offset: Vector2 = Vector2.ZERO) -> void:
	owner_character = target_owner
	radius = initial_radius
	monitoring = false
	monitorable = true

	_circle_shape = CircleShape2D.new()
	_circle_shape.radius = radius

	_collision_shape = CollisionShape2D.new()
	_collision_shape.position = offset
	_collision_shape.shape = _circle_shape
	add_child(_collision_shape)


func set_disabled(disabled: bool) -> void:
	if _collision_shape != null:
		_collision_shape.set_deferred(&"disabled", disabled)


func get_center_global_position() -> Vector2:
	if _collision_shape != null:
		return _collision_shape.global_position
	return global_position

