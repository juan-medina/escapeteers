# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name RoomLayout
extends RefCounted

enum Face {
	NORTH,
	SOUTH,
	EAST,
	WEST,
}

enum RoomProfile {
	COMPACT,
	STANDARD,
	WIDE_HALL,
	TALL_GALLERY,
	GRAND_CHAMBER,
}

const INWARD_ANCHOR: int = 2
const OUTWARD_STUB: int = 4
const SOCKET_EDGE_MARGIN: int = 3
const PROFILE_WEIGHT_TOTAL: int = 100
const PROFILE_THRESHOLD_COMPACT: int = 15
const PROFILE_THRESHOLD_STANDARD: int = 45
const PROFILE_THRESHOLD_WIDE: int = 67
const PROFILE_THRESHOLD_TALL: int = 89


static func get_archetype_title(archetype: WorldPlan.RoomArchetype) -> StringName:
	var title: StringName = &"Slime Pit"
	match archetype:
		WorldPlan.RoomArchetype.BONE_SWARM:
			title = &"Bone Swarm"
		WorldPlan.RoomArchetype.ARCHER_GARRISON:
			title = &"Archer Garrison"
		WorldPlan.RoomArchetype.NECRO_CRYPT:
			title = &"Necro Crypt"
	return title


static func roll_room_size(rng: RandomNumberGenerator, depth: int) -> Vector2i:
	var tier: int = 1 if depth <= 1 else (2 if depth <= 3 else 3)
	var bonus: int = mini(maxi(0, depth - 4) * 2, 8) if tier == 3 else 0
	var roll: int = rng.randi_range(1, PROFILE_WEIGHT_TOTAL)
	var profile: RoomProfile = RoomProfile.GRAND_CHAMBER
	if roll <= PROFILE_THRESHOLD_COMPACT:
		profile = RoomProfile.COMPACT
	elif roll <= PROFILE_THRESHOLD_STANDARD:
		profile = RoomProfile.STANDARD
	elif roll <= PROFILE_THRESHOLD_WIDE:
		profile = RoomProfile.WIDE_HALL
	elif roll <= PROFILE_THRESHOLD_TALL:
		profile = RoomProfile.TALL_GALLERY

	return _roll_size_for_profile(rng, profile, tier, bonus)


static func _roll_size_for_profile(rng: RandomNumberGenerator, profile: RoomProfile, tier: int, bonus: int) -> Vector2i:
	var min_s: Vector2i = Vector2i(18, 16)
	var max_s: Vector2i = Vector2i(22, 22)
	match profile:
		RoomProfile.COMPACT:
			if tier == 1:
				min_s = Vector2i(14, 14)
				max_s = Vector2i(18, 18)
			elif tier == 2:
				min_s = Vector2i(18, 18)
				max_s = Vector2i(22, 22)
			else:
				min_s = Vector2i(24, 24)
				max_s = Vector2i(30, 30)
		RoomProfile.STANDARD:
			if tier == 1:
				min_s = Vector2i(18, 16)
				max_s = Vector2i(22, 22)
			elif tier == 2:
				min_s = Vector2i(24, 22)
				max_s = Vector2i(32, 30)
			else:
				min_s = Vector2i(34 + bonus, 32 + bonus)
				max_s = Vector2i(44 + bonus, 42 + bonus)
		RoomProfile.WIDE_HALL:
			if tier == 1:
				min_s = Vector2i(24, 14)
				max_s = Vector2i(32, 16)
			elif tier == 2:
				min_s = Vector2i(34, 16)
				max_s = Vector2i(44, 20)
			else:
				min_s = Vector2i(46, 20)
				max_s = Vector2i(58, 26)
		RoomProfile.TALL_GALLERY:
			if tier == 1:
				min_s = Vector2i(14, 24)
				max_s = Vector2i(16, 32)
			elif tier == 2:
				min_s = Vector2i(16, 34)
				max_s = Vector2i(20, 44)
			else:
				min_s = Vector2i(20, 46)
				max_s = Vector2i(26, 58)
		RoomProfile.GRAND_CHAMBER:
			if tier == 1:
				min_s = Vector2i(22, 20)
				max_s = Vector2i(26, 24)
			elif tier == 2:
				min_s = Vector2i(32, 30)
				max_s = Vector2i(40, 38)
			else:
				min_s = Vector2i(42 + int(float(bonus) * 0.5), 40 + int(float(bonus) * 0.5))
				max_s = Vector2i(mini(54, 48 + bonus), mini(50, 44 + bonus))

	return Vector2i(rng.randi_range(min_s.x, max_s.x), rng.randi_range(min_s.y, max_s.y))


