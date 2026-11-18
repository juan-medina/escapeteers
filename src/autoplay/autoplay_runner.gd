# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name AutoplayRunner
extends Node

enum RunState {
	IDLE,
	LOADING,
	RUNNING,
	CLEANUP,
}

const GAME_SCENE: PackedScene = preload("res://game/game.tscn")
const MATRIX_HEROES: Array[String] = [
	"archer",
	"armored_axeman",
	"knight",
	"knight_templar",
	"priest",
	"soldier",
	"swordsman",
	"wizard",
]

var _mode: String = "perf"
var _seeds_count: int = 3
var _base_seed: int = 12345
var _leader_id: String = "knight"
var _build_policy: String = "balanced"
var _max_depth: int = 12
var _max_frames: int = 3600
var _speed: float = 1.0
var _immortal: bool = true
var _out_path: String = ""
var _profile_enabled: bool = true

var _state: RunState = RunState.IDLE
var _run_queue: Array[Dictionary] = []
var _run_index: int = 0
var _total_runs: int = 0
var _current_run_cfg: Dictionary = {}
var _game: Game = null
var _map: Map = null
var _sim_frame: int = 0
var _cleanup_frames: int = 0
var _is_shutting_down: bool = false

var _bot: AutoplayBot = AutoplayBot.new()
var _profiler: AutoplayProfiler = AutoplayProfiler.new()
var _balance: AutoplayBalance = AutoplayBalance.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1
	_parse_args()
	_build_run_queue()
	_profiler.reset_session()
	_balance.reset_session()
	print(
		(
			&"[Autoplay] mode=%s runs=%d base_seed=%d max_depth=%d max_frames=%d speed=%.1fx immortal=%s"
			% [_mode, _total_runs, _base_seed, _max_depth, _max_frames, _speed, str(_immortal)]
		)
	)
	_start_next_run()


func _process(delta: float) -> void:
	if _is_shutting_down:
		return

	match _state:
		RunState.LOADING:
			_tick_loading()
		RunState.RUNNING:
			_tick_running(delta)
		RunState.CLEANUP:
			_tick_cleanup()


func _parse_args() -> void:
	var args: Dictionary[String, String] = {}
	for raw: String in OS.get_cmdline_user_args():
		if not raw.begins_with("--"):
			continue
		var eq_idx: int = raw.find("=")
		if eq_idx == -1:
			args[raw.substr(2)] = "true"
		else:
			args[raw.substr(2, eq_idx - 2)] = raw.substr(eq_idx + 1)

	_mode = _get_arg(args, "mode", "perf").to_lower()
	_base_seed = int(_get_arg(args, "seed", "12345"))
	_leader_id = _get_arg(args, "leader", "knight")
	_build_policy = _get_arg(args, "build", "balanced")
	_max_depth = maxi(1, int(_get_arg(args, "max_depth", "12")))
	_out_path = _get_arg(args, "out", "")

	var default_seeds: int = 3 if _mode == "perf" else (1 if _mode == "watch" else 10)
	_seeds_count = maxi(1, int(_get_arg(args, "seeds", str(default_seeds))))

	var default_frames: int = 9000 if _mode == "perf" else (0 if _mode == "watch" else 18000)
	_max_frames = int(_get_arg(args, "max_frames", str(default_frames)))

	var default_speed: float = 2.0 if _mode == "watch" else 1.0
	_speed = maxf(0.1, float(_get_arg(args, "speed", str(default_speed))))

	var default_immortal: String = "true" if _mode == "perf" else "false"
	_immortal = _get_arg(args, "immortal", default_immortal).to_lower() == "true"
	_profile_enabled = _mode == "perf" or _mode == "watch"


static func _get_arg(args: Dictionary[String, String], key: String, fallback: String) -> String:
	if args.has(key):
		return args[key]
	return fallback


func _build_run_queue() -> void:
	_run_queue.clear()
	if _mode == "matrix":
		var configs: Array[Dictionary] = [
			{&"leader": "knight", &"build": "balanced"},
			{&"leader": "knight", &"build": "melee_stack"},
			{&"leader": "archer", &"build": "ranged_kite"},
			{&"leader": "knight", &"build": "random"},
		]
		for hero_id: String in MATRIX_HEROES:
			configs.append({&"leader": hero_id, &"build": "mono:" + hero_id})

		for cfg: Dictionary in configs:
			for i: int in range(_seeds_count):
				(
					_run_queue
					. append(
						{
							&"seed": _base_seed + i,
							&"leader": cfg[&"leader"],
							&"build": cfg[&"build"],
						}
					)
				)
	else:
		for i: int in range(_seeds_count):
			(
				_run_queue
				. append(
					{
						&"seed": _base_seed + i,
						&"leader": _leader_id,
						&"build": _build_policy,
					}
				)
			)

	_total_runs = _run_queue.size()
	_run_index = 0


