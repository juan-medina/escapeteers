# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name WorldPlan
extends RefCounted

enum RoomArchetype {
	SLIME_PIT,
	BONE_SWARM,
	ARCHER_GARRISON,
	NECRO_CRYPT,
}

enum KeyColor {
	NONE = -1,
	BLUE = 0,
	GREEN = 1,
	YELLOW = 2,
	RED = 3,
}

enum RoomShape {
	RECTANGLE,
	CUT_CORNERS,
	PILLARED,
	CROSS,
	L_SHAPE,
	T_SHAPE,
}

enum FloorPattern {
	BORDER_TRIM,
	CROSSROADS,
	ARENA_RINGS,
	CHECKERED_COURT,
	PILLAR_PLINTHS,
}

const WORLD_SIZE_TILES: int = 4096
const HALF_WORLD_SIZE: int = 2048

const HERO_ROOM_SIZE: Vector2i = Vector2i(18, 18)
const INITIAL_ROOM_COUNT: int = 3
const ROOM_PADDING: int = 8
const CORRIDOR_WIDTH: int = 4
const MAX_PLACEMENT_ATTEMPTS: int = 120
const LOOP_CONNECT_MAX_DISTANCE: float = 95.0
const MIN_ROOM_GAP: float = 14.0
const MAX_ROOM_GAP: float = 28.0
const SECTOR_TARGET_ROOMS: Array[int] = [9, 11, 11, 11, 3]
const MAX_ROOM_DEGREE: int = 3
const MAX_LOOPS_PER_SECTOR: int = 2
const SPIKE_PHASE_GROUPS: int = 4
const TILE_SET_COUNT: int = 8

var run_seed: int = 0
var hero_room: Rect2i = Rect2i()
var rooms: Array[Rect2i] = []
var carve_rects: Array[Rect2i] = []
var spatial_grid: SpatialGrid = SpatialGrid.new()
var room_children: Dictionary[Rect2i, Array] = {}
var baked_chunks: Dictionary[Vector2i, Dictionary] = {}
var spike_tile_sets: Dictionary[Vector2i, int] = {}
var sector_gates: Array[SectorGatePlanner.SectorGate] = []
var door_cell_codes: Dictionary[Vector2i, int] = {}
var closed_shortcut_walls: Dictionary[Vector2i, bool] = {}
var lever_cells: Dictionary[Vector2i, KeyColor] = {}
var no_prop_cells: Dictionary[Vector2i, bool] = {}
var protected_neck_rects: Array[Rect2i] = []

var _room_depths: Dictionary[Rect2i, int] = {}
var _room_sectors: Dictionary[Rect2i, int] = {}
var _room_in_dirs: Dictionary[Rect2i, Vector2] = {}
var _room_archetypes: Dictionary[Rect2i, RoomArchetype] = {}
var _room_tile_sets: Dictionary[Rect2i, int] = {}
var _room_shapes: Dictionary[Rect2i, RoomShape] = {}
var _room_floor_patterns: Dictionary[Rect2i, FloorPattern] = {}
var _room_pillars: Dictionary[Rect2i, Array] = {}
var _room_neighbors: Dictionary[Rect2i, Array] = {}
var _room_enemy_quotas: Dictionary[Rect2i, int] = {}
var _room_companion_spawns: Dictionary[Rect2i, Array] = {}
var _room_grid: SpatialGrid = SpatialGrid.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _candle_post_bases: Dictionary[Vector2i, bool] = {}
var _candle_post_tops: Dictionary[Vector2i, bool] = {}
var _spike_cells: Dictionary[Vector2i, int] = {}
var _corridor_segments: Array[Dictionary] = []
var _corridor_rects: Array[Rect2i] = []
var _corridor_sectors: Array[int] = []
var _all_pillars: Array[Rect2i] = []
var _cut_corner_rects: Array[Rect2i] = []
var _next_spike_group: int = 0


func generate(seed_val: int = 0, max_depth: int = 12) -> void:
	run_seed = seed_val
	if run_seed != 0:
		_rng.seed = run_seed
	else:
		_rng.randomize()
		run_seed = int(_rng.seed)

	rooms.clear()
	carve_rects.clear()
	spatial_grid.clear()
	room_children.clear()
	baked_chunks.clear()
	spike_tile_sets.clear()
	sector_gates.clear()
	door_cell_codes.clear()
	closed_shortcut_walls.clear()
	lever_cells.clear()
	no_prop_cells.clear()
	protected_neck_rects.clear()
	_room_grid.clear()
	_room_depths.clear()
	_room_sectors.clear()
	_room_in_dirs.clear()
	_room_archetypes.clear()
	_room_tile_sets.clear()
	_room_shapes.clear()
	_room_floor_patterns.clear()
	_room_pillars.clear()
	_room_neighbors.clear()
	_room_enemy_quotas.clear()
	_room_companion_spawns.clear()
	_candle_post_bases.clear()
	_candle_post_tops.clear()
	_spike_cells.clear()
	_corridor_segments.clear()
	_corridor_rects.clear()
	_corridor_sectors.clear()
	_all_pillars.clear()
	_cut_corner_rects.clear()
	_next_spike_group = 0

	_create_hero_room()
	_generate_sectors(max_depth)
	_prune_clipped_pillars()
	_color_room_graph()
	_eliminate_narrow_gaps()
	_assign_wing_tile_sets()
	for room: Rect2i in rooms:
		_plan_candle_posts_for_room(room)
	SectorGatePlanner.plan_spike_traps(self)


