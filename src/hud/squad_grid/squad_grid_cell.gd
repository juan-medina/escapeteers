# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name SquadGridCell
extends Control

const FONT_M3X6: FontFile = preload("res://data/assets/pixel_ui_theme/m3x6.ttf")
const CELL_SIZE: Vector2 = Vector2(20.0, 16.0)
const FONT_SIZE: int = 16
const COLOR_BG: Color = Color(0.06, 0.06, 0.09, 0.88)
const COLOR_BORDER: Color = Color(0.2, 0.22, 0.3, 0.6)
const COLOR_OUTLINE: Color = Color(0.04, 0.04, 0.06, 0.95)

var _hero: Hero = null
var _max_health: float = 100.0
var _fill_height: int = -1
var _class_color: Color = Color.WHITE
var _label: Label = null


func _init() -> void:
	custom_minimum_size = CELL_SIZE
	mouse_filter = MOUSE_FILTER_IGNORE

	_label = Label.new()
	_label.mouse_filter = MOUSE_FILTER_IGNORE
	_label.set_anchors_preset(PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_override(&"font", FONT_M3X6)
	_label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_label.add_theme_color_override(&"font_color", Color.WHITE)
	_label.add_theme_color_override(&"font_outline_color", COLOR_OUTLINE)
	_label.add_theme_constant_override(&"outline_size", 1)
	add_child(_label)


func _exit_tree() -> void:
	_disconnect_hero()


func _draw() -> void:
	# 1. Dark charcoal/black background (empty health)
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG, true)

	# 2. Vertical health fill from bottom to top using class color
	if _fill_height > 0:
		var fill_h: float = float(_fill_height)
		var fill_y: float = size.y - fill_h
		var fill_rect: Rect2 = Rect2(0.0, fill_y, size.x, fill_h)
		draw_rect(fill_rect, _class_color, true)

	# 3. 1px cell border
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BORDER, false, 1.0)


func bind_hero(hero: Hero) -> void:
	if _hero == hero:
		_max_health = maxf(1.0, _hero.max_health)
		_update_fill_height(_hero.health)
		if not visible:
			visible = true
		return

	_disconnect_hero()

	_hero = hero
	_hero.damaged.connect(_on_hero_damaged)
	_hero.healed.connect(_on_hero_healed)

	var data: HeroData = _hero.hero_data
	_label.text = data.abbr
	if _class_color != data.color:
		_class_color = data.color
		queue_redraw()

	_max_health = maxf(1.0, _hero.max_health)
	_update_fill_height(_hero.health)
	if not visible:
		visible = true


func unbind() -> void:
	_disconnect_hero()
	_fill_height = -1
	_max_health = 1.0
	if visible:
		visible = false


func get_bound_hero() -> Hero:
	return _hero


func _disconnect_hero() -> void:
	if _hero != null:
		_hero.damaged.disconnect(_on_hero_damaged)
		_hero.healed.disconnect(_on_hero_healed)
		_hero = null


func _update_fill_height(current_health: float) -> void:
	var new_fill_h: int = 0
	if _max_health > 0.0 and current_health > 0.0:
		var ratio: float = clampf(current_health / _max_health, 0.0, 1.0)
		new_fill_h = roundi(maxf(size.y, CELL_SIZE.y) * ratio)
	if new_fill_h != _fill_height:
		_fill_height = new_fill_h
		queue_redraw()


func _on_hero_damaged(_amount: float, current_health: float) -> void:
	_update_fill_height(current_health)


func _on_hero_healed(_amount: float, current_health: float) -> void:
	_update_fill_height(current_health)
