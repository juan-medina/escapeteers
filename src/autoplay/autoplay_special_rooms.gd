# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name AutoplaySpecialRooms
extends RefCounted


static func is_in_active_special_room(map: Map, leader: Hero, skipped_rooms: Dictionary[Rect2i, bool]) -> bool:
	var room: Rect2i = map.plan.get_room_at(map.local_to_map(leader.global_position))
	if room == Rect2i() or skipped_rooms.has(room):
		return false
	var event_type: WorldPlan.RoomEventType = map.plan.room_event_types.get(room, WorldPlan.RoomEventType.NONE)
	match event_type:
		WorldPlan.RoomEventType.CLOSING_SPIKES:
			var hazard: ClosingSpikeHazard = map.plan.closing_spike_hazards.get(room, null)
			return hazard != null and not hazard.is_cleared
		_:
			return false


static func decide_move(bot: AutoplayBot, game: Game, map: Map, leader: Hero, delta: float) -> Vector2:
	var room: Rect2i = map.plan.get_room_at(map.local_to_map(leader.global_position))
	var event_type: WorldPlan.RoomEventType = map.plan.room_event_types.get(room, WorldPlan.RoomEventType.NONE)
	match event_type:
		WorldPlan.RoomEventType.CLOSING_SPIKES:
			return _decide_closing_spikes_move(bot, game, map, leader, room, delta)
		_:
			return Vector2.ZERO


static func _decide_closing_spikes_move(bot: AutoplayBot, game: Game, map: Map, leader: Hero, room: Rect2i, delta: float) -> Vector2:
	var hazard: ClosingSpikeHazard = map.plan.closing_spike_hazards.get(room, null)
	if hazard == null or hazard.is_cleared:
		return Vector2.ZERO

	var safe_rect: Rect2i = hazard.safe_rect
	var inner_safe: Rect2i = safe_rect.grow(-1) if (safe_rect.size.x > 4 and safe_rect.size.y > 4) else safe_rect
	var safe_center: Vector2 = map.clamp_to_walkable(map.map_to_local(safe_rect.get_center()))
	var leader_cell: Vector2i = map.local_to_map(leader.global_position)

	if not inner_safe.has_point(leader_cell):
		return bot._steer_toward(map, leader, safe_center, delta)

	var safe_pickup: Vector2 = _find_safe_pickup(bot, game, map, leader, inner_safe)
	if safe_pickup != Vector2.ZERO:
		return bot._steer_toward(map, leader, safe_pickup, delta)

	var combat_target: Enemy = bot._find_priority_enemy(game, map, leader)
	if combat_target != null:
		return _decide_safe_combat_move(bot, game, map, leader, combat_target, inner_safe, delta)

	if leader.global_position.distance_squared_to(safe_center) > 24.0 * 24.0:
		return bot._steer_toward(map, leader, safe_center, delta)
	return Vector2.ZERO


static func _find_safe_pickup(bot: AutoplayBot, game: Game, map: Map, leader: Hero, inner_safe: Rect2i) -> Vector2:
	var nearby_recruit: Unknown = bot._find_nearest_recruit(game, map, leader)
	if nearby_recruit != null and inner_safe.has_point(map.local_to_map(nearby_recruit.global_position)):
		return nearby_recruit.global_position
	var nearby_key: KeyPickup = bot._find_nearest_key(game, map, leader)
	if nearby_key != null and inner_safe.has_point(map.local_to_map(nearby_key.global_position)):
		return nearby_key.global_position
	var nearby_potion: Vector2 = bot._find_nearest_potion(game, map, leader, true)
	if nearby_potion != Vector2.ZERO and inner_safe.has_point(map.local_to_map(nearby_potion)):
		return nearby_potion
	return Vector2.ZERO


static func _decide_safe_combat_move(
	bot: AutoplayBot,
	game: Game,
	map: Map,
	leader: Hero,
	target: Enemy,
	inner_safe: Rect2i,
	delta: float,
) -> Vector2:
	var combat_dir: Vector2 = bot._compute_combat_move(game, map, leader, target, delta)
	if combat_dir != Vector2.ZERO:
		var probe_cell: Vector2i = map.local_to_map(leader.global_position + combat_dir * 24.0)
		if inner_safe.has_point(probe_cell):
			return combat_dir
	var target_cell: Vector2i = map.local_to_map(target.global_position)
	var clamped_x: int = clampi(target_cell.x, inner_safe.position.x, inner_safe.end.x - 1)
	var clamped_y: int = clampi(target_cell.y, inner_safe.position.y, inner_safe.end.y - 1)
	var clamped_pos: Vector2 = map.clamp_to_walkable(map.map_to_local(Vector2i(clamped_x, clamped_y)))
	if leader.global_position.distance_squared_to(clamped_pos) > AutoplayBot.WAYPOINT_REACHED_DIST_SQ:
		return bot._steer_toward(map, leader, clamped_pos, delta)
	return Vector2.ZERO


static func is_dangerous_spike_cell(map: Map, check_cell: Vector2i) -> bool:
	if map.is_spike_active_at(check_cell):
		return true
	if map.plan.event_spike_cell_rooms.has(check_cell):
		var event_room: Rect2i = map.plan.event_spike_cell_rooms[check_cell]
		var hazard: ClosingSpikeHazard = map.plan.closing_spike_hazards.get(event_room, null)
		return hazard != null and hazard.get_cell_frame(check_cell) >= 1
	return false
