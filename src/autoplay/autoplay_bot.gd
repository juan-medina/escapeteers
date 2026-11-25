# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name AutoplayBot
extends RefCounted

const ACTION_DEADZONE: float = 0.3
const RECRUIT_SEARCH_RADIUS_SQ: float = 280.0 * 280.0
const COMBAT_SEARCH_RADIUS_SQ: float = 340.0 * 340.0
const NECRO_PRIORITY_RADIUS_SQ: float = 260.0 * 260.0
const WAYPOINT_REACHED_DIST_SQ: float = 12.0 * 12.0
const ROOM_ARRIVE_DIST_SQ: float = 40.0 * 40.0
const STUCK_DIST_SQ: float = 10.0 * 10.0
const STUCK_SIDESTEP_TIME: float = 1.2
const STUCK_UNSTICK_TIME: float = 2.2
const ROOM_STALL_TIMEOUT: float = 45.0
const SPIKE_AVOID_RADIUS_CELLS: int = 1
const EARLY_RECRUIT_TARGET_SQUAD: int = 6
const MAP_OPEN_DURATION: float = 4.0
const MAP_CLOSED_DURATION: float = 6.0

const MELEE_IDS: Array[StringName] = [&"knight", &"armored_axeman", &"swordsman", &"knight_templar", &"torchero"]
const RANGED_IDS: Array[StringName] = [&"archer", &"wizard", &"soldier", &"priest"]

var build_policy: String = "balanced"
var target_max_depth: int = 12
var rush_deep: bool = false
var max_depth_reached: int = 0
var rooms_cleared_count: int = 0
var has_won: bool = false

var _room_graph: Dictionary[Rect2i, Array] = {}
var _highest_depth: int = 1
var _last_known_room: Rect2i = Rect2i()
var _goal_room: Rect2i = Rect2i()
var _room_path: Array[Rect2i] = []
var _room_stall_timer: float = 0.0
var _stall_room: Rect2i = Rect2i()
var _min_room_remaining: int = 999999
var _skipped_rooms: Dictionary[Rect2i, bool] = {}
var _visited_rooms: Dictionary[Rect2i, bool] = {}
var _cleared_at_max_depth: bool = false
var _anchor_pos: Vector2 = Vector2.ZERO
var _stuck_timer: float = 0.0
var _sidestep_timer: float = 0.0
var _sidestep_sign: float = 1.0
var _cached_path: PackedVector2Array = PackedVector2Array()
var _cached_path_dest: Vector2 = Vector2.ZERO
var _repath_timer: float = 0.0
var _strafe_sign: float = 1.0
var _strafe_timer: float = 0.0
var _map_toggle_timer: float = MAP_CLOSED_DURATION
var _shortcut_waypoints: Array[Vector2] = []


func setup(map: Map, policy: String, max_depth: int, rush_deep_mode: bool = false) -> void:
	build_policy = policy
	target_max_depth = max_depth
	rush_deep = rush_deep_mode
	max_depth_reached = 0
	rooms_cleared_count = 0
	has_won = false
	_last_known_room = map.hero_room
	_goal_room = Rect2i()
	_room_path.clear()
	_shortcut_waypoints.clear()
	_room_stall_timer = 0.0
	_stall_room = Rect2i()
	_min_room_remaining = 999999
	_skipped_rooms.clear()
	_visited_rooms.clear()
	_cleared_at_max_depth = false
	_anchor_pos = Vector2.ZERO
	_stuck_timer = 0.0
	_sidestep_timer = 0.0
	_cached_path = PackedVector2Array()
	_cached_path_dest = Vector2.ZERO
	_repath_timer = 0.0
	_map_toggle_timer = MAP_CLOSED_DURATION
	_build_room_graph(map)
	release_movement()


func release_movement() -> void:
	Input.action_release(&"left")
	Input.action_release(&"right")
	Input.action_release(&"up")
	Input.action_release(&"down")


func update_map_toggle(game: Game, delta: float) -> bool:
	_map_toggle_timer -= delta
	if _map_toggle_timer <= 0.0:
		game._hud._map_overlay.toggle()
		_map_toggle_timer = MAP_CLOSED_DURATION
		return true
	return false


func update(game: Game, map: Map, delta: float) -> void:
	if game.get_tree().paused:
		release_movement()
		_handle_paused_panels(game)
		return

	var leader: Hero = game._character
	if leader == null or not is_instance_valid(leader) or leader.is_dead:
		release_movement()
		return

	_update_room_progress(game, map, leader, delta)
	var move_dir: Vector2 = _decide_move_direction(game, map, leader, delta)
	move_dir = _apply_spike_avoidance(map, leader.global_position, move_dir)
	_update_stuck_recovery(map, leader, move_dir, delta)
	if _sidestep_timer > 0.0:
		var perp: Vector2 = Vector2(-move_dir.y, move_dir.x) * _sidestep_sign
		move_dir = (move_dir * 0.35 + perp).normalized() if move_dir.length_squared() > 0.01 else perp
	_apply_movement(move_dir)


