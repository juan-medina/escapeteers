# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name AutoplayMapAudit
extends RefCounted

const COLOR_NAMES: Array[String] = ["BLUE", "GREEN", "YELLOW", "RED"]
const CARDINAL_DIRS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(0, 1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
]
const MAX_SAMPLES: int = 8

var _results: Array[Dictionary] = []


func reset_session() -> void:
	_results.clear()


func audit_seed(seed_val: int, max_depth: int) -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	seed(seed_val)
	var plan: WorldPlan = WorldPlan.new()
	plan.generate(seed_val, max_depth)

	var all_chunks: Array[Vector2i] = ChunkRaster.collect_chunk_coords(plan, MapStreamer.CHUNK_SIZE)
	var raster: ChunkRaster = ChunkRaster.new()
	for coord: Vector2i in all_chunks:
		TileClassifier.bake_chunk(coord, raster, plan)
	SectorGatePlanner.prebake_shortcut_tunnels(plan, raster)

	var solvability_ok: bool = SectorGatePlanner.verify_solvability(plan)

	var shortcut_direct_overlaps: Array[Dictionary] = []
	var shortcut_margin_overlaps: Array[Dictionary] = []
	var shortcut_diff_collisions: Array[Dictionary] = []
	_check_shortcut_overlaps(
		plan,
		shortcut_direct_overlaps,
		shortcut_margin_overlaps,
		shortcut_diff_collisions,
	)

	var floors: Dictionary[Vector2i, bool] = {}
	var walls: Dictionary[Vector2i, bool] = {}
	var walkable: Dictionary[Vector2i, bool] = {}
	_build_grid_from_baked_chunks(plan, floors, walls, walkable)

	var unlocked_door_cells: Dictionary[Vector2i, bool] = {}
	var collected_keys: Dictionary[WorldPlan.KeyColor, bool] = {}
	var opened_shortcuts: Dictionary[int, bool] = {}
	var unlocked_doors: Dictionary[int, bool] = {}
	var visited: Dictionary[Vector2i, bool] = {}
	var hero_spawn_blocked: bool = _simulate_progression(
		plan,
		floors,
		walls,
		walkable,
		unlocked_door_cells,
		collected_keys,
		opened_shortcuts,
		unlocked_doors,
		visited,
	)

	var unreachable_rooms: int = _count_unreachable_rooms(plan, visited)
	var uncollected_keys: Array[String] = []
	var locked_doors: Array[String] = []
	var unopened_shortcuts: Array[String] = []
	_collect_gate_progression_failures(
		plan,
		collected_keys,
		unlocked_doors,
		opened_shortcuts,
		uncollected_keys,
		locked_doors,
		unopened_shortcuts,
	)

	var broken_shortcuts: Array[String] = _find_broken_shortcuts(
		plan,
		opened_shortcuts,
		walkable,
		walls,
		unlocked_door_cells,
	)

	var wall_on_walkable_samples: Array[String] = []
	var wall_on_walkable_count: int = _count_wall_on_walkable(
		walkable,
		walls,
		unlocked_door_cells,
		wall_on_walkable_samples,
	)

	var wall_hole_samples: Array[String] = []
	var wall_hole_count: int = _count_wall_holes(walkable, walls, wall_hole_samples)

	var elapsed_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	var shortcuts_count: int = 0
	for gate: SectorGatePlanner.SectorGate in plan.sector_gates:
		if gate.has_shortcut:
			shortcuts_count += 1

	var passed: bool = (
		solvability_ok
		and not hero_spawn_blocked
		and unreachable_rooms == 0
		and uncollected_keys.is_empty()
		and locked_doors.is_empty()
		and unopened_shortcuts.is_empty()
		and shortcut_direct_overlaps.is_empty()
		and shortcut_margin_overlaps.is_empty()
		and shortcut_diff_collisions.is_empty()
		and broken_shortcuts.is_empty()
		and wall_on_walkable_count == 0
		and wall_hole_count == 0
	)

	var result: Dictionary = {
		&"seed": seed_val,
		&"max_depth": max_depth,
		&"passed": passed,
		&"elapsed_ms": elapsed_ms,
		&"room_count": plan.rooms.size() + 1,
		&"gate_count": plan.sector_gates.size(),
		&"shortcut_count": shortcuts_count,
		&"solvability_ok": solvability_ok,
		&"hero_spawn_blocked": hero_spawn_blocked,
		&"unreachable_rooms": unreachable_rooms,
		&"uncollected_keys": uncollected_keys,
		&"locked_doors": locked_doors,
		&"unopened_shortcuts": unopened_shortcuts,
		&"shortcut_direct_overlaps": shortcut_direct_overlaps,
		&"shortcut_margin_overlaps": shortcut_margin_overlaps,
		&"shortcut_diff_collisions": shortcut_diff_collisions,
		&"broken_shortcuts": broken_shortcuts,
		&"wall_on_walkable_count": wall_on_walkable_count,
		&"wall_on_walkable_samples": wall_on_walkable_samples,
		&"wall_hole_count": wall_hole_count,
		&"wall_hole_samples": wall_hole_samples,
	}
	_results.append(result)
	return result


