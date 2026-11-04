# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name LevelUpPanel
extends CanvasLayer

signal class_leveled_up(hero_data: HeroData)

const UNIT_CARD_SCENE: PackedScene = preload("res://unit_card/unit_card.tscn")

@onready var _cards_container: VBoxContainer = $Center/Panel/VBox/CardsContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var audio_mgr: Node = get_node_or_null(^"/root/Audio")
	if audio_mgr != null:
		audio_mgr.call(&"connect_menu_sounds", self)


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


func setup_choices(squad: Array[Hero], class_levels: Dictionary[StringName, int]) -> void:
	for child: Node in _cards_container.get_children():
		child.queue_free()

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

	for i: int in range(pick_count):
		var hero_data: HeroData = candidate_list[i]
		var cur_lvl: int = class_levels.get(hero_data.id, 1)
		var next_lvl: int = cur_lvl + 1
		var card: UnitCard = UNIT_CARD_SCENE.instantiate() as UnitCard
		card.hero_data = hero_data
		card.previous_level = cur_lvl
		card.level = next_lvl
		card.unit_count = class_counts.get(hero_data.id, 0)
		card.button_text = "Level Up"
		card.chosen.connect(_on_card_chosen)
		_cards_container.add_child(card)
		if first_card == null:
			first_card = card

	if first_card != null:
		first_card.grab_recruit_focus()


func _on_card_chosen(hero_data: HeroData) -> void:
	class_leveled_up.emit(hero_data)
	queue_free()
