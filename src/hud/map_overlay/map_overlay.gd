# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name MapOverlay
extends Control

const TILE_SIZE: float = 16.0
const CHUNK_SIZE_TILES: int = 2
const CHUNK_SIZE_PX: float = float(CHUNK_SIZE_TILES) * TILE_SIZE
const DEADZONE_HALF_EXTENT: Vector2 = Vector2(220.0, 130.0)
const DAMAGE_METER_SAFE_MARGIN: float = 192.0
const RECENTER_SPEED: float = 420.0
const ROOM_LABEL_SCENE: PackedScene = preload("res://hud/map_overlay/room_level_label.tscn")
const LABEL_HALF_SIZE: Vector2 = Vector2(16.0, 8.0)
const LABEL_COLOR_SAFE: Color = Color(0.55, 0.95, 0.62, 0.95)
const LABEL_COLOR_CAUTION: Color = Color(1.0, 0.82, 0.32, 0.95)
const LABEL_COLOR_DANGER: Color = Color(1.0, 0.38, 0.35, 0.95)
const LABEL_COLOR_CLEARED: Color = Color(0.55, 0.62, 0.70, 0.50)
const LABEL_COLOR_START: Color = Color(0.70, 0.88, 1.0, 0.80)
const HUD_EDGE_MARGIN_LEFT: float = 22.0
const HUD_EDGE_MARGIN_RIGHT: float = 22.0
const HUD_EDGE_MARGIN_TOP: float = 38.0
const HUD_EDGE_MARGIN_BOTTOM: float = 26.0
const HUD_ON_SCREEN_PAD: float = 8.0

## Screen pixels per world tile. Must be an integer so every wall vertex lands on a whole pixel (crisp, no shimmer).
@export_range(1, 8) var pixels_per_tile: int = 2
@export_range(1, 16) var reveal_chunk_radius: int = 8
@export_range(1, 8) var explore_chunk_radius: int = 2

var map_scale: float = 0.0
var _plan: WorldPlan = null
var _target: CharacterBody2D = null
var _squad_level: int = 1
var _chunk_segments: Dictionary[Vector2i, PackedVector2Array] = {}
var _chunk_floor_vertices: Dictionary[Vector2i, PackedVector2Array] = {}
var _revealed_chunks: Dictionary[Vector2i, bool] = {}
var _explored_chunks: Dictionary[Vector2i, bool] = {}
var _unexplored_floor_chunks: Dictionary[Vector2i, PackedVector2Array] = {}
var _explored_floor_verts: PackedVector2Array = PackedVector2Array()
var _wall_verts: PackedVector2Array = PackedVector2Array()
var _discovered_rooms: Dictionary[Rect2i, bool] = {}
var _cleared_rooms: Dictionary[Rect2i, bool] = {}
var _room_labels: Dictionary[Rect2i, Label] = {}
var _label_pool: Array[Label] = []
var _last_revealed_chunk: Vector2i = Vector2i(2147483647, 2147483647)
var _anchor_map_pos: Vector2 = Vector2.ZERO
var _has_anchor: bool = false
var _is_recentering: bool = false
var _dirty: bool = false
var _unexplored_dirty: bool = false
var _explored_dirty: bool = false
var _walls_dirty: bool = false
var _opened_shortcuts: Dictionary[WorldPlan.KeyColor, bool] = {}
var _collected_keys: Dictionary[WorldPlan.KeyColor, bool] = {}
var _unlocked_doors: Dictionary[WorldPlan.KeyColor, bool] = {}
var _door_world_positions: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _key_world_positions: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _hud_door_indicators: Array[Node2D] = []
var _hud_door_arrows: Array[Node2D] = []
var _hud_key_indicators: Array[Node2D] = []
var _hud_key_arrows: Array[Node2D] = []
var _visibility: MapVisibility = MapVisibility.new()
var _visited_fov_chunks: Dictionary[Vector2i, bool] = {}
var _fov_chunks: Dictionary[Vector2i, bool] = {}