func print_seed_failure(res: Dictionary) -> void:
	var tags: Array[String] = []
	if not res[&"solvability_ok"]:
		tags.append("solvability_failed")
	if res[&"hero_spawn_blocked"]:
		tags.append("hero_spawn_blocked")
	var unreach: int = res[&"unreachable_rooms"]
	if unreach > 0:
		tags.append("unreachable_rooms=%d" % unreach)
	var uncoll: Array[String] = res[&"uncollected_keys"]
	if not uncoll.is_empty():
		tags.append("uncollected_keys=[%s]" % ", ".join(uncoll))
	var ldoors: Array[String] = res[&"locked_doors"]
	if not ldoors.is_empty():
		tags.append("locked_doors=[%s]" % ", ".join(ldoors))
	var unopen: Array[String] = res[&"unopened_shortcuts"]
	if not unopen.is_empty():
		tags.append("unopened_shortcuts=[%s]" % ", ".join(unopen))

	var direct_ov: Array[Dictionary] = res[&"shortcut_direct_overlaps"]
	if not direct_ov.is_empty():
		tags.append("direct_overlaps=%s" % _format_pair_list(direct_ov))
	var margin_ov: Array[Dictionary] = res[&"shortcut_margin_overlaps"]
	if not margin_ov.is_empty():
		tags.append("margin_overlaps=%s" % _format_pair_list(margin_ov))
	var diff_col: Array[Dictionary] = res[&"shortcut_diff_collisions"]
	if not diff_col.is_empty():
		tags.append("diff_collisions=%s" % _format_diff_list(diff_col))

	var broken: Array[String] = res[&"broken_shortcuts"]
	if not broken.is_empty():
		tags.append("broken_shortcuts=[%s]" % ", ".join(broken))
	var wow_count: int = res[&"wall_on_walkable_count"]
	if wow_count > 0:
		tags.append("wall_on_walkable=%d" % wow_count)
	var hole_count: int = res[&"wall_hole_count"]
	if hole_count > 0:
		tags.append("wall_holes=%d" % hole_count)

	print(&"[Audit FAIL] seed=%d -> %s" % [res[&"seed"], " | ".join(tags)])