func _build_room_graph(map: Map) -> void:
	_room_graph.clear()
	_highest_depth = 1
	var plan: WorldPlan = map.plan
	_room_graph[plan.hero_room] = []

	for room: Rect2i in plan.rooms:
		_room_graph[room] = []
		var depth: int = map.get_room_depth(room)
		if depth > _highest_depth:
			_highest_depth = depth

	for d1_room: Rect2i in plan.get_depth_rooms(1):
		_connect_rooms(plan.hero_room, d1_room)

	for parent_room: Rect2i in plan.room_children:
		var children: Array = plan.room_children[parent_room]
		for child_var: Variant in children:
			if child_var is Rect2i:
				var child_room: Rect2i = child_var
				_connect_rooms(parent_room, child_room)

	for room_a: Rect2i in plan._room_neighbors:
		var neighbors: Array = plan._room_neighbors[room_a]
		for n_var: Variant in neighbors:
			if n_var is Rect2i:
				var n_room: Rect2i = n_var
				_connect_rooms(room_a, n_room)


func _connect_rooms(room_a: Rect2i, room_b: Rect2i) -> void:
	if not _room_graph.has(room_a):
		_room_graph[room_a] = []
	if not _room_graph[room_a].has(room_b):
		_room_graph[room_a].append(room_b)
	if not _room_graph.has(room_b):
		_room_graph[room_b] = []
	if not _room_graph[room_b].has(room_a):
		_room_graph[room_b].append(room_a)


func _handle_paused_panels(game: Game) -> void:
	var guard: int = 0
	while game.get_tree().paused and guard < 8:
		guard += 1
		if game._recruit_panel.visible:
			if game._reroll_coins > 0 and not game._recruit_panel._reroll_button.disabled:
				if _should_reroll_recruit(game._recruit_panel._cards_by_id, game):
					game._on_recruit_reroll_requested()
					continue
			var chosen_id: StringName = _pick_visible_card(game._recruit_panel._cards_by_id, game, false)
			if chosen_id == &"":
				break
			game._recruit_panel._on_card_chosen(HeroData.get_hero(chosen_id))
		elif game._level_up_panel.visible:
			var chosen_id: StringName = _pick_visible_card(game._level_up_panel._cards_by_id, game, true)
			if chosen_id == &"":
				break
			game._level_up_panel._on_card_chosen(HeroData.get_hero(chosen_id))
		elif game._hud._map_overlay.visible:
			game._hud._map_overlay.set_map_visible(false)
		else:
			break


func _should_reroll_recruit(cards_by_id: Dictionary[StringName, UnitCard], game: Game) -> bool:
	if build_policy.begins_with("mono:"):
		var mono_id: StringName = StringName(build_policy.substr(5))
		return not cards_by_id.has(mono_id) or not cards_by_id[mono_id].visible
	if build_policy == "balanced" and game._squad.size() >= 3:
		var counts: Dictionary[StringName, int] = game._get_squad_unit_counts()
		if not counts.has(&"priest") or counts[&"priest"] == 0:
			return not cards_by_id.has(&"priest") or not cards_by_id[&"priest"].visible
	return false


func _pick_visible_card(cards_by_id: Dictionary[StringName, UnitCard], game: Game, is_level_up: bool) -> StringName:
	var visible_ids: Array[StringName] = []
	for hero_id: StringName in cards_by_id:
		var card: UnitCard = cards_by_id[hero_id]
		if card.visible:
			visible_ids.append(hero_id)

	if visible_ids.is_empty():
		return &""
	if visible_ids.size() == 1:
		return visible_ids[0]

	var counts: Dictionary[StringName, int] = game._get_squad_unit_counts()
	var levels: Dictionary[StringName, int] = game._class_levels

	if build_policy == "random":
		return visible_ids[randi_range(0, visible_ids.size() - 1)]

	if build_policy.begins_with("mono:"):
		var mono_id: StringName = StringName(build_policy.substr(5))
		if visible_ids.has(mono_id):
			return mono_id

	if is_level_up:
		return _score_level_up_choice(visible_ids, counts, levels)
	return _score_recruit_choice(visible_ids, counts)


func _score_recruit_choice(choices: Array[StringName], counts: Dictionary[StringName, int]) -> StringName:
	var best_id: StringName = choices[0]
	var best_score: float = -INF
	var total_units: int = _sum_counts(counts)

	for hero_id: StringName in choices:
		var count: int = counts.get(hero_id, 0)
		var score: float = 0.0
		if build_policy == "melee_stack":
			score = 100.0 if MELEE_IDS.has(hero_id) else (70.0 if hero_id == &"priest" and count == 0 else 10.0)
			score -= float(count) * 4.0
		elif build_policy == "ranged_kite":
			score = 100.0 if RANGED_IDS.has(hero_id) else 10.0
			if hero_id == &"priest" and count < 2:
				score += 30.0
			score -= float(count) * 4.0
		else:
			if hero_id == &"priest" and count == 0:
				score = 200.0
			elif hero_id == &"priest" and total_units >= 8 and count < 2:
				score = 140.0
			else:
				var melee_cnt: int = _count_group(counts, MELEE_IDS)
				var ranged_cnt: int = _count_group(counts, RANGED_IDS)
				var want_melee: bool = melee_cnt <= ranged_cnt
				var is_melee: bool = MELEE_IDS.has(hero_id)
				score = 80.0 if (is_melee == want_melee) else 45.0
				score -= float(count) * 6.0
		if score > best_score:
			best_score = score
			best_id = hero_id
	return best_id


