# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Map
extends Node2D

signal generation_progress_updated(progress: float)
signal secret_torches_completed
signal door_unlocked(gate: SectorGatePlanner.SectorGate)
signal locked_door_bumped(color: WorldPlan.KeyColor)
signal shortcut_opened(shortcut: ShortcutTunnelPlanner.LocalShortcut)
signal event_room_armed(room: Rect2i)
signal event_room_disarmed(room: Rect2i)

const ROOM_PADDING: int = 8
const EXPAND_TRIGGER_DISTANCE_TILES: float = 75.0
const SECRET_TORCH_COUNT: int = 4
const SECRET_TORCH_TRIGGER_DIST_SQ: float = 28.0 * 28.0
const LEVER_TRIGGER_DIST_SQ: float = 18.0 * 18.0
const DOOR_TRIGGER_DIST_SQ: float = 30.0 * 30.0
const LOCKED_DOOR_TOAST_COOLDOWN: float = 3.0
const SPIKE_STAY_DOWN_TIME: float = 2.00
const SPIKE_UP_1_TIME: float = 0.40
const SPIKE_UP_2_TIME: float = 0.10
const SPIKE_STAY_UP_TIME: float = 1.10
const SPIKE_DOWN_2_TIME: float = 0.10
const SPIKE_DOWN_1_TIME: float = 0.10
const SPIKE_CYCLE_DURATION: float = 3.80
const COIN_ROOM_CHANCE: float = 0.30
const POTION_ROOM_CHANCE: float = 0.30
const SHORTCUT_WALL_SCENE: PackedScene = preload("res://map/shortcut_wall.tscn")

var plan: WorldPlan = WorldPlan.new()
var streamer: MapStreamer = MapStreamer.new()
var hero_room: Rect2i = Rect2i()
var companion_rooms: Array[Rect2i] = []

var nav_window: NavWindow = NavWindow.new()
var barriers: RoomBarrierManager = RoomBarrierManager.new()
var active_event_safe_world_rect: Rect2 = Rect2()
var active_event_room: Rect2i = Rect2i()
var _walkable_cells: Dictionary[Vector2i, bool] = {}
var _loaded_spikes: Dictionary[Vector2i, int] = {}
var _group_frames: Array[int] = [0, 0, 0, 0]
var _spike_elapsed: float = 0.0
var _expanded_rooms: Dictionary[Rect2i, bool] = {}
var _secret_torch_cells: Array[Vector2i] = []
var _secret_torch_index: int = 0
var _guaranteed_coin_room: Rect2i = Rect2i()
var _guaranteed_potion_room: Rect2i = Rect2i()
var _locked_door_toast_timer: float = 0.0
var _shortcut_walls: Dictionary[int, ShortcutWall] = {}
var _cached_event_safe_cells: Rect2i = Rect2i()

@onready var light_manager: LightManager = $Lights
@onready var _floor: TileMapLayer = $Floor
@onready var _walls: TileMapLayer = $Walls
@onready var _decorations: TileMapLayer = $Decorations
@onready var _shortcut_walls_container: Node2D = $ShortcutWalls


func _exit_tree() -> void:
	Hero.active_hazard_safe_rect = Rect2()


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
	if plan.is_event_room(room):
		return []
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
	if plan.closing_spike_hazards.has(room):
		var safe: Rect2i = plan.closing_spike_hazards[room].safe_rect
		min_x = safe.position.x
		max_x = safe.end.x - 1
		min_y = safe.position.y
		max_y = safe.end.y - 1

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
		if cell.distance_squared_to(center) >= 2 and is_cell_walkable(cell):
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
	var closest_cell: Vector2i = nav_window.find_closest_walkable_cell(cell)
	return _floor.map_to_local(closest_cell)


func get_navigation_path(from_pos: Vector2, to_pos: Vector2) -> PackedVector2Array:
	return nav_window.get_path(from_pos, to_pos)


func is_in_nav_bounds(world_pos: Vector2) -> bool:
	return nav_window.is_in_bounds(_floor.local_to_map(world_pos))


