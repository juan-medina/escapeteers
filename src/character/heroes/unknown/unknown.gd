# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Unknown
extends Character

const FLICKER_SPEED: float = 8.0
const FLICKER_AMP: float = 0.12
const HINT_LIGHT_ENERGY: float = 2.0
const HINT_LIGHT_SCALE: float = 2.2

var forced_hero_id: StringName = &""

var _secret_light: PointLight2D = null
var _flicker_time: float = 0.0

@onready var _ground_indicator: GroundIndicator = get_node_or_null(^"GroundIndicator") as GroundIndicator


func _ready() -> void:
	super._ready()
	set_process(false)
	set_physics_process(false)
	disable_collisions()
	if _health_bar != null:
		_health_bar.visible = false
	if _ground_indicator != null:
		_ground_indicator.is_recruited = false
		_ground_indicator.is_player = false


func _process(delta: float) -> void:
	if _secret_light != null:
		_flicker_time += delta
		_secret_light.energy = HINT_LIGHT_ENERGY + sin(_flicker_time * FLICKER_SPEED) * FLICKER_AMP


func ignite_secret_light() -> void:
	if _secret_light != null:
		return
	_secret_light = PointLight2D.new()
	_secret_light.texture = TorchLight.LIGHT_TEXTURE
	_secret_light.color = TorchLight.TORCH_COLOR
	_secret_light.energy = HINT_LIGHT_ENERGY
	_secret_light.texture_scale = HINT_LIGHT_SCALE
	add_child(_secret_light)
	set_process(true)
