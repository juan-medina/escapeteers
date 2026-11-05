# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name SquadGrid
extends GridContainer

var _cell_pool: Array[SquadGridCell] = []


func update_squad(squad: Array[Hero]) -> void:
	var active_count: int = 0
	for hero: Hero in squad:
		if hero.is_dead:
			continue

		var cell: SquadGridCell
		if active_count < _cell_pool.size():
			cell = _cell_pool[active_count]
		else:
			cell = SquadGridCell.new()
			_cell_pool.append(cell)
			add_child(cell)

		cell.bind_hero(hero)
		active_count += 1

	for i: int in range(active_count, _cell_pool.size()):
		_cell_pool[i].unbind()