func generate_map() -> void:
	generation_progress_updated.emit(0.15)
	await get_tree().process_frame

	_floor.clear()
	_cached_event_safe_cells = Rect2i()
	active_event_safe_world_rect = Rect2()
	active_event_room = Rect2i()
	Hero.active_hazard_safe_rect = Rect2()
	_walls.clear()
	_decorations.clear()
	light_manager.clear()
	companion_rooms.clear()
	_walkable_cells.clear()
	_loaded_spikes.clear()
	_group_frames = [0, 0, 0, 0]
	_spike_elapsed = 0.0
	_expanded_rooms.clear()
	_locked_door_toast_timer = 0.0
	_shortcut_walls.clear()
	barriers.clear()
	for child: Node in _shortcut_walls_container.get_children():
		child.queue_free()

	plan.generate()
	hero_room = plan.hero_room
	_expanded_rooms[hero_room] = true

	for sc: ShortcutTunnelPlanner.LocalShortcut in plan.local_shortcuts:
		var wall: ShortcutWall = SHORTCUT_WALL_SCENE.instantiate() as ShortcutWall
		wall.position = (_floor.map_to_local(sc.door_cells[0]) + _floor.map_to_local(sc.door_cells[1])) * 0.5
		_shortcut_walls_container.add_child(wall)
		wall.setup(sc.is_horizontal_door, plan.get_cell_tile_set(sc.door_cells[0]))
		_shortcut_walls[sc.id] = wall

	barriers.build_for_ambushes(plan, _floor, _shortcut_walls_container, SHORTCUT_WALL_SCENE)

	var depth_1_rooms: Array[Rect2i] = plan.get_depth_rooms(1)
	companion_rooms.append_array(depth_1_rooms)
	_guaranteed_coin_room = Rect2i()
	_guaranteed_potion_room = Rect2i()
	if not depth_1_rooms.is_empty():
		var pick_idx: int = TileClassifier.cell_hash(plan.run_seed, 71, 97) % depth_1_rooms.size()
		_guaranteed_coin_room = depth_1_rooms[pick_idx]
		var potion_pick_idx: int = TileClassifier.cell_hash(plan.run_seed, 113, 59) % depth_1_rooms.size()
		if depth_1_rooms.size() > 1 and depth_1_rooms[potion_pick_idx] == _guaranteed_coin_room:
			potion_pick_idx = (potion_pick_idx + 1) % depth_1_rooms.size()
		_guaranteed_potion_room = depth_1_rooms[potion_pick_idx]

	generation_progress_updated.emit(0.20)
	await get_tree().process_frame

	var all_chunks: Array[Vector2i] = ChunkRaster.collect_chunk_coords(plan, MapStreamer.CHUNK_SIZE)
	var chunk_raster: ChunkRaster = ChunkRaster.new()
	var total_chunks: int = all_chunks.size()
	var slice_start_usec: int = Time.get_ticks_usec()
	for i: int in range(total_chunks):
		TileClassifier.bake_chunk(all_chunks[i], chunk_raster, plan)
		if (Time.get_ticks_usec() - slice_start_usec) >= 12000:
			var pct: float = lerpf(0.20, 0.72, float(i + 1) / float(maxi(1, total_chunks)))
			generation_progress_updated.emit(pct)
			await get_tree().process_frame
			slice_start_usec = Time.get_ticks_usec()

	generation_progress_updated.emit(0.75)
	await get_tree().process_frame

	nav_window.setup(_walkable_cells, _floor, streamer)
	light_manager.setup(plan.run_seed)
	light_manager.set_focus(get_hero_spawn_position())
	streamer.setup(plan, _floor, _walls, _decorations, light_manager, nav_window, _walkable_cells, _loaded_spikes, _group_frames, plan.run_seed)
	nav_window.update_center(hero_room.get_center())

	generation_progress_updated.emit(0.82)
	await get_tree().process_frame

	var start_bounds: Rect2i = hero_room
	for r: Rect2i in depth_1_rooms:
		start_bounds = start_bounds.merge(r)
	streamer.materialize_rect_immediate(start_bounds.grow(ROOM_PADDING))

	_setup_secret_torches()

	generation_progress_updated.emit(0.90)
	await get_tree().process_frame