func _start_next_run() -> void:
	if _run_queue.is_empty():
		_finish_session()
		return

	_current_run_cfg = _run_queue.pop_front()
	_run_index += 1
	var run_seed: int = _current_run_cfg[&"seed"]
	var leader: String = _current_run_cfg[&"leader"]

	get_tree().paused = false
	Transition.starting_hero_id = StringName(leader)
	Engine.time_scale = _speed
	Engine.max_physics_steps_per_frame = maxi(8, ceili(_speed * 8.0)) if _speed > 1.0 else 8

	_game = GAME_SCENE.instantiate() as Game
	var plan: AutoplayPlan = AutoplayPlan.new()
	plan.forced_seed = run_seed
	plan.forced_max_depth = _max_depth
	var map_node: Map = _game.get_node(^"Map") as Map
	map_node.plan = plan

	seed(run_seed)
	add_child(_game)
	_state = RunState.LOADING


func _tick_loading() -> void:
	if not is_instance_valid(_game) or not _game.is_processing():
		return

	_map = _game._map
	var run_seed: int = _current_run_cfg[&"seed"]
	var leader: String = _current_run_cfg[&"leader"]
	var build: String = _current_run_cfg[&"build"]

	_bot.setup(_map, build, _max_depth)
	_balance.begin_run(_game, _map, run_seed, StringName(leader), build)

	if _profile_enabled:
		_game.set_process(false)
		_profiler.begin_run(_map)

	_sim_frame = 0
	_state = RunState.RUNNING


func _tick_running(delta: float) -> void:
	if _profile_enabled:
		_profiler.on_tick_start()

	if not is_instance_valid(_game) or _map == null or not is_instance_valid(_game._character):
		_finish_current_run("invalid_state")
		return

	if _immortal and not _game._character.is_dead:
		var floor_hp: float = _game._character.max_health * 0.65
		if _game._character.health < floor_hp:
			_game._character.health = floor_hp

	if _game._character.is_dead or _game._game_over_dialog.visible:
		_finish_current_run("leader_dead")
		return

	if _mode != "perf" and _mode != "watch" and _bot.has_won:
		_finish_current_run("won")
		return

	if _max_frames > 0 and _sim_frame >= _max_frames:
		_finish_current_run("frame_limit")
		return

	var bot_t0: int = Time.get_ticks_usec()
	_bot.update(_game, _map, delta)
	var bot_usec: int = Time.get_ticks_usec() - bot_t0

	if not get_tree().paused:
		_sim_frame += 1
		var run_seed: int = _current_run_cfg[&"seed"]
		if _profile_enabled:
			_profiler.step_game_frame(_game, _map, delta, _sim_frame, run_seed, bot_usec)
		var bal_t0: int = Time.get_ticks_usec()
		_balance.update(_game, _map, delta)
		var bal_usec: int = Time.get_ticks_usec() - bal_t0
		if _profile_enabled:
			_profiler.record_balance_overhead(bal_usec)


func _finish_current_run(reason: String) -> void:
	_bot.release_movement()
	if _profile_enabled:
		_profiler.flush_pending_frame()

	var summary: Dictionary = {}
	if is_instance_valid(_game) and _map != null:
		summary = _balance.finish_run(_bot, _game, _map)

	if not summary.is_empty():
		print(
			(
				&"[Autoplay %d/%d] seed=%d %s|%s -> depth=%d cleared=%d squad=%d lv=%d time=%.1fs reason=%s"
				% [
					_run_index,
					_total_runs,
					summary[&"seed"],
					summary[&"leader"],
					summary[&"build"],
					summary[&"max_depth"],
					summary[&"rooms_cleared"],
					summary[&"final_squad_size"],
					summary[&"squad_level"],
					summary[&"duration_sec"],
					reason,
				]
			)
		)

	if is_instance_valid(_game):
		_game.queue_free()
	_game = null
	_map = null
	get_tree().paused = false
	_cleanup_frames = 2
	_state = RunState.CLEANUP


func _tick_cleanup() -> void:
	_cleanup_frames -= 1
	if _cleanup_frames > 0:
		return
	_state = RunState.IDLE
	_start_next_run()


func _finish_session() -> void:
	_is_shutting_down = true
	set_process(false)
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8
	get_tree().paused = false
	_bot.release_movement()

	if _profile_enabled:
		_profiler.print_report()
	if _mode == "balance" or _mode == "matrix" or _mode == "watch":
		_balance.print_balance_report("AUTOPLAY %s REPORT" % _mode.to_upper())

	if _out_path != "":
		_write_json_report()

	_shutdown.call_deferred()


func _write_json_report() -> void:
	var payload: Dictionary = {
		&"mode": _mode,
		&"runs": _total_runs,
		&"balance": _balance.build_report_dict(),
	}
	if _profile_enabled:
		payload[&"performance"] = _profiler.build_report_dict()

	var file: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
	if file == null:
		printerr(&"Failed to write autoplay JSON report to: " + _out_path)
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	print(&"[Autoplay] JSON report saved to: %s" % _out_path)


func _shutdown() -> void:
	await Alerts.quit_game()
