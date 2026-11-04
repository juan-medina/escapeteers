# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Benchmark
extends Node2D

const BENCHMARK_FRAMES: int = 1800
const PHASE_1_END_FRAME: int = 180
const BENCHMARK_SEED: int = 12345
const PLAYER_SPEED: float = 950.0
const WAYPOINT_REACHED_DIST: float = 32.0
const CHURN_FRAME_THRESHOLD: int = 5
const TOP_SPIKE_COUNT: int = 5
const GAME_SCENE: PackedScene = preload("res://game/game.tscn")

var _game: Game = null
var _map: Map = null
var _character: Hero = null
var _frame_count: int = 0
var _last_tick_usec: int = 0

var _delta_times_ms: Array[float] = []
var _cpu_times_ms: Array[float] = []
var _phase1_cpu_ms: Array[float] = []
var _phase2_cpu_ms: Array[float] = []
var _max_delta_spike_ms: float = 0.0
var _max_cpu_spike_ms: float = 0.0

var _waypoints: Array[Vector2] = []
var _waypoint_index: int = 0

var _max_awake_offscreen: int = 0
var _sum_awake_offscreen: int = 0
var _max_unmaterialized_enemies: int = 0
var _frames_with_unmaterialized_enemies: int = 0
var _max_empty_path_awake: int = 0
var _frames_with_empty_path_awake: int = 0
var _nav_recenter_count: int = 0
var _last_nav_center: Vector2i = Vector2i(-999999, -999999)

var _active_enemy_spawn_frame: Dictionary[int, int] = {}
var _active_enemy_last_dist_sq: Dictionary[int, float] = {}
var _instant_despawn_churn_count: int = 0
var _total_despawns_observed: int = 0

var _visited_rooms_order: Array[Rect2i] = []
var _visited_room_peak_live: Dictionary[Rect2i, int] = {}
var _visited_room_entry_live: Dictionary[Rect2i, int] = {}
var _visited_room_was_registered: Dictionary[Rect2i, bool] = {}
var _visited_room_active_cap_at_entry: Dictionary[Rect2i, int] = {}
var _visited_room_pending_at_entry: Dictionary[Rect2i, int] = {}

var _spike_records: Array[Dictionary] = []


func _ready() -> void:
	set_process(false)
	print(&"=== STARTING DEEP BENCHMARK (%d frames, Seed %d) ===" % [BENCHMARK_FRAMES, BENCHMARK_SEED])
	_game = GAME_SCENE.instantiate() as Game
	_map = _game.get_node_or_null(^"Map") as Map
	if _map != null:
		_map.debug_seed = BENCHMARK_SEED
	add_child(_game)

	while is_instance_valid(_game) and not _game.is_processing():
		await get_tree().process_frame

	_character = _game.get_node_or_null(^"Characters/Character") as Hero
	if is_instance_valid(_character):
		_character.max_health = 999999.0
		_character.health = 999999.0
		_character.set_process(false)
		_character.disable_collisions()

	_build_exploration_route()
	if _map != null and _map.nav_window != null:
		_last_nav_center = _map.nav_window._center_cell

	_last_tick_usec = Time.get_ticks_usec()
	set_process(true)


func _process(delta: float) -> void:
	if _game == null or _map == null or not is_instance_valid(_character):
		return

	var now_usec: int = Time.get_ticks_usec()
	var cpu_ms: float = float(now_usec - _last_tick_usec) / 1000.0
	_last_tick_usec = now_usec

	_frame_count += 1
	var delta_ms: float = delta * 1000.0
	_delta_times_ms.append(delta_ms)
	_cpu_times_ms.append(cpu_ms)

	if _frame_count <= PHASE_1_END_FRAME:
		_phase1_cpu_ms.append(cpu_ms)
	else:
		_phase2_cpu_ms.append(cpu_ms)

	if delta_ms > _max_delta_spike_ms:
		_max_delta_spike_ms = delta_ms
	if cpu_ms > _max_cpu_spike_ms:
		_max_cpu_spike_ms = cpu_ms

	_prevent_recruit_pause()
	_advance_player_along_route(delta)
	_sample_frame_diagnostics(cpu_ms, delta_ms)

	if _frame_count >= BENCHMARK_FRAMES:
		_finish_benchmark()
		get_tree().quit(0)


