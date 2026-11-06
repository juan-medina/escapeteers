# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name MapOverlay
extends Control

const TILE_SIZE: float = 16.0
const CHUNK_SIZE_TILES: int = 2
const CHUNK_SIZE_PX: float = float(CHUNK_SIZE_TILES) * TILE_SIZE
const WALL_COLOR: Color = Color(0.85, 0.72, 0.38, 0.65)
const EXPLORED_FLOOR_COLOR: Color = Color(0.22, 0.48, 0.68, 0.38)
const UNEXPLORED_FLOOR_COLOR: Color = Color(0.55, 0.25, 0.30, 0.28)
const DEADZONE_HALF_EXTENT: Vector2 = Vector2(220.0, 130.0)
const DAMAGE_METER_SAFE_MARGIN: float = 192.0
const RECENTER_SPEED: float = 420.0

## Screen pixels per world tile. Must be an integer so every wall vertex lands on a whole pixel (crisp, no shimmer).
@export_range(1, 8) var pixels_per_tile: int = 2
@export_range(1, 16) var reveal_chunk_radius: int = 8
@export_range(1, 8) var explore_chunk_radius: int = 2

var map_scale: float = 0.0
var _target: CharacterBody2D = null
var _chunk_segments: Dictionary[Vector2i, PackedVector2Array] = {}
var _chunk_floor_vertices: Dictionary[Vector2i, PackedVector2Array] = {}
var _revealed_chunks: Dictionary[Vector2i, bool] = {}
var _explored_chunks: Dictionary[Vector2i, bool] = {}
var _last_revealed_chunk: Vector2i = Vector2i(2147483647, 2147483647)
var _anchor_map_pos: Vector2 = Vector2.ZERO
var _has_anchor: bool = false
var _is_recentering: bool = false
var _dirty: bool = false

var _unexplored_floor_mesh: MeshInstance2D = null
var _explored_floor_mesh: MeshInstance2D = null
var _walls_mesh: MeshInstance2D = null

@onready var _chunks_container: Node2D = $Chunks
@onready var _player_marker: PlayerMarker = $PlayerMarker


func _ready() -> void:
	visible = false
	set_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_marker.rotation = -PI * 0.5

	_unexplored_floor_mesh = MeshInstance2D.new()
	_unexplored_floor_mesh.self_modulate = UNEXPLORED_FLOOR_COLOR
	_chunks_container.add_child(_unexplored_floor_mesh)

	_explored_floor_mesh = MeshInstance2D.new()
	_explored_floor_mesh.self_modulate = EXPLORED_FLOOR_COLOR
	_chunks_container.add_child(_explored_floor_mesh)

	_walls_mesh = MeshInstance2D.new()
	_walls_mesh.self_modulate = WALL_COLOR
	_chunks_container.add_child(_walls_mesh)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_map"):
		toggle()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		return
	_update_discovery()
	if visible:
		_update_view(delta)


func setup(plan: WorldPlan, target: CharacterBody2D) -> void:
	_target = target
	_player_marker.rotation = -PI * 0.5
	_has_anchor = false
	_is_recentering = false
	_build_chunks(plan)
	set_process(true)
	if is_instance_valid(_target):
		_center_anchor_on_target()
		_update_discovery()
		if visible:
			_update_view(0.0)


func toggle() -> void:
	set_map_visible(not visible)


func set_map_visible(is_vis: bool) -> void:
	visible = is_vis
	if visible and is_instance_valid(_target):
		_center_anchor_on_target()
		_update_view(0.0)
		if _dirty:
			_rebuild_meshes()


func _center_anchor_on_target() -> void:
	_anchor_map_pos = (_target.global_position * map_scale).round()
	_has_anchor = true
	_is_recentering = false