func is_floor(cell: Vector2i) -> bool:
	if absi(cell.x) >= HALF_WORLD_SIZE or absi(cell.y) >= HALF_WORLD_SIZE:
		return false
	return spatial_grid.has_point(cell, carve_rects)


func get_child_rooms(parent_room: Rect2i) -> Array:
	if room_children.has(parent_room):
		return room_children[parent_room]
	return []


func get_depth_rooms(depth: int) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	for room: Rect2i in rooms:
		if get_room_depth(room) == depth:
			result.append(room)
	return result


func get_room_depth(room: Rect2i) -> int:
	if _room_depths.has(room):
		return _room_depths[room]
	var center_y: float = float(room.get_center().y)
	return maxi(1, int(maxf(0.0, -center_y) / 50.0))


func get_room_tier(room: Rect2i) -> int:
	var depth: int = get_room_depth(room)
	if depth <= 1:
		return 1
	if depth <= 3:
		return 2
	return 3


func get_room_archetype(room: Rect2i) -> RoomArchetype:
	if _room_archetypes.has(room):
		return _room_archetypes[room]
	return RoomArchetype.SLIME_PIT


func get_room_tile_set(room: Rect2i) -> int:
	return _room_tile_sets.get(room, 1)


func get_cell_tile_set(cell: Vector2i) -> int:
	var room: Rect2i = get_room_at(cell)
	if room.size != Vector2i.ZERO:
		return _room_tile_sets.get(room, 1)

	var best_room: Rect2i = hero_room
	var best_dist_sq: int = _dist_sq_to_rect(cell, hero_room)
	if best_dist_sq <= 2:
		return _room_tile_sets.get(best_room, 1)
	for idx: int in _room_grid.get_candidate_ids_for_rect(Rect2i(cell - Vector2i(64, 64), Vector2i(128, 128))):
		var dist_sq: int = _dist_sq_to_rect(cell, rooms[idx])
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_room = rooms[idx]
			if best_dist_sq <= 2:
				break
	return _room_tile_sets.get(best_room, 1)


static func _dist_sq_to_rect(cell: Vector2i, rect: Rect2i) -> int:
	var dx: int = maxi(rect.position.x - cell.x, maxi(0, cell.x - (rect.end.x - 1)))
	var dy: int = maxi(rect.position.y - cell.y, maxi(0, cell.y - (rect.end.y - 1)))
	return dx * dx + dy * dy


func _color_room_graph() -> void:
	var all_colors: Array[RoomArchetype] = [
		RoomArchetype.SLIME_PIT,
		RoomArchetype.BONE_SWARM,
		RoomArchetype.ARCHER_GARRISON,
		RoomArchetype.NECRO_CRYPT,
	]
	var necro_at_depth: Dictionary[int, int] = {}
	for room: Rect2i in rooms:
		if _room_archetypes.has(room):
			continue
		var depth: int = get_room_depth(room)
		var forbidden: Array[RoomArchetype] = _get_neighbor_archetypes(room)
		var candidates: Array[RoomArchetype] = []
		for color: RoomArchetype in all_colors:
			if depth <= 1 and color == RoomArchetype.NECRO_CRYPT:
				continue
			if not forbidden.has(color):
				candidates.append(color)
		if candidates.is_empty():
			candidates.append_array(all_colors)
		var needs_necro: bool = not necro_at_depth.has(depth)
		var chosen: RoomArchetype = _pick_weighted_archetype(candidates, depth, needs_necro)
		_room_archetypes[room] = chosen
		if chosen == RoomArchetype.NECRO_CRYPT:
			necro_at_depth[depth] = (necro_at_depth[depth] + 1) if necro_at_depth.has(depth) else 1


func _get_neighbor_archetypes(room: Rect2i) -> Array[RoomArchetype]:
	var used: Array[RoomArchetype] = []
	if not _room_neighbors.has(room):
		return used
	var neighbors: Array = _room_neighbors[room]
	for n_var: Variant in neighbors:
		if n_var is Rect2i:
			var n_room: Rect2i = n_var
			if _room_archetypes.has(n_room):
				var arch: RoomArchetype = _room_archetypes[n_room]
				if not used.has(arch):
					used.append(arch)
	return used


func _pick_weighted_archetype(candidates: Array[RoomArchetype], depth: int, needs_necro: bool) -> RoomArchetype:
	if depth >= 2 and needs_necro and candidates.has(RoomArchetype.NECRO_CRYPT):
		return RoomArchetype.NECRO_CRYPT
	var total_weight: int = 0
	for c: RoomArchetype in candidates:
		total_weight += _get_archetype_weight(c)
	var roll: int = _rng.randi_range(1, maxi(1, total_weight))
	var accum: int = 0
	var chosen: RoomArchetype = candidates[0]
	for c: RoomArchetype in candidates:
		accum += _get_archetype_weight(c)
		if roll <= accum:
			chosen = c
			break
	return chosen


