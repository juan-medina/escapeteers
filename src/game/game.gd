# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Game
extends Node2D

const MAX_CHARACTERS: int = 80
const MAX_ENEMIES: int = 120

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
	await _spawn_characters()
	_check_recruitment()
	_spawn_enemies()

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


func _spawn_characters() -> void:
	var spawn_points: Array[Vector2] = _map.get_companion_spawn_positions()

	if MAX_CHARACTERS > 0 and spawn_points.size() > MAX_CHARACTERS:
		spawn_points.resize(MAX_CHARACTERS)

	var hero_deck: Array[PackedScene] = []
	var starter_heroes: Array[PackedScene] = [WIZARD_SCENE, PRIEST_SCENE, ARMORED_AXEMAN_SCENE]

	for i: int in range(spawn_points.size()):
		var pos: Vector2 = spawn_points[i]
		var scene: PackedScene = null
		if i < starter_heroes.size():
			scene = starter_heroes[i]
		else:
			if hero_deck.is_empty():
				hero_deck = _build_hero_deck()
				hero_deck.shuffle()
			scene = hero_deck.pop_back()

		var ch: Hero = scene.instantiate() as Hero
		if ch == null:
			printerr(&"Game: Failed to instantiate hero scene!")
			await Alerts.fatal_error(&"Could not spawn characters")
			return

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


func _spawn_enemies() -> void:
	var rooms: Array[Rect2i] = _map.companion_rooms.duplicate()
	var hero_center: Vector2 = Vector2(_map.hero_room.get_center())
	rooms.sort_custom(
		func(a: Rect2i, b: Rect2i) -> bool:
			return hero_center.distance_squared_to(Vector2(a.get_center())) < hero_center.distance_squared_to(Vector2(b.get_center()))
	)

	for room: Rect2i in rooms:
		if _enemies.size() >= MAX_ENEMIES:
			break

		var tier: int = _map.get_room_tier(room)
		var mob_count: int = 0
		match tier:
			1:
				mob_count = randi_range(5, 8)
			2:
				mob_count = randi_range(12, 18)
			3:
				mob_count = randi_range(25, 35)

		var remaining_capacity: int = MAX_ENEMIES - _enemies.size()
		mob_count = mini(mob_count, remaining_capacity)

		var spawn_positions: Array[Vector2] = _map.get_enemy_spawn_positions_for_room(room, mob_count)
		for pos: Vector2 in spawn_positions:
			var slime: Enemy = LAVA_SLIME_SCENE.instantiate() as Enemy
			if slime == null:
				continue
			slime.home_room = room
			slime.position = pos
			slime.map = _map
			slime.y_sort_enabled = true
			slime.projectile_spawn_requested.connect(_on_projectile_spawn_requested)
			_characters.add_child(slime)
			_enemies.append(slime)


func _on_projectile_spawn_requested(projectile: Projectile) -> void:
	_projectiles.add_child(projectile)


func _update_followers(delta: float) -> void:
	for i: int in range(1, _squad.size()):
		var follower: Hero = _squad[i]
		if follower.squad_member != null:
			follower.squad_member.update(follower, delta, _squad, _map)


func _update_enemies() -> void:
	var camera_pos: Vector2 = _camera.global_position
	const ACTIVE_DIST_SQ: float = 480.0 * 480.0

	var i: int = _enemies.size() - 1
	while i >= 0:
		var enemy: Enemy = _enemies[i]
		if not is_instance_valid(enemy) or enemy.is_dead:
			_enemies.remove_at(i)
			i -= 1
			continue

		if enemy.global_position.distance_squared_to(camera_pos) > ACTIVE_DIST_SQ:
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