func _update_view(delta: float) -> void:
	if not _has_anchor:
		_center_anchor_on_target()

	var center: Vector2 = (size * 0.5).round()
	var player_map_pos: Vector2 = (_target.global_position * map_scale).round()
	var offset: Vector2 = player_map_pos - _anchor_map_pos

	var max_right_extent: float = clampf(center.x - DAMAGE_METER_SAFE_MARGIN, 32.0, DEADZONE_HALF_EXTENT.x)
	if offset.x < -DEADZONE_HALF_EXTENT.x or offset.x > max_right_extent or absf(offset.y) > DEADZONE_HALF_EXTENT.y:
		_is_recentering = true

	if _is_recentering:
		_anchor_map_pos = _anchor_map_pos.move_toward(player_map_pos, RECENTER_SPEED * delta)
		if _anchor_map_pos.distance_squared_to(player_map_pos) <= 0.25:
			_anchor_map_pos = player_map_pos
			_is_recentering = false

	var snapped_anchor: Vector2 = _anchor_map_pos.round()
	_chunks_container.position = center - snapped_anchor
	_player_marker.position = center + (player_map_pos - snapped_anchor)
	if _target.velocity.length_squared() > 0.01:
		_player_marker.rotation = _target.velocity.angle()


func _update_discovery() -> void:
	var cur_chunk: Vector2i = Vector2i(floori(_target.global_position.x / CHUNK_SIZE_PX), floori(_target.global_position.y / CHUNK_SIZE_PX))
	if cur_chunk == _last_revealed_chunk:
		return
	_last_revealed_chunk = cur_chunk
	_reveal_chunks_at(cur_chunk)


func _reveal_chunks_at(player_chunk: Vector2i) -> void:
	var state_changed: bool = false
	for dy: int in range(-reveal_chunk_radius, reveal_chunk_radius + 1):
		for dx: int in range(-reveal_chunk_radius, reveal_chunk_radius + 1):
			var coord: Vector2i = player_chunk + Vector2i(dx, dy)
			if not _revealed_chunks.has(coord):
				_revealed_chunks[coord] = true
				state_changed = true

			if maxi(absi(dx), absi(dy)) <= explore_chunk_radius and not _explored_chunks.has(coord):
				_explored_chunks[coord] = true
				state_changed = true

	if state_changed:
		_dirty = true
		if visible:
			_rebuild_meshes()


func _rebuild_meshes() -> void:
	if not _dirty:
		return
	_dirty = false

	var unexp_verts: PackedVector2Array = PackedVector2Array()
	var exp_verts: PackedVector2Array = PackedVector2Array()
	var wall_verts: PackedVector2Array = PackedVector2Array()

	for coord: Vector2i in _revealed_chunks:
		if _explored_chunks.has(coord):
			if _chunk_floor_vertices.has(coord):
				exp_verts.append_array(_chunk_floor_vertices[coord])
		else:
			if _chunk_floor_vertices.has(coord):
				unexp_verts.append_array(_chunk_floor_vertices[coord])

		if _chunk_segments.has(coord):
			wall_verts.append_array(_chunk_segments[coord])

	_unexplored_floor_mesh.mesh = _create_simple_mesh(unexp_verts, Mesh.PRIMITIVE_TRIANGLES)
	_explored_floor_mesh.mesh = _create_simple_mesh(exp_verts, Mesh.PRIMITIVE_TRIANGLES)
	_walls_mesh.mesh = _create_simple_mesh(wall_verts, Mesh.PRIMITIVE_LINES)


static func _create_simple_mesh(vertices: PackedVector2Array, primitive: Mesh.PrimitiveType) -> ArrayMesh:
	if vertices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(primitive, arrays)
	return mesh


func _build_chunks(plan: WorldPlan) -> void:
	if _unexplored_floor_mesh != null:
		_unexplored_floor_mesh.mesh = null
	if _explored_floor_mesh != null:
		_explored_floor_mesh.mesh = null
	if _walls_mesh != null:
		_walls_mesh.mesh = null
	_dirty = false
	_revealed_chunks.clear()
	_explored_chunks.clear()
	_chunk_segments.clear()
	_chunk_floor_vertices.clear()
	_last_revealed_chunk = Vector2i(2147483647, 2147483647)

	if plan == null or plan.carve_rects.is_empty():
		return

	map_scale = float(pixels_per_tile) / TILE_SIZE
	_chunks_container.scale = Vector2(map_scale, map_scale)
	_extract_chunked_floors(plan)
	_extract_chunked_wall_segments(plan)