static func pick_room_shape(rng: RandomNumberGenerator, size: Vector2i) -> WorldPlan.RoomShape:
	var min_dim: int = mini(size.x, size.y)
	var max_cut_x: int = int(float(size.x) * 0.5) - 5
	var max_cut_y: int = int(float(size.y) * 0.5) - 5
	var can_asym_cut: bool = max_cut_x >= 4 and max_cut_y >= 4
	var roll: float = rng.randf()

	var is_elongated: bool = float(maxi(size.x, size.y)) >= float(min_dim) * 1.5
	if min_dim < 16:
		if is_elongated and roll >= 0.55:
			return WorldPlan.RoomShape.PILLARED
		return WorldPlan.RoomShape.RECTANGLE

	if min_dim < 18:
		return WorldPlan.RoomShape.RECTANGLE if roll < 0.55 else WorldPlan.RoomShape.PILLARED

	if min_dim < 22:
		if roll < 0.25:
			return WorldPlan.RoomShape.RECTANGLE
		if roll < 0.55:
			return WorldPlan.RoomShape.CUT_CORNERS
		if roll < 0.85 or not can_asym_cut:
			return WorldPlan.RoomShape.PILLARED
		return WorldPlan.RoomShape.L_SHAPE

	if roll < 0.25 and can_asym_cut:
		return WorldPlan.RoomShape.L_SHAPE
	if roll < 0.45 and can_asym_cut:
		return WorldPlan.RoomShape.T_SHAPE
	if roll < 0.65:
		return WorldPlan.RoomShape.PILLARED
	if roll < 0.80:
		return WorldPlan.RoomShape.CUT_CORNERS
	if roll < 0.90:
		return WorldPlan.RoomShape.CROSS
	return WorldPlan.RoomShape.RECTANGLE


static func pick_floor_pattern(rng: RandomNumberGenerator, shape: WorldPlan.RoomShape) -> WorldPlan.FloorPattern:
	match shape:
		WorldPlan.RoomShape.PILLARED:
			return WorldPlan.FloorPattern.PILLAR_PLINTHS if rng.randf() < 0.65 else WorldPlan.FloorPattern.CROSSROADS
		WorldPlan.RoomShape.CROSS:
			return WorldPlan.FloorPattern.CROSSROADS if rng.randf() < 0.70 else WorldPlan.FloorPattern.BORDER_TRIM
		WorldPlan.RoomShape.CUT_CORNERS:
			return WorldPlan.FloorPattern.ARENA_RINGS if rng.randf() < 0.60 else WorldPlan.FloorPattern.BORDER_TRIM
		WorldPlan.RoomShape.L_SHAPE, WorldPlan.RoomShape.T_SHAPE:
			return WorldPlan.FloorPattern.BORDER_TRIM if rng.randf() < 0.65 else WorldPlan.FloorPattern.CROSSROADS
		_:
			var r_pat: int = rng.randi_range(0, 3)
			return r_pat as WorldPlan.FloorPattern


