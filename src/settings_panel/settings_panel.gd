# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name SettingsPanel
extends MenuPanel

@onready var _fullscreen_check: CheckButton = $VBox/Fullscreen
@onready var _scanlines_check: CheckButton = $VBox/Scanlines
@onready var _curvature_check: CheckButton = $VBox/Curvature
@onready var _crt_border_check: CheckButton = $VBox/CrtBorder
@onready var _master_volume: VolumeSlider = $VBox/MasterVolume
@onready var _music_volume: VolumeSlider = $VBox/MusicVolume
@onready var _sfx_volume: VolumeSlider = $VBox/SfxVolume


func _ready() -> void:
	super._ready()
	Options.fullscreen_changed.connect(_on_fullscreen_changed)
	_on_fullscreen_changed(Options.fullscreen)
	_master_volume.set_value_no_signal(Options.master_volume)
	_music_volume.set_value_no_signal(Options.music_volume)
	_sfx_volume.set_value_no_signal(Options.sfx_volume)
	_scanlines_check.set_pressed_no_signal(Options.scanlines)
	_curvature_check.set_pressed_no_signal(Options.curvature)
	_crt_border_check.set_pressed_no_signal(Options.crt_border)


func _exit_tree() -> void:
	Options.fullscreen_changed.disconnect(_on_fullscreen_changed)


func _on_fullscreen_changed(is_on: bool) -> void:
	_fullscreen_check.set_pressed_no_signal(is_on)


func _on_fullscreen_toggled(is_on: bool) -> void:
	Options.fullscreen = is_on


func _on_master_volume_changed(value: float) -> void:
	Options.master_volume = value


func _on_music_volume_changed(value: float) -> void:
	Options.music_volume = value


func _on_sfx_volume_changed(value: float) -> void:
	Options.sfx_volume = value


func _on_scanlines_toggled(toggled_on: bool) -> void:
	Options.scanlines = toggled_on


func _on_curvature_toggled(toggled_on: bool) -> void:
	Options.curvature = toggled_on


func _on_crt_border_toggled(toggled_on: bool) -> void:
	Options.crt_border = toggled_on
