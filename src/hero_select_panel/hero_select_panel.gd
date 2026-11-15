# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name HeroSelectPanel
extends MenuPanel

signal hero_selected(hero: HeroData)

@onready var _cards: Array[HeroSelectCard] = [
	$VBox/GridMargin/Grid/Card1,
	$VBox/GridMargin/Grid/Card2,
	$VBox/GridMargin/Grid/Card3,
	$VBox/GridMargin/Grid/Card4,
	$VBox/GridMargin/Grid/Card5,
	$VBox/GridMargin/Grid/Card6,
	$VBox/GridMargin/Grid/Card7,
	$VBox/GridMargin/Grid/Card8,
]


func _ready() -> void:
	var heroes: Array[HeroData] = HeroData.get_heroes_by_role_order()
	for i: int in range(_cards.size()):
		var card: HeroSelectCard = _cards[i]
		if i < heroes.size():
			card.visible = true
			card.setup(heroes[i])
		else:
			card.visible = false
	super._ready()


func _on_card_chosen(hero: HeroData) -> void:
	hero_selected.emit(hero)
