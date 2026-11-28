# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name ScoreCardRow
extends HBoxContainer

const POSITIVE_COLOR: Color = Color(0.45, 0.95, 0.58, 1.0)
const NEGATIVE_COLOR: Color = Color(0.95, 0.42, 0.42, 1.0)
const ZERO_COLOR: Color = Color(0.60, 0.65, 0.72, 1.0)

@onready var _name_label: Label = $NameLabel
@onready var _detail_label: Label = $DetailLabel
@onready var _points_label: Label = $PointsLabel


func setup(line: RunScore.ScoreLine) -> void:
	_name_label.text = line.label
	_detail_label.text = line.detail
	if line.points > 0:
		_points_label.text = &"+%d" % line.points
		_points_label.add_theme_color_override(&"font_color", POSITIVE_COLOR)
	elif line.points < 0:
		_points_label.text = &"%d" % line.points
		_points_label.add_theme_color_override(&"font_color", NEGATIVE_COLOR)
	else:
		_points_label.text = &"0"
		_points_label.add_theme_color_override(&"font_color", ZERO_COLOR)
