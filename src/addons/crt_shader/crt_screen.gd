# Godot CRT Shader
# Original Author: Henrique Alves (perons) - https://perons.itch.io/godot-crt-shader
#
# Modified by Juan Medina

@tool
class_name CRTScreen
extends ColorRect

const CRT_MATERIAL: ShaderMaterial = preload("res://addons/crt_shader/ShaderScreen.material")


func _ready() -> void:
	if material == null:
		material = CRT_MATERIAL

	item_rect_changed.connect(_update_screen_parameters)
	_update_screen_parameters()


func _update_screen_parameters() -> void:
	var shader_material: ShaderMaterial = material
	shader_material.set_shader_parameter(&"screen_width", size.x)
	shader_material.set_shader_parameter(&"screen_height", size.y)


func set_curvature_enabled(enabled: bool) -> void:
	var shader_material: ShaderMaterial = material
	shader_material.set_shader_parameter(&"curvature", enabled)


func set_scanlines_enabled(enabled: bool) -> void:
	var shader_material: ShaderMaterial = material
	shader_material.set_shader_parameter(&"scanlines", enabled)