@onready var _chunks_container: Node2D = $Chunks
@onready var _unexplored_floor_mesh: MeshInstance2D = $Chunks/UnexploredFloorMesh
@onready var _explored_floor_mesh: MeshInstance2D = $Chunks/ExploredFloorMesh
@onready var _walls_mesh: MeshInstance2D = $Chunks/WallsMesh
@onready var _room_labels_container: Node2D = $RoomLabels
@onready var _gate_markers_container: Node2D = $GateMarkers
@onready var _player_marker: Node2D = $PlayerMarker
@onready var _door_markers: Array[Node2D] = [
	$GateMarkers/BlueDoorMarker,
	$GateMarkers/GreenDoorMarker,
	$GateMarkers/YellowDoorMarker,
	$GateMarkers/RedDoorMarker,
]
@onready var _key_markers: Array[Node2D] = [
	$GateMarkers/BlueKeyMarker,
	$GateMarkers/GreenKeyMarker,
	$GateMarkers/YellowKeyMarker,
	$GateMarkers/RedKeyMarker,
]


func _ready() -> void:
	visible = false
	set_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


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
	_update_hud_edge_indicators()


func set_hud_edge_indicators(
	door_indicators: Array[Node2D],
	door_arrows: Array[Node2D],
	key_indicators: Array[Node2D],
	key_arrows: Array[Node2D],
) -> void:
	_hud_door_indicators = door_indicators
	_hud_door_arrows = door_arrows
	_hud_key_indicators = key_indicators
	_hud_key_arrows = key_arrows


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
	_update_hud_edge_indicators()


func mark_room_discovered(room: Rect2i) -> void:
	if _room_labels.has(room) and not _discovered_rooms.has(room):
		_discovered_rooms[room] = true
		_update_room_label(room)


func set_room_cleared(room: Rect2i, is_cleared: bool) -> void:
	if is_cleared:
		_cleared_rooms[room] = true
	else:
		_cleared_rooms.erase(room)
	_update_room_label(room)


func set_squad_level(squad_level: int) -> void:
	if _squad_level == squad_level:
		return
	_squad_level = squad_level
	for room: Rect2i in _discovered_rooms:
		_update_room_label(room)


func set_key_state(color: WorldPlan.KeyColor, collected: bool, used: bool) -> void:
	var newly_unlocked: bool = used and not _unlocked_doors.has(color)
	if collected:
		_collected_keys[color] = true
	else:
		_collected_keys.erase(color)
	if used:
		_unlocked_doors[color] = true
	else:
		_unlocked_doors.erase(color)
	_update_gate_markers_visibility()
	if newly_unlocked and _plan != null:
		for gate: SectorGatePlanner.SectorGate in _plan.sector_gates:
			if gate.color == color:
				_visibility.open_door(gate)
		_visited_fov_chunks.clear()
		_last_revealed_chunk = Vector2i(2147483647, 2147483647)
		if is_instance_valid(_target):
			_update_discovery()


func notify_shortcut_opened(color: WorldPlan.KeyColor) -> void:
	if _opened_shortcuts.has(color) or _plan == null:
		return
	_opened_shortcuts[color] = true
	var changed: bool = false
	for gate: SectorGatePlanner.SectorGate in _plan.sector_gates:
		if gate.color != color:
			continue
		_visibility.open_shortcut(gate)
		for coord: Vector2i in gate.opened_map_chunk_coords:
			if gate.opened_map_floors.has(coord):
				_chunk_floor_vertices[coord] = gate.opened_map_floors[coord]
			if gate.opened_map_walls.has(coord):
				_chunk_segments[coord] = gate.opened_map_walls[coord]
			else:
				_chunk_segments.erase(coord)
			_revealed_chunks[coord] = true
			changed = true

	_visited_fov_chunks.clear()
	_last_revealed_chunk = Vector2i(2147483647, 2147483647)
	if changed:
		_rebuild_cached_buffers_from_revealed()
		_update_gate_markers_visibility()
		if visible:
			_rebuild_meshes()
	if is_instance_valid(_target):
		_update_discovery()