static func build_room_cutouts(rng: RandomNumberGenerator, room: Rect2i, shape: WorldPlan.RoomShape) -> Array[Rect2i]:
	var cutouts: Array[Rect2i] = []
	var max_cut_x: int = int(float(room.size.x) * 0.5) - 5
	var max_cut_y: int = int(float(room.size.y) * 0.5) - 5
	if max_cut_x < 3 or max_cut_y < 3:
		return cutouts

	if shape == WorldPlan.RoomShape.L_SHAPE and max_cut_x >= 4 and max_cut_y >= 4:
		var lx: int = clampi(int(float(room.size.x) * rng.randf_range(0.32, 0.40)), 4, max_cut_x)
		var ly: int = clampi(int(float(room.size.y) * rng.randf_range(0.32, 0.40)), 4, max_cut_y)
		var corner: int = rng.randi_range(0, 3)
		cutouts.append(_make_corner_rect(room, corner, lx, ly))
		return cutouts

	if shape == WorldPlan.RoomShape.T_SHAPE and max_cut_x >= 4 and max_cut_y >= 4:
		var orient: int = rng.randi_range(0, 3)
		var stem_is_vert: bool = orient < 2
		var fx: float = rng.randf_range(0.25, 0.32) if stem_is_vert else rng.randf_range(0.32, 0.40)
		var fy: float = rng.randf_range(0.32, 0.40) if stem_is_vert else rng.randf_range(0.25, 0.32)
		var tx: int = clampi(int(float(room.size.x) * fx), 4, max_cut_x)
		var ty: int = clampi(int(float(room.size.y) * fy), 4, max_cut_y)
		var pair_a: int = 2 if orient == 0 else (0 if orient == 1 else (0 if orient == 2 else 1))
		var pair_b: int = 3 if orient == 0 else (1 if orient == 1 else (2 if orient == 2 else 3))
		cutouts.append(_make_corner_rect(room, pair_a, tx, ty))
		cutouts.append(_make_corner_rect(room, pair_b, tx, ty))
		return cutouts

	var cut_x: int = 0
	var cut_y: int = 0
	if shape == WorldPlan.RoomShape.CUT_CORNERS:
		cut_x = mini(clampi(int(float(mini(room.size.x, room.size.y)) * 0.18), 3, 6), max_cut_x)
		cut_y = mini(cut_x, max_cut_y)
	elif shape == WorldPlan.RoomShape.CROSS:
		cut_x = clampi(int(float(room.size.x) * 0.25), 3, max_cut_x)
		cut_y = clampi(int(float(room.size.y) * 0.25), 3, max_cut_y)
	elif shape == WorldPlan.RoomShape.PILLARED and room.size.x >= 26 and room.size.y >= 26 and rng.randf() < 0.5:
		cut_x = mini(3, max_cut_x)
		cut_y = mini(3, max_cut_y)

	if cut_x > 0 and cut_y > 0:
		for corner_idx: int in range(4):
			cutouts.append(_make_corner_rect(room, corner_idx, cut_x, cut_y))
	return cutouts


static func _make_corner_rect(room: Rect2i, corner: int, cut_x: int, cut_y: int) -> Rect2i:
	var x: int = room.position.x if (corner == 0 or corner == 2) else (room.end.x - cut_x)
	var y: int = room.position.y if (corner == 0 or corner == 1) else (room.end.y - cut_y)
	return Rect2i(x, y, cut_x, cut_y)


static func carve_room_layout(plan: WorldPlan, room: Rect2i, shape: WorldPlan.RoomShape, cutouts: Array[Rect2i]) -> void:
	var floor_rects: Array[Rect2i] = [room]
	for cut: Rect2i in cutouts:
		plan._cut_corner_rects.append(cut)
		floor_rects = subtract_rect_from_list(floor_rects, cut)

	if shape == WorldPlan.RoomShape.PILLARED:
		var pillars: Array[Rect2i] = _build_pillars_for_room(room)
		plan._room_pillars[room] = pillars
		plan._all_pillars.append_array(pillars)
		for p: Rect2i in pillars:
			floor_rects = subtract_rect_from_list(floor_rects, p)

	var r_sector: int = plan._room_sectors.get(room, 0)
	for r: Rect2i in floor_rects:
		plan._add_carve_rect(r, r_sector)


static func _build_pillars_for_room(room: Rect2i) -> Array[Rect2i]:
	var center: Vector2i = room.get_center()
	var is_wide_hall: bool = float(room.size.x) >= float(room.size.y) * 1.5 and room.size.y < 22
	var is_tall_gallery: bool = float(room.size.y) >= float(room.size.x) * 1.5 and room.size.x < 22

	if is_wide_hall:
		var col_ox: int = maxi(5, int(float(room.size.x) * 0.26))
		var col_size: Vector2i = Vector2i(2, 2)
		return [
			Rect2i(Vector2i(center.x - col_ox - 1, center.y - 1), col_size),
			Rect2i(Vector2i(center.x + col_ox, center.y - 1), col_size),
		]

	if is_tall_gallery:
		var col_oy: int = maxi(5, int(float(room.size.y) * 0.26))
		var tall_size: Vector2i = Vector2i(2, 2)
		return [
			Rect2i(Vector2i(center.x - 1, center.y - col_oy - 1), tall_size),
			Rect2i(Vector2i(center.x - 1, center.y + col_oy), tall_size),
		]

	var ps: int = 3 if mini(room.size.x, room.size.y) >= 26 else 2
	var ox: int = maxi(4, int(float(room.size.x) * 0.22))
	var oy: int = maxi(4, int(float(room.size.y) * 0.22))
	var p_size: Vector2i = Vector2i(ps, ps)
	return [
		Rect2i(Vector2i(center.x - ox - ps + 1, center.y - oy - ps + 1), p_size),
		Rect2i(Vector2i(center.x + ox, center.y - oy - ps + 1), p_size),
		Rect2i(Vector2i(center.x - ox - ps + 1, center.y + oy), p_size),
		Rect2i(Vector2i(center.x + ox, center.y + oy), p_size),
	]


