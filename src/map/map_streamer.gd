# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name MapStreamer
extends RefCounted


class StreamJob:
	extends RefCounted
	var coord: Vector2i
	var data: Dictionary
	var is_evict: bool
	var phase: int = 0
	var idx: int = 0
	var spawned_lights: Array[Vector2i] = []

	func _init(job_coord: Vector2i, job_data: Dictionary, job_is_evict: bool) -> void:
		coord = job_coord
		data = job_data
		is_evict = job_is_evict


const CHUNK_SIZE: int = 32
const SUBCHUNK_SIZE: int = 8
const LOAD_RADIUS: int = 3
const UNLOAD_RADIUS: int = 5
const FRAME_BUDGET_USEC: int = 1200
const CELL_BATCH_SIZE: int = 48

var _plan: WorldPlan = null
var _floor: TileMapLayer = null
var _walls: TileMapLayer = null
var _decorations: TileMapLayer = null
var _light_manager: LightManager = null
var _nav_window: NavWindow = null
var _walkable_cells: Dictionary[Vector2i, bool] = {}
var _loaded_spikes: Dictionary[Vector2i, int] = {}
var _group_frames: Array[int] = []
var _run_seed: int = 0

var _loaded_chunks: Dictionary[Vector2i, Dictionary] = {}
var _load_queue: Array[Vector2i] = []
var _queued_set: Dictionary[Vector2i, bool] = {}
var _evict_queue: Array[Vector2i] = []
var _evict_queued_set: Dictionary[Vector2i, bool] = {}
var _active_load_job: StreamJob = null
var _active_evict_job: StreamJob = null
var _last_player_chunk: Vector2i = Vector2i(-999999, -999999)
var _last_player_subchunk: Vector2i = Vector2i(-999999, -999999)
var _sort_center_chunk: Vector2i = Vector2i.ZERO
var _sort_has_vel: bool = false
var _sort_move_dir: Vector2 = Vector2.ZERO


func setup(
	plan: WorldPlan,
	floor_layer: TileMapLayer,
	walls_layer: TileMapLayer,
	decor_layer: TileMapLayer,
	light_manager: LightManager,
	nav_window: NavWindow,
	walkable_cells: Dictionary[Vector2i, bool],
	loaded_spikes: Dictionary[Vector2i, int],
	group_frames: Array[int],
	run_seed: int
) -> void:
	_plan = plan
	_floor = floor_layer
	_walls = walls_layer
	_decorations = decor_layer
	_light_manager = light_manager
	_nav_window = nav_window
	_walkable_cells = walkable_cells
	_loaded_spikes = loaded_spikes
	_group_frames = group_frames
	_run_seed = run_seed

	_loaded_chunks.clear()
	_load_queue.clear()
	_queued_set.clear()
	_evict_queue.clear()
	_evict_queued_set.clear()
	_active_load_job = null
	_active_evict_job = null
	_last_player_chunk = Vector2i(-999999, -999999)
	_last_player_subchunk = Vector2i(-999999, -999999)


func update(player_world_pos: Vector2, player_velocity: Vector2) -> void:
	var start_usec: int = Time.get_ticks_usec()
	var player_cell: Vector2i = _floor.local_to_map(player_world_pos)
	var player_chunk: Vector2i = get_chunk_coord(player_cell)
	var player_subchunk: Vector2i = cell_to_subchunk(player_cell)

	_nav_window.update_center(player_cell)

	if player_subchunk != _last_player_subchunk:
		_last_player_subchunk = player_subchunk
		_last_player_chunk = player_chunk
		_queue_chunks_in_radius(player_chunk)
		_queue_evict_distant_chunks(player_chunk)
		if not _load_queue.is_empty():
			_sort_queue(player_chunk, player_velocity)

	if _has_pending_work():
		_process_queues(start_usec)


