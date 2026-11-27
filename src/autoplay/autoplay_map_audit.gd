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

	var solvability_ok: bool = SectorGatePlanner.verify_solvability(plan)

	var shortcut_direct_overlaps: Array[Dictionary] = []
	var shortcut_margin_overlaps: Array[Dictionary] = []
	_check_shortcut_overlaps(plan, shortcut_direct_overlaps, shortcut_margin_overlaps)

	var floors: Dictionary[Vector2i, bool] = {}
	var walls: Dictionary[Vector2i, bool] = {}
	var walkable: Dictionary[Vector2i, bool] = {}
	_build_grid_from_baked_chunks(plan, floors, walls, walkable)

	var unlocked_door_cells: Dictionary[Vector2i, bool] = {}
	var collected_keys: Dictionary[WorldPlan.KeyColor, bool] = {}
	var opened_shortcuts: Dictionary[int, bool] = {}
	var unlocked_doors: Dictionary[int, bool] = {}
	var visited: Dictionary[Vector2i, bool] = {}
	var sequence_breaks: Array[String] = []
	var hero_spawn_blocked: bool = _simulate_progression(
		plan,
		walls,
		walkable,
		unlocked_door_cells,
		collected_keys,
		opened_shortcuts,
		unlocked_doors,
		visited,
		sequence_breaks,
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
	var wall_hole_count: int = _count_wall_holes(plan, walkable, walls, wall_hole_samples)

	var elapsed_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	var shortcuts_count: int = plan.local_shortcuts.size()

	var passed: bool = (
		solvability_ok
		and not hero_spawn_blocked
		and unreachable_rooms == 0
		and uncollected_keys.is_empty()
		and locked_doors.is_empty()
		and unopened_shortcuts.is_empty()
		and sequence_breaks.is_empty()
		and shortcut_direct_overlaps.is_empty()
		and shortcut_margin_overlaps.is_empty()
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
		&"sequence_breaks": sequence_breaks,
		&"shortcut_direct_overlaps": shortcut_direct_overlaps,
		&"shortcut_margin_overlaps": shortcut_margin_overlaps,
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
	var seq_breaks: Array[String] = res[&"sequence_breaks"]
	if not seq_breaks.is_empty():
		tags.append("sequence_breaks=[%s]" % ", ".join(seq_breaks))

	var direct_ov: Array[Dictionary] = res[&"shortcut_direct_overlaps"]
	if not direct_ov.is_empty():
		tags.append("direct_overlaps=%s" % _format_pair_list(direct_ov))
	var margin_ov: Array[Dictionary] = res[&"shortcut_margin_overlaps"]
	if not margin_ov.is_empty():
		tags.append("margin_overlaps=%s" % _format_pair_list(margin_ov))

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
			&"Gates: %d  Local Shortcuts Created: %d (avg %.1f/seed)"
			% [
				summary[&"total_gates"],
				summary[&"total_shortcuts"],
				summary[&"avg_shortcuts_per_seed"],
			]
		)
	)
	var counts: Dictionary = summary[&"failure_counts"]
	print(&"Failure Breakdown:")
	print(&"  shortcut_direct_overlaps : %d" % counts[&"shortcut_direct_overlaps"])
	print(&"  shortcut_margin_overlaps : %d" % counts[&"shortcut_margin_overlaps"])
	print(&"  wall_on_walkable         : %d" % counts[&"wall_on_walkable"])
	print(&"  wall_holes               : %d" % counts[&"wall_holes"])
	print(&"  broken_shortcuts         : %d" % counts[&"broken_shortcuts"])
	print(&"  unreachable_rooms        : %d" % counts[&"unreachable_rooms"])
	print(&"  locked_doors             : %d" % counts[&"locked_doors"])
	print(&"  uncollected_keys         : %d" % counts[&"uncollected_keys"])
	print(&"  unopened_shortcuts       : %d" % counts[&"unopened_shortcuts"])
	print(&"  sequence_breaks          : %d" % counts[&"sequence_breaks"])
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
		&"wall_on_walkable": 0,
		&"wall_holes": 0,
		&"broken_shortcuts": 0,
		&"unreachable_rooms": 0,
		&"locked_doors": 0,
		&"uncollected_keys": 0,
		&"unopened_shortcuts": 0,
		&"sequence_breaks": 0,
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
		if not res[&"sequence_breaks"].is_empty():
			counts[&"sequence_breaks"] += 1
		if not res[&"solvability_ok"]:
			counts[&"solvability_failed"] += 1
		if res[&"hero_spawn_blocked"]:
			counts[&"hero_spawn_blocked"] += 1

	var avg_shortcuts: float = float(total_shortcuts) / float(maxi(1, total))
	return {
		&"total_seeds": total,
		&"passed_seeds": passed_count,
		&"failed_seeds": total - passed_count,
		&"total_elapsed_ms": total_ms,
		&"avg_elapsed_ms": total_ms / float(maxi(1, total)),
		&"total_gates": total_gates,
		&"total_shortcuts": total_shortcuts,
		&"avg_shortcuts_per_seed": avg_shortcuts,
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
) -> void:
	for i: int in range(plan.local_shortcuts.size()):
		var sc_a: ShortcutTunnelPlanner.LocalShortcut = plan.local_shortcuts[i]
		for j: int in range(i + 1, plan.local_shortcuts.size()):
			var sc_b: ShortcutTunnelPlanner.LocalShortcut = plan.local_shortcuts[j]
			var pair_label: String = "S%d+S%d" % [sc_a.id, sc_b.id]
			var ra: Rect2i = sc_a.corridor_rect
			var rb: Rect2i = sc_b.corridor_rect
			if ra.intersects(rb):
				direct_overlaps.append({&"pair": pair_label, &"rect_a": str(ra), &"rect_b": str(rb)})
			elif ra.grow(1).intersects(rb):
				margin_overlaps.append({&"pair": pair_label, &"rect_a": str(ra), &"rect_b": str(rb)})


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
	walls: Dictionary[Vector2i, bool],
	walkable: Dictionary[Vector2i, bool],
	unlocked_door_cells: Dictionary[Vector2i, bool],
	collected_keys: Dictionary[WorldPlan.KeyColor, bool],
	opened_shortcuts: Dictionary[int, bool],
	unlocked_doors: Dictionary[int, bool],
	visited: Dictionary[Vector2i, bool],
	sequence_breaks: Array[String],
) -> bool:
	var start_cell: Vector2i = plan.hero_room.get_center()
	if not _is_passable(start_cell, walkable, walls, unlocked_door_cells):
		return true

	var unlocked_sectors: Dictionary[int, bool] = {0: true}
	var seq_seen: Dictionary[int, bool] = {}
	visited[start_cell] = true
	var queue: Array[Vector2i] = [start_cell]
	var head: int = 0
	var progress: bool = true

	while progress:
		progress = false
		while head < queue.size():
			var cur: Vector2i = queue[head]
			head += 1
			var cur_room: Rect2i = plan.get_room_at(cur)
			if cur_room.size != Vector2i.ZERO:
				var cur_sec: int = plan._room_sectors.get(cur_room, 0)
				if cur_sec > 0 and not unlocked_sectors.has(cur_sec) and not seq_seen.has(cur_sec):
					seq_seen[cur_sec] = true
					sequence_breaks.append("S%d@%s" % [cur_sec, str(cur)])
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

			if not unlocked_doors.has(gate_idx) and collected_keys.has(gate.color) and gate.door_cells.size() >= 2:
				var cell_a: Vector2i = gate.door_cells[0]
				var cell_b: Vector2i = gate.door_cells[1]
				if _has_visited_neighbor(cell_a, visited) or _has_visited_neighbor(cell_b, visited):
					unlocked_doors[gate_idx] = true
					var next_sec: int = plan._room_sectors.get(gate.next_room, -1)
					if next_sec > 0:
						unlocked_sectors[next_sec] = true
					progress = true
					var is_horiz_door: bool = gate.door_face == RoomLayout.Face.NORTH or gate.door_face == RoomLayout.Face.SOUTH
					_unlock_door_cells_in_sim(cell_a, cell_b, is_horiz_door, walls, walkable, unlocked_door_cells, visited, queue)

		for sc_idx: int in range(plan.local_shortcuts.size()):
			var sc: ShortcutTunnelPlanner.LocalShortcut = plan.local_shortcuts[sc_idx]
			if not opened_shortcuts.has(sc_idx) and visited.has(sc.lever_cell) and sc.door_cells.size() >= 2:
				opened_shortcuts[sc_idx] = true
				progress = true
				for dcell: Vector2i in sc.door_cells:
					unlocked_door_cells[dcell] = true
					walkable[dcell] = true
					if not visited.has(dcell):
						visited[dcell] = true
						queue.append(dcell)

	return false


