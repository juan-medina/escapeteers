# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name LevelUpPanel
extends CanvasLayer

signal class_leveled_up(hero_data: HeroData)

const UNIT_CARD_SCENE: PackedScene = preload("res://unit_card/unit_card.tscn")

var _cards: Array[UnitCard] = []

@onready var _cards_container: VBoxContainer = $Center/Panel/VBox/CardsContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Audio.connect_menu_sounds(self)
	_ensure_cards()


func _ensure_cards() -> void:
	if not _cards.is_empty():
		return
	for _i: int in range(3):
		var card: UnitCard = UNIT_CARD_SCENE.instantiate() as UnitCard
		card.button_text = "Level Up"
		card.chosen.connect(_on_card_chosen)
		_cards_container.add_child(card)
		_cards.append(card)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"back"):
		get_viewport().set_input_as_handled()
		_ensure_focus()


func _ensure_focus() -> void:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner != null and is_ancestor_of(focus_owner):
		return
	if not _cards.is_empty() and _cards[0].visible:
		_cards[0].grab_recruit_focus()


func setup_choices(squad: Array[Hero], class_levels: Dictionary[StringName, int]) -> void:
	_ensure_cards()
	var unique_classes: Dictionary[StringName, HeroData] = {}
	var class_counts: Dictionary[StringName, int] = {}
	for h: Hero in squad:
		if is_instance_valid(h) and not h.is_dead and h.hero_data != null:
			var id: StringName = h.hero_data.id
			unique_classes[id] = h.hero_data
			class_counts[id] = class_counts.get(id, 0) + 1

	var candidate_list: Array[HeroData] = []
	for hero_data: HeroData in unique_classes.values():
		candidate_list.append(hero_data)

	candidate_list.shuffle()
	var pick_count: int = mini(3, candidate_list.size())
	var first_card: UnitCard = null

	for i: int in range(_cards.size()):
		var card: UnitCard = _cards[i]
		if i < pick_count:
			var hero_data: HeroData = candidate_list[i]
			var cur_lvl: int = class_levels.get(hero_data.id, 1)
			card.visible = true
			card.hero_data = hero_data
			card.previous_level = cur_lvl
			card.level = cur_lvl + 1
			card.unit_count = class_counts.get(hero_data.id, 0)
			if first_card == null:
				first_card = card
		else:
			card.visible = false

	if first_card != null:
		first_card.grab_recruit_focus()


func _on_card_chosen(hero_data: HeroData) -> void:
	visible = false
	class_leveled_up.emit(hero_data)
