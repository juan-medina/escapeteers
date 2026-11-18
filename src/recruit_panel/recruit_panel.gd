# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name RecruitPanel
extends UiPanel

signal hero_selected(hero: HeroData)

const MAX_CHOICES: int = 3

var _recruit_roll_count: int = 0
var _healer_offered_early: bool = false
var _cards_by_id: Dictionary[StringName, UnitCard] = {}

@onready var _cards_container: VBoxContainer = $Center/Panel/VBox/CardsContainer


func _ready() -> void:
	for child: Node in _cards_container.get_children():
		var card: UnitCard = child as UnitCard
		_cards_by_id[card.hero_id] = card
	super._ready()


func initialize() -> void:
	for card: UnitCard in _cards_by_id.values():
		card.initialize()


func setup_choices(class_levels: Dictionary[StringName, int], unit_counts: Dictionary[StringName, int], forced_hero_id: StringName = &"") -> void:
	for card: UnitCard in _cards_by_id.values():
		card.visible = false

	var choices: Array[HeroData] = _roll_choices(unit_counts, forced_hero_id)
	var choice_count: int = mini(choices.size(), MAX_CHOICES)

	for i: int in range(choice_count):
		var data: HeroData = choices[i]
		var card: UnitCard = _cards_by_id[data.id]
		var lvl: int = class_levels.get(data.id, 1)
		var count: int = unit_counts.get(data.id, 0)
		_cards_container.move_child(card, i)
		card.update_stats(lvl, count)
		card.visible = true
		if i == 0:
			first_focus = card.get_recruit_button()

	grab_first_focus()


func _roll_choices(unit_counts: Dictionary[StringName, int], forced_hero_id: StringName) -> Array[HeroData]:
	if forced_hero_id != &"":
		return [HeroData.get_hero(forced_hero_id)]

	_recruit_roll_count += 1
	var choices: Array[HeroData] = HeroData.get_random_choices(MAX_CHOICES, unit_counts)
	var priest_data: HeroData = HeroData.get_hero(&"priest")
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