func get_room_color(room: Rect2i) -> Color:
	var depth: int = _plan.get_room_depth(room)
	if depth <= 0:
		return LABEL_COLOR_START
	if _cleared_rooms.has(room):
		return LABEL_COLOR_CLEARED
	var diff: int = clampi(depth, 1, 12) - _squad_level
	if diff <= 0:
		return LABEL_COLOR_SAFE
	if diff == 1:
		return LABEL_COLOR_CAUTION
	return LABEL_COLOR_DANGER


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
	_room_labels_container.position = center - snapped_anchor
	_gate_markers_container.position = center - snapped_anchor
	_player_marker.position = center + (player_map_pos - snapped_anchor)
	if _target.velocity.length_squared() > 0.01:
		_player_marker.rotation = _target.velocity.angle()


func _update_discovery() -> void:
	var cur_chunk: Vector2i = Vector2i(floori(_target.global_position.x / CHUNK_SIZE_PX), floori(_target.global_position.y / CHUNK_SIZE_PX))
	if cur_chunk == _last_revealed_chunk:
		return
	_last_revealed_chunk = cur_chunk
	if _visited_fov_chunks.has(cur_chunk):
		return
	_visited_fov_chunks[cur_chunk] = true
	var origin_tile: Vector2i = Vector2i(floori(_target.global_position.x / TILE_SIZE), floori(_target.global_position.y / TILE_SIZE))
	_reveal_chunks_at(origin_tile)


func _reveal_chunks_at(origin_tile: Vector2i) -> void:
	(
		_visibility
		. compute_fov(
			origin_tile,
			reveal_chunk_radius * CHUNK_SIZE_TILES,
			explore_chunk_radius * CHUNK_SIZE_TILES,
			_fov_chunks,
		)
	)
	var markers_changed: bool = false
	for coord: Vector2i in _fov_chunks:
		var is_explore: bool = _fov_chunks[coord]
		if not _revealed_chunks.has(coord):
			_revealed_chunks[coord] = true
			markers_changed = true
			if _chunk_segments.has(coord):
				_wall_verts.append_array(_chunk_segments[coord])
				_walls_dirty = true
			if not is_explore and _chunk_floor_vertices.has(coord):
				_unexplored_floor_chunks[coord] = _chunk_floor_vertices[coord]
				_unexplored_dirty = true

		if is_explore and not _explored_chunks.has(coord):
			_explored_chunks[coord] = true
			if _unexplored_floor_chunks.erase(coord):
				_unexplored_dirty = true
			if _chunk_floor_vertices.has(coord):
				_explored_floor_verts.append_array(_chunk_floor_vertices[coord])
				_explored_dirty = true

	if markers_changed:
		_update_gate_markers_visibility()
	if _unexplored_dirty or _explored_dirty or _walls_dirty:
		_dirty = true
		if visible:
			_rebuild_meshes()


func _rebuild_cached_buffers_from_revealed() -> void:
	_unexplored_floor_chunks.clear()
	_explored_floor_verts.clear()
	_wall_verts.clear()
	for coord: Vector2i in _revealed_chunks:
		if _chunk_floor_vertices.has(coord):
			if _explored_chunks.has(coord):
				_explored_floor_verts.append_array(_chunk_floor_vertices[coord])
			else:
				_unexplored_floor_chunks[coord] = _chunk_floor_vertices[coord]
		if _chunk_segments.has(coord):
			_wall_verts.append_array(_chunk_segments[coord])
	_unexplored_dirty = true
	_explored_dirty = true
	_walls_dirty = true
	_dirty = true