static func _get_archetype_weight(archetype: RoomArchetype) -> int:
	var weight: int = 25
	if archetype == RoomArchetype.NECRO_CRYPT:
		weight = 35
	elif archetype == RoomArchetype.SLIME_PIT:
		weight = 15
	return weight


func _add_neighbor_edge(room_a: Rect2i, room_b: Rect2i) -> void:
	if not _room_neighbors.has(room_a):
		_room_neighbors[room_a] = []
	if not _room_neighbors[room_a].has(room_b):
		_room_neighbors[room_a].append(room_b)
	if not _room_neighbors.has(room_b):
		_room_neighbors[room_b] = []
	if not _room_neighbors[room_b].has(room_a):
		_room_neighbors[room_b].append(room_a)


func get_room_enemy_quota(room: Rect2i) -> int:
	if _room_enemy_quotas.has(room):
		return _room_enemy_quotas[room]
	var depth: int = get_room_depth(room)
	var area_factor: float = float(room.size.x * room.size.y) / (28.0 * 28.0)
	var steps: int = depth - 1
	var base_min: int = 4 + steps * 4 + steps * steps
	var base_max: int = 6 + steps * 6 + steps * steps
	var scaled_min: int = int(roundf(float(base_min) * clampf(area_factor * 0.65, 0.8, 2.2)))
	var scaled_max: int = int(roundf(float(base_max) * clampf(area_factor * 0.65, 0.8, 2.2)))
	var quota: int = clampi(_rng.randi_range(scaled_min, maxi(scaled_min, scaled_max)), 4, 140)
	_room_enemy_quotas[room] = quota
	return quota


func get_companion_spawns_for_room(room: Rect2i) -> Array:
	if _room_companion_spawns.has(room):
		return _room_companion_spawns[room]
	var spawns: Array[Vector2i] = _compute_companion_spawns_for_room(room)
	_room_companion_spawns[room] = spawns
	return spawns


func get_room_at(cell: Vector2i) -> Rect2i:
	if hero_room.has_point(cell):
		return hero_room
	var candidate_ids: Array = _room_grid.get_candidate_ids_for_point(cell)
	for idx: int in candidate_ids:
		if idx >= 0 and idx < rooms.size():
			if rooms[idx].has_point(cell):
				return rooms[idx]
	return Rect2i()


func is_candle_post_top(cell: Vector2i) -> bool:
	return _candle_post_tops.has(cell)


func is_candle_post_base(cell: Vector2i) -> bool:
	return _candle_post_bases.has(cell)


func is_spike_cell(cell: Vector2i) -> bool:
	return _spike_cells.has(cell)


func get_spike_group(cell: Vector2i) -> int:
	return _spike_cells.get(cell, 0)


func get_floor_plate_index(cell: Vector2i) -> int:
	var room: Rect2i = get_room_at(cell)
	if room.size == Vector2i.ZERO:
		return -1

	var pattern: FloorPattern = _room_floor_patterns.get(room, FloorPattern.BORDER_TRIM)
	if pattern == FloorPattern.PILLAR_PLINTHS:
		var plinth_idx: int = _get_pillar_plinth_plate(cell, room)
		if plinth_idx >= 0:
			return plinth_idx

	if not _is_wall_buffer_free(cell):
		return -1

	var center: Vector2i = room.get_center()
	var result: int = -1
	match pattern:
		FloorPattern.BORDER_TRIM, FloorPattern.PILLAR_PLINTHS:
			result = 0 if _is_border_trim_cell(cell, room) else -1
		FloorPattern.CROSSROADS:
			var dx: int = absi(cell.x - center.x)
			var dy: int = absi(cell.y - center.y)
			var cheb: int = maxi(dx, dy)
			if cheb == 3:
				result = 0
			elif cheb > 3 and (dx == 2 or dy == 2):
				result = 1
		FloorPattern.ARENA_RINGS:
			var cheb: int = maxi(absi(cell.x - center.x), absi(cell.y - center.y))
			if cheb == 4:
				result = 0
			elif mini(room.size.x, room.size.y) >= 24 and cheb == 8:
				result = 1
		FloorPattern.CHECKERED_COURT:
			if absi(cell.x - center.x) % 3 == 0 and absi(cell.y - center.y) % 3 == 0:
				result = 2 if absi(cell.x + cell.y) % 2 == 0 else 3
	return result


func _get_pillar_plinth_plate(cell: Vector2i, room: Rect2i) -> int:
	if not is_floor(cell) or not is_floor(cell + Vector2i(0, -1)):
		return -1
	var pillars: Array = _room_pillars.get(room, [])
	for p_var: Variant in pillars:
		if p_var is Rect2i:
			var p: Rect2i = p_var
			var ring: Rect2i = Rect2i(p.position.x - 1, p.position.y - 1, p.size.x + 2, p.size.y + 3)
			if ring.has_point(cell):
				var on_side: bool = cell.x == ring.position.x or cell.x == ring.end.x - 1
				var on_cap: bool = cell.y == ring.position.y or cell.y == ring.end.y - 1
				return 2 if (on_side and on_cap) else 0
	return -1


