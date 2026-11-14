# Godot CRT Shader
# Original Author: Henrique Alves (perons) - https://perons.itch.io/godot-crt-shader
#
# Modified by Juan Medina

@tool
@icon("res://addons/crt_shader/icon.png")
class_name CRTScreen
extends ColorRect

const CRT_MATERIAL: ShaderMaterial = preload("res://addons/crt_shader/ShaderScreen.material")

var _shader_material: ShaderMaterial = null


func _ready() -> void:
	if material == null:
		material = CRT_MATERIAL
	_shader_material = material as ShaderMaterial

	item_rect_changed.connect(_update_screen_parameters)
	_update_screen_parameters()


func set_curvature_enabled(enabled: bool) -> void:
	_shader_material.set_shader_parameter(&"curvature", enabled)


func set_scanlines_enabled(enabled: bool) -> void:
	_shader_material.set_shader_parameter(&"scanlines", enabled)


func _update_screen_parameters() -> void:
	_shader_material.set_shader_parameter(&"screen_width", size.x)
	_shader_material.set_shader_parameter(&"screen_height", size.y)
