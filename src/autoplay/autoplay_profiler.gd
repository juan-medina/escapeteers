# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name AutoplayProfiler
extends RefCounted

const TOP_SPIKE_COUNT: int = 20
const SPIKE_WARN_MS: float = 8.0
const FRAME_BUDGET_MS: float = 16.67

var _has_pending_frame: bool = false
var _pending_frame: Dictionary = {}
var _pending_start_usec: int = 0
var _last_balance_usec: int = 0
var _prev_loaded_chunks: Dictionary[Vector2i, bool] = {}

var _total_frames: int = 0
var _cpu_ms_samples: Array[float] = []
var _other_ms_samples: Array[float] = []
var _process_ms_samples: Array[float] = []
var _physics_ms_samples: Array[float] = []
var _wall_ms_samples: Array[float] = []
var _streaming_ms_samples: Array[float] = []
var _squad_ms_samples: Array[float] = []
var _enemies_ms_samples: Array[float] = []
var _spawns_ms_samples: Array[float] = []
var _hazards_ms_samples: Array[float] = []
var _bot_ms_samples: Array[float] = []

var _spikes_over_8ms: int = 0
var _spikes_over_16ms: int = 0
var _nav_recenter_count: int = 0
var _nav_recenter_stream_ms: Array[float] = []
var _chunk_load_count: int = 0
var _chunk_load_stream_ms: Array[float] = []
var _chunk_evict_count: int = 0
var _chunk_evict_stream_ms: Array[float] = []
var _max_squad_seen: int = 0
var _max_awake_enemies_seen: int = 0
var _max_awake_offscreen_seen: int = 0
var _max_projectiles_seen: int = 0
var _max_collision_pairs_seen: int = 0
var _max_nodes_seen: int = 0
var _top_spikes: Array[Dictionary] = []


func reset_session() -> void:
	_has_pending_frame = false
	_pending_frame = {}
	_pending_start_usec = 0
	_last_balance_usec = 0
	_prev_loaded_chunks.clear()
	_total_frames = 0
	_cpu_ms_samples.clear()
	_other_ms_samples.clear()
	_process_ms_samples.clear()
	_physics_ms_samples.clear()
	_wall_ms_samples.clear()
	_streaming_ms_samples.clear()
	_squad_ms_samples.clear()
	_enemies_ms_samples.clear()
	_spawns_ms_samples.clear()
	_hazards_ms_samples.clear()
	_bot_ms_samples.clear()
	_spikes_over_8ms = 0
	_spikes_over_16ms = 0
	_nav_recenter_count = 0
	_nav_recenter_stream_ms.clear()
	_chunk_load_count = 0
	_chunk_load_stream_ms.clear()
	_chunk_evict_count = 0
	_chunk_evict_stream_ms.clear()
	_max_squad_seen = 0
	_max_awake_enemies_seen = 0
	_max_awake_offscreen_seen = 0
	_max_projectiles_seen = 0
	_max_collision_pairs_seen = 0
	_max_nodes_seen = 0
	_top_spikes.clear()


func begin_run(map: Map) -> void:
	_has_pending_frame = false
	_pending_frame = {}
	_last_balance_usec = 0
	_prev_loaded_chunks.clear()
	for coord: Vector2i in map.streamer._loaded_chunks:
		_prev_loaded_chunks[coord] = true


func on_tick_start() -> void:
	if not _has_pending_frame:
		return
	var now_usec: int = Time.get_ticks_usec()
	_finalize_pending_frame(now_usec)


func record_balance_overhead(balance_usec: int) -> void:
	_last_balance_usec = balance_usec


func flush_pending_frame() -> void:
	if not _has_pending_frame:
		return
	var now_usec: int = Time.get_ticks_usec()
	_finalize_pending_frame(now_usec)


