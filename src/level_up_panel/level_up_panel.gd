# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name LevelUpPanel
extends UiPanel

signal class_leveled_up(hero_data: HeroData)
signal reroll_requested

const MAX_CHOICES: int = 3

var _cards_by_id: Dictionary[StringName, UnitCard] = {}
var _current_choice_ids: Array[StringName] = []

@onready var _cards_container: VBoxContainer = $Center/Panel/VBox/CardsContainer
@onready var _coin_count_label: Label = $Center/Panel/VBox/RerollRow/CoinCountLabel
@onready var _reroll_button: Button = $Center/Panel/VBox/RerollRow/RerollButton


func _ready() -> void:
	for child: Node in _cards_container.get_children():
		var card: UnitCard = child as UnitCard
		_cards_by_id[card.hero_id] = card
	super._ready()


func initialize() -> void:
	for card: UnitCard in _cards_by_id.values():
		card.initialize()


func setup_choices(class_levels: Dictionary[StringName, int], unit_counts: Dictionary[StringName, int], reroll_coins: int = 0) -> void:
	var choices: Array[HeroData] = _roll_choices(class_levels, unit_counts)
	_apply_choices(choices, class_levels, unit_counts)
	_update_reroll_ui(reroll_coins, unit_counts.size() > MAX_CHOICES)
	grab_first_focus()


func reroll_choices(class_levels: Dictionary[StringName, int], unit_counts: Dictionary[StringName, int], reroll_coins: int) -> void:
	var choices: Array[HeroData] = _roll_reroll_choices(class_levels, unit_counts)
	_apply_choices(choices, class_levels, unit_counts)
	_update_reroll_ui(reroll_coins, unit_counts.size() > MAX_CHOICES)
	if _reroll_button.disabled:
		grab_first_focus()


func _apply_choices(choices: Array[HeroData], class_levels: Dictionary[StringName, int], unit_counts: Dictionary[StringName, int]) -> void:
	for card: UnitCard in _cards_by_id.values():
		card.visible = false
	_current_choice_ids.clear()

	var choice_count: int = mini(choices.size(), MAX_CHOICES)
	for i: int in range(choice_count):
		var data: HeroData = choices[i]
		_current_choice_ids.append(data.id)
		var cur_lvl: int = class_levels.get(data.id, 1)
		var count: int = unit_counts.get(data.id, 0)
		var card: UnitCard = _cards_by_id[data.id]
		_cards_container.move_child(card, i)
		card.update_stats(cur_lvl + 1, count, cur_lvl)
		card.visible = true
		if i == 0:
			first_focus = card.get_recruit_button()


func _update_reroll_ui(reroll_coins: int, can_reroll: bool) -> void:
	_coin_count_label.text = &"Coins: %d" % reroll_coins
	_reroll_button.disabled = not (can_reroll and reroll_coins > 0)
	_reroll_button.focus_mode = Control.FOCUS_NONE if _reroll_button.disabled else Control.FOCUS_ALL


func _roll_choices(class_levels: Dictionary[StringName, int], unit_counts: Dictionary[StringName, int]) -> Array[HeroData]:
	var candidates: Array[HeroData] = []
	for id: StringName in unit_counts:
		candidates.append(HeroData.get_hero(id))

	if candidates.size() < 4:
		candidates.shuffle()
		return candidates.slice(0, mini(candidates.size(), MAX_CHOICES))

	var weights: Array[float] = _build_level_weights(candidates, class_levels)
	return HeroData.pick_weighted_choices(candidates, weights, MAX_CHOICES)


func _roll_reroll_choices(class_levels: Dictionary[StringName, int], unit_counts: Dictionary[StringName, int]) -> Array[HeroData]:
	var fresh: Array[HeroData] = []
	var previous: Array[HeroData] = []
	for id: StringName in unit_counts:
		var hero: HeroData = HeroData.get_hero(id)
		if _current_choice_ids.has(id):
			previous.append(hero)
		else:
			fresh.append(hero)

	var fresh_weights: Array[float] = _build_level_weights(fresh, class_levels)
	var choices: Array[HeroData] = HeroData.pick_weighted_choices(fresh, fresh_weights, MAX_CHOICES)
	if choices.size() < MAX_CHOICES and not previous.is_empty():
		var prev_weights: Array[float] = _build_level_weights(previous, class_levels)
		choices.append_array(HeroData.pick_weighted_choices(previous, prev_weights, MAX_CHOICES - choices.size()))
	return choices


static func _build_level_weights(candidates: Array[HeroData], class_levels: Dictionary[StringName, int]) -> Array[float]:
	var weights: Array[float] = []
	for hero: HeroData in candidates:
		var raw_lvl: int = class_levels.get(hero.id, 1)
		var lvl: int = maxi(raw_lvl, 1)
		weights.append(1.0 / float(lvl))
	return weights


func _on_card_chosen(hero_data: HeroData) -> void:
	visible = false
	class_leveled_up.emit(hero_data)


func _on_reroll_pressed() -> void:
	reroll_requested.emit()
