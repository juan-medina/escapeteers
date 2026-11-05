# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name SquadGrid
extends GridContainer

const DEFAULT_COLUMNS: int = 4
const H_SEPARATION: int = 1
const V_SEPARATION: int = 1

var _cell_pool: Array[SquadGridCell] = []


func _init() -> void:
	columns = DEFAULT_COLUMNS
	mouse_filter = MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"h_separation", H_SEPARATION)
	add_theme_constant_override(&"v_separation", V_SEPARATION)


func _exit_tree() -> void:
	for cell: SquadGridCell in _cell_pool:
		if is_instance_valid(cell):
			cell.unbind()
	_cell_pool.clear()


func update_squad(squad: Array[Hero]) -> void:
	var alive_heroes: Array[Hero] = []
	for hero: Hero in squad:
		if hero != null and is_instance_valid(hero) and not hero.is_dead:
			alive_heroes.append(hero)

	for i: int in range(alive_heroes.size()):
		var cell: SquadGridCell
		if i < _cell_pool.size():
			cell = _cell_pool[i]
		else:
			cell = SquadGridCell.new()
			_cell_pool.append(cell)
			add_child(cell)

		cell.bind_hero(alive_heroes[i])

	for i: int in range(alive_heroes.size(), _cell_pool.size()):
		_cell_pool[i].unbind()
