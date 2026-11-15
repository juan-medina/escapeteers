# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name LevelUpPanel
extends UiPanel

signal class_leveled_up(hero_data: HeroData)

@onready var _cards: Array[UnitCard] = [
	$Center/Panel/VBox/CardsContainer/Card1,
	$Center/Panel/VBox/CardsContainer/Card2,
	$Center/Panel/VBox/CardsContainer/Card3,
]


func _ready() -> void:
	first_focus = _cards[0].get_recruit_button()
	super._ready()


func setup_choices(class_levels: Dictionary[StringName, int], unit_counts: Dictionary[StringName, int]) -> void:
	var candidates: Array[HeroData] = []
	for id: StringName in unit_counts:
		var hero_data: HeroData = HeroData.get_hero(id)
		if hero_data != null:
			candidates.append(hero_data)

	candidates.shuffle()

	for i: int in range(_cards.size()):
		var card: UnitCard = _cards[i]
		if i < candidates.size():
			var data: HeroData = candidates[i]
			var cur_lvl: int = class_levels.get(data.id, 1)
			var count: int = unit_counts.get(data.id, 0)
			card.visible = true
			card.setup(data, cur_lvl + 1, count, cur_lvl)
		else:
			card.visible = false

	grab_first_focus()


func _on_card_chosen(hero_data: HeroData) -> void:
	visible = false
	class_leveled_up.emit(hero_data)
