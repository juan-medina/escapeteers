# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name RecruitPanel
extends CanvasLayer

signal hero_selected(hero: HeroData)

const UNIT_CARD_SCENE: PackedScene = preload("res://unit_card/unit_card.tscn")

@onready var _cards_container: VBoxContainer = $Center/Panel/VBox/CardsContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var audio_mgr: Node = get_node_or_null(^"/root/Audio")
	if audio_mgr != null:
		audio_mgr.call(&"connect_menu_sounds", self)

	if _cards_container.get_child_count() == 0:
		setup_choices()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"back"):
		get_viewport().set_input_as_handled()
		_ensure_focus()


func _ensure_focus() -> void:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner != null and is_ancestor_of(focus_owner):
		return
	if _cards_container.get_child_count() > 0:
		var first_card: UnitCard = _cards_container.get_child(0) as UnitCard
		if first_card != null:
			first_card.grab_recruit_focus()


func setup_choices(class_levels: Dictionary[StringName, int] = {}) -> void:
	for child: Node in _cards_container.get_children():
		child.queue_free()

	var choices: Array[HeroData] = HeroData.get_random_choices(3)
	var first_card: UnitCard = null

	for data: HeroData in choices:
		var card: UnitCard = UNIT_CARD_SCENE.instantiate() as UnitCard
		card.hero_data = data
		card.level = class_levels.get(data.id, 1)
		card.chosen.connect(_on_card_chosen)
		_cards_container.add_child(card)
		if first_card == null:
			first_card = card

	if first_card != null:
		first_card.grab_recruit_focus()


func _on_card_chosen(hero_data: HeroData) -> void:
	hero_selected.emit(hero_data)
	queue_free()