func _is_wall_buffer_free(cell: Vector2i) -> bool:
	return (
		is_floor(cell)
		and is_floor(cell + Vector2i(0, -1))
		and is_floor(cell + Vector2i(0, -2))
		and is_floor(cell + Vector2i(0, 1))
		and is_floor(cell + Vector2i(-1, 0))
		and is_floor(cell + Vector2i(1, 0))
	)


func _is_border_trim_cell(cell: Vector2i, room: Rect2i) -> bool:
	var room_pillars: Array = _room_pillars.get(room, [])
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if (dx != 0 or dy != 0) and not _is_wall_buffer_free(cell + Vector2i(dx, dy)):
				var n_cell: Vector2i = cell + Vector2i(dx, dy)
				var in_pillar: bool = false
				for p_var: Variant in room_pillars:
					var p: Rect2i = p_var
					if Rect2i(p.position.x - 1, p.position.y - 1, p.size.x + 2, p.size.y + 3).has_point(n_cell):
						in_pillar = true
						break
				if not in_pillar:
					return true
	return false


func _create_hero_room() -> void:
	var top_left: Vector2i = Vector2i(Vector2(-HERO_ROOM_SIZE) * 0.5)
	hero_room = Rect2i(top_left, HERO_ROOM_SIZE)
	_room_depths[hero_room] = 0
	_room_sectors[hero_room] = 0
	_room_tile_sets[hero_room] = _rng.randi_range(0, TILE_SET_COUNT - 1)
	_room_shapes[hero_room] = RoomShape.RECTANGLE
	_room_floor_patterns[hero_room] = FloorPattern.ARENA_RINGS
	_add_carve_rect(hero_room)


func _generate_sectors(target_max_depth: int) -> void:
	var max_sector: int = SectorGatePlanner.get_sector_for_depth(target_max_depth)
	var entry_room: Rect2i = hero_room

	for sector_idx: int in range(max_sector + 1):
		var sector_rooms: Array[Rect2i] = []
		var hop_from_entry: Dictionary[Rect2i, int] = {entry_room: 0}
		if sector_idx > 0:
			sector_rooms.append(entry_room)

		var target_count: int = SECTOR_TARGET_ROOMS[mini(sector_idx, SECTOR_TARGET_ROOMS.size() - 1)]
		var south_limit_y: int = (hero_room.end.y + 45) if sector_idx == 0 else (entry_room.end.y + 25)
		var active_tips: Array[Rect2i] = _create_sector_wings(
			entry_room,
			sector_idx,
			target_count,
			target_max_depth,
			sector_rooms,
			hop_from_entry,
			south_limit_y,
		)
		_grow_sector_maze(
			entry_room,
			sector_idx,
			target_count,
			target_max_depth,
			sector_rooms,
			hop_from_entry,
			active_tips,
			south_limit_y,
		)

		if sector_idx < SectorGatePlanner.GATE_DEPTHS.size() and SectorGatePlanner.GATE_DEPTHS[sector_idx] < target_max_depth:
			var gate_depth: int = SectorGatePlanner.GATE_DEPTHS[sector_idx]
			var next_entry: Rect2i = SectorGatePlanner.build_sector_gate(self, sector_rooms, entry_room, sector_idx, gate_depth)
			if next_entry.size == Vector2i.ZERO:
				break
			entry_room = next_entry


func _create_sector_wings(
	entry_room: Rect2i,
	sector_idx: int,
	target_count: int,
	target_max_depth: int,
	sector_rooms: Array[Rect2i],
	hop_from_entry: Dictionary[Rect2i, int],
	south_limit_y: int,
) -> Array[Rect2i]:
	var wings: Array[Rect2i] = []
	var wing_angles: Array[float] = [-PI * 0.88, -PI * 0.5, -PI * 0.12]
	var desired_wings: int = INITIAL_ROOM_COUNT if sector_idx == 0 else mini(target_count - sector_rooms.size(), INITIAL_ROOM_COUNT)

	var starter_archetypes: Array[RoomArchetype] = [
		RoomArchetype.SLIME_PIT,
		RoomArchetype.BONE_SWARM,
		RoomArchetype.ARCHER_GARRISON,
	]
	if sector_idx == 0:
		for s_idx: int in range(starter_archetypes.size() - 1, 0, -1):
			var swap_idx: int = _rng.randi_range(0, s_idx)
			var tmp: RoomArchetype = starter_archetypes[s_idx]
			starter_archetypes[s_idx] = starter_archetypes[swap_idx]
			starter_archetypes[swap_idx] = tmp
	else:
		for a_idx: int in range(wing_angles.size() - 1, 0, -1):
			var swap_idx: int = _rng.randi_range(0, a_idx)
			var tmp_a: float = wing_angles[a_idx]
			wing_angles[a_idx] = wing_angles[swap_idx]
			wing_angles[swap_idx] = tmp_a

	var child_depth: int = _compute_depth_for_hop(sector_idx, 1, target_max_depth)
	var placed: int = 0
	for slot_idx: int in range(wing_angles.size()):
		if placed >= desired_wings:
			break
		var base_angle: float = wing_angles[slot_idx]
		for _attempt: int in range(40):
			var angle: float = base_angle + _rng.randf_range(-0.22, 0.22)
			var cand: Rect2i = _try_place_maze_child(entry_room, sector_idx, child_depth, angle, south_limit_y, false)
			if cand.size != Vector2i.ZERO:
				if sector_idx == 0:
					_room_archetypes[cand] = starter_archetypes[placed % starter_archetypes.size()]
				sector_rooms.append(cand)
				hop_from_entry[cand] = 1
				wings.append(cand)
				placed += 1
				break

	if wings.is_empty() and sector_idx > 0:
		for _rescue: int in range(60):
			var angle: float = _rng.randf_range(-PI * 0.96, 0.20)
			var cand: Rect2i = _try_place_maze_child(entry_room, sector_idx, child_depth, angle, south_limit_y, false)
			if cand.size != Vector2i.ZERO:
				sector_rooms.append(cand)
				hop_from_entry[cand] = 1
				wings.append(cand)
				break
	return wings