func materialize_rect_immediate(tile_rect: Rect2i) -> void:
	var min_chunk: Vector2i = get_chunk_coord(tile_rect.position)
	var max_chunk: Vector2i = get_chunk_coord(tile_rect.end)

	for cy: int in range(min_chunk.y, max_chunk.y + 1):
		for cx: int in range(min_chunk.x, max_chunk.x + 1):
			var coord: Vector2i = Vector2i(cx, cy)
			if _loaded_chunks.has(coord):
				continue
			var data: Dictionary = _plan.baked_chunks.get(coord, {})
			if data.is_empty():
				_store_empty_chunk(coord)
				continue
			var job: StreamJob = StreamJob.new(coord, data, false)
			while job.phase <= 5:
				_step_load_job(job, 999999)
			_commit_loaded_job(job)


static func cell_to_chunk(cell: Vector2i) -> Vector2i:
	var cx: int = floori(float(cell.x) / float(CHUNK_SIZE))
	var cy: int = floori(float(cell.y) / float(CHUNK_SIZE))
	return Vector2i(cx, cy)


static func cell_to_subchunk(cell: Vector2i) -> Vector2i:
	var sx: int = floori(float(cell.x) / float(SUBCHUNK_SIZE))
	var sy: int = floori(float(cell.y) / float(SUBCHUNK_SIZE))
	return Vector2i(sx, sy)


func get_chunk_coord(cell: Vector2i) -> Vector2i:
	return cell_to_chunk(cell)


func is_chunk_loaded(coord: Vector2i) -> bool:
	return _loaded_chunks.has(coord) or _is_active_job_coord(_active_load_job, coord)


func sync_loaded_chunk_arrays(coord: Vector2i, data: Dictionary) -> void:
	if not _loaded_chunks.has(coord):
		return
	var loaded: Dictionary = _loaded_chunks[coord]
	loaded[&"floors"] = data[&"floors"]
	loaded[&"spikes"] = data[&"spikes"]
	loaded[&"walls"] = data[&"walls"]
	loaded[&"torches"] = data[&"torches"]
	loaded[&"walkable"] = data[&"walkable"]
	loaded[&"walkable_rects"] = data[&"walkable_rects"]


func add_loaded_chunk_walkable(coord: Vector2i, cells: Array[Vector2i]) -> void:
	if not _loaded_chunks.has(coord) or cells.is_empty():
		return
	var loaded: Dictionary = _loaded_chunks[coord]
	var walk_arr: Array[Vector2i] = loaded[&"walkable"]
	var existing: Dictionary[Vector2i, bool] = {}
	for wcell: Vector2i in walk_arr:
		existing[wcell] = true
	var added: bool = false
	for cell: Vector2i in cells:
		if not existing.has(cell):
			existing[cell] = true
			walk_arr.append(cell)
			added = true
	if added:
		loaded[&"walkable_rects"] = TileClassifier.build_walkable_rects(coord, walk_arr)


func populate_nav_region(astar: AStarGrid2D, region: Rect2i) -> void:
	var min_chunk: Vector2i = cell_to_chunk(region.position)
	var max_chunk: Vector2i = cell_to_chunk(region.end - Vector2i.ONE)

	for cy: int in range(min_chunk.y, max_chunk.y + 1):
		for cx: int in range(min_chunk.x, max_chunk.x + 1):
			var coord: Vector2i = Vector2i(cx, cy)
			if not _loaded_chunks.has(coord):
				continue
			var rects: Array[Rect2i] = _loaded_chunks[coord][&"walkable_rects"]
			var interior: bool = cx > min_chunk.x and cx < max_chunk.x and cy > min_chunk.y and cy < max_chunk.y
			for r: Rect2i in rects:
				if interior:
					astar.fill_solid_region(r, false)
				else:
					var clipped: Rect2i = r.intersection(region)
					if clipped.has_area():
						astar.fill_solid_region(clipped, false)

	if _active_load_job != null and _active_load_job.phase == 5:
		var jc: Vector2i = _active_load_job.coord
		if jc.x >= min_chunk.x and jc.x <= max_chunk.x and jc.y >= min_chunk.y and jc.y <= max_chunk.y:
			var walk_arr: Array[Vector2i] = _active_load_job.data[&"walkable"]
			for i: int in range(_active_load_job.idx):
				var fpos: Vector2i = walk_arr[i]
				if region.has_point(fpos):
					astar.set_point_solid(fpos, false)