static func subtract_rect_from_list(rects: Array[Rect2i], hole: Rect2i) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	for r: Rect2i in rects:
		if not r.intersects(hole):
			result.append(r)
			continue
		var inter: Rect2i = r.intersection(hole)
		if inter.position.y > r.position.y:
			result.append(Rect2i(r.position.x, r.position.y, r.size.x, inter.position.y - r.position.y))
		if inter.end.y < r.end.y:
			result.append(Rect2i(r.position.x, inter.end.y, r.size.x, r.end.y - inter.end.y))
		if inter.position.x > r.position.x:
			result.append(Rect2i(r.position.x, inter.position.y, inter.position.x - r.position.x, inter.size.y))
		if inter.end.x < r.end.x:
			result.append(Rect2i(inter.end.x, inter.position.y, r.end.x - inter.end.x, inter.size.y))
	return result


static func plan_corridor(
	plan: WorldPlan,
	room_a: Rect2i,
	room_b: Rect2i,
	cutouts_b: Array[Rect2i],
	sector_idx: int,
	room_b_exists: bool = false,
) -> Array[Dictionary]:
	var half_width: int = int(float(WorldPlan.CORRIDOR_WIDTH) * 0.5)
	var face_pairs: Array[Vector2i] = _get_candidate_face_pairs(room_a, room_b)

	for pair: Vector2i in face_pairs:
		var face_a: Face = pair.x as Face
		var face_b: Face = pair.y as Face
		var sockets_a: Array[int] = _collect_face_sockets(plan, room_a, [], face_a, half_width, true)
		var sockets_b: Array[int] = _collect_face_sockets(plan, room_b, cutouts_b, face_b, half_width, room_b_exists)
		if sockets_a.is_empty() or sockets_b.is_empty():
			continue

		for attempt: int in range(4):
			var sock_a: int = sockets_a[int(float(sockets_a.size()) * 0.5)]
			var sock_b: int = sockets_b[int(float(sockets_b.size()) * 0.5)]
			if attempt < 3:
				sock_a = sockets_a[plan._rng.randi_range(0, sockets_a.size() - 1)]
				sock_b = sockets_b[plan._rng.randi_range(0, sockets_b.size() - 1)]

			var segs: Array[Dictionary] = _build_corridor_segments(
				plan._rng,
				room_a,
				face_a,
				sock_a,
				room_b,
				face_b,
				sock_b,
				half_width,
			)
			if not segs.is_empty() and _is_corridor_valid(plan, segs, room_a, room_b, cutouts_b, sector_idx):
				return segs

	return []


static func get_usable_corridor_run(plan: WorldPlan, seg: Dictionary) -> Vector2i:
	var is_horiz: bool = seg[&"is_horizontal"]
	var min_c: int = seg[&"min"]
	var max_c: int = seg[&"max"]
	var fixed_c: int = seg[&"fixed"]

	var run_start: int = -999999
	var best_start: int = 0
	var best_len: int = 0

	for c: int in range(min_c, max_c + 1):
		var center_cell: Vector2i = Vector2i(c, fixed_c) if is_horiz else Vector2i(fixed_c, c)
		if plan.get_room_at(center_cell) == Rect2i():
			if run_start == -999999:
				run_start = c
			var cur_len: int = c - run_start + 1
			if cur_len > best_len:
				best_len = cur_len
				best_start = run_start
		else:
			run_start = -999999

	return Vector2i(best_start, best_len)


