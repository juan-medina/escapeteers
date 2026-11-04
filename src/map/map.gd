# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Map
extends Node2D

signal generation_progress_updated(progress: float, stage_name: StringName)

const TILE_SET_SOURCE_ID: int = 4

const FLOOR_ATLAS_START: Vector2i = Vector2i(10, 14)
const FLOOR_ATLAS_SIZE: Vector2i = Vector2i(6, 3)

const WALL_TOP_LEFT_OUTER: Vector2i = Vector2i(2, 11)
const WALL_TOP_RIGHT_OUTER: Vector2i = Vector2i(5, 11)
const WALL_TOP_LEFT_INNER: Vector2i = Vector2i(2, 12)
const WALL_TOP_RIGHT_INNER: Vector2i = Vector2i(5, 12)
const WALL_TOP_VARIANTS: Array[Vector2i] = [Vector2i(3, 11), Vector2i(4, 11)]

const WALL_BOTTOM_LEFT_OUTER: Vector2i = Vector2i(0, 16)
const WALL_BOTTOM_RIGHT_OUTER: Vector2i = Vector2i(7, 16)
const WALL_BOTTOM_LEFT_INNER: Vector2i = Vector2i(1, 16)
const WALL_BOTTOM_RIGHT_INNER: Vector2i = Vector2i(6, 16)
const WALL_BOTTOM_VARIANTS: Array[Vector2i] = [Vector2i(3, 18), Vector2i(4, 18)]

const WALL_LEFT_VARIANTS: Array[Vector2i] = [Vector2i(0, 14), Vector2i(0, 15)]
const WALL_RIGHT_VARIANTS: Array[Vector2i] = [Vector2i(7, 14), Vector2i(7, 15)]

const TORCH_TOP: Vector2i = Vector2i(12, 20)
const TORCH_SIDE: Vector2i = Vector2i(12, 19)
const TORCH_RIGHT_ALT_ID: int = 1
const TORCH_SPAWN_CHANCE: float = 0.1
const MIN_TORCH_DISTANCE_SQUARED: int = 36

const CANDLE_POST_TOP: Vector2i = Vector2i(10, 30)
const CANDLE_POST_BOTTOM: Vector2i = Vector2i(10, 31)

const PROP_BARREL: Vector2i = Vector2i(4, 28)
const PROP_BOX: Vector2i = Vector2i(4, 29)
const PROP_SKULLS_AND_BONES: Array[Vector2i] = [Vector2i(5, 29), Vector2i(6, 29), Vector2i(7, 29), Vector2i(8, 29)]
const CORRIDOR_BONE_CHANCE: float = 0.02

const ROOM_PADDING: int = 8
const EXPAND_TRIGGER_DISTANCE_TILES: float = 75.0

@export var debug_seed: int = 0

var plan: WorldPlan = WorldPlan.new()
var streamer: MapStreamer = MapStreamer.new()
var hero_room: Rect2i = Rect2i()
var companion_rooms: Array[Rect2i] = []

var nav_window: NavWindow = NavWindow.new()
var light_manager: LightManager = LightManager.new()
var _cells: Dictionary[Vector2i, bool] = {}
var _walkable_cells: Dictionary[Vector2i, bool] = {}
var _placed_torches: Array[Vector2i] = []
var _room_depths: Dictionary[Rect2i, int] = {}
var _expanded_rooms: Dictionary[Rect2i, bool] = {}
var _decorated_rooms: Dictionary[Rect2i, bool] = {}

@onready var _floor: TileMapLayer = $Floor
@onready var _walls: TileMapLayer = $Walls
@onready var _decorations: TileMapLayer = $Decorations
@onready var _lights: Node2D = $Lights


func _ready() -> void:
	y_sort_enabled = true
	_walls.y_sort_enabled = true
	_decorations.y_sort_enabled = true
	_floor.z_index = -1
	_floor.rendering_quadrant_size = 4
	_walls.rendering_quadrant_size = 4
	_decorations.rendering_quadrant_size = 4
	if _walls.tile_set == null:
		_walls.tile_set = _floor.tile_set
	if _decorations.tile_set == null:
		_decorations.tile_set = _floor.tile_set
	if not _lights.is_ancestor_of(light_manager):
		_lights.add_child(light_manager)