func _has_pending_work() -> bool:
	return _active_load_job != null or not _load_queue.is_empty() or _active_evict_job != null or not _evict_queue.is_empty()


func _is_active_job_coord(job: StreamJob, coord: Vector2i) -> bool:
	return job != null and job.coord == coord


func _queue_chunks_in_radius(center_chunk: Vector2i) -> void:
	for dy: int in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dx: int in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var coord: Vector2i = center_chunk + Vector2i(dx, dy)
			if _evict_queued_set.has(coord):
				_evict_queued_set.erase(coord)
				_evict_queue.erase(coord)
			if (
				not _loaded_chunks.has(coord)
				and not _queued_set.has(coord)
				and not _is_active_job_coord(_active_load_job, coord)
				and not _is_active_job_coord(_active_evict_job, coord)
			):
				_load_queue.append(coord)
				_queued_set[coord] = true


func _queue_evict_distant_chunks(center_chunk: Vector2i) -> void:
	for i: int in range(_load_queue.size() - 1, -1, -1):
		var qcoord: Vector2i = _load_queue[i]
		if absi(qcoord.x - center_chunk.x) > UNLOAD_RADIUS or absi(qcoord.y - center_chunk.y) > UNLOAD_RADIUS:
			_load_queue.remove_at(i)
			_queued_set.erase(qcoord)

	for coord: Vector2i in _loaded_chunks:
		if absi(coord.x - center_chunk.x) > UNLOAD_RADIUS or absi(coord.y - center_chunk.y) > UNLOAD_RADIUS:
			if not _evict_queued_set.has(coord) and not _is_active_job_coord(_active_evict_job, coord):
				_evict_queue.append(coord)
				_evict_queued_set[coord] = true


func _sort_queue(center_chunk: Vector2i, velocity: Vector2) -> void:
	_sort_center_chunk = center_chunk
	_sort_has_vel = velocity.length_squared() > 1.0
	_sort_move_dir = velocity.normalized() if _sort_has_vel else Vector2.ZERO
	_load_queue.sort_custom(_compare_chunk_priority)


func _compare_chunk_priority(a: Vector2i, b: Vector2i) -> bool:
	var da: Vector2 = Vector2(a - _sort_center_chunk)
	var db: Vector2 = Vector2(b - _sort_center_chunk)
	var dist_a: float = da.length()
	var dist_b: float = db.length()

	var score_a: float = dist_a
	var score_b: float = dist_b

	if _sort_has_vel:
		if dist_a > 0.001:
			score_a -= da.normalized().dot(_sort_move_dir) * 1.5
		if dist_b > 0.001:
			score_b -= db.normalized().dot(_sort_move_dir) * 1.5

	return score_a < score_b


func _process_queues(start_usec: int) -> void:
	while (Time.get_ticks_usec() - start_usec) < FRAME_BUDGET_USEC:
		if _active_load_job != null or not _load_queue.is_empty():
			if _active_load_job == null:
				var coord: Vector2i = _load_queue.pop_front()
				_queued_set.erase(coord)
				var data: Dictionary = _plan.baked_chunks.get(coord, {})
				if data.is_empty():
					_store_empty_chunk(coord)
					continue
				_active_load_job = StreamJob.new(coord, data, false)

			_step_load_job(_active_load_job, CELL_BATCH_SIZE)
			if _active_load_job.phase > 5:
				_commit_loaded_job(_active_load_job)
				_active_load_job = null
		elif _active_evict_job != null or not _evict_queue.is_empty():
			if _active_evict_job == null:
				var coord: Vector2i = _evict_queue.pop_front()
				_evict_queued_set.erase(coord)
				if not _loaded_chunks.has(coord):
					continue
				var data: Dictionary = _loaded_chunks[coord]
				_loaded_chunks.erase(coord)
				var floors: Array[Vector2i] = data[&"floors"]
				var walls: Array[Vector2i] = data[&"walls"]
				if floors.is_empty() and walls.is_empty():
					continue
				_active_evict_job = StreamJob.new(coord, data, true)

			_step_evict_job(_active_evict_job, CELL_BATCH_SIZE)
			if _active_evict_job.phase > 5:
				var evicted_coord: Vector2i = _active_evict_job.coord
				_active_evict_job = null
				_requeue_if_returned(evicted_coord)
		else:
			break