func _rebuild_meshes() -> void:
	if not _dirty:
		return
	_dirty = false

	if _unexplored_dirty:
		_unexplored_dirty = false
		var unexp_verts: PackedVector2Array = PackedVector2Array()
		for coord: Vector2i in _unexplored_floor_chunks:
			unexp_verts.append_array(_unexplored_floor_chunks[coord])
		_unexplored_floor_mesh.mesh = _create_simple_mesh(unexp_verts, Mesh.PRIMITIVE_TRIANGLES)

	if _explored_dirty:
		_explored_dirty = false
		_explored_floor_mesh.mesh = _create_simple_mesh(_explored_floor_verts, Mesh.PRIMITIVE_TRIANGLES)

	if _walls_dirty:
		_walls_dirty = false
		_walls_mesh.mesh = _create_simple_mesh(_wall_verts, Mesh.PRIMITIVE_LINES)


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
	_unexplored_floor_mesh.mesh = null
	_explored_floor_mesh.mesh = null
	_walls_mesh.mesh = null
	_dirty = false
	_unexplored_dirty = false
	_explored_dirty = false
	_walls_dirty = false
	_plan = plan
	_revealed_chunks.clear()
	_explored_chunks.clear()
	_unexplored_floor_chunks.clear()
	_explored_floor_verts.clear()
	_wall_verts.clear()
	_discovered_rooms.clear()
	_cleared_rooms.clear()
	_room_labels.clear()
	_chunk_segments.clear()
	_chunk_floor_vertices.clear()
	_opened_shortcuts.clear()
	_collected_keys.clear()
	_unlocked_doors.clear()
	_visited_fov_chunks.clear()
	_fov_chunks.clear()
	for marker: Node2D in _door_markers:
		marker.visible = false
	for marker: Node2D in _key_markers:
		marker.visible = false
	for ind: Node2D in _hud_door_indicators:
		ind.visible = false
	for ind: Node2D in _hud_key_indicators:
		ind.visible = false
	_last_revealed_chunk = Vector2i(2147483647, 2147483647)

	if plan.carve_rects.is_empty():
		_visibility.setup(null)
		for label: Label in _label_pool:
			label.visible = false
		return

	_visibility.setup(plan)
	map_scale = float(pixels_per_tile) / TILE_SIZE
	_chunks_container.scale = Vector2(map_scale, map_scale)
	_extract_chunked_floors(plan)
	_extract_chunked_wall_segments(plan)
	_build_room_labels(plan)
	_build_gate_markers_and_opened_tunnels(plan)


func _build_gate_markers_and_opened_tunnels(plan: WorldPlan) -> void:
	for gate: SectorGatePlanner.SectorGate in plan.sector_gates:
		var color_idx: int = int(gate.color)
		if color_idx >= 0 and color_idx < _door_markers.size():
			var door_mid: Vector2 = (Vector2(gate.door_cells[0]) + Vector2(gate.door_cells[1])) * 0.5 + Vector2(0.5, 0.5)
			var door_world: Vector2 = door_mid * TILE_SIZE
			_door_world_positions[color_idx] = door_world
			_door_markers[color_idx].position = (door_world * map_scale).round()
		if color_idx >= 0 and color_idx < _key_markers.size():
			var key_mid: Vector2 = Vector2(gate.key_cell) + Vector2(0.5, 0.5)
			var key_world: Vector2 = key_mid * TILE_SIZE
			_key_world_positions[color_idx] = key_world
			_key_markers[color_idx].position = (key_world * map_scale).round()

		if gate.key_room == gate.gate_room or gate.shortcut_corridor_rects.is_empty():
			continue
		_build_opened_tunnel_map_data(plan, gate)


