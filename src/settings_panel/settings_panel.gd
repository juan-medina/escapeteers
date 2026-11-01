# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name SettingsPanel
extends MenuPanel

@onready var _fullscreen_check: CheckButton = $VBox/Fullscreen
@onready var _scanlines_check: CheckButton = $VBox/Scanlines
@onready var _curvature_check: CheckButton = $VBox/Curvature
@onready var _crt_border_check: CheckButton = $VBox/CrtBorder
@onready var _master_slider: HSlider = $VBox/MasterVolume/VBox/HBox/HSlider
@onready var _master_percent: Label = $VBox/MasterVolume/VBox/HBox/Label
@onready var _music_slider: HSlider = $VBox/MusicVolume/VBox/HBox/HSlider
@onready var _music_percent: Label = $VBox/MusicVolume/VBox/HBox/Label
@onready var _sfx_slider: HSlider = $VBox/SfxVolume/VBox/HBox/HSlider
@onready var _sfx_percent: Label = $VBox/SfxVolume/VBox/HBox/Label


func _ready() -> void:
	super._ready()
	Options.fullscreen_changed.connect(_on_fullscreen_changed)
	_on_fullscreen_changed(Options.fullscreen)
	_init_slider(_master_slider, _master_percent, Options.master_volume)
	_init_slider(_music_slider, _music_percent, Options.music_volume)
	_init_slider(_sfx_slider, _sfx_percent, Options.sfx_volume)
	_scanlines_check.button_pressed = Options.scanlines
	_curvature_check.button_pressed = Options.curvature
	_crt_border_check.button_pressed = Options.crt_border


func _exit_tree() -> void:
	Options.fullscreen_changed.disconnect(_on_fullscreen_changed)


func first_focus_control() -> Control:
	return _fullscreen_check


func _on_fullscreen_changed(is_on: bool) -> void:
	_fullscreen_check.button_pressed = is_on


func _on_fullscreen_toggled(is_on: bool) -> void:
	Options.fullscreen = is_on


func _on_master_volume_changed(value: float) -> void:
	Options.master_volume = value
	_master_percent.text = _format_percent(value)


func _on_music_volume_changed(value: float) -> void:
	Options.music_volume = value
	_music_percent.text = _format_percent(value)


func _on_sfx_volume_changed(value: float) -> void:
	Options.sfx_volume = value
	_sfx_percent.text = _format_percent(value)


func _on_back_pressed() -> void:
	back_requested.emit()


func _init_slider(slider: HSlider, percent: Label, volume: float) -> void:
	slider.set_value_no_signal(volume)
	percent.text = _format_percent(volume)


func _format_percent(volume: float) -> String:
	return &"%d %%" % roundi(volume * 100.0)


func _on_scanlines_toggled(toggled_on: bool) -> void:
	Options.scanlines = toggled_on


func _on_curvature_toggled(toggled_on: bool) -> void:
	Options.curvature = toggled_on


func _on_crt_border_toggled(toggled_on: bool) -> void:
	Options.crt_border = toggled_on