func _score_level_up_choice(choices: Array[StringName], counts: Dictionary[StringName, int], levels: Dictionary[StringName, int]) -> StringName:
	var best_id: StringName = choices[0]
	var best_score: float = -INF

	for hero_id: StringName in choices:
		var raw_count: int = counts.get(hero_id, 0)
		var raw_lvl: int = levels.get(hero_id, 1)
		var count: int = maxi(1, raw_count)
		var lvl: int = maxi(1, raw_lvl)
		var score: float = float(count) * 12.0 - float(lvl) * 3.0
		if build_policy == "melee_stack" and MELEE_IDS.has(hero_id):
			score += 50.0
		elif build_policy == "ranged_kite" and RANGED_IDS.has(hero_id):
			score += 50.0
		if score > best_score:
			best_score = score
			best_id = hero_id
	return best_id


static func _sum_counts(counts: Dictionary[StringName, int]) -> int:
	var total: int = 0
	for v: int in counts.values():
		total += v
	return total


static func _count_group(counts: Dictionary[StringName, int], group_ids: Array[StringName]) -> int:
	var total: int = 0
	for id: StringName in group_ids:
		total += counts.get(id, 0)
	return total


func _update_room_progress(game: Game, map: Map, leader: Hero, delta: float) -> void:
	var leader_cell: Vector2i = map.local_to_map(leader.global_position)
	var current_room: Rect2i = map.plan.get_room_at(leader_cell)
	if current_room != Rect2i():
		_last_known_room = current_room
		_visited_rooms[current_room] = true
		var depth: int = map.get_room_depth(current_room)
		if depth > max_depth_reached:
			max_depth_reached = depth
		if current_room != map.hero_room:
			var rem: int = game._room_remaining_enemies.get(current_room, 1)
			if rem <= 0 and depth >= mini(target_max_depth, _highest_depth):
				_cleared_at_max_depth = true
				has_won = true

	var cleared_now: int = 0
	for room: Rect2i in game._room_remaining_enemies:
		if game._room_remaining_enemies[room] <= 0:
			cleared_now += 1
	rooms_cleared_count = cleared_now

	if (
		not _is_rushing_gates(map)
		and _last_known_room != map.hero_room
		and not _is_room_done(game, _last_known_room)
		and _goal_room != _last_known_room
	):
		_goal_room = _last_known_room
		_room_path = [_goal_room]
		_shortcut_waypoints.clear()
		_room_stall_timer = 0.0
		_stall_room = _last_known_room
		_min_room_remaining = 999999
		return

	if _last_known_room == _goal_room:
		_shortcut_waypoints.clear()

	if _goal_room == Rect2i() or _is_room_done(game, _goal_room):
		_assign_next_goal(game, map, leader)
		return

	var rem_goal: int = game._room_remaining_enemies.get(_goal_room, -1)
	if _last_known_room != _stall_room:
		_stall_room = _last_known_room
		_room_stall_timer = 0.0
		_min_room_remaining = rem_goal if rem_goal >= 0 else 999999
	elif rem_goal >= 0 and rem_goal < _min_room_remaining:
		_min_room_remaining = rem_goal
		_room_stall_timer = 0.0
	else:
		_room_stall_timer += delta

	if _room_stall_timer >= ROOM_STALL_TIMEOUT:
		_cached_path = PackedVector2Array()
		_room_stall_timer = 0.0
		if not _shortcut_waypoints.is_empty():
			_shortcut_waypoints.remove_at(0)
			return
		if _is_progression_room(game, _goal_room):
			if _last_known_room == _goal_room:
				var obj_pos: Vector2 = _get_gate_objective_pos(game, map)
				if obj_pos != Vector2.ZERO:
					leader.global_position = map.clamp_to_walkable(obj_pos)
			elif not _room_path.is_empty():
				var hop: Rect2i = _room_path[0]
				var hop_rem: int = game._room_remaining_enemies.get(hop, 1)
				if hop == map.hero_room or hop_rem <= 0:
					leader.global_position = map.clamp_to_walkable(map.map_to_local(hop.get_center()))
		else:
			_skipped_rooms[_goal_room] = true
		_assign_next_goal(game, map, leader)


func _assign_next_goal(game: Game, map: Map, leader: Hero) -> void:
	var dest_room: Rect2i = _pick_next_goal_room(game, map, leader)
	var chain: Array[Rect2i] = _find_room_chain(map, _last_known_room, dest_room)
	var next_target: Rect2i = dest_room
	var target_idx: int = chain.size() - 1
	if not _is_rushing_gates(map):
		for i: int in range(chain.size()):
			if not _is_room_done(game, chain[i]):
				next_target = chain[i]
				target_idx = i
				break
	_goal_room = next_target
	_room_path = chain.slice(0, target_idx + 1) if not chain.is_empty() else [next_target]
	_shortcut_waypoints.clear()
	if not _room_path.is_empty():
		_populate_shortcut_waypoints(map, _last_known_room, _room_path[0])
	_room_stall_timer = 0.0
	_stall_room = _last_known_room
	_min_room_remaining = 999999


