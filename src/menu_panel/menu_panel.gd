# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name MenuPanel
extends PanelContainer

@warning_ignore("unused_signal")
signal back_requested
@warning_ignore("unused_signal")
signal busy_changed(is_busy: bool)

var busy: bool = false:
	set(value):
		if busy != value:
			busy = value
			busy_changed.emit(busy)


func _ready() -> void:
	Audio.connect_menu_sounds(self)


func first_focus_control() -> Control:
	return null
