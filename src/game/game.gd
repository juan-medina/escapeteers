# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Game
extends Node2D

const MAX_CHARACTERS: int = 80
const MAX_ENEMIES: int = 160
const ENEMY_ACTIVE_DIST_SQ: float = 480.0 * 480.0
const ENEMY_DESPAWN_DIST_SQ: float = 1650.0 * 1650.0
const ROOM_RESPAWN_DIST_SQ: float = 1350.0 * 1350.0
const STREAM_CHECK_INTERVAL: float = 0.25

const ARCHER_SCENE: PackedScene = preload("res://character/heroes/archer/archer.tscn")
const ARMORED_AXEMAN_SCENE: PackedScene = preload("res://character/heroes/armored_axeman/armored_axeman.tscn")
const KNIGHT_SCENE: PackedScene = preload("res://character/heroes/knight/knight.tscn")
const KNIGHT_TEMPLAR_SCENE: PackedScene = preload("res://character/heroes/knight_templar/knight_templar.tscn")
const PRIEST_SCENE: PackedScene = preload("res://character/heroes/priest/priest.tscn")
const SOLDIER_SCENE: PackedScene = preload("res://character/heroes/soldier/soldier.tscn")
const SWORDSMAN_SCENE: PackedScene = preload("res://character/heroes/swordsman/swordsman.tscn")
const WIZARD_SCENE: PackedScene = preload("res://character/heroes/wizard/wizard.tscn")
const LAVA_SLIME_SCENE: PackedScene = preload("res://character/enemies/lava_slime/lava_slime.tscn")
const GAME_OVER_DIALOG_SCENE: PackedScene = preload("res://game_over_dialog/game_over_dialog.tscn")

const HERO_SPAWN_WEIGHTS: Dictionary[PackedScene, int] = {
	ARMORED_AXEMAN_SCENE: 5,
	KNIGHT_SCENE: 3,
	KNIGHT_TEMPLAR_SCENE: 2,
	SWORDSMAN_SCENE: 2,
	WIZARD_SCENE: 1,
	ARCHER_SCENE: 1,
	SOLDIER_SCENE: 1,
	PRIEST_SCENE: 1,
}

var _squad: Array[Hero] = []
var _unrecruited_characters: Array[Hero] = []
var _enemies: Array[Enemy] = []
var _hero_deck: Array[PackedScene] = []
var _room_remaining_enemies: Dictionary[Rect2i, int] = {}
var _room_spawned_enemies: Dictionary[Rect2i, int] = {}
var _stream_timer: float = 0.0
var _frame_spike_count: int = 0
var _is_benchmarking: bool = false
var _benchmark_frame_count: int = 0
var _benchmark_frame_times: Array[float] = []
var _benchmark_max_spike_ms: float = 0.0

@onready var _camera: Camera2D = $Camera2D
@onready var _characters: Node2D = $Characters
@onready var _character: Hero = $Characters/Character as Hero
@onready var _map: Map = $Map
@onready var _projectiles: Node2D = $Projectiles


func _ready() -> void:
	# Workaround for Godot 4 Camera2D not re-centering after the window resizes.
	get_tree().root.size_changed.connect(_on_window_resized)
	process_priority = 1
	y_sort_enabled = true
	set_process(false)

	_map.generation_progress_updated.connect(_on_map_generation_progress)
	await _map.generate_map()

	_character.position = _map.get_hero_spawn_position()
	_camera.position = _character.position
	_character.y_sort_enabled = true
	_character.is_player = true
	_character.record_step(0.0)
	_character.projectile_spawn_requested.connect(_on_projectile_spawn_requested)
	_character.death_completed.connect(_on_player_death_completed)
	_squad.append(_character)

	Transition.set_loading_progress(0.92, &"Assembling the fellowship...")
	await get_tree().process_frame
	_spawn_initial_characters()
	_check_recruitment()
	_register_and_populate_rooms(_map.companion_rooms)

	Transition.set_loading_progress(1.0, &"Ready to escape!")
	await get_tree().process_frame
	set_process(true)
	await Transition.hide_loading()

	if not Performance.has_custom_monitor(&"streaming/frame_spikes"):
		Performance.add_custom_monitor(&"streaming/frame_spikes", _get_monitor_frame_spikes)
	if not Performance.has_custom_monitor(&"streaming/active_enemies"):
		Performance.add_custom_monitor(&"streaming/active_enemies", _get_monitor_active_enemies)
	if not Performance.has_custom_monitor(&"streaming/active_lights"):
		Performance.add_custom_monitor(&"streaming/active_lights", _get_monitor_active_lights)

	if "--benchmark" in OS.get_cmdline_args() or "--benchmark" in OS.get_cmdline_user_args():
		_is_benchmarking = true
		_map.debug_seed = 12345
		process_mode = Node.PROCESS_MODE_ALWAYS
		if is_instance_valid(_character):
			_character.max_health = 999999.0
			_character.health = 999999.0
		print(&"=== STARTING BENCHMARK MODE (300 frames, Seed 12345) ===")