func _populate_shortcut_waypoints(map: Map, from_room: Rect2i, to_room: Rect2i) -> void:
	for gate: SectorGatePlanner.SectorGate in map.plan.sector_gates:
		if not gate.has_shortcut or not gate.shortcut_opened or gate.key_room != from_room or gate.shortcut_target_room != to_room:
			continue
		if gate.shortcut_waypoints.is_empty():
			return
		_shortcut_waypoints.append(map.map_to_local(gate.shortcut_waypoints[0]))
		for i: int in range(gate.shortcut_waypoints.size() - 1):
			var p0: Vector2i = gate.shortcut_waypoints[i]
			var p1: Vector2i = gate.shortcut_waypoints[i + 1]
			var diff: Vector2 = Vector2(p1 - p0)
			var steps: int = maxi(1, ceili(diff.length() / 28.0))
			for s_idx: int in range(1, steps + 1):
				var t: float = float(s_idx) / float(steps)
				var cell: Vector2i = Vector2i((Vector2(p0) + diff * t).round())
				_shortcut_waypoints.append(map.map_to_local(cell))
		return


func _is_progression_room(game: Game, room: Rect2i) -> bool:
	for gate: SectorGatePlanner.SectorGate in game._map.plan.sector_gates:
		var needs_key: bool = gate.has_key and room == gate.key_room and not game._collected_keys.has(gate.color)
		var needs_lever: bool = gate.has_shortcut and room == gate.key_room and not gate.shortcut_opened and _last_known_room == gate.key_room
		var needs_door: bool = room == gate.gate_room and game._collected_keys.has(gate.color) and not gate.door_unlocked
		if needs_key or needs_lever or needs_door:
			return true
	return false


func _is_room_done(game: Game, room: Rect2i) -> bool:
	if room == Rect2i():
		return true
	if _is_progression_room(game, room):
		return false
	if _is_rushing_gates(game._map) or _skipped_rooms.has(room):
		return true
	if room == game._map.hero_room:
		return not _has_recruit_in_room(game, room)
	if game._room_remaining_enemies.has(room):
		return game._room_remaining_enemies[room] <= 0 and not _has_recruit_in_room(game, room)
	return false


func _get_active_sector_gate(map: Map) -> SectorGatePlanner.SectorGate:
	for gate: SectorGatePlanner.SectorGate in map.plan.sector_gates:
		if not gate.door_unlocked:
			return gate
	return null


func _is_edge_passable(map: Map, room_a: Rect2i, room_b: Rect2i) -> bool:
	for gate: SectorGatePlanner.SectorGate in map.plan.sector_gates:
		if not gate.door_unlocked:
			if (room_a == gate.gate_room and room_b == gate.next_room) or (room_b == gate.gate_room and room_a == gate.next_room):
				return false
		if gate.has_shortcut and not gate.shortcut_opened:
			if (room_a == gate.key_room and room_b == gate.shortcut_target_room) or (room_b == gate.key_room and room_a == gate.shortcut_target_room):
				return false
	return true


func _is_rushing_gates(map: Map) -> bool:
	return rush_deep and _get_active_sector_gate(map) != null


func _get_max_allowed_sector(map: Map) -> int:
	var active_gate: SectorGatePlanner.SectorGate = _get_active_sector_gate(map)
	return int(active_gate.color) if active_gate != null else 4


func _is_room_in_unlocked_sector(map: Map, room: Rect2i) -> bool:
	if room == Rect2i():
		return true
	if _is_room_locked(map, room):
		return false
	return SectorGatePlanner.get_sector_for_depth(map.get_room_depth(room)) <= _get_max_allowed_sector(map)


func _is_room_locked(map: Map, room: Rect2i) -> bool:
	for gate: SectorGatePlanner.SectorGate in map.plan.sector_gates:
		if not gate.door_unlocked and gate.next_room == room:
			return true
	return false


func _has_recruit_in_room(game: Game, room: Rect2i) -> bool:
	for candidate: Unknown in game._unrecruited_characters:
		if not is_instance_valid(candidate):
			continue
		var cell: Vector2i = game._map.local_to_map(candidate.global_position)
		if room.has_point(cell):
			return true
	return false


func _pick_next_goal_room(game: Game, map: Map, leader: Hero) -> Rect2i:
	if _last_known_room != Rect2i() and _last_known_room != map.hero_room and not _is_room_done(game, _last_known_room):
		if not _is_rushing_gates(map) or _is_progression_room(game, _last_known_room):
			return _last_known_room

	var active_gate: SectorGatePlanner.SectorGate = _get_active_sector_gate(map)
	var max_allowed_sector: int = _get_max_allowed_sector(map)
	var cur_depth: int = map.get_room_depth(_last_known_room) if _last_known_room != Rect2i() else 0
	var need_early_recruits: bool = (
		not rush_deep and game._squad.size() < EARLY_RECRUIT_TARGET_SQUAD and (active_gate == null or active_gate.color == WorldPlan.KeyColor.BLUE)
	)
	var best_room: Rect2i = Rect2i()
	var best_score: float = -INF

	for room: Rect2i in map.plan.rooms:
		var depth: int = map.get_room_depth(room)
		if SectorGatePlanner.get_sector_for_depth(depth) > max_allowed_sector:
			continue
		if _is_room_locked(map, room) or _is_room_done(game, room):
			continue
		var dist: float = leader.global_position.distance_to(map.map_to_local(room.get_center()))
		var score: float = 0.0
		if active_gate != null and game._collected_keys.has(active_gate.color) and room == active_gate.gate_room:
			score = 18000.0 - dist * 0.20
		elif active_gate != null and not game._collected_keys.has(active_gate.color) and not need_early_recruits and room == active_gate.key_room:
			score = 15000.0 - dist * 0.20
		elif need_early_recruits and depth <= 2:
			score = 12000.0 - float(depth) * 100.0 - dist * 0.25
		elif not _cleared_at_max_depth and depth > cur_depth and depth <= target_max_depth:
			score = 10000.0 - float(depth - cur_depth) * 500.0 - dist * 0.20
		elif not _cleared_at_max_depth:
			var clamped_depth: int = mini(depth, target_max_depth)
			score = float(clamped_depth) * 200.0 - dist * 0.25
		else:
			score = float(depth) * 150.0 - dist * 0.25

		if score > best_score:
			best_score = score
			best_room = room

	if best_room != Rect2i():
		return best_room
	return _pick_fallback_room(map, leader, _last_known_room)


