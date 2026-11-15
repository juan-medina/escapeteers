# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name RecruitPanel
extends UiPanel

signal hero_selected(hero: HeroData)

var _recruit_roll_count: int = 0
var _healer_offered_early: bool = false

@onready var _cards: Array[UnitCard] = [
	$Center/Panel/VBox/CardsContainer/Card1,
	$Center/Panel/VBox/CardsContainer/Card2,
	$Center/Panel/VBox/CardsContainer/Card3,
]


func _ready() -> void:
	first_focus = _cards[0].get_recruit_button()
	super._ready()


func setup_choices(class_levels: Dictionary[StringName, int], unit_counts: Dictionary[StringName, int], forced_hero_id: StringName = &"") -> void:
	var choices: Array[HeroData] = _roll_choices(unit_counts, forced_hero_id)

	for i: int in range(_cards.size()):
		var card: UnitCard = _cards[i]
		if i < choices.size():
			var data: HeroData = choices[i]
			var lvl: int = class_levels.get(data.id, 1)
			var count: int = unit_counts.get(data.id, 0)
			card.visible = true
			card.setup(data, lvl, count)
		else:
			card.visible = false

	grab_first_focus()


func _roll_choices(unit_counts: Dictionary[StringName, int], forced_hero_id: StringName) -> Array[HeroData]:
	if forced_hero_id != &"":
		var forced_data: HeroData = HeroData.get_hero(forced_hero_id)
		if forced_data != null:
			return [forced_data]
		return []

	_recruit_roll_count += 1
	var choices: Array[HeroData] = HeroData.get_random_choices(_cards.size())
	var priest_data: HeroData = HeroData.get_hero(&"priest")
	if priest_data != null:
		if choices.has(priest_data):
			_healer_offered_early = true
		elif _recruit_roll_count <= 2 and not _healer_offered_early and unit_counts.get(&"priest", 0) == 0:
			if _recruit_roll_count == 2 or randf() < 0.5:
				var replace_idx: int = randi_range(0, choices.size() - 1)
				choices[replace_idx] = priest_data
				_healer_offered_early = true
	return choices


func _on_card_chosen(hero_data: HeroData) -> void:
	visible = false
	hero_selected.emit(hero_data)