func step_game_frame(game: Game, map: Map, delta: float, sim_frame: int, seed_val: int, bot_usec: int) -> void:
	var frame_enter_usec: int = Time.get_ticks_usec()
	if _has_pending_frame:
		_finalize_pending_frame(frame_enter_usec)

	var prev_chunk_count: int = map.streamer._loaded_chunks.size()
	var prev_nav_center: Vector2i = map.nav_window._center_cell
	var prev_rooms_count: int = map.companion_rooms.size()
	var prev_enemies_count: int = game._enemies.size()
	var prev_pending_count: int = game._pending_spawns.size()

	var t0: int = Time.get_ticks_usec()
	_step_streaming_and_spikes(game, map, delta)
	var t1: int = Time.get_ticks_usec()
	game._update_squad_speed(delta)
	game._update_followers(delta)
	var t2: int = Time.get_ticks_usec()
	game._update_enemies()
	var t3: int = Time.get_ticks_usec()
	game._check_recruitment()
	game._process_pending_spawns()
	var t4: int = Time.get_ticks_usec()
	game._update_spike_hazards(delta)
	var t5: int = Time.get_ticks_usec()

	var chunk_stats: Vector2i = _diff_chunks(map, prev_chunk_count)
	var nav_recentered: bool = map.nav_window._center_cell != prev_nav_center
	var rooms_discovered: int = map.companion_rooms.size() - prev_rooms_count
	var spawns_delta: int = maxi(0, prev_pending_count - game._pending_spawns.size())
	var enemies_delta: int = game._enemies.size() - prev_enemies_count
	var counts: Dictionary = _sample_entity_counts(game, map)

	_pending_start_usec = frame_enter_usec
	_last_balance_usec = 0
	_pending_frame = {
		&"seed": seed_val,
		&"frame": sim_frame,
		&"depth": counts[&"depth"],
		&"squad": counts[&"squad"],
		&"enemies": game._enemies.size(),
		&"awake_enemies": counts[&"awake_enemies"],
		&"awake_offscreen": counts[&"awake_offscreen"],
		&"projectiles": counts[&"projectiles"],
		&"pending_spawns": game._pending_spawns.size(),
		&"queued_chunks": map.streamer._load_queue.size(),
		&"chunks_loaded": chunk_stats.x,
		&"chunks_evicted": chunk_stats.y,
		&"nav_recentered": nav_recentered,
		&"rooms_discovered": rooms_discovered,
		&"spawns_processed": spawns_delta,
		&"enemies_delta": enemies_delta,
		&"streaming_ms": float(t1 - t0) / 1000.0,
		&"squad_ms": float(t2 - t1) / 1000.0,
		&"enemies_ms": float(t3 - t2) / 1000.0,
		&"spawns_ms": float(t4 - t3) / 1000.0,
		&"hazards_ms": float(t5 - t4) / 1000.0,
		&"bot_ms": float(bot_usec) / 1000.0,
		&"game_step_ms": float(t5 - t0) / 1000.0,
	}
	_has_pending_frame = true


func _step_streaming_and_spikes(game: Game, map: Map, delta: float) -> void:
	game._camera.position = game._character.position
	if not game._character.is_dead:
		if game._character.is_moving:
			game._hud.dismiss_movement_hint()
			game._check_room_entry()
		game._character.record_step(delta)
		game._stream_timer -= delta
		if game._stream_timer <= 0.0:
			game._stream_timer = Game.STREAM_CHECK_INTERVAL
			game._update_map_streaming()
		map.update_streaming(game._character.global_position, game._character.velocity)
	map.update_spikes(delta)


func _diff_chunks(map: Map, prev_count: int) -> Vector2i:
	var curr_chunks: Dictionary[Vector2i, Dictionary] = map.streamer._loaded_chunks
	if curr_chunks.size() == prev_count and _prev_loaded_chunks.size() == prev_count:
		var any_change: bool = false
		for coord: Vector2i in curr_chunks:
			if not _prev_loaded_chunks.has(coord):
				any_change = true
				break
		if not any_change:
			return Vector2i.ZERO

	var loaded: int = 0
	var evicted: int = 0
	for coord: Vector2i in curr_chunks:
		if not _prev_loaded_chunks.has(coord):
			loaded += 1
	for coord: Vector2i in _prev_loaded_chunks:
		if not curr_chunks.has(coord):
			evicted += 1

	_prev_loaded_chunks.clear()
	for coord: Vector2i in curr_chunks:
		_prev_loaded_chunks[coord] = true
	return Vector2i(loaded, evicted)


