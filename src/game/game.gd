# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Game
extends Node2D

const MAX_CHARACTERS: int = 80
const MAX_ENEMIES: int = 15

const HERO_SCENES: Array[PackedScene] = [
	preload("res://character/heroes/archer/archer.tscn"),
	preload("res://character/heroes/armored_axeman/armored_axeman.tscn"),
	preload("res://character/heroes/knight/knight.tscn"),
	preload("res://character/heroes/knight_templar/knight_templar.tscn"),
	preload("res://character/heroes/priest/priest.tscn"),
	preload("res://character/heroes/soldier/soldier.tscn"),
	preload("res://character/heroes/swordsman/swordsman.tscn"),
	preload("res://character/heroes/wizard/wizard.tscn"),
]
const LAVA_SLIME_SCENE: PackedScene = preload("res://character/enemies/lava_slime/lava_slime.tscn")

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

	_character.position = _map.get_hero_spawn_position()
	_camera.position = _character.position
	_character.y_sort_enabled = true
	_character.is_player = true
	_character.record_step(0.0)
	_squad.append(_character)

	await _spawn_characters()
	_spawn_enemies()


func _process(delta: float) -> void:
	_camera.position = _character.position
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

	for pos: Vector2 in spawn_points:
		if hero_deck.is_empty():
			hero_deck.assign(HERO_SCENES)
			hero_deck.shuffle()

		var scene: PackedScene = hero_deck.pop_back()
		var ch: Hero = scene.instantiate() as Hero
		if ch == null:
			printerr(&"Game: Failed to instantiate hero scene!")
			await Alerts.fatal_error(&"Could not spawn characters")
			return

		ch.is_player = false
		ch.position = pos
		ch.y_sort_enabled = true
		ch.flip_h = randf() > 0.5
		ch.frame = randi() % 6
		ch.frame_progress = randf()
		_characters.add_child(ch)
		_unrecruited_characters.append(ch)


func _spawn_enemies() -> void:
	var rooms: Array[Rect2i] = _map.companion_rooms.duplicate()
	rooms.shuffle()

	var count: int = mini(MAX_ENEMIES, rooms.size())
	for i: int in range(count):
		var room: Rect2i = rooms[i]
		var slime: Enemy = LAVA_SLIME_SCENE.instantiate() as Enemy
		if slime == null:
			continue

		var cell: Vector2i = room.get_center()
		var floor_layer: TileMapLayer = _map.get_node(^"Floor") as TileMapLayer
		slime.position = floor_layer.map_to_local(cell)
		slime.map = _map
		slime.y_sort_enabled = true
		slime.projectile_spawn_requested.connect(_on_projectile_spawn_requested)
		_characters.add_child(slime)
		_enemies.append(slime)


func _on_projectile_spawn_requested(projectile: Projectile) -> void:
	if _projectiles != null and projectile != null:
		_projectiles.add_child(projectile)


func _update_followers(delta: float) -> void:
	for i: int in range(1, _squad.size()):
		var follower: Hero = _squad[i]
		if follower.squad_member != null:
			follower.squad_member.update(follower, delta, _squad, _map)


func _update_enemies() -> void:
	for enemy: Enemy in _enemies:
		if not is_instance_valid(enemy):
			continue
		var closest: Hero = _get_closest_squad_member(enemy.global_position)
		if closest != null:
			enemy.set_target_candidate(closest)


func _get_closest_squad_member(pos: Vector2) -> Hero:
	var closest: Hero = null
	var min_dist_sq: float = INF
	for member: Hero in _squad:
		if not is_instance_valid(member):
			continue
		var dist_sq: float = pos.distance_squared_to(member.global_position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			closest = member
	return closest


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