func _exit_tree() -> void:
	if Performance.has_custom_monitor(&"streaming/frame_spikes"):
		Performance.remove_custom_monitor(&"streaming/frame_spikes")
	if Performance.has_custom_monitor(&"streaming/active_enemies"):
		Performance.remove_custom_monitor(&"streaming/active_enemies")
	if Performance.has_custom_monitor(&"streaming/active_lights"):
		Performance.remove_custom_monitor(&"streaming/active_lights")


func _get_monitor_frame_spikes() -> int:
	return _frame_spike_count


func _get_monitor_active_enemies() -> int:
	return _enemies.size()


func _get_monitor_active_lights() -> int:
	return _map.get_active_light_count()


func _on_map_generation_progress(progress: float, stage_name: StringName) -> void:
	Transition.set_loading_progress(progress, stage_name)


func _process(delta: float) -> void:
	if delta > 0.0167:
		_frame_spike_count += 1
		if delta > 0.0333:
			print(&"[Perf] Frame spike: %.2f ms" % [delta * 1000.0])

	if _is_benchmarking:
		if is_instance_valid(_character):
			_character.position.x += 180.0 * delta
		_benchmark_frame_count += 1
		var delta_ms: float = delta * 1000.0
		_benchmark_frame_times.append(delta_ms)
		if delta_ms > _benchmark_max_spike_ms:
			_benchmark_max_spike_ms = delta_ms
		if _benchmark_frame_count >= 300:
			_finish_benchmark()
			get_tree().quit(0)
			return

	if is_instance_valid(_character):
		_camera.position = _character.position
		if not _character.is_dead:
			_character.record_step(delta)
			_stream_timer -= delta
			if _stream_timer <= 0.0:
				_stream_timer = STREAM_CHECK_INTERVAL
				_update_map_streaming()

	_update_followers(delta)
	_check_recruitment()
	_update_enemies()


func remove_member(hero: Hero) -> void:
	var idx: int = _squad.find(hero)
	if idx == -1 or hero == _character:
		return

	_squad.remove_at(idx)
	hero.queue_free()
	_rebalance_escort_slots()


func _update_map_streaming() -> void:
	var start_usec: int = Time.get_ticks_usec()
	var new_rooms: Array[Rect2i] = _map.expand_frontier_near(_character.global_position)
	if not new_rooms.is_empty():
		for room: Rect2i in new_rooms:
			_spawn_companions_for_room(room)
		_register_and_populate_rooms(new_rooms)

	_respawn_nearby_hibernating_rooms()
	var elapsed_ms: float = float(Time.get_ticks_usec() - start_usec) / 1000.0
	if elapsed_ms >= 2.0:
		print(&"[Perf] _update_map_streaming took %.2f ms (new_rooms: %d)" % [elapsed_ms, new_rooms.size()])


func _spawn_initial_characters() -> void:
	var starter_positions: Array[Vector2] = _map.get_starter_companion_spawn_positions()
	var starter_heroes: Array[PackedScene] = [PRIEST_SCENE, ARMORED_AXEMAN_SCENE]

	for i: int in range(starter_positions.size()):
		var scene: PackedScene = starter_heroes[i] if i < starter_heroes.size() else _draw_next_hero_scene()
		_spawn_recruit_at(starter_positions[i], scene)

	for room: Rect2i in _map.companion_rooms:
		_spawn_companions_for_room(room)


func _spawn_companions_for_room(room: Rect2i) -> void:
	if MAX_CHARACTERS > 0 and (_squad.size() + _unrecruited_characters.size()) >= MAX_CHARACTERS:
		return

	var positions: Array[Vector2] = _map.get_companion_spawn_positions_for_room(room)
	for pos: Vector2 in positions:
		if MAX_CHARACTERS > 0 and (_squad.size() + _unrecruited_characters.size()) >= MAX_CHARACTERS:
			break
		_spawn_recruit_at(pos, _draw_next_hero_scene())


func _draw_next_hero_scene() -> PackedScene:
	if _hero_deck.is_empty():
		_hero_deck = _build_hero_deck()
		_hero_deck.shuffle()
	return _hero_deck.pop_back()


