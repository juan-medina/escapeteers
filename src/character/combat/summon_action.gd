# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name SummonAction
extends CombatAction

var summon_count: int = 2
var check_line_of_sight: bool = true


func can_reach(user: Character, target: Character) -> bool:
	if not super.can_reach(user, target):
		return false

	if check_line_of_sight:
		if not SquadNavigator.has_line_of_sight(user, target.global_position):
			return false

	return true


func execute(user: Character, target: Character) -> void:
	super.execute(user, target)
	user.play(Character.ANIM_SUMMON)

	var dir_x: float = -1.0 if target.global_position.x < user.global_position.x else 1.0
	user.flip_h = dir_x < 0.0

