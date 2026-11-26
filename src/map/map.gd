# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Map
extends Node2D

signal generation_progress_updated(progress: float)
signal secret_torches_completed
signal door_unlocked(gate: SectorGatePlanner.SectorGate)
signal locked_door_bumped(color: WorldPlan.KeyColor)
signal shortcut_opened(color: WorldPlan.KeyColor)
signal event_room_armed(room: Rect2i)
signal event_room_disarmed(room: Rect2i)

const ROOM_PADDING: int = 8
const EXPAND_TRIGGER_DISTANCE_TILES: float = 75.0
const SECRET_TORCH_COUNT: int = 4
const SECRET_TORCH_TRIGGER_DIST_SQ: float = 28.0 * 28.0
const LEVER_TRIGGER_DIST_SQ: float = 18.0 * 18.0
const DOOR_TRIGGER_DIST_SQ: float = 26.0 * 26.0
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
const SHORTCUT_TILE_BATCH_SIZE: int = 64
const SHORTCUT_IMMEDIATE_RADIUS_SQ: int = 64

var plan: WorldPlan = WorldPlan.new()
var streamer: MapStreamer = MapStreamer.new()
var hero_room: Rect2i = Rect2i()
var companion_rooms: Array[Rect2i] = []

var nav_window: NavWindow = NavWindow.new()
var _walkable_cells: Dictionary[Vector2i, bool] = {}
var _loaded_spikes: Dictionary[Vector2i, int] = {}
var _group_frames: Array[int] = [0, 0, 0, 0]
var _spike_elapsed: float = 0.0
var _expanded_rooms: Dictionary[Rect2i, bool] = {}
var _secret_torch_cells: Array[Vector2i] = []
var _secret_torch_index: int = 0
var _guaranteed_coin_room: Rect2i = Rect2i()
var _guaranteed_potion_room: Rect2i = Rect2i()
var _is_activating_lever: bool = false
var _locked_door_toast_timer: float = 0.0
var _pending_shortcut_floors: Array[Vector2i] = []
var _pending_shortcut_floor_atlas: Array[Vector2i] = []
var _pending_shortcut_erased_walls: Array[Vector2i] = []
var _pending_shortcut_walls: Array[Vector2i] = []
var _pending_shortcut_wall_atlas: Array[Vector2i] = []
var _pending_shortcut_gate: SectorGatePlanner.SectorGate = null
var _pending_shortcut_chunks: Array[Vector2i] = []

@onready var light_manager: LightManager = $Lights
@onready var _floor: TileMapLayer = $Floor
@onready var _walls: TileMapLayer = $Walls
@onready var _decorations: TileMapLayer = $Decorations
@onready var _shortcut_effect: Node2D = $ShortcutEffect
@onready var _shortcut_left_wall: Sprite2D = $ShortcutEffect/LeftWall
@onready var _shortcut_right_wall: Sprite2D = $ShortcutEffect/RightWall
@onready var _shortcut_dust: CPUParticles2D = $ShortcutEffect/DustParticles


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
	_walls.clear()
	_decorations.clear()
	light_manager.clear()
	companion_rooms.clear()
	_walkable_cells.clear()
	_loaded_spikes.clear()
	_group_frames = [0, 0, 0, 0]
	_spike_elapsed = 0.0
	_expanded_rooms.clear()
	_is_activating_lever = false
	_locked_door_toast_timer = 0.0
	_shortcut_effect.visible = false

	plan.generate()
	hero_room = plan.hero_room
	_expanded_rooms[hero_room] = true

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

	SectorGatePlanner.prebake_shortcut_tunnels(plan, chunk_raster)
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
	for hazard: ClosingSpikeHazard in plan.closing_spike_hazards.values():
		var was_armed: bool = hazard.is_armed
		hazard.update_player_presence(delta, player_cell)
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
	if _is_activating_lever:
		return

	for gate: SectorGatePlanner.SectorGate in plan.sector_gates:
		if gate.has_shortcut and not gate.shortcut_opened and _is_squad_near(squad, _floor.map_to_local(gate.lever_cell), LEVER_TRIGGER_DIST_SQ):
			_activate_shortcut_lever(gate)
			return
		if not gate.door_unlocked:
			var door_center: Vector2 = (_floor.map_to_local(gate.door_cells[0]) + _floor.map_to_local(gate.door_cells[1])) * 0.5 + Vector2(0.0, 8.0)
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
	var left_cell: Vector2i = gate.door_cells[0]
	var right_cell: Vector2i = gate.door_cells[1]
	var top_left: Vector2i = left_cell + Vector2i(0, -1)
	var top_right: Vector2i = right_cell + Vector2i(0, -1)

	var top_l_atlas: Vector2i = TileClassifier.DOOR_OPEN_TOP_LEFT[color_idx]
	var top_r_atlas: Vector2i = TileClassifier.DOOR_OPEN_TOP_RIGHT[color_idx]
	var bot_l_atlas: Vector2i = TileClassifier.DOOR_OPEN_BOTTOM_LEFT[color_idx]
	var bot_r_atlas: Vector2i = TileClassifier.DOOR_OPEN_BOTTOM_RIGHT[color_idx]

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

	Audio.play_sfx(Audio.Sfx.DOOR_UNLOCK)
	door_unlocked.emit(gate)