func update_streaming(player_world_pos: Vector2, player_velocity: Vector2) -> void:
	streamer.update(player_world_pos, player_velocity)
	light_manager.set_focus(player_world_pos)
	_check_secret_torch_proximity(player_world_pos)


func update_spikes(delta: float, player_cell: Vector2i = Vector2i(2147483647, 2147483647)) -> void:
	_update_event_hazards(delta, player_cell)
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
			var tile_set: int = plan.spike_tile_sets.get(cell, 1)
			_floor.set_cell(cell, TileClassifier.TILE_SET_SOURCE_ID, TileClassifier.get_spike_frame(frame_idx, tile_set))


func is_spike_active_at(cell: Vector2i) -> bool:
	if plan.event_spike_cell_rooms.has(cell):
		var event_room: Rect2i = plan.event_spike_cell_rooms[cell]
		var hazard: ClosingSpikeHazard = plan.closing_spike_hazards.get(event_room, null)
		if hazard != null and hazard.is_cell_active(cell):
			return true
	if not _loaded_spikes.has(cell):
		return false
	var group_id: int = _loaded_spikes[cell]
	return group_id >= 0 and group_id < _group_frames.size() and _group_frames[group_id] == 3


func _update_event_hazards(delta: float, player_cell: Vector2i) -> void:
	if player_cell.x == 2147483647:
		return
	var next_safe_cells: Rect2i = Rect2i()
	var next_event_room: Rect2i = Rect2i()
	for hazard: ClosingSpikeHazard in plan.closing_spike_hazards.values():
		var was_armed: bool = hazard.is_armed
		hazard.update_player_presence(delta, player_cell)
		if hazard.is_armed and not hazard.is_cleared and hazard.room.has_point(player_cell):
			next_event_room = hazard.room
			active_event_room = hazard.room
		if not was_armed and hazard.is_armed:
			event_room_armed.emit(hazard.room)
		elif was_armed and not hazard.is_armed:
			event_room_disarmed.emit(hazard.room)
		var result: Dictionary = hazard.update(delta)
		if result[&"telegraph_started"]:
			Audio.play_sfx(Audio.Sfx.TELEGRAPH)
		if result[&"snapped_active"]:
			Audio.play_sfx(Audio.Sfx.SPIKE_TRAP)
		var changed_rings: Array[int] = result[&"changed_rings"]
		for ring_idx: int in changed_rings:
			_apply_event_spike_ring(hazard, ring_idx)
		if hazard.is_armed and not hazard.is_cleared and hazard.room.has_point(player_cell):
			next_safe_cells = hazard.get_active_safe_rect()
	var locked_room: Rect2i = barriers.get_locked_room()
	active_event_room = next_event_room if next_event_room != Rect2i() else locked_room

	if next_safe_cells != _cached_event_safe_cells:
		_cached_event_safe_cells = next_safe_cells
		if next_safe_cells.size == Vector2i.ZERO:
			active_event_safe_world_rect = Rect2()
		else:
			var min_pt: Vector2 = _floor.map_to_local(next_safe_cells.position)
			var max_pt: Vector2 = _floor.map_to_local(next_safe_cells.end - Vector2i.ONE)
			active_event_safe_world_rect = Rect2(min_pt, max_pt - min_pt).grow(4.0)
		Hero.active_hazard_safe_rect = active_event_safe_world_rect


func _apply_event_spike_ring(hazard: ClosingSpikeHazard, ring_idx: int) -> void:
	var ring: ClosingSpikeHazard.SpikeRing = hazard.rings[ring_idx]
	for cell: Vector2i in ring.cells:
		if _walkable_cells.has(cell):
			var tile_set: int = plan.spike_tile_sets.get(cell, 1)
			_floor.set_cell(cell, TileClassifier.TILE_SET_SOURCE_ID, TileClassifier.get_blood_spike_frame(ring.frame, tile_set))


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