func _build_opened_tunnel_map_data(plan: WorldPlan, gate: SectorGatePlanner.SectorGate) -> void:
	var touched: Array[Vector2i] = SectorGatePlanner.collect_rects_chunks(gate.shortcut_corridor_rects, CHUNK_SIZE_TILES, 1)
	if touched.is_empty():
		return

	var min_tx: int = touched[0].x * CHUNK_SIZE_TILES
	var max_tx: int = min_tx + CHUNK_SIZE_TILES
	var min_ty: int = touched[0].y * CHUNK_SIZE_TILES
	var max_ty: int = min_ty + CHUNK_SIZE_TILES
	for coord: Vector2i in touched:
		var cx0: int = coord.x * CHUNK_SIZE_TILES
		var cy0: int = coord.y * CHUNK_SIZE_TILES
		min_tx = mini(min_tx, cx0)
		max_tx = maxi(max_tx, cx0 + CHUNK_SIZE_TILES)
		min_ty = mini(min_ty, cy0)
		max_ty = maxi(max_ty, cy0 + CHUNK_SIZE_TILES)

	var tile_rect: Rect2i = Rect2i(min_tx, min_ty, max_tx - min_tx, max_ty - min_ty)
	var query_rect: Rect2i = tile_rect.grow(2)
	var base_count: int = plan.carve_rects.size()
	for seg: Rect2i in gate.shortcut_corridor_rects:
		plan._add_carve_rect(seg)

	gate.opened_map_chunk_coords = touched
	gate.opened_map_floors.clear()
	gate.opened_map_walls.clear()
	for coord: Vector2i in touched:
		var verts: PackedVector2Array = _build_chunk_floor_vertices(coord, plan)
		if not verts.is_empty():
			gate.opened_map_floors[coord] = verts

	var opened_segments: Dictionary[Vector2i, PackedVector2Array] = {}
	var rects: Array[Rect2i] = plan.carve_rects
	var grid: SpatialGrid = plan.spatial_grid
	for idx: int in grid.get_candidate_ids_for_rect(query_rect):
		if idx < 0 or idx >= rects.size():
			continue
		var r: Rect2i = rects[idx]
		if not r.grow(1).intersects(tile_rect):
			continue
		_extract_horizontal_edge(r, r.position.y, r.position.y - 1, rects, grid, opened_segments)
		_extract_horizontal_edge(r, r.end.y, r.end.y, rects, grid, opened_segments)
		_extract_vertical_edge(r, r.position.x, r.position.x - 1, rects, grid, opened_segments)
		_extract_vertical_edge(r, r.end.x, r.end.x, rects, grid, opened_segments)

	for coord: Vector2i in touched:
		if opened_segments.has(coord):
			gate.opened_map_walls[coord] = opened_segments[coord]

	plan.carve_rects.resize(base_count)
	SectorGatePlanner.rebuild_spatial_grid(plan)


func _update_gate_markers_visibility() -> void:
	if _plan == null:
		return
	for gate: SectorGatePlanner.SectorGate in _plan.sector_gates:
		var color_idx: int = int(gate.color)
		if color_idx >= 0 and color_idx < _door_markers.size():
			var door_chunk: Vector2i = _cell_to_map_chunk(gate.door_cells[0])
			_door_markers[color_idx].visible = _revealed_chunks.has(door_chunk) and not _unlocked_doors.has(gate.color)
		if color_idx >= 0 and color_idx < _key_markers.size():
			var key_chunk: Vector2i = _cell_to_map_chunk(gate.key_cell)
			_key_markers[color_idx].visible = _revealed_chunks.has(key_chunk) and not _collected_keys.has(gate.color)
	_update_hud_edge_indicators()


func _update_hud_edge_indicators() -> void:
	if _hud_door_indicators.is_empty():
		return
	var on_screen_rect: Rect2 = Rect2(
		Vector2(HUD_ON_SCREEN_PAD, HUD_ON_SCREEN_PAD),
		Vector2(maxf(0.0, size.x - HUD_ON_SCREEN_PAD * 2.0), maxf(0.0, size.y - HUD_ON_SCREEN_PAD * 2.0)),
	)
	var min_bound: Vector2 = Vector2(HUD_EDGE_MARGIN_LEFT, HUD_EDGE_MARGIN_TOP)
	var max_bound: Vector2 = Vector2(
		maxf(min_bound.x, size.x - HUD_EDGE_MARGIN_RIGHT),
		maxf(min_bound.y, size.y - HUD_EDGE_MARGIN_BOTTOM),
	)
	for i: int in range(_door_markers.size()):
		_update_hud_indicator(
			_door_markers[i].visible,
			_door_world_positions[i],
			_hud_door_indicators[i],
			_hud_door_arrows[i],
			on_screen_rect,
			min_bound,
			max_bound,
		)
	for i: int in range(_key_markers.size()):
		_update_hud_indicator(
			_key_markers[i].visible,
			_key_world_positions[i],
			_hud_key_indicators[i],
			_hud_key_arrows[i],
			on_screen_rect,
			min_bound,
			max_bound,
		)