func _activate_shortcut_lever(gate: SectorGatePlanner.SectorGate) -> void:
	gate.shortcut_opened = true
	_is_activating_lever = true
	_decorations.set_cell(gate.lever_cell, TileClassifier.TILE_SET_SOURCE_ID, TileClassifier.LEVER_OPEN, 0)
	_update_baked_decoration_cell(gate.lever_cell, TileClassifier.LEVER_OPEN, 0)

	var w_left: Vector2i = gate.shortcut_wall_cells[0]
	var w_right: Vector2i = gate.shortcut_wall_cells[1]
	var f_left: Vector2i = gate.shortcut_flank_cells[0]
	var f_right: Vector2i = gate.shortcut_flank_cells[1]

	for c: Vector2i in [w_left, w_right, f_left, f_right]:
		plan.closed_shortcut_walls.erase(c)

	var atlas_l: Vector2i = _walls.get_cell_atlas_coords(w_left)
	if atlas_l.x < 0:
		atlas_l = TileClassifier.get_wall_top_for_cell(plan.run_seed, w_left, plan.get_cell_tile_set(w_left))
	var atlas_r: Vector2i = _walls.get_cell_atlas_coords(w_right)
	if atlas_r.x < 0:
		atlas_r = TileClassifier.get_wall_top_for_cell(plan.run_seed, w_right, plan.get_cell_tile_set(w_right))

	_shortcut_left_wall.region_rect = Rect2(Vector2(atlas_l * 16), Vector2(16, 16))
	_shortcut_right_wall.region_rect = Rect2(Vector2(atlas_r * 16), Vector2(16, 16))
	_shortcut_effect.position = (_floor.map_to_local(w_left) + _floor.map_to_local(w_right)) * 0.5
	_shortcut_left_wall.position = Vector2(-8.0, 0.0)
	_shortcut_left_wall.scale = Vector2.ONE
	_shortcut_left_wall.modulate = Color.WHITE
	_shortcut_right_wall.position = Vector2(8.0, 0.0)
	_shortcut_right_wall.scale = Vector2.ONE
	_shortcut_right_wall.modulate = Color.WHITE
	_shortcut_effect.modulate = Color.WHITE
	_shortcut_effect.visible = true

	_apply_shortcut_tiles(gate)

	Audio.play_sfx(Audio.Sfx.SHORTCUT_OPEN)
	shortcut_opened.emit(gate.color)

	get_tree().paused = true
	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_shortcut_effect, ^"modulate", Color(2.2, 2.2, 2.2, 1.0), 0.12)
	tween.parallel().tween_property(_shortcut_left_wall, ^"position:x", -10.0, 0.06)
	tween.parallel().tween_property(_shortcut_right_wall, ^"position:x", 10.0, 0.06)
	tween.tween_property(_shortcut_left_wall, ^"position:x", -6.0, 0.06)
	tween.parallel().tween_property(_shortcut_right_wall, ^"position:x", 6.0, 0.06)
	tween.tween_callback(_shortcut_dust.restart)
	tween.tween_property(_shortcut_left_wall, ^"position", Vector2(-12.0, -4.0), 0.45)
	tween.parallel().tween_property(_shortcut_left_wall, ^"scale", Vector2(0.2, 0.2), 0.45)
	tween.parallel().tween_property(_shortcut_left_wall, ^"modulate:a", 0.0, 0.45)
	tween.parallel().tween_property(_shortcut_right_wall, ^"position", Vector2(12.0, -4.0), 0.45)
	tween.parallel().tween_property(_shortcut_right_wall, ^"scale", Vector2(0.2, 0.2), 0.45)
	tween.parallel().tween_property(_shortcut_right_wall, ^"modulate:a", 0.0, 0.45)
	tween.tween_interval(0.15)
	tween.finished.connect(_on_shortcut_effect_finished.bind(gate))
	var tile_tween: Tween = create_tween()
	tile_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tile_tween.tween_method(_step_shortcut_tile_batch, 0.0, 1.0, 0.65)