func update_gates(squad: Array[Hero], collected_keys: Dictionary[WorldPlan.KeyColor, bool], delta: float) -> void:
	_locked_door_toast_timer = maxf(0.0, _locked_door_toast_timer - delta)

	for shortcut: ShortcutTunnelPlanner.LocalShortcut in plan.local_shortcuts:
		if not shortcut.opened and _is_squad_near(squad, _floor.map_to_local(shortcut.lever_cell), LEVER_TRIGGER_DIST_SQ):
			_activate_local_shortcut(shortcut)
			return

	for gate: SectorGatePlanner.SectorGate in plan.sector_gates:
		if not gate.door_unlocked:
			var door_center: Vector2 = (_floor.map_to_local(gate.door_cells[0]) + _floor.map_to_local(gate.door_cells[1])) * 0.5
			if _is_squad_near(squad, door_center, DOOR_TRIGGER_DIST_SQ):
				if collected_keys.has(gate.color):
					_unlock_door(gate)
				elif _locked_door_toast_timer <= 0.0:
					_locked_door_toast_timer = LOCKED_DOOR_TOAST_COOLDOWN
					locked_door_bumped.emit(gate.color)


static func _is_squad_near(squad: Array[Hero], target_pos: Vector2, max_dist_sq: float) -> bool:
	for member: Hero in squad:
		if not member.is_dead and member.global_position.distance_squared_to(target_pos) <= max_dist_sq:
			return true
	return false


func _unlock_door(gate: SectorGatePlanner.SectorGate) -> void:
	gate.door_unlocked = true
	var color_idx: int = int(gate.color)
	if gate.door_face == RoomLayout.Face.NORTH or gate.door_face == RoomLayout.Face.SOUTH:
		var left_cell: Vector2i = gate.door_cells[0]
		var right_cell: Vector2i = gate.door_cells[1]
		_open_horizontal_door_cells(
			left_cell,
			right_cell,
			left_cell + Vector2i(0, -1),
			right_cell + Vector2i(0, -1),
			TileClassifier.DOOR_OPEN_TOP_LEFT[color_idx],
			TileClassifier.DOOR_OPEN_TOP_RIGHT[color_idx],
			TileClassifier.DOOR_OPEN_BOTTOM_LEFT[color_idx],
			TileClassifier.DOOR_OPEN_BOTTOM_RIGHT[color_idx],
		)
	else:
		_open_vertical_door_cells(gate.door_cells[0], gate.door_cells[1])

	Audio.play_sfx(Audio.Sfx.DOOR_UNLOCK)
	door_unlocked.emit(gate)


func _activate_local_shortcut(shortcut: ShortcutTunnelPlanner.LocalShortcut) -> void:
	shortcut.opened = true
	_decorations.set_cell(shortcut.lever_cell, TileClassifier.TILE_SET_SOURCE_ID, TileClassifier.LEVER_OPEN, 0)
	_update_baked_decoration_cell(shortcut.lever_cell, TileClassifier.LEVER_OPEN, 0)

	if _shortcut_walls.has(shortcut.id):
		_shortcut_walls[shortcut.id].open_animated()

	for cell: Vector2i in shortcut.door_cells:
		_walkable_cells[cell] = true
		nav_window.set_cell_walkable(cell, true)
		_set_baked_walkable(cell, true)

	Audio.play_sfx(Audio.Sfx.SHORTCUT_OPEN)
	shortcut_opened.emit(shortcut)