func print_report() -> void:
	var summary: Dictionary = build_report_dict()
	print("")
	print(&"================ AUTOPLAY MAP AUDIT REPORT ================")
	print(
		(
			&"Seeds Audited: %d  Passed: %d  Failed: %d  Elapsed: %.1fms (avg %.2fms/seed)"
			% [
				summary[&"total_seeds"],
				summary[&"passed_seeds"],
				summary[&"failed_seeds"],
				summary[&"total_elapsed_ms"],
				summary[&"avg_elapsed_ms"],
			]
		)
	)
	print(
		(
			&"Gates: %d  Shortcuts Created: %d (%.1f%%)"
			% [
				summary[&"total_gates"],
				summary[&"total_shortcuts"],
				summary[&"shortcut_pct"],
			]
		)
	)
	var counts: Dictionary = summary[&"failure_counts"]
	print(&"Failure Breakdown:")
	print(&"  shortcut_direct_overlaps : %d" % counts[&"shortcut_direct_overlaps"])
	print(&"  shortcut_margin_overlaps : %d" % counts[&"shortcut_margin_overlaps"])
	print(&"  shortcut_diff_collisions : %d" % counts[&"shortcut_diff_collisions"])
	print(&"  wall_on_walkable         : %d" % counts[&"wall_on_walkable"])
	print(&"  wall_holes               : %d" % counts[&"wall_holes"])
	print(&"  broken_shortcuts         : %d" % counts[&"broken_shortcuts"])
	print(&"  unreachable_rooms        : %d" % counts[&"unreachable_rooms"])
	print(&"  locked_doors             : %d" % counts[&"locked_doors"])
	print(&"  uncollected_keys         : %d" % counts[&"uncollected_keys"])
	print(&"  unopened_shortcuts       : %d" % counts[&"unopened_shortcuts"])
	print(&"  solvability_failed       : %d" % counts[&"solvability_failed"])
	print(&"  hero_spawn_blocked       : %d" % counts[&"hero_spawn_blocked"])

	var failing_examples: Array[Dictionary] = summary[&"failing_examples"]
	if not failing_examples.is_empty():
		print(&"Example Failing Seeds (up to 10):")
		for ex: Dictionary in failing_examples:
			print_seed_failure(ex)
	print(&"===========================================================")
	print("")


func build_report_dict() -> Dictionary:
	var total: int = _results.size()
	var passed_count: int = 0
	var total_ms: float = 0.0
	var total_gates: int = 0
	var total_shortcuts: int = 0
	var counts: Dictionary = {
		&"shortcut_direct_overlaps": 0,
		&"shortcut_margin_overlaps": 0,
		&"shortcut_diff_collisions": 0,
		&"wall_on_walkable": 0,
		&"wall_holes": 0,
		&"broken_shortcuts": 0,
		&"unreachable_rooms": 0,
		&"locked_doors": 0,
		&"uncollected_keys": 0,
		&"unopened_shortcuts": 0,
		&"solvability_failed": 0,
		&"hero_spawn_blocked": 0,
	}
	var failing_examples: Array[Dictionary] = []

	for res: Dictionary in _results:
		total_ms += float(res[&"elapsed_ms"])
		total_gates += int(res[&"gate_count"])
		total_shortcuts += int(res[&"shortcut_count"])
		if res[&"passed"]:
			passed_count += 1
			continue
		if failing_examples.size() < 10:
			failing_examples.append(res)
		if not res[&"shortcut_direct_overlaps"].is_empty():
			counts[&"shortcut_direct_overlaps"] += 1
		if not res[&"shortcut_margin_overlaps"].is_empty():
			counts[&"shortcut_margin_overlaps"] += 1
		if not res[&"shortcut_diff_collisions"].is_empty():
			counts[&"shortcut_diff_collisions"] += 1
		if int(res[&"wall_on_walkable_count"]) > 0:
			counts[&"wall_on_walkable"] += 1
		if int(res[&"wall_hole_count"]) > 0:
			counts[&"wall_holes"] += 1
		if not res[&"broken_shortcuts"].is_empty():
			counts[&"broken_shortcuts"] += 1
		if int(res[&"unreachable_rooms"]) > 0:
			counts[&"unreachable_rooms"] += 1
		if not res[&"locked_doors"].is_empty():
			counts[&"locked_doors"] += 1
		if not res[&"uncollected_keys"].is_empty():
			counts[&"uncollected_keys"] += 1
		if not res[&"unopened_shortcuts"].is_empty():
			counts[&"unopened_shortcuts"] += 1
		if not res[&"solvability_ok"]:
			counts[&"solvability_failed"] += 1
		if res[&"hero_spawn_blocked"]:
			counts[&"hero_spawn_blocked"] += 1

	var shortcut_pct: float = float(total_shortcuts) / float(maxi(1, total_gates)) * 100.0
	return {
		&"total_seeds": total,
		&"passed_seeds": passed_count,
		&"failed_seeds": total - passed_count,
		&"total_elapsed_ms": total_ms,
		&"avg_elapsed_ms": total_ms / float(maxi(1, total)),
		&"total_gates": total_gates,
		&"total_shortcuts": total_shortcuts,
		&"shortcut_pct": shortcut_pct,
		&"failure_counts": counts,
		&"failing_examples": failing_examples,
		&"results": _results,
	}