func _extract_chunked_floors(plan: WorldPlan) -> void:
	var touched_chunks: Dictionary[Vector2i, bool] = {}
	for r: Rect2i in plan.carve_rects:
		var min_cx: int = floori(float(r.position.x) / float(CHUNK_SIZE_TILES))
		var max_cx: int = floori(float(r.end.x - 1) / float(CHUNK_SIZE_TILES))
		var min_cy: int = floori(float(r.position.y) / float(CHUNK_SIZE_TILES))
		var max_cy: int = floori(float(r.end.y - 1) / float(CHUNK_SIZE_TILES))
		for cy: int in range(min_cy, max_cy + 1):
			for cx: int in range(min_cx, max_cx + 1):
				touched_chunks[Vector2i(cx, cy)] = true

	for coord: Vector2i in touched_chunks:
		var verts: PackedVector2Array = PackedVector2Array()
		var base_tx: int = coord.x * CHUNK_SIZE_TILES
		var base_ty: int = coord.y * CHUNK_SIZE_TILES
		for dy: int in range(CHUNK_SIZE_TILES):
			var ty: int = base_ty + dy
			var y0: float = float(ty) * TILE_SIZE
			var y1: float = float(ty + 1) * TILE_SIZE
			for dx: int in range(CHUNK_SIZE_TILES):
				var tx: int = base_tx + dx
				if not plan.is_floor(Vector2i(tx, ty)):
					continue
				var x0: float = float(tx) * TILE_SIZE
				var x1: float = float(tx + 1) * TILE_SIZE
				verts.append(Vector2(x0, y0))
				verts.append(Vector2(x1, y0))
				verts.append(Vector2(x1, y1))
				verts.append(Vector2(x0, y0))
				verts.append(Vector2(x1, y1))
				verts.append(Vector2(x0, y1))

		if not verts.is_empty():
			_chunk_floor_vertices[coord] = verts


func _extract_chunked_wall_segments(plan: WorldPlan) -> void:
	var rects: Array[Rect2i] = plan.carve_rects
	var grid: SpatialGrid = plan.spatial_grid

	for r: Rect2i in rects:
		# 1. Top Edge: at y = r.position.y, x in [r.position.x, r.end.x]
		# Outside neighbor is y = r.position.y - 1
		var y_top: int = r.position.y
		var y_top_out: int = y_top - 1
		var top_blockers: Array[Vector2i] = []
		var query_top: Rect2i = Rect2i(r.position.x, y_top_out, r.size.x, 1)
		var cand_top: Array[int] = grid.get_candidate_ids_for_rect(query_top)
		for idx: int in cand_top:
			var other: Rect2i = rects[idx]
			if other == r:
				continue
			if other.position.y <= y_top_out and other.end.y > y_top_out:
				var ox1: int = maxi(r.position.x, other.position.x)
				var ox2: int = mini(r.end.x, other.end.x)
				if ox2 > ox1:
					top_blockers.append(Vector2i(ox1, ox2))

		var top_walls: Array[Vector2i] = _subtract_intervals(r.position.x, r.end.x, top_blockers)
		for w: Vector2i in top_walls:
			_split_horizontal(w.x, w.y, y_top)

		# 2. Bottom Edge: at y = r.end.y, x in [r.position.x, r.end.x]
		# Outside neighbor is y = r.end.y
		var y_bot: int = r.end.y
		var bot_blockers: Array[Vector2i] = []
		var query_bot: Rect2i = Rect2i(r.position.x, y_bot, r.size.x, 1)
		var cand_bot: Array[int] = grid.get_candidate_ids_for_rect(query_bot)
		for idx: int in cand_bot:
			var other: Rect2i = rects[idx]
			if other == r:
				continue
			if other.position.y <= y_bot and other.end.y > y_bot:
				var ox1: int = maxi(r.position.x, other.position.x)
				var ox2: int = mini(r.end.x, other.end.x)
				if ox2 > ox1:
					bot_blockers.append(Vector2i(ox1, ox2))

		var bot_walls: Array[Vector2i] = _subtract_intervals(r.position.x, r.end.x, bot_blockers)
		for w: Vector2i in bot_walls:
			_split_horizontal(w.x, w.y, y_bot)

		# 3. Left Edge: at x = r.position.x, y in [r.position.y, r.end.y]
		# Outside neighbor is x = r.position.x - 1
		var x_left: int = r.position.x
		var x_left_out: int = x_left - 1
		var left_blockers: Array[Vector2i] = []
		var query_left: Rect2i = Rect2i(x_left_out, r.position.y, 1, r.size.y)
		var cand_left: Array[int] = grid.get_candidate_ids_for_rect(query_left)
		for idx: int in cand_left:
			var other: Rect2i = rects[idx]
			if other == r:
				continue
			if other.position.x <= x_left_out and other.end.x > x_left_out:
				var oy1: int = maxi(r.position.y, other.position.y)
				var oy2: int = mini(r.end.y, other.end.y)
				if oy2 > oy1:
					left_blockers.append(Vector2i(oy1, oy2))

		var left_walls: Array[Vector2i] = _subtract_intervals(r.position.y, r.end.y, left_blockers)
		for w: Vector2i in left_walls:
			_split_vertical(w.x, w.y, x_left)

		# 4. Right Edge: at x = r.end.x, y in [r.position.y, r.end.y]
		# Outside neighbor is x = r.end.x
		var x_right: int = r.end.x
		var right_blockers: Array[Vector2i] = []
		var query_right: Rect2i = Rect2i(x_right, r.position.y, 1, r.size.y)
		var cand_right: Array[int] = grid.get_candidate_ids_for_rect(query_right)
		for idx: int in cand_right:
			var other: Rect2i = rects[idx]
			if other == r:
				continue
			if other.position.x <= x_right and other.end.x > x_right:
				var oy1: int = maxi(r.position.y, other.position.y)
				var oy2: int = mini(r.end.y, other.end.y)
				if oy2 > oy1:
					right_blockers.append(Vector2i(oy1, oy2))

		var right_walls: Array[Vector2i] = _subtract_intervals(r.position.y, r.end.y, right_blockers)
		for w: Vector2i in right_walls:
			_split_vertical(w.x, w.y, x_right)


