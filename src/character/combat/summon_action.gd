# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name SummonAction
extends CombatAction

var summon_count: int = 2


func _init() -> void:
	check_line_of_sight = true


func execute(user: Character, target: Character) -> void:
	super.execute(user, target)
	user.play(Character.ANIM_SUMMON)