static func _color_name(color: WorldPlan.KeyColor) -> String:
	var idx: int = int(color)
	if idx >= 0 and idx < COLOR_NAMES.size():
		return COLOR_NAMES[idx]
	return "COLOR_%d" % idx


static func _check_shortcut_overlaps(
	plan: WorldPlan,
	direct_overlaps: Array[Dictionary],
	margin_overlaps: Array[Dictionary],
	diff_collisions: Array[Dictionary],
) -> void:
	for i: int in range(plan.sector_gates.size()):
		var gate_a: SectorGatePlanner.SectorGate = plan.sector_gates[i]
		if not gate_a.has_shortcut or gate_a.shortcut_corridor_rects.is_empty():
			continue
		for j: int in range(i + 1, plan.sector_gates.size()):
			var gate_b: SectorGatePlanner.SectorGate = plan.sector_gates[j]
			if not gate_b.has_shortcut or gate_b.shortcut_corridor_rects.is_empty():
				continue
			var pair_label: String = "%s+%s" % [_color_name(gate_a.color), _color_name(gate_b.color)]
			_compare_shortcut_rects(gate_a, gate_b, pair_label, direct_overlaps, margin_overlaps)
			_compare_shortcut_diffs(gate_a, gate_b, pair_label, diff_collisions)


static func _compare_shortcut_rects(
	gate_a: SectorGatePlanner.SectorGate,
	gate_b: SectorGatePlanner.SectorGate,
	pair_label: String,
	direct_overlaps: Array[Dictionary],
	margin_overlaps: Array[Dictionary],
) -> void:
	for ra: Rect2i in gate_a.shortcut_corridor_rects:
		for rb: Rect2i in gate_b.shortcut_corridor_rects:
			if ra.intersects(rb):
				(
					direct_overlaps
					. append(
						{
							&"pair": pair_label,
							&"rect_a": str(ra),
							&"rect_b": str(rb),
							&"intersection": str(ra.intersection(rb)),
						}
					)
				)
			elif ra.grow(1).intersects(rb):
				(
					margin_overlaps
					. append(
						{
							&"pair": pair_label,
							&"rect_a": str(ra),
							&"rect_b": str(rb),
						}
					)
				)


static func _compare_shortcut_diffs(
	gate_a: SectorGatePlanner.SectorGate,
	gate_b: SectorGatePlanner.SectorGate,
	pair_label: String,
	diff_collisions: Array[Dictionary],
) -> void:
	var walk_a: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in gate_a.tunnel_walkable:
		walk_a[cell] = true
	var wall_a: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in gate_a.tunnel_walls:
		wall_a[cell] = true
	var walk_b: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in gate_b.tunnel_walkable:
		walk_b[cell] = true
	var wall_b: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in gate_b.tunnel_walls:
		wall_b[cell] = true

	var wall_blocks_walkable: int = 0
	for cell: Vector2i in gate_b.tunnel_walls:
		if walk_a.has(cell):
			wall_blocks_walkable += 1
	for cell: Vector2i in gate_a.tunnel_walls:
		if walk_b.has(cell):
			wall_blocks_walkable += 1

	var erased_other_wall: int = 0
	for cell: Vector2i in gate_b.tunnel_erased_walls:
		if wall_a.has(cell):
			erased_other_wall += 1
	for cell: Vector2i in gate_a.tunnel_erased_walls:
		if wall_b.has(cell):
			erased_other_wall += 1

	if wall_blocks_walkable > 0 or erased_other_wall > 0:
		(
			diff_collisions
			. append(
				{
					&"pair": pair_label,
					&"wall_blocks_walkable": wall_blocks_walkable,
					&"erased_other_wall": erased_other_wall,
				}
			)
		)