func _update_hud_indicator(
	is_active: bool,
	world_pos: Vector2,
	indicator: Node2D,
	arrow: Node2D,
	on_screen_rect: Rect2,
	min_bound: Vector2,
	max_bound: Vector2,
) -> void:
	if visible or not is_active or not is_instance_valid(_target):
		indicator.visible = false
		return
	var screen_pos: Vector2 = (size * 0.5) + (world_pos - _target.global_position)
	if on_screen_rect.has_point(screen_pos):
		indicator.visible = false
		return
	var clamped_pos: Vector2 = screen_pos.clamp(min_bound, max_bound)
	indicator.position = clamped_pos.round()
	indicator.visible = true
	arrow.rotation = (screen_pos - clamped_pos).angle()


static func _cell_to_map_chunk(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / float(CHUNK_SIZE_TILES)), floori(float(cell.y) / float(CHUNK_SIZE_TILES)))


func _build_room_labels(plan: WorldPlan) -> void:
	var pool_idx: int = 0
	if plan.hero_room.size != Vector2i.ZERO:
		_register_room_label(plan.hero_room, &"Start", pool_idx)
		pool_idx += 1

	for room: Rect2i in plan.rooms:
		var level_text: String = &"Lv.%d" % clampi(plan.get_room_depth(room), 1, 12)
		_register_room_label(room, level_text, pool_idx)
		pool_idx += 1

	for i: int in range(pool_idx, _label_pool.size()):
		_label_pool[i].visible = false


func _register_room_label(room: Rect2i, label_text: String, pool_idx: int) -> void:
	var label: Label
	if pool_idx < _label_pool.size():
		label = _label_pool[pool_idx]
	else:
		label = ROOM_LABEL_SCENE.instantiate() as Label
		_label_pool.append(label)
		_room_labels_container.add_child(label)

	var room_center: Vector2 = Vector2(room.position) + Vector2(room.size) * 0.5
	label.text = label_text
	label.position = (room_center * TILE_SIZE * map_scale).round() - LABEL_HALF_SIZE
	label.visible = false
	_room_labels[room] = label


func _update_room_label(room: Rect2i) -> void:
	if not _room_labels.has(room):
		return
	var label: Label = _room_labels[room]
	label.visible = _discovered_rooms.has(room)
	if label.visible:
		label.add_theme_color_override(&"font_color", get_room_color(room))


func _extract_chunked_floors(plan: WorldPlan) -> void:
	for coord: Vector2i in SectorGatePlanner.collect_rects_chunks(plan.carve_rects, CHUNK_SIZE_TILES, 0):
		var verts: PackedVector2Array = _build_chunk_floor_vertices(coord, plan)
		if not verts.is_empty():
			_chunk_floor_vertices[coord] = verts


func _build_chunk_floor_vertices(coord: Vector2i, plan: WorldPlan) -> PackedVector2Array:
	var base_tx: int = coord.x * CHUNK_SIZE_TILES
	var base_ty: int = coord.y * CHUNK_SIZE_TILES
	if (
		plan.is_floor(Vector2i(base_tx, base_ty))
		and plan.is_floor(Vector2i(base_tx + 1, base_ty))
		and plan.is_floor(Vector2i(base_tx, base_ty + 1))
		and plan.is_floor(Vector2i(base_tx + 1, base_ty + 1))
	):
		var x0: float = float(base_tx) * TILE_SIZE
		var y0: float = float(base_ty) * TILE_SIZE
		var x2: float = float(base_tx + CHUNK_SIZE_TILES) * TILE_SIZE
		var y2: float = float(base_ty + CHUNK_SIZE_TILES) * TILE_SIZE
		return PackedVector2Array(
			[
				Vector2(x0, y0),
				Vector2(x2, y0),
				Vector2(x2, y2),
				Vector2(x0, y0),
				Vector2(x2, y2),
				Vector2(x0, y2),
			]
		)
	var verts: PackedVector2Array = PackedVector2Array()
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
	return verts


func _extract_chunked_wall_segments(plan: WorldPlan) -> void:
	var rects: Array[Rect2i] = plan.carve_rects
	var grid: SpatialGrid = plan.spatial_grid

	for r: Rect2i in rects:
		_extract_horizontal_edge(r, r.position.y, r.position.y - 1, rects, grid, _chunk_segments)
		_extract_horizontal_edge(r, r.end.y, r.end.y, rects, grid, _chunk_segments)
		_extract_vertical_edge(r, r.position.x, r.position.x - 1, rects, grid, _chunk_segments)
		_extract_vertical_edge(r, r.end.x, r.end.x, rects, grid, _chunk_segments)