static func commit_corridor(plan: WorldPlan, segments: Array[Dictionary], sector_idx: int) -> void:
	for seg: Dictionary in segments:
		var rect: Rect2i = seg[&"rect"]
		plan._add_carve_rect(rect, sector_idx)
		plan._corridor_rects.append(rect)
		plan._corridor_sectors.append(sector_idx)
		(
			plan
			. _corridor_segments
			. append(
				{
					&"is_horizontal": seg[&"is_horizontal"],
					&"min": seg[&"min"],
					&"max": seg[&"max"],
					&"fixed": seg[&"fixed"],
					&"half_width": seg[&"half_width"],
				}
			)
		)


static func _get_candidate_face_pairs(room_a: Rect2i, room_b: Rect2i) -> Array[Vector2i]:
	var delta: Vector2i = room_b.get_center() - room_a.get_center()
	var pairs: Array[Vector2i] = []
	var horiz_pair: Vector2i = Vector2i(Face.EAST, Face.WEST) if delta.x >= 0 else Vector2i(Face.WEST, Face.EAST)
	var vert_pair: Vector2i = Vector2i(Face.SOUTH, Face.NORTH) if delta.y >= 0 else Vector2i(Face.NORTH, Face.SOUTH)

	if absi(delta.x) >= absi(delta.y):
		pairs.append(horiz_pair)
		pairs.append(vert_pair)
	else:
		pairs.append(vert_pair)
		pairs.append(horiz_pair)

	if absi(delta.x) >= 6 and absi(delta.y) >= 6:
		var exit_h: Face = Face.EAST if delta.x >= 0 else Face.WEST
		var enter_v: Face = Face.NORTH if delta.y >= 0 else Face.SOUTH
		var exit_v: Face = Face.SOUTH if delta.y >= 0 else Face.NORTH
		var enter_h: Face = Face.WEST if delta.x >= 0 else Face.EAST
		pairs.append(Vector2i(exit_h, enter_v))
		pairs.append(Vector2i(exit_v, enter_h))

	return pairs


static func _collect_face_sockets(
	plan: WorldPlan,
	room: Rect2i,
	cutouts: Array[Rect2i],
	face: Face,
	half_width: int,
	is_existing: bool,
) -> Array[int]:
	var sockets: Array[int] = []
	var is_horiz_face: bool = face == Face.NORTH or face == Face.SOUTH
	var start_c: int = (room.position.x if is_horiz_face else room.position.y) + SOCKET_EDGE_MARGIN + half_width
	var end_c: int = (room.end.x if is_horiz_face else room.end.y) - 1 - SOCKET_EDGE_MARGIN - half_width
	if start_c > end_c:
		return sockets

	var edge_coord: int = room.position.y
	var inward_step: int = 1
	match face:
		Face.SOUTH:
			edge_coord = room.end.y - 1
			inward_step = -1
		Face.WEST:
			edge_coord = room.position.x
			inward_step = 1
		Face.EAST:
			edge_coord = room.end.x - 1
			inward_step = -1

	for c: int in range(start_c, end_c + 1):
		if _is_socket_clear(plan, room, cutouts, is_horiz_face, c, edge_coord, inward_step, half_width, is_existing):
			sockets.append(c)
	return sockets


static func _is_socket_clear(
	plan: WorldPlan,
	room: Rect2i,
	cutouts: Array[Rect2i],
	is_horiz_face: bool,
	coord: int,
	edge_coord: int,
	inward_step: int,
	half_width: int,
	is_existing: bool,
) -> bool:
	for dc: int in range(-half_width, half_width + 1):
		for depth_i: int in range(3):
			var fixed_c: int = edge_coord + depth_i * inward_step
			var cell: Vector2i = Vector2i(coord + dc, fixed_c) if is_horiz_face else Vector2i(fixed_c, coord + dc)
			if not room.has_point(cell) or _point_in_rects(cell, cutouts):
				return false
			if is_existing and not plan.is_floor(cell):
				return false
	return true


static func _point_in_rects(point: Vector2i, rects: Array[Rect2i]) -> bool:
	for r: Rect2i in rects:
		if r.has_point(point):
			return true
	return false


