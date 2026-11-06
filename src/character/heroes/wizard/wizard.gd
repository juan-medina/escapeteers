# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Wizard
extends Hero


func _find_closest_enemy() -> Enemy:
	var closest_unslowed: Enemy = null
	var min_dist_unslowed_sq: float = INF
	var closest_slowed: Enemy = null
	var min_dist_slowed_sq: float = INF
	var max_detection: float = get_detection_range()
	var max_detection_sq: float = max_detection * max_detection

	for node: Node in get_tree().get_nodes_in_group(_GROUP_ENEMIES):
		var enemy: Enemy = node as Enemy
		if not _is_valid_enemy_target(enemy):
			continue

		var dist_to_self_sq: float = global_position.distance_squared_to(enemy.global_position)
		if dist_to_self_sq > max_detection_sq:
			continue

		if enemy.is_slowed():
			if dist_to_self_sq < min_dist_slowed_sq:
				min_dist_slowed_sq = dist_to_self_sq
				closest_slowed = enemy
		else:
			if dist_to_self_sq < min_dist_unslowed_sq:
				min_dist_unslowed_sq = dist_to_self_sq
				closest_unslowed = enemy

	if closest_unslowed != null:
		return closest_unslowed
	return closest_slowed