static func _unlock_door_cells_in_sim(
	cell_a: Vector2i,
	cell_b: Vector2i,
	is_horiz_door: bool,
	walls: Dictionary[Vector2i, bool],
	walkable: Dictionary[Vector2i, bool],
	unlocked_door_cells: Dictionary[Vector2i, bool],
	visited: Dictionary[Vector2i, bool],
	queue: Array[Vector2i],
) -> void:
	var cells: Array[Vector2i] = [cell_a, cell_b]
	if is_horiz_door:
		cells.append(cell_a + Vector2i(0, -1))
		cells.append(cell_b + Vector2i(0, -1))
	for dcell: Vector2i in cells:
		unlocked_door_cells[dcell] = true
		if not is_horiz_door:
			walls.erase(dcell)
		walkable[dcell] = true
		if not visited.has(dcell):
			visited[dcell] = true
			queue.append(dcell)


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
	for sc_idx: int in range(plan.local_shortcuts.size()):
		if not opened_shortcuts.has(sc_idx):
			unopened_shortcuts.append("S%d" % plan.local_shortcuts[sc_idx].id)


static func _find_broken_shortcuts(
	plan: WorldPlan,
	opened_shortcuts: Dictionary[int, bool],
	walkable: Dictionary[Vector2i, bool],
	walls: Dictionary[Vector2i, bool],
	unlocked_door_cells: Dictionary[Vector2i, bool],
) -> Array[String]:
	var broken: Array[String] = []
	for sc_idx: int in range(plan.local_shortcuts.size()):
		var sc: ShortcutTunnelPlanner.LocalShortcut = plan.local_shortcuts[sc_idx]
		if not opened_shortcuts.has(sc_idx):
			continue
		if sc.lever_cell.distance_squared_to(sc.door_cells[0]) > 36:
			broken.append("S%d(lever_far)" % sc.id)
		elif not _is_local_shortcut_traversable(sc, walkable, walls, unlocked_door_cells):
			broken.append("S%d" % sc.id)
	return broken


