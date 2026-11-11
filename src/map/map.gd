# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Map
extends Node2D

signal generation_progress_updated(progress: float, stage_name: StringName)
signal secret_torches_completed

const PROP_BARREL: Vector2i = Vector2i(4, 28)
const PROP_BOX: Vector2i = Vector2i(4, 29)
const PROP_SKULLS_AND_BONES: Array[Vector2i] = [Vector2i(5, 29), Vector2i(6, 29), Vector2i(7, 29), Vector2i(8, 29)]

const ROOM_PADDING: int = 8
const EXPAND_TRIGGER_DISTANCE_TILES: float = 75.0
const SECRET_TORCH_COUNT: int = 4
const SECRET_TORCH_TRIGGER_DIST_SQ: float = 28.0 * 28.0
const SPIKE_STAY_DOWN_TIME: float = 2.00
const SPIKE_UP_1_TIME: float = 0.40
const SPIKE_UP_2_TIME: float = 0.10
const SPIKE_STAY_UP_TIME: float = 1.10
const SPIKE_DOWN_2_TIME: float = 0.10
const SPIKE_DOWN_1_TIME: float = 0.10
const SPIKE_CYCLE_DURATION: float = 3.80

@export var debug_seed: int = 0

var plan: WorldPlan = WorldPlan.new()
var streamer: MapStreamer = MapStreamer.new()
var hero_room: Rect2i = Rect2i()
var companion_rooms: Array[Rect2i] = []

var nav_window: NavWindow = NavWindow.new()
var light_manager: LightManager = LightManager.new()
var _walkable_cells: Dictionary[Vector2i, bool] = {}
var _loaded_spikes: Dictionary[Vector2i, int] = {}
var _group_frames: Array[int] = [0, 0, 0, 0]
var _spike_elapsed: float = 0.0
var _expanded_rooms: Dictionary[Rect2i, bool] = {}
var _decorated_rooms: Dictionary[Rect2i, bool] = {}
var _secret_torch_cells: Array[Vector2i] = []
var _secret_torch_index: int = 0

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


func get_hero_spawn_position() -> Vector2:
	return _floor.map_to_local(hero_room.get_center() + Vector2i(0, 1))


func map_to_local(cell: Vector2i) -> Vector2:
	return _floor.map_to_local(cell)


func local_to_map(world_pos: Vector2) -> Vector2i:
	return _floor.local_to_map(world_pos)


func get_room_depth(room: Rect2i) -> int:
	return plan.get_room_depth(room)


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
	_walkable_cells.clear()
	_loaded_spikes.clear()
	_group_frames = [0, 0, 0, 0]
	_spike_elapsed = 0.0
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
	streamer.setup(plan, _floor, _walls, _decorations, light_manager, nav_window, _walkable_cells, _loaded_spikes, _group_frames, debug_seed)

	generation_progress_updated.emit(0.70, &"Materializing starting chambers...")
	await get_tree().process_frame

	var start_bounds: Rect2i = hero_room
	for r: Rect2i in depth_1_rooms:
		start_bounds = start_bounds.merge(r)
	streamer.materialize_rect_immediate(start_bounds.grow(ROOM_PADDING))

	var initial_rooms: Array[Rect2i] = [hero_room]
	initial_rooms.append_array(companion_rooms)
	_decorate_rooms(initial_rooms)
	_setup_secret_torches()

	generation_progress_updated.emit(0.90, &"Lighting dungeon torches...")
	await get_tree().process_frame


func update_streaming(player_world_pos: Vector2, player_velocity: Vector2) -> void:
	streamer.update(player_world_pos, player_velocity)
	light_manager.set_focus(player_world_pos)
	_check_secret_torch_proximity(player_world_pos)