func _requeue_if_returned(coord: Vector2i) -> void:
	if absi(coord.x - _last_player_chunk.x) <= LOAD_RADIUS and absi(coord.y - _last_player_chunk.y) <= LOAD_RADIUS:
		if not _loaded_chunks.has(coord) and not _queued_set.has(coord):
			_load_queue.append(coord)
			_queued_set[coord] = true


func _store_empty_chunk(coord: Vector2i) -> void:
	_loaded_chunks[coord] = {
		&"floors": [] as Array[Vector2i],
		&"spikes": [] as Array[Vector2i],
		&"event_spikes": [] as Array[Vector2i],
		&"walls": [] as Array[Vector2i],
		&"torches": [] as Array[Vector2i],
		&"lights": [] as Array[Vector2i],
		&"walkable": [] as Array[Vector2i],
		&"walkable_rects": [] as Array[Rect2i],
	}


func _commit_loaded_job(job: StreamJob) -> void:
	var data: Dictionary = job.data
	var event_spikes: Array[Vector2i] = data[&"event_spikes"]
	for spos: Vector2i in event_spikes:
		var event_room: Rect2i = _plan.event_spike_cell_rooms.get(spos, Rect2i())
		var hazard: ClosingSpikeHazard = _plan.closing_spike_hazards.get(event_room, null)
		if hazard != null:
			var frame_idx: int = hazard.get_cell_frame(spos)
			if frame_idx > 0:
				var tile_set: int = _plan.spike_tile_sets.get(spos, 1)
				_floor.set_cell(spos, TileClassifier.TILE_SET_SOURCE_ID, TileClassifier.get_blood_spike_frame(frame_idx, tile_set))
	_loaded_chunks[job.coord] = {
		&"floors": data[&"floors"],
		&"spikes": data[&"spikes"],
		&"event_spikes": event_spikes,
		&"walls": data[&"walls"],
		&"torches": data[&"torches"],
		&"lights": job.spawned_lights,
		&"walkable": data[&"walkable"],
		&"walkable_rects": data[&"walkable_rects"],
	}


