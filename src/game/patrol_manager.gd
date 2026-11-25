# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name PatrolManager
extends RefCounted


class RoomCandidate:
	extends RefCounted
	var room: Rect2i
	var dist_sq: float
	var is_patrol: bool = false
	var needed: int = 0

	func _init(cand_room: Rect2i, cand_dist_sq: float, cand_is_patrol: bool = false, cand_needed: int = 0) -> void:
		room = cand_room
		dist_sq = cand_dist_sq
		is_patrol = cand_is_patrol
		needed = cand_needed


const PATROL_RESPAWN_COOLDOWN_MIN: float = 45.0
const PATROL_RESPAWN_COOLDOWN_MAX: float = 60.0
const PATROL_QUOTA_MIN_RATIO: float = 0.50
const PATROL_QUOTA_MAX_RATIO: float = 0.75
const PATROL_MIN_COUNT: int = 3
const PATROL_MAX_COUNT: int = 30
const PATROL_OFFSCREEN_MARGIN: Vector2 = Vector2(420.0, 280.0)

var _map: Map = null
var _orig_remaining: Dictionary[Rect2i, int] = {}
var _orig_spawned: Dictionary[Rect2i, int] = {}
var _room_patrol_remaining: Dictionary[Rect2i, int] = {}
var _room_patrol_spawned: Dictionary[Rect2i, int] = {}
var _room_next_patrol_time: Dictionary[Rect2i, float] = {}
var _elapsed_time: float = 0.0
var _last_occupied_room: Rect2i = Rect2i()


func setup(map: Map, orig_remaining: Dictionary[Rect2i, int], orig_spawned: Dictionary[Rect2i, int]) -> void:
	_map = map
	_orig_remaining = orig_remaining
	_orig_spawned = orig_spawned
	_room_patrol_remaining.clear()
	_room_patrol_spawned.clear()
	_room_next_patrol_time.clear()
	_elapsed_time = 0.0
	_last_occupied_room = map.hero_room


func advance_time(delta: float) -> void:
	_elapsed_time += delta


func set_occupied_room(room: Rect2i) -> void:
	_last_occupied_room = room


func schedule_respawn(room: Rect2i) -> void:
	_room_next_patrol_time[room] = _elapsed_time + randf_range(PATROL_RESPAWN_COOLDOWN_MIN, PATROL_RESPAWN_COOLDOWN_MAX)


func update_repopulation(camera_pos: Vector2) -> void:
	if _room_next_patrol_time.is_empty():
		return
	var ready_rooms: Array[Rect2i] = []
	for room: Rect2i in _room_next_patrol_time:
		if _elapsed_time < _room_next_patrol_time[room]:
			continue
		if _room_patrol_remaining.get(room, 0) > 0:
			continue
		if not is_room_at_least_two_hops_away(_map.plan, _last_occupied_room, room):
			continue
		if not is_room_offscreen(_map, room, camera_pos):
			continue
		ready_rooms.append(room)

	for room: Rect2i in ready_rooms:
		_room_next_patrol_time.erase(room)
		var base_quota: int = _map.get_room_enemy_quota(room)
		var ratio: float = randf_range(PATROL_QUOTA_MIN_RATIO, PATROL_QUOTA_MAX_RATIO)
		var patrol_count: int = clampi(roundi(float(base_quota) * ratio), PATROL_MIN_COUNT, PATROL_MAX_COUNT)
		_room_patrol_remaining[room] = patrol_count
		_room_patrol_spawned[room] = 0


func has_active_patrol(room: Rect2i) -> bool:
	return _room_patrol_remaining.get(room, 0) > 0


func get_needed_spawns(room: Rect2i, is_patrol: bool = true) -> int:
	if is_patrol:
		return _room_patrol_remaining.get(room, 0) - _room_patrol_spawned.get(room, 0)
	return _orig_remaining.get(room, 0) - _orig_spawned.get(room, 0)


func record_spawned(room: Rect2i, count: int = 1, is_patrol: bool = true) -> void:
	var target_dict: Dictionary[Rect2i, int] = _room_patrol_spawned if is_patrol else _orig_spawned
	target_dict[room] = target_dict.get(room, 0) + count


func record_despawned(room: Rect2i, is_patrol: bool = true) -> void:
	var target_dict: Dictionary[Rect2i, int] = _room_patrol_spawned if is_patrol else _orig_spawned
	if target_dict.has(room):
		target_dict[room] = maxi(0, target_dict[room] - 1)


func on_patrol_enemy_died(room: Rect2i) -> void:
	if _room_patrol_remaining.has(room):
		_room_patrol_remaining[room] = maxi(0, _room_patrol_remaining[room] - 1)
		if _room_patrol_remaining[room] <= 0:
			schedule_respawn(room)
	record_despawned(room, true)


func collect_rooms(player_pos: Vector2, max_dist_sq: float) -> Array[RoomCandidate]:
	var candidates: Array[RoomCandidate] = []
	for room: Rect2i in _map.companion_rooms:
		var is_patrol: bool = _orig_remaining.get(room, 0) <= 0 and has_active_patrol(room)
		var needed: int = get_needed_spawns(room, is_patrol)
		if needed <= 0 or not _map.is_cell_walkable(room.get_center()):
			continue
		var room_world_center: Vector2 = _map.map_to_local(room.get_center())
		var dist_sq: float = player_pos.distance_squared_to(room_world_center)
		if dist_sq <= max_dist_sq:
			candidates.append(RoomCandidate.new(room, dist_sq, is_patrol, needed))
	candidates.sort_custom(_compare_room_candidate_asc)
	return candidates


static func is_room_at_least_two_hops_away(plan: WorldPlan, origin_room: Rect2i, target_room: Rect2i) -> bool:
	if origin_room == Rect2i() or target_room == Rect2i() or target_room == origin_room:
		return false
	if plan._room_neighbors.has(origin_room) and plan._room_neighbors[origin_room].has(target_room):
		return false
	return true


static func is_room_offscreen(map: Map, room: Rect2i, camera_pos: Vector2) -> bool:
	var top_left: Vector2 = map.map_to_local(room.position) - Vector2(8.0, 8.0)
	var world_rect: Rect2 = Rect2(top_left, Vector2(room.size) * 16.0)
	var guard_rect: Rect2 = (
		world_rect
		. grow_individual(
			PATROL_OFFSCREEN_MARGIN.x,
			PATROL_OFFSCREEN_MARGIN.y,
			PATROL_OFFSCREEN_MARGIN.x,
			PATROL_OFFSCREEN_MARGIN.y,
		)
	)
	return not guard_rect.has_point(camera_pos)


static func pick_enemy_scene(
	archetype: WorldPlan.RoomArchetype,
	slime_scene: PackedScene,
	skeleton_scene: PackedScene,
	archer_scene: PackedScene,
) -> PackedScene:
	var result: PackedScene = skeleton_scene
	match archetype:
		WorldPlan.RoomArchetype.SLIME_PIT:
			result = skeleton_scene if randf() < 0.65 else slime_scene
		WorldPlan.RoomArchetype.ARCHER_GARRISON:
			result = archer_scene if randf() < 0.55 else skeleton_scene
		WorldPlan.RoomArchetype.NECRO_CRYPT:
			result = archer_scene if randf() < 0.30 else skeleton_scene
	return result


static func _compare_room_candidate_asc(a: RoomCandidate, b: RoomCandidate) -> bool:
	return a.dist_sq < b.dist_sq