func update_spikes(delta: float) -> void:
	_spike_elapsed += delta
	var changed_groups: Dictionary[int, int] = {}
	var step_offset: float = SPIKE_CYCLE_DURATION / float(WorldPlan.SPIKE_PHASE_GROUPS)

	for g: int in range(WorldPlan.SPIKE_PHASE_GROUPS):
		var group_time: float = fmod(_spike_elapsed + float(g) * step_offset, SPIKE_CYCLE_DURATION)
		var new_frame: int = _get_spike_frame_for_time(group_time)
		if new_frame != _group_frames[g]:
			_group_frames[g] = new_frame
			changed_groups[g] = new_frame

	if changed_groups.is_empty() or _loaded_spikes.is_empty():
		return

	for cell: Vector2i in _loaded_spikes:
		var group_id: int = _loaded_spikes[cell]
		if changed_groups.has(group_id):
			var frame_idx: int = changed_groups[group_id]
			_floor.set_cell(cell, TileClassifier.TILE_SET_SOURCE_ID, TileClassifier.SPIKE_FRAMES[frame_idx])


func is_spike_active_at(cell: Vector2i) -> bool:
	if not _loaded_spikes.has(cell):
		return false
	var group_id: int = _loaded_spikes[cell]
	return group_id >= 0 and group_id < _group_frames.size() and _group_frames[group_id] == 3


static func _get_spike_frame_for_time(t: float) -> int:
	if t < SPIKE_STAY_DOWN_TIME:
		return 0
	var rem: float = t - SPIKE_STAY_DOWN_TIME
	if rem < SPIKE_UP_1_TIME:
		return 1
	rem -= SPIKE_UP_1_TIME
	if rem < SPIKE_UP_2_TIME:
		return 2
	rem -= SPIKE_UP_2_TIME
	if rem < SPIKE_STAY_UP_TIME:
		return 3
	rem -= SPIKE_STAY_UP_TIME
	if rem < SPIKE_DOWN_2_TIME:
		return 2
	return 1


func cancel_secret_torches() -> void:
	if _secret_torch_index < _secret_torch_cells.size():
		light_manager.set_light_blinking(_secret_torch_cells[_secret_torch_index], false)
		_secret_torch_index = _secret_torch_cells.size()


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
		_decorate_rooms(ready_to_decorate)

	return new_rooms


func _decorate_rooms(rooms: Array[Rect2i]) -> void:
	_place_room_props_for_rooms(rooms)
	for r: Rect2i in rooms:
		_decorated_rooms[r] = true


func _check_secret_torch_proximity(player_world_pos: Vector2) -> void:
	if _secret_torch_index >= _secret_torch_cells.size():
		return

	var target_cell: Vector2i = _secret_torch_cells[_secret_torch_index]
	var torch_world_pos: Vector2 = _decorations.map_to_local(target_cell)
	if player_world_pos.distance_squared_to(torch_world_pos) > SECRET_TORCH_TRIGGER_DIST_SQ:
		return

	_decorations.erase_cell(target_cell)
	light_manager.remove_light_at(target_cell)
	_secret_torch_index += 1

	if _secret_torch_index < _secret_torch_cells.size():
		light_manager.set_light_blinking(_secret_torch_cells[_secret_torch_index], true)
		return

	secret_torches_completed.emit()


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


