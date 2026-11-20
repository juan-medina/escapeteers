# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name KeyPickup
extends Node2D

const PICKUP_DISTANCE: float = 18.0
const BASE_SPRITE_Y: float = -3.0
const BOB_AMPLITUDE: float = 1.5
const BOB_SPEED: float = 4.0

var key_color: WorldPlan.KeyColor = WorldPlan.KeyColor.BLUE

var _bob_elapsed: float = 0.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _indicator: GroundIndicator = $GroundIndicator


func _ready() -> void:
	_apply_visuals()


func _process(delta: float) -> void:
	_bob_elapsed += delta
	_sprite.position.y = BASE_SPRITE_Y + sin(_bob_elapsed * BOB_SPEED) * BOB_AMPLITUDE


func setup(color: WorldPlan.KeyColor) -> void:
	key_color = color
	if is_node_ready():
		_apply_visuals()


func is_touching(hero: Hero) -> bool:
	return position.distance_squared_to(hero.position) <= PICKUP_DISTANCE * PICKUP_DISTANCE


static func get_color_name(color: WorldPlan.KeyColor) -> String:
	match color:
		WorldPlan.KeyColor.GREEN:
			return "Green"
		WorldPlan.KeyColor.YELLOW:
			return "Yellow"
		WorldPlan.KeyColor.RED:
			return "Red"
		_:
			return "Blue"


static func get_display_color(color: WorldPlan.KeyColor) -> Color:
	match color:
		WorldPlan.KeyColor.GREEN:
			return Color(0.35, 0.95, 0.50, 1.0)
		WorldPlan.KeyColor.YELLOW:
			return Color(1.0, 0.88, 0.30, 1.0)
		WorldPlan.KeyColor.RED:
			return Color(1.0, 0.38, 0.38, 1.0)
		_:
			return Color(0.35, 0.72, 1.0, 1.0)


func _apply_visuals() -> void:
	var anim_name: StringName = &"blue"
	var ring_color: Color = Color(0.25, 0.65, 1.0, 0.75)
	match key_color:
		WorldPlan.KeyColor.GREEN:
			anim_name = &"green"
			ring_color = Color(0.30, 0.90, 0.45, 0.75)
		WorldPlan.KeyColor.YELLOW:
			anim_name = &"yellow"
			ring_color = Color(1.0, 0.85, 0.25, 0.75)
		WorldPlan.KeyColor.RED:
			anim_name = &"red"
			ring_color = Color(1.0, 0.32, 0.32, 0.75)
	_sprite.play(anim_name)
	_indicator.custom_ring_color = ring_color