func get_active_light_count() -> int:
	return light_manager.get_active_light_count()


func get_hero_spawn_position() -> Vector2:
	return _floor.map_to_local(hero_room.get_center() + Vector2i(0, 1))


func map_to_local(cell: Vector2i) -> Vector2:
	return _floor.map_to_local(cell)


func local_to_map(world_pos: Vector2) -> Vector2i:
	return _floor.local_to_map(world_pos)


func get_room_depth(room: Rect2i) -> int:
	return plan.get_room_depth(room)


func get_room_tier(room: Rect2i) -> int:
	return plan.get_room_tier(room)


func get_starter_companion_spawn_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var hero_center: Vector2i = hero_room.get_center()
	for offset_x: int in [-2, 2]:
		var recruit_cell: Vector2i = hero_center + Vector2i(offset_x, -1)
		positions.append(_floor.map_to_local(recruit_cell))
	return positions


func get_companion_spawn_positions_for_room(room: Rect2i) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var spawns: Array = plan.get_companion_spawns_for_room(room)
	for cell_var: Variant in spawns:
		if cell_var is Vector2i:
			var cell: Vector2i = cell_var
			positions.append(_floor.map_to_local(cell))
	if positions.is_empty():
		positions.append(_floor.map_to_local(room.get_center()))
	return positions


func get_companion_spawn_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = get_starter_companion_spawn_positions()
	for room: Rect2i in companion_rooms:
		positions.append_array(get_companion_spawn_positions_for_room(room))
	return positions


func get_room_enemy_quota(room: Rect2i) -> int:
	return plan.get_room_enemy_quota(room)


