# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name SquadNavigator
extends RefCounted

const REPATH_INTERVAL: float = 0.2
const REPATH_JITTER: float = 0.08
const FAILED_REPATH_INTERVAL: float = 0.5
const FAILED_REPATH_JITTER: float = 0.1
const LOS_CHECK_INTERVAL: float = 0.10
const LOS_CHECK_JITTER: float = 0.05
const SEPARATION_CELL_SIZE: float = 16.0
const SEPARATION_RADIUS: float = 10.0
const SEPARATION_SPEED: float = 40.0
const SEPARATION_MAX_SPEED: float = 55.0
const WAYPOINT_REACHED_DIST_SQ: float = 64.0
const REPATH_DISTANCE_MOVED_SQ: float = 144.0

static var _los_query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.new()
static var _separation_grid: Dictionary[Vector2i, Array] = {}
static var _separation_grid_used: Array[Vector2i] = []

var _current_path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _target_pos: Vector2 = Vector2.ZERO
var _repath_timer: float = 0.0
var _los_timer: float = 0.0
var _has_direct_los: bool = false
var _los_dest: Vector2 = Vector2.ZERO


static func has_line_of_sight(character: Character, target_pos: Vector2) -> bool:
	var space_state: PhysicsDirectSpaceState2D = character.get_world_2d().direct_space_state
	_los_query.from = character.global_position
	_los_query.to = target_pos
	_los_query.collision_mask = 1
	var hit: Dictionary = space_state.intersect_ray(_los_query)
	return hit.is_empty()


func reset() -> void:
	_current_path.clear()
	_path_index = 0
	_target_pos = Vector2.ZERO
	_repath_timer = 0.0
	_los_timer = 0.0
	_has_direct_los = false
	_los_dest = Vector2.ZERO


func get_next_waypoint(character: Character, destination: Vector2, map: Map, delta: float) -> Vector2:
	_repath_timer -= delta
	_los_timer -= delta

	var check_los: bool = _los_timer <= 0.0 or destination.distance_squared_to(_los_dest) > REPATH_DISTANCE_MOVED_SQ * 2.0
	if check_los:
		_los_timer = LOS_CHECK_INTERVAL + randf_range(0.0, LOS_CHECK_JITTER)
		_los_dest = destination
		_has_direct_los = has_line_of_sight(character, destination)

	if _has_direct_los:
		_current_path.clear()
		_path_index = 0
		return destination

	var needs_repath: bool = false
	if _repath_timer <= 0.0:
		if _current_path.is_empty() or _path_index >= _current_path.size():
			needs_repath = true
		elif destination.distance_squared_to(_target_pos) > REPATH_DISTANCE_MOVED_SQ:
			needs_repath = true

	if needs_repath:
		_repath_timer = REPATH_INTERVAL + randf_range(0.0, REPATH_JITTER)
		_target_pos = destination
		if not map.is_in_nav_bounds(character.global_position) or not map.is_in_nav_bounds(destination):
			_current_path.clear()
			_path_index = 0
			_repath_timer = FAILED_REPATH_INTERVAL + randf_range(0.0, FAILED_REPATH_JITTER)
			return destination

		_current_path = map.get_navigation_path(character.global_position, destination)
		_path_index = 0
		if _current_path.is_empty():
			_repath_timer = FAILED_REPATH_INTERVAL + randf_range(0.0, FAILED_REPATH_JITTER)

	if _current_path.is_empty():
		return destination

	var advanced: bool = true
	while advanced and _path_index < _current_path.size() - 1:
		advanced = false
		var dist_sq: float = character.global_position.distance_squared_to(_current_path[_path_index])
		if dist_sq <= WAYPOINT_REACHED_DIST_SQ:
			_path_index += 1
			advanced = true
		elif check_los and has_line_of_sight(character, _current_path[_path_index + 1]):
			_path_index += 1
			advanced = true

	return _current_path[_path_index]


static func update_enemy_separation(enemies: Array[Enemy]) -> void:
	for cell: Vector2i in _separation_grid_used:
		var bucket: Array = _separation_grid[cell]
		bucket.clear()
	_separation_grid_used.clear()

	var count: int = enemies.size()
	if count <= 1:
		if count == 1:
			enemies[0].separation_velocity = Vector2.ZERO
		return

	for enemy: Enemy in enemies:
		var pos: Vector2 = enemy.global_position
		var cell: Vector2i = Vector2i(floori(pos.x / SEPARATION_CELL_SIZE), floori(pos.y / SEPARATION_CELL_SIZE))
		if not _separation_grid.has(cell):
			_separation_grid[cell] = []
		var bucket: Array = _separation_grid[cell]
		if bucket.is_empty():
			_separation_grid_used.append(cell)
		bucket.append(enemy)

	var radius_sq: float = SEPARATION_RADIUS * SEPARATION_RADIUS
	for enemy: Enemy in enemies:
		_apply_enemy_separation(enemy, radius_sq)


static func _apply_enemy_separation(enemy: Enemy, radius_sq: float) -> void:
	var pos: Vector2 = enemy.global_position
	var base_cell: Vector2i = Vector2i(floori(pos.x / SEPARATION_CELL_SIZE), floori(pos.y / SEPARATION_CELL_SIZE))
	var push: Vector2 = Vector2.ZERO

	for ox: int in range(-1, 2):
		for oy: int in range(-1, 2):
			var check_cell: Vector2i = Vector2i(base_cell.x + ox, base_cell.y + oy)
			if not _separation_grid.has(check_cell):
				continue
			var bucket: Array = _separation_grid[check_cell]
			for idx: int in range(bucket.size()):
				var other: Enemy = bucket[idx]
				if other == enemy:
					continue
				var diff: Vector2 = pos - other.global_position
				var d_sq: float = diff.length_squared()
				if d_sq >= radius_sq:
					continue
				if d_sq < 0.0001:
					var nudge_idx: int = int(enemy.get_instance_id() % 7) - 3
					var angle: float = float(nudge_idx) * 0.9
					push += Vector2(cos(angle), sin(angle)) * (SEPARATION_SPEED * 0.5)
				else:
					var dist: float = sqrt(d_sq)
					var strength: float = (SEPARATION_RADIUS - dist) / SEPARATION_RADIUS
					push += (diff / dist) * (SEPARATION_SPEED * strength)

	var push_len_sq: float = push.length_squared()
	if push_len_sq > SEPARATION_MAX_SPEED * SEPARATION_MAX_SPEED:
		push = (push / sqrt(push_len_sq)) * SEPARATION_MAX_SPEED
	enemy.separation_velocity = push