func _open_horizontal_door_cells(
	left_cell: Vector2i,
	right_cell: Vector2i,
	top_left: Vector2i,
	top_right: Vector2i,
	top_l_atlas: Vector2i,
	top_r_atlas: Vector2i,
	bot_l_atlas: Vector2i,
	bot_r_atlas: Vector2i,
) -> void:
	_walls.set_cell(top_left, TileClassifier.TILE_SET_SOURCE_ID, top_l_atlas, 0)
	_walls.set_cell(top_right, TileClassifier.TILE_SET_SOURCE_ID, top_r_atlas, 0)
	_walls.set_cell(left_cell, TileClassifier.TILE_SET_SOURCE_ID, bot_l_atlas, 0)
	_walls.set_cell(right_cell, TileClassifier.TILE_SET_SOURCE_ID, bot_r_atlas, 0)

	_update_baked_wall_cell(top_left, top_l_atlas, 0)
	_update_baked_wall_cell(top_right, top_r_atlas, 0)
	_update_baked_wall_cell(left_cell, bot_l_atlas, 0)
	_update_baked_wall_cell(right_cell, bot_r_atlas, 0)

	for cell: Vector2i in [left_cell, right_cell, top_left, top_right]:
		_walkable_cells[cell] = true
		nav_window.set_cell_walkable(cell, true)
		_set_baked_walkable(cell, true)


func _open_vertical_door_cells(top_cell: Vector2i, bottom_cell: Vector2i) -> void:
	for cell: Vector2i in [top_cell, bottom_cell]:
		_walls.erase_cell(cell)
		_update_baked_wall_cell(cell, Vector2i(-1, -1), 0)
		_walkable_cells[cell] = true
		nav_window.set_cell_walkable(cell, true)
		_set_baked_walkable(cell, true)


func _update_baked_wall_cell(cell: Vector2i, atlas: Vector2i, alt_id: int) -> void:
	var coord: Vector2i = MapStreamer.cell_to_chunk(cell)
	if not plan.baked_chunks.has(coord):
		return
	var data: Dictionary = plan.baked_chunks[coord]
	var walls: Array[Vector2i] = data[&"walls"]
	var wall_atlas: Array[Vector2i] = data[&"wall_atlas"]
	var wall_alt_ids: Array[int] = data[&"wall_alt_ids"]
	var idx: int = walls.find(cell)
	if atlas.x == -1:
		if idx != -1:
			walls.remove_at(idx)
			wall_atlas.remove_at(idx)
			wall_alt_ids.remove_at(idx)
	elif idx != -1:
		wall_atlas[idx] = atlas
		wall_alt_ids[idx] = alt_id
	else:
		walls.append(cell)
		wall_atlas.append(atlas)
		wall_alt_ids.append(alt_id)


func _set_baked_walkable(cell: Vector2i, walkable: bool) -> void:
	var coord: Vector2i = MapStreamer.cell_to_chunk(cell)
	if not plan.baked_chunks.has(coord):
		return
	var data: Dictionary = plan.baked_chunks[coord]
	var walk_arr: Array[Vector2i] = data[&"walkable"]
	if walkable:
		if not walk_arr.has(cell):
			walk_arr.append(cell)
	else:
		walk_arr.erase(cell)
	data[&"walkable_rects"] = TileClassifier.build_walkable_rects(coord, walk_arr)
	streamer.sync_loaded_chunk_arrays(coord, data)


func _update_baked_decoration_cell(cell: Vector2i, atlas: Vector2i, alt_id: int) -> void:
	var coord: Vector2i = MapStreamer.cell_to_chunk(cell)
	if not plan.baked_chunks.has(coord):
		return
	var data: Dictionary = plan.baked_chunks[coord]
	var torches: Array[Vector2i] = data[&"torches"]
	var torch_atlas: Array[Vector2i] = data[&"torch_atlas"]
	var torch_alt_ids: Array[int] = data[&"torch_alt_ids"]
	var idx: int = torches.find(cell)
	if idx != -1:
		torch_atlas[idx] = atlas
		torch_alt_ids[idx] = alt_id


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

	return new_rooms


