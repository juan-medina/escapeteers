# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name AutoplaySpecialRooms
extends RefCounted


static func is_active_special_room(map: Map, room: Rect2i) -> bool:
	if room == Rect2i():
		return false
	var event_type: WorldPlan.RoomEventType = map.plan.room_event_types.get(room, WorldPlan.RoomEventType.NONE)
	match event_type:
		WorldPlan.RoomEventType.CLOSING_SPIKES:
			var hazard: ClosingSpikeHazard = map.plan.closing_spike_hazards.get(room, null)
			return hazard != null and not hazard.is_cleared
		WorldPlan.RoomEventType.WAVE_AMBUSH:
			var ambush: WaveAmbush = map.plan.wave_ambushes.get(room, null)
			return ambush != null and not ambush.is_cleared
		WorldPlan.RoomEventType.CURSED_OBELISKS:
			var enc: ObeliskEncounter = map.plan.obelisk_encounters.get(room, null)
			return enc != null and not enc.is_cleared
		WorldPlan.RoomEventType.RUNE_PLATES:
			var rune_enc: RunePlateEncounter = map.plan.rune_encounters.get(room, null)
			return rune_enc != null and not rune_enc.is_cleared
		_:
			return false


static func is_in_active_special_room(map: Map, leader: Hero) -> bool:
	var room: Rect2i = map.plan.get_room_at(map.local_to_map(leader.global_position))
	return is_active_special_room(map, room)


static func is_in_closing_spikes_room(map: Map, leader: Hero) -> bool:
	var room: Rect2i = map.plan.get_room_at(map.local_to_map(leader.global_position))
	if room == Rect2i():
		return false
	if map.plan.room_event_types.get(room, WorldPlan.RoomEventType.NONE) != WorldPlan.RoomEventType.CLOSING_SPIKES:
		return false
	var hazard: ClosingSpikeHazard = map.plan.closing_spike_hazards.get(room, null)
	return hazard != null and hazard.is_triggered and not hazard.is_cleared


static func find_ready_chest_in_room(game: Game, room: Rect2i) -> Vector2:
	if room == Rect2i():
		return Vector2.ZERO
	var chest: CursedChest = game._event_director.get_unclaimed_chest_in_room(room)
	return chest.position if chest != null else Vector2.ZERO


static func decide_move(bot: AutoplayBot, game: Game, map: Map, leader: Hero, delta: float) -> Vector2:
	var room: Rect2i = map.plan.get_room_at(map.local_to_map(leader.global_position))
	var event_type: WorldPlan.RoomEventType = map.plan.room_event_types.get(room, WorldPlan.RoomEventType.NONE)
	match event_type:
		WorldPlan.RoomEventType.CLOSING_SPIKES:
			return _decide_closing_spikes_move(bot, game, map, leader, room, delta)
		WorldPlan.RoomEventType.WAVE_AMBUSH:
			return _decide_wave_ambush_move(bot, game, map, leader, room, delta)
		WorldPlan.RoomEventType.CURSED_OBELISKS:
			return _decide_obelisk_move(bot, game, map, leader, room, delta)
		WorldPlan.RoomEventType.RUNE_PLATES:
			return _decide_rune_plates_move(bot, game, map, leader, room, delta)
		_:
			return Vector2.ZERO


static func _decide_rune_plates_move(bot: AutoplayBot, game: Game, map: Map, leader: Hero, room: Rect2i, delta: float) -> Vector2:
	var enc: RunePlateEncounter = map.plan.rune_encounters.get(room, null)
	if enc == null or enc.is_cleared:
		return Vector2.ZERO
	if not enc.is_triggered:
		var bait_pos: Vector2 = map.clamp_to_walkable(map.map_to_local(enc.bait_cell))
		return bot._steer_toward(map, leader, bait_pos, delta)

	var plates: Array[RunePlate] = game._event_director.get_active_rune_plates_in_room(room)
	if plates.is_empty():
		return Vector2.ZERO

	var target_plate: RunePlate = null
	for plate: RunePlate in plates:
		if plate.progress > 0.0:
			target_plate = plate
			break
	if target_plate == null:
		target_plate = plates[0]
		var min_dist_sq: float = leader.global_position.distance_squared_to(target_plate.global_position)
		for i: int in range(1, plates.size()):
			var d_sq: float = leader.global_position.distance_squared_to(plates[i].global_position)
			if d_sq < min_dist_sq:
				min_dist_sq = d_sq
				target_plate = plates[i]

	var safe_pickup: Vector2 = _find_safe_pickup(bot, game, map, leader, room)
	if safe_pickup != Vector2.ZERO:
		if target_plate.progress <= 0.0 or target_plate.is_point_inside(safe_pickup):
			return bot._steer_toward(map, leader, safe_pickup, delta)

	if leader.global_position.distance_squared_to(target_plate.global_position) > 16.0 * 16.0:
		return bot._steer_toward(map, leader, target_plate.global_position, delta)
	return Vector2.ZERO