static func _is_local_shortcut_traversable(
	sc: ShortcutTunnelPlanner.LocalShortcut,
	walkable: Dictionary[Vector2i, bool],
	walls: Dictionary[Vector2i, bool],
	unlocked_door_cells: Dictionary[Vector2i, bool],
) -> bool:
	var near_overlap: Rect2i = sc.corridor_rect.intersection(sc.room_near)
	var far_overlap: Rect2i = sc.corridor_rect.intersection(sc.room_far)
	var visited: Dictionary[Vector2i, bool] = {}
	var queue: Array[Vector2i] = []

	for cy: int in range(near_overlap.position.y, near_overlap.end.y):
		for cx: int in range(near_overlap.position.x, near_overlap.end.x):
			var cell: Vector2i = Vector2i(cx, cy)
			if _is_passable(cell, walkable, walls, unlocked_door_cells):
				visited[cell] = true
				queue.append(cell)

	var head: int = 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if far_overlap.has_point(cur):
			return true
		for dir: Vector2i in CARDINAL_DIRS:
			var nb: Vector2i = cur + dir
			if not visited.has(nb) and sc.corridor_rect.has_point(nb) and _is_passable(nb, walkable, walls, unlocked_door_cells):
				visited[nb] = true
				queue.append(nb)
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
	plan: WorldPlan,
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
			if not walkable.has(nb) and not walls.has(nb) and not plan.shortcut_blocker_cells.has(nb):
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
