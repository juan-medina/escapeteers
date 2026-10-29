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


func _on_map_generation_progress(progress: float, stage_name: StringName) -> void:
	Transition.set_loading_progress(progress, stage_name)


func _process(delta: float) -> void:
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
	var new_rooms: Array[Rect2i] = _map.expand_frontier_near(_character.global_position)
	if not new_rooms.is_empty():
		for room: Rect2i in new_rooms:
			_spawn_companions_for_room(room)
		_register_and_populate_rooms(new_rooms)

	_respawn_nearby_hibernating_rooms()


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
	for room: Rect2i in rooms:
		if not _room_remaining_enemies.has(room):
			var quota: int = _map.get_room_enemy_quota(room)
			_room_remaining_enemies[room] = quota
			_room_spawned_enemies[room] = 0
		_populate_room_enemies(room)


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
