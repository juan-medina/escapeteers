# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Benchmark
extends Node2D

const BENCHMARK_FRAMES: int = 300
const BENCHMARK_SEED: int = 12345
const PLAYER_SPEED: float = 180.0
const GAME_SCENE: PackedScene = preload("res://game/game.tscn")

var _game: Game = null
var _character: Hero = null
var _frame_count: int = 0
var _frame_times: Array[float] = []
var _max_spike_ms: float = 0.0


func _ready() -> void:
	set_process(false)
	print(&"=== STARTING BENCHMARK MODE (%d frames, Seed %d) ===" % [BENCHMARK_FRAMES, BENCHMARK_SEED])
	_game = GAME_SCENE.instantiate() as Game
	var map: Map = _game.get_node_or_null(^"Map") as Map
	if map != null:
		map.debug_seed = BENCHMARK_SEED
	add_child(_game)

	while is_instance_valid(_game) and not _game.is_processing():
		await get_tree().process_frame

	_character = _game.get_node_or_null(^"Characters/Character") as Hero
	if is_instance_valid(_character):
		_character.max_health = 999999.0
		_character.health = 999999.0

	set_process(true)


func _process(delta: float) -> void:
	if _game == null:
		return

	if is_instance_valid(_character):
		_character.position.x += PLAYER_SPEED * delta

	_frame_count += 1
	var delta_ms: float = delta * 1000.0
	_frame_times.append(delta_ms)
	if delta_ms > _max_spike_ms:
		_max_spike_ms = delta_ms

	if _frame_count >= BENCHMARK_FRAMES:
		_finish_benchmark()
		get_tree().quit(0)


func _finish_benchmark() -> void:
	_frame_times.sort()
	var n: int = _frame_times.size()
	var sum: float = 0.0
	var spikes_16ms: int = 0
	var spikes_33ms: int = 0
	for t: float in _frame_times:
		sum += t
		if t > 16.67:
			spikes_16ms += 1
		if t > 33.33:
			spikes_33ms += 1
	var avg: float = sum / float(n) if n > 0 else 0.0
	var p50: float = _frame_times[int(float(n) * 0.50)] if n > 0 else 0.0
	var p95: float = _frame_times[int(float(n) * 0.95)] if n > 0 else 0.0
	var p99: float = _frame_times[int(float(n) * 0.99)] if n > 0 else 0.0

	@warning_ignore("unsafe_call_argument")
	var active_enemies: int = int(Performance.get_custom_monitor(&"streaming/active_enemies"))
	@warning_ignore("unsafe_call_argument")
	var active_lights: int = int(Performance.get_custom_monitor(&"streaming/active_lights"))

	print(&"\n================ BENCHMARK BASELINE REPORT ================")
	print(&"Total Frames Sampled: %d" % n)
	print(&"Average Frame Time:   %.2f ms (%.1f FPS)" % [avg, 1000.0 / avg if avg > 0.0 else 0.0])
	print(&"50th Percentile (p50): %.2f ms" % p50)
	print(&"95th Percentile (p95): %.2f ms" % p95)
	print(&"99th Percentile (p99): %.2f ms" % p99)
	print(&"Max Frame Spike:      %.2f ms" % _max_spike_ms)
	print(&"Frames > 16.7ms:       %d (%.1f%%)" % [spikes_16ms, (float(spikes_16ms) / float(n)) * 100.0])
	print(&"Frames > 33.3ms:       %d (%.1f%%)" % [spikes_33ms, (float(spikes_33ms) / float(n)) * 100.0])
	print(&"Active Enemies:       %d" % active_enemies)
	print(&"Active Lights:        %d" % active_lights)
	print(&"Static Memory:        %.2f MB" % [float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0)])
	print(&"===========================================================\n")