func _check_secret_torch_proximity(player_world_pos: Vector2) -> void:
	if _secret_torch_index >= _secret_torch_cells.size():
		return

	var target_cell: Vector2i = _secret_torch_cells[_secret_torch_index]
	var torch_world_pos: Vector2 = _decorations.map_to_local(target_cell)
	if player_world_pos.distance_squared_to(torch_world_pos) > SECRET_TORCH_TRIGGER_DIST_SQ:
		return

	_decorations.erase_cell(target_cell)
	light_manager.remove_light_at(target_cell)
	Audio.play_sfx(Audio.Sfx.SECRET_TORCH)
	_secret_torch_index += 1

	if _secret_torch_index < _secret_torch_cells.size():
		light_manager.set_light_blinking(_secret_torch_cells[_secret_torch_index], true)
		return

	secret_torches_completed.emit()


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
		if TileClassifier.is_top_wall(_walls.get_cell_atlas_coords(top_cell)):
			var entry: Dictionary = {&"cell": top_cell, &"atlas": TileClassifier.TORCH_TOP, &"alt": 0}
			all_candidates.append(entry)
			if x < center.x:
				top_left.append(entry)
			else:
				top_right.append(entry)

	for y: int in range(hero_room.position.y + 2, hero_room.end.y - 1):
		var left_wall: Vector2i = Vector2i(hero_room.position.x - 1, y)
		var left_floor: Vector2i = Vector2i(hero_room.position.x, y)
		if TileClassifier.is_left_wall(_walls.get_cell_atlas_coords(left_wall)) and _walls.get_cell_source_id(left_floor) == -1:
			var entry_l: Dictionary = {&"cell": left_floor, &"atlas": TileClassifier.TORCH_SIDE, &"alt": 0}
			all_candidates.append(entry_l)
			if y >= center.y:
				side_left.append(entry_l)

		var right_wall: Vector2i = Vector2i(hero_room.end.x, y)
		var right_floor: Vector2i = Vector2i(hero_room.end.x - 1, y)
		if TileClassifier.is_right_wall(_walls.get_cell_atlas_coords(right_wall)) and _walls.get_cell_source_id(right_floor) == -1:
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


func get_room_pickups(room: Rect2i, include_event_reward: bool = false, drop_anchor: Vector2 = Vector2.INF) -> Dictionary:
	var coins: Array[Vector2] = []
	var potions: Array[Dictionary] = []
	if room == hero_room or room.size.x < 8 or room.size.y < 8:
		return {&"coins": coins, &"potions": potions}

	if plan.is_event_room(room):
		if include_event_reward:
			var base_world: Vector2 = drop_anchor if drop_anchor.is_finite() else _floor.map_to_local(room.get_center())
			var event_type: WorldPlan.RoomEventType = plan.room_event_types.get(room, WorldPlan.RoomEventType.NONE)
			if event_type == WorldPlan.RoomEventType.WAVE_AMBUSH:
				coins.append(_clamp_world_to_room(base_world + Vector2(-18.0, -8.0), room))
				coins.append(_clamp_world_to_room(base_world + Vector2(18.0, -8.0), room))
				potions.append({&"pos": _clamp_world_to_room(base_world + Vector2(-12.0, 10.0), room), &"type": PotionPickup.PotionType.HEALTH})
				potions.append({&"pos": _clamp_world_to_room(base_world + Vector2(12.0, 10.0), room), &"type": _roll_potion_type(room, 53, 89)})
			elif event_type == WorldPlan.RoomEventType.CURSED_OBELISKS:
				coins.append(_clamp_world_to_room(base_world + Vector2(-14.0, -6.0), room))
				potions.append({&"pos": _clamp_world_to_room(base_world + Vector2(14.0, -6.0), room), &"type": PotionPickup.PotionType.HEALTH})
				potions.append({&"pos": _clamp_world_to_room(base_world + Vector2(0.0, 10.0), room), &"type": _roll_potion_type(room, 41, 79)})
			else:
				coins.append(_clamp_world_to_room(base_world + Vector2(-12.0, 0.0), room))
				potions.append({&"pos": _clamp_world_to_room(base_world + Vector2(12.0, 0.0), room), &"type": _roll_potion_type(room, 37, 71)})
		return {&"coins": coins, &"potions": potions}

	var coin_roll: int = TileClassifier.cell_hash(plan.run_seed, room.position.x, room.position.y) % 100
	if room == _guaranteed_coin_room or float(coin_roll) < COIN_ROOM_CHANCE * 100.0:
		var coin_cell: Vector2i = _find_coin_cell_for_room(room)
		if coin_cell.x != 2147483647:
			coins.append(_floor.map_to_local(coin_cell))

	var potion_roll: int = TileClassifier.cell_hash(plan.run_seed, room.position.x + 19, room.position.y + 43) % 100
	if room == _guaranteed_potion_room or float(potion_roll) < POTION_ROOM_CHANCE * 100.0:
		var potion_cell: Vector2i = _find_potion_cell_for_room(room)
		if potion_cell.x != 2147483647:
			potions.append({&"pos": _floor.map_to_local(potion_cell), &"type": _roll_potion_type(room, 13, 29)})

	return {&"coins": coins, &"potions": potions}


