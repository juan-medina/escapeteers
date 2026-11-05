# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name DamageMeterRow
extends HBoxContainer

const FONT_M3X6: FontFile = preload("res://data/assets/pixel_ui_theme/m3x6.ttf")

var _class_label: Label = null
var _progress_bar: ProgressBar = null
var _stats_label: Label = null
var _fill_style: StyleBoxFlat = null

var _last_abbr: String = ""
var _last_count: int = -1
var _last_color: Color = Color.BLACK
var _last_stats_text: String = ""


func _init() -> void:
	custom_minimum_size = Vector2(126.0, 11.0)
	add_theme_constant_override(&"separation", 4)

	_class_label = Label.new()
	_class_label.custom_minimum_size = Vector2(34.0, 0.0)
	_class_label.add_theme_font_override(&"font", FONT_M3X6)
	_class_label.text = "??? x0"
	add_child(_class_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(24.0, 5.0)
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress_bar.max_value = 100.0
	_progress_bar.show_percentage = false

	_fill_style = StyleBoxFlat.new()
	_fill_style.corner_radius_top_left = 2
	_fill_style.corner_radius_top_right = 2
	_fill_style.corner_radius_bottom_left = 2
	_fill_style.corner_radius_bottom_right = 2
	_progress_bar.add_theme_stylebox_override(&"fill", _fill_style)
	add_child(_progress_bar)

	_stats_label = Label.new()
	_stats_label.custom_minimum_size = Vector2(48.0, 0.0)
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats_label.add_theme_font_override(&"font", FONT_M3X6)
	_stats_label.add_theme_color_override(&"font_color", Color(0.85, 0.85, 0.85, 1.0))
	_stats_label.text = "0 (0) 0%"
	add_child(_stats_label)


func setup(abbr: String, color: Color, count: int, total_dps: float, avg_dps: float, percentage: float) -> void:
	if _last_color != color:
		_last_color = color
		if _fill_style != null:
			_fill_style.bg_color = color
		_class_label.add_theme_color_override(&"font_color", color)

	if _last_abbr != abbr or _last_count != count:
		_last_abbr = abbr
		_last_count = count
		_class_label.text = "%s x%d" % [abbr, count]

	_progress_bar.value = percentage

	var total_str: String = DamageMeter.format_compact(total_dps)
	var avg_str: String = DamageMeter.format_compact(avg_dps)
	var new_stats_text: String = "%s (%s) %d%%" % [total_str, avg_str, int(roundf(percentage))]
	if _last_stats_text != new_stats_text:
		_last_stats_text = new_stats_text
		_stats_label.text = new_stats_text