func _pick_fallback_room(map: Map, leader: Hero, current_room: Rect2i) -> Rect2i:
	var best_room: Rect2i = Rect2i()
	var best_dist: float = INF
	for room: Rect2i in map.plan.rooms:
		if room == current_room:
			continue
		var d: float = leader.global_position.distance_squared_to(map.map_to_local(room.get_center()))
		if d < best_dist:
			best_dist = d
			best_room = room
	return best_room


func _find_room_chain(map: Map, start_room: Rect2i, target_room: Rect2i) -> Array[Rect2i]:
	if target_room == Rect2i():
		return []
	var origin: Rect2i = start_room if start_room != Rect2i() else map.hero_room
	if origin == target_room:
		return [target_room]

	var queue: Array[Rect2i] = [origin]
	var parents: Dictionary[Rect2i, Rect2i] = {}
	var seen: Dictionary[Rect2i, bool] = {origin: true}
	var found: bool = false

	while not queue.is_empty():
		var curr: Rect2i = queue.pop_front()
		if curr == target_room:
			found = true
			break
		var neighbors: Array = _room_graph.get(curr, [])
		for n_var: Variant in neighbors:
			if n_var is Rect2i:
				var n_room: Rect2i = n_var
				if not seen.has(n_room) and _is_edge_passable(map, curr, n_room):
					seen[n_room] = true
					parents[n_room] = curr
					queue.append(n_room)

	if not found:
		return [target_room]

	var chain: Array[Rect2i] = []
	var cursor: Rect2i = target_room
	while cursor != origin:
		chain.append(cursor)
		cursor = parents[cursor]
	chain.reverse()
	return chain


func _decide_move_direction(game: Game, map: Map, leader: Hero, delta: float) -> Vector2:
	var rushing: bool = _is_rushing_gates(map)
	var steer_dest: Vector2 = Vector2.ZERO
	var nearby_recruit: Unknown = _find_nearest_recruit(game, map, leader) if (not rushing or game._squad.size() < 15) else null
	if nearby_recruit != null:
		steer_dest = nearby_recruit.global_position
	else:
		var nearby_key: KeyPickup = _find_nearest_key(game, map, leader)
		if nearby_key != null:
			steer_dest = nearby_key.global_position
		else:
			steer_dest = _find_nearest_potion(game, map, leader, true)

	if steer_dest != Vector2.ZERO:
		return _steer_toward(map, leader, steer_dest, delta)

	if not rushing:
		var combat_target: Enemy = _find_priority_enemy(game, map, leader)
		if combat_target != null:
			return _compute_combat_move(game, map, leader, combat_target, delta)

	if _shortcut_waypoints.is_empty():
		steer_dest = _find_nearest_coin_or_potion(game, map, leader)
	if steer_dest == Vector2.ZERO:
		steer_dest = _get_gate_objective_pos(game, map)
	if steer_dest == Vector2.ZERO:
		steer_dest = _get_exploration_destination(map, leader)
	if steer_dest != Vector2.ZERO:
		return _steer_toward(map, leader, steer_dest, delta)

	if rushing:
		var fallback_target: Enemy = _find_priority_enemy(game, map, leader)
		if fallback_target != null:
			return _compute_combat_move(game, map, leader, fallback_target, delta)
	return Vector2.ZERO


func _is_pickup_reachable(map: Map, leader: Hero, pos: Vector2) -> bool:
	var cell: Vector2i = map.local_to_map(pos)
	if not map.is_cell_walkable(cell):
		return false
	var room: Rect2i = map.plan.get_room_at(cell)
	if not _is_room_in_unlocked_sector(map, room):
		return false
	if room != _last_known_room and room != _goal_room and not SquadNavigator.has_line_of_sight(leader, pos):
		return false
	return true


func _get_squad_hp_ratio(game: Game) -> float:
	var hp_sum: float = 0.0
	var max_sum: float = 0.0
	for member: Hero in game._squad:
		if is_instance_valid(member) and not member.is_dead:
			hp_sum += member.health
			max_sum += member.max_health
	return hp_sum / maxf(1.0, max_sum)


func _find_nearest_potion(game: Game, map: Map, leader: Hero, combat_priority: bool) -> Vector2:
	var leader_hp_ratio: float = leader.health / maxf(1.0, leader.max_health)
	var squad_hp_ratio: float = _get_squad_hp_ratio(game)
	var best_pos: Vector2 = Vector2.ZERO
	var best_dist_sq: float = RECRUIT_SEARCH_RADIUS_SQ
	for potion: PotionPickup in game._potion_manager._potions:
		if not is_instance_valid(potion):
			continue
		if potion.potion_type == PotionPickup.PotionType.HEALTH:
			if combat_priority and leader_hp_ratio >= 0.80 and squad_hp_ratio >= 0.85:
				continue
			if not combat_priority and squad_hp_ratio >= 0.96:
				continue
		var d_sq: float = leader.global_position.distance_squared_to(potion.global_position)
		if d_sq < best_dist_sq and _is_pickup_reachable(map, leader, potion.global_position):
			best_dist_sq = d_sq
			best_pos = potion.global_position
	return best_pos