func _sample_entity_counts(game: Game, map: Map) -> Dictionary:
	var awake: int = 0
	var awake_offscreen: int = 0
	for enemy: Enemy in game._enemies:
		if is_instance_valid(enemy) and not enemy.is_dead and enemy.is_physics_processing():
			awake += 1
			if not enemy.is_on_screen:
				awake_offscreen += 1

	var projectiles: int = 0
	for child: Node in game._projectiles.get_children():
		var proj: Node2D = child as Node2D
		if proj != null and proj.visible:
			projectiles += 1

	var depth: int = 0
	if is_instance_valid(game._character):
		var cell: Vector2i = map.local_to_map(game._character.global_position)
		var room: Rect2i = map.plan.get_room_at(cell)
		if room != Rect2i():
			depth = map.get_room_depth(room)

	return {
		&"depth": depth,
		&"squad": game._squad.size(),
		&"awake_enemies": awake,
		&"awake_offscreen": awake_offscreen,
		&"projectiles": projectiles,
	}


func _finalize_pending_frame(next_enter_usec: int) -> void:
	_has_pending_frame = false
	var process_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var wall_ms: float = float(maxi(0, next_enter_usec - _pending_start_usec)) / 1000.0
	var balance_ms: float = float(_last_balance_usec) / 1000.0
	var game_step_ms: float = _pending_frame[&"game_step_ms"]
	var cpu_ms: float = maxf(game_step_ms, wall_ms - balance_ms)
	if DisplayServer.get_name() != "headless":
		cpu_ms = process_ms + physics_ms
	var other_ms: float = maxf(0.0, cpu_ms - game_step_ms)
	var collision_pairs: int = int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS))
	var active_physics: int = int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS))
	var node_count: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

	_pending_frame[&"process_ms"] = process_ms
	_pending_frame[&"physics_ms"] = physics_ms
	_pending_frame[&"cpu_ms"] = cpu_ms
	_pending_frame[&"other_ms"] = other_ms
	_pending_frame[&"wall_ms"] = wall_ms
	_pending_frame[&"collision_pairs"] = collision_pairs
	_pending_frame[&"active_physics"] = active_physics
	_pending_frame[&"node_count"] = node_count

	_accumulate_sample(_pending_frame)


func _accumulate_sample(rec: Dictionary) -> void:
	_total_frames += 1
	var cpu_ms: float = rec[&"cpu_ms"]
	var other_ms: float = rec[&"other_ms"]
	var stream_ms: float = rec[&"streaming_ms"]
	_cpu_ms_samples.append(cpu_ms)
	_other_ms_samples.append(other_ms)
	_process_ms_samples.append(rec[&"process_ms"])
	_physics_ms_samples.append(rec[&"physics_ms"])
	_wall_ms_samples.append(rec[&"wall_ms"])
	_streaming_ms_samples.append(stream_ms)
	_squad_ms_samples.append(rec[&"squad_ms"])
	_enemies_ms_samples.append(rec[&"enemies_ms"])
	_spawns_ms_samples.append(rec[&"spawns_ms"])
	_hazards_ms_samples.append(rec[&"hazards_ms"])
	_bot_ms_samples.append(rec[&"bot_ms"])

	if cpu_ms > SPIKE_WARN_MS:
		_spikes_over_8ms += 1
	if cpu_ms > FRAME_BUDGET_MS:
		_spikes_over_16ms += 1

	var chunks_loaded: int = rec[&"chunks_loaded"]
	var chunks_evicted: int = rec[&"chunks_evicted"]
	var squad_count: int = rec[&"squad"]
	var awake_enemies: int = rec[&"awake_enemies"]
	var awake_offscreen: int = rec[&"awake_offscreen"]
	var projectiles: int = rec[&"projectiles"]
	var collision_pairs: int = rec[&"collision_pairs"]
	var node_count: int = rec[&"node_count"]

	if rec[&"nav_recentered"]:
		_nav_recenter_count += 1
		_nav_recenter_stream_ms.append(stream_ms)
	if chunks_loaded > 0:
		_chunk_load_count += chunks_loaded
		_chunk_load_stream_ms.append(stream_ms)
	if chunks_evicted > 0:
		_chunk_evict_count += chunks_evicted
		_chunk_evict_stream_ms.append(stream_ms)

	_max_squad_seen = maxi(_max_squad_seen, squad_count)
	_max_awake_enemies_seen = maxi(_max_awake_enemies_seen, awake_enemies)
	_max_awake_offscreen_seen = maxi(_max_awake_offscreen_seen, awake_offscreen)
	_max_projectiles_seen = maxi(_max_projectiles_seen, projectiles)
	_max_collision_pairs_seen = maxi(_max_collision_pairs_seen, collision_pairs)
	_max_nodes_seen = maxi(_max_nodes_seen, node_count)

	_record_top_spike(rec)