func _spawn_recruit_at(pos: Vector2, scene: PackedScene) -> void:
	var ch: Hero = scene.instantiate() as Hero
	_characters.add_child(ch)
	ch.is_player = false
	ch.position = pos
	ch.y_sort_enabled = true
	ch.flip_h = randf() > 0.5
	ch.frame = randi() % 6
	ch.frame_progress = randf()
	ch.projectile_spawn_requested.connect(_on_projectile_spawn_requested)
	ch.died.connect(_on_hero_died.bind(ch))
	_unrecruited_characters.append(ch)


func _build_hero_deck() -> Array[PackedScene]:
	var deck: Array[PackedScene] = []
	for scene: PackedScene in HERO_SPAWN_WEIGHTS:
		var weight: int = HERO_SPAWN_WEIGHTS[scene]
		for _i: int in range(weight):
			deck.append(scene)
	return deck


func _register_and_populate_rooms(rooms: Array[Rect2i]) -> void:
	var start_usec: int = Time.get_ticks_usec()
	for room: Rect2i in rooms:
		if not _room_remaining_enemies.has(room):
			var quota: int = _map.get_room_enemy_quota(room)
			_room_remaining_enemies[room] = quota
			_room_spawned_enemies[room] = 0
		_populate_room_enemies(room)

	var elapsed_ms: float = float(Time.get_ticks_usec() - start_usec) / 1000.0
	if elapsed_ms >= 2.0:
		print(&"[Perf] _register_and_populate_rooms took %.2f ms (rooms: %d)" % [elapsed_ms, rooms.size()])


func _populate_room_enemies(room: Rect2i) -> void:
	var remaining: int = _room_remaining_enemies.get(room, 0)
	var alive_in_room: int = _room_spawned_enemies.get(room, 0)
	var needed: int = remaining - alive_in_room
	if needed <= 0 or _enemies.size() >= MAX_ENEMIES:
		return

	var capacity: int = MAX_ENEMIES - _enemies.size()
	var to_spawn: int = mini(needed, capacity)
	var spawn_positions: Array[Vector2] = _map.get_enemy_spawn_positions_for_room(room, to_spawn)

	for pos: Vector2 in spawn_positions:
		var slime: Enemy = LAVA_SLIME_SCENE.instantiate() as Enemy
		slime.home_room = room
		slime.position = pos
		slime.map = _map
		slime.y_sort_enabled = true
		slime.projectile_spawn_requested.connect(_on_projectile_spawn_requested)
		slime.died.connect(_on_enemy_died.bind(room))
		_characters.add_child(slime)
		_enemies.append(slime)
		_room_spawned_enemies[room] = _room_spawned_enemies.get(room, 0) + 1


func _respawn_nearby_hibernating_rooms() -> void:
	if _enemies.size() >= MAX_ENEMIES:
		return

	var player_pos: Vector2 = _character.global_position
	for room: Rect2i in _map.companion_rooms:
		var remaining: int = _room_remaining_enemies.get(room, 0)
		var spawned: int = _room_spawned_enemies.get(room, 0)
		if remaining <= spawned:
			continue

		var room_world_center: Vector2 = _map.map_to_local(room.get_center())
		if player_pos.distance_squared_to(room_world_center) <= ROOM_RESPAWN_DIST_SQ:
			_populate_room_enemies(room)
			if _enemies.size() >= MAX_ENEMIES:
				break


func _on_enemy_died(room: Rect2i) -> void:
	if _room_remaining_enemies.has(room):
		_room_remaining_enemies[room] = maxi(0, _room_remaining_enemies[room] - 1)
	if _room_spawned_enemies.has(room):
		_room_spawned_enemies[room] = maxi(0, _room_spawned_enemies[room] - 1)


func _on_projectile_spawn_requested(projectile: Projectile) -> void:
	_projectiles.add_child(projectile)


func _update_followers(delta: float) -> void:
	for i: int in range(1, _squad.size()):
		var follower: Hero = _squad[i]
		if follower.squad_member != null:
			follower.squad_member.update(follower, delta, _squad, _map)


