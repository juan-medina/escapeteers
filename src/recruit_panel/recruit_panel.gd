# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name RecruitPanel
extends CanvasLayer

signal hero_selected(hero: HeroData)

const UNIT_CARD_SCENE: PackedScene = preload("res://unit_card/unit_card.tscn")

var _cards: Array[UnitCard] = []
var _recruit_roll_count: int = 0
var _healer_offered_early: bool = false

@onready var _cards_container: VBoxContainer = $Center/Panel/VBox/CardsContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var audio_mgr: Node = get_node_or_null(^"/root/Audio")
	if audio_mgr != null:
		audio_mgr.call(&"connect_menu_sounds", self)

	_ensure_cards()


func _ensure_cards() -> void:
	if not _cards.is_empty():
		return
	for _i: int in range(3):
		var card: UnitCard = UNIT_CARD_SCENE.instantiate() as UnitCard
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


func setup_choices(class_levels: Dictionary[StringName, int] = {}, unit_counts: Dictionary[StringName, int] = {}) -> void:
	_ensure_cards()
	_recruit_roll_count += 1
	var choices: Array[HeroData] = HeroData.get_random_choices(3)
	var priest_data: HeroData = HeroData.get_hero(&"priest")

	if priest_data != null:
		if choices.has(priest_data):
			_healer_offered_early = true
		elif _recruit_roll_count <= 2 and not _healer_offered_early and unit_counts.get(&"priest", 0) == 0:
			if _recruit_roll_count == 2 or randf() < 0.5:
				var replace_idx: int = randi_range(0, choices.size() - 1)
				choices[replace_idx] = priest_data
				_healer_offered_early = true

	var first_card: UnitCard = null

	for i: int in range(_cards.size()):
		var card: UnitCard = _cards[i]
		if i < choices.size():
			var data: HeroData = choices[i]
			card.visible = true
			card.hero_data = data
			card.level = class_levels.get(data.id, 1)
			card.unit_count = unit_counts.get(data.id, 0)
			if first_card == null:
				first_card = card
		else:
			card.visible = false

	if first_card != null:
		first_card.grab_recruit_focus()


func _on_card_chosen(hero_data: HeroData) -> void:
	visible = false
	hero_selected.emit(hero_data)