static func _build_corridor_segments(
	rng: RandomNumberGenerator,
	room_a: Rect2i,
	face_a: Face,
	sock_a: int,
	room_b: Rect2i,
	face_b: Face,
	sock_b: int,
	half_width: int,
) -> Array[Dictionary]:
	var anchor_a: Vector2i = _face_point(room_a, face_a, sock_a, -INWARD_ANCHOR)
	var stub_a: Vector2i = _face_point(room_a, face_a, sock_a, OUTWARD_STUB)
	var anchor_b: Vector2i = _face_point(room_b, face_b, sock_b, -INWARD_ANCHOR)
	var stub_b: Vector2i = _face_point(room_b, face_b, sock_b, OUTWARD_STUB)

	if _is_horizontal_face(face_a) and _is_horizontal_face(face_b):
		if not _stubs_face_along_y(face_a, face_b, stub_a.y, stub_b.y):
			return []
		var mid_y: int = roundi(lerpf(float(stub_a.y), float(stub_b.y), rng.randf_range(0.30, 0.70)))
		return [
			_make_vert_seg(anchor_a.y, mid_y, anchor_a.x, half_width),
			_make_horiz_seg(anchor_a.x, anchor_b.x, mid_y, half_width),
			_make_vert_seg(mid_y, anchor_b.y, anchor_b.x, half_width),
		]

	if not _is_horizontal_face(face_a) and not _is_horizontal_face(face_b):
		if not _stubs_face_along_x(face_a, face_b, stub_a.x, stub_b.x):
			return []
		var mid_x: int = roundi(lerpf(float(stub_a.x), float(stub_b.x), rng.randf_range(0.30, 0.70)))
		return [
			_make_horiz_seg(anchor_a.x, mid_x, anchor_a.y, half_width),
			_make_vert_seg(anchor_a.y, anchor_b.y, mid_x, half_width),
			_make_horiz_seg(mid_x, anchor_b.x, anchor_b.y, half_width),
		]

	if not _is_horizontal_face(face_a) and _is_horizontal_face(face_b):
		var corner_x: int = anchor_b.x
		var corner_y: int = anchor_a.y
		if not _check_perp_forward(face_a, stub_a.x, corner_x) or not _check_perp_forward(face_b, stub_b.y, corner_y):
			return []
		return [
			_make_horiz_seg(anchor_a.x, corner_x, corner_y, half_width),
			_make_vert_seg(corner_y, anchor_b.y, corner_x, half_width),
		]

	var corner_x2: int = anchor_a.x
	var corner_y2: int = anchor_b.y
	if not _check_perp_forward(face_a, stub_a.y, corner_y2) or not _check_perp_forward(face_b, stub_b.x, corner_x2):
		return []
	return [
		_make_vert_seg(anchor_a.y, corner_y2, corner_x2, half_width),
		_make_horiz_seg(corner_x2, anchor_b.x, corner_y2, half_width),
	]


static func _is_horizontal_face(face: Face) -> bool:
	return face == Face.NORTH or face == Face.SOUTH


static func _stubs_face_along_x(face_a: Face, face_b: Face, ax: int, bx: int) -> bool:
	if face_a == Face.EAST and face_b == Face.WEST:
		return ax <= bx
	if face_a == Face.WEST and face_b == Face.EAST:
		return ax >= bx
	return false


static func _stubs_face_along_y(face_a: Face, face_b: Face, ay: int, by: int) -> bool:
	if face_a == Face.SOUTH and face_b == Face.NORTH:
		return ay <= by
	if face_a == Face.NORTH and face_b == Face.SOUTH:
		return ay >= by
	return false


static func _check_perp_forward(face: Face, stub_coord: int, corner_coord: int) -> bool:
	match face:
		Face.EAST:
			return corner_coord >= stub_coord
		Face.WEST:
			return corner_coord <= stub_coord
		Face.SOUTH:
			return corner_coord >= stub_coord
		_:
			return corner_coord <= stub_coord


static func _face_point(room: Rect2i, face: Face, sock: int, outward_offset: int) -> Vector2i:
	match face:
		Face.NORTH:
			return Vector2i(sock, room.position.y - outward_offset)
		Face.SOUTH:
			return Vector2i(sock, room.end.y - 1 + outward_offset)
		Face.WEST:
			return Vector2i(room.position.x - outward_offset, sock)
		_:
			return Vector2i(room.end.x - 1 + outward_offset, sock)


static func _make_horiz_seg(x_start: int, x_end: int, y: int, half_width: int) -> Dictionary:
	var min_x: int = mini(x_start, x_end)
	var max_x: int = maxi(x_start, x_end)
	var rect: Rect2i = Rect2i(min_x, y - half_width, (max_x - min_x) + 1, half_width * 2 + 1)
	return {&"is_horizontal": true, &"min": min_x, &"max": max_x, &"fixed": y, &"half_width": half_width, &"rect": rect}


