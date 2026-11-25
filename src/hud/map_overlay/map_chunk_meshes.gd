# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

## Manages chunked dungeon map floor/wall geometry extraction and regional ArrayMesh pooling.
class_name MapChunkMeshes
extends RefCounted


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
const REGION_SHIFT: int = 4

var _unexplored_floor_mesh: MeshInstance2D = null
var _explored_floor_mesh: MeshInstance2D = null
var _walls_mesh: MeshInstance2D = null
var _chunk_segments: Dictionary[Vector2i, PackedVector2Array] = {}
var _chunk_floor_vertices: Dictionary[Vector2i, PackedVector2Array] = {}
var _regions: Dictionary[Vector2i, MapRegion] = {}
var _dirty_regions: Dictionary[Vector2i, bool] = {}
var _unexplored_mesh_pool: Array[MeshInstance2D] = []
var _explored_mesh_pool: Array[MeshInstance2D] = []
var _walls_mesh_pool: Array[MeshInstance2D] = []
var _unexplored_pool_idx: int = 0
var _explored_pool_idx: int = 0
var _walls_pool_idx: int = 0


func bind_layers(unexplored: MeshInstance2D, explored: MeshInstance2D, walls: MeshInstance2D) -> void:
	_unexplored_floor_mesh = unexplored
	_explored_floor_mesh = explored
	_walls_mesh = walls


func reset(plan: WorldPlan) -> void:
	_reset_layer_pool(_unexplored_mesh_pool)
	_reset_layer_pool(_explored_mesh_pool)
	_reset_layer_pool(_walls_mesh_pool)
	_unexplored_pool_idx = 0
	_explored_pool_idx = 0
	_walls_pool_idx = 0
	_regions.clear()
	_dirty_regions.clear()
	_chunk_segments.clear()
	_chunk_floor_vertices.clear()
	if plan != null and not plan.carve_rects.is_empty():
		_extract_chunked_floors(plan)
		_extract_chunked_wall_segments(plan)


func build_opened_tunnel_data(plan: WorldPlan, gate: SectorGatePlanner.SectorGate) -> void:
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


func reveal_chunk(coord: Vector2i, is_explore: bool) -> void:
	var region: MapRegion = _get_or_create_region(coord)
	if _chunk_segments.has(coord):
		_append_wall_chunk(region, coord, _chunk_segments[coord])
	if not is_explore and _chunk_floor_vertices.has(coord):
		region.unexplored_chunks[coord] = _chunk_floor_vertices[coord]
		region.unexplored_dirty = true
		_dirty_regions[region.coord] = true


func explore_chunk(coord: Vector2i) -> void:
	var region: MapRegion = _get_or_create_region(coord)
	if region.unexplored_chunks.erase(coord):
		region.unexplored_dirty = true
		_dirty_regions[region.coord] = true
	if _chunk_floor_vertices.has(coord):
		_append_explored_chunk(region, coord, _chunk_floor_vertices[coord])


func apply_shortcut_chunk(coord: Vector2i, gate: SectorGatePlanner.SectorGate, was_revealed: bool, is_explored: bool) -> void:
	var region: MapRegion = _get_or_create_region(coord)
	if gate.opened_map_floors.has(coord):
		_chunk_floor_vertices[coord] = gate.opened_map_floors[coord]
	if gate.opened_map_walls.has(coord):
		_chunk_segments[coord] = gate.opened_map_walls[coord]
	else:
		_chunk_segments.erase(coord)
	var new_floors: PackedVector2Array = _chunk_floor_vertices.get(coord, PackedVector2Array())
	var new_walls: PackedVector2Array = _chunk_segments.get(coord, PackedVector2Array())
	if not was_revealed:
		if not new_floors.is_empty():
			region.unexplored_chunks[coord] = new_floors
			region.unexplored_dirty = true
			_dirty_regions[region.coord] = true
	else:
		if is_explored:
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


func has_dirty_regions() -> bool:
	return not _dirty_regions.is_empty()


func rebuild_dirty() -> void:
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


static func _create_simple_mesh(vertices: PackedVector2Array, primitive: Mesh.PrimitiveType) -> ArrayMesh:
	if vertices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(primitive, arrays)
	return mesh


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