static func _build_grid_from_baked_chunks(
	plan: WorldPlan,
	floors: Dictionary[Vector2i, bool],
	walls: Dictionary[Vector2i, bool],
	walkable: Dictionary[Vector2i, bool],
) -> void:
	for data: Dictionary in plan.baked_chunks.values():
		var c_floors: Array[Vector2i] = data[&"floors"]
		for fcell: Vector2i in c_floors:
			floors[fcell] = true
		var c_walls: Array[Vector2i] = data[&"walls"]
		for wcell: Vector2i in c_walls:
			walls[wcell] = true
		var c_walk: Array[Vector2i] = data[&"walkable"]
		for kcell: Vector2i in c_walk:
			walkable[kcell] = true


static func _is_passable(
	cell: Vector2i,
	walkable: Dictionary[Vector2i, bool],
	walls: Dictionary[Vector2i, bool],
	unlocked_door_cells: Dictionary[Vector2i, bool],
) -> bool:
	return walkable.has(cell) and (not walls.has(cell) or unlocked_door_cells.has(cell))


static func _simulate_progression(
	plan: WorldPlan,
	floors: Dictionary[Vector2i, bool],
	walls: Dictionary[Vector2i, bool],
	walkable: Dictionary[Vector2i, bool],
	unlocked_door_cells: Dictionary[Vector2i, bool],
	collected_keys: Dictionary[WorldPlan.KeyColor, bool],
	opened_shortcuts: Dictionary[int, bool],
	unlocked_doors: Dictionary[int, bool],
	visited: Dictionary[Vector2i, bool],
) -> bool:
	var start_cell: Vector2i = plan.hero_room.get_center()
	if not _is_passable(start_cell, walkable, walls, unlocked_door_cells):
		return true

	visited[start_cell] = true
	var queue: Array[Vector2i] = [start_cell]
	var head: int = 0
	var progress: bool = true

	while progress:
		progress = false
		while head < queue.size():
			var cur: Vector2i = queue[head]
			head += 1
			for dir: Vector2i in CARDINAL_DIRS:
				var nb: Vector2i = cur + dir
				if not visited.has(nb) and _is_passable(nb, walkable, walls, unlocked_door_cells):
					visited[nb] = true
					queue.append(nb)
					progress = true

		for gate_idx: int in range(plan.sector_gates.size()):
			var gate: SectorGatePlanner.SectorGate = plan.sector_gates[gate_idx]
			if gate.has_key and not collected_keys.has(gate.color) and visited.has(gate.key_cell):
				collected_keys[gate.color] = true
				progress = true

			if gate.has_shortcut and not opened_shortcuts.has(gate_idx) and visited.has(gate.lever_cell):
				opened_shortcuts[gate_idx] = true
				progress = true
				_apply_shortcut_diffs_to_grid(gate, floors, walls, walkable)
				for wcell: Vector2i in gate.tunnel_walkable:
					_try_enqueue_adjacent_visited(wcell, walkable, walls, unlocked_door_cells, visited, queue)
				for scell: Vector2i in gate.shortcut_wall_cells:
					_try_enqueue_adjacent_visited(scell, walkable, walls, unlocked_door_cells, visited, queue)

			if not unlocked_doors.has(gate_idx) and collected_keys.has(gate.color) and gate.door_cells.size() >= 2:
				var left_cell: Vector2i = gate.door_cells[0]
				var right_cell: Vector2i = gate.door_cells[1]
				if _has_visited_neighbor(left_cell, visited) or _has_visited_neighbor(right_cell, visited):
					unlocked_doors[gate_idx] = true
					progress = true
					var top_left: Vector2i = left_cell + Vector2i(0, -1)
					var top_right: Vector2i = right_cell + Vector2i(0, -1)
					for dcell: Vector2i in [left_cell, right_cell, top_left, top_right]:
						unlocked_door_cells[dcell] = true
						walkable[dcell] = true
						if not visited.has(dcell):
							visited[dcell] = true
							queue.append(dcell)

	return false


