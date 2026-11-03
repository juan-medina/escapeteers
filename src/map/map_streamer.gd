# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name MapStreamer
extends RefCounted

const CHUNK_SIZE: int = 32
const LOAD_RADIUS: int = 3
const UNLOAD_RADIUS: int = 5
const FRAME_BUDGET_USEC: int = 1500

var _plan: WorldPlan = null
var _floor: TileMapLayer = null
var _walls: TileMapLayer = null
var _decorations: TileMapLayer = null
var _light_manager: LightManager = null
var _nav_window: NavWindow = null
var _walkable_cells: Dictionary[Vector2i, bool] = {}
var _run_seed: int = 0

var _loaded_chunks: Dictionary[Vector2i, Dictionary] = {}
var _load_queue: Array[Vector2i] = []
var _queued_set: Dictionary[Vector2i, bool] = {}
var _raster: ChunkRaster = ChunkRaster.new()
var _last_player_chunk: Vector2i = Vector2i(-999999, -999999)


func setup(
	plan: WorldPlan,
	floor_layer: TileMapLayer,
	walls_layer: TileMapLayer,
	decor_layer: TileMapLayer,
	light_manager: LightManager,
	nav_window: NavWindow,
	walkable_cells: Dictionary[Vector2i, bool],
	run_seed: int
) -> void:
	_plan = plan
	_floor = floor_layer
	_walls = walls_layer
	_decorations = decor_layer
	_light_manager = light_manager
	_nav_window = nav_window
	_walkable_cells = walkable_cells
	_run_seed = run_seed

	_loaded_chunks.clear()
	_load_queue.clear()
	_queued_set.clear()
	_last_player_chunk = Vector2i(-999999, -999999)


func update(player_world_pos: Vector2, player_velocity: Vector2) -> void:
	var player_cell: Vector2i = _floor.local_to_map(player_world_pos)
	var player_chunk: Vector2i = get_chunk_coord(player_cell)

	if _nav_window != null:
		_nav_window.update_center(player_cell)

	if _light_manager != null:
		_light_manager.set_focus(player_world_pos)

	if player_chunk != _last_player_chunk:
		_last_player_chunk = player_chunk
		_queue_chunks_in_radius(player_chunk)
		_evict_distant_chunks(player_chunk)

	if not _load_queue.is_empty():
		_sort_queue(player_chunk, player_velocity)
		_process_queue()


func materialize_rect_immediate(tile_rect: Rect2i) -> void:
	var min_chunk: Vector2i = get_chunk_coord(tile_rect.position)
	var max_chunk: Vector2i = get_chunk_coord(tile_rect.end)

	for cy: int in range(min_chunk.y, max_chunk.y + 1):
		for cx: int in range(min_chunk.x, max_chunk.x + 1):
			var coord: Vector2i = Vector2i(cx, cy)
			if not _loaded_chunks.has(coord):
				_materialize_chunk(coord)


static func cell_to_chunk(cell: Vector2i) -> Vector2i:
	var cx: int = floori(float(cell.x) / float(CHUNK_SIZE))
	var cy: int = floori(float(cell.y) / float(CHUNK_SIZE))
	return Vector2i(cx, cy)


func get_chunk_coord(cell: Vector2i) -> Vector2i:
	return cell_to_chunk(cell)


func is_chunk_loaded(coord: Vector2i) -> bool:
	return _loaded_chunks.has(coord)


func get_loaded_chunk_count() -> int:
	return _loaded_chunks.size()


func get_queued_chunk_count() -> int:
	return _load_queue.size()


func _queue_chunks_in_radius(center_chunk: Vector2i) -> void:
	for dy: int in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dx: int in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var coord: Vector2i = center_chunk + Vector2i(dx, dy)
			if not _loaded_chunks.has(coord) and not _queued_set.has(coord):
				_load_queue.append(coord)
				_queued_set[coord] = true


func _sort_queue(center_chunk: Vector2i, velocity: Vector2) -> void:
	var has_vel: bool = velocity.length_squared() > 1.0
	var move_dir: Vector2 = velocity.normalized() if has_vel else Vector2.ZERO

	_load_queue.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var da: Vector2 = Vector2(a - center_chunk)
			var db: Vector2 = Vector2(b - center_chunk)
			var dist_a: float = da.length()
			var dist_b: float = db.length()

			var score_a: float = dist_a
			var score_b: float = dist_b

			if has_vel:
				if dist_a > 0.001:
					score_a -= da.normalized().dot(move_dir) * 1.5
				if dist_b > 0.001:
					score_b -= db.normalized().dot(move_dir) * 1.5

			return score_a < score_b
	)


