# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name SquadGridCell
extends Control

var _hero: Hero = null
var _fill_style: StyleBoxFlat = null

@onready var _health_bar: ProgressBar = $ProgressBar
@onready var _label: Label = $Label


func _ready() -> void:
	_fill_style = _health_bar.get_theme_stylebox(&"fill").duplicate() as StyleBoxFlat
	_health_bar.add_theme_stylebox_override(&"fill", _fill_style)


func _exit_tree() -> void:
	_disconnect_hero()


func bind_hero(hero: Hero) -> void:
	if _hero == hero:
		_update_health(_hero.health, _hero.max_health)
		if not visible:
			visible = true
		return

	_disconnect_hero()

	_hero = hero
	_hero.damaged.connect(_on_hero_damaged)
	_hero.healed.connect(_on_hero_healed)

	var data: HeroData = _hero.hero_data
	_label.text = data.abbr
	_fill_style.bg_color = data.color

	_update_health(_hero.health, _hero.max_health)
	if not visible:
		visible = true


func unbind() -> void:
	_disconnect_hero()
	_health_bar.max_value = 1.0
	_health_bar.value = 0.0
	if visible:
		visible = false


func _disconnect_hero() -> void:
	if _hero != null:
		_hero.damaged.disconnect(_on_hero_damaged)
		_hero.healed.disconnect(_on_hero_healed)
		_hero = null


func _update_health(current_health: float, max_health: float) -> void:
	var safe_max: float = maxf(1.0, max_health)
	_health_bar.max_value = safe_max
	_health_bar.value = clampf(current_health, 0.0, safe_max)


func _on_hero_damaged(_amount: float, current_health: float) -> void:
	_update_health(current_health, _hero.max_health)


func _on_hero_healed(_amount: float, current_health: float) -> void:
	_update_health(current_health, _hero.max_health)