func _find_nearest_coin(game: Game, map: Map, leader: Hero) -> Vector2:
	var best_pos: Vector2 = Vector2.ZERO
	var best_dist_sq: float = RECRUIT_SEARCH_RADIUS_SQ
	for coin: Coin in game._coins:
		if not is_instance_valid(coin):
			continue
		var d_sq: float = leader.global_position.distance_squared_to(coin.global_position)
		if d_sq < best_dist_sq and _is_pickup_reachable(map, leader, coin.global_position):
			best_dist_sq = d_sq
			best_pos = coin.global_position
	return best_pos


func _find_nearest_coin_or_potion(game: Game, map: Map, leader: Hero) -> Vector2:
	var pot_pos: Vector2 = _find_nearest_potion(game, map, leader, false)
	if pot_pos != Vector2.ZERO:
		return pot_pos
	return _find_nearest_coin(game, map, leader)


func _find_nearest_key(game: Game, map: Map, leader: Hero) -> KeyPickup:
	var best: KeyPickup = null
	var best_dist_sq: float = INF
	for candidate: KeyPickup in game._keys:
		if not is_instance_valid(candidate):
			continue
		var key_cell: Vector2i = map.local_to_map(candidate.global_position)
		if not map.is_cell_walkable(key_cell):
			continue
		var key_room: Rect2i = map.plan.get_room_at(key_cell)
		if not _is_room_in_unlocked_sector(map, key_room):
			continue
		var d_sq: float = leader.global_position.distance_squared_to(candidate.global_position)
		var in_cur_room: bool = _last_known_room != Rect2i() and _last_known_room.has_point(key_cell)
		var can_reach: bool = in_cur_room
		if not can_reach and d_sq < RECRUIT_SEARCH_RADIUS_SQ:
			can_reach = key_room == _goal_room or SquadNavigator.has_line_of_sight(leader, candidate.global_position)
		if can_reach and d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best = candidate
	return best


func _get_gate_objective_pos(game: Game, map: Map) -> Vector2:
	var active_gate: SectorGatePlanner.SectorGate = _get_active_sector_gate(map)
	if active_gate != null:
		if active_gate.has_key and not game._collected_keys.has(active_gate.color) and _last_known_room == active_gate.key_room:
			return map.map_to_local(active_gate.key_cell)
		if game._collected_keys.has(active_gate.color):
			if active_gate.has_shortcut and not active_gate.shortcut_opened and _last_known_room == active_gate.key_room:
				return map.map_to_local(active_gate.lever_cell)
			if _last_known_room == active_gate.gate_room:
				var door_pos: Vector2 = (map.map_to_local(active_gate.door_cells[0]) + map.map_to_local(active_gate.door_cells[1])) * 0.5
				return door_pos + Vector2(0.0, 12.0)
	for gate: SectorGatePlanner.SectorGate in map.plan.sector_gates:
		if gate.has_key and not game._collected_keys.has(gate.color) and _last_known_room == gate.key_room:
			return map.map_to_local(gate.key_cell)
		if not gate.door_unlocked and _last_known_room == gate.gate_room and game._collected_keys.has(gate.color):
			var d_pos: Vector2 = (map.map_to_local(gate.door_cells[0]) + map.map_to_local(gate.door_cells[1])) * 0.5
			return d_pos + Vector2(0.0, 12.0)
	return Vector2.ZERO


func _find_nearest_recruit(game: Game, map: Map, leader: Hero) -> Unknown:
	var best: Unknown = null
	var best_dist_sq: float = RECRUIT_SEARCH_RADIUS_SQ
	for candidate: Unknown in game._unrecruited_characters:
		if not is_instance_valid(candidate):
			continue
		var d_sq: float = leader.global_position.distance_squared_to(candidate.global_position)
		if d_sq >= best_dist_sq:
			continue
		var rec_cell: Vector2i = map.local_to_map(candidate.global_position)
		if not map.is_cell_walkable(rec_cell):
			continue
		var rec_room: Rect2i = map.plan.get_room_at(rec_cell)
		if not _is_room_in_unlocked_sector(map, rec_room):
			continue
		if rec_room != _last_known_room and rec_room != _goal_room and not SquadNavigator.has_line_of_sight(leader, candidate.global_position):
			continue
		best_dist_sq = d_sq
		best = candidate
	return best


