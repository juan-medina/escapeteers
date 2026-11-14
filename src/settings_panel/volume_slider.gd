# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name VolumeSlider
extends MarginContainer

signal value_changed(value: float)

@export var label_text: String = ""

@onready var _label: Label = $VBox/Label
@onready var _slider: HSlider = $VBox/HBox/HSlider
@onready var _percent: Label = $VBox/HBox/Percent


func _ready() -> void:
	_label.text = label_text


func set_value_no_signal(volume: float) -> void:
	_slider.set_value_no_signal(volume)
	_update_percent(volume)


func _update_percent(volume: float) -> void:
	_percent.text = &"%d %%" % roundi(volume * 100.0)


func _on_slider_value_changed(new_value: float) -> void:
	_update_percent(new_value)
	value_changed.emit(new_value)