func _roll_potion_type(room: Rect2i, seed_x_off: int, seed_y_off: int) -> PotionPickup.PotionType:
	var type_roll: int = TileClassifier.cell_hash(plan.run_seed, room.position.x + seed_x_off, room.position.y + seed_y_off) % 100
	if type_roll < 35:
		return PotionPickup.PotionType.HEALTH
	if type_roll < 55:
		return PotionPickup.PotionType.HASTE
	if type_roll < 75:
		return PotionPickup.PotionType.FURY
	return PotionPickup.PotionType.XP


func _find_coin_cell_for_room(room: Rect2i) -> Vector2i:
	return _find_pickup_cell_for_room(room, 0, Vector2i(2147483647, 2147483647))


func _find_potion_cell_for_room(room: Rect2i) -> Vector2i:
	var coin_cell: Vector2i = _find_coin_cell_for_room(room)
	return _find_pickup_cell_for_room(room, 1009, coin_cell)


func _find_pickup_cell_for_room(room: Rect2i, seed_offset: int, avoid_cell: Vector2i) -> Vector2i:
	var inner: Rect2i = room.grow(-3)
	if inner.size.x <= 0 or inner.size.y <= 0:
		return Vector2i(2147483647, 2147483647)

	var center: Vector2i = room.get_center()
	var companions: Array = plan.get_companion_spawns_for_room(room)
	for attempt: int in range(40):
		var hx: int = TileClassifier.cell_hash(plan.run_seed + seed_offset + attempt * 17, room.position.x, room.position.y)
		var hy: int = TileClassifier.cell_hash(plan.run_seed + seed_offset + attempt * 31, room.end.x, room.end.y)
		var cell: Vector2i = Vector2i(inner.position.x + (hx % inner.size.x), inner.position.y + (hy % inner.size.y))
		if avoid_cell.x != 2147483647 and cell.distance_squared_to(avoid_cell) < 9:
			continue
		if _is_valid_coin_cell(cell, center, companions):
			return cell
	return Vector2i(2147483647, 2147483647)


func _clamp_world_to_room(world_pos: Vector2, room: Rect2i) -> Vector2:
	var inner: Rect2i = room.grow(-2)
	if inner.size.x > 0 and inner.size.y > 0:
		var min_pt: Vector2 = _floor.map_to_local(inner.position)
		var max_pt: Vector2 = _floor.map_to_local(inner.end - Vector2i.ONE)
		world_pos = world_pos.clamp(min_pt, max_pt)
	return clamp_to_walkable(world_pos)


func _is_valid_coin_cell(cell: Vector2i, center: Vector2i, companions: Array) -> bool:
	if cell.distance_squared_to(center) < 16 or plan.has_candle_post_near(cell, 4) or plan.no_prop_cells.has(cell):
		return false
	for comp_var: Variant in companions:
		if comp_var is Vector2i:
			var comp_cell: Vector2i = comp_var
			if cell.distance_squared_to(comp_cell) < 16:
				return false
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if not plan.is_floor(cell + Vector2i(dx, dy)):
				return false
	for dy: int in range(-2, 3):
		for dx: int in range(-2, 3):
			if dx * dx + dy * dy <= 4 and plan.is_spike_cell(cell + Vector2i(dx, dy)):
				return false
	return true
