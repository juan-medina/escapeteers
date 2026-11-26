# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Fog
extends CanvasLayer

const NORMAL_FOG_COLOR: Color = Color(0.03, 0.03, 0.05, 1.0)
const EVENT_FOG_COLOR: Color = Color(0.18, 0.03, 0.04, 1.0)
const TRANSITION_DURATION: float = 0.5

var _fog_tween: Tween = null
var _current_color: Color = NORMAL_FOG_COLOR
var _fog_material: ShaderMaterial = null

@onready var _fog_rect: ColorRect = $FogRect


func _ready() -> void:
	_fog_material = _fog_rect.material as ShaderMaterial
	_apply_fog_color(NORMAL_FOG_COLOR)


func set_event_atmosphere(active: bool) -> void:
	var target: Color = EVENT_FOG_COLOR if active else NORMAL_FOG_COLOR
	if _fog_tween != null and _fog_tween.is_valid():
		_fog_tween.kill()
	_fog_tween = create_tween()
	_fog_tween.tween_method(_apply_fog_color, _current_color, target, TRANSITION_DURATION)


func _apply_fog_color(color: Color) -> void:
	_current_color = color
	_fog_material.set_shader_parameter(&"fog_color", color)