func _extract_horizontal_edge(
	r: Rect2i,
	y_line: int,
	y_outside: int,
	rects: Array[Rect2i],
	grid: SpatialGrid,
	target_segments: Dictionary[Vector2i, PackedVector2Array],
) -> void:
	var blockers: Array[Vector2i] = []
	var query: Rect2i = Rect2i(r.position.x, y_outside, r.size.x, 1)
	for idx: int in grid.get_candidate_ids_for_rect(query):
		var other: Rect2i = rects[idx]
		if other == r:
			continue
		if other.position.y <= y_outside and other.end.y > y_outside:
			var ox1: int = maxi(r.position.x, other.position.x)
			var ox2: int = mini(r.end.x, other.end.x)
			if ox2 > ox1:
				blockers.append(Vector2i(ox1, ox2))

	for w: Vector2i in _subtract_intervals(r.position.x, r.end.x, blockers):
		_split_horizontal(w.x, w.y, y_line, target_segments)


func _extract_vertical_edge(
	r: Rect2i,
	x_line: int,
	x_outside: int,
	rects: Array[Rect2i],
	grid: SpatialGrid,
	target_segments: Dictionary[Vector2i, PackedVector2Array],
) -> void:
	var blockers: Array[Vector2i] = []
	var query: Rect2i = Rect2i(x_outside, r.position.y, 1, r.size.y)
	for idx: int in grid.get_candidate_ids_for_rect(query):
		var other: Rect2i = rects[idx]
		if other == r:
			continue
		if other.position.x <= x_outside and other.end.x > x_outside:
			var oy1: int = maxi(r.position.y, other.position.y)
			var oy2: int = mini(r.end.y, other.end.y)
			if oy2 > oy1:
				blockers.append(Vector2i(oy1, oy2))

	for w: Vector2i in _subtract_intervals(r.position.y, r.end.y, blockers):
		_split_vertical(w.x, w.y, x_line, target_segments)


func _split_horizontal(min_x: int, max_x: int, y: int, target_segments: Dictionary[Vector2i, PackedVector2Array]) -> void:
	var cy: int = floori(float(y) / float(CHUNK_SIZE_TILES))
	var cur_x: int = min_x
	while cur_x < max_x:
		var cx: int = floori(float(cur_x) / float(CHUNK_SIZE_TILES))
		var next_chunk_x: int = (cx + 1) * CHUNK_SIZE_TILES
		var end_x: int = mini(max_x, next_chunk_x)

		var coord: Vector2i = Vector2i(cx, cy)
		if not target_segments.has(coord):
			target_segments[coord] = PackedVector2Array()
		var pts: PackedVector2Array = target_segments[coord]
		pts.append(Vector2(float(cur_x) * TILE_SIZE, float(y) * TILE_SIZE))
		pts.append(Vector2(float(end_x) * TILE_SIZE, float(y) * TILE_SIZE))
		target_segments[coord] = pts
		cur_x = end_x


func _split_vertical(min_y: int, max_y: int, x: int, target_segments: Dictionary[Vector2i, PackedVector2Array]) -> void:
	var cx: int = floori(float(x) / float(CHUNK_SIZE_TILES))
	var cur_y: int = min_y
	while cur_y < max_y:
		var cy: int = floori(float(cur_y) / float(CHUNK_SIZE_TILES))
		var next_chunk_y: int = (cy + 1) * CHUNK_SIZE_TILES
		var end_y: int = mini(max_y, next_chunk_y)

		var coord: Vector2i = Vector2i(cx, cy)
		if not target_segments.has(coord):
			target_segments[coord] = PackedVector2Array()
		var pts: PackedVector2Array = target_segments[coord]
		pts.append(Vector2(float(x) * TILE_SIZE, float(cur_y) * TILE_SIZE))
		pts.append(Vector2(float(x) * TILE_SIZE, float(end_y) * TILE_SIZE))
		target_segments[coord] = pts
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
