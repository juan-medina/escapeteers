# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name RecruitPanel
extends UiPanel

signal hero_selected(hero: HeroData)
signal reroll_requested

const MAX_CHOICES: int = 3

var _recruit_roll_count: int = 0
var _healer_offered_early: bool = false
var _cards_by_id: Dictionary[StringName, UnitCard] = {}
var _current_choice_ids: Array[StringName] = []
var _visible_cards: Array[UnitCard] = []
var _last_inspected_card: UnitCard = null

@onready var _cards_container: HBoxContainer = $Center/Panel/VBox/CardsContainer
@onready var _details_panel: UnitDetailsPanel = $Center/Panel/VBox/UnitDetailsPanel
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


func setup_choices(
	class_levels: Dictionary[StringName, int], unit_counts: Dictionary[StringName, int], forced_hero_id: StringName = &"", reroll_coins: int = 0
) -> void:
	var choices: Array[HeroData] = _roll_choices(unit_counts, forced_hero_id)
	_apply_choices(choices, class_levels, unit_counts)
	_update_reroll_ui(reroll_coins, forced_hero_id == &"")
	grab_first_focus()


func reroll_choices(class_levels: Dictionary[StringName, int], unit_counts: Dictionary[StringName, int], reroll_coins: int) -> void:
	var choices: Array[HeroData] = HeroData.get_random_choices(MAX_CHOICES, unit_counts, _current_choice_ids)
	if choices.has(HeroData.get_hero(&"priest")):
		_healer_offered_early = true
	_apply_choices(choices, class_levels, unit_counts)
	_update_reroll_ui(reroll_coins, true)
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
		var card: UnitCard = _cards_by_id[data.id]
		var lvl: int = class_levels.get(data.id, 1)
		var count: int = unit_counts.get(data.id, 0)
		_cards_container.move_child(card, i)
		card.update_stats(lvl, count)
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


func _on_card_inspected(hero_data: HeroData, target_level: int, prev_level: int) -> void:
	_details_panel.show_hero(hero_data, target_level, prev_level)
	_last_inspected_card = _cards_by_id[hero_data.id]
	_update_reroll_top_neighbor()


func _on_reroll_pressed() -> void:
	reroll_requested.emit()
