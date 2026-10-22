# Godot CRT Shader
# Original Author: Henrique Alves (perons) - https://perons.itch.io/godot-crt-shader
#
# Modified by Juan Medina

@tool
extends EditorPlugin


func _enter_tree() -> void:
	add_custom_type(
		&"CRTScreen",
		&"ColorRect",
		preload("res://addons/crt_shader/crt_screen.gd"),
		preload("res://addons/crt_shader/icon.png")
	)


func _exit_tree() -> void:
	remove_custom_type(&"CRTScreen")