func _grow_sector_maze(
	entry_room: Rect2i,
	sector_idx: int,
	target_count: int,
	target_max_depth: int,
	sector_rooms: Array[Rect2i],
	hop_from_entry: Dictionary[Rect2i, int],
	active_tips: Array[Rect2i],
	south_limit_y: int,
) -> void:
	if active_tips.is_empty() and sector_idx > 0:
		active_tips.append(entry_room)

	var exhausted: Dictionary[Rect2i, bool] = {}
	var guard: int = 0
	var max_iters: int = target_count * 25
	while sector_rooms.size() < target_count and guard < max_iters:
		guard += 1
		var parent: Rect2i = _pick_maze_parent(active_tips, sector_rooms, exhausted)
		if parent.size == Vector2i.ZERO:
			break

		var parent_hop: int = hop_from_entry.get(parent, 1)
		var child_hop: int = parent_hop + 1
		var child_depth: int = _compute_depth_for_hop(sector_idx, child_hop, target_max_depth)
		var placed: bool = false

		for _attempt: int in range(20):
			var angle: float = _pick_maze_angle(parent)
			var cand: Rect2i = _try_place_maze_child(parent, sector_idx, child_depth, angle, south_limit_y, false)
			if cand.size != Vector2i.ZERO:
				sector_rooms.append(cand)
				hop_from_entry[cand] = child_hop
				active_tips.append(cand)
				placed = true
				break

		if not placed:
			active_tips.erase(parent)
			exhausted[parent] = true


func _pick_maze_parent(active_tips: Array[Rect2i], sector_rooms: Array[Rect2i], exhausted: Dictionary[Rect2i, bool]) -> Rect2i:
	for i: int in range(active_tips.size() - 1, -1, -1):
		var tip: Rect2i = active_tips[i]
		if exhausted.has(tip) or _get_room_degree(tip) >= MAX_ROOM_DEGREE:
			active_tips.remove_at(i)

	if not active_tips.is_empty() and (_rng.randf() < 0.70 or sector_rooms.is_empty()):
		if active_tips.size() > 1 and _rng.randf() < 0.25:
			return active_tips[active_tips.size() - 2]
		return active_tips[active_tips.size() - 1]

	var open_rooms: Array[Rect2i] = []
	for r: Rect2i in sector_rooms:
		if not exhausted.has(r) and _get_room_degree(r) < MAX_ROOM_DEGREE:
			open_rooms.append(r)
	if not open_rooms.is_empty():
		return open_rooms[_rng.randi_range(0, open_rooms.size() - 1)]
	return Rect2i()


func _get_room_degree(room: Rect2i) -> int:
	if not _room_neighbors.has(room):
		return 0
	return _room_neighbors[room].size()


func _pick_maze_angle(parent: Rect2i) -> float:
	var in_dir: Vector2 = _room_in_dirs.get(parent, Vector2.UP)
	var base_angle: float = in_dir.angle()
	var roll: float = _rng.randf()
	var angle: float = base_angle
	if roll < 0.35:
		angle = base_angle + _rng.randf_range(-0.45, 0.45)
	elif roll < 0.63:
		angle = base_angle - PI * 0.5 + _rng.randf_range(-0.40, 0.40)
	elif roll < 0.91:
		angle = base_angle + PI * 0.5 + _rng.randf_range(-0.40, 0.40)
	else:
		var sign_dir: float = -1.0 if _rng.randf() < 0.5 else 1.0
		angle = base_angle + sign_dir * _rng.randf_range(1.85, 2.35)

	var cx: int = parent.get_center().x
	if absi(cx) > 380 and _rng.randf() < 0.65:
		var inward_angle: float = -PI * 0.25 if cx < 0 else -PI * 0.75
		angle = lerp_angle(angle, inward_angle, 0.65)
	return angle