static func _make_vert_seg(y_start: int, y_end: int, x: int, half_width: int) -> Dictionary:
	var min_y: int = mini(y_start, y_end)
	var max_y: int = maxi(y_start, y_end)
	var rect: Rect2i = Rect2i(x - half_width, min_y, half_width * 2 + 1, (max_y - min_y) + 1)
	return {&"is_horizontal": false, &"min": min_y, &"max": max_y, &"fixed": x, &"half_width": half_width, &"rect": rect}


static func _is_corridor_valid(
	plan: WorldPlan,
	segs: Array[Dictionary],
	room_a: Rect2i,
	room_b: Rect2i,
	cutouts_b: Array[Rect2i],
	sector_idx: int,
) -> bool:
	var last_idx: int = segs.size() - 1
	for i: int in range(segs.size()):
		var rect: Rect2i = segs[i][&"rect"]
		if plan._is_outside_world_bounds(rect):
			return false
		if WorldPlan._intersects_any_rect(rect, cutouts_b) or WorldPlan._intersects_any_rect(rect, plan._cut_corner_rects):
			return false
		if WorldPlan._intersects_any_rect(rect.grow(1), plan.protected_neck_rects):
			return false
		if WorldPlan._intersects_any_rect(rect.grow(1), plan._reserved_pockets):
			return false
		if i > 0 and rect.intersects(room_a):
			return false
		if i < last_idx and rect.intersects(room_b):
			return false
		if _hits_other_room_or_sector_corridor(plan, rect, room_a, room_b, sector_idx):
			return false
	return true


static func _hits_other_room_or_sector_corridor(
	plan: WorldPlan,
	rect: Rect2i,
	room_a: Rect2i,
	room_b: Rect2i,
	sector_idx: int,
) -> bool:
	var padded: Rect2i = rect.grow(3)
	if plan.hero_room != room_a and plan.hero_room != room_b and plan.hero_room.intersects(padded):
		return true
	for r_id: int in plan._room_grid.get_candidate_ids_for_rect(padded):
		if r_id >= 0 and r_id < plan.rooms.size():
			var other: Rect2i = plan.rooms[r_id]
			if other != room_a and other != room_b and other.intersects(padded):
				return true
	var corr_padded: Rect2i = rect.grow(3)
	for c_idx: int in range(plan._corridor_rects.size()):
		if plan._corridor_sectors[c_idx] != sector_idx and plan._corridor_rects[c_idx].intersects(corr_padded):
			return true
	return false


static func eliminate_narrow_gaps(plan: WorldPlan) -> void:
	var bridges_to_add: Array[Rect2i] = []
	var bridge_sectors: Array[int] = []
	for i: int in range(plan.carve_rects.size()):
		var rect_a: Rect2i = plan.carve_rects[i]
		var sec_a: int = plan._carve_rect_sectors[i]
		var query_rect: Rect2i = rect_a.grow(3)
		var candidates: Array[int] = plan.spatial_grid.get_candidate_ids_for_rect(query_rect)

		for j: int in candidates:
			if j <= i or j >= plan.carve_rects.size():
				continue
			if plan._carve_rect_sectors[j] != sec_a:
				continue
			var rect_b: Rect2i = plan.carve_rects[j]
			_try_add_horizontal_bridge(rect_a, rect_b, bridges_to_add)
			_try_add_horizontal_bridge(rect_b, rect_a, bridges_to_add)
			_try_add_vertical_bridge(rect_a, rect_b, bridges_to_add)
			_try_add_vertical_bridge(rect_b, rect_a, bridges_to_add)
			while bridge_sectors.size() < bridges_to_add.size():
				bridge_sectors.append(sec_a)

	for b_idx: int in range(bridges_to_add.size()):
		var bridge: Rect2i = bridges_to_add[b_idx]
		if (
			not WorldPlan._intersects_any_rect(bridge, plan._all_pillars)
			and not WorldPlan._intersects_any_rect(bridge, plan._cut_corner_rects)
			and not WorldPlan._intersects_any_rect(bridge, plan.protected_neck_rects)
		):
			plan._add_carve_rect(bridge, bridge_sectors[b_idx])


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