func _split_horizontal(min_x: int, max_x: int, y: int) -> void:
	var cy: int = floori(float(y) / float(CHUNK_SIZE_TILES))
	var cur_x: int = min_x
	while cur_x < max_x:
		var cx: int = floori(float(cur_x) / float(CHUNK_SIZE_TILES))
		var next_chunk_x: int = (cx + 1) * CHUNK_SIZE_TILES
		var end_x: int = mini(max_x, next_chunk_x)

		var coord: Vector2i = Vector2i(cx, cy)
		if not _chunk_segments.has(coord):
			_chunk_segments[coord] = PackedVector2Array()
		var pts: PackedVector2Array = _chunk_segments[coord]
		pts.append(Vector2(float(cur_x) * TILE_SIZE, float(y) * TILE_SIZE))
		pts.append(Vector2(float(end_x) * TILE_SIZE, float(y) * TILE_SIZE))
		_chunk_segments[coord] = pts
		cur_x = end_x


func _split_vertical(min_y: int, max_y: int, x: int) -> void:
	var cx: int = floori(float(x) / float(CHUNK_SIZE_TILES))
	var cur_y: int = min_y
	while cur_y < max_y:
		var cy: int = floori(float(cur_y) / float(CHUNK_SIZE_TILES))
		var next_chunk_y: int = (cy + 1) * CHUNK_SIZE_TILES
		var end_y: int = mini(max_y, next_chunk_y)

		var coord: Vector2i = Vector2i(cx, cy)
		if not _chunk_segments.has(coord):
			_chunk_segments[coord] = PackedVector2Array()
		var pts: PackedVector2Array = _chunk_segments[coord]
		pts.append(Vector2(float(x) * TILE_SIZE, float(cur_y) * TILE_SIZE))
		pts.append(Vector2(float(x) * TILE_SIZE, float(end_y) * TILE_SIZE))
		_chunk_segments[coord] = pts
		cur_y = end_y


func _subtract_intervals(base_min: int, base_max: int, blockers: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if base_min >= base_max:
		return result
	if blockers.is_empty():
		result.append(Vector2i(base_min, base_max))
		return result

	blockers.sort_custom(_compare_intervals_asc)

	var current: int = base_min
	for b: Vector2i in blockers:
		var b_start: int = clampi(b.x, base_min, base_max)
		var b_end: int = clampi(b.y, base_min, base_max)
		if b_start > current:
			result.append(Vector2i(current, b_start))
		current = maxi(current, b_end)
		if current >= base_max:
			break

	if current < base_max:
		result.append(Vector2i(current, base_max))

	return result


static func _compare_intervals_asc(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x
