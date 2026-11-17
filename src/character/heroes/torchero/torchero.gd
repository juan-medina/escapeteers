# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Torchero
extends Hero

const TORCH_FLICKER_SPEED: float = 8.0
const TORCH_FLICKER_AMP: float = 0.06

var _flicker_time: float = 0.0
var _base_light_energy: float = 1.1

@onready var _torch_light: PointLight2D = $PointLight2D


func _ready() -> void:
	super._ready()
	_base_light_energy = _torch_light.energy
	_flicker_time = randf() * TAU


func _process(delta: float) -> void:
	super._process(delta)
	if not is_dead and _torch_light.enabled:
		_flicker_time += delta
		_torch_light.energy = _base_light_energy + sin(_flicker_time * TORCH_FLICKER_SPEED) * TORCH_FLICKER_AMP


func _on_death() -> void:
	super._on_death()
	_torch_light.enabled = false


func _is_preferred_target(enemy: Enemy) -> bool:
	return not enemy.is_burning()
