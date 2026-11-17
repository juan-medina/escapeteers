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

var _circle_shape: CircleShape2D = null

@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	monitoring = false
	monitorable = true
	_circle_shape = (_collision_shape.shape as CircleShape2D).duplicate() as CircleShape2D
	_circle_shape.radius = radius
	_collision_shape.shape = _circle_shape


func setup(target_owner: Character, initial_radius: float, offset: Vector2, layer: int) -> void:
	owner_character = target_owner
	radius = initial_radius
	_collision_shape.position = offset
	collision_layer = layer
	collision_mask = 0


func set_disabled(disabled: bool) -> void:
	_collision_shape.set_deferred(&"disabled", disabled)


func get_center_global_position() -> Vector2:
	return _collision_shape.global_position
