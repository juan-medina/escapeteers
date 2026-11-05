# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name SquadNavigator
extends RefCounted

const REPATH_INTERVAL: float = 0.2
const WAYPOINT_REACHED_DIST_SQ: float = 64.0
const REPATH_DISTANCE_MOVED_SQ: float = 144.0

var _current_path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _target_pos: Vector2 = Vector2.ZERO
var _repath_timer: float = 0.0


static func has_line_of_sight(character: Character, target_pos: Vector2) -> bool:
	var world_2d: World2D = character.get_world_2d()
	if world_2d == null:
		return true

	var space_state: PhysicsDirectSpaceState2D = world_2d.direct_space_state
	if space_state == null:
		return true

	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(character.global_position, target_pos, 1)
	var hit: Dictionary = space_state.intersect_ray(query)
	return hit.is_empty()


func reset() -> void:
	_current_path.clear()
	_path_index = 0
	_target_pos = Vector2.ZERO
	_repath_timer = 0.0


func get_next_waypoint(character: Character, destination: Vector2, map: Map, delta: float) -> Vector2:
	_repath_timer -= delta

	if has_line_of_sight(character, destination):
		_current_path.clear()
		_path_index = 0
		return destination

	var needs_repath: bool = false
	if _repath_timer <= 0.0:
		if _current_path.is_empty() or _path_index >= _current_path.size():
			needs_repath = true
		elif destination.distance_squared_to(_target_pos) > REPATH_DISTANCE_MOVED_SQ:
			needs_repath = true

	if needs_repath and map != null:
		_repath_timer = REPATH_INTERVAL + randf_range(0.0, 0.08)
		_target_pos = destination
		if not map.is_in_nav_bounds(character.global_position) or not map.is_in_nav_bounds(destination):
			_current_path.clear()
			_path_index = 0
			_repath_timer = 0.5 + randf_range(0.0, 0.1)
			return destination

		_current_path = map.get_navigation_path(character.global_position, destination)
		_path_index = 0
		if _current_path.is_empty():
			_repath_timer = 0.5 + randf_range(0.0, 0.1)

	if _current_path.is_empty():
		return destination

	var advanced: bool = true
	while advanced and _path_index < _current_path.size() - 1:
		advanced = false
		var dist_sq: float = character.global_position.distance_squared_to(_current_path[_path_index])
		if dist_sq <= WAYPOINT_REACHED_DIST_SQ:
			_path_index += 1
			advanced = true
		elif has_line_of_sight(character, _current_path[_path_index + 1]):
			_path_index += 1
			advanced = true

	return _current_path[_path_index]
