# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name CodexUnitsPanel
extends MenuPanel

@export var cards_container: Container = null
@export var details_panel: CodexDetailsPanel = null

var _cards_by_id: Dictionary[StringName, CodexEntryCard] = {}


func _ready() -> void:
	for child: Node in cards_container.get_children():
		var card: CodexEntryCard = child as CodexEntryCard
		_cards_by_id[card.entry_id] = card
	Codex.unread_changed.connect(_refresh_all_cards)
	super._ready()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready() and is_visible_in_tree():
		var start_card: CodexEntryCard = first_focus as CodexEntryCard
		back_button.focus_neighbor_top = start_card.get_path()
		_refresh_all_cards()
		_display_entry(start_card.entry_id)


func initialize() -> void:
	for card: CodexEntryCard in _cards_by_id.values():
		_setup_card(card)
	_refresh_all_cards()
	var start_card: CodexEntryCard = first_focus as CodexEntryCard
	_display_entry(start_card.entry_id)


func _refresh_all_cards() -> void:
	for entry_id: StringName in _cards_by_id:
		var card: CodexEntryCard = _cards_by_id[entry_id]
		card.refresh_state(_is_entry_discovered(entry_id), _is_entry_unread(entry_id))


func _display_entry(entry_id: StringName) -> void:
	if _is_entry_discovered(entry_id):
		_show_entry_details(entry_id)
	else:
		details_panel.show_locked(_get_unlock_hint(entry_id))


func _setup_card(_card: CodexEntryCard) -> void:
	pass


func _is_entry_discovered(_entry_id: StringName) -> bool:
	return false


func _is_entry_unread(_entry_id: StringName) -> bool:
	return false


func _mark_entry_viewed(_entry_id: StringName) -> void:
	pass


func _show_entry_details(_entry_id: StringName) -> void:
	pass


func _get_unlock_hint(_entry_id: StringName) -> String:
	return ""


func _on_card_inspected(entry_id: StringName) -> void:
	var card: CodexEntryCard = _cards_by_id[entry_id]
	back_button.focus_neighbor_top = card.get_path()
	if is_visible_in_tree() and _is_entry_discovered(entry_id) and _is_entry_unread(entry_id):
		_mark_entry_viewed(entry_id)
		card.refresh_state(true, false)
	_display_entry(entry_id)