func _process_queue() -> void:
	var start_usec: int = Time.get_ticks_usec()
	while not _load_queue.is_empty():
		var coord: Vector2i = _load_queue.pop_front()
		_queued_set.erase(coord)
		_materialize_chunk(coord)

		if (Time.get_ticks_usec() - start_usec) >= FRAME_BUDGET_USEC:
			break


func _materialize_chunk(coord: Vector2i) -> void:
	_raster.rasterize(coord, _plan)

	if not _raster.has_any_content():
		_loaded_chunks[coord] = {
			&"floors": [] as Array[Vector2i],
			&"walls": [] as Array[Vector2i],
			&"torches": [] as Array[Vector2i],
			&"lights": [] as Array[Vector2i],
		}
		return

	var data: Dictionary = TileClassifier.classify_chunk(_raster, _run_seed, _plan)
	var floors: Array[Vector2i] = data[&"floors"]
	var floor_atlas: Array[Vector2i] = data[&"floor_atlas"]
	var walls: Array[Vector2i] = data[&"walls"]
	var wall_atlas: Array[Vector2i] = data[&"wall_atlas"]
	var wall_alt_ids: Array[int] = data[&"wall_alt_ids"]
	var torches: Array[Vector2i] = data[&"torches"]
	var torch_atlas: Array[Vector2i] = data[&"torch_atlas"]
	var torch_alt_ids: Array[int] = data[&"torch_alt_ids"]
	var lights: Array[Vector2i] = data[&"lights"]

	for i: int in range(floors.size()):
		_floor.set_cell(floors[i], TileClassifier.TILE_SET_SOURCE_ID, floor_atlas[i])

	var wall_set: Dictionary[Vector2i, bool] = {}
	for i: int in range(walls.size()):
		var wpos: Vector2i = walls[i]
		_walls.set_cell(wpos, TileClassifier.TILE_SET_SOURCE_ID, wall_atlas[i], wall_alt_ids[i])
		wall_set[wpos] = true

	for i: int in range(torches.size()):
		_decorations.set_cell(torches[i], TileClassifier.TILE_SET_SOURCE_ID, torch_atlas[i], torch_alt_ids[i])

	var spawned_lights: Array[Vector2i] = []
	for lpos: Vector2i in lights:
		if _light_manager != null and not _light_manager.has_light(lpos):
			var world_pos: Vector2 = _decorations.map_to_local(lpos)
			_light_manager.add_light(coord, lpos, world_pos)
			spawned_lights.append(lpos)

	for fpos: Vector2i in floors:
		if not wall_set.has(fpos):
			_walkable_cells[fpos] = true
			if _nav_window != null:
				_nav_window.set_cell_walkable(fpos, true)

	_loaded_chunks[coord] = {
		&"floors": floors,
		&"walls": walls,
		&"torches": torches,
		&"lights": spawned_lights,
	}


func _evict_distant_chunks(center_chunk: Vector2i) -> void:
	var chunks_to_evict: Array[Vector2i] = []
	for coord: Vector2i in _loaded_chunks:
		if absi(coord.x - center_chunk.x) > UNLOAD_RADIUS or absi(coord.y - center_chunk.y) > UNLOAD_RADIUS:
			chunks_to_evict.append(coord)

	for coord: Vector2i in chunks_to_evict:
		_evict_chunk(coord)


func _evict_chunk(coord: Vector2i) -> void:
	var chunk_data: Dictionary = _loaded_chunks[coord]
	var floors: Array[Vector2i] = chunk_data[&"floors"]
	var walls: Array[Vector2i] = chunk_data[&"walls"]
	var torches: Array[Vector2i] = chunk_data[&"torches"]

	for fpos: Vector2i in floors:
		_floor.erase_cell(fpos)
		_walkable_cells.erase(fpos)
		if _nav_window != null:
			_nav_window.set_cell_walkable(fpos, false)

	for wpos: Vector2i in walls:
		_walls.erase_cell(wpos)

	for tpos: Vector2i in torches:
		_decorations.erase_cell(tpos)

	if _light_manager != null:
		_light_manager.remove_chunk_lights(coord)

	_loaded_chunks.erase(coord)