static func _apply_shortcut_diffs_to_grid(
	gate: SectorGatePlanner.SectorGate,
	floors: Dictionary[Vector2i, bool],
	walls: Dictionary[Vector2i, bool],
	walkable: Dictionary[Vector2i, bool],
) -> void:
	for diff_var: Variant in gate.tunnel_chunk_diffs.values():
		var diff: Dictionary = diff_var
		var chunk_erased: Dictionary[Vector2i, bool] = diff[&"erased_walls"]
		for ecell: Vector2i in chunk_erased:
			walls.erase(ecell)
		var chunk_floors: Array[Vector2i] = diff[&"floors"]
		for fcell: Vector2i in chunk_floors:
			floors[fcell] = true
		var chunk_walls: Array[Vector2i] = diff[&"walls"]
		for wcell: Vector2i in chunk_walls:
			walls[wcell] = true
		var chunk_walk: Array[Vector2i] = diff[&"walkable"]
		for kcell: Vector2i in chunk_walk:
			walkable[kcell] = true


static func _try_enqueue_adjacent_visited(
	cell: Vector2i,
	walkable: Dictionary[Vector2i, bool],
	walls: Dictionary[Vector2i, bool],
	unlocked_door_cells: Dictionary[Vector2i, bool],
	visited: Dictionary[Vector2i, bool],
	queue: Array[Vector2i],
) -> void:
	if visited.has(cell):
		return
	if not _is_passable(cell, walkable, walls, unlocked_door_cells):
		return
	if _has_visited_neighbor(cell, visited):
		visited[cell] = true
		queue.append(cell)


static func _has_visited_neighbor(cell: Vector2i, visited: Dictionary[Vector2i, bool]) -> bool:
	for dir: Vector2i in CARDINAL_DIRS:
		if visited.has(cell + dir):
			return true
	return false


static func _count_unreachable_rooms(plan: WorldPlan, visited: Dictionary[Vector2i, bool]) -> int:
	var unreachable: int = 0
	for room: Rect2i in plan.rooms:
		if visited.has(room.get_center()):
			continue
		var reached: bool = false
		for y: int in range(room.position.y, room.end.y):
			for x: int in range(room.position.x, room.end.x):
				if visited.has(Vector2i(x, y)):
					reached = true
					break
			if reached:
				break
		if not reached:
			unreachable += 1
	return unreachable


static func _collect_gate_progression_failures(
	plan: WorldPlan,
	collected_keys: Dictionary[WorldPlan.KeyColor, bool],
	unlocked_doors: Dictionary[int, bool],
	opened_shortcuts: Dictionary[int, bool],
	uncollected_keys: Array[String],
	locked_doors: Array[String],
	unopened_shortcuts: Array[String],
) -> void:
	for gate_idx: int in range(plan.sector_gates.size()):
		var gate: SectorGatePlanner.SectorGate = plan.sector_gates[gate_idx]
		var cname: String = _color_name(gate.color)
		if gate.has_key and not collected_keys.has(gate.color):
			uncollected_keys.append(cname)
		if not unlocked_doors.has(gate_idx):
			locked_doors.append(cname)
		if gate.has_shortcut and not opened_shortcuts.has(gate_idx):
			unopened_shortcuts.append(cname)