func _build_exploration_route() -> void:
	_waypoints.clear()
	_waypoint_index = 0
	if _map == null or _map.plan == null:
		return

	var visited: Dictionary[Rect2i, bool] = {}
	var route_rooms: Array[Rect2i] = []
	var current_center: Vector2 = Vector2(_map.hero_room.get_center())

	while route_rooms.size() < _map.plan.rooms.size():
		var best_room: Rect2i = Rect2i()
		var best_dist_sq: float = INF
		var found: bool = false
		for candidate: Rect2i in _map.plan.rooms:
			if visited.has(candidate):
				continue
			var d_sq: float = current_center.distance_squared_to(Vector2(candidate.get_center()))
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best_room = candidate
				found = true
		if not found:
			break
		visited[best_room] = true
		route_rooms.append(best_room)
		current_center = Vector2(best_room.get_center())

	for room: Rect2i in route_rooms:
		var waypoint_cell: Vector2i = room.get_center() + Vector2i(0, 3)
		_waypoints.append(_map.map_to_local(waypoint_cell))

	print(&"[Benchmark] Built exploration route across %d rooms (%d waypoints)." % [route_rooms.size(), _waypoints.size()])


func _prevent_recruit_pause() -> void:
	for i: int in range(_game._unrecruited_characters.size() - 1, -1, -1):
		var candidate: Character = _game._unrecruited_characters[i]
		if is_instance_valid(candidate) and candidate.position.distance_squared_to(_character.position) <= 36.0 * 36.0:
			candidate.position += Vector2(120.0, 0.0)


func _advance_player_along_route(delta: float) -> void:
	if _waypoints.is_empty():
		_character.position.y -= PLAYER_SPEED * delta
		_character.velocity = Vector2(0.0, -PLAYER_SPEED)
		return

	var target_pos: Vector2 = _waypoints[_waypoint_index]
	var to_target: Vector2 = target_pos - _character.position
	var dist: float = to_target.length()

	if dist <= WAYPOINT_REACHED_DIST:
		_waypoint_index = (_waypoint_index + 1) % _waypoints.size()
		target_pos = _waypoints[_waypoint_index]
		to_target = target_pos - _character.position
		dist = to_target.length()

	if dist > 0.001:
		var dir: Vector2 = to_target / dist
		_character.move_direction = dir
		_character.velocity = dir * PLAYER_SPEED
		_character.position += dir * PLAYER_SPEED * delta


func _sample_frame_diagnostics(cpu_ms: float, delta_ms: float) -> void:
	var nav_recentered: bool = false
	if _map.nav_window != null and _map.nav_window._center_cell != _last_nav_center:
		_last_nav_center = _map.nav_window._center_cell
		_nav_recenter_count += 1
		nav_recentered = true

	var awake_offscreen: int = 0
	var unmaterialized: int = 0
	var empty_path_awake: int = 0
	var current_ids: Dictionary[int, bool] = {}
	var room_live_counts: Dictionary[Rect2i, int] = {}
	var cam_pos: Vector2 = _character.global_position

	for enemy: Enemy in _game._enemies:
		if not is_instance_valid(enemy) or enemy.is_dead:
			continue
		var inst_id: int = enemy.get_instance_id()
		current_ids[inst_id] = true
		if not _active_enemy_spawn_frame.has(inst_id):
			_active_enemy_spawn_frame[inst_id] = _frame_count
		_active_enemy_last_dist_sq[inst_id] = enemy.global_position.distance_squared_to(cam_pos)

		var h_room: Rect2i = enemy.home_room
		room_live_counts[h_room] = room_live_counts.get(h_room, 0) + 1

		var is_awake: bool = enemy.is_physics_processing()
		if is_awake and not enemy.is_on_screen:
			awake_offscreen += 1

		var cell: Vector2i = _map.local_to_map(enemy.global_position)
		if not _map.is_cell_walkable(cell):
			unmaterialized += 1

		if is_awake and enemy._navigator != null and enemy._navigator._current_path.is_empty():
			empty_path_awake += 1

	var tracked_ids: Array[int] = _active_enemy_spawn_frame.keys()
	for old_id: int in tracked_ids:
		if not current_ids.has(old_id):
			var age_frames: int = _frame_count - _active_enemy_spawn_frame[old_id]
			_total_despawns_observed += 1
			if age_frames <= CHURN_FRAME_THRESHOLD:
				_instant_despawn_churn_count += 1
			_active_enemy_spawn_frame.erase(old_id)
			_active_enemy_last_dist_sq.erase(old_id)

	_sum_awake_offscreen += awake_offscreen
	if awake_offscreen > _max_awake_offscreen:
		_max_awake_offscreen = awake_offscreen
	if unmaterialized > _max_unmaterialized_enemies:
		_max_unmaterialized_enemies = unmaterialized
	if unmaterialized > 0:
		_frames_with_unmaterialized_enemies += 1
	if empty_path_awake > _max_empty_path_awake:
		_max_empty_path_awake = empty_path_awake
	if empty_path_awake > 0:
		_frames_with_empty_path_awake += 1

	var player_cell: Vector2i = _map.local_to_map(_character.global_position)
	var current_room: Rect2i = _map.plan.get_room_at(player_cell)
	if current_room != Rect2i() and current_room != _map.hero_room:
		var live_in_room: int = room_live_counts.get(current_room, 0)
		if not _visited_room_peak_live.has(current_room):
			_visited_rooms_order.append(current_room)
			_visited_room_entry_live[current_room] = live_in_room
			_visited_room_peak_live[current_room] = live_in_room
			_visited_room_was_registered[current_room] = _map.companion_rooms.has(current_room)
			_visited_room_active_cap_at_entry[current_room] = _game._enemies.size()
			_visited_room_pending_at_entry[current_room] = _game._pending_spawns.size()
		else:
			if live_in_room > _visited_room_peak_live[current_room]:
				_visited_room_peak_live[current_room] = live_in_room
			if _map.companion_rooms.has(current_room):
				_visited_room_was_registered[current_room] = true

	_record_spike_candidate(cpu_ms, delta_ms, awake_offscreen, unmaterialized, empty_path_awake, nav_recentered)