static func _decide_obelisk_move(bot: AutoplayBot, game: Game, map: Map, leader: Hero, room: Rect2i, delta: float) -> Vector2:
	var enc: ObeliskEncounter = map.plan.obelisk_encounters.get(room, null)
	if enc == null or enc.is_cleared:
		return Vector2.ZERO
	if not enc.is_triggered:
		var bait_pos: Vector2 = map.clamp_to_walkable(map.map_to_local(enc.bait_cell))
		return bot._steer_toward(map, leader, bait_pos, delta)

	var safe_pickup: Vector2 = _find_safe_pickup(bot, game, map, leader, room)
	if safe_pickup != Vector2.ZERO:
		return bot._steer_toward(map, leader, safe_pickup, delta)

	var obelisks: Array[CursedObelisk] = game._event_director.get_active_obelisks_in_room(room)
	if not obelisks.is_empty():
		var nearest: CursedObelisk = obelisks[0]
		var min_dist_sq: float = leader.global_position.distance_squared_to(nearest.global_position)
		for i: int in range(1, obelisks.size()):
			var d_sq: float = leader.global_position.distance_squared_to(obelisks[i].global_position)
			if d_sq < min_dist_sq:
				min_dist_sq = d_sq
				nearest = obelisks[i]
		return bot._compute_combat_move(game, map, leader, nearest, delta)

	var combat_target: Enemy = bot._find_priority_enemy(game, map, leader)
	if combat_target != null:
		return bot._compute_combat_move(game, map, leader, combat_target, delta)

	var center_pos: Vector2 = map.clamp_to_walkable(map.map_to_local(room.get_center()))
	if leader.global_position.distance_squared_to(center_pos) > 24.0 * 24.0:
		return bot._steer_toward(map, leader, center_pos, delta)
	return Vector2.ZERO


static func _decide_wave_ambush_move(bot: AutoplayBot, game: Game, map: Map, leader: Hero, room: Rect2i, delta: float) -> Vector2:
	var ambush: WaveAmbush = map.plan.wave_ambushes.get(room, null)
	if ambush == null or ambush.is_cleared:
		return Vector2.ZERO
	if ambush.state == WaveAmbush.State.WAITING:
		var bait_pos: Vector2 = map.clamp_to_walkable(map.map_to_local(ambush.bait_cell))
		return bot._steer_toward(map, leader, bait_pos, delta)

	var safe_pickup: Vector2 = _find_safe_pickup(bot, game, map, leader, room)
	if safe_pickup != Vector2.ZERO:
		return bot._steer_toward(map, leader, safe_pickup, delta)

	var combat_target: Enemy = bot._find_priority_enemy(game, map, leader)
	if combat_target != null:
		return bot._compute_combat_move(game, map, leader, combat_target, delta)

	var center_pos: Vector2 = map.clamp_to_walkable(map.map_to_local(room.get_center()))
	if leader.global_position.distance_squared_to(center_pos) > 24.0 * 24.0:
		return bot._steer_toward(map, leader, center_pos, delta)
	return Vector2.ZERO


static func _compute_current_safe_rect(hazard: ClosingSpikeHazard) -> Rect2i:
	var closed_rings: int = 0
	for i: int in range(hazard.rings.size()):
		if hazard.rings[i].frame > 0:
			closed_rings = i + 1
	if closed_rings >= hazard.rings.size():
		return hazard.safe_rect
	var inner_bounds: Rect2i = Rect2i(
		hazard.room.position.x,
		hazard.room.position.y + 1,
		hazard.room.size.x,
		hazard.room.size.y - 1,
	)
	var inset: int = closed_rings * ClosingSpikeHazard.RING_THICKNESS
	var dynamic_safe: Rect2i = Rect2i(
		inner_bounds.position + Vector2i(inset, inset),
		inner_bounds.size - Vector2i(inset * 2, inset * 2),
	)
	if dynamic_safe.size.x <= 0 or dynamic_safe.size.y <= 0:
		return hazard.safe_rect
	return dynamic_safe


static func _decide_closing_spikes_move(bot: AutoplayBot, game: Game, map: Map, leader: Hero, room: Rect2i, delta: float) -> Vector2:
	var hazard: ClosingSpikeHazard = map.plan.closing_spike_hazards.get(room, null)
	if hazard == null or hazard.is_cleared:
		return Vector2.ZERO
	if not hazard.is_triggered:
		var bait_pos: Vector2 = map.clamp_to_walkable(map.map_to_local(hazard.bait_cell))
		return bot._steer_toward(map, leader, bait_pos, delta)

	var active_safe: Rect2i = _compute_current_safe_rect(hazard)
	var inner_safe: Rect2i = active_safe.grow(-1) if (active_safe.size.x >= 3 and active_safe.size.y >= 3) else active_safe
	var safe_center: Vector2 = map.clamp_to_walkable(map.map_to_local(hazard.safe_rect.get_center()))
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