func _find_priority_enemy(game: Game, map: Map, leader: Hero) -> Enemy:
	var best_necro: Enemy = null
	var best_necro_dist_sq: float = INF
	var best: Enemy = null
	var best_score: float = INF
	for enemy: Enemy in game._enemies:
		if not is_instance_valid(enemy) or enemy.is_dead or not enemy.visible:
			continue
		var d_sq: float = leader.global_position.distance_squared_to(enemy.global_position)
		if d_sq > COMBAT_SEARCH_RADIUS_SQ:
			continue
		if not _is_room_in_unlocked_sector(map, enemy.home_room):
			continue
		var enemy_room: Rect2i = map.plan.get_room_at(map.local_to_map(enemy.global_position))
		if not _is_room_in_unlocked_sector(map, enemy_room):
			continue
		if enemy.home_room != _last_known_room and enemy.home_room != _goal_room and enemy_room != _last_known_room:
			if not SquadNavigator.has_line_of_sight(leader, enemy.global_position):
				continue
		if enemy is Necromancer:
			if d_sq < best_necro_dist_sq:
				best_necro_dist_sq = d_sq
				best_necro = enemy
		elif d_sq < best_score:
			best_score = d_sq
			best = enemy

	var best_room_enemy: Enemy = null
	var best_room_dist_sq: float = INF
	for enemy: Enemy in game._enemies:
		if not is_instance_valid(enemy) or enemy.is_dead or not enemy.visible:
			continue
		if not _is_room_in_unlocked_sector(map, enemy.home_room):
			continue
		if enemy.home_room != _last_known_room and enemy.home_room != _goal_room:
			continue
		var d_sq: float = leader.global_position.distance_squared_to(enemy.global_position)
		if enemy is Necromancer:
			if d_sq < best_necro_dist_sq:
				best_necro_dist_sq = d_sq
				best_necro = enemy
		elif best == null and d_sq < best_room_dist_sq:
			best_room_dist_sq = d_sq
			best_room_enemy = enemy

	if best_necro != null:
		return best_necro
	if best != null:
		return best
	return best_room_enemy


func _compute_combat_move(game: Game, map: Map, leader: Hero, target: Enemy, delta: float) -> Vector2:
	var desired_range: float = _get_desired_combat_range(game, leader, target)
	var to_enemy: Vector2 = target.global_position - leader.global_position
	var dist: float = to_enemy.length()
	if dist <= 0.001:
		return Vector2.UP

	var has_los: bool = SquadNavigator.has_line_of_sight(leader, target.global_position)
	if not has_los or dist > desired_range + 16.0:
		return _steer_toward(map, leader, target.global_position, delta)

	if dist < desired_range - 14.0:
		return _pick_safe_kite_direction(map, leader.global_position, -to_enemy / dist)

	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = 1.4
		_strafe_sign = -_strafe_sign
	var dir_to_enemy: Vector2 = to_enemy / dist
	var strafe_dir: Vector2 = Vector2(-dir_to_enemy.y, dir_to_enemy.x) * _strafe_sign
	if _is_step_walkable(map, leader.global_position + strafe_dir * 20.0):
		return strafe_dir
	return Vector2.ZERO


func _get_desired_combat_range(game: Game, leader: Hero, target: Enemy) -> float:
	var hp_ratio: float = leader.health / maxf(1.0, leader.max_health)
	if hp_ratio < 0.30:
		return 95.0
	if not leader.can_melee or leader.can_ranged:
		return 85.0
	if target is Necromancer or game._squad.size() <= 2:
		return 16.0
	return 34.0


func _pick_safe_kite_direction(map: Map, pos: Vector2, away_dir: Vector2) -> Vector2:
	var offsets: Array[float] = [0.0, 0.55, -0.55, 1.15, -1.15]
	for angle_off: float in offsets:
		var cand: Vector2 = away_dir.rotated(angle_off)
		if _is_step_walkable(map, pos + cand * 22.0):
			return cand
	return away_dir


func _get_exploration_destination(map: Map, leader: Hero) -> Vector2:
	while not _shortcut_waypoints.is_empty():
		if leader.global_position.distance_squared_to(_shortcut_waypoints[0]) <= ROOM_ARRIVE_DIST_SQ:
			_shortcut_waypoints.remove_at(0)
			_room_stall_timer = 0.0
		else:
			return _shortcut_waypoints[0]

	while not _room_path.is_empty():
		var hop_center: Vector2 = map.clamp_to_walkable(map.map_to_local(_room_path[0].get_center()))
		var arrived_hop: bool = _last_known_room == _room_path[0] or leader.global_position.distance_squared_to(hop_center) <= ROOM_ARRIVE_DIST_SQ
		if arrived_hop and _room_path.size() > 1:
			var popped: Rect2i = _room_path[0]
			_room_path.remove_at(0)
			_populate_shortcut_waypoints(map, popped, _room_path[0])
			if not _shortcut_waypoints.is_empty():
				return _shortcut_waypoints[0]
		else:
			return hop_center

	if _goal_room != Rect2i():
		return map.clamp_to_walkable(map.map_to_local(_goal_room.get_center()))
	return Vector2.ZERO


func get_keys_mask(game: Game) -> String:
	var color_chars: Array[String] = ["B", "G", "Y", "R"]
	var keys_str: String = ""
	for i: int in range(color_chars.size()):
		var kc: WorldPlan.KeyColor = i as WorldPlan.KeyColor
		if game._collected_keys.has(kc):
			keys_str += color_chars[i]
	return keys_str if keys_str != "" else "-"


func get_doors_mask(map: Map) -> String:
	var color_chars: Array[String] = ["B", "G", "Y", "R"]
	var doors_str: String = ""
	for i: int in range(color_chars.size()):
		var kc: WorldPlan.KeyColor = i as WorldPlan.KeyColor
		for gate: SectorGatePlanner.SectorGate in map.plan.sector_gates:
			if gate.color == kc and gate.door_unlocked:
				doors_str += color_chars[i]
				break
	return doors_str if doors_str != "" else "-"


