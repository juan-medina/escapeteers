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

	_populate_choices()


func _populate_choices() -> void:
	for child: Node in _cards_container.get_children():
		child.queue_free()

	var choices: Array[HeroData] = HeroData.get_random_choices(3)
	var first_card: UnitCard = null

	for data: HeroData in choices:
		var card: UnitCard = UNIT_CARD_SCENE.instantiate() as UnitCard
		card.hero_data = data
		card.chosen.connect(_on_card_chosen)
		_cards_container.add_child(card)
		if first_card == null:
			first_card = card

	if first_card != null:
		first_card.grab_recruit_focus()


func _on_card_chosen(hero_data: HeroData) -> void:
	hero_selected.emit(hero_data)
	queue_free()
