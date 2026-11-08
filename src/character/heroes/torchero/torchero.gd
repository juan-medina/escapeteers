# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Torchero
extends Hero

const TORCH_FLICKER_SPEED: float = 8.0
const TORCH_FLICKER_AMP: float = 0.06

var _flicker_time: float = 0.0
var _base_light_energy: float = 1.1

@onready var _torch_light: PointLight2D = $PointLight2D


func _ready() -> void:
	super._ready()
	_base_light_energy = _torch_light.energy
	_flicker_time = randf() * TAU


func _process(delta: float) -> void:
	super._process(delta)
	if not is_dead and _torch_light.enabled:
		_flicker_time += delta
		_torch_light.energy = _base_light_energy + sin(_flicker_time * TORCH_FLICKER_SPEED) * TORCH_FLICKER_AMP


func _on_death() -> void:
	super._on_death()
	_torch_light.enabled = false


func _find_closest_enemy() -> Enemy:
	var closest_unburned: Enemy = null
	var min_dist_unburned_sq: float = INF
	var closest_burned: Enemy = null
	var min_dist_burned_sq: float = INF
	var max_detection: float = get_detection_range()
	var max_detection_sq: float = max_detection * max_detection
	var leash: float = get_current_leash()
	var leash_sq: float = leash * leash
	var anchor_pos: Vector2 = get_anchor_position()
	var enforce_leash: bool = not is_player and not can_ranged and leash > 0.0

	for node: Node in get_tree().get_nodes_in_group(_GROUP_ENEMIES):
		var enemy: Enemy = node as Enemy
		if not _is_valid_enemy_target(enemy):
			continue

		var dist_to_self_sq: float = global_position.distance_squared_to(enemy.global_position)
		if enforce_leash:
			if anchor_pos.distance_squared_to(enemy.global_position) > leash_sq:
				continue
		elif dist_to_self_sq > max_detection_sq:
			continue

		if enemy.is_burning():
			if dist_to_self_sq < min_dist_burned_sq:
				min_dist_burned_sq = dist_to_self_sq
				closest_burned = enemy
		else:
			if dist_to_self_sq < min_dist_unburned_sq:
				min_dist_unburned_sq = dist_to_self_sq
				closest_unburned = enemy

	if closest_unburned != null:
		return closest_unburned
	return closest_burned
