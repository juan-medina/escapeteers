# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Unknown
extends Character

const FLICKER_SPEED: float = 8.0
const FLICKER_AMP: float = 0.12
const HINT_LIGHT_ENERGY: float = 2.0

var forced_hero_id: StringName = &""

var _flicker_time: float = 0.0

@onready var _ground_indicator: GroundIndicator = $GroundIndicator
@onready var _secret_light: PointLight2D = $SecretLight


func _ready() -> void:
	has_footsteps = false
	super._ready()
	set_process(false)
	set_physics_process(false)
	disable_collisions()
	_health_bar.visible = false
	_ground_indicator.is_recruited = false
	_ground_indicator.is_player = false


func _process(delta: float) -> void:
	_flicker_time += delta
	_secret_light.energy = HINT_LIGHT_ENERGY + sin(_flicker_time * FLICKER_SPEED) * FLICKER_AMP


func ignite_secret_light() -> void:
	if _secret_light.enabled:
		return
	_secret_light.enabled = true
	set_process(true)
