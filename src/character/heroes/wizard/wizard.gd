# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Wizard
extends Hero


func _is_preferred_target(enemy: Enemy) -> bool:
	return not enemy.is_slowed()
