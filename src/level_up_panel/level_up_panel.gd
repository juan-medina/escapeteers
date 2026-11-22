# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name LevelUpPanel
extends UiPanel

signal class_leveled_up(hero_data: HeroData)
signal reroll_requested

const MAX_CHOICES: int = 3

var _cards_by_id: Dictionary[StringName, UnitCard] = {}
var _current_choice_ids: Array[StringName] = []
var _visible_cards: Array[UnitCard] = []
var _last_inspected_card: UnitCard = null

@onready var _cards_container: HBoxContainer = $Center/Panel/VBox/CardsContainer
@onready var _details_panel: UnitDetailsPanel = $Center/Panel/VBox/UnitDetailsPanel
@onready var _coin_count_label: Label = $Center/Panel/VBox/RerollRow/CoinCountLabel
@onready var _reroll_button: Button = $Center/Panel/VBox/RerollRow/RerollButton


static func _build_level_weights(candidates: Array[HeroData], class_levels: Dictionary[StringName, int]) -> Array[float]:
	var weights: Array[float] = []
	for hero: HeroData in candidates:
		var raw_lvl: int = class_levels.get(hero.id, 1)
		var lvl: int = maxi(raw_lvl, 1)
		weights.append(1.0 / float(lvl))
	return weights


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
	_visible_cards.clear()
	_last_inspected_card = null

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
		_visible_cards.append(card)
		if i == 0:
			first_focus = card

	if not _visible_cards.is_empty():
		_last_inspected_card = _visible_cards[0]
		_visible_cards[0].emit_inspected()


func _update_reroll_ui(reroll_coins: int, can_reroll: bool) -> void:
	_coin_count_label.text = &"Coins: %d" % reroll_coins
	_reroll_button.disabled = not (can_reroll and reroll_coins > 0)
	_reroll_button.focus_mode = Control.FOCUS_NONE if _reroll_button.disabled else Control.FOCUS_ALL
	_update_focus_neighbors()


func _update_focus_neighbors() -> void:
	var count: int = _visible_cards.size()
	var bottom_path: NodePath = _reroll_button.get_path() if not _reroll_button.disabled else NodePath()
	for i: int in range(count):
		var card: UnitCard = _visible_cards[i]
		var left_idx: int = (i - 1 + count) % count
		var right_idx: int = (i + 1) % count
		card.focus_neighbor_left = _visible_cards[left_idx].get_path() if count > 1 else NodePath()
		card.focus_neighbor_right = _visible_cards[right_idx].get_path() if count > 1 else NodePath()
		card.focus_neighbor_top = NodePath()
		card.focus_neighbor_bottom = bottom_path

	_update_reroll_top_neighbor()


func _update_reroll_top_neighbor() -> void:
	if _reroll_button.disabled or _visible_cards.is_empty():
		_reroll_button.focus_neighbor_top = NodePath()
		return
	var target: UnitCard = _last_inspected_card if (_last_inspected_card != null and _last_inspected_card.visible) else _visible_cards[0]
	_reroll_button.focus_neighbor_top = target.get_path()


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


func _on_card_chosen(hero_data: HeroData) -> void:
	visible = false
	class_leveled_up.emit(hero_data)


func _on_card_inspected(hero_data: HeroData, target_level: int, prev_level: int) -> void:
	_details_panel.show_hero(hero_data, target_level, prev_level)
	_last_inspected_card = _cards_by_id[hero_data.id]
	_update_reroll_top_neighbor()


func _on_reroll_pressed() -> void:
	reroll_requested.emit()