func _record_spike_candidate(
	cpu_ms: float, delta_ms: float, awake_offscreen: int, unmaterialized: int, empty_path_awake: int, nav_recentered: bool
) -> void:
	var entry: Dictionary = {
		&"frame": _frame_count,
		&"cpu_ms": cpu_ms,
		&"delta_ms": delta_ms,
		&"enemies": _game._enemies.size(),
		&"pending_spawns": _game._pending_spawns.size(),
		&"awake_offscreen": awake_offscreen,
		&"unmaterialized": unmaterialized,
		&"empty_path_awake": empty_path_awake,
		&"queued_chunks": _map.streamer.get_queued_chunk_count() if _map.streamer != null else 0,
		&"nav_recentered": nav_recentered,
	}
	_spike_records.append(entry)
	_spike_records.sort_custom(_compare_spike_records)
	if _spike_records.size() > TOP_SPIKE_COUNT:
		_spike_records.resize(TOP_SPIKE_COUNT)


static func _compare_spike_records(a: Dictionary, b: Dictionary) -> bool:
	var cpu_a: float = a[&"cpu_ms"]
	var cpu_b: float = b[&"cpu_ms"]
	return cpu_a > cpu_b


static func _compute_percentile(sorted_values: Array[float], pct: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var idx: int = clampi(int(float(sorted_values.size()) * pct), 0, sorted_values.size() - 1)
	return sorted_values[idx]


static func _compute_average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for v: float in values:
		total += v
	return total / float(values.size())


func _finish_benchmark() -> void:
	_delta_times_ms.sort()
	_cpu_times_ms.sort()
	_phase1_cpu_ms.sort()
	_phase2_cpu_ms.sort()

	var n: int = _cpu_times_ms.size()
	var cpu_avg: float = _compute_average(_cpu_times_ms)
	var cpu_p50: float = _compute_percentile(_cpu_times_ms, 0.50)
	var cpu_p95: float = _compute_percentile(_cpu_times_ms, 0.95)
	var cpu_p99: float = _compute_percentile(_cpu_times_ms, 0.99)

	var p1_avg: float = _compute_average(_phase1_cpu_ms)
	var p1_p99: float = _compute_percentile(_phase1_cpu_ms, 0.99)
	var p2_avg: float = _compute_average(_phase2_cpu_ms)
	var p2_p99: float = _compute_percentile(_phase2_cpu_ms, 0.99)

	var cpu_spikes_8ms: int = 0
	var cpu_spikes_16ms: int = 0
	for t: float in _cpu_times_ms:
		if t > 8.0:
			cpu_spikes_8ms += 1
		if t > 16.67:
			cpu_spikes_16ms += 1

	var empty_rooms_count: int = 0
	var empty_on_entry_count: int = 0
	var unregistered_rooms_count: int = 0
	var underpopulated_rooms_count: int = 0
	for room: Rect2i in _visited_rooms_order:
		var quota: int = _map.get_room_enemy_quota(room)
		var entry_live: int = _visited_room_entry_live.get(room, 0)
		var peak_live: int = _visited_room_peak_live.get(room, 0)
		var was_reg: bool = _visited_room_was_registered.get(room, false)
		if not was_reg:
			unregistered_rooms_count += 1
		if entry_live == 0:
			empty_on_entry_count += 1
		if peak_live == 0:
			empty_rooms_count += 1
		elif float(peak_live) < float(quota) * 0.5:
			underpopulated_rooms_count += 1

	var avg_awake_offscreen: float = float(_sum_awake_offscreen) / float(maxi(1, n))

	print(&"\n================ DEEP BENCHMARK REPORT ================")
	print(&"Total Frames Sampled:          %d" % n)
	print(&"CPU Frame Time Avg / p50:      %.2f ms / %.2f ms" % [cpu_avg, cpu_p50])
	print(&"CPU Frame Time p95 / p99:      %.2f ms / %.2f ms" % [cpu_p95, cpu_p99])
	print(&"Max CPU Spike / Engine Delta:  %.2f ms / %.2f ms" % [_max_cpu_spike_ms, _max_delta_spike_ms])
	print(&"Phase 1 (Start 1-%d) Avg/p99: %.2f ms / %.2f ms" % [PHASE_1_END_FRAME, p1_avg, p1_p99])
	print(&"Phase 2 (Explore) Avg/p99:     %.2f ms / %.2f ms" % [p2_avg, p2_p99])
	print(&"CPU Frames > 8.0ms / > 16.7ms: %d / %d" % [cpu_spikes_8ms, cpu_spikes_16ms])
	print(&"-------------------------------------------------------")
	print(&"MOB & STREAMING DIAGNOSTICS:")
	print(&"Awake Off-Screen Mobs Avg/Max: %.1f / %d" % [avg_awake_offscreen, _max_awake_offscreen])
	print(&"Mobs on Unstreamed Tiles Max:  %d (%d frames affected)" % [_max_unmaterialized_enemies, _frames_with_unmaterialized_enemies])
	print(&"Awake Mobs w/ Empty A* Path:   %d max (%d frames affected)" % [_max_empty_path_awake, _frames_with_empty_path_awake])
	print(&"Instant Spawn-Despawn Churn:   %d / %d total despawns" % [_instant_despawn_churn_count, _total_despawns_observed])
	print(&"NavWindow Recenters:           %d" % _nav_recenter_count)
	print(&"-------------------------------------------------------")
	print(&"ROOM POPULATION AUDIT (%d non-starter rooms visited):" % _visited_rooms_order.size())
	print(&"Empty on Entry (0 mobs):       %d" % empty_on_entry_count)
	print(&"Empty at Peak (0 mobs):        %d" % empty_rooms_count)
	print(&"Underpopulated (<50%% quota):   %d" % underpopulated_rooms_count)
	print(&"Unregistered Rooms Entered:    %d" % unregistered_rooms_count)
	for i: int in range(_visited_rooms_order.size()):
		var room: Rect2i = _visited_rooms_order[i]
		var depth: int = _map.get_room_depth(room)
		var quota: int = _map.get_room_enemy_quota(room)
		var entry_l: int = _visited_room_entry_live.get(room, 0)
		var peak: int = _visited_room_peak_live.get(room, 0)
		var reg: bool = _visited_room_was_registered.get(room, false)
		var cap_entry: int = _visited_room_active_cap_at_entry.get(room, 0)
		var pend_entry: int = _visited_room_pending_at_entry.get(room, 0)
		print(
			(
				&"  Room #%02d [Depth %d, %dx%d]: entry=%d peak=%d/%d | reg=%s | active=%d, pend=%d"
				% [i + 1, depth, room.size.x, room.size.y, entry_l, peak, quota, str(reg), cap_entry, pend_entry]
			)
		)
	print(&"-------------------------------------------------------")
	print(&"TOP %d SLOWEST CPU FRAMES:" % _spike_records.size())
	for rec: Dictionary in _spike_records:
		var part1: String = (
			&"  Frame %04d: cpu=%.2fms (delta=%.2fms) | enemies=%d (pend=%d)"
			% [
				rec[&"frame"],
				rec[&"cpu_ms"],
				rec[&"delta_ms"],
				rec[&"enemies"],
				rec[&"pending_spawns"],
			]
		)
		var part2: String = (
			&" | awake_off=%d | unstream=%d | empty_path=%d | q_chunks=%d | recenter=%s"
			% [
				rec[&"awake_offscreen"],
				rec[&"unmaterialized"],
				rec[&"empty_path_awake"],
				rec[&"queued_chunks"],
				str(rec[&"nav_recentered"]),
			]
		)
		print(part1 + part2)
	print(&"Static Memory:                 %.2f MB" % [float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0)])
	print(&"=======================================================\n")