func _step_load_job(job: StreamJob, batch_limit: int) -> void:
	var data: Dictionary = job.data
	match job.phase:
		0:
			var floors: Array[Vector2i] = data[&"floors"]
			var floor_atlas: Array[Vector2i] = data[&"floor_atlas"]
			var end_idx: int = mini(floors.size(), job.idx + batch_limit)
			for i: int in range(job.idx, end_idx):
				_floor.set_cell(floors[i], TileClassifier.TILE_SET_SOURCE_ID, floor_atlas[i])
			_advance_job_cursor(job, end_idx, floors.size())
		1:
			var spikes: Array[Vector2i] = data[&"spikes"]
			var end_idx: int = mini(spikes.size(), job.idx + batch_limit)
			for i: int in range(job.idx, end_idx):
				var spos: Vector2i = spikes[i]
				var group_id: int = _plan.get_spike_group(spos)
				_loaded_spikes[spos] = group_id
				if group_id >= 0 and group_id < _group_frames.size():
					var frame_idx: int = _group_frames[group_id]
					var tile_set: int = _plan.spike_tile_sets.get(spos, 1)
					_floor.set_cell(spos, TileClassifier.TILE_SET_SOURCE_ID, TileClassifier.get_spike_frame(frame_idx, tile_set))
			_advance_job_cursor(job, end_idx, spikes.size())
		2:
			var walls: Array[Vector2i] = data[&"walls"]
			var wall_atlas: Array[Vector2i] = data[&"wall_atlas"]
			var wall_alt_ids: Array[int] = data[&"wall_alt_ids"]
			var end_idx: int = mini(walls.size(), job.idx + batch_limit)
			for i: int in range(job.idx, end_idx):
				_walls.set_cell(walls[i], TileClassifier.TILE_SET_SOURCE_ID, wall_atlas[i], wall_alt_ids[i])
			_advance_job_cursor(job, end_idx, walls.size())
		3:
			var torches: Array[Vector2i] = data[&"torches"]
			var torch_atlas: Array[Vector2i] = data[&"torch_atlas"]
			var torch_alt_ids: Array[int] = data[&"torch_alt_ids"]
			var end_idx: int = mini(torches.size(), job.idx + batch_limit)
			for i: int in range(job.idx, end_idx):
				_decorations.set_cell(torches[i], TileClassifier.TILE_SET_SOURCE_ID, torch_atlas[i], torch_alt_ids[i])
			_advance_job_cursor(job, end_idx, torches.size())
		4:
			var lights: Array[Vector2i] = data[&"lights"]
			var end_idx: int = mini(lights.size(), job.idx + batch_limit)
			for i: int in range(job.idx, end_idx):
				var lpos: Vector2i = lights[i]
				if not _light_manager.has_light(lpos):
					var world_pos: Vector2 = _decorations.map_to_local(lpos)
					_light_manager.add_light(job.coord, lpos, world_pos)
					job.spawned_lights.append(lpos)
			_advance_job_cursor(job, end_idx, lights.size())
		5:
			var walkable: Array[Vector2i] = data[&"walkable"]
			var end_idx: int = mini(walkable.size(), job.idx + batch_limit)
			for i: int in range(job.idx, end_idx):
				var fpos: Vector2i = walkable[i]
				_walkable_cells[fpos] = true
				_nav_window.set_cell_walkable(fpos, true)
			_advance_job_cursor(job, end_idx, walkable.size())


func _step_evict_job(job: StreamJob, batch_limit: int) -> void:
	var data: Dictionary = job.data
	match job.phase:
		0:
			var spikes: Array[Vector2i] = data[&"spikes"]
			var end_idx: int = mini(spikes.size(), job.idx + batch_limit)
			for i: int in range(job.idx, end_idx):
				_loaded_spikes.erase(spikes[i])
			_advance_job_cursor(job, end_idx, spikes.size())
		1:
			var walkable: Array[Vector2i] = data[&"walkable"]
			var end_idx: int = mini(walkable.size(), job.idx + batch_limit)
			for i: int in range(job.idx, end_idx):
				var fpos: Vector2i = walkable[i]
				_walkable_cells.erase(fpos)
				_nav_window.set_cell_walkable(fpos, false)
			_advance_job_cursor(job, end_idx, walkable.size())
		2:
			var floors: Array[Vector2i] = data[&"floors"]
			var end_idx: int = mini(floors.size(), job.idx + batch_limit)
			for i: int in range(job.idx, end_idx):
				_floor.erase_cell(floors[i])
			_advance_job_cursor(job, end_idx, floors.size())
		3:
			var walls: Array[Vector2i] = data[&"walls"]
			var end_idx: int = mini(walls.size(), job.idx + batch_limit)
			for i: int in range(job.idx, end_idx):
				_walls.erase_cell(walls[i])
			_advance_job_cursor(job, end_idx, walls.size())
		4:
			var torches: Array[Vector2i] = data[&"torches"]
			var end_idx: int = mini(torches.size(), job.idx + batch_limit)
			for i: int in range(job.idx, end_idx):
				_decorations.erase_cell(torches[i])
			_advance_job_cursor(job, end_idx, torches.size())
		5:
			_light_manager.remove_chunk_lights(job.coord)
			job.phase = 6
			job.idx = 0


static func _advance_job_cursor(job: StreamJob, end_idx: int, total_size: int) -> void:
	if end_idx >= total_size:
		job.phase += 1
		job.idx = 0
	else:
		job.idx = end_idx