func _try_place_maze_child(
	parent_room: Rect2i,
	sector_idx: int,
	child_depth: int,
	angle: float,
	south_limit_y: int,
	require_clear_north: bool = false,
) -> Rect2i:
	var dir: Vector2 = Vector2.from_angle(angle)
	var size: Vector2i = RoomLayout.roll_room_size(_rng, child_depth)
	var extent_a: float = absf(dir.x) * float(parent_room.size.x) * 0.5 + absf(dir.y) * float(parent_room.size.y) * 0.5
	var extent_b: float = absf(dir.x) * float(size.x) * 0.5 + absf(dir.y) * float(size.y) * 0.5
	var step_dist: float = extent_a + extent_b + _rng.randf_range(MIN_ROOM_GAP, MAX_ROOM_GAP)
	var center_pos: Vector2 = Vector2(parent_room.get_center()) + dir * step_dist
	var top_left: Vector2i = Vector2i(center_pos.round()) - Vector2i(Vector2(size) * 0.5)
	var candidate: Rect2i = Rect2i(top_left, size)

	if candidate.end.y > south_limit_y or _is_outside_world_bounds(candidate) or _overlaps_any_room(candidate):
		return Rect2i()

	var shape: RoomShape = RoomLayout.pick_room_shape(_rng, size)
	var cutouts: Array[Rect2i] = RoomLayout.build_room_cutouts(_rng, candidate, shape)
	var segs: Array[Dictionary] = RoomLayout.plan_corridor(self, parent_room, candidate, cutouts, sector_idx, false)
	if segs.is_empty():
		return Rect2i()

	if require_clear_north:
		var n_probe: Rect2i = Rect2i(candidate.get_center().x - 4, candidate.position.y - 6, 8, 6)
		for seg: Dictionary in segs:
			var seg_rect: Rect2i = seg[&"rect"]
			if seg_rect.intersects(n_probe):
				return Rect2i()
		if spatial_grid.intersects_any(n_probe, carve_rects, 0):
			return Rect2i()

	if not room_children.has(parent_room):
		room_children[parent_room] = []
	room_children[parent_room].append(candidate)
	_add_neighbor_edge(parent_room, candidate)
	_room_in_dirs[candidate] = dir
	_add_room_with_layout(candidate, child_depth, sector_idx, shape, cutouts)
	RoomLayout.commit_corridor(self, segs, sector_idx)
	return candidate


static func _compute_depth_for_hop(sector_idx: int, hop: int, max_depth: int) -> int:
	var raw_depth: int = 12
	match sector_idx:
		0:
			raw_depth = 1 if hop <= 1 else 2
		1:
			raw_depth = 3 if hop == 0 else (4 if hop <= 2 else 5)
		2:
			raw_depth = 6 if hop == 0 else (7 if hop <= 2 else 8)
		3:
			raw_depth = 9 if hop == 0 else (10 if hop <= 2 else 11)
		_:
			raw_depth = 12
	return mini(raw_depth, max_depth)


func _add_room(room: Rect2i, depth: int, sector_idx: int = -1) -> void:
	var shape: RoomShape = RoomLayout.pick_room_shape(_rng, room.size)
	var cutouts: Array[Rect2i] = RoomLayout.build_room_cutouts(_rng, room, shape)
	var resolved_sector: int = sector_idx if sector_idx >= 0 else SectorGatePlanner.get_sector_for_depth(depth)
	_add_room_with_layout(room, depth, resolved_sector, shape, cutouts)


func _add_room_with_layout(
	room: Rect2i,
	depth: int,
	sector_idx: int,
	shape: RoomShape,
	cutouts: Array[Rect2i],
) -> void:
	rooms.append(room)
	_room_depths[room] = depth
	_room_sectors[room] = sector_idx
	_room_tile_sets[room] = _rng.randi_range(0, TILE_SET_COUNT - 1)
	_room_shapes[room] = shape
	_room_floor_patterns[room] = RoomLayout.pick_floor_pattern(_rng, shape)

	_room_grid.add_rect(rooms.size() - 1, room)
	RoomLayout.carve_room_layout(self, room, shape, cutouts)
	get_room_enemy_quota(room)
	get_companion_spawns_for_room(room)


func _prune_clipped_pillars() -> void:
	for room: Rect2i in rooms:
		if not _room_pillars.has(room):
			continue
		var pillars: Array = _room_pillars[room]
		var kept: Array[Rect2i] = []
		for p_var: Variant in pillars:
			if p_var is Rect2i:
				var p: Rect2i = p_var
				var padded: Rect2i = p.grow(1)
				var touched: bool = false
				for c_rect: Rect2i in _corridor_rects:
					if c_rect.intersects(padded):
						touched = true
						break
				if touched:
					_add_carve_rect(p)
					_all_pillars.erase(p)
				else:
					kept.append(p)
		_room_pillars[room] = kept


func _add_carve_rect(rect: Rect2i) -> void:
	carve_rects.append(rect)
	spatial_grid.add_rect(carve_rects.size() - 1, rect)


