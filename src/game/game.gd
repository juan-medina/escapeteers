# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Game
extends Node2D

const SPREAD_MIN_DISTANCE: float = 150.0
const SPREAD_MAX_DISTANCE: float = 200.0
const MAX_CHARACTERS: int = 80

const _BACKGROUND_SIZE: float = 2000.0
const _PATTERN_SIZE: int = 64
const _CELL_SIZE: int = 32
const _COLOR_DARK: Color = Color(0.12, 0.14, 0.18, 1.0)
const _COLOR_LIGHT: Color = Color(0.16, 0.19, 0.24, 1.0)
const _COLOR_GRID: Color = Color(0.24, 0.28, 0.35, 1.0)

const _MAP_MARGIN: float = 100.0
const _K_POISSON_ATTEMPTS: int = 30

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


func _ready() -> void:
	# Workaround for Godot 4 Camera2D not re-centering after the window resizes.
	get_tree().root.size_changed.connect(_on_window_resized)
	process_priority = 1
	y_sort_enabled = true

	_character.y_sort_enabled = true
	_character.is_player = true
	_character.record_step(0.0)
	_squad.append(_character)

	_create_background()

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


func _create_background() -> void:
	var img: Image = Image.create(_PATTERN_SIZE, _PATTERN_SIZE, false, Image.FORMAT_RGBA8)
	for y: int in _PATTERN_SIZE:
		for x: int in _PATTERN_SIZE:
			if x == 0 or y == 0:
				img.set_pixel(x, y, _COLOR_GRID)
			elif (x < _CELL_SIZE and y < _CELL_SIZE) or (x >= _CELL_SIZE and y >= _CELL_SIZE):
				img.set_pixel(x, y, _COLOR_DARK)
			else:
				img.set_pixel(x, y, _COLOR_LIGHT)

	var texture: ImageTexture = ImageTexture.create_from_image(img)
	var background: Sprite2D = Sprite2D.new()
	background.name = &"Background"
	background.texture = texture
	background.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	background.region_enabled = true
	background.region_rect = Rect2(-_BACKGROUND_SIZE / 2.0, -_BACKGROUND_SIZE / 2.0, _BACKGROUND_SIZE, _BACKGROUND_SIZE)
	background.z_index = -1
	add_child(background)
	move_child(background, 0)


func _spawn_characters() -> void:
	var half_size: float = (_BACKGROUND_SIZE / 2.0) - _MAP_MARGIN
	var cell_size: float = SPREAD_MIN_DISTANCE / sqrt(2.0)
	var grid: Dictionary = {}
	var active_points: Array[Vector2] = []
	var spawn_points: Array[Vector2] = []

	# Reserve player position at (0, 0) in grid so no character spawns on top of player.
	var player_cell: Vector2i = Vector2i(floori(0.0 / cell_size), floori(0.0 / cell_size))
	grid[player_cell] = Vector2.ZERO

	# Seed point within spread range of player.
	var seed_angle: float = randf() * TAU
	var seed_dist: float = randf_range(SPREAD_MIN_DISTANCE, SPREAD_MAX_DISTANCE)
	var seed_pt: Vector2 = Vector2(cos(seed_angle), sin(seed_angle)) * seed_dist
	var seed_cell: Vector2i = Vector2i(floori(seed_pt.x / cell_size), floori(seed_pt.y / cell_size))
	grid[seed_cell] = seed_pt
	active_points.append(seed_pt)
	spawn_points.append(seed_pt)

	while not active_points.is_empty():
		var rand_idx: int = randi() % active_points.size()
		var pt: Vector2 = active_points[rand_idx]
		var found: bool = false

		for attempt: int in _K_POISSON_ATTEMPTS:
			var angle: float = randf() * TAU
			var dist: float = randf_range(SPREAD_MIN_DISTANCE, SPREAD_MAX_DISTANCE)
			var candidate: Vector2 = pt + Vector2(cos(angle), sin(angle)) * dist

			if candidate.x < -half_size or candidate.x > half_size or candidate.y < -half_size or candidate.y > half_size:
				continue

			var cell: Vector2i = Vector2i(floori(candidate.x / cell_size), floori(candidate.y / cell_size))
			var too_close: bool = false

			for dy: int in range(-2, 3):
				for dx: int in range(-2, 3):
					var neighbor_cell: Vector2i = cell + Vector2i(dx, dy)
					if grid.has(neighbor_cell):
						var other: Vector2 = grid[neighbor_cell]
						if candidate.distance_to(other) < SPREAD_MIN_DISTANCE:
							too_close = true
							break
				if too_close:
					break

			if not too_close:
				grid[cell] = candidate
				active_points.append(candidate)
				spawn_points.append(candidate)
				found = true
				break

		if not found:
			active_points.remove_at(rand_idx)

	if MAX_CHARACTERS > 0 and spawn_points.size() > MAX_CHARACTERS:
		var seed_point: Vector2 = spawn_points[0]
		spawn_points.remove_at(0)
		spawn_points.shuffle()
		spawn_points.resize(MAX_CHARACTERS - 1)
		spawn_points.insert(0, seed_point)

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
		_squad[i].follow_leader(delta, _squad)


func _check_recruitment() -> void:
	var i: int = _unrecruited_characters.size() - 1
	var recruited_any: bool = false

	while i >= 0:
		var candidate: Character = _unrecruited_characters[i]
		for member: Character in _squad:
			if candidate.is_touching(member):
				_unrecruited_characters.remove_at(i)
				candidate.leader = _character
				_squad.append(candidate)
				recruited_any = true
				break

		i -= 1

	if recruited_any:
		_rebalance_escort_slots()


func _rebalance_escort_slots() -> void:
	var follower_count: int = _squad.size() - 1
	for i: int in range(1, _squad.size()):
		_squad[i].assign_escort_slot(i - 1, follower_count)


func _on_window_resized() -> void:
	# Workaround for Godot 4 Camera2D not re-centering after the window resizes.
	_camera.enabled = false
	_camera.enabled = true
	_camera.force_update_scroll()