func _record_top_spike(rec: Dictionary) -> void:
	var rec_cpu: float = rec[&"cpu_ms"]
	if _top_spikes.size() >= TOP_SPIKE_COUNT:
		var last_cpu: float = _top_spikes[_top_spikes.size() - 1][&"cpu_ms"]
		if rec_cpu <= last_cpu:
			return
	_top_spikes.append(rec.duplicate())
	_top_spikes.sort_custom(_compare_spike_desc)
	if _top_spikes.size() > TOP_SPIKE_COUNT:
		_top_spikes.resize(TOP_SPIKE_COUNT)


static func _compare_spike_desc(a: Dictionary, b: Dictionary) -> bool:
	var cpu_a: float = a[&"cpu_ms"]
	var cpu_b: float = b[&"cpu_ms"]
	return cpu_a > cpu_b


func build_report_dict() -> Dictionary:
	var cpu_sorted: Array[float] = _cpu_ms_samples.duplicate()
	cpu_sorted.sort()
	return {
		&"total_frames": _total_frames,
		&"cpu_avg_ms": _avg(_cpu_ms_samples),
		&"cpu_p50_ms": _pct(cpu_sorted, 0.50),
		&"cpu_p95_ms": _pct(cpu_sorted, 0.95),
		&"cpu_p99_ms": _pct(cpu_sorted, 0.99),
		&"cpu_max_ms": _max_val(cpu_sorted),
		&"spikes_over_8ms": _spikes_over_8ms,
		&"spikes_over_16ms": _spikes_over_16ms,
		&"subsystems":
		{
			&"process": _stats_dict(_process_ms_samples),
			&"physics": _stats_dict(_physics_ms_samples),
			&"wall": _stats_dict(_wall_ms_samples),
			&"streaming": _stats_dict(_streaming_ms_samples),
			&"squad": _stats_dict(_squad_ms_samples),
			&"enemies": _stats_dict(_enemies_ms_samples),
			&"spawns": _stats_dict(_spawns_ms_samples),
			&"hazards": _stats_dict(_hazards_ms_samples),
			&"other_engine": _stats_dict(_other_ms_samples),
			&"bot_overhead": _stats_dict(_bot_ms_samples),
		},
		&"triggers":
		{
			&"nav_recenters": _nav_recenter_count,
			&"nav_recenter_stream": _stats_dict(_nav_recenter_stream_ms),
			&"chunks_loaded": _chunk_load_count,
			&"chunk_load_stream": _stats_dict(_chunk_load_stream_ms),
			&"chunks_evicted": _chunk_evict_count,
			&"chunk_evict_stream": _stats_dict(_chunk_evict_stream_ms),
		},
		&"peaks":
		{
			&"squad": _max_squad_seen,
			&"awake_enemies": _max_awake_enemies_seen,
			&"awake_offscreen": _max_awake_offscreen_seen,
			&"projectiles": _max_projectiles_seen,
			&"collision_pairs": _max_collision_pairs_seen,
			&"node_count": _max_nodes_seen,
		},
		&"top_spikes": _top_spikes,
	}