func get_enemy_spawn_positions_for_room(room: Rect2i, count: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var center: Vector2i = room.get_center()
	var margin: int = 2 if room.size.x >= 6 and room.size.y >= 6 else 1
	var min_x: int = room.position.x + margin
	var max_x: int = room.position.x + room.size.x - margin - 1
	var min_y: int = room.position.y + margin
	var max_y: int = room.position.y + room.size.y - margin - 1

	if min_x > max_x or min_y > max_y:
		min_x = room.position.x + 1
		max_x = room.position.x + room.size.x - 2
		min_y = room.position.y + 1
		max_y = room.position.y + room.size.y - 2

	var attempts: int = 0
	var max_attempts: int = count * 6

	while positions.size() < count and attempts < max_attempts:
		attempts += 1
		var cell: Vector2i = Vector2i(randi_range(min_x, max_x), randi_range(min_y, max_y))
		if cell.distance_squared_to(center) >= 2:
			positions.append(_floor.map_to_local(cell))

	if positions.is_empty():
		positions.append(_floor.map_to_local(center))

	return positions


func is_cell_walkable(cell: Vector2i) -> bool:
	return _walkable_cells.has(cell)


func clamp_to_walkable(world_pos: Vector2) -> Vector2:
	var cell: Vector2i = _floor.local_to_map(world_pos)
	if is_cell_walkable(cell):
		return world_pos
	var closest_cell: Vector2i = _find_closest_walkable_cell(cell)
	return _floor.map_to_local(closest_cell)


func get_navigation_path(from_pos: Vector2, to_pos: Vector2) -> PackedVector2Array:
	if nav_window == null:
		return PackedVector2Array()
	return nav_window.get_path(from_pos, to_pos)


func is_in_nav_bounds(world_pos: Vector2) -> bool:
	if nav_window == null or _floor == null:
		return false
	return nav_window.is_in_bounds(_floor.local_to_map(world_pos))


func generate_map() -> void:
	if debug_seed != 0:
		seed(debug_seed)
		print(&"[Map] Seed set to debug_seed: %d" % debug_seed)

	generation_progress_updated.emit(0.15, &"Surveying primal chamber...")
	await get_tree().process_frame

	_floor.clear()
	_walls.clear()
	_decorations.clear()
	_clear_lights()
	companion_rooms.clear()
	_cells.clear()
	_walkable_cells.clear()
	_placed_torches.clear()
	_room_depths.clear()
	_expanded_rooms.clear()
	_decorated_rooms.clear()

	plan.generate(debug_seed)
	hero_room = plan.hero_room
	_expanded_rooms[hero_room] = true

	var depth_1_rooms: Array[Rect2i] = plan.get_depth_rooms(1)
	companion_rooms.append_array(depth_1_rooms)

	generation_progress_updated.emit(0.45, &"Preparing navigation network...")
	await get_tree().process_frame

	nav_window.setup(_walkable_cells, _floor)
	nav_window.update_center(hero_room.get_center())
	light_manager.setup(debug_seed)
	light_manager.set_focus(get_hero_spawn_position())
	streamer.setup(plan, _floor, _walls, _decorations, light_manager, nav_window, _walkable_cells, debug_seed)

	generation_progress_updated.emit(0.70, &"Materializing starting chambers...")
	await get_tree().process_frame

	var start_bounds: Rect2i = hero_room
	for r: Rect2i in depth_1_rooms:
		start_bounds = start_bounds.merge(r)
	streamer.materialize_rect_immediate(start_bounds.grow(ROOM_PADDING))

	var initial_rooms: Array[Rect2i] = [hero_room]
	initial_rooms.append_array(companion_rooms)
	decorate_rooms(initial_rooms)

	generation_progress_updated.emit(0.90, &"Lighting dungeon torches...")
	await get_tree().process_frame


func update_streaming(player_world_pos: Vector2, player_velocity: Vector2) -> void:
	streamer.update(player_world_pos, player_velocity)
	light_manager.set_focus(player_world_pos)


func is_room_materialized(room: Rect2i) -> bool:
	return is_cell_walkable(room.get_center())


func expand_frontier_near(player_world_pos: Vector2) -> Array[Rect2i]:
	var player_cell: Vector2i = _floor.local_to_map(player_world_pos)
	var trigger_dist_sq: float = EXPAND_TRIGGER_DISTANCE_TILES * EXPAND_TRIGGER_DISTANCE_TILES
	var new_rooms: Array[Rect2i] = []

	for candidate_room: Rect2i in plan.rooms:
		if not companion_rooms.has(candidate_room):
			var d_sq: float = Vector2(player_cell).distance_squared_to(Vector2(candidate_room.get_center()))
			if d_sq <= trigger_dist_sq:
				companion_rooms.append(candidate_room)
				new_rooms.append(candidate_room)

	var rooms_to_expand: Array[Rect2i] = []
	for room: Rect2i in companion_rooms:
		if _expanded_rooms.has(room):
			continue
		var dist_sq: float = Vector2(player_cell).distance_squared_to(Vector2(room.get_center()))
		if dist_sq <= trigger_dist_sq:
			rooms_to_expand.append(room)

	for expand_room: Rect2i in rooms_to_expand:
		_expanded_rooms[expand_room] = true
		var raw_children: Array = plan.get_child_rooms(expand_room)
		for item: Variant in raw_children:
			if item is Rect2i:
				var child_room: Rect2i = item
				if not companion_rooms.has(child_room):
					companion_rooms.append(child_room)
					new_rooms.append(child_room)

	var ready_to_decorate: Array[Rect2i] = []
	for r: Rect2i in companion_rooms:
		if not _decorated_rooms.has(r) and is_room_materialized(r):
			ready_to_decorate.append(r)
	if not ready_to_decorate.is_empty():
		decorate_rooms(ready_to_decorate)

	return new_rooms


func decorate_rooms(rooms: Array[Rect2i]) -> void:
	_place_room_props_for_rooms(rooms)
	for r: Rect2i in rooms:
		_decorated_rooms[r] = true


func _find_closest_walkable_cell(target_cell: Vector2i) -> Vector2i:
	if is_cell_walkable(target_cell):
		return target_cell

	for r: int in range(1, 6):
		for dx: int in range(-r, r + 1):
			for dy: int in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var candidate: Vector2i = target_cell + Vector2i(dx, dy)
				if is_cell_walkable(candidate):
					return candidate

	return target_cell


func _pick_random_tile(tiles: Array[Vector2i]) -> Vector2i:
	return tiles[randi() % tiles.size()]


func _clear_lights() -> void:
	if light_manager != null:
		light_manager.clear()


func _is_corner_cell(cell: Vector2i) -> bool:
	if _walls.get_cell_source_id(cell) != -1:
		return false
	var wall_n: bool = _walls.get_cell_source_id(cell + Vector2i(0, -1)) != -1
	var wall_s: bool = _walls.get_cell_source_id(cell + Vector2i(0, 1)) != -1
	var wall_w: bool = _walls.get_cell_source_id(cell + Vector2i(-1, 0)) != -1
	var wall_e: bool = _walls.get_cell_source_id(cell + Vector2i(1, 0)) != -1
	return (wall_n and wall_w) or (wall_n and wall_e) or (wall_s and wall_w) or (wall_s and wall_e)


func _is_far_from_torches(cell: Vector2i) -> bool:
	for dy: int in range(-6, 7):
		for dx: int in range(-6, 7):
			if dx * dx + dy * dy < MIN_TORCH_DISTANCE_SQUARED:
				if light_manager.has_light(cell + Vector2i(dx, dy)):
					return false
	return true


func _ensure_room_torches_for_rooms(rooms: Array[Rect2i]) -> void:
	for room: Rect2i in rooms:
		if _decorated_rooms.has(room):
			continue
		var top_y: int = room.position.y - 1
		var north_torch_count: int = 0
		for x: int in range(room.position.x, room.position.x + room.size.x):
			if light_manager.has_light(Vector2i(x, top_y)):
				north_torch_count += 1

		var target_count: int = 2 if room.size.x >= 14 else 1
		if north_torch_count < target_count:
			var candidate_x_offsets: Array[float] = []
			if target_count == 1:
				candidate_x_offsets.append(0.5)
			else:
				candidate_x_offsets.append(0.33)
				candidate_x_offsets.append(0.67)
			for offset: float in candidate_x_offsets:
				var target_x: int = room.position.x + int(float(room.size.x) * offset)
				var candidate: Vector2i = Vector2i(target_x, top_y)
				if _walls.get_cell_atlas_coords(candidate) in WALL_TOP_VARIANTS and not light_manager.has_light(candidate):
					_decorations.set_cell(candidate, TILE_SET_SOURCE_ID, TORCH_TOP)
					var chunk_coord: Vector2i = MapStreamer.cell_to_chunk(candidate)
					var world_pos: Vector2 = _decorations.map_to_local(candidate)
					light_manager.add_light(chunk_coord, candidate, world_pos)
				else:
					for dx: int in range(-2, 3):
						var alt_candidate: Vector2i = Vector2i(target_x + dx, top_y)
						if (
							alt_candidate.x >= room.position.x
							and alt_candidate.x < room.position.x + room.size.x
							and _walls.get_cell_atlas_coords(alt_candidate) in WALL_TOP_VARIANTS
							and not light_manager.has_light(alt_candidate)
						):
							_decorations.set_cell(alt_candidate, TILE_SET_SOURCE_ID, TORCH_TOP)
							var chunk_coord: Vector2i = MapStreamer.cell_to_chunk(alt_candidate)
							var world_pos: Vector2 = _decorations.map_to_local(alt_candidate)
							light_manager.add_light(chunk_coord, alt_candidate, world_pos)
							break


func _place_candle_posts_for_rooms(rooms: Array[Rect2i]) -> void:
	for room: Rect2i in rooms:
		if _decorated_rooms.has(room):
			continue
		var center: Vector2i = room.get_center()
		var candidate_points: Array[Vector2i] = []

		if room.size.x >= 50 and room.size.y >= 50:
			var qw: int = int(float(room.size.x) * 0.28)
			var qh: int = int(float(room.size.y) * 0.28)
			candidate_points.append(center + Vector2i(-qw, -qh))
			candidate_points.append(center + Vector2i(qw, -qh))
			candidate_points.append(center + Vector2i(-qw, qh))
			candidate_points.append(center + Vector2i(qw, qh))
			candidate_points.append(center + Vector2i(0, -qh))
			candidate_points.append(center + Vector2i(0, qh))
			candidate_points.append(center + Vector2i(-qw, 0))
			candidate_points.append(center + Vector2i(qw, 0))
		elif room.size.x >= 20 and room.size.y >= 20:
			var half_w: int = int(float(room.size.x) * 0.25)
			var half_h: int = int(float(room.size.y) * 0.25)
			candidate_points.append(center + Vector2i(-half_w, -half_h))
			candidate_points.append(center + Vector2i(half_w, -half_h))
			candidate_points.append(center + Vector2i(-half_w, half_h))
			candidate_points.append(center + Vector2i(half_w, half_h))
		else:
			var half_w: int = int(float(room.size.x) * 0.25)
			candidate_points.append(center + Vector2i(-half_w, 0))
			candidate_points.append(center + Vector2i(half_w, 0))

		for base_candidate: Vector2i in candidate_points:
			var placed: bool = false
			for dx: int in range(-1, 2):
				if placed:
					break
				for dy: int in range(-1, 2):
					var base_cell: Vector2i = base_candidate + Vector2i(dx, dy)
					var top_cell: Vector2i = base_cell + Vector2i(0, -1)

					if _floor.get_cell_source_id(base_cell) == -1 or _floor.get_cell_source_id(top_cell) == -1:
						continue
					if _walls.get_cell_source_id(base_cell) != -1 or _walls.get_cell_source_id(top_cell) != -1:
						continue
					if _decorations.get_cell_source_id(base_cell) != -1 or _decorations.get_cell_source_id(top_cell) != -1:
						continue
					if base_cell.distance_squared_to(center) < 4:
						continue
					if not _is_far_from_torches(top_cell):
						continue

					_decorations.set_cell(top_cell, TILE_SET_SOURCE_ID, CANDLE_POST_TOP)
					_decorations.set_cell(base_cell, TILE_SET_SOURCE_ID, CANDLE_POST_BOTTOM)
					var chunk_coord: Vector2i = MapStreamer.cell_to_chunk(top_cell)
					var world_pos: Vector2 = _decorations.map_to_local(top_cell)
					light_manager.add_light(chunk_coord, top_cell, world_pos)
					placed = true
					break


func _place_room_props_for_rooms(rooms: Array[Rect2i]) -> void:
	for room: Rect2i in rooms:
		if _decorated_rooms.has(room):
			continue
		var center: Vector2i = room.get_center()
		var corner_cells: Array[Vector2i] = []
		var floor_cells: Array[Vector2i] = []

		for x: int in range(room.position.x, room.position.x + room.size.x):
			for y: int in range(room.position.y, room.position.y + room.size.y):
				var cell: Vector2i = Vector2i(x, y)
				if _floor.get_cell_source_id(cell) == -1 or _walls.get_cell_source_id(cell) != -1:
					continue
				if cell.distance_squared_to(center) <= 4:
					continue
				if _is_corner_cell(cell):
					corner_cells.append(cell)
				else:
					floor_cells.append(cell)

		corner_cells.shuffle()
		floor_cells.shuffle()

		# Barrels and boxes only in corners
		for cell: Vector2i in corner_cells:
			if _decorations.get_cell_source_id(cell) != -1:
				continue
			if randf() <= 0.75:
				var prop_tile: Vector2i = PROP_BARREL if randf() > 0.5 else PROP_BOX
				_decorations.set_cell(cell, TILE_SET_SOURCE_ID, prop_tile)

		# Skulls and bones in rooms
		var bones_count: int = clampi(int(float(room.size.x * room.size.y) * 0.025), 1, 4)
		var bones_placed: int = 0
		for cell: Vector2i in floor_cells:
			if bones_placed >= bones_count:
				break
			if _decorations.get_cell_source_id(cell) != -1:
				continue
			var bone_tile: Vector2i = _pick_random_tile(PROP_SKULLS_AND_BONES)
			_decorations.set_cell(cell, TILE_SET_SOURCE_ID, bone_tile)
			bones_placed += 1


func _place_corridor_bones_in_rect(region: Rect2i) -> void:
	for x: int in range(region.position.x, region.end.x):
		for y: int in range(region.position.y, region.end.y):
			var cell: Vector2i = Vector2i(x, y)
			if not _cells.has(cell):
				continue
			if _walls.get_cell_source_id(cell) != -1 or _decorations.get_cell_source_id(cell) != -1:
				continue
			if _is_inside_any_room(cell):
				continue
			if randf() <= CORRIDOR_BONE_CHANCE:
				var bone_tile: Vector2i = _pick_random_tile(PROP_SKULLS_AND_BONES)
				_decorations.set_cell(cell, TILE_SET_SOURCE_ID, bone_tile)


func _is_inside_any_room(cell: Vector2i) -> bool:
	if hero_room.has_point(cell):
		return true
	for room: Rect2i in companion_rooms:
		if room.has_point(cell):
			return true
	return false