func _setup_secret_torches() -> void:
	_secret_torch_cells.clear()
	_secret_torch_index = 0

	var clear_rect: Rect2i = hero_room.grow(2)
	var existing_lights: Array[Vector2i] = light_manager.get_lights_in_rect(clear_rect)
	for cell_pos: Vector2i in existing_lights:
		_decorations.erase_cell(cell_pos)
		light_manager.remove_light_at(cell_pos)

	var top_left: Array[Dictionary] = []
	var top_right: Array[Dictionary] = []
	var side_left: Array[Dictionary] = []
	var side_right: Array[Dictionary] = []
	var all_candidates: Array[Dictionary] = []
	var center: Vector2i = hero_room.get_center()

	for x: int in range(hero_room.position.x + 1, hero_room.end.x - 1):
		var top_cell: Vector2i = Vector2i(x, hero_room.position.y)
		if _walls.get_cell_atlas_coords(top_cell) in TileClassifier.WALL_TOP_VARIANTS:
			var entry: Dictionary = {&"cell": top_cell, &"atlas": TileClassifier.TORCH_TOP, &"alt": 0}
			all_candidates.append(entry)
			if x < center.x:
				top_left.append(entry)
			else:
				top_right.append(entry)

	for y: int in range(hero_room.position.y + 2, hero_room.end.y - 1):
		var left_wall: Vector2i = Vector2i(hero_room.position.x - 1, y)
		var left_floor: Vector2i = Vector2i(hero_room.position.x, y)
		if _walls.get_cell_atlas_coords(left_wall) in TileClassifier.WALL_LEFT_VARIANTS and _walls.get_cell_source_id(left_floor) == -1:
			var entry_l: Dictionary = {&"cell": left_floor, &"atlas": TileClassifier.TORCH_SIDE, &"alt": 0}
			all_candidates.append(entry_l)
			if y >= center.y:
				side_left.append(entry_l)

		var right_wall: Vector2i = Vector2i(hero_room.end.x, y)
		var right_floor: Vector2i = Vector2i(hero_room.end.x - 1, y)
		if _walls.get_cell_atlas_coords(right_wall) in TileClassifier.WALL_RIGHT_VARIANTS and _walls.get_cell_source_id(right_floor) == -1:
			var entry_r: Dictionary = {
				&"cell": right_floor,
				&"atlas": TileClassifier.TORCH_SIDE,
				&"alt": TileClassifier.TORCH_RIGHT_ALT_ID,
			}
			all_candidates.append(entry_r)
			if y >= center.y:
				side_right.append(entry_r)

	var chosen: Array[Dictionary] = []
	var buckets: Array[Array] = [top_left, top_right, side_left, side_right]
	for bucket: Array in buckets:
		if not bucket.is_empty():
			var pick: Dictionary = bucket[int(float(bucket.size()) * 0.5)]
			chosen.append(pick)

	all_candidates.shuffle()
	for cand: Dictionary in all_candidates:
		if chosen.size() >= SECRET_TORCH_COUNT:
			break
		var cand_cell: Vector2i = cand[&"cell"]
		var too_close: bool = false
		for existing: Dictionary in chosen:
			var ex_cell: Vector2i = existing[&"cell"]
			if cand_cell.distance_squared_to(ex_cell) < 16:
				too_close = true
				break
		if not too_close:
			chosen.append(cand)

	for torch_info: Dictionary in chosen:
		var cell: Vector2i = torch_info[&"cell"]
		var atlas: Vector2i = torch_info[&"atlas"]
		var alt: int = torch_info[&"alt"]
		_decorations.set_cell(cell, TileClassifier.TILE_SET_SOURCE_ID, atlas, alt)
		var chunk_coord: Vector2i = MapStreamer.cell_to_chunk(cell)
		var world_pos: Vector2 = _decorations.map_to_local(cell)
		light_manager.add_light(chunk_coord, cell, world_pos)
		_secret_torch_cells.append(cell)

	_secret_torch_cells.shuffle()
	if not _secret_torch_cells.is_empty():
		light_manager.set_light_blinking(_secret_torch_cells[0], true)


func _is_corner_cell(cell: Vector2i) -> bool:
	if _walls.get_cell_source_id(cell) != -1:
		return false
	var wall_n: bool = _walls.get_cell_source_id(cell + Vector2i(0, -1)) != -1
	var wall_s: bool = _walls.get_cell_source_id(cell + Vector2i(0, 1)) != -1
	var wall_w: bool = _walls.get_cell_source_id(cell + Vector2i(-1, 0)) != -1
	var wall_e: bool = _walls.get_cell_source_id(cell + Vector2i(1, 0)) != -1
	return (wall_n and wall_w) or (wall_n and wall_e) or (wall_s and wall_w) or (wall_s and wall_e)


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
				if plan.is_spike_cell(cell):
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
				_decorations.set_cell(cell, TileClassifier.TILE_SET_SOURCE_ID, prop_tile)

		# Skulls and bones in rooms
		var bones_count: int = clampi(int(float(room.size.x * room.size.y) * 0.025), 1, 4)
		var bones_placed: int = 0
		for cell: Vector2i in floor_cells:
			if bones_placed >= bones_count:
				break
			if _decorations.get_cell_source_id(cell) != -1:
				continue
			var bone_tile: Vector2i = _pick_random_tile(PROP_SKULLS_AND_BONES)
			_decorations.set_cell(cell, TileClassifier.TILE_SET_SOURCE_ID, bone_tile)
			bones_placed += 1
