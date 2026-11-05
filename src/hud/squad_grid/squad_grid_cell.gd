# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name SquadGridCell
extends Control


class ClassConfig:
	extends RefCounted
	var abbr: String = ""
	var color: Color = Color.WHITE

	func _init(p_abbr: String, p_color: Color) -> void:
		abbr = p_abbr
		color = p_color


const FONT_M3X6: FontFile = preload("res://data/assets/pixel_ui_theme/m3x6.ttf")
const CELL_SIZE: Vector2 = Vector2(20.0, 16.0)
const FONT_SIZE: int = 16
const COLOR_BG: Color = Color(0.06, 0.06, 0.09, 0.88)
const COLOR_BORDER: Color = Color(0.2, 0.22, 0.3, 0.6)
const COLOR_OUTLINE: Color = Color(0.04, 0.04, 0.06, 0.95)

static var _configs: Dictionary[StringName, ClassConfig] = {}
static var _default_config: ClassConfig = ClassConfig.new("????", Color(0.7, 0.7, 0.7, 1.0))

var _hero: Hero = null
var _health: float = 100.0
var _max_health: float = 100.0
var _class_color: Color = Color.WHITE
var _label: Label = null


func _init() -> void:
	custom_minimum_size = CELL_SIZE
	mouse_filter = MOUSE_FILTER_IGNORE
	_ensure_configs()

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
	unbind()


func _draw() -> void:
	# 1. Dark charcoal/black background (empty health)
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG, true)

	# 2. Vertical health fill from bottom to top using class color
	if _max_health > 0.0 and _health > 0.0:
		var ratio: float = clampf(_health / _max_health, 0.0, 1.0)
		var fill_h: float = roundf(size.y * ratio)
		if fill_h > 0.0:
			var fill_y: float = size.y - fill_h
			var fill_rect: Rect2 = Rect2(0.0, fill_y, size.x, fill_h)
			draw_rect(fill_rect, _class_color, true)

	# 3. 1px cell border
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BORDER, false, 1.0)


func bind_hero(hero: Hero) -> void:
	if hero == null or not is_instance_valid(hero) or hero.is_dead:
		unbind()
		return

	if _hero == hero:
		_sync_stats()
		visible = true
		return

	unbind()

	_hero = hero
	_hero.damaged.connect(_on_hero_damaged)
	_hero.healed.connect(_on_hero_healed)

	var class_id: StringName = &""
	if _hero.hero_data != null:
		class_id = _hero.hero_data.id

	var config: ClassConfig = _configs.get(class_id, _default_config)
	_class_color = config.color
	_label.text = config.abbr

	_sync_stats()
	visible = true


func unbind() -> void:
	if _hero != null and is_instance_valid(_hero):
		if _hero.damaged.is_connected(_on_hero_damaged):
			_hero.damaged.disconnect(_on_hero_damaged)
		if _hero.healed.is_connected(_on_hero_healed):
			_hero.healed.disconnect(_on_hero_healed)

	_hero = null
	_health = 0.0
	_max_health = 1.0
	visible = false


func get_bound_hero() -> Hero:
	return _hero


func _sync_stats() -> void:
	if _hero != null and is_instance_valid(_hero):
		_health = _hero.health
		_max_health = maxf(1.0, _hero.max_health)
	queue_redraw()


func _on_hero_damaged(_amount: float, current_health: float) -> void:
	_health = current_health
	queue_redraw()


func _on_hero_healed(_amount: float, current_health: float) -> void:
	_health = current_health
	queue_redraw()


static func _ensure_configs() -> void:
	if not _configs.is_empty():
		return

	_configs[&"archer"] = ClassConfig.new("ARCH", Color(0.333, 0.651, 0.188, 1.0))
	_configs[&"armored_axeman"] = ClassConfig.new("AXEM", Color(0.906, 0.435, 0.318, 1.0))
	_configs[&"knight"] = ClassConfig.new("KNGH", Color(0.227, 0.525, 1.0, 1.0))
	_configs[&"knight_templar"] = ClassConfig.new("TMPL", Color(1.0, 0.820, 0.400, 1.0))
	_configs[&"priest"] = ClassConfig.new("PRST", Color(0.878, 0.984, 0.988, 1.0))
	_configs[&"soldier"] = ClassConfig.new("SOLD", Color(0.753, 0.224, 0.169, 1.0))
	_configs[&"swordsman"] = ClassConfig.new("SWRD", Color(0.165, 0.616, 0.561, 1.0))
	_configs[&"wizard"] = ClassConfig.new("WIZD", Color(0.608, 0.365, 0.898, 1.0))