func _on_shortcut_effect_finished(gate: SectorGatePlanner.SectorGate) -> void:
	_shortcut_effect.visible = false
	_flush_shortcut_tile_batches()
	_apply_shortcut_walkable(gate)

	_is_activating_lever = false
	get_tree().paused = false


func _step_shortcut_tile_batch(_progress: float) -> void:
	if not _pending_shortcut_chunks.is_empty():
		var coord: Vector2i = _pending_shortcut_chunks.pop_back()
		_process_one_pending_shortcut_chunk(coord)
	_drain_shortcut_tile_ops(SHORTCUT_TILE_BATCH_SIZE)


func _flush_shortcut_tile_batches() -> void:
	while not _pending_shortcut_chunks.is_empty():
		var coord: Vector2i = _pending_shortcut_chunks.pop_back()
		_process_one_pending_shortcut_chunk(coord)
	_pending_shortcut_gate = null
	_drain_shortcut_tile_ops(-1)


func _drain_shortcut_tile_ops(budget: int) -> void:
	var unlimited: bool = budget < 0
	var remaining: int = budget
	while (unlimited or remaining > 0) and not _pending_shortcut_erased_walls.is_empty():
		var ecell: Vector2i = _pending_shortcut_erased_walls.pop_back()
		_walls.erase_cell(ecell)
		remaining -= 1
	while (unlimited or remaining > 0) and not _pending_shortcut_floors.is_empty():
		var fcell: Vector2i = _pending_shortcut_floors.pop_back()
		var fatlas: Vector2i = _pending_shortcut_floor_atlas.pop_back()
		_floor.set_cell(fcell, TileClassifier.TILE_SET_SOURCE_ID, fatlas)
		remaining -= 1
	while (unlimited or remaining > 0) and not _pending_shortcut_walls.is_empty():
		var wcell: Vector2i = _pending_shortcut_walls.pop_back()
		var watlas: Vector2i = _pending_shortcut_wall_atlas.pop_back()
		_walls.set_cell(wcell, TileClassifier.TILE_SET_SOURCE_ID, watlas, 0)
		remaining -= 1


func _process_one_pending_shortcut_chunk(coord: Vector2i) -> void:
	var diff: Dictionary = _pending_shortcut_gate.tunnel_chunk_diffs[coord]
	var chunk_floors: Array[Vector2i] = diff[&"floors"]
	var chunk_erased: Dictionary[Vector2i, bool] = diff[&"erased_walls"]
	var chunk_walls: Array[Vector2i] = diff[&"walls"]
	var chunk_spikes: Array[Vector2i] = diff[&"spikes"]
	var chunk_torches: Array[Vector2i] = diff[&"torches"]
	var chunk_erased_torches: Dictionary[Vector2i, bool] = diff[&"erased_torches"]
	var chunk_lights: Array[Vector2i] = diff[&"lights"]
	var chunk_erased_lights: Dictionary[Vector2i, bool] = diff[&"erased_lights"]
	if streamer.is_chunk_loaded(coord):
		for scell: Vector2i in chunk_spikes:
			_loaded_spikes[scell] = plan.get_spike_group(scell)
		for etcell: Vector2i in chunk_erased_torches:
			_decorations.erase_cell(etcell)
		for tcell: Vector2i in chunk_torches:
			var tatlas: Vector2i = _pending_shortcut_gate.tunnel_torches[tcell]
			var talt: int = _pending_shortcut_gate.tunnel_torch_alt_ids[tcell]
			_decorations.set_cell(tcell, TileClassifier.TILE_SET_SOURCE_ID, tatlas, talt)
		for elcell: Vector2i in chunk_erased_lights:
			light_manager.remove_light_at(elcell)
		for lcell: Vector2i in chunk_lights:
			if not light_manager.has_light(lcell):
				light_manager.add_light(coord, lcell, _decorations.map_to_local(lcell))
		var anchor_cell: Vector2i = _pending_shortcut_gate.shortcut_wall_cells[0]
		_apply_or_queue_loaded_shortcut_chunk(chunk_floors, chunk_erased, chunk_walls, _pending_shortcut_gate, anchor_cell)
	if plan.baked_chunks.has(coord):
		var data: Dictionary = plan.baked_chunks[coord]
		_apply_chunk_baked_floors(data, chunk_floors, _pending_shortcut_gate.tunnel_floors)
		_apply_chunk_baked_walls(data, chunk_erased, chunk_walls, _pending_shortcut_gate.tunnel_walls)
		_apply_chunk_baked_spikes(data, chunk_spikes)
		ShortcutTunnelPlanner.apply_baked_chunk_torches_and_lights(data, diff, _pending_shortcut_gate)
		streamer.sync_loaded_chunk_arrays(coord, data)


