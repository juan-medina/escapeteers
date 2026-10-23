# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name TorchLight
extends PointLight2D

const LIGHT_TEXTURE: Texture2D = preload("res://map/light_texture.tres")
const TORCH_COLOR: Color = Color(1.0, 0.70, 0.35, 1.0)
const BASE_ENERGY: float = 1.1
const BASE_SCALE: float = 1.4
const FLICKER_SPEED_MIN: float = 6.0
const FLICKER_SPEED_MAX: float = 10.0
const JITTER_SPEED: float = 14.0

var _flicker_phase: float = 0.0
var _flicker_speed: float = 8.0
var _jitter: float = 0.0
var _target_jitter: float = 0.0
var _jitter_timer: float = 0.0
var _notifier: VisibleOnScreenNotifier2D = null


func _ready() -> void:
	texture = LIGHT_TEXTURE
	color = TORCH_COLOR
	energy = BASE_ENERGY
	texture_scale = BASE_SCALE
	_flicker_phase = randf_range(0.0, TAU)
	_flicker_speed = randf_range(FLICKER_SPEED_MIN, FLICKER_SPEED_MAX)

	_notifier = VisibleOnScreenNotifier2D.new()
	var reach: float = 128.0 * BASE_SCALE
	_notifier.rect = Rect2(-reach, -reach, reach * 2.0, reach * 2.0)
	_notifier.screen_entered.connect(_on_screen_entered)
	_notifier.screen_exited.connect(_on_screen_exited)
	add_child(_notifier)
	enabled = _notifier.is_on_screen()
	set_process(enabled)


func _process(delta: float) -> void:
	_flicker_phase += delta * _flicker_speed
	_jitter_timer -= delta
	if _jitter_timer <= 0.0:
		_jitter_timer = randf_range(0.05, 0.12)
		_target_jitter = randf_range(-0.08, 0.08)

	_jitter = lerpf(_jitter, _target_jitter, delta * JITTER_SPEED)
	var wave: float = sin(_flicker_phase) * 0.04
	energy = BASE_ENERGY + wave + _jitter
	texture_scale = BASE_SCALE + (wave + _jitter) * 0.05


func _on_screen_entered() -> void:
	enabled = true
	set_process(true)


func _on_screen_exited() -> void:
	enabled = false
	set_process(false)
