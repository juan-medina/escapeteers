# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name ClassBreakdownRow
extends HBoxContainer

var _fill_style: StyleBoxFlat = null

@onready var _class_label: Label = $ClassLabel
@onready var _damage_bar: ProgressBar = $DamageBar
@onready var _stats_label: Label = $StatsLabel


func _ready() -> void:
	_fill_style = _damage_bar.get_theme_stylebox(&"fill").duplicate() as StyleBoxFlat
	_damage_bar.add_theme_stylebox_override(&"fill", _fill_style)


func setup(entry: RunStats.ClassBreakdownEntry, max_damage: float) -> void:
	_class_label.text = &"%s Lv.%d" % [entry.abbr, entry.level]
	_class_label.add_theme_color_override(&"font_color", entry.color)
	_fill_style.bg_color = entry.color
	_damage_bar.max_value = maxf(1.0, max_damage)
	_damage_bar.value = entry.total_damage
	_stats_label.text = &"%s  %s/s" % [DamageMeter.format_compact(entry.total_damage), DamageMeter.format_compact(entry.dps)]