func _apply_shortcut_tiles(gate: SectorGatePlanner.SectorGate) -> void:
	_flush_shortcut_tile_batches()
	_pending_shortcut_gate = gate
	var anchor_cell: Vector2i = gate.shortcut_wall_cells[0]
	var min_c: Vector2i = MapStreamer.cell_to_chunk(anchor_cell - Vector2i(8, 8))
	var max_c: Vector2i = MapStreamer.cell_to_chunk(anchor_cell + Vector2i(8, 8))
	for coord: Vector2i in gate.tunnel_chunk_diffs:
		if coord.x >= min_c.x and coord.x <= max_c.x and coord.y >= min_c.y and coord.y <= max_c.y:
			_process_one_pending_shortcut_chunk(coord)
		else:
			_pending_shortcut_chunks.append(coord)


func _apply_or_queue_loaded_shortcut_chunk(
	chunk_floors: Array[Vector2i],
	chunk_erased: Dictionary[Vector2i, bool],
	chunk_walls: Array[Vector2i],
	gate: SectorGatePlanner.SectorGate,
	anchor_cell: Vector2i,
) -> void:
	for fcell: Vector2i in chunk_floors:
		var fatlas: Vector2i = gate.tunnel_floors[fcell]
		if _loaded_spikes.has(fcell):
			var group_id: int = _loaded_spikes[fcell]
			if group_id >= 0 and group_id < _group_frames.size():
				var tile_set: int = plan.spike_tile_sets.get(fcell, 1)
				fatlas = TileClassifier.get_spike_frame(_group_frames[group_id], tile_set)
		if fcell.distance_squared_to(anchor_cell) <= SHORTCUT_IMMEDIATE_RADIUS_SQ:
			_floor.set_cell(fcell, TileClassifier.TILE_SET_SOURCE_ID, fatlas)
		else:
			_pending_shortcut_floors.append(fcell)
			_pending_shortcut_floor_atlas.append(fatlas)
	for ecell: Vector2i in chunk_erased:
		if ecell.distance_squared_to(anchor_cell) <= SHORTCUT_IMMEDIATE_RADIUS_SQ:
			_walls.erase_cell(ecell)
		else:
			_pending_shortcut_erased_walls.append(ecell)
	for wcell: Vector2i in chunk_walls:
		var watlas: Vector2i = gate.tunnel_walls[wcell]
		if wcell.distance_squared_to(anchor_cell) <= SHORTCUT_IMMEDIATE_RADIUS_SQ:
			_walls.set_cell(wcell, TileClassifier.TILE_SET_SOURCE_ID, watlas, 0)
		else:
			_pending_shortcut_walls.append(wcell)
			_pending_shortcut_wall_atlas.append(watlas)


static func _apply_chunk_baked_floors(
	data: Dictionary,
	chunk_floors: Array[Vector2i],
	tunnel_floors: Dictionary[Vector2i, Vector2i],
) -> void:
	if chunk_floors.is_empty():
		return
	var floors: Array[Vector2i] = data[&"floors"]
	var floor_atlas: Array[Vector2i] = data[&"floor_atlas"]
	var index_by_cell: Dictionary[Vector2i, int] = {}
	for i: int in range(floors.size()):
		index_by_cell[floors[i]] = i
	for fcell: Vector2i in chunk_floors:
		var fatlas: Vector2i = tunnel_floors[fcell]
		if index_by_cell.has(fcell):
			floor_atlas[index_by_cell[fcell]] = fatlas
		else:
			index_by_cell[fcell] = floors.size()
			floors.append(fcell)
			floor_atlas.append(fatlas)


