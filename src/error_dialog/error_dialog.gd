# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name ErrorDialog
extends CanvasLayer

@onready var _detail: Label = $Center/Panel/VBox/Detail
@onready var _action: Button = $Center/Panel/VBox/Action


func _ready() -> void:
	Audio.connect_menu_sounds(self)


func setup(message: StringName) -> void:
	var build: String = BuildInfo.display_string()
	var platform: String = OS.get_name()
	_detail.text = &"%s · %s · %s" % [message, build, platform]
	_action.text = &"Reload" if OS.has_feature(&"web") else &"Exit"
	Audio.grab_focus_silent(_action)


func _on_action_pressed() -> void:
	if OS.has_feature(&"web"):
		JavaScriptBridge.eval(&"window.location.reload();")
	else:
		get_tree().quit()
