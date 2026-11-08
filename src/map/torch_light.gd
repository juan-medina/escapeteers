# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name TorchLight
extends PointLight2D

const LIGHT_TEXTURE: Texture2D = preload("res://map/light_texture.tres")
const TORCH_COLOR: Color = Color(1.0, 0.70, 0.35, 1.0)
const BASE_ENERGY: float = 1.1
const BASE_SCALE: float = 1.4

var phase_offset: float = 0.0
var cell_pos: Vector2i = Vector2i.ZERO
var current_dist_sq: float = 0.0
var is_blinking: bool = false


func _ready() -> void:
	texture = LIGHT_TEXTURE
	color = TORCH_COLOR
	energy = BASE_ENERGY
	texture_scale = BASE_SCALE
	enabled = true
	set_process(false)


func apply_flicker(wave: float, jitter: float, time: float = 0.0) -> void:
	if is_blinking:
		var blink_on: bool = fmod(time * 3.0, 1.0) < 0.65
		energy = (BASE_ENERGY + wave + jitter) if blink_on else 0.12
		texture_scale = BASE_SCALE if blink_on else BASE_SCALE * 0.75
		return
	energy = BASE_ENERGY + wave + jitter
	texture_scale = BASE_SCALE + (wave + jitter) * 0.05