func _plan_candle_posts_for_room(room: Rect2i) -> void:
	var cols: int = maxi(1, roundi(float(room.size.x - 6) / 14.0))
	var rows: int = maxi(1, roundi(float(room.size.y - 6) / 14.0))
	var center: Vector2i = room.get_center()

	var step_x: float = float(room.size.x - 6) / float(cols + 1)
	var step_y: float = float(room.size.y - 6) / float(rows + 1)
	var nudges: Array[Vector2i] = [Vector2i.ZERO, Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2), Vector2i(2, 2), Vector2i(-2, -2)]

	for r_idx: int in range(rows):
		var target_y: int = room.position.y + 3 + int(roundf(float(r_idx + 1) * step_y))
		for c_idx: int in range(cols):
			var target_x: int = room.position.x + 3 + int(roundf(float(c_idx + 1) * step_x))
			var base_cell: Vector2i = Vector2i(target_x, target_y)

			# If landing on companion spawn at room center, shift slightly
			if base_cell.distance_squared_to(center) <= 6:
				base_cell.x += 2 if (c_idx % 2 == 0) else -2

			for offset: Vector2i in nudges:
				var candidate: Vector2i = base_cell + offset
				if _is_valid_candle_base(candidate, center):
					_candle_post_bases[candidate] = true
					_candle_post_tops[candidate + Vector2i(0, -1)] = true
					break


func _is_valid_candle_base(cell: Vector2i, center: Vector2i) -> bool:
	if cell.distance_squared_to(center) <= 6 or no_prop_cells.has(cell):
		return false
	var top_cell: Vector2i = cell + Vector2i(0, -1)
	if no_prop_cells.has(top_cell):
		return false
	if not is_floor(cell) or not is_floor(top_cell) or not is_floor(top_cell + Vector2i(0, -1)):
		return false
	return not _is_near_pillar(cell, 1) and not _is_near_pillar(top_cell, 1)


func _is_near_pillar(cell: Vector2i, margin: int) -> bool:
	for p: Rect2i in _all_pillars:
		if p.grow(margin).has_point(cell):
			return true
	return false


func has_candle_post_near(cell: Vector2i, radius_sq: int = 81) -> bool:
	return _has_cell_near(cell, _candle_post_tops, radius_sq)


static func _has_cell_near(cell: Vector2i, lookup: Dictionary, radius_sq: int) -> bool:
	var r: int = int(ceilf(sqrt(float(radius_sq))))
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			if dx * dx + dy * dy <= radius_sq:
				if lookup.has(cell + Vector2i(dx, dy)):
					return true
	return false


func _overlaps_any_room(candidate: Rect2i) -> bool:
	if hero_room.grow(ROOM_PADDING).intersects(candidate):
		return true
	if _room_grid.intersects_any(candidate, rooms, ROOM_PADDING):
		return true
	return _intersects_any_rect(candidate.grow(3), _corridor_rects)


func _is_outside_world_bounds(rect: Rect2i) -> bool:
	var limit: int = HALF_WORLD_SIZE - ROOM_PADDING - 100
	return absi(rect.position.x) > limit or absi(rect.position.y) > limit or absi(rect.end.x) > limit or absi(rect.end.y) > limit


func _add_horizontal_corridor_rect(x_start: int, x_end: int, y: int, half_width: int, sector_idx: int = 0) -> void:
	var min_x: int = mini(x_start, x_end)
	var max_x: int = maxi(x_start, x_end)
	var rect: Rect2i = Rect2i(min_x, y - half_width, (max_x - min_x) + 1, half_width * 2 + 1)
	_add_carve_rect(rect)
	_corridor_rects.append(rect)
	_corridor_sectors.append(sector_idx)
	_corridor_segments.append({&"is_horizontal": true, &"min": min_x, &"max": max_x, &"fixed": y, &"half_width": half_width})


func _add_vertical_corridor_rect(y_start: int, y_end: int, x: int, half_width: int, sector_idx: int = 0) -> void:
	var min_y: int = mini(y_start, y_end)
	var max_y: int = maxi(y_start, y_end)
	var rect: Rect2i = Rect2i(x - half_width, min_y, half_width * 2 + 1, (max_y - min_y) + 1)
	_add_carve_rect(rect)
	_corridor_rects.append(rect)
	_corridor_sectors.append(sector_idx)
	_corridor_segments.append({&"is_horizontal": false, &"min": min_y, &"max": max_y, &"fixed": x, &"half_width": half_width})


func _eliminate_narrow_gaps() -> void:
	var bridges_to_add: Array[Rect2i] = []
	for i: int in range(carve_rects.size()):
		var rect_a: Rect2i = carve_rects[i]
		var query_rect: Rect2i = rect_a.grow(3)
		var candidates: Array[int] = spatial_grid.get_candidate_ids_for_rect(query_rect)

		for j: int in candidates:
			if j <= i or j >= carve_rects.size():
				continue
			var rect_b: Rect2i = carve_rects[j]
			_try_add_horizontal_bridge(rect_a, rect_b, bridges_to_add)
			_try_add_horizontal_bridge(rect_b, rect_a, bridges_to_add)
			_try_add_vertical_bridge(rect_a, rect_b, bridges_to_add)
			_try_add_vertical_bridge(rect_b, rect_a, bridges_to_add)

	for bridge: Rect2i in bridges_to_add:
		if (
			not _intersects_any_rect(bridge, _all_pillars)
			and not _intersects_any_rect(bridge, _cut_corner_rects)
			and not _intersects_any_rect(bridge, protected_neck_rects)
		):
			_add_carve_rect(bridge)