func get_gate_progress_tag(game: Game, map: Map) -> String:
	var goal_d: int = map.get_room_depth(_goal_room) if _goal_room != Rect2i() else -1
	return "keys=%s doors=%s goalD=%d" % [get_keys_mask(game), get_doors_mask(map), goal_d]


func _steer_toward(map: Map, leader: Hero, world_dest: Vector2, delta: float) -> Vector2:
	var dest: Vector2 = world_dest
	if not map.is_in_nav_bounds(dest):
		var dir_to_dest: Vector2 = (world_dest - leader.global_position).normalized()
		dest = map.clamp_to_walkable(leader.global_position + dir_to_dest * 480.0)

	_repath_timer -= delta
	if _cached_path.is_empty() or _repath_timer <= 0.0 or dest.distance_squared_to(_cached_path_dest) > 1024.0:
		_repath_timer = 0.25
		_cached_path_dest = dest
		_cached_path = map.get_navigation_path(leader.global_position, dest)

	while _cached_path.size() > 1 and leader.global_position.distance_squared_to(_cached_path[0]) <= WAYPOINT_REACHED_DIST_SQ:
		_cached_path.remove_at(0)

	var next_pt: Vector2 = _cached_path[0] if not _cached_path.is_empty() else dest
	var to_next: Vector2 = next_pt - leader.global_position
	if to_next.length_squared() <= 4.0:
		return Vector2.ZERO
	return to_next.normalized()


func _apply_spike_avoidance(map: Map, world_pos: Vector2, move_dir: Vector2) -> Vector2:
	var base_cell: Vector2i = map.local_to_map(world_pos)
	var avoid: Vector2 = Vector2.ZERO
	for dy: int in range(-SPIKE_AVOID_RADIUS_CELLS, SPIKE_AVOID_RADIUS_CELLS + 1):
		for dx: int in range(-SPIKE_AVOID_RADIUS_CELLS, SPIKE_AVOID_RADIUS_CELLS + 1):
			var check_cell: Vector2i = base_cell + Vector2i(dx, dy)
			if map.is_spike_active_at(check_cell):
				var spike_world: Vector2 = map.map_to_local(check_cell)
				var away: Vector2 = world_pos - spike_world
				var d_sq: float = maxf(16.0, away.length_squared())
				avoid += away.normalized() * (640.0 / d_sq)

	if avoid.length_squared() <= 0.01:
		return move_dir
	if move_dir.length_squared() <= 0.01:
		return avoid.normalized()
	return (move_dir + avoid * 0.75).normalized()


func _update_stuck_recovery(map: Map, leader: Hero, move_dir: Vector2, delta: float) -> void:
	if _sidestep_timer > 0.0:
		_sidestep_timer = maxf(0.0, _sidestep_timer - delta)

	if move_dir.length_squared() < 0.01:
		_stuck_timer = 0.0
		_anchor_pos = leader.global_position
		return

	var anchor_dist_sq: float = (48.0 * 48.0) if rush_deep else STUCK_DIST_SQ
	if _anchor_pos == Vector2.ZERO or leader.global_position.distance_squared_to(_anchor_pos) > anchor_dist_sq:
		_anchor_pos = leader.global_position
		_stuck_timer = 0.0
		return

	_stuck_timer += delta
	if _stuck_timer >= STUCK_SIDESTEP_TIME and _sidestep_timer <= 0.0:
		_sidestep_timer = 0.65
		_sidestep_sign = -_sidestep_sign

	if _stuck_timer >= STUCK_UNSTICK_TIME:
		_stuck_timer = 0.0
		if not _shortcut_waypoints.is_empty() and _cached_path.size() <= 2:
			leader.global_position = map.clamp_to_walkable(_shortcut_waypoints[0])
			if leader.global_position.distance_squared_to(_shortcut_waypoints[0]) <= ROOM_ARRIVE_DIST_SQ:
				_shortcut_waypoints.remove_at(0)
				_room_stall_timer = 0.0
			_cached_path = PackedVector2Array()
		elif not _cached_path.is_empty():
			var step_idx: int = mini(8 if rush_deep else 2, _cached_path.size() - 1)
			leader.global_position = map.clamp_to_walkable(_cached_path[step_idx])
			_cached_path = PackedVector2Array()
		else:
			leader.global_position = map.clamp_to_walkable(leader.global_position + move_dir * 24.0)
		_anchor_pos = leader.global_position


func _is_step_walkable(map: Map, world_pos: Vector2) -> bool:
	return map.is_cell_walkable(map.local_to_map(world_pos))


func _apply_movement(dir: Vector2) -> void:
	if dir.length_squared() < 0.01:
		release_movement()
		return
	var norm: Vector2 = dir.normalized()
	_set_axis_actions(norm.x, &"left", &"right")
	_set_axis_actions(norm.y, &"up", &"down")


func _set_axis_actions(value: float, neg_action: StringName, pos_action: StringName) -> void:
	if value < -0.08:
		var strength: float = ACTION_DEADZONE + (1.0 - ACTION_DEADZONE) * clampf(-value, 0.0, 1.0)
		Input.action_press(neg_action, strength)
		Input.action_release(pos_action)
	elif value > 0.08:
		var strength: float = ACTION_DEADZONE + (1.0 - ACTION_DEADZONE) * clampf(value, 0.0, 1.0)
		Input.action_press(pos_action, strength)
		Input.action_release(neg_action)
	else:
		Input.action_release(neg_action)
		Input.action_release(pos_action)
