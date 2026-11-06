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


func _ready() -> void:
	texture = LIGHT_TEXTURE
	color = TORCH_COLOR
	energy = BASE_ENERGY
	texture_scale = BASE_SCALE
	enabled = true
	set_process(false)


func apply_flicker(wave: float, jitter: float) -> void:
	energy = BASE_ENERGY + wave + jitter
	texture_scale = BASE_SCALE + (wave + jitter) * 0.05
