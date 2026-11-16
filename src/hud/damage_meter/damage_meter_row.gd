# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name DamageMeterRow
extends HBoxContainer

var _fill_style: StyleBoxFlat = null
var _last_abbr: String = ""
var _last_count: int = -1
var _last_color: Color = Color.BLACK
var _last_stats_text: String = ""

@onready var _class_label: Label = $ClassLabel
@onready var _progress_bar: ProgressBar = $ProgressBar
@onready var _stats_label: Label = $StatsLabel


func _ready() -> void:
	_fill_style = _progress_bar.get_theme_stylebox(&"fill").duplicate() as StyleBoxFlat
	_progress_bar.add_theme_stylebox_override(&"fill", _fill_style)


func setup(abbr: String, color: Color, count: int, total_dps: float, avg_dps: float, percentage: float) -> void:
	if _last_color != color:
		_last_color = color
		_fill_style.bg_color = color
		_class_label.add_theme_color_override(&"font_color", color)

	if _last_abbr != abbr or _last_count != count:
		_last_abbr = abbr
		_last_count = count
		if count >= 0:
			_class_label.text = "%s x%d" % [abbr, count]
		else:
			_class_label.text = abbr

	_progress_bar.value = percentage

	var total_str: String = DamageMeter.format_compact(total_dps)
	var new_stats_text: String
	if count >= 0:
		var avg_str: String = DamageMeter.format_compact(avg_dps)
		new_stats_text = "%s (%s) %d%%" % [total_str, avg_str, int(roundf(percentage))]
	else:
		new_stats_text = "%s (-) %d%%" % [total_str, int(roundf(percentage))]
	if _last_stats_text != new_stats_text:
		_last_stats_text = new_stats_text
		_stats_label.text = new_stats_text