func _update_enemies() -> void:
	var camera_pos: Vector2 = _camera.global_position

	var i: int = _enemies.size() - 1
	while i >= 0:
		var enemy: Enemy = _enemies[i]
		if not is_instance_valid(enemy) or enemy.is_dead:
			_enemies.remove_at(i)
			i -= 1
			continue

		var dist_sq: float = enemy.global_position.distance_squared_to(camera_pos)
		if dist_sq > ENEMY_DESPAWN_DIST_SQ:
			var room: Rect2i = enemy.home_room
			if _room_spawned_enemies.has(room):
				_room_spawned_enemies[room] = maxi(0, _room_spawned_enemies[room] - 1)
			enemy.queue_free()
			_enemies.remove_at(i)
			i -= 1
			continue

		if dist_sq > ENEMY_ACTIVE_DIST_SQ:
			i -= 1
			continue

		var closest: Hero = _get_closest_squad_member(enemy.global_position)
		if closest != null:
			enemy.set_target_candidate(closest)
		i -= 1


func _get_closest_squad_member(pos: Vector2) -> Hero:
	var closest: Hero = null
	var min_dist_sq: float = INF
	for member: Hero in _squad:
		if not is_instance_valid(member) or member.is_dead:
			continue
		var dist_sq: float = pos.distance_squared_to(member.global_position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			closest = member
	return closest


func _on_hero_died(hero: Hero) -> void:
	if hero == _character:
		return

	var squad_idx: int = _squad.find(hero)
	if squad_idx != -1:
		_squad.remove_at(squad_idx)
		_rebalance_escort_slots()
		return

	var unrecruited_idx: int = _unrecruited_characters.find(hero)
	if unrecruited_idx != -1:
		_unrecruited_characters.remove_at(unrecruited_idx)


func _on_player_death_completed() -> void:
	var dialog: GameOverDialog = GAME_OVER_DIALOG_SCENE.instantiate() as GameOverDialog
	add_child(dialog)
	get_tree().paused = true


func _check_recruitment() -> void:
	var i: int = _unrecruited_characters.size() - 1
	var recruited_any: bool = false

	while i >= 0:
		var candidate: Hero = _unrecruited_characters[i]
		for member: Hero in _squad:
			if candidate.is_touching(member):
				_unrecruited_characters.remove_at(i)
				candidate.leader = _character
				candidate.squad_member = SquadMember.new()
				_squad.append(candidate)
				recruited_any = true
				break

		i -= 1

	if recruited_any:
		_rebalance_escort_slots()


func _rebalance_escort_slots() -> void:
	var follower_count: int = _squad.size() - 1
	for i: int in range(1, _squad.size()):
		var follower: Hero = _squad[i]
		if follower.squad_member != null:
			follower.squad_member.assign_escort_slot(i - 1, follower_count)


func _on_window_resized() -> void:
	# Workaround for Godot 4 Camera2D not re-centering after the window resizes.
	_camera.enabled = false
	_camera.enabled = true
	_camera.force_update_scroll()


func _finish_benchmark() -> void:
	_benchmark_frame_times.sort()
	var n: int = _benchmark_frame_times.size()
	var sum: float = 0.0
	var spikes_16ms: int = 0
	var spikes_33ms: int = 0
	for t: float in _benchmark_frame_times:
		sum += t
		if t > 16.67:
			spikes_16ms += 1
		if t > 33.33:
			spikes_33ms += 1
	var avg: float = sum / float(n) if n > 0 else 0.0
	var p50: float = _benchmark_frame_times[int(float(n) * 0.50)] if n > 0 else 0.0
	var p95: float = _benchmark_frame_times[int(float(n) * 0.95)] if n > 0 else 0.0
	var p99: float = _benchmark_frame_times[int(float(n) * 0.99)] if n > 0 else 0.0

	print(&"\n================ BENCHMARK BASELINE REPORT ================")
	print(&"Total Frames Sampled: %d" % n)
	print(&"Average Frame Time:   %.2f ms (%.1f FPS)" % [avg, 1000.0 / avg if avg > 0.0 else 0.0])
	print(&"50th Percentile (p50): %.2f ms" % p50)
	print(&"95th Percentile (p95): %.2f ms" % p95)
	print(&"99th Percentile (p99): %.2f ms" % p99)
	print(&"Max Frame Spike:      %.2f ms" % _benchmark_max_spike_ms)
	print(&"Frames > 16.7ms:       %d (%.1f%%)" % [spikes_16ms, (float(spikes_16ms) / float(n)) * 100.0])
	print(&"Frames > 33.3ms:       %d (%.1f%%)" % [spikes_33ms, (float(spikes_33ms) / float(n)) * 100.0])
	print(&"Active Enemies:       %d" % _enemies.size())
	print(&"Active Lights:        %d" % _map.get_active_light_count())
	print(&"Static Memory:        %.2f MB" % [float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0)])
	print(&"===========================================================\n")
