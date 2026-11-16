# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name HeroSelectPanel
extends MenuPanel

signal hero_selected(hero: HeroData)


func _on_card_chosen(hero: HeroData) -> void:
	hero_selected.emit(hero)