static func _find_broken_shortcuts(
	plan: WorldPlan,
	opened_shortcuts: Dictionary[int, bool],
	walkable: Dictionary[Vector2i, bool],
	walls: Dictionary[Vector2i, bool],
	unlocked_door_cells: Dictionary[Vector2i, bool],
) -> Array[String]:
	var broken: Array[String] = []
	for gate_idx: int in range(plan.sector_gates.size()):
		var gate: SectorGatePlanner.SectorGate = plan.sector_gates[gate_idx]
		if (
			not opened_shortcuts.has(gate_idx)
			or not gate.has_shortcut
			or gate.key_room == gate.shortcut_target_room
			or gate.shortcut_corridor_rects.is_empty()
			or gate.shortcut_wall_cells.is_empty()
			or gate.shortcut_waypoints.is_empty()
		):
			continue
		if not _is_shortcut_tunnel_traversable(gate, walkable, walls, unlocked_door_cells):
			broken.append(_color_name(gate.color))
	return broken


static func _is_shortcut_tunnel_traversable(
	gate: SectorGatePlanner.SectorGate,
	walkable: Dictionary[Vector2i, bool],
	walls: Dictionary[Vector2i, bool],
	unlocked_door_cells: Dictionary[Vector2i, bool],
) -> bool:
	var padded_rects: Array[Rect2i] = []
	for r: Rect2i in gate.shortcut_corridor_rects:
		padded_rects.append(r.grow(1))

	var target_cell: Vector2i = gate.shortcut_waypoints[gate.shortcut_waypoints.size() - 1]
	var t_visited: Dictionary[Vector2i, bool] = {}
	var t_queue: Array[Vector2i] = []
	for sw_cell: Vector2i in gate.shortcut_wall_cells:
		var start_t: Vector2i = sw_cell + Vector2i(0, 1)
		if _is_passable(start_t, walkable, walls, unlocked_door_cells) and _in_any_rect(start_t, padded_rects):
			t_visited[start_t] = true
			t_queue.append(start_t)

	var head: int = 0
	while head < t_queue.size():
		var cur: Vector2i = t_queue[head]
		head += 1
		if cur == target_cell or cur == gate.gate_entry_cell:
			return true
		for dir: Vector2i in CARDINAL_DIRS:
			var nb: Vector2i = cur + dir
			if not t_visited.has(nb) and _in_any_rect(nb, padded_rects) and _is_passable(nb, walkable, walls, unlocked_door_cells):
				t_visited[nb] = true
				t_queue.append(nb)

	return false


static func _in_any_rect(cell: Vector2i, rects: Array[Rect2i]) -> bool:
	for r: Rect2i in rects:
		if r.has_point(cell):
			return true
	return false


static func _count_wall_on_walkable(
	walkable: Dictionary[Vector2i, bool],
	walls: Dictionary[Vector2i, bool],
	unlocked_door_cells: Dictionary[Vector2i, bool],
	samples: Array[String],
) -> int:
	var count: int = 0
	for cell: Vector2i in walkable:
		if walls.has(cell) and not unlocked_door_cells.has(cell):
			count += 1
			if samples.size() < MAX_SAMPLES:
				samples.append(str(cell))
	return count


static func _count_wall_holes(
	walkable: Dictionary[Vector2i, bool],
	walls: Dictionary[Vector2i, bool],
	samples: Array[String],
) -> int:
	var count: int = 0
	for cell: Vector2i in walkable:
		if walls.has(cell):
			continue
		for dir: Vector2i in CARDINAL_DIRS:
			var nb: Vector2i = cell + dir
			if not walkable.has(nb) and not walls.has(nb):
				count += 1
				if samples.size() < MAX_SAMPLES:
					samples.append(str(nb))
	return count


static func _format_pair_list(entries: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for item: Dictionary in entries:
		var pair_str: String = item[&"pair"]
		if not parts.has(pair_str):
			parts.append(pair_str)
	return "[%s]" % ", ".join(parts)


static func _format_diff_list(entries: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for item: Dictionary in entries:
		parts.append("%s(w=%d,e=%d)" % [item[&"pair"], item[&"wall_blocks_walkable"], item[&"erased_other_wall"]])
	return "[%s]" % ", ".join(parts)
