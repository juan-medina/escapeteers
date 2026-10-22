# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

extends CanvasLayer

@onready var _crt_screen: CRTScreen = $CRTScreen
@onready var _crt_border: TextureRect = $Border


func set_curvature_enabled(enabled: bool) -> void:
	_crt_screen.set_curvature_enabled(enabled)


func set_scanlines_enabled(enabled: bool) -> void:
	_crt_screen.set_scanlines_enabled(enabled)


func set_border_enabled(enabled: bool) -> void:
	_crt_border.visible = enabled