static func _intersects_any_point(point: Vector2i, rects: Array[Rect2i]) -> bool:
	for other: Rect2i in rects:
		if other.has_point(point):
			return true
	return false


static func _intersects_any_rect(rect: Rect2i, rects: Array[Rect2i]) -> bool:
	for other: Rect2i in rects:
		if rect.intersects(other):
			return true
	return false


static func _try_add_horizontal_bridge(left_rect: Rect2i, right_rect: Rect2i, bridges: Array[Rect2i]) -> void:
	var gap: int = right_rect.position.x - left_rect.end.x
	if gap <= 0 or gap > 2:
		return
	var ov_y_start: int = maxi(left_rect.position.y, right_rect.position.y)
	var ov_y_end: int = mini(left_rect.end.y, right_rect.end.y)
	if ov_y_end > ov_y_start:
		bridges.append(Rect2i(left_rect.end.x, ov_y_start, gap, ov_y_end - ov_y_start))


static func _try_add_vertical_bridge(top_rect: Rect2i, bottom_rect: Rect2i, bridges: Array[Rect2i]) -> void:
	var gap: int = bottom_rect.position.y - top_rect.end.y
	if gap <= 0 or gap > 2:
		return
	var ov_x_start: int = maxi(top_rect.position.x, bottom_rect.position.x)
	var ov_x_end: int = mini(top_rect.end.x, bottom_rect.end.x)
	if ov_x_end > ov_x_start:
		bridges.append(Rect2i(ov_x_start, top_rect.end.y, ov_x_end - ov_x_start, gap))


func _compute_companion_spawns_for_room(room: Rect2i) -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	var center_cell: Vector2i = room.get_center()
	var tier: int = get_room_tier(room)

	positions.append(center_cell)
	if tier == 2 and _rng.randf() < 0.35:
		var offset: Vector2i = Vector2i(_rng.randi_range(-2, 2), _rng.randi_range(-2, 2))
		if offset != Vector2i.ZERO:
			positions.append(center_cell + offset)
	elif tier >= 3 and _rng.randf() < 0.65:
		var offset: Vector2i = Vector2i(_rng.randi_range(-3, 3), _rng.randi_range(-3, 3))
		if offset != Vector2i.ZERO:
			positions.append(center_cell + offset)

	return positions


func _commit_spike_cells(cells: Array[Vector2i]) -> void:
	var group_id: int = _next_spike_group % SPIKE_PHASE_GROUPS
	_next_spike_group += 1
	for cell: Vector2i in cells:
		_spike_cells[cell] = group_id
		spike_tile_sets[cell] = get_cell_tile_set(cell)


func _assign_wing_tile_sets() -> void:
	var hubs: Array[Rect2i] = [hero_room]
	var gate_parent_for_hub: Dictionary[Rect2i, Rect2i] = {}
	for gate: SectorGatePlanner.SectorGate in sector_gates:
		gate_parent_for_hub[gate.next_room] = gate.gate_room
		hubs.append(gate.next_room)

	for hub: Rect2i in hubs:
		var hub_sector: int = _room_sectors.get(hub, 0)
		if hub != hero_room:
			var prev_gate_room: Rect2i = gate_parent_for_hub.get(hub, Rect2i())
			var prev_ts: int = _room_tile_sets.get(prev_gate_room, -1)
			var hub_pool: Array[int] = _build_shuffled_tile_set_pool(prev_ts)
			_room_tile_sets[hub] = hub_pool[0]

		var hub_ts: int = _room_tile_sets.get(hub, 0)
		var wing_roots: Array[Rect2i] = []
		for child_var: Variant in get_child_rooms(hub):
			if child_var is Rect2i:
				var child: Rect2i = child_var
				if _room_sectors.get(child, -1) == hub_sector:
					wing_roots.append(child)

		var wing_pool: Array[int] = _build_shuffled_tile_set_pool(hub_ts)
		for i: int in range(wing_roots.size()):
			var wing_ts: int = hub_ts if hub_sector >= 4 else wing_pool[i % wing_pool.size()]
			_propagate_wing_tile_set(wing_roots[i], hub_sector, wing_ts)


func _build_shuffled_tile_set_pool(excluded: int) -> Array[int]:
	var pool: Array[int] = []
	for ts: int in range(TILE_SET_COUNT):
		if ts != excluded:
			pool.append(ts)
	for i: int in range(pool.size() - 1, 0, -1):
		var swap_idx: int = _rng.randi_range(0, i)
		var tmp: int = pool[i]
		pool[i] = pool[swap_idx]
		pool[swap_idx] = tmp
	return pool


func _propagate_wing_tile_set(root_room: Rect2i, sector_idx: int, tile_set: int) -> void:
	var stack: Array[Rect2i] = [root_room]
	while not stack.is_empty():
		var cur: Rect2i = stack.pop_back()
		_room_tile_sets[cur] = tile_set
		for child_var: Variant in get_child_rooms(cur):
			if child_var is Rect2i:
				var child: Rect2i = child_var
				if _room_sectors.get(child, -1) == sector_idx:
					stack.append(child)
