# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name HeroSelectPanel
extends MenuPanel

signal hero_selected(hero: HeroData)

const HERO_CARD_SCENE: PackedScene = preload("res://hero_select_panel/hero_select_card.tscn")

var _cards: Array[HeroSelectCard] = []

@onready var _grid: GridContainer = $VBox/GridMargin/Grid
@onready var _back_button: Button = $VBox/Buttons/Back


func _ready() -> void:
	super._ready()
	_build_cards()
	Audio.connect_menu_sounds(_grid)


func _build_cards() -> void:
	for child: Node in _grid.get_children():
		child.queue_free()
	_cards.clear()

	var heroes: Array[HeroData] = HeroData.get_heroes_by_role_order()
	for hero: HeroData in heroes:
		var card: HeroSelectCard = HERO_CARD_SCENE.instantiate() as HeroSelectCard
		card.hero_data = hero
		card.chosen.connect(_on_card_chosen)
		_grid.add_child(card)
		_cards.append(card)

	for i: int in range(4, _cards.size()):
		_cards[i].focus_neighbor_bottom = _back_button.get_path()
	if not _cards.is_empty():
		_back_button.focus_neighbor_top = _cards[mini(2, _cards.size() - 1)].get_path()
		first_focus = _cards[0]


func _on_card_chosen(hero: HeroData) -> void:
	hero_selected.emit(hero)
