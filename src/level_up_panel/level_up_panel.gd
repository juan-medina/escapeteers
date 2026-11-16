# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name LevelUpPanel
extends UiPanel

signal class_leveled_up(hero_data: HeroData)

const MAX_CHOICES: int = 3

var _cards_by_id: Dictionary[StringName, UnitCard] = {}

@onready var _cards_container: VBoxContainer = $Center/Panel/VBox/CardsContainer


func _ready() -> void:
	for child: Node in _cards_container.get_children():
		var card: UnitCard = child as UnitCard
		_cards_by_id[card.hero_id] = card
	super._ready()


func setup_choices(class_levels: Dictionary[StringName, int], unit_counts: Dictionary[StringName, int]) -> void:
	for card: UnitCard in _cards_by_id.values():
		card.visible = false

	var candidates: Array[HeroData] = []
	for id: StringName in unit_counts:
		candidates.append(HeroData.get_hero(id))

	candidates.shuffle()

	var choice_count: int = mini(candidates.size(), MAX_CHOICES)
	for i: int in range(choice_count):
		var data: HeroData = candidates[i]
		var cur_lvl: int = class_levels.get(data.id, 1)
		var count: int = unit_counts.get(data.id, 0)
		var card: UnitCard = _cards_by_id[data.id]
		_cards_container.move_child(card, i)
		card.update_stats(cur_lvl + 1, count, cur_lvl)
		card.visible = true
		if i == 0:
			first_focus = card.get_recruit_button()

	grab_first_focus()


func _on_card_chosen(hero_data: HeroData) -> void:
	visible = false
	class_leveled_up.emit(hero_data)