static func _apply_chunk_baked_walls(
	data: Dictionary,
	chunk_erased: Dictionary[Vector2i, bool],
	chunk_walls: Array[Vector2i],
	tunnel_walls: Dictionary[Vector2i, Vector2i],
) -> void:
	var walls: Array[Vector2i] = data[&"walls"]
	var wall_atlas: Array[Vector2i] = data[&"wall_atlas"]
	var wall_alt_ids: Array[int] = data[&"wall_alt_ids"]

	if not chunk_erased.is_empty():
		var write_idx: int = 0
		for read_idx: int in range(walls.size()):
			var wcell: Vector2i = walls[read_idx]
			if chunk_erased.has(wcell):
				continue
			if write_idx != read_idx:
				walls[write_idx] = wcell
				wall_atlas[write_idx] = wall_atlas[read_idx]
				wall_alt_ids[write_idx] = wall_alt_ids[read_idx]
			write_idx += 1
		if write_idx < walls.size():
			walls.resize(write_idx)
			wall_atlas.resize(write_idx)
			wall_alt_ids.resize(write_idx)

	if chunk_walls.is_empty():
		return
	var index_by_cell: Dictionary[Vector2i, int] = {}
	for i: int in range(walls.size()):
		index_by_cell[walls[i]] = i
	for wcell: Vector2i in chunk_walls:
		var watlas: Vector2i = tunnel_walls[wcell]
		if index_by_cell.has(wcell):
			var idx: int = index_by_cell[wcell]
			wall_atlas[idx] = watlas
			wall_alt_ids[idx] = 0
		else:
			index_by_cell[wcell] = walls.size()
			walls.append(wcell)
			wall_atlas.append(watlas)
			wall_alt_ids.append(0)


static func _apply_chunk_baked_spikes(data: Dictionary, chunk_spikes: Array[Vector2i]) -> void:
	if chunk_spikes.is_empty():
		return
	var spikes: Array[Vector2i] = data[&"spikes"]
	var existing: Dictionary[Vector2i, bool] = {}
	for scell: Vector2i in spikes:
		existing[scell] = true
	for scell: Vector2i in chunk_spikes:
		if not existing.has(scell):
			existing[scell] = true
			spikes.append(scell)


func _apply_shortcut_walkable(gate: SectorGatePlanner.SectorGate) -> void:
	for coord: Vector2i in gate.tunnel_chunk_diffs:
		var diff: Dictionary = gate.tunnel_chunk_diffs[coord]
		var chunk_cells: Array[Vector2i] = diff[&"walkable"]
		if chunk_cells.is_empty():
			continue
		for cell: Vector2i in chunk_cells:
			_walkable_cells[cell] = true
			nav_window.set_cell_walkable(cell, true)
		if not plan.baked_chunks.has(coord):
			streamer.add_loaded_chunk_walkable(coord, chunk_cells)
			continue
		var data: Dictionary = plan.baked_chunks[coord]
		var walk_arr: Array[Vector2i] = data[&"walkable"]
		var existing: Dictionary[Vector2i, bool] = {}
		for wcell: Vector2i in walk_arr:
			existing[wcell] = true
		for cell: Vector2i in chunk_cells:
			if not existing.has(cell):
				existing[cell] = true
				walk_arr.append(cell)
		data[&"walkable_rects"] = TileClassifier.build_walkable_rects(coord, walk_arr)
		streamer.sync_loaded_chunk_arrays(coord, data)


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


func get_room_pickups(room: Rect2i, include_event_reward: bool = false) -> Dictionary:
	var coins: Array[Vector2] = []
	var potions: Array[Dictionary] = []
	if room == hero_room or room.size.x < 8 or room.size.y < 8:
		return {&"coins": coins, &"potions": potions}

	if plan.is_event_room(room):
		if include_event_reward:
			var center_world: Vector2 = _floor.map_to_local(room.get_center())
			coins.append(clamp_to_walkable(center_world + Vector2(-12.0, 0.0)))
			var potion_pos: Vector2 = clamp_to_walkable(center_world + Vector2(12.0, 0.0))
			potions.append({&"pos": potion_pos, &"type": _roll_potion_type(room, 37, 71)})
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