func print_report() -> void:
	var r: Dictionary = build_report_dict()
	var subs: Dictionary = r[&"subsystems"]
	var trigs: Dictionary = r[&"triggers"]
	var peaks: Dictionary = r[&"peaks"]

	print(&"\n================ AUTOPLAY PERFORMANCE REPORT ================")
	print(&"Frames Sampled:         %d" % _total_frames)
	print(
		(
			&"Frame CPU Time (ms):    avg=%.2f  p50=%.2f  p95=%.2f  p99=%.2f  max=%.2f"
			% [r[&"cpu_avg_ms"], r[&"cpu_p50_ms"], r[&"cpu_p95_ms"], r[&"cpu_p99_ms"], r[&"cpu_max_ms"]]
		)
	)
	print(&"CPU Spikes >8ms / >16.7ms: %d / %d" % [_spikes_over_8ms, _spikes_over_16ms])
	print(&"-------------------------------------------------------------")
	print(&"SUBSYSTEM TIMINGS (ms)          avg     p95     p99     max")
	_print_sub_row(&"Wall Frame (total)", subs, &"wall")
	_print_sub_row(&"  Game.streaming", subs, &"streaming")
	_print_sub_row(&"  Game.squad", subs, &"squad")
	_print_sub_row(&"  Game.enemies", subs, &"enemies")
	_print_sub_row(&"  Game.spawns", subs, &"spawns")
	_print_sub_row(&"  Game.hazards", subs, &"hazards")
	_print_sub_row(&"  Other Engine (H/E/P2D)", subs, &"other_engine")
	_print_sub_row(&"  Bot.update (test only)", subs, &"bot_overhead")
	_print_sub_row(&"Monitor _process (1s)", subs, &"process")
	_print_sub_row(&"Monitor _physics (1s)", subs, &"physics")
	print(&"-------------------------------------------------------------")
	print(&"STREAMING & NAV TRIGGERS:")
	var nav_s: Dictionary = trigs[&"nav_recenter_stream"]
	var load_s: Dictionary = trigs[&"chunk_load_stream"]
	var evict_s: Dictionary = trigs[&"chunk_evict_stream"]
	print(&"  NavWindow Recenters:  %d (stream avg=%.2fms max=%.2fms)" % [_nav_recenter_count, nav_s[&"avg"], nav_s[&"max"]])
	print(&"  Chunks Loaded:        %d (stream avg=%.2fms max=%.2fms)" % [_chunk_load_count, load_s[&"avg"], load_s[&"max"]])
	print(&"  Chunks Evicted:       %d (stream avg=%.2fms max=%.2fms)" % [_chunk_evict_count, evict_s[&"avg"], evict_s[&"max"]])
	print(
		(
			&"Peaks: squad=%d | awake_enemies=%d (offscreen=%d) | proj=%d | pairs=%d | nodes=%d"
			% [
				peaks[&"squad"],
				peaks[&"awake_enemies"],
				peaks[&"awake_offscreen"],
				peaks[&"projectiles"],
				peaks[&"collision_pairs"],
				peaks[&"node_count"]
			]
		)
	)
	print(&"-------------------------------------------------------------")
	print(&"TOP %d SLOWEST CPU FRAMES:" % _top_spikes.size())
	for rec: Dictionary in _top_spikes:
		var p1: String = (
			&"  [S%d F%05d D%d] cpu=%.2fms (step=%.2f other=%.2f)"
			% [rec[&"seed"], rec[&"frame"], rec[&"depth"], rec[&"cpu_ms"], rec[&"game_step_ms"], rec[&"other_ms"]]
		)
		var p2: String = (
			&" | str=%.2f sq=%.2f en=%.2f sp=%.2f | unit=%d/%d(%d awk,%d off) proj=%d pairs=%d"
			% [
				rec[&"streaming_ms"],
				rec[&"squad_ms"],
				rec[&"enemies_ms"],
				rec[&"spawns_ms"],
				rec[&"squad"],
				rec[&"enemies"],
				rec[&"awake_enemies"],
				rec[&"awake_offscreen"],
				rec[&"projectiles"],
				rec[&"collision_pairs"],
			]
		)
		var p3: String = (
			&" | load=%d evict=%d nav=%s spawn=%d"
			% [rec[&"chunks_loaded"], rec[&"chunks_evicted"], str(rec[&"nav_recentered"]), rec[&"spawns_processed"]]
		)
		print(p1 + p2 + p3)
	print(&"=============================================================\n")


static func _print_sub_row(label: StringName, subs: Dictionary, key: StringName) -> void:
	var s: Dictionary = subs[key]
	print(&"  %-24s %6.2f  %6.2f  %6.2f  %6.2f" % [String(label), s[&"avg"], s[&"p95"], s[&"p99"], s[&"max"]])


static func _stats_dict(values: Array[float]) -> Dictionary:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return {
		&"avg": _avg(values),
		&"p95": _pct(sorted, 0.95),
		&"p99": _pct(sorted, 0.99),
		&"max": _max_val(sorted),
	}


static func _avg(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for v: float in values:
		total += v
	return total / float(values.size())


static func _pct(sorted_values: Array[float], pct: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var idx: int = clampi(int(float(sorted_values.size()) * pct), 0, sorted_values.size() - 1)
	return sorted_values[idx]


static func _max_val(sorted_values: Array[float]) -> float:
	if sorted_values.is_empty():
		return 0.0
	return sorted_values[sorted_values.size() - 1]
