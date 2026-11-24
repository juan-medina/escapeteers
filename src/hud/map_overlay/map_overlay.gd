# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name MapOverlay
extends Control


class MapRegion:
	extends RefCounted
	var coord: Vector2i
	var unexplored_chunks: Dictionary[Vector2i, PackedVector2Array] = {}
	var explored_verts: PackedVector2Array = PackedVector2Array()
	var wall_verts: PackedVector2Array = PackedVector2Array()
	var explored_ranges: Dictionary[Vector2i, Vector2i] = {}
	var wall_ranges: Dictionary[Vector2i, Vector2i] = {}
	var unexplored_mesh: MeshInstance2D = null
	var explored_mesh: MeshInstance2D = null
	var walls_mesh: MeshInstance2D = null
	var unexplored_dirty: bool = false
	var explored_dirty: bool = false
	var walls_dirty: bool = false

	func _init(region_coord: Vector2i) -> void:
		coord = region_coord


const TILE_SIZE: float = 16.0
const CHUNK_SIZE_TILES: int = 2
const CHUNK_SIZE_PX: float = float(CHUNK_SIZE_TILES) * TILE_SIZE
const REGION_SHIFT: int = 4
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
var _regions: Dictionary[Vector2i, MapRegion] = {}
var _dirty_regions: Dictionary[Vector2i, bool] = {}
var _unexplored_mesh_pool: Array[MeshInstance2D] = []
var _explored_mesh_pool: Array[MeshInstance2D] = []
var _walls_mesh_pool: Array[MeshInstance2D] = []
var _unexplored_pool_idx: int = 0
var _explored_pool_idx: int = 0
var _walls_pool_idx: int = 0
var _discovered_rooms: Dictionary[Rect2i, bool] = {}
var _cleared_rooms: Dictionary[Rect2i, bool] = {}
var _room_labels: Dictionary[Rect2i, Label] = {}
var _label_pool: Array[Label] = []
var _last_revealed_chunk: Vector2i = Vector2i(2147483647, 2147483647)
var _anchor_map_pos: Vector2 = Vector2.ZERO
var _has_anchor: bool = false
var _is_recentering: bool = false
var _dirty: bool = false
var _opened_shortcuts: Dictionary[WorldPlan.KeyColor, bool] = {}
var _collected_keys: Dictionary[WorldPlan.KeyColor, bool] = {}
var _door_entries: Array[Dictionary] = []
var _key_entries: Array[Dictionary] = []
var _pulse_time: float = 0.0
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
@onready var _door_markers: Array[Sprite2D] = [
	$GateMarkers/BlueDoorMarker,
	$GateMarkers/GreenDoorMarker,
	$GateMarkers/YellowDoorMarker,
	$GateMarkers/RedDoorMarker,
]
@onready var _door_rings: Array[Line2D] = [
	$GateMarkers/BlueDoorMarker/HighlightRing,
	$GateMarkers/GreenDoorMarker/HighlightRing,
	$GateMarkers/YellowDoorMarker/HighlightRing,
	$GateMarkers/RedDoorMarker/HighlightRing,
]
@onready var _key_markers: Array[Sprite2D] = [
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
	_pulse_time += delta
	if not is_instance_valid(_target):
		return
	_update_discovery()
	if visible:
		if _dirty:
			_rebuild_meshes()
		_update_view(delta)
		_update_matching_door_pulses()
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


func set_key_state(color: WorldPlan.KeyColor, collected: bool, _used: bool) -> void:
	if collected:
		_collected_keys[color] = true
	else:
		_collected_keys.erase(color)
	_update_gate_markers_visibility()


func notify_door_unlocked(gate: SectorGatePlanner.SectorGate) -> void:
	if _plan != null:
		_visibility.open_door(gate)
		_visited_fov_chunks.clear()
		_last_revealed_chunk = Vector2i(2147483647, 2147483647)
	_update_gate_markers_visibility()


func notify_shortcut_opened(color: WorldPlan.KeyColor) -> void:
	if _opened_shortcuts.has(color) or _plan == null:
		return
	_opened_shortcuts[color] = true
	var changed: bool = false
	for gate: SectorGatePlanner.SectorGate in _plan.sector_gates:
		if gate.color != color or not gate.has_shortcut:
			continue
		_visibility.open_shortcut(gate)
		for coord: Vector2i in gate.opened_map_chunk_coords:
			var region: MapRegion = _get_or_create_region(coord)
			var was_revealed: bool = _revealed_chunks.has(coord)
			if gate.opened_map_floors.has(coord):
				_chunk_floor_vertices[coord] = gate.opened_map_floors[coord]
			if gate.opened_map_walls.has(coord):
				_chunk_segments[coord] = gate.opened_map_walls[coord]
			else:
				_chunk_segments.erase(coord)
			var new_floors: PackedVector2Array = _chunk_floor_vertices.get(coord, PackedVector2Array())
			var new_walls: PackedVector2Array = _chunk_segments.get(coord, PackedVector2Array())
			if not was_revealed:
				_revealed_chunks[coord] = true
				if not new_floors.is_empty():
					region.unexplored_chunks[coord] = new_floors
					region.unexplored_dirty = true
					_dirty_regions[region.coord] = true
			else:
				if _explored_chunks.has(coord):
					_replace_explored_chunk(region, coord, new_floors)
				elif not new_floors.is_empty():
					region.unexplored_chunks[coord] = new_floors
					region.unexplored_dirty = true
					_dirty_regions[region.coord] = true
				elif region.unexplored_chunks.erase(coord):
					region.unexplored_dirty = true
					_dirty_regions[region.coord] = true
				if region.wall_ranges.has(coord):
					var span: Vector2i = region.wall_ranges[coord]
					for i: int in range(span.x, span.x + span.y):
						region.wall_verts[i] = Vector2.ZERO
					region.wall_ranges.erase(coord)
					region.walls_dirty = true
					_dirty_regions[region.coord] = true
			_append_wall_chunk(region, coord, new_walls)
			changed = true

	_visited_fov_chunks.clear()
	_last_revealed_chunk = Vector2i(2147483647, 2147483647)
	if changed:
		_dirty = true
		_update_gate_markers_visibility()


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
		var region: MapRegion = _get_or_create_region(coord)
		if not _revealed_chunks.has(coord):
			_revealed_chunks[coord] = true
			markers_changed = true
			if _chunk_segments.has(coord):
				_append_wall_chunk(region, coord, _chunk_segments[coord])
			if not is_explore and _chunk_floor_vertices.has(coord):
				region.unexplored_chunks[coord] = _chunk_floor_vertices[coord]
				region.unexplored_dirty = true
				_dirty_regions[region.coord] = true

		if is_explore and not _explored_chunks.has(coord):
			_explored_chunks[coord] = true
			if region.unexplored_chunks.erase(coord):
				region.unexplored_dirty = true
				_dirty_regions[region.coord] = true
			if _chunk_floor_vertices.has(coord):
				_append_explored_chunk(region, coord, _chunk_floor_vertices[coord])

	if markers_changed:
		_update_gate_markers_visibility()
	if not _dirty_regions.is_empty():
		_dirty = true
		if visible:
			_rebuild_meshes()


static func _chunk_to_region(coord: Vector2i) -> Vector2i:
	return Vector2i(coord.x >> REGION_SHIFT, coord.y >> REGION_SHIFT)


func _get_or_create_region(chunk_coord: Vector2i) -> MapRegion:
	var region_coord: Vector2i = _chunk_to_region(chunk_coord)
	if _regions.has(region_coord):
		return _regions[region_coord]
	var region: MapRegion = MapRegion.new(region_coord)
	_regions[region_coord] = region
	return region


func _acquire_layer_mesh(parent: MeshInstance2D, pool: Array[MeshInstance2D], pool_idx: int) -> MeshInstance2D:
	if pool_idx < pool.size():
		var existing: MeshInstance2D = pool[pool_idx]
		existing.visible = true
		return existing
	var inst: MeshInstance2D = MeshInstance2D.new()
	inst.self_modulate = parent.self_modulate
	parent.add_child(inst)
	pool.append(inst)
	return inst


static func _reset_layer_pool(pool: Array[MeshInstance2D]) -> void:
	for inst: MeshInstance2D in pool:
		inst.visible = false
		inst.mesh = null


func _append_wall_chunk(region: MapRegion, coord: Vector2i, segs: PackedVector2Array) -> void:
	if segs.is_empty():
		return
	region.wall_ranges[coord] = Vector2i(region.wall_verts.size(), segs.size())
	region.wall_verts.append_array(segs)
	region.walls_dirty = true
	_dirty_regions[region.coord] = true


func _append_explored_chunk(region: MapRegion, coord: Vector2i, verts: PackedVector2Array) -> void:
	if verts.is_empty():
		return
	region.explored_ranges[coord] = Vector2i(region.explored_verts.size(), verts.size())
	region.explored_verts.append_array(verts)
	region.explored_dirty = true
	_dirty_regions[region.coord] = true


func _replace_explored_chunk(region: MapRegion, coord: Vector2i, verts: PackedVector2Array) -> void:
	if region.explored_ranges.has(coord):
		var span: Vector2i = region.explored_ranges[coord]
		for i: int in range(span.x, span.x + span.y):
			region.explored_verts[i] = Vector2.ZERO
		region.explored_ranges.erase(coord)
		region.explored_dirty = true
		_dirty_regions[region.coord] = true
	_append_explored_chunk(region, coord, verts)


func _rebuild_meshes() -> void:
	if not _dirty:
		return
	_dirty = false

	for rc: Vector2i in _dirty_regions:
		var region: MapRegion = _regions[rc]
		if region.unexplored_dirty:
			region.unexplored_dirty = false
			var unexp_verts: PackedVector2Array = PackedVector2Array()
			for coord: Vector2i in region.unexplored_chunks:
				unexp_verts.append_array(region.unexplored_chunks[coord])
			if unexp_verts.is_empty():
				if region.unexplored_mesh != null:
					region.unexplored_mesh.mesh = null
					region.unexplored_mesh.visible = false
			else:
				if region.unexplored_mesh == null:
					region.unexplored_mesh = _acquire_layer_mesh(_unexplored_floor_mesh, _unexplored_mesh_pool, _unexplored_pool_idx)
					_unexplored_pool_idx += 1
				else:
					region.unexplored_mesh.visible = true
				region.unexplored_mesh.mesh = _create_simple_mesh(unexp_verts, Mesh.PRIMITIVE_TRIANGLES)

		if region.explored_dirty:
			region.explored_dirty = false
			if region.explored_verts.is_empty():
				if region.explored_mesh != null:
					region.explored_mesh.mesh = null
					region.explored_mesh.visible = false
			else:
				if region.explored_mesh == null:
					region.explored_mesh = _acquire_layer_mesh(_explored_floor_mesh, _explored_mesh_pool, _explored_pool_idx)
					_explored_pool_idx += 1
				else:
					region.explored_mesh.visible = true
				region.explored_mesh.mesh = _create_simple_mesh(region.explored_verts, Mesh.PRIMITIVE_TRIANGLES)

		if region.walls_dirty:
			region.walls_dirty = false
			if region.wall_verts.is_empty():
				if region.walls_mesh != null:
					region.walls_mesh.mesh = null
					region.walls_mesh.visible = false
			else:
				if region.walls_mesh == null:
					region.walls_mesh = _acquire_layer_mesh(_walls_mesh, _walls_mesh_pool, _walls_pool_idx)
					_walls_pool_idx += 1
				else:
					region.walls_mesh.visible = true
				region.walls_mesh.mesh = _create_simple_mesh(region.wall_verts, Mesh.PRIMITIVE_LINES)

	_dirty_regions.clear()


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
	_reset_layer_pool(_unexplored_mesh_pool)
	_reset_layer_pool(_explored_mesh_pool)
	_reset_layer_pool(_walls_mesh_pool)
	_unexplored_pool_idx = 0
	_explored_pool_idx = 0
	_walls_pool_idx = 0
	_dirty = false
	_plan = plan
	_revealed_chunks.clear()
	_explored_chunks.clear()
	_regions.clear()
	_dirty_regions.clear()
	_discovered_rooms.clear()
	_cleared_rooms.clear()
	_room_labels.clear()
	_chunk_segments.clear()
	_chunk_floor_vertices.clear()
	_opened_shortcuts.clear()
	_collected_keys.clear()
	_door_entries.clear()
	_key_entries.clear()
	_pulse_time = 0.0
	_visited_fov_chunks.clear()
	_fov_chunks.clear()
	for marker: Sprite2D in _door_markers:
		marker.visible = false
	for ring: Line2D in _door_rings:
		ring.visible = false
	for marker: Sprite2D in _key_markers:
		marker.visible = false
	for ind: Node2D in _hud_door_indicators:
		ind.visible = false
		ind.scale = Vector2.ONE
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
			var marker: Sprite2D = _door_markers[color_idx]
			var ring: Line2D = _door_rings[color_idx]
			marker.position = (door_world * map_scale).round()
			_door_entries.append({&"gate": gate, &"marker": marker, &"ring": ring, &"world_pos": door_world})
		if gate.has_key and color_idx >= 0 and color_idx < _key_markers.size():
			var key_mid: Vector2 = Vector2(gate.key_cell) + Vector2(0.5, 0.5)
			var key_world: Vector2 = key_mid * TILE_SIZE
			var key_marker: Sprite2D = _key_markers[color_idx]
			key_marker.position = (key_world * map_scale).round()
			_key_entries.append({&"gate": gate, &"marker": key_marker, &"world_pos": key_world})

		if not gate.has_shortcut or gate.key_room == gate.shortcut_target_room or gate.shortcut_corridor_rects.is_empty():
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
	for entry: Dictionary in _door_entries:
		var gate: SectorGatePlanner.SectorGate = entry[&"gate"]
		var marker: Sprite2D = entry[&"marker"]
		var ring: Line2D = entry[&"ring"]
		var c0: Vector2i = _cell_to_map_chunk(gate.door_cells[0])
		var c1: Vector2i = _cell_to_map_chunk(gate.door_cells[1])
		var is_revealed: bool = _revealed_chunks.has(c0) or _revealed_chunks.has(c1)
		marker.visible = is_revealed and not gate.door_unlocked
		var is_ready: bool = marker.visible and _collected_keys.has(gate.color)
		ring.visible = is_ready
		marker.scale = Vector2.ONE
		marker.self_modulate.a = 1.0 if is_ready else 0.85

	for entry: Dictionary in _key_entries:
		var gate: SectorGatePlanner.SectorGate = entry[&"gate"]
		var marker: Sprite2D = entry[&"marker"]
		var key_chunk: Vector2i = _cell_to_map_chunk(gate.key_cell)
		marker.visible = _revealed_chunks.has(key_chunk) and not _collected_keys.has(gate.color)

	_update_hud_edge_indicators()


func _update_matching_door_pulses() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_pulse_time * 6.0)
	for entry: Dictionary in _door_entries:
		var marker: Sprite2D = entry[&"marker"]
		var ring: Line2D = entry[&"ring"]
		if ring.visible:
			ring.scale = Vector2.ONE * lerpf(0.92, 1.28, pulse)
			ring.modulate.a = lerpf(0.55, 1.0, pulse)
			marker.scale = Vector2.ONE * lerpf(1.0, 1.12, pulse)


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
	var pulse: float = 0.5 + 0.5 * sin(_pulse_time * 6.0)
	for i: int in range(_door_markers.size()):
		var target_color: WorldPlan.KeyColor = i as WorldPlan.KeyColor
		var best_pos: Vector2 = Vector2.ZERO
		var has_door: bool = false
		var best_off_screen: bool = false
		var best_dist_sq: float = INF
		if is_instance_valid(_target):
			for entry: Dictionary in _door_entries:
				var gate: SectorGatePlanner.SectorGate = entry[&"gate"]
				var marker: Sprite2D = entry[&"marker"]
				if gate.color != target_color or not marker.visible:
					continue
				var world_pos: Vector2 = entry[&"world_pos"]
				var screen_pos: Vector2 = (size * 0.5) + (world_pos - _target.global_position)
				var is_off: bool = not on_screen_rect.has_point(screen_pos)
				var d_sq: float = _target.global_position.distance_squared_to(world_pos)
				if not has_door or (is_off and not best_off_screen) or (is_off == best_off_screen and d_sq < best_dist_sq):
					has_door = true
					best_off_screen = is_off
					best_dist_sq = d_sq
					best_pos = world_pos
		_update_hud_indicator(
			has_door,
			best_pos,
			_hud_door_indicators[i],
			_hud_door_arrows[i],
			on_screen_rect,
			min_bound,
			max_bound,
		)
		if _hud_door_indicators[i].visible and _collected_keys.has(target_color):
			_hud_door_indicators[i].scale = Vector2.ONE * lerpf(1.0, 1.16, pulse)
		else:
			_hud_door_indicators[i].scale = Vector2.ONE

	for i: int in range(_key_markers.size()):
		var target_color: WorldPlan.KeyColor = i as WorldPlan.KeyColor
		var key_pos: Vector2 = Vector2.ZERO
		var has_key: bool = false
		for entry: Dictionary in _key_entries:
			var gate: SectorGatePlanner.SectorGate = entry[&"gate"]
			var marker: Sprite2D = entry[&"marker"]
			if gate.color == target_color and marker.visible:
				has_key = true
				key_pos = entry[&"world_pos"]
				break
		_update_hud_indicator(
			has_key,
			key_pos,
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
