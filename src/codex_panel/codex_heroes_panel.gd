# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name CodexHeroesPanel
extends CodexUnitsPanel


func _setup_card(card: CodexEntryCard) -> void:
	card.setup_hero()


func _is_entry_discovered(entry_id: StringName) -> bool:
	return Codex.is_discovered(Codex.Category.HEROES, entry_id)


func _is_entry_unread(entry_id: StringName) -> bool:
	return Codex.is_unread(Codex.Category.HEROES, entry_id)


func _mark_entry_viewed(entry_id: StringName) -> void:
	Codex.mark_viewed(Codex.Category.HEROES, entry_id)


func _show_entry_details(entry_id: StringName) -> void:
	details_panel.show_hero(HeroData.get_hero(entry_id))


func _get_unlock_hint(entry_id: StringName) -> String:
	return HeroData.get_hero(entry_id).unlock_hint
