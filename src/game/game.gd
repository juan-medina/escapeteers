# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Game
extends Node2D

const MAX_CHARACTERS: int = 80

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

var _squad: Array[Character] = []
var _unrecruited_characters: Array[Character] = []

@onready var _camera: Camera2D = $Camera2D
@onready var _character: Character = $Character
@onready var _map: Map = $Map


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


func _process(delta: float) -> void:
	_camera.position = _character.position
	_character.record_step(delta)

	_update_followers(delta)
	_check_recruitment()


func remove_member(character: Character) -> void:
	var idx: int = _squad.find(character)
	if idx == -1 or character == _character:
		return

	_squad.remove_at(idx)
	character.queue_free()
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
		var ch: Character = scene.instantiate() as Character
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
		add_child(ch)
		_unrecruited_characters.append(ch)


func _update_followers(delta: float) -> void:
	for i: int in range(1, _squad.size()):
		var follower: Character = _squad[i]
		if follower.squad_member != null:
			follower.squad_member.update(follower, delta, _squad, _map)


func _check_recruitment() -> void:
	var i: int = _unrecruited_characters.size() - 1
	var recruited_any: bool = false

	while i >= 0:
		var candidate: Character = _unrecruited_characters[i]
		for member: Character in _squad:
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
		var follower: Character = _squad[i]
		if follower.squad_member != null:
			follower.squad_member.assign_escort_slot(i - 1, follower_count)


func _on_window_resized() -> void:
	# Workaround for Godot 4 Camera2D not re-centering after the window resizes.
	_camera.enabled = false
	_camera.enabled = true
	_camera.force_update_scroll()
