# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name HeroSelectPanel
extends MenuPanel

signal hero_selected(hero: HeroData)

@onready var _grid: GridContainer = $VBox/GridMargin/Grid


func initialize() -> void:
	for child: Node in _grid.get_children():
		(child as HeroSelectCard).initialize()


func _on_card_chosen(hero: HeroData) -> void:
	hero_selected.emit(hero)
